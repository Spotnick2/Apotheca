-- export_scan.lua - turn an /apo scan + /apo scan2 SavedVariables file into a
-- TSV for Tools/build_item_tables.py.
--
--   lua5.1 Tools/export_scan.lua <WTF>/Account/<id>/SavedVariables/ApothecaProbe.lua out.tsv
--
-- Scans made before the probe had its own SavedVariable are in Apotheca.lua.
--
-- Columns: id, subClassID, subType, name, spellID, spellName, tooltip lines
-- joined by " | " (the spell description is appended as "|| DESC: ...").
dofile(arg[1])
local scan = (ApothecaProbeDB and ApothecaProbeDB.itemScan) or (ApothecaDB and ApothecaDB.itemScan)
assert(scan, "no itemScan in " .. arg[1] .. " - run /apo scan and /apo scan2, then /reload")
local ids = {}
for id in pairs(scan.items) do ids[#ids + 1] = id end
table.sort(ids)
local out = assert(io.open(arg[2], "w"))
for _, id in ipairs(ids) do
    local e = scan.items[id]
    local t = (e.t and table.concat(e.t, " | ") or "") .. (e.d and (" || DESC: " .. e.d) or "")
    out:write(id, "\t", tostring(e.s), "\t", tostring(e.st), "\t", tostring(e.n), "\t",
              tostring(e.sp), "\t", tostring(e.spn), "\t", (t:gsub("[\t\r\n]", " ")), "\n")
end
out:close()
print(#ids .. " items from build " .. tostring(scan.build))
