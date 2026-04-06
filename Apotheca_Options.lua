-- ============================================================
-- Apotheca_Options.lua  —  Configuration Panel
-- Panel frame is registered at PLAYER_LOGIN.
-- Widget content is built LAZILY on first OnShow — nothing runs
-- during the loading screen, eliminating load-time crash risk.
-- ============================================================

-- ── Safe DB accessors ────────────────────────────────────────

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

-- ── RefreshOptions ───────────────────────────────────────────

local refreshCallbacks = {}

function Apotheca.RefreshOptions()
    for _, fn in ipairs(refreshCallbacks) do pcall(fn) end
end

-- ============================================================
-- PANEL SHELL — called from ADDON_LOADED
-- Only creates the bare frame; content is built on first show.
-- ============================================================

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

    -- Called at PLAYER_LOGIN so Settings/InterfaceOptions is ready right now.
    -- Register directly — no nested event frame needed.
    if Settings and Settings.RegisterCanvasLayoutCategory then
        local cat = Settings.RegisterCanvasLayoutCategory(panel, panel.name)
        Settings.RegisterAddOnCategory(cat)
        panel._category = cat
    elseif InterfaceOptions_AddCategory then
        InterfaceOptions_AddCategory(panel)
    end
end

-- ============================================================
-- PANEL CONTENT — built once on first OnShow
-- All widget creation happens here, after the loading screen.
-- ============================================================

function Apotheca.BuildOptionsPanelContent(panel)

    local CONTENT_W = 540
    local PAD       = 20

    -- ── Scroll frame ─────────────────────────────────────────────
    local scrollFrame = CreateFrame("ScrollFrame", "ApothecaScroll", panel)
    scrollFrame:SetPoint("TOPLEFT",     panel, "TOPLEFT",    4,  -4)
    scrollFrame:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -4,  4)

    local content = CreateFrame("Frame", "ApothecaContent", scrollFrame)
    content:SetWidth(CONTENT_W)
    content:SetHeight(400)   -- grows as sections are added
    scrollFrame:SetScrollChild(content)

    scrollFrame:EnableMouseWheel(true)
    scrollFrame:SetScript("OnMouseWheel", function(self, delta)
        local cur = self:GetVerticalScroll()
        local max = self:GetVerticalScrollRange()
        self:SetVerticalScroll(math.max(0, math.min(max, cur - delta * 20)))
    end)

    local totalH = 0
    local function Y() return -totalH end
    local function Gap(h) totalH = totalH + (h or 8) end

    -- ── Section header ───────────────────────────────────────────
    local function SectionHeader(text)
        Gap(12)
        local bg = content:CreateTexture(nil, "BACKGROUND")
        bg:SetPoint("TOPLEFT",  content, "TOPLEFT",  0, Y())
        bg:SetPoint("TOPRIGHT", content, "TOPRIGHT", 0, Y())
        bg:SetHeight(22)
        bg:SetColorTexture(0.12, 0.12, 0.22, 0.90)
        local fs = content:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        fs:SetPoint("LEFT", bg, "LEFT", PAD, 0)
        fs:SetTextColor(0.9, 0.85, 0.45)
        fs:SetText(text)
        totalH = totalH + 22 + 6
    end

    -- ── Small description label ──────────────────────────────────
    local function SmallLabel(text)
        local fs = content:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        fs:SetPoint("TOPLEFT", content, "TOPLEFT", PAD, Y())
        fs:SetTextColor(0.6, 0.6, 0.6)
        fs:SetText(text)
        fs:SetWidth(CONTENT_W - PAD * 2)
        fs:SetJustifyH("LEFT")
        totalH = totalH + fs:GetStringHeight() + 4
    end

    -- ── Checkbox ─────────────────────────────────────────────────
    local function Checkbox(labelText, getter, setter, indent)
        local cb = CreateFrame("CheckButton", nil, content, "InterfaceOptionsCheckButtonTemplate")
        cb:SetPoint("TOPLEFT", content, "TOPLEFT", PAD + (indent or 0), Y())
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
        totalH = totalH + 24
        return cb
    end

    -- ── Radio group ──────────────────────────────────────────────
    local function RadioGroup(options, getter, setter)
        local radios = {}
        Gap(4)
        for _, opt in ipairs(options) do
            local rb = CreateFrame("CheckButton", nil, content, "UIRadioButtonTemplate")
            rb:SetPoint("TOPLEFT", content, "TOPLEFT", PAD + 4, Y())
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
            totalH = totalH + 22
        end
        local function Sync()
            local cur = getter()
            for _, r in ipairs(radios) do r:SetChecked(r.value == cur) end
        end
        Sync()
        refreshCallbacks[#refreshCallbacks + 1] = Sync
        Gap(4)
    end

    -- ── Slider — dark box background so it's visible ─────────────
    local sliderN = 0
    local function Slider(labelText, minV, maxV, step, getter, setter, fmtFn)
        sliderN = sliderN + 1
        local fmt = fmtFn or tostring

        Gap(4)
        -- Dark background box around the entire slider row
        local boxTop = Y()
        -- Will set height after all children are placed
        local box = content:CreateTexture(nil, "BACKGROUND")
        box:SetColorTexture(0.08, 0.08, 0.18, 0.88)

        -- Label
        local lbl = content:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        lbl:SetPoint("TOPLEFT", content, "TOPLEFT", PAD + 4, Y())
        lbl:SetText(labelText)
        totalH = totalH + 18

        -- Slider widget
        local name = "ApothecaSlider" .. sliderN
        local sl   = CreateFrame("Slider", name, content, "OptionsSliderTemplate")
        sl:SetPoint("TOPLEFT", content, "TOPLEFT", PAD + 4, Y())
        sl:SetWidth(200)
        sl:SetMinMaxValues(minV, maxV)
        sl:SetValueStep(step)
        if sl.SetObeyStepOnDrag then sl:SetObeyStepOnDrag(true) end
        sl:SetValue(getter() or minV)

        -- Safe child access — template child names vary by build
        local lowText  = sl.Low  or _G[name .. "Low"]
        local highText = sl.High or _G[name .. "High"]
        if lowText  then lowText:SetText(fmt(minV))  end
        if highText then highText:SetText(fmt(maxV)) end

        -- Current value readout
        local valText = content:CreateFontString(nil, "OVERLAY", "GameFontNormal")
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

        totalH = totalH + 28

        -- Now that we know the height, anchor and size the background box
        local boxH = totalH - (-boxTop) + 6   -- +6 bottom padding
        box:SetPoint("TOPLEFT",  content, "TOPLEFT",  PAD - 4, boxTop - 2)
        box:SetPoint("TOPRIGHT", content, "TOPRIGHT", -(PAD - 4), boxTop - 2)
        box:SetHeight(boxH)

        Gap(8)
    end

    -- ── Dropdown ─────────────────────────────────────────────────
    local ddN = 0
    local function Dropdown(labelText, options, getter, setter)
        ddN = ddN + 1
        Gap(4)
        local lbl = content:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
        lbl:SetPoint("TOPLEFT", content, "TOPLEFT", PAD, Y())
        lbl:SetText(labelText)
        totalH = totalH + 16
        local dd = CreateFrame("Frame", "ApothecaDD" .. ddN, content, "UIDropDownMenuTemplate")
        dd:SetPoint("TOPLEFT", content, "TOPLEFT", PAD - 16, Y())
        UIDropDownMenu_SetWidth(dd, 160)
        local function Init()
            UIDropDownMenu_Initialize(dd, function()
                for _, opt in ipairs(options) do
                    local info   = UIDropDownMenu_CreateInfo()
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
                if opt.value == cur then UIDropDownMenu_SetText(dd, opt.label) ; break end
            end
        end
        Init()
        refreshCallbacks[#refreshCallbacks + 1] = Init
        totalH = totalH + 32
        Gap(4)
    end

    local function Divider()
        Gap(6)
        local t = content:CreateTexture(nil, "BACKGROUND")
        t:SetPoint("TOPLEFT",  content, "TOPLEFT",  PAD, Y())
        t:SetPoint("TOPRIGHT", content, "TOPRIGHT", -PAD, Y())
        t:SetHeight(1)
        t:SetColorTexture(0.35, 0.35, 0.45, 0.6)
        totalH = totalH + 1
        Gap(6)
    end

    -- ════════════════════════════════════════════════════════════
    -- PROFILE
    -- ════════════════════════════════════════════════════════════
    SectionHeader("Profile")

    local charKey = Apotheca.GetCharProfileKey and Apotheca.GetCharProfileKey() or ""
    local charCB  = CreateFrame("CheckButton", nil, content, "InterfaceOptionsCheckButtonTemplate")
    charCB:SetPoint("TOPLEFT", content, "TOPLEFT", PAD, Y())
    charCB.Text:SetText("Use character-specific profile" ..
        (charKey ~= "" and ("  |cff888888(" .. charKey .. ")|r") or ""))
    charCB:SetScript("OnClick", function(self)
        local v   = self:GetChecked()
        local key = charKey ~= "" and charKey or (Apotheca.GetCharProfileKey and Apotheca.GetCharProfileKey() or "Global")
        if v == true or v == 1 then Apotheca.SetProfile(key)
        else Apotheca.SetProfile("Global") end
    end)
    refreshCallbacks[#refreshCallbacks + 1] = function()
        charCB:SetChecked(Apotheca.GetActiveProfileKey() ~= "Global")
    end
    charCB:SetChecked(Apotheca.GetActiveProfileKey() ~= "Global")
    totalH = totalH + 24

    SmallLabel("Settings saved per character and do not affect other characters.")
    Gap(4)

    -- ════════════════════════════════════════════════════════════
    -- GENERAL
    -- ════════════════════════════════════════════════════════════
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
    Gap(4)
    SmallLabel("When at full health/mana, recovery buttons:")
    RadioGroup(
        {
            { value = "BLOCK",      label = "Block usage  |cff888888(silently disable button)|r" },
            { value = "ASK",        label = "Ask first  |cff888888(confirmation popup)|r" },
            { value = "DO_NOTHING", label = "Do nothing  |cff888888(allow free usage)|r" },
        },
        function() return DBGet("preventWasteMode") or "BLOCK" end,
        function(v) DBSet(v, "preventWasteMode") end)

    -- ════════════════════════════════════════════════════════════
    -- VISIBILITY
    -- ════════════════════════════════════════════════════════════
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

    -- ════════════════════════════════════════════════════════════
    -- LAYOUT
    -- ════════════════════════════════════════════════════════════
    SectionHeader("Layout")

    Dropdown("Orientation:",
        {
            { value = "HORIZONTAL", label = "Horizontal" },
            { value = "VERTICAL",   label = "Vertical"   },
        },
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

    -- ════════════════════════════════════════════════════════════
    -- BUTTON ORDER
    -- ════════════════════════════════════════════════════════════
    SectionHeader("Button Order")
    SmallLabel("Drag categories up/down to set the visual order on the bar.")
    Gap(6)

    -- Human-readable labels for each button key.
    local BUTTON_LABELS = {
        mana             = "Mana Potion",
        health           = "Health Potion / Healthstone",
        rune             = "Rune / Battle Res",
        recovery         = "Recovery (Conjured Combo)",
        food             = "Food",
        drink            = "Drink",
        flask            = "Flask",
        battle           = "Battle Elixir",
        guardian         = "Guardian Elixir",
        bufffood         = "Buff Food",
        spiritscroll     = "Spirit Scroll",
        protectionscroll = "Protection Scroll",
        weaponoil        = "Weapon Oil",
        bandage          = "Bandage",
    }

    local ROW_HEIGHT = 22
    local ROW_WIDTH  = CONTENT_W - PAD * 2

    -- Container for all order rows.
    local orderContainer = CreateFrame("Frame", nil, content)
    orderContainer:SetPoint("TOPLEFT", content, "TOPLEFT", PAD, Y())
    orderContainer:SetWidth(ROW_WIDTH)

    local orderRows = {}  -- { frame, key }

    -- Rebuilds visual positions of all rows inside the container.
    local function RepositionOrderRows()
        for i, row in ipairs(orderRows) do
            row.frame:ClearAllPoints()
            row.frame:SetPoint("TOPLEFT", orderContainer, "TOPLEFT", 0, -(i - 1) * (ROW_HEIGHT + 2))
            row.indexText:SetText(i .. ".")
        end
        orderContainer:SetHeight(#orderRows * (ROW_HEIGHT + 2))
    end

    -- Persist the current row order to the profile.
    local function SaveOrder()
        local order = {}
        for _, row in ipairs(orderRows) do
            order[#order + 1] = row.key
        end
        DBSet(order, "buttonOrder")
        Apotheca.ResetLayout()
        Apotheca.UpdateAllButtons()
    end

    -- Swap two rows and save.
    local function SwapRows(indexA, indexB)
        if indexA < 1 or indexB < 1 or indexA > #orderRows or indexB > #orderRows then return end
        orderRows[indexA], orderRows[indexB] = orderRows[indexB], orderRows[indexA]
        RepositionOrderRows()
        SaveOrder()
    end

    -- Build one row.
    local function MakeOrderRow(i, key)
        local f = CreateFrame("Frame", nil, orderContainer)
        f:SetWidth(ROW_WIDTH)
        f:SetHeight(ROW_HEIGHT)

        -- Alternating background for readability
        local bg = f:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        bg:SetColorTexture(0.10, 0.10, 0.18, (i % 2 == 0) and 0.5 or 0.8)

        -- Index number
        local idx = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        idx:SetPoint("LEFT", f, "LEFT", 6, 0)
        idx:SetWidth(20)
        idx:SetJustifyH("RIGHT")
        idx:SetText(i .. ".")

        -- Label
        local lbl = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        lbl:SetPoint("LEFT", f, "LEFT", 30, 0)
        lbl:SetText(BUTTON_LABELS[key] or key)

        -- Up arrow
        local up = CreateFrame("Button", nil, f)
        up:SetWidth(16) ; up:SetHeight(16)
        up:SetPoint("RIGHT", f, "RIGHT", -22, 0)
        up:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIcon-ScrollUp-Up")
        up:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIcon-ScrollUp-Highlight")
        up:SetScript("OnClick", function()
            -- Find current index of this row
            for idx2, row in ipairs(orderRows) do
                if row.key == key then SwapRows(idx2, idx2 - 1) ; return end
            end
        end)

        -- Down arrow
        local down = CreateFrame("Button", nil, f)
        down:SetWidth(16) ; down:SetHeight(16)
        down:SetPoint("RIGHT", f, "RIGHT", -4, 0)
        down:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIcon-ScrollDown-Up")
        down:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIcon-ScrollDown-Highlight")
        down:SetScript("OnClick", function()
            for idx2, row in ipairs(orderRows) do
                if row.key == key then SwapRows(idx2, idx2 + 1) ; return end
            end
        end)

        return { frame = f, key = key, indexText = idx, label = lbl }
    end

    -- Initial build from saved order.
    local initOrder = Apotheca.GetButtonOrder()
    for i, key in ipairs(initOrder) do
        orderRows[#orderRows + 1] = MakeOrderRow(i, key)
    end
    RepositionOrderRows()

    -- Reset button
    Gap(#initOrder * (ROW_HEIGHT + 2) + 4)
    local resetBtn = CreateFrame("Button", nil, content, "UIPanelButtonTemplate")
    resetBtn:SetPoint("TOPLEFT", content, "TOPLEFT", PAD, Y())
    resetBtn:SetWidth(130)
    resetBtn:SetHeight(22)
    resetBtn:SetText("Reset to Default")
    resetBtn:SetScript("OnClick", function()
        DBSet(nil, "buttonOrder")
        -- Rebuild rows from default order
        for _, row in ipairs(orderRows) do row.frame:Hide() end
        orderRows = {}
        local defOrder = Apotheca.GetButtonOrder()
        for i, key in ipairs(defOrder) do
            orderRows[#orderRows + 1] = MakeOrderRow(i, key)
        end
        RepositionOrderRows()
        Apotheca.ResetLayout()
        Apotheca.UpdateAllButtons()
    end)
    totalH = totalH + 26

    -- Refresh callback: rebuild rows when profile changes.
    refreshCallbacks[#refreshCallbacks + 1] = function()
        for _, row in ipairs(orderRows) do row.frame:Hide() end
        orderRows = {}
        local curOrder = Apotheca.GetButtonOrder()
        for i, key in ipairs(curOrder) do
            orderRows[#orderRows + 1] = MakeOrderRow(i, key)
        end
        RepositionOrderRows()
    end

    Gap(8)

    -- ════════════════════════════════════════════════════════════
    -- BUFF FOOD
    -- ════════════════════════════════════════════════════════════
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

    -- ════════════════════════════════════════════════════════════
    -- BUFF FOOD PRIORITY
    -- ════════════════════════════════════════════════════════════
    SectionHeader("Buff Food Priority")
    SmallLabel("Priority order for stat categories (1 = most preferred).")
    Gap(4)

    local STAT_OPTIONS = {
        { value = "healing", label = "Healing"  },
        { value = "mp5",     label = "MP5"       },
        { value = "crit",    label = "Crit"      },
        { value = "stamina", label = "Stamina"   },
    }
    local DEFAULT_PRIO = { "healing", "mp5", "crit", "stamina" }
    for slot = 1, 4 do
        Dropdown("Priority " .. slot .. ":",
            STAT_OPTIONS,
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

    -- ════════════════════════════════════════════════════════════
    -- BUFF FOOD FILTERS
    -- ════════════════════════════════════════════════════════════
    SectionHeader("Buff Food Filters")
    SmallLabel("Which stat categories are considered when scanning bags:")
    Gap(2)
    for _, cat in ipairs({
        { key = "healing", label = "Healing  |cff888888(e.g. Golden Fish Sticks)|r" },
        { key = "mp5",     label = "MP5      |cff888888(e.g. Blackened Sporefish)|r" },
        { key = "crit",    label = "Crit     |cff888888(e.g. Skullfish Soup)|r"      },
        { key = "stamina", label = "Stamina  |cff888888(e.g. Spicy Crawdad)|r"       },
    }) do
        local k = cat.key
        Checkbox(cat.label,
            function() return DBGet("categories", k) ~= false end,
            function(v) DBSet(v, "categories", k) end)
    end

    -- ════════════════════════════════════════════════════════════
    -- ELIXIRS & FLASKS
    -- ════════════════════════════════════════════════════════════
    SectionHeader("Elixirs & Flasks")

    Checkbox("Enable Elixir / Flask buttons",
        function() return DBGet("elixirs", "enabled") ~= false end,
        function(v) DBSet(v, "elixirs", "enabled") end)
    Gap(4)
    SmallLabel("Mode:")
    RadioGroup(
        {
            { value = "AUTO",    label = "Auto  |cff888888(flask if available, otherwise separate elixirs)|r" },
            { value = "FLASK",   label = "Prefer Flask"   },
            { value = "ELIXIRS", label = "Prefer Elixirs" },
        },
        function() return DBGet("elixirs", "mode") or "AUTO" end,
        function(v) DBSet(v, "elixirs", "mode") end)
    Divider()
    Checkbox("Allow lower-tier elixirs as fallback",
        function() return DBGet("elixirs", "allowLower") ~= false end,
        function(v) DBSet(v, "elixirs", "allowLower") end, 8)

    -- ════════════════════════════════════════════════════════════
    -- SCROLLS & WEAPON OIL
    -- ════════════════════════════════════════════════════════════
    SectionHeader("Scrolls & Weapon Oil")
    SmallLabel("These buttons only appear when matching items exist in your bags.")
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

    -- ════════════════════════════════════════════════════════════
    -- BANDAGE
    -- ════════════════════════════════════════════════════════════
    SectionHeader("Bandage")
    SmallLabel("Shows the best available bandage from your bags.")
    Gap(4)
    Checkbox("Enable Bandage button",
        function() return DBGet("bandage", "enabled") ~= false end,
        function(v) DBSet(v, "bandage", "enabled") end)
    SmallLabel("|cff888888Button is automatically disabled while Recently Bandaged is active.|r")
    Gap(4)

    -- ════════════════════════════════════════════════════════════
    -- DEBUG
    -- ════════════════════════════════════════════════════════════
    SectionHeader("Debug")
    Checkbox("Enable debug mode  |cff888888(items will NOT be consumed)|r",
        function() return DBGet("debug") == true end,
        function(v) Apotheca.SetDebug(v) end)

    -- ── Finalise ─────────────────────────────────────────────────
    Gap(24)
    content:SetHeight(totalH)
end