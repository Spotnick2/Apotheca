-- export_wellfed.lua - turn an /apo scan3 SavedVariables file into a TSV of
-- every spell named "Well Fed" (#19): the source for telling XP Well Fed
-- auras from ordinary ones.
--
--   lua5.1 Tools/export_wellfed.lua <WTF>/Account/<id>/SavedVariables/ApothecaProbe.lua docs/forever-wellfed-<build>.tsv
--
-- Columns: spellID, description. The file starts with "#" lines: COMPLETE
-- or INCOMPLETE with the coverage counts, then the hidden spells (names
-- the client never served; Blizzard keeps some data encrypted until it is
-- discovered). A scan is INCOMPLETE only when unnamed spells were skipped;
-- it is still written, so it can be read, but the exit status is 2.
-- The XP line is in no spell text the API returns (measured on 70009), so
-- this file does not classify: see docs/FOREVER-PROBE.md.
dofile(arg[1])
local scan = ApothecaProbeDB and ApothecaProbeDB.wellFedScan
assert(scan, "no wellFedScan in " .. arg[1] .. " - run /apo scan3, then /reload")
if type(scan.hidden) ~= "table" or type(scan.scannedTo) ~= "number" then
    error("this wellFedScan was saved by an older probe - run /apo scan3 again, then /reload", 0)
end
local ids = {}
for id in pairs(scan.spells) do ids[#ids + 1] = id end
table.sort(ids)
local out = assert(io.open(arg[2], "w"))
out:write(string.format("# %s build %s: %d spells exist, highest %d, scanned to %d; names skipped %d, hidden %d; %d Well Fed spells, %d with an empty description\n",
    scan.complete and "COMPLETE" or "INCOMPLETE", tostring(scan.build), scan.exist, scan.highest,
    scan.scannedTo, scan.unnamedSkipped, #scan.hidden, #ids, scan.emptyDescription))
out:write("# hidden: ", #scan.hidden > 0 and table.concat(scan.hidden, ", ") or "none", "\n")
for _, id in ipairs(ids) do
    out:write(id, "\t", (scan.spells[id]:gsub("[\t\r\n]", " ")), "\n")
end
out:close()
print(#ids .. " Well Fed spells from build " .. tostring(scan.build))
if not scan.complete then
    print("INCOMPLETE scan: " .. scan.unnamedSkipped .. " unnamed spells were skipped.")
    os.exit(2)
end
