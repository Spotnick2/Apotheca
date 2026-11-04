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
    -- Every blocked secret operation is a taint.log line in game, even
    -- when a pcall catches it (wow_stubs.lua counts them).
    local stubs = rawget(_G, "WoW")
    if stubs and stubs.secretBlocked then
        H.eq(stubs.secretBlocked, 0, "no arithmetic or comparison was attempted on a secret")
    end
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

-- ForeverProbe, the probe's host (GUIDE.md section 8, as GlassChat's
-- harness): $FOREVERPROBE, else ../ForeverProbe. It is private and lives
-- on the owner's disk only, so CI sets FOREVERPROBE_OPTIONAL=1 and a probe
-- test file then exits cleanly, SKIPPED; locally a missing checkout fails.
function H.loadForeverProbe()
    local root = (os.getenv("FOREVERPROBE") or "../ForeverProbe"):gsub("\\", "/"):gsub("/$", "")
    local toc = io.open(root .. "/ForeverProbe.toc", "rb")
    if not toc then
        if os.getenv("FOREVERPROBE_OPTIONAL") == "1" then
            io.write("SKIPPED: ForeverProbe isn't here (private, local only); the probe tests run locally\n")
            os.exit(0)
        end
        error("ForeverProbe checkout not found at " .. root .. ": clone it there or set FOREVERPROBE", 0)
    end
    local files = {}
    for line in toc:read("*a"):gmatch("[^\r\n]+") do
        if line:match("%.lua$") and not line:match("^#") then files[#files + 1] = root .. "/" .. line end
    end
    toc:close()
    for _, file in ipairs(files) do assert(loadfile(file))("ForeverProbe", {}) end
    WoW.fire("ADDON_LOADED", "ForeverProbe")
    return ForeverProbe
end

local function loadFiles(files, name, ns)
    for _, f in ipairs(files) do
        local chunk, err = loadfile(f)
        if not chunk then error(err) end
        chunk(name, ns)
    end
end

-- Load every TOC file in order, then run the client's login sequence.
-- With opts.probe, the dev-only probe too, in the client's order: its host
-- ForeverProbe, then Apotheca, then ApothecaProbe, each addon's files and
-- then its ADDON_LOADED. H.probe is the probe's test seam (NS._test).
function H.loadAddon(opts)
    opts = opts or {}
    if opts.probe then H.loadForeverProbe() end
    loadFiles(H.tocFiles(), "Apotheca", {})
    if opts.savedDB then rawset(_G, "ApothecaDB", opts.savedDB) end
    WoW.fire("ADDON_LOADED", "Apotheca")
    if opts.probe then
        local ns = {}
        loadFiles({ "Tools/ApothecaProbe/ApothecaProbe.lua" }, "ApothecaProbe", ns)
        WoW.fire("ADDON_LOADED", "ApothecaProbe")
        H.probe = ns._test
    end
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

-- The probe's commands: /fp apo <cmd>. Chat and the console's session
-- lines start empty, so a test reads what this command said.
function H.fp(cmd)
    WoW.messages = {}
    ForeverProbe.lines = {}
    SlashCmdList.FOREVERPROBE("apo " .. cmd)
end

-- The probe's console lines (ForeverProbe.lines) matching a pattern.
function H.probeMatching(pattern)
    local n = 0
    for _, l in ipairs(ForeverProbe.lines) do
        if l.m == "ApothecaProbe" and l.text:find(pattern) then n = n + 1 end
    end
    return n
end

return H
