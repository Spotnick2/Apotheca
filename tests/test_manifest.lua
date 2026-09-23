-- The TOC and .pkgmeta. Wrong values here are invisible in game: the client
-- does not hard-block a bad interface number, and a packaging mistake only
-- shows in the published zip.

dofile("tests/wow_stubs.lua")
local H = dofile("tests/harness.lua")

local toc = assert(io.open("Apotheca.toc")):read("*a"):gsub("\r", "")

H.check(toc:find("\n?## Interface: 16001\n"), "Interface is 16001 (1.60.1 -> %d%02d%02d; 11601 is a transposed-digit bug)")
H.check(toc:find("## X%-Curse%-Project%-ID: 1498195\n"), "CurseForge project ID is 1498195")
H.check(toc:find("## Version: @project%-version@\n"), "Version stays the packager token in the repo")
H.check(toc:find("## IconTexture: "), "the addon list gets an icon, not a question mark")
H.check(toc:find("## SavedVariables: ApothecaDB\n"), "ApothecaDB is the saved table")

local files = H.tocFiles()
H.eq(files[1], "ApothecaCompat.lua", "the compat layer loads first")
local seen = {}
for _, f in ipairs(files) do
    seen[f] = true
    H.check(io.open(f) ~= nil, "TOC file exists: " .. f)
end
H.check(seen["Apotheca.lua"] and seen["Apotheca_Options.lua"], "both main files are listed")

local pkg = assert(io.open(".pkgmeta")):read("*a"):gsub("\r", "")
H.check(pkg:find("package%-as: Apotheca\n"), ".pkgmeta packages as Apotheca")
for _, ignored in ipairs({ "tests", "Tools", "docs", "AGENTS.md", "CLAUDE.md", ".claude", ".github" }) do
    H.check(pkg:find("\n%s*%- " .. ignored:gsub("%p", "%%%0") .. "\n"), ".pkgmeta ignores " .. ignored)
end

H.done("test_manifest")
