-- export_wellfed.lua - turn an /apo scan3 SavedVariables file into a TSV of
-- every spell named "Well Fed" (#19), for Tools/build_item_tables.py.
--
--   lua5.1 Tools/export_wellfed.lua <WTF>/Account/<id>/SavedVariables/ApothecaProbe.lua docs/forever-wellfed-<build>.tsv
--
-- Columns: spellID, xp (1 if the description or tooltip has the kill-XP
-- bonus), description, spell tooltip. The IDs whose names never loaded are
-- listed in a second "#" line.
-- The first line is a "#" comment: COMPLETE or INCOMPLETE, and the scan's
-- coverage counts. An incomplete scan is still written, so it can be read,
-- but the exit status is 2 and the generator refuses it as a source.
dofile(arg[1])
local scan = ApothecaProbeDB and ApothecaProbeDB.wellFedScan
assert(scan, "no wellFedScan in " .. arg[1] .. " - run /apo scan3, then /reload")
local ids = {}
for id in pairs(scan.spells) do ids[#ids + 1] = id end
table.sort(ids)
local out = assert(io.open(arg[2], "w"))
out:write(string.format("# %s build %s: %d spells exist, highest %d, scanned to %d; names skipped %d, never loaded %d; %d without description\n",
    scan.complete and "COMPLETE" or "INCOMPLETE", tostring(scan.build), scan.exist, scan.highest,
    scan.scannedTo, scan.unnamedSkipped, scan.unnamedNeverLoaded, scan.noDescription))
if scan.neverLoaded and #scan.neverLoaded > 0 then
    out:write("# names never loaded: ", table.concat(scan.neverLoaded, ", "), "\n")
end
local xp = 0
for _, id in ipairs(ids) do
    local d = scan.spells[id]
    local tip = scan.tooltips and scan.tooltips[id] or ""
    local isXP = (d .. tip):find("[Ee]xperience gained from kills") and 1 or 0
    xp = xp + isXP
    out:write(id, "\t", isXP, "\t", (d:gsub("[\t\r\n]", " ")), "\t", (tip:gsub("[\t\r\n]", " ")), "\n")
end
out:close()
print(#ids .. " Well Fed spells (" .. xp .. " with XP) from build " .. tostring(scan.build))
if not scan.complete then
    print("INCOMPLETE scan: some names or descriptions never loaded. Run /apo scan3 again.")
    os.exit(2)
end
