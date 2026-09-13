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
