local wow = require("tests.support.wow")

local function tocFiles()
    local root = os.getenv("MLH_ROOT") or "."
    local files = {}

    for raw in io.lines(root.."/MyLootHistory.toc") do
        local line = raw:gsub("\r$", ""):gsub("\\", "/")

        if (line ~= "" and not line:match("^#")) then files[#files+1] = line end
    end

    return files
end

describe("wow.loadOrder", function()
    it("follows the .toc order, so specs load files the way the client does", function()
        local toc = tocFiles()
        local position = {}

        for i = 1, #toc do position[toc[i]] = i end

        local previous = 0

        for i = 1, #wow.loadOrder do
            local path = wow.loadOrder[i]

            assert.is_not_nil(position[path], path.." is not in MyLootHistory.toc")
            assert.is_true(position[path] > previous, path.." is out of .toc order")

            previous = position[path]
        end
    end)
end)
