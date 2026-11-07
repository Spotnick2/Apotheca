-- Every widget method the addon calls must exist on this client, on that
-- widget type: the stub answers any method (a no-op for one it doesn't
-- implement), so a call Forever lacks would otherwise pass silently. The
-- addon is exercised as widely as is cheap, then WowTestKit's
-- Kit.checkMethods checks each recorded "Type:Method" against the pinned
-- build's widget methods.

dofile("tests/wow_stubs.lua")
local H = dofile("tests/harness.lua")

-- A mage with something on most buttons, so the bar, its glows and the
-- profession bar all draw.
WoW.class = "MAGE"
WoW.knownSpells[818] = true            -- Basic Campfire (Cooking)
WoW.knownSpells[3273] = true           -- First Aid

H.loadAddon()
local DATA = Apotheca.DATA
local slot = 0
local function carry(list)
    local e = list and list[1]
    local id = type(e) == "table" and e.id or e
    if id then slot = slot + 1; WoW.AddItem(0, slot, id, 3) end
end
carry(DATA.MANA_ITEMS); carry(DATA.HEALTH_ITEMS); carry(DATA.FOOD_ITEMS); carry(DATA.DRINK_ITEMS)
carry(DATA.BANDAGE_ITEMS); carry(DATA.HEALTHSTONE_ITEMS); carry(DATA.MANA_GEMS)
for _, list in pairs(DATA.SCROLLS_BY_STAT or {}) do carry(list) end
for _, list in pairs(DATA.BUFF_FOOD_BY_STAT or {}) do carry(list) end
carry(DATA.XP_FOOD); carry(DATA.OILS)

-- Every event, then a few seconds of frames.
WoW.fireAllRegistered()
WoW.fire("BAG_UPDATE_DELAYED")
for _ = 1, 5 do WoW.step(1) end

-- Every frame under f, depth first.
local function walk(f, fn)
    fn(f)
    for _, c in ipairs(f._children or {}) do walk(c, fn) end
end
-- Hover everything that has a tooltip, and click what isn't secure (the
-- options' checkboxes, arrows and buttons).
local function poke(frame)
    walk(frame, function(w)
        local s = w._scripts
        if s.OnEnter then s.OnEnter(w) end
        if s.OnLeave then s.OnLeave(w) end
        if s.OnClick and (w._type == "Button" or w._type == "CheckButton") and not w._protected then
            s.OnClick(w, "LeftButton", false)
        end
    end)
end

-- Every options page, shown as Settings shows it, then poked.
for _, page in ipairs(Apotheca.optionsPages) do
    page:Show()
    poke(page)
    page:Hide()
end

-- The bars: hover every button, Alt over the bar for the drag anchor.
poke(ApothecaFrame)
poke(ApothecaUtilityFrame)
WoW.altDown = true
ApothecaFrame._mouseOver = true
WoW.fire("MODIFIER_STATE_CHANGED", "LALT", 1)
WoW.step(0.2)
WoW.altDown = false
ApothecaFrame._mouseOver = false
WoW.fire("MODIFIER_STATE_CHANGED", "LALT", 0)
WoW.step(0.2)

-- Every slash command.
for _, cmd in ipairs({ "status", "debug", "debug", "utility", "utility", "" }) do
    SlashCmdList.APOTHECA(cmd)
    WoW.step(1)
end

-- A fight and its end.
WoW.enterCombat()
WoW.fire("BAG_UPDATE_COOLDOWN")
WoW.fire("UNIT_AURA", "player")
WoW.step(1)
WoW.leaveCombat()
WoW.step(1)

local recorded = Kit.checkMethods({ allow = {
    ["GameTooltip:SetItemByID"] = "GameTooltipDataMixin's tooltip data accessor "
        .. "(Blizzard_SharedXMLGame/Tooltip/TooltipDataHandler.lua:525, AddTooltipDataAccessor)",
} })
check(recorded >= 90, "the exercise reached the bars and the options (" .. recorded .. " recorded)")

done("test_methods")
