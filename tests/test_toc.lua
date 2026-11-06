-- The TOC, by WowTestKit's checks: interface 16001, the packager's version
-- token, every listed .lua file exists and is listed once. Apotheca's own
-- manifest checks (IDs, load order, .pkgmeta, the probe) are test_manifest.

dofile("tests/wow_stubs.lua")
dofile("tests/harness.lua")

Kit.checkToc(TOC)
-- Kit.checkToc checks only .lua files exist. Bindings.xml isn't in the TOC
-- (the client loads it by name), so it is checked here.
local xml = io.open("Bindings.xml", "rb")
check(xml ~= nil, "Bindings.xml exists")
if xml then xml:close() end
for _, line in ipairs(Kit.tocLines(TOC)) do
    check(line:match("%.lua$"), "the TOC lists only Lua files: " .. line)
end

done("test_toc")
