------------------------------------------------------------
-- harness.lua: addon loading for the tests (the assertions are WowTestKit's).
--
--     dofile("tests/wow_stubs.lua")
--     local H = dofile("tests/harness.lua")
--     H.loadAddon()
--     check(cond, "message")        -- WowTestKit's check / eq / done
--     done("test_name")
------------------------------------------------------------

local H = {}

-- check / eq / done are WowTestKit's (globals).

TOC = "Apotheca.toc"
-- Every file line of the TOC, and its Lua files, in load order.
function H.tocLines() return Kit.tocLines(TOC) end
function H.tocFiles() return Kit.tocFiles(TOC) end

-- The embedded LibGlass-1.0 (the wheel's glass, #94) comes from a checkout,
-- not from Libs\ (gitignored, filled by the packager): $LIBGLASS, else
-- ../LibGlass. No checkout fails the run loudly; a silently skipped library
-- would test nothing. (GlassChat's harness.)
H.LIBGLASS_XML = "Libs\\LibGlass-1.0\\LibGlass-1.0.xml"
function H.libGlassRoot()
    local root = (os.getenv("LIBGLASS") or "../LibGlass"):gsub("\\", "/"):gsub("/$", "")
    local f = io.open(root .. "/LibGlass-1.0.xml", "rb")
    if not f then
        error("LibGlass checkout not found at " .. root .. " (no LibGlass-1.0.xml): clone "
              .. "github.com/Spotnick2/LibGlass there or set LIBGLASS", 0)
    end
    f:close()
    return root
end
-- The Lua files the library's XML loads, in order: what the client runs for
-- that TOC line. A listed file that is missing fails here.
function H.libGlassScripts()
    local root = H.libGlassRoot()
    local f = assert(io.open(root .. "/LibGlass-1.0.xml", "rb"))
    local xml = f:read("*a"):gsub("<!%-%-.-%-%->", "")   -- listed in a comment is not loaded
    f:close()
    local files = {}
    for file in xml:gmatch('<Script%s+file="([^"]+)"') do
        local path = root .. "/" .. file:gsub("\\", "/")
        local src = io.open(path, "rb")
        if not src then error("LibGlass-1.0.xml at " .. root .. " is missing " .. file, 0) end
        src:close()
        files[#files + 1] = path
    end
    if #files == 0 then error("LibGlass-1.0.xml at " .. root .. " lists no Script files", 0) end
    return files
end
-- Every TOC line's Lua, in load order: the library's XML is its scripts.
function H.loadOrder()
    local files = {}
    for _, line in ipairs(H.tocLines()) do
        if line == H.LIBGLASS_XML then
            for _, f in ipairs(H.libGlassScripts()) do files[#files + 1] = f end
        elseif line:match("%.lua$") then
            files[#files + 1] = line:gsub("\\", "/")
        else
            error("a TOC line the tests can't load: " .. line, 0)
        end
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
    loadFiles(H.loadOrder(), "Apotheca", {})
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
    WoW.step(1)
    WoW.step(1)
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
    for _, m in ipairs(WoW.chat) do if m:find(pattern) then n = n + 1 end end
    return n
end

-- The probe's commands: /fp apo <cmd>. Chat and the console's session
-- lines start empty, so a test reads what this command said.
function H.fp(cmd)
    WoW.chat = {}
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
