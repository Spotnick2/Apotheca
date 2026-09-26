-- export_wellfed.lua - turn an /apo scan3 SavedVariables file into a TSV of
-- every spell named "Well Fed" (#19), for Tools/build_item_tables.py.
--
--   lua5.1 Tools/export_wellfed.lua <WTF>/Account/<id>/SavedVariables/ApothecaProbe.lua docs/forever-wellfed-<build>.tsv
--
-- Columns: spellID, xp (1 if the description has the kill-XP bonus), description.
-- The first line is a "#" comment with the scan's coverage counts.
dofile(arg[1])
local scan = ApothecaProbeDB and ApothecaProbeDB.wellFedScan
assert(scan, "no wellFedScan in " .. arg[1] .. " - run /apo scan3, then /reload")
local ids = {}
for id in pairs(scan.spells) do ids[#ids + 1] = id end
table.sort(ids)
local out = assert(io.open(arg[2], "w"))
out:write(string.format("# build %s, spell IDs 1..%d: %d exist, names never loaded %d in range and %d outside it, %d without description\n",
    tostring(scan.build), scan.max, scan.exist, scan.unnamedNeverLoaded, scan.unnamedOutside, scan.noDescription))
local xp = 0
for _, id in ipairs(ids) do
    local d = scan.spells[id]
    local isXP = d:find("[Ee]xperience gained from kills") and 1 or 0
    xp = xp + isXP
    out:write(id, "\t", isXP, "\t", (d:gsub("[\t\r\n]", " ")), "\n")
end
out:close()
print(#ids .. " Well Fed spells (" .. xp .. " with XP) from build " .. tostring(scan.build))
