------------------------------------------------------------
-- harness.lua: assertions and addon loading for the tests.
--
--     dofile("tests/wow_stubs.lua")
--     local H = dofile("tests/harness.lua")
--     H.loadAddon()
--     H.check(cond, "message")
--     H.done("test_name")
------------------------------------------------------------

local H = {}
local passed, failed = 0, 0

function H.check(cond, msg)
    if cond then
        passed = passed + 1
    else
        failed = failed + 1
        io.stderr:write("FAIL: " .. tostring(msg) .. "\n")
    end
end

function H.eq(actual, expected, msg)
    H.check(actual == expected, (msg or "") .. " (expected " .. tostring(expected)
            .. ", got " .. tostring(actual) .. ")")
end

function H.done(name)
    if failed > 0 then
        io.stderr:write(name .. ": " .. failed .. " failed, " .. passed .. " passed\n")
        os.exit(1)
    end
    io.write(name .. ": " .. passed .. " tests passed\n")
end

-- The files the TOC lists, in load order.
function H.tocFiles()
    local files = {}
    for line in io.lines("Apotheca.toc") do
        line = line:gsub("\r", "")
        if line ~= "" and not line:match("^#") then files[#files + 1] = line end
    end
    return files
end

-- Load every TOC file in order, then run the client's login sequence.
function H.loadAddon(opts)
    opts = opts or {}
    local files = H.tocFiles()
    -- The dev-only probe addon loads after Apotheca, as its TOC requires.
    if opts.probe then files[#files + 1] = "Tools/ApothecaProbe/ApothecaProbe.lua" end
    for _, f in ipairs(files) do
        local chunk, err = loadfile(f)
        if not chunk then error(err) end
        chunk()
    end
    if opts.savedDB then rawset(_G, "ApothecaDB", opts.savedDB) end
    WoW.fire("ADDON_LOADED", "Apotheca")
    if opts.probe then WoW.fire("ADDON_LOADED", "ApothecaProbe") end
    WoW.fire("PLAYER_LOGIN")
    WoW.fire("PLAYER_ENTERING_WORLD")
    WoW.tick(1)
    WoW.tick(1)
    return Apotheca
end

-- Frames created from a template, by template name.
function H.framesWithTemplate(template)
    local out = {}
    for _, f in ipairs(WoW.frames) do
        if f._template == template then out[#out + 1] = f end
    end
    return out
end

function H.messagesMatching(pattern)
    local n = 0
    for _, m in ipairs(WoW.messages) do if m:find(pattern) then n = n + 1 end end
    return n
end

return H
