-- ============================================================
-- Apotheca_Options.lua  —  Configuration Panel (Tabbed)
-- Panel frame is registered at PLAYER_LOGIN.
-- Widget content is built LAZILY on first OnShow.
-- ============================================================

local function DB()
    if not ApothecaDB or not ApothecaDB.profiles then return {} end
    return ApothecaDB.profiles[ApothecaDB.activeProfile or "Global"] or {}
end

local function DBGet(...)
    local t = DB()
    local n = select("#", ...)
    for i = 1, n - 1 do
        local k = select(i, ...)
        if type(t) ~= "table" then return nil end
        t = t[k]
    end
    if type(t) ~= "table" then return nil end
    return t[select(n, ...)]
end

local function DBSet(value, ...)
    local t = DB()
    local n = select("#", ...)
    for i = 1, n - 1 do
        local k = select(i, ...)
        if type(t[k]) ~= "table" then t[k] = {} end
        t = t[k]
    end
    t[select(n, ...)] = value
end

local refreshCallbacks = {}

function Apotheca.RefreshOptions()
    for _, fn in ipairs(refreshCallbacks) do pcall(fn) end
end

function Apotheca.CreateOptionsPanel()
    local panel = CreateFrame("Frame", "ApothecaOptionsPanel", UIParent)
    panel.name  = "Apotheca"
    Apotheca.optionsPanel = panel
    local built = false
    panel:SetScript("OnShow", function(self)
        if not built then
            built = true
            Apotheca.BuildOptionsPanelContent(self)
        end
        Apotheca.RefreshOptions()
    end)
    if Settings and Settings.RegisterCanvasLayoutCategory then
        local cat = Settings.RegisterCanvasLayoutCategory(panel, panel.name)
        Settings.RegisterAddOnCategory(cat)
        panel._category = cat
    elseif InterfaceOptions_AddCategory then
        InterfaceOptions_AddCategory(panel)
    end
end

function Apotheca.BuildOptionsPanelContent(panel)
    local CONTENT_W = 540
    local PAD       = 20
    local TAB_H     = 26
    local TAB_DEFS = {
        { key = "general",     label = "General"      },
        { key = "consumables", label = "Consumables"  },
        { key = "buttonorder", label = "Button Order" },
        { key = "profile",     label = "Profile"      },
    }
    local tabFrames, tabButtons, activeTab = {}, {}, nil

    local tabStrip = CreateFrame("Frame", nil, panel)
    tabStrip:SetPoint("TOPLEFT", panel, "TOPLEFT", 8, -8)
    tabStrip:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -8, -8)
    tabStrip:SetHeight(TAB_H + 4)

    local function SwitchTab(key)
        if activeTab == key then return end
        activeTab = key
        for _, def in ipairs(TAB_DEFS) do
            local k = def.key
            if tabFrames[k] then
                if k == key then tabFrames[k]:GetParent():Show()
                else tabFrames[k]:GetParent():Hide() end
            end
            if tabButtons[k] then
                if k == key then
                    tabButtons[k]:SetNormalFontObject(GameFontHighlight)
                    tabButtons[k]._bg:SetColorTexture(0.15, 0.15, 0.30, 1)
                else
                    tabButtons[k]:SetNormalFontObject(GameFontNormal)
                    tabButtons[k]._bg:SetColorTexture(0.08, 0.08, 0.18, 0.8)
                end
            end
        end
    end

    local tabX = 0
    for _, def in ipairs(TAB_DEFS) do
        local tb = CreateFrame("Button", nil, tabStrip)
        tb:SetHeight(TAB_H)
        tb:SetPoint("TOPLEFT", tabStrip, "TOPLEFT", tabX, 0)
        tb:SetNormalFontObject(GameFontNormal)
        tb:SetHighlightFontObject(GameFontHighlight)
        tb:SetText(def.label)
        local w = tb:GetFontString():GetStringWidth() + 24
        tb:SetWidth(w)
        local bg = tb:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        bg:SetColorTexture(0.08, 0.08, 0.18, 0.8)
        tb._bg = bg
        tb:SetScript("OnClick", function() SwitchTab(def.key) end)
        tabButtons[def.key] = tb
        tabX = tabX + w + 2
    end

    for _, def in ipairs(TAB_DEFS) do
        local sf = CreateFrame("ScrollFrame", "ApothecaScroll_" .. def.key, panel)
        sf:SetPoint("TOPLEFT", tabStrip, "BOTTOMLEFT", -4, -4)
        sf:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -4, 4)
        sf:Hide()
        local c = CreateFrame("Frame", "ApothecaContent_" .. def.key, sf)
        c:SetWidth(CONTENT_W)
        c:SetHeight(400)
        sf:SetScrollChild(c)
        sf:EnableMouseWheel(true)
        sf:SetScript("OnMouseWheel", function(self, delta)
            local cur = self:GetVerticalScroll()
            local mx  = self:GetVerticalScrollRange()
            self:SetVerticalScroll(math.max(0, math.min(mx, cur - delta * 24)))
        end)
        tabFrames[def.key] = c
    end

    -- widget state
    local curContent, curH = nil, 0
    local function SetTarget(c) curContent = c; curH = 0 end
    local function Y() return -curH end
    local function Gap(h) curH = curH + (h or 8) end
    local function FinalizeTarget() curContent:SetHeight(curH + 24) end

    local function SectionHeader(text)
        Gap(12)
        local bg = curContent:CreateTexture(nil, "BACKGROUND")
        bg:SetPoint("TOPLEFT", curContent, "TOPLEFT", 0, Y())
        bg:SetPoint("TOPRIGHT", curContent, "TOPRIGHT", 0, Y())
        bg:SetHeight(22)
        bg:SetColorTexture(0.12, 0.12, 0.22, 0.90)
        local fs = curContent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        fs:SetPoint("LEFT", bg, "LEFT", PAD, 0)
        fs:SetTextColor(0.9, 0.85, 0.45)
        fs:SetText(text)
        curH = curH + 22 + 6
    end

    local function SmallLabel(text)
        local fs = curContent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        fs:SetPoint("TOPLEFT", curContent, "TOPLEFT", PAD, Y())
        fs:SetTextColor(0.6, 0.6, 0.6)
        fs:SetText(text)
        fs:SetWidth(CONTENT_W - PAD * 2)
        fs:SetJustifyH("LEFT")
        curH = curH + fs:GetStringHeight() + 4
    end

    local function Checkbox(labelText, getter, setter, indent)
        local cb = CreateFrame("CheckButton", nil, curContent, "InterfaceOptionsCheckButtonTemplate")
        cb:SetPoint("TOPLEFT", curContent, "TOPLEFT", PAD + (indent or 0), Y())
        cb.Text:SetText(labelText)
        local function Sync() cb:SetChecked(getter() == true) end
        Sync()
        cb:SetScript("OnClick", function(self)
            local v = self:GetChecked()
            setter(v == true or v == 1)
            Apotheca.ResetLayout()
            Apotheca.UpdateAllButtons()
        end)
        refreshCallbacks[#refreshCallbacks + 1] = Sync
        curH = curH + 24
    end

    local function RadioGroup(options, getter, setter)
        local radios = {}
        Gap(4)
        for _, opt in ipairs(options) do
            local rb = CreateFrame("CheckButton", nil, curContent, "UIRadioButtonTemplate")
            rb:SetPoint("TOPLEFT", curContent, "TOPLEFT", PAD + 4, Y())
            rb.value = opt.value
            local lbl = rb:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
            lbl:SetPoint("LEFT", rb, "RIGHT", 4, 0)
            lbl:SetText(opt.label)
            rb:SetScript("OnClick", function(self)
                setter(self.value)
                for _, r in ipairs(radios) do r:SetChecked(r.value == self.value) end
                Apotheca.UpdateAllButtons()
            end)
            radios[#radios + 1] = rb
            curH = curH + 22
        end
        local function Sync()
            local cur = getter()
            for _, r in ipairs(radios) do r:SetChecked(r.value == cur) end
        end
        Sync()
        refreshCallbacks[#refreshCallbacks + 1] = Sync
        Gap(4)
    end

    local sliderN = 0
    local function Slider(labelText, minV, maxV, step, getter, setter, fmtFn)
        sliderN = sliderN + 1
        local fmt = fmtFn or tostring
        Gap(4)
        local boxTop = Y()
        local box = curContent:CreateTexture(nil, "BACKGROUND")
        box:SetColorTexture(0.08, 0.08, 0.18, 0.88)
        local lbl = curContent:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        lbl:SetPoint("TOPLEFT", curContent, "TOPLEFT", PAD + 4, Y())
        lbl:SetText(labelText)
        curH = curH + 18
        local name = "ApothecaSlider" .. sliderN
        local sl = CreateFrame("Slider", name, curContent, "OptionsSliderTemplate")
        sl:SetPoint("TOPLEFT", curContent, "TOPLEFT", PAD + 4, Y())
        sl:SetWidth(200)
        sl:SetMinMaxValues(minV, maxV)
        sl:SetValueStep(step)
        if sl.SetObeyStepOnDrag then sl:SetObeyStepOnDrag(true) end
        sl:SetValue(getter() or minV)
        local lowText  = sl.Low  or _G[name .. "Low"]
        local highText = sl.High or _G[name .. "High"]
        if lowText  then lowText:SetText(fmt(minV))  end
        if highText then highText:SetText(fmt(maxV)) end
        local valText = curContent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        valText:SetPoint("LEFT", sl, "RIGHT", 10, 0)
        valText:SetTextColor(1, 0.82, 0)
        valText:SetText(fmt(getter() or minV))
        sl:SetScript("OnValueChanged", function(self, v)
            v = math.floor(v / step + 0.5) * step
            setter(v)
            valText:SetText(fmt(v))
            Apotheca.ResetLayout()
            Apotheca.UpdateAllButtons()
        end)
        refreshCallbacks[#refreshCallbacks + 1] = function()
            local v = getter() or minV
            sl:SetValue(v)
            valText:SetText(fmt(v))
        end
        curH = curH + 28
        local boxH = curH - (-boxTop) + 6
        box:SetPoint("TOPLEFT", curContent, "TOPLEFT", PAD - 4, boxTop - 2)
        box:SetPoint("TOPRIGHT", curContent, "TOPRIGHT", -(PAD - 4), boxTop - 2)
        box:SetHeight(boxH)
        Gap(8)
    end

    local ddN = 0
    local function Dropdown(labelText, options, getter, setter)
        ddN = ddN + 1
        Gap(4)
        local lbl = curContent:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
        lbl:SetPoint("TOPLEFT", curContent, "TOPLEFT", PAD, Y())
        lbl:SetText(labelText)
        curH = curH + 16
        local dd = CreateFrame("Frame", "ApothecaDD" .. ddN, curContent, "UIDropDownMenuTemplate")
        dd:SetPoint("TOPLEFT", curContent, "TOPLEFT", PAD - 16, Y())
        UIDropDownMenu_SetWidth(dd, 160)
        local function Init()
            UIDropDownMenu_Initialize(dd, function()
                for _, opt in ipairs(options) do
                    local info = UIDropDownMenu_CreateInfo()
                    info.text    = opt.label
                    info.value   = opt.value
                    info.checked = (getter() == opt.value)
                    info.func    = function()
                        setter(opt.value)
                        UIDropDownMenu_SetText(dd, opt.label)
                        Apotheca.ResetLayout()
                        Apotheca.UpdateAllButtons()
                    end
                    UIDropDownMenu_AddButton(info)
                end
            end)
            local cur = getter()
            for _, opt in ipairs(options) do
                if opt.value == cur then UIDropDownMenu_SetText(dd, opt.label); break end
            end
        end
        Init()
        refreshCallbacks[#refreshCallbacks + 1] = Init
        curH = curH + 32
        Gap(4)
    end

    local function Divider()
        Gap(6)
        local t = curContent:CreateTexture(nil, "BACKGROUND")
        t:SetPoint("TOPLEFT", curContent, "TOPLEFT", PAD, Y())
        t:SetPoint("TOPRIGHT", curContent, "TOPRIGHT", -PAD, Y())
        t:SetHeight(1)
        t:SetColorTexture(0.35, 0.35, 0.45, 0.6)
        curH = curH + 1
        Gap(6)
    end

    -- ════════════════════════════════════════════════════════════
    -- TAB 1: GENERAL
    -- ════════════════════════════════════════════════════════════
    SetTarget(tabFrames["general"])

    SectionHeader("General")
    Checkbox("Enable Apotheca",
        function() return DBGet("enabled") ~= false end,
        function(v) DBSet(v, "enabled") end)
    Checkbox("Only show in healing spec",
        function() return DBGet("showOnlyHealingSpec") ~= false end,
        function(v) DBSet(v, "showOnlyHealingSpec") end)
    Checkbox("Always show empty buttons  |cff888888(show all slots even if bag is empty)|r",
        function() return DBGet("showEmptyButtons") == true end,
        function(v) DBSet(v, "showEmptyButtons") end)
    Checkbox("Lock bar position  |cff888888(disables Alt+Drag)|r",
        function() return DBGet("lockPosition") == true end,
        function(v) DBSet(v, "lockPosition") end)

    SectionHeader("Waste Prevention")
    SmallLabel("When at full health/mana, recovery buttons:")
    RadioGroup(
        {
            { value = "BLOCK",      label = "Block usage  |cff888888(silently disable button)|r" },
            { value = "ASK",        label = "Ask first  |cff888888(confirmation dialog)|r" },
            { value = "DO_NOTHING", label = "Do nothing  |cff888888(allow free usage)|r" },
        },
        function() return DBGet("preventWasteMode") or "BLOCK" end,
        function(v) DBSet(v, "preventWasteMode") end)

    SectionHeader("Right-Click Alternate")
    SmallLabel("When waste prevention shows a popup, right-clicking food/drink uses the alternate item instead:")
    RadioGroup(
        {
            { value = "OFF",    label = "Off  |cff888888(right-click uses same item)|r" },
            { value = "ASK",    label = "Ask first  |cff888888(confirmation dialog for alternate)|r" },
        },
        function() return DBGet("rightClickAlternate") or "OFF" end,
        function(v) DBSet(v, "rightClickAlternate") end)
    Gap(4)
    Slider("Conjured preference threshold", 1.0, 3.0, 0.1,
        function() return DBGet("conjuredThreshold") or 1.5 end,
        function(v) DBSet(v, "conjuredThreshold") end,
        function(v) return string.format("%.1fx", v) end)
    SmallLabel("|cff888888Prefer conjured food/drink unless a non-conjured item restores this many times more.|r")

    SectionHeader("Visibility")
    SmallLabel("Show bar when:")
    RadioGroup(
        {
            { value = "ALWAYS",        label = "Always visible"  },
            { value = "IN_COMBAT",     label = "In combat only"  },
            { value = "OUT_OF_COMBAT", label = "Out of combat"   },
            { value = "HIDDEN",        label = "Hidden"          },
        },
        function() return DBGet("visibility") or "ALWAYS" end,
        function(v) DBSet(v, "visibility") end)

    SectionHeader("Layout")
    Dropdown("Orientation:",
        { { value = "HORIZONTAL", label = "Horizontal" },
          { value = "VERTICAL",   label = "Vertical"   } },
        function() return DBGet("orientation") or "HORIZONTAL" end,
        function(v) DBSet(v, "orientation") end)
    Slider("Rows", 1, 4, 1,
        function() return DBGet("rows") or 1 end,
        function(v) DBSet(v, "rows") end)
    Slider("Icon Size", 20, 60, 2,
        function() return DBGet("iconSize") or 36 end,
        function(v) DBSet(v, "iconSize") end,
        function(v) return v .. "px" end)
    Slider("Icon Padding", 0, 10, 1,
        function() return DBGet("iconPadding") or 3 end,
        function(v) DBSet(v, "iconPadding") end)
    FinalizeTarget()

    -- ════════════════════════════════════════════════════════════
    -- TAB 2: CONSUMABLES
    -- ════════════════════════════════════════════════════════════
    SetTarget(tabFrames["consumables"])

    SectionHeader("Buff Food")
    Checkbox("Enable Buff Food button",
        function() return DBGet("buffFood", "enabled") ~= false end,
        function(v) DBSet(v, "buffFood", "enabled") end)
    Checkbox("Glow when Well Fed buff is missing  |cff888888(ready check)|r",
        function() return DBGet("buffFood", "glowOnMissingBuff") ~= false end,
        function(v) DBSet(v, "buffFood", "glowOnMissingBuff") end)
    Checkbox("Allow lower-tier substitutions",
        function() return DBGet("buffFood", "allowSubstitutions") ~= false end,
        function(v) DBSet(v, "buffFood", "allowSubstitutions") end)
    Checkbox("Strict: only use highest-tier food in category",
        function() return DBGet("buffFood", "strictBestOnly") == true end,
        function(v) DBSet(v, "buffFood", "strictBestOnly") end)

    SectionHeader("Buff Food Priority")
    SmallLabel("Priority order for stat categories (1 = most preferred).")
    Gap(4)
    local STAT_OPTIONS = {
        { value = "healing", label = "Healing" }, { value = "mp5", label = "MP5" },
        { value = "crit", label = "Crit" }, { value = "stamina", label = "Stamina" },
    }
    local DEFAULT_PRIO = { "healing", "mp5", "crit", "stamina" }
    for slot = 1, 4 do
        Dropdown("Priority " .. slot .. ":", STAT_OPTIONS,
            function()
                local _, cls = UnitClass("player")
                local p = DBGet("buffFoodPriority", cls or "PRIEST")
                return (p and p[slot]) or DEFAULT_PRIO[slot]
            end,
            function(v)
                local _, cls = UnitClass("player")
                if not cls then return end
                local db = DB()
                if type(db.buffFoodPriority) ~= "table" then db.buffFoodPriority = {} end
                if type(db.buffFoodPriority[cls]) ~= "table" then
                    db.buffFoodPriority[cls] = { "healing", "mp5", "crit", "stamina" }
                end
                db.buffFoodPriority[cls][slot] = v
            end)
    end

    SectionHeader("Buff Food Filters")
    SmallLabel("Which stat categories are considered when scanning bags:")
    Gap(2)
    for _, cat in ipairs({
        { key = "healing", label = "Healing  |cff888888(e.g. Golden Fish Sticks)|r" },
        { key = "mp5",     label = "MP5      |cff888888(e.g. Blackened Sporefish)|r" },
        { key = "crit",    label = "Crit     |cff888888(e.g. Skullfish Soup)|r" },
        { key = "stamina", label = "Stamina  |cff888888(e.g. Spicy Crawdad)|r" },
    }) do
        Checkbox(cat.label,
            function() return DBGet("categories", cat.key) ~= false end,
            function(v) DBSet(v, "categories", cat.key) end)
    end

    SectionHeader("Elixirs & Flasks")
    Checkbox("Enable Elixir / Flask buttons",
        function() return DBGet("elixirs", "enabled") ~= false end,
        function(v) DBSet(v, "elixirs", "enabled") end)
    Gap(4)
    SmallLabel("Mode:")
    RadioGroup(
        {
            { value = "AUTO",    label = "Auto  |cff888888(flask if available, otherwise separate elixirs)|r" },
            { value = "FLASK",   label = "Prefer Flask" },
            { value = "ELIXIRS", label = "Prefer Elixirs" },
        },
        function() return DBGet("elixirs", "mode") or "AUTO" end,
        function(v) DBSet(v, "elixirs", "mode") end)
    Divider()
    Checkbox("Allow lower-tier elixirs as fallback",
        function() return DBGet("elixirs", "allowLower") ~= false end,
        function(v) DBSet(v, "elixirs", "allowLower") end, 8)

    SectionHeader("Scrolls & Weapon Oil")
    Gap(4)
    Checkbox("Enable Spirit Scroll button",
        function() return DBGet("scrolls", "spirit") ~= false end,
        function(v) DBSet(v, "scrolls", "spirit") end)
    Checkbox("Enable Protection Scroll button",
        function() return DBGet("scrolls", "protection") ~= false end,
        function(v) DBSet(v, "scrolls", "protection") end)
    Checkbox("Glow scrolls when buff is missing  |cff888888(ready check)|r",
        function() return DBGet("scrolls", "glowOnMissingBuff") ~= false end,
        function(v) DBSet(v, "scrolls", "glowOnMissingBuff") end)
    Divider()
    Checkbox("Enable Weapon Oil button",
        function() return DBGet("weaponOil", "enabled") ~= false end,
        function(v) DBSet(v, "weaponOil", "enabled") end)
    Checkbox("Include Wizard Oils  |cff888888(off = mana oils only)|r",
        function() return DBGet("weaponOil", "includeWizardOils") == true end,
        function(v) DBSet(v, "weaponOil", "includeWizardOils") end)
    Checkbox("Glow when weapon oil is missing  |cff888888(ready check)|r",
        function() return DBGet("weaponOil", "glowOnMissingBuff") ~= false end,
        function(v) DBSet(v, "weaponOil", "glowOnMissingBuff") end)

    SectionHeader("Bandage")
    SmallLabel("Shows the best available bandage from your bags.")
    Gap(4)
    Checkbox("Enable Bandage button",
        function() return DBGet("bandage", "enabled") ~= false end,
        function(v) DBSet(v, "bandage", "enabled") end)
    SmallLabel("|cff888888Disabled while Recently Bandaged debuff is active.|r")
    FinalizeTarget()

    -- ════════════════════════════════════════════════════════════
    -- TAB 3: BUTTON ORDER
    -- ════════════════════════════════════════════════════════════
    SetTarget(tabFrames["buttonorder"])

    SectionHeader("Button Order")
    SmallLabel("Use the arrows to set the visual order of buttons on the bar.")
    Gap(6)

    local BUTTON_LABELS = {
        mana = "Mana Potion", health = "Health / Healthstone", rune = "Rune / Battle Res",
        recovery = "Recovery (Conjured)", food = "Food", drink = "Drink",
        flask = "Flask", battle = "Battle Elixir", guardian = "Guardian Elixir",
        bufffood = "Buff Food", spiritscroll = "Spirit Scroll",
        protectionscroll = "Protection Scroll", weaponoil = "Weapon Oil", bandage = "Bandage",
    }
    local ROW_HEIGHT, ROW_WIDTH = 22, CONTENT_W - PAD * 2
    local orderContainer = CreateFrame("Frame", nil, curContent)
    orderContainer:SetPoint("TOPLEFT", curContent, "TOPLEFT", PAD, Y())
    orderContainer:SetWidth(ROW_WIDTH)
    local orderRows = {}

    local function RepositionOrderRows()
        for i, row in ipairs(orderRows) do
            row.frame:ClearAllPoints()
            row.frame:SetPoint("TOPLEFT", orderContainer, "TOPLEFT", 0, -(i-1)*(ROW_HEIGHT+2))
            row.indexText:SetText(i .. ".")
        end
        orderContainer:SetHeight(#orderRows * (ROW_HEIGHT + 2))
    end
    local function SaveOrder()
        local order = {}
        for _, row in ipairs(orderRows) do order[#order+1] = row.key end
        DBSet(order, "buttonOrder")
        Apotheca.ResetLayout()
        Apotheca.UpdateAllButtons()
    end
    local function SwapRows(a, b)
        if a < 1 or b < 1 or a > #orderRows or b > #orderRows then return end
        orderRows[a], orderRows[b] = orderRows[b], orderRows[a]
        RepositionOrderRows()
        SaveOrder()
    end
    local function MakeOrderRow(i, key)
        local f = CreateFrame("Frame", nil, orderContainer)
        f:SetWidth(ROW_WIDTH); f:SetHeight(ROW_HEIGHT)
        local bg = f:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints(); bg:SetColorTexture(0.10, 0.10, 0.18, (i%2==0) and 0.5 or 0.8)
        local idx = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        idx:SetPoint("LEFT", f, "LEFT", 6, 0); idx:SetWidth(20); idx:SetJustifyH("RIGHT")
        idx:SetText(i .. ".")
        local lbl = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        lbl:SetPoint("LEFT", f, "LEFT", 30, 0); lbl:SetText(BUTTON_LABELS[key] or key)
        local up = CreateFrame("Button", nil, f)
        up:SetSize(16,16); up:SetPoint("RIGHT", f, "RIGHT", -22, 0)
        up:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIcon-ScrollUp-Up")
        up:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIcon-ScrollUp-Highlight")
        up:SetScript("OnClick", function()
            for j, row in ipairs(orderRows) do if row.key == key then SwapRows(j, j-1); return end end
        end)
        local down = CreateFrame("Button", nil, f)
        down:SetSize(16,16); down:SetPoint("RIGHT", f, "RIGHT", -4, 0)
        down:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIcon-ScrollDown-Up")
        down:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIcon-ScrollDown-Highlight")
        down:SetScript("OnClick", function()
            for j, row in ipairs(orderRows) do if row.key == key then SwapRows(j, j+1); return end end
        end)
        return { frame = f, key = key, indexText = idx, label = lbl }
    end

    local initOrder = Apotheca.GetButtonOrder()
    for i, key in ipairs(initOrder) do orderRows[#orderRows+1] = MakeOrderRow(i, key) end
    RepositionOrderRows()
    Gap(#initOrder * (ROW_HEIGHT + 2) + 4)

    local resetBtn = CreateFrame("Button", nil, curContent, "UIPanelButtonTemplate")
    resetBtn:SetPoint("TOPLEFT", curContent, "TOPLEFT", PAD, Y())
    resetBtn:SetSize(130, 22); resetBtn:SetText("Reset to Default")
    resetBtn:SetScript("OnClick", function()
        DBSet(nil, "buttonOrder")
        for _, row in ipairs(orderRows) do row.frame:Hide() end
        orderRows = {}
        for i, key in ipairs(Apotheca.GetButtonOrder()) do orderRows[#orderRows+1] = MakeOrderRow(i, key) end
        RepositionOrderRows()
        Apotheca.ResetLayout(); Apotheca.UpdateAllButtons()
    end)
    curH = curH + 26

    refreshCallbacks[#refreshCallbacks + 1] = function()
        for _, row in ipairs(orderRows) do row.frame:Hide() end
        orderRows = {}
        for i, key in ipairs(Apotheca.GetButtonOrder()) do orderRows[#orderRows+1] = MakeOrderRow(i, key) end
        RepositionOrderRows()
    end
    FinalizeTarget()

    -- ════════════════════════════════════════════════════════════
    -- TAB 4: PROFILE & DEBUG
    -- ════════════════════════════════════════════════════════════
    SetTarget(tabFrames["profile"])

    SectionHeader("Profile")
    local charKey = Apotheca.GetCharProfileKey and Apotheca.GetCharProfileKey() or ""
    local charCB = CreateFrame("CheckButton", nil, curContent, "InterfaceOptionsCheckButtonTemplate")
    charCB:SetPoint("TOPLEFT", curContent, "TOPLEFT", PAD, Y())
    charCB.Text:SetText("Use character-specific profile" ..
        (charKey ~= "" and ("  |cff888888(" .. charKey .. ")|r") or ""))
    charCB:SetScript("OnClick", function(self)
        local v = self:GetChecked()
        local key = charKey ~= "" and charKey or (Apotheca.GetCharProfileKey and Apotheca.GetCharProfileKey() or "Global")
        if v == true or v == 1 then Apotheca.SetProfile(key)
        else Apotheca.SetProfile("Global") end
    end)
    refreshCallbacks[#refreshCallbacks + 1] = function()
        charCB:SetChecked(Apotheca.GetActiveProfileKey() ~= "Global")
    end
    charCB:SetChecked(Apotheca.GetActiveProfileKey() ~= "Global")
    curH = curH + 24
    SmallLabel("Settings saved per character and do not affect other characters.")

    SectionHeader("Debug")
    Checkbox("Enable debug mode  |cff888888(items will NOT be consumed)|r",
        function() return DBGet("debug") == true end,
        function(v) Apotheca.SetDebug(v) end)
    FinalizeTarget()

    -- activate first tab
    SwitchTab("general")
end