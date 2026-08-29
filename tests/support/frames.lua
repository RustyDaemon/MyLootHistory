--[[
Just enough of the WoW widget API to build the report window outside the game and then
click on it.

The report is the one part of the addon that used to be untestable: it was widget
construction, and widget construction needs a client. It does not need a *real* client
though - it needs frames that remember their size, their scripts and their children. That
is all this is.

Two rules make it small enough to trust:

  * Unknown methods are no-ops that return the widget, so only the ones whose return value
    the addon actually reads have to be written out.
  * Only PascalCase keys are synthesised. Widget methods are PascalCase and the fields the
    addon hangs on a frame (`row.entry`, `bar.fill`) are not, so reading an unset field
    still answers nil - otherwise `if frame.entry then` would be true for every frame.

`Fire` is the point of the whole thing: it runs the handlers a script has, the way the
client would, so a spec can click a header or scroll a list and watch what happens.
--]]

local frames = {}

local widget = {}

local function noop(self) return self end

local widgetMeta = {
    __index = function(self, key)
        if (widget[key]) then return widget[key] end

        if (key:sub(1, 1):upper() ~= key:sub(1, 1)) then return nil end

        -- anything not modelled is a setter: remember that it was called, do nothing
        local fn = function(s)
            s.calls[key] = (s.calls[key] or 0) + 1

            return s
        end

        rawset(self, key, fn)

        return fn
    end,
}

local function newWidget(kind, name, parent)
    local self = setmetatable({
        kind = kind,
        name = name,
        parent = parent,
        calls = {},
        scripts = {},
        children = {},
        points = {},
        shown = true,
        alpha = 1,
        width = 100,
        height = 20,
        text = "",
    }, widgetMeta)

    if (parent and parent.children) then
        parent.children[#parent.children + 1] = self
    end

    frames.all[#frames.all + 1] = self

    return self
end

frames.all = {}

-- ── sizing and visibility ─────────────────────────────────────────────────────

function widget:SetWidth(w) self.width = w return self end
function widget:SetHeight(h) self.height = h return self end
function widget:SetSize(w, h) self.width, self.height = w, h return self end
function widget:GetWidth() return self.width end
function widget:GetHeight() return self.height end
function widget:GetSize() return self.width, self.height end
function widget:GetEffectiveScale() return 1 end
function widget:GetScale() return 1 end
function widget:GetFrameLevel() return 5 end
function widget:GetFrameStrata() return "HIGH" end

function widget:Show() self.shown = true self:Fire("OnShow") return self end
function widget:Hide() self.shown = false self:Fire("OnHide") return self end
function widget:SetShown(value) if (value) then self:Show() else self:Hide() end return self end
function widget:IsShown() return self.shown end
function widget:IsVisible() return self.shown end

function widget:SetAlpha(a) self.alpha = a return self end
function widget:GetAlpha() return self.alpha end

function widget:SetPoint(point, ...)
    self.points[#self.points + 1] = { point, ... }

    return self
end

function widget:ClearAllPoints() self.points = {} return self end
function widget:SetAllPoints() return self end
function widget:GetPoint() return "CENTER", nil, "CENTER", 0, 0 end
function widget:GetParent() return self.parent end
function widget:GetNumPoints() return #self.points end

-- ── scripts ───────────────────────────────────────────────────────────────────

function widget:SetScript(name, handler)
    self.scripts[name] = { handler }

    return self
end

function widget:HookScript(name, handler)
    self.scripts[name] = self.scripts[name] or {}
    table.insert(self.scripts[name], handler)

    return self
end

function widget:GetScript(name)
    return self.scripts[name] and self.scripts[name][1]
end

-- Runs every handler registered for a script, the way the client would.
function widget:Fire(name, ...)
    local handlers = self.scripts[name]

    if (not handlers) then return end

    for i = 1, #handlers do
        handlers[i](self, ...)
    end
end

function widget:Click(...)
    self:Fire("OnClick", ...)

    return self
end

-- ── text ──────────────────────────────────────────────────────────────────────

function widget:SetText(value) self.text = value ~= nil and tostring(value) or "" return self end
function widget:GetText() return self.text end
function widget:SetFormattedText(fmt, ...) self.text = string.format(fmt, ...) return self end
function widget:GetStringWidth() return #self.text * 6 end
function widget:GetStringHeight() return 12 end
function widget:GetFont() return "Fonts\\FRIZQT__.TTF", 12, "" end

function widget:SetFont(path, size, flags)
    assert(type(path) == "string", "SetFont wants a font path")
    assert(type(size) == "number", "SetFont wants a size")
    -- the client rejects a nil third argument outright, so nothing here may pass one
    assert(type(flags) == "string", "SetFont wants flags as a string, got "..type(flags))

    return self
end

-- `UI:rgb` returns four values, and putting that call anywhere but last in an argument
-- list - or inside an `and`/`or` - silently truncates it to the red channel. Checking all
-- three channels here is what turns that into a test failure instead of a live error.
function widget:SetTextColor(r, g, b)
    assert(type(r) == "number" and type(g) == "number" and type(b) == "number",
        "SetTextColor wants three numbers, got "
        ..tostring(r)..", "..tostring(g)..", "..tostring(b))

    return self
end

-- ── children ──────────────────────────────────────────────────────────────────

function widget:CreateTexture(name)
    return newWidget("Texture", name, self)
end

function widget:CreateFontString(name)
    return newWidget("FontString", name, self)
end

function widget:CreateAnimationGroup()
    local group = newWidget("AnimationGroup", nil, self)

    group.CreateAnimation = function(g) return newWidget("Animation", nil, g) end
    group.Play = function(g) g.played = (g.played or 0) + 1 return g end
    group.Stop = noop

    return group
end

function widget:SetGradient(orientation, from, to)
    assert(orientation == "HORIZONTAL" or orientation == "VERTICAL",
        "bad gradient orientation: "..tostring(orientation))
    assert(type(from) == "table" and type(to) == "table", "SetGradient wants two colours")

    return self
end

function widget:SetColorTexture(r, g, b)
    assert(type(r) == "number" and type(g) == "number" and type(b) == "number",
        "SetColorTexture wants three numbers, got "
        ..tostring(r)..", "..tostring(g)..", "..tostring(b))

    return self
end

function widget:SetTexture(value)
    assert(value ~= nil, "SetTexture(nil)")

    return self
end

function widget:SetVertexColor(r, g, b)
    assert(type(r) == "number" and type(g) == "number" and type(b) == "number",
        "SetVertexColor wants three numbers, got "
        ..tostring(r)..", "..tostring(g)..", "..tostring(b))

    return self
end

function widget:SetScrollChild(child) self.scrollChild = child return self end

-- ── globals ───────────────────────────────────────────────────────────────────

-- Installs the widget API into _G. Call once, before loading the UI modules.
function frames.install()
    _G.UIParent = newWidget("Frame", "UIParent")
    _G.UIParent:SetSize(1920, 1080)

    _G.CreateFrame = function(kind, name, parent)
        local frame = newWidget(kind, name, parent)

        if (name) then _G[name] = frame end

        return frame
    end

    _G.CreateColor = function(r, g, b, a) return { r = r, g = g, b = b, a = a } end

    local function fontObject()
        local font = newWidget("Font")

        font.GetFont = function() return "Fonts\\FRIZQT__.TTF", 12, "" end

        return font
    end

    _G.GameFontNormal = fontObject()
    _G.NumberFontNormal = fontObject()

    _G.PlaySound = function() end
    _G.SOUNDKIT = setmetatable({}, { __index = function() return 1 end })
    _G.GetCursorPosition = function() return 0, 0 end
    _G.UnitName = function() return "Testchar" end
    _G.GetRealmName = function() return "Testrealm" end
    _G.IsLeftShiftKeyDown = function() return frames.shiftDown == true end
    _G.IsRightShiftKeyDown = function() return false end

    _G.ChatEdit_TryInsertChatLink = function(link)
        assert(link ~= nil, "tried to link a nil")

        frames.lastLink = link
    end

    _G.UISpecialFrames = {}
    _G.tinsert = table.insert

    _G.tContains = function(list, value)
        for i = 1, #list do
            if (list[i] == value) then return true end
        end

        return false
    end

    -- the report defers its first re-layout by a frame; here "next frame" is "now"
    _G.C_Timer.After = function(_, fn) fn() end

    local tooltip = newWidget("GameTooltip", "GameTooltip")

    tooltip.SetOwner = noop
    -- AddLine(text, r, g, b, wrap): a colour has to arrive as three numbers, which is the
    -- same truncation trap as SetTextColor when `UI:rgb` is not the last argument
    tooltip.AddLine = function(self, _, r, g, b)
        if (r ~= nil) then
            assert(type(r) == "number" and type(g) == "number" and type(b) == "number",
                "AddLine wants three colour numbers, got "
                ..tostring(r)..", "..tostring(g)..", "..tostring(b))
        end

        return self
    end

    tooltip.SetHyperlink = function(self, link)
        assert(link ~= nil, "GameTooltip:SetHyperlink(nil)")

        return self
    end

    tooltip.SetItemByID = function(self, id)
        assert(type(id) == "number", "SetItemByID wants an id, got "..tostring(id))

        return self
    end

    tooltip.SetCurrencyByID = function(self, id)
        assert(type(id) == "number", "SetCurrencyByID wants an id, got "..tostring(id))

        return self
    end

    _G.GameTooltip = tooltip

    return frames
end

-- The first real Button among a frame's children. Textures and font strings are children
-- too, so a spec cannot just take children[1].
function frames.firstButton(frame)
    for i = 1, #frame.children do
        if (frame.children[i].kind == "Button") then return frame.children[i] end
    end
end

-- Every pooled list row currently showing an entry of the given kind.
function frames.rowsOfKind(kind)
    local found = {}

    for i = 1, #frames.all do
        local frame = frames.all[i]

        if (frame.entry and (kind == nil or frame.entry.kind == kind)) then
            found[#found + 1] = frame
        end
    end

    return found
end

return frames
