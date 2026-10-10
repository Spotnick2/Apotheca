-- #54: drag and drop in the options' reorderable lists (the Profession Bar
-- tab's Actions and the main Button Order tab). The cursor is faked: the
-- list's top is at 500 (stub GetTop), scale 1, so a row's slot is found
-- from how far below 500 the cursor is.

dofile("tests/wow_stubs.lua")
local H = dofile("tests/harness.lua")

H.loadAddon()
local panel = Apotheca.optionsPanel
panel._scripts.OnShow(panel)
local db = ApothecaDB.profiles[ApothecaDB.activeProfile]
local U = Apotheca.Utility

-- A list row, found by its label.
local function utilityRow(label)
    for _, f in ipairs(H.framesWithTemplate("InterfaceOptionsCheckButtonTemplate")) do
        if f.Text and f.Text:GetText() == label and f:GetParent()._scripts.OnDragStart then
            return f:GetParent()
        end
    end
end
local function orderRow(label)
    for _, fs in ipairs(WoW.fontStrings) do
        local row = fs:GetParent()
        if fs._text == label and row and row._scripts.OnDragStart then return row end
    end
end
local function countLabel(label)
    local n = 0
    for _, fs in ipairs(WoW.fontStrings) do
        if fs._text == label then n = n + 1 end
    end
    return n
end

-- Lift a row, move the cursor to `slot` (rows `step` apart below 500), drop.
local function drag(row, slot, step)
    row._scripts.OnDragStart(row)
    WoW.cursorY = 500 - (slot - 1) * step - 5
    WoW.tick(0.05)
    local lineShown = row:GetParent()._dropLine and row:GetParent()._dropLine:IsShown()
    row._scripts.OnDragStop(row)
    return lineShown
end

-- Profession Bar: rows 24 high, 2 apart.
local US = 26
H.eq(U.Order()[1], "hearthstone", "default order first")
local de = utilityRow("Disenchant")
H.check(de, "the Disenchant row is draggable")
local line = drag(de, 1, US)
H.check(line, "a gold line marks where it will land")
H.eq(db.utility.order[1], "disenchant", "dropped first: saved")
H.eq(U.Order()[1], "disenchant", "and the bar's order follows")
H.eq(U.Order()[2], "hearthstone", "the others move down")
H.eq(de:GetAlpha() or 1, 1, "the row is opaque again")

-- Down: from 1 to 3.
drag(de, 3, US)
H.eq(table.concat({ U.Order()[1], U.Order()[2], U.Order()[3] }, ","), "hearthstone,cooking,disenchant",
    "moved down two places")

-- Dropped where it was: nothing saved.
local before = table.concat(db.utility.order, ",")
H.check(not drag(de, 3, US), "no line over its own place")
H.eq(table.concat(db.utility.order, ","), before, "dropped in place: the order is unchanged")

-- The panel closed mid-drag: the row goes back, nothing saved.
de._scripts.OnDragStart(de)
WoW.cursorY = 495
WoW.tick(0.05)
de._scripts.OnHide(de)
H.eq(table.concat(db.utility.order, ","), before, "closed mid-drag: nothing moved")
H.eq(de._scripts.OnUpdate, nil, "and it stops following the cursor")

-- The arrows still work.
local function arrows(row)
    local out = {}
    for _, f in ipairs(WoW.frames) do
        if f:GetParent() == row and f._kind == "Button" then out[#out + 1] = f end
    end
    return out
end
local up = arrows(de)[1]
up._scripts.OnClick(up)
H.eq(U.Order()[2], "disenchant", "the up arrow moves it one place")

-- Main Button Order: rows 22 high, 2 apart.
local MS = 24
local order = Apotheca.GetButtonOrder()
local lastKey = order[#order]
H.eq(lastKey, "bandage", "Bandage is last by default")
local bandage = orderRow("Bandage")
H.check(bandage, "the Bandage row is draggable")
drag(bandage, 1, MS)
H.eq(db.buttonOrder[1], "bandage", "dropped first: saved")
H.eq(Apotheca.GetButtonOrder()[1], "bandage", "and the bar's order follows")
local number
for _, fs in ipairs(WoW.fontStrings) do
    if fs:GetParent() == bandage and type(fs._text) == "string" and fs._text:match("^%d+%.$") then number = fs._text end
end
H.eq(number, "1.", "its number follows")

-- Rows are made once: refreshing the panel reuses them.
local n = countLabel("Bandage")
Apotheca.RefreshOptions()
Apotheca.RefreshOptions()
H.eq(countLabel("Bandage"), n, "no new Button Order rows on refresh")

-- Reset puts the default order back, with the same rows.
db.buttonOrder = nil
Apotheca.RefreshOptions()
H.eq(Apotheca.GetButtonOrder()[#Apotheca.GetButtonOrder()], "bandage", "reset: Bandage last again")
H.eq(countLabel("Bandage"), n, "with the same row")

H.done("test_reorder")
