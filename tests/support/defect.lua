--[[
`defect` describes a behaviour that is wrong today and known to be wrong.

busted has `pending`, but a pending test never runs, so it cannot tell you when
the bug goes away - and a bug that has been quietly fixed is worth knowing about.
This runs the body and expects it to fail: the suite stays green while the defect
stands, and turns red the moment the behaviour is corrected, at which point the
test should be rewritten as an ordinary `it`.

    local defect = require("tests.support.defect")(it)

    defect("the range drops loot when it spans New Year", function()
        assert.is_true(...)   -- what it *should* do
    end)

`it` has to be handed in: busted puts it in the spec file's own environment
rather than in _G, so a required module cannot reach it on its own.
--]]

return function(it)
    return function(name, body)
        it(name.." [known defect]", function()
            local ok = pcall(body)

            if (ok) then
                error("this known defect now passes - promote it from defect() to it() "
                    .."and describe the fixed behaviour", 2)
            end
        end)
    end
end
