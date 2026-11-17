-- The TOC, by WowTestKit's checks: interface 16001, the packager's version
-- token, every listed .lua file exists and is listed once. Apotheca's own
-- manifest checks (IDs, load order, .pkgmeta, the probe) are test_manifest.

dofile("tests/wow_stubs.lua")
local H = dofile("tests/harness.lua")

Kit.checkToc(TOC)
-- Kit.checkToc checks only .lua files exist. Bindings.xml isn't in the TOC
-- (the client loads it by name), so it is checked here.
local xml = io.open("Bindings.xml", "rb")
check(xml ~= nil, "Bindings.xml exists")
if xml then xml:close() end
-- Lua files, and the embedded LibGlass's XML (the wheel's glass, #94),
-- first: the wheel builds its glass at load.
local lines = Kit.tocLines(TOC)
eq(lines[1], H.LIBGLASS_XML, "LibGlass-1.0 loads first")
for i, line in ipairs(lines) do
    if i > 1 then check(line:match("%.lua$"), "after it, only Lua files: " .. line) end
end
check(#H.libGlassScripts() > 0, "the library's XML loads its scripts (from the checkout)")

done("test_toc")
