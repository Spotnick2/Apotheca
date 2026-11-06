-- #54: drag and drop in the options' reorderable lists (the Profession Bar
-- tab's Actions and the main Button Order tab). The cursor is faked: the
-- list's top is at 500 and its left at 600 (stub GetTop / GetLeft), scale 1,
-- so a row's slot is found from how far below 500 the cursor is.

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

WoW.cursorX = 610

-- In game a row is dragged on its open page: show the row's page and every
-- frame above it, so the drag's OnUpdate runs (only a visible frame's does).
local function openPageOf(row)
    local f = row
    while f do
        if not f:IsShown() then f:Show() end
        f = f:GetParent()
    end
end

-- Lift a row, move the cursor to `slot` (rows `step` apart below 500), drop.
local function drag(row, slot, step)
    row._scripts.OnDragStart(row)
    WoW.cursorY = 500 - (slot - 1) * step - 5
    WoW.step(0.05)
    local lineShown = row:GetParent()._dropLine and row:GetParent()._dropLine:IsShown()
    row._scripts.OnDragStop(row)
    return lineShown
end

-- Profession Bar: rows 24 high, 2 apart.
local US = 26
eq(U.Order()[1], "hearthstone", "default order first")
local de = utilityRow("Disenchant")
check(de, "the Disenchant row is draggable")
openPageOf(de)
local line = drag(de, 1, US)
check(line, "a gold line marks where it will land")
eq(db.utility.order[1], "disenchant", "dropped first: saved")
eq(U.Order()[1], "disenchant", "and the bar's order follows")
eq(U.Order()[2], "hearthstone", "the others move down")
eq(de:GetAlpha() or 1, 1, "the row is opaque again")

-- Down: from 1 to 3.
drag(de, 3, US)
eq(table.concat({ U.Order()[1], U.Order()[2], U.Order()[3] }, ","), "hearthstone,cooking,disenchant",
    "moved down two places")

-- Dropped where it was: nothing saved.
local before = table.concat(db.utility.order, ",")
check(not drag(de, 3, US), "no line over its own place")
eq(table.concat(db.utility.order, ","), before, "dropped in place: the order is unchanged")

-- The panel closed mid-drag: the row goes back, nothing saved.
de._scripts.OnDragStart(de)
WoW.cursorY = 495
WoW.step(0.05)
de._scripts.OnHide(de)
eq(table.concat(db.utility.order, ","), before, "closed mid-drag: nothing moved")
eq(de._scripts.OnUpdate, nil, "and it stops following the cursor")

-- Pressing the label lifts the row: the tick box covers it.
local cb
for _, f in ipairs(H.framesWithTemplate("InterfaceOptionsCheckButtonTemplate")) do
    if f:GetParent() == de then cb = f end
end
cb._scripts.OnDragStart(cb)
WoW.cursorY = 500 - 5
WoW.step(0.05)
local deLine = de:GetParent()._dropLine
check((deLine:GetFrameLevel() or 0) > (de:GetFrameLevel() or 0), "the line is drawn over the lifted row")
cb._scripts.OnDragStop(cb)
eq(U.Order()[1], "disenchant", "dragged by its label: moved first")

-- Let go away from the list: nothing moves.
local function dropAt(row, x, y)
    row._scripts.OnDragStart(row)
    WoW.cursorX, WoW.cursorY = x, y
    WoW.step(0.05)
    local shown = row:GetParent()._dropLine:IsShown()
    row._scripts.OnDragStop(row)
    WoW.cursorX = 610
    return shown
end
before = table.concat(db.utility.order, ",")
check(not dropAt(de, 100, 495), "no line beside the list")
eq(table.concat(db.utility.order, ","), before, "dropped beside the list: unchanged")
dropAt(de, 610, -2000)
eq(table.concat(db.utility.order, ","), before, "dropped far below it: unchanged")

-- Scrolled: the list's top is above the view (scroll frame 500 to 200).
-- Over the tabs above it or below the panel, level with rows out of view,
-- a drop is away from the list.
local uList = de:GetParent()
uList._top = 700
dropAt(de, 610, 550)
eq(table.concat(db.utility.order, ","), before, "scrolled, dropped above the view: unchanged")
dropAt(de, 610, 190)
eq(table.concat(db.utility.order, ","), before, "scrolled, dropped below the view: unchanged")
uList._top = nil

-- A refresh during the drag: the row is found again at the drop.
de._scripts.OnDragStart(de)
db.utility.order = { "hearthstone", "cooking", "firstaid", "disenchant" }
Apotheca.RefreshOptions()
WoW.cursorY = 500 - 5
WoW.step(0.05)
de._scripts.OnDragStop(de)
eq(U.Order()[1], "disenchant", "refreshed mid-drag: the dragged row still moves")
eq(U.Order()[2], "hearthstone", "and only it")

-- Auto-scroll waits until the cursor has moved: a row lifted beside the
-- edge doesn't run away.
local sf = de:GetParent():GetParent():GetParent()
sf._bottom, sf._vrange, sf._vscroll = 470, 200, 0
WoW.cursorY = 480
de._scripts.OnDragStart(de)
WoW.step(0.05)
eq(sf:GetVerticalScroll(), 0, "lifted near the bottom edge: no scroll yet")
WoW.cursorY = 455
WoW.step(0.05)
check(sf:GetVerticalScroll() > 0, "moved toward the edge: it scrolls")
de._scripts.OnHide(de)
sf._bottom, sf._vrange, sf._vscroll = nil, nil, nil

-- The arrows still work.
local function arrows(row)
    local out = {}
    for _, f in ipairs(WoW.frames) do
        if f:GetParent() == row and f._type == "Button" then out[#out + 1] = f end
    end
    return out
end
local down = arrows(de)[2]
down._scripts.OnClick(down)
eq(U.Order()[2], "disenchant", "the down arrow moves it one place")

-- Main Button Order: rows 22 high, 2 apart.
local MS = 24
local order = Apotheca.GetButtonOrder()
local lastKey = order[#order]
eq(lastKey, "bandage", "Bandage is last by default")
local bandage = orderRow("Bandage")
check(bandage, "the Bandage row is draggable")
openPageOf(bandage)
drag(bandage, 1, MS)
eq(db.buttonOrder[1], "bandage", "dropped first: saved")
eq(Apotheca.GetButtonOrder()[1], "bandage", "and the bar's order follows")
local number
for _, fs in ipairs(WoW.fontStrings) do
    if fs:GetParent() == bandage and type(fs._text) == "string" and fs._text:match("^%d+%.$") then number = fs._text end
end
eq(number, "1.", "its number follows")

-- A refresh during a Button Order drag doesn't drop it.
local mana = orderRow("Mana Potion")
-- In game, hiding a shown frame runs its OnHide (the stub doesn't).
function mana:Hide()
    if self._shown ~= false and self._scripts.OnHide then self._scripts.OnHide(self) end
    self._shown = false
end
mana._scripts.OnDragStart(mana)
Apotheca.RefreshOptions()
check(mana._scripts.OnUpdate ~= nil, "a refresh keeps the drag going")
WoW.cursorY = 500 - 5
WoW.step(0.05)
mana._scripts.OnDragStop(mana)
eq(db.buttonOrder[1], "mana", "and the drop lands")

-- Rows are made once: refreshing the panel reuses them.
local n = countLabel("Bandage")
Apotheca.RefreshOptions()
Apotheca.RefreshOptions()
eq(countLabel("Bandage"), n, "no new Button Order rows on refresh")

-- Reset puts the default order back, with the same rows.
db.buttonOrder = nil
Apotheca.RefreshOptions()
eq(Apotheca.GetButtonOrder()[#Apotheca.GetButtonOrder()], "bandage", "reset: Bandage last again")
eq(countLabel("Bandage"), n, "with the same row")

done("test_reorder")
