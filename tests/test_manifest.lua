-- The TOC and .pkgmeta. Wrong values here are invisible in game: the client
-- does not hard-block a bad interface number, and a packaging mistake only
-- shows in the published zip.

dofile("tests/wow_stubs.lua")
local H = dofile("tests/harness.lua")

local toc = assert(io.open("Apotheca.toc")):read("*a"):gsub("\r", "")

check(toc:find("\n?## Interface: 16001\n"), "Interface is 16001 (1.60.1 -> %d%02d%02d; 11601 is a transposed-digit bug)")
check(toc:find("## X%-Curse%-Project%-ID: 1498195\n"), "CurseForge project ID is 1498195")
check(toc:find("## Version: @project%-version@\n"), "Version stays the packager token in the repo")
check(toc:find("## IconTexture: "), "the addon list gets an icon, not a question mark")
check(toc:find("## SavedVariables: ApothecaDB\n"), "ApothecaDB is the saved table")

local files = H.tocFiles()
eq(files[1], "ApothecaCompat.lua", "the compat layer loads first")
local seen = {}
for _, f in ipairs(files) do
    seen[f] = true
    check(io.open(f) ~= nil, "TOC file exists: " .. f)
end
check(seen["Apotheca.lua"] and seen["Apotheca_Options.lua"], "both main files are listed")
-- The client loads Bindings.xml by name from the addon folder (#42).
check(io.open("Bindings.xml") ~= nil, "Bindings.xml exists")
check(not seen["Bindings.xml"], "and is not in the TOC")
check(not seen["ApothecaProbe.lua"], "the dev-only probe is not in the shipped TOC")
check(io.open("Tools/ApothecaProbe/ApothecaProbe.toc") ~= nil, "the probe lives in its own dev addon under Tools/")
-- A ForeverProbe module (#76): the host is its dependency, /fp its only command.
do
    local toc = io.open("Tools/ApothecaProbe/ApothecaProbe.toc"):read("*a")
    check(toc:find("\n## Dependencies: ForeverProbe") ~= nil, "the probe's TOC depends on ForeverProbe")
    local lua = io.open("Tools/ApothecaProbe/ApothecaProbe.lua"):read("*a")
    check(not lua:find("SLASH_%u") and not lua:find("SlashCmdList"), "the probe has no slash command of its own")
    check(not lua:find("[^%w_]print%("), "the probe writes nothing to chat")
    local shipped = io.open("Apotheca.toc"):read("*a")
    check(not shipped:find("ForeverProbe"), "the shipped TOC never names ForeverProbe")
end

local pkg = assert(io.open(".pkgmeta")):read("*a"):gsub("\r", "")
check(pkg:find("package%-as: Apotheca\n"), ".pkgmeta packages as Apotheca")
-- LibGlass, embedded at a pinned tag (never `latest`), and its dev files
-- left out: CurseForge's packager ignores an external's own ignore list.
check(pkg:find("\nexternals:\n  Libs/LibGlass%-1%.0:\n    url: https://github%.com/Spotnick2/LibGlass\n    tag: r%d+\n"),
    ".pkgmeta embeds LibGlass at a pinned tag")
for _, ignored in ipairs({ "tests", "docs", "Tools", "AGENTS.md", "CLAUDE.md", "README.md" }) do
    check(pkg:find("\n%s*%- Libs/LibGlass%-1%.0/" .. ignored:gsub("%p", "%%%0") .. "\n"),
        ".pkgmeta ignores the library's " .. ignored)
end
local gi = io.open(".gitignore")
check(gi and gi:read("*a"):find("\nLibs/") ~= nil, "Libs/ is never committed (the packager fills it)")
if gi then gi:close() end
for _, ignored in ipairs({ "tests", "Tools", "docs", "AGENTS.md", "CLAUDE.md", ".claude", ".github" }) do
    check(pkg:find("\n%s*%- " .. ignored:gsub("%p", "%%%0") .. "\n"), ".pkgmeta ignores " .. ignored)
end

done("test_manifest")
