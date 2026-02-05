local mq              = require('mq')
local Icons           = require('mq.ICONS')
local actors          = require('modules.actor')
local perf            = require('modules.performance')
local settings        = require('modules.settings')
local success, Logger = pcall(require, 'lib.Logger')
if not success then
    printf('\arERROR: Write.lua could not be loaded\n%s\ax', Logger)
    return
end

local LNS_UI                         = { _version = '0.1', }

-- gui
local fontScale                      = 1
local iconSize                       = 16
local tempValues                     = {}
local iconAnimation                  = mq.FindTextureAnimation('A_DragItem')
local EQ_ICON_OFFSET                 = 500
local showSettings                   = false
local enteredSafeZone                = false
local settingList                    = {
    "Ask",
    "CanUse",
    "Keep",
    "Ignore",
    "Destroy",
    "Quest",
    "Sell",
    "Tribute",
    "Bank",
}
local tmpRules, tmpClasses, tmpLinks = {}, {}, {}

-- Pagination state
local ITEMS_PER_PAGE                 = 25
local selectedIndex                  = 1

local LNS

function LNS_UI.SetLNS(_LNS)
    LNS = _LNS
end

local function comma_value(amount)
    local formatted = amount
    local k = 0
    while true do
        formatted, k = string.gsub(formatted, "^(-?%d+)(%d%d%d)", '%1,%2')
        if (k == 0) then
            break
        end
    end
    return formatted
end

local function draw_currency_value(icon, value)
    iconAnimation:SetTextureCell(icon - EQ_ICON_OFFSET)
    ImGui.DrawTextureAnimation(iconAnimation, 10, 10)
    ImGui.SameLine()
    ImGui.TextColored(ImVec4(0, 1, 1, 1), " %s ", comma_value(value))
    ImGui.SameLine()
end

local function draw_value(value)
    local val_plat = math.floor(value / 1000)
    local val_gold = math.floor((value - (val_plat * 1000)) / 100)
    local val_silver = math.floor((value - (val_plat * 1000) - (val_gold * 100)) / 10)
    local val_copper = value - (val_plat * 1000) - (val_gold * 100) - (val_silver * 10)

    draw_currency_value(644, val_plat)
    draw_currency_value(645, val_gold)
    draw_currency_value(646, val_silver)
    draw_currency_value(647, val_copper)
end

local ColorList = {
    red = ImVec4(0.9, 0.1, 0.1, 1),
    red2 = ImVec4(0.928, 0.352, 0.035, 1.000),
    pink2 = ImVec4(0.976, 0.518, 0.844, 1.000),
    pink = ImVec4(0.9, 0.4, 0.4, 0.8),
    orange = ImVec4(0.78, 0.20, 0.05, 0.8),
    tangarine = ImVec4(1.000, 0.557, 0.000, 1.000),
    yellow = ImVec4(1, 1, 0, 1),
    yellow2 = ImVec4(0.7, 0.6, 0.1, 0.7),
    white = ImVec4(1, 1, 1, 1),
    blue = ImVec4(0, 0, 1, 1),
    softblue = ImVec4(0.370, 0.704, 1.000, 1.000),
    ['light blue2'] = ImVec4(0.2, 0.9, 0.9, 0.5),
    ['light blue'] = ImVec4(0, 1, 1, 1),
    teal = ImVec4(0, 1, 1, 1),
    green = ImVec4(0, 1, 0, 1),
    green2 = ImVec4(0.01, 0.56, 0.001, 1),
    grey = ImVec4(0.6, 0.6, 0.6, 1),
    purple = ImVec4(0.8, 0.0, 1.0, 1.0),
    purple2 = ImVec4(0.460, 0.204, 1.000, 1.000),
    btn_red = ImVec4(1.0, 0.4, 0.4, 0.4),
    btn_green = ImVec4(0.4, 1.0, 0.4, 0.4),
}

--- Color table for GUI returns ImVec4
---Valud colors are:
---(red, pink, orange, yellow, yellow2, white, blue, softblue, light blue2, light blue,teal, green, green2, grey, purple, btn_red, btn_green)
---@param color_name string  the name of the color you want to return
---@return ImVec4  returns color as an ImVec4 vector
function LNS_UI.Colors(color_name)
    color_name = color_name:lower()
    if (ColorList[color_name]) then
        return ColorList[color_name]
    end
    -- If the color is not found, return white as default
    return ImVec4(1, 1, 1, 1)
end

local Sizes = {
    [0] = 'Tiny',
    [1] = "Small",
    [2] = "Medium",
    [3] = "Large",
    [4] = "Giant",
}
function LNS_UI.Draw_item_tooltip(itemID)
    if settings.TempSettings.NewItemData[itemID] == nil then
        return
    end
    if LNS.NewItems[itemID] == nil then
        settings.TempSettings.NewItemData[itemID] = nil
        settings.TempSettings.Popped[itemID] = nil
        return
    end
    local itemData = settings.TempSettings.NewItemData[itemID]

    local hasStats = false
    local hasResists = false
    local hasBase = false
    local numCombatEfx = itemData.CombatEffects
    local hasCombatEffects = numCombatEfx and numCombatEfx > 0

    for _, stat in pairs({ 'STR', 'AGI', 'STA', 'INT', 'WIS', 'DEX', 'CHA', 'hStr', 'hSta', 'hAgi', 'hInt', 'hWis', 'hDex', 'hCha', }) do
        if itemData[stat] and (itemData[stat] > 0 or itemData[stat] < 0) then
            hasStats = true
            break
        end
    end
    for _, resist in pairs({ 'MR', 'FR', 'DR', 'PR', 'CR', 'svCor', 'hMr', 'hFr', 'hCr', 'hPr', 'hDr', 'hCor', }) do
        if itemData[resist] and (itemData[resist] > 0 or itemData[resist] < 0) then
            hasResists = true
            break
        end
    end
    for _, base in pairs({ 'HP', 'Mana', 'Endurance', 'AC', 'HPRegen', 'EnduranceRegen', 'ManaRegen', }) do
        if itemData[base] and (itemData[base] > 0 or itemData[base] < 0) then
            hasBase = true
            break
        end
    end
    local cursorY = ImGui.GetCursorPosY()

    ImGui.Text("Item: ")
    ImGui.SameLine()
    --local changeColor, isTrash = LNS.ColorItemInfo(item)
    if itemData.CanUse and (itemData.ReqLvl <= mq.TLO.Me.Level()) then
        ImGui.TextColored(LNS_UI.Colors('green'), "%s", itemData.Name)
    else
        ImGui.TextColored(LNS_UI.Colors('tangarine'), "%s", itemData.Name)
    end
    if ImGui.IsItemHovered() then
        ImGui.BeginTooltip()
        ImGui.Text("Click to copy item Name to clipboard")
        ImGui.EndTooltip()
        if ImGui.IsMouseClicked(ImGuiMouseButton.Left) then
            ImGui.LogToClipboard()
            ImGui.LogText(itemData.Name)
            ImGui.LogFinish()
        end
    end
    ImGui.Text("Item ID: ")
    ImGui.SameLine()
    ImGui.TextColored(LNS_UI.Colors('yellow'), "%s", itemData.ID)
    if ImGui.IsItemHovered() then
        ImGui.BeginTooltip()
        ImGui.Text("Click to copy item ID to clipboard")
        ImGui.EndTooltip()
        if ImGui.IsMouseClicked(ImGuiMouseButton.Left) then
            ImGui.LogToClipboard()
            ImGui.LogText(itemData.ID)
            ImGui.LogFinish()
        end
    end
    local cursorX = ImGui.GetCursorPosX()
    local cursorY2 = ImGui.GetCursorPosY()
    ImGui.SetCursorPosY(cursorY)
    ImGui.SetCursorPosX(ImGui.GetWindowWidth() - 60)

    LNS_UI.drawIcon(itemData.Icon or 0, 50)
    ImGui.SetCursorPosX(cursorX)
    ImGui.SetCursorPosY(cursorY2)

    ImGui.Spacing()

    ImGui.Text("Type: ")
    ImGui.SameLine()
    ImGui.TextColored(LNS_UI.Colors('teal'), "%s", itemData.Type)

    ImGui.Text("Size: ")
    ImGui.SameLine()
    ImGui.TextColored(LNS_UI.Colors('yellow'), "%s", Sizes[itemData.Size] or "uknwn")

    local needSameLine = false
    local restrictionString = ''
    --restrictions
    local function buildRestrictions(restriction, restrictionStringBuilder, restrictionString, needSameLine)
        if itemData[restriction] then
            if needSameLine then restrictionStringBuilder = restrictionStringBuilder .. ',' end
            restrictionStringBuilder = restrictionStringBuilder .. restrictionString
            return true
        end
    end
    needSameLine = buildRestrictions('isMagic', restrictionString, 'Magic ', needSameLine)
    needSameLine = buildRestrictions('isNoDrop', restrictionString, 'No Drop ', needSameLine)
    needSameLine = buildRestrictions('isNoRent', restrictionString, 'No Rent ', needSameLine)
    needSameLine = buildRestrictions('isNoTrade', restrictionString, 'No Trade ', needSameLine)
    needSameLine = buildRestrictions('isLore', restrictionString, 'Lore ', needSameLine)
    needSameLine = buildRestrictions('isAttuneable', restrictionString, 'Attuneable ', needSameLine)
    needSameLine = buildRestrictions('isEvolving', restrictionString, 'Evolving ', needSameLine)

    if restrictionString ~= '' then
        ImGui.PushTextWrapPos(ImGui.GetWindowWidth() - 60)
        ImGui.TextColored(LNS_UI.Colors('grey'), "%s", restrictionString)
        ImGui.PopTextWrapPos()
    end

    if ImGui.BeginTable('basicinfo##basicinfo', 2, ImGuiTableFlags.None) then
        ImGui.TableSetupColumn("Info##basicinfo", ImGuiTableColumnFlags.WidthFixed, 60)
        ImGui.TableSetupColumn("Value##basicinfo", ImGuiTableColumnFlags.WidthStretch, 240)
        ImGui.TableNextRow()
        if itemData.ClassList and itemData.ClassList ~= '' then
            ImGui.TableNextColumn()
            ImGui.Text("Classes:")
            ImGui.TableNextColumn()
            ImGui.PushTextWrapPos(ImGui.GetColumnWidth(-1))
            ImGui.TextColored(LNS_UI.Colors('grey'), "%s", itemData.ClassList)
            ImGui.PopTextWrapPos()
        end

        if itemData.RaceList and itemData.RaceList ~= '' then
            ImGui.TableNextColumn()
            ImGui.Text("Races:")
            ImGui.TableNextColumn()
            ImGui.PushTextWrapPos(ImGui.GetColumnWidth(-1))
            ImGui.TextColored(LNS_UI.Colors('grey'), "%s", itemData.RaceList)
            ImGui.PopTextWrapPos()
        end

        if itemData.WornSlots ~= '' then
            ImGui.TableNextColumn()
            ImGui.Text('Slots:')
            ImGui.TableNextColumn()
            ImGui.PushTextWrapPos(ImGui.GetColumnWidth(-1))
            ImGui.TextColored(LNS_UI.Colors('grey'), "%s", itemData.WornSlots)
            ImGui.PopTextWrapPos()
        end
        ImGui.EndTable()
    end

    if ImGui.BeginTable('LVlInfo##lvl', 2, ImGuiTableFlags.None) then
        ImGui.TableSetupColumn("Level Info##lvlinfo", ImGuiTableColumnFlags.WidthFixed, 150)
        ImGui.TableSetupColumn("Value##lvlvalue", ImGuiTableColumnFlags.WidthFixed, 150)

        ImGui.TableNextRow()
        if itemData.ReqLvl > 0 then
            ImGui.TableNextColumn()
            ImGui.Text('Req Lvl: ')
            ImGui.SameLine()
            local reqColorLabel = itemData.ReqLvl <= mq.TLO.Me.Level() and 'green' or 'tangarine'
            ImGui.TextColored(LNS_UI.Colors(reqColorLabel), "%s", itemData.ReqLvl)
        end
        if itemData.RecLvl and itemData.RecLvl > 0 then
            ImGui.TableNextColumn()
            ImGui.Text('Rec Lvl: ')
            ImGui.SameLine()
            ImGui.TextColored(LNS_UI.Colors('softblue'), "%s", itemData.RecLvl)
        end

        ImGui.TableNextColumn()
        ImGui.Text("Weight: ")
        ImGui.SameLine()
        ImGui.TextColored(LNS_UI.Colors('pink2'), "%s", itemData.Weight)

        if itemData.NumSlots and itemData.NumSlots > 0 then
            ImGui.TableNextColumn()
            ImGui.Text("Slots: ")
            ImGui.SameLine()
            ImGui.TextColored(LNS_UI.Colors('yellow'), "%s", itemData.NumSlots)

            -- Size Capacity
            if itemData.SizeCapacity and itemData.SizeCapacity > 0 then
                ImGui.TableNextColumn()
                ImGui.Text("Bag Size:")
                ImGui.SameLine()
                ImGui.TextColored(LNS_UI.Colors('teal'), "%s", Sizes[itemData.SizeCapacity] or 'Unknown')
            end
        end

        if itemData.MaxStack > 1 then
            ImGui.TableNextColumn()
            ImGui.Text("Qty: ")
            ImGui.SameLine()
            ImGui.TextColored(LNS_UI.Colors('yellow'), "%s", itemData.Stack)
            ImGui.SameLine()
            ImGui.Text(" / ")
            ImGui.SameLine()
            ImGui.TextColored(LNS_UI.Colors('teal'), "%s", itemData.MaxStack)
        end
        ImGui.EndTable()
    end

    if ImGui.BeginTable("DamageStats", 2, ImGuiTableFlags.None) then
        ImGui.TableSetupColumn("Stat##dmg", ImGuiTableColumnFlags.WidthFixed, 150)
        ImGui.TableSetupColumn("Value##dmg", ImGuiTableColumnFlags.WidthFixed, 150)
        ImGui.TableNextRow()

        if itemData.BaseDMG > 0 then
            ImGui.TableNextColumn()
            ImGui.Text("Dmg: ")
            ImGui.SameLine()
            ImGui.TextColored(LNS_UI.Colors('pink2'), "%s", itemData.BaseDMG or 'NA')
        end
        if itemData.Delay > 0 then
            ImGui.TableNextColumn()

            ImGui.Text(" Dly: ")
            ImGui.SameLine()
            ImGui.TextColored(LNS_UI.Colors('yellow'), "%s", itemData.Delay or 'NA')
        end
        if itemData.BonusDmgType ~= 'None' then
            ImGui.TableNextColumn()
            ImGui.Text("Bonus %s Dmg ", itemData.BonusDmgType)
            -- ImGui.SameLine()
            -- ImGui.TextColored(LNS_UI.Colors('pink2'), "%s", itemData.ElementalDamage or 'NA')
            ImGui.TableNextColumn()
        end

        local function ModifierText(modifier, label, color, pattern, value)
            if itemData[modifier] > 0 then
                ImGui.TableNextColumn()
                ImGui.Text(label)
                ImGui.SameLine()
                ImGui.TextColored(LNS_UI.Colors(color), pattern, value)
            end
        end
        ModifierText('Haste', 'Haste: ', 'green', '%s%%', itemData.Haste)
        ModifierText('DmgShield', 'Dmg Shield: ', 'yellow', '%s', itemData.DmgShield)
        ModifierText('DmgShieldMit', 'DS Mit: ', 'teal', '%s', itemData.DmgShieldMit)
        ModifierText('Avoidance', 'Avoidance: ', 'green', '%s', itemData.Avoidance)
        ModifierText('DotShield', 'DoT Shielding: ', 'yellow', '%s', itemData.DotShield)
        ModifierText('Accuracy', 'Accuracy: ', 'green', '%s', itemData.Accuracy)
        ModifierText('SpellShield', 'Spell Shield: ', 'teal', '%s', itemData.SpellShield)
        ModifierText('HealAmount', 'Heal Amt: ', 'pink2', '%s', itemData.HealAmount)
        ModifierText('SpellDamage', 'Spell Dmg: ', 'teal', '%s', itemData.SpellDamage)
        ModifierText('StunResist', 'Stun Res: ', 'green', '%s', itemData.StunResist)
        ModifierText('Clairvoyance', 'Claiyvoyance: ', 'green', '%s', itemData.Clairvoyance)
        -- DPS Ratio
        if itemData.BaseDMG > 0 and itemData.Delay > 0 then
            ImGui.TableNextColumn()
            ImGui.Text("Ratio: ")
            ImGui.SameLine()
            ImGui.TextColored(LNS_UI.Colors('teal'), "%0.3f", (itemData.Delay / (itemData.BaseDMG or 1)) or 0)
        end
        ImGui.EndTable()
    end

    ImGui.Spacing()

    -- base stats

    if hasBase then
        ImGui.SeparatorText('Stats')
        -- base
        if ImGui.BeginTable("BaseStats##itemBaseStats", 2, ImGuiTableFlags.None) then
            ImGui.TableSetupColumn("Stat", ImGuiTableColumnFlags.WidthFixed, 150)
            ImGui.TableSetupColumn("Value", ImGuiTableColumnFlags.WidthFixed, 150)
            ImGui.TableNextRow()
            if itemData.AC > 0 then
                ImGui.TableNextColumn()
                ImGui.Text(" AC: ")
                ImGui.SameLine()
                ImGui.TextColored(LNS_UI.Colors('teal'), " %s", itemData.AC)
                ImGui.TableNextRow()
            end

            if itemData.HP and itemData.HP > 0 then
                ImGui.TableNextColumn()

                ImGui.Text("HPs: ")
                ImGui.SameLine()
                ImGui.TextColored(LNS_UI.Colors('pink2'), "%s", itemData.HP)
            end
            if itemData.Mana and itemData.Mana > 0 then
                ImGui.TableNextColumn()
                ImGui.Text("Mana: ")
                ImGui.SameLine()
                ImGui.TextColored(LNS_UI.Colors('teal'), "%s", itemData.Mana)
            end
            if itemData.Endurance and itemData.Endurance > 0 then
                ImGui.TableNextColumn()
                ImGui.Text("End: ")
                ImGui.SameLine()
                ImGui.TextColored(LNS_UI.Colors('yellow'), "%s", itemData['Endurance'])
            end
            if itemData.HPRegen > 0 then
                ImGui.TableNextColumn()
                ImGui.Text("HP Regen: ")
                ImGui.SameLine()
                ImGui.TextColored(LNS_UI.Colors('pink2'), "%s", itemData.HPRegen)
            end
            if itemData.ManaRegen > 0 then
                ImGui.TableNextColumn()
                ImGui.Text("Mana Regen: ")
                ImGui.SameLine()
                ImGui.TextColored(LNS_UI.Colors('teal'), "%s", itemData.ManaRegen)
            end
            if itemData.EnduranceRegen > 0 then
                ImGui.TableNextColumn()
                ImGui.Text("Endurance Regen: ")
                ImGui.SameLine()
                ImGui.TextColored(LNS_UI.Colors('yellow'), "%s", itemData.EnduranceRegen)
            end

            ImGui.EndTable()
        end
    end
    -- stats
    if hasStats then
        -- ImGui.SeparatorText('Stats')
        if ImGui.BeginTable("Stats##itemStats", 2, ImGuiTableFlags.None) then
            ImGui.TableSetupColumn("Stat##stats", ImGuiTableColumnFlags.WidthFixed, 150)
            ImGui.TableSetupColumn("Value##stats", ImGuiTableColumnFlags.WidthFixed, 150)

            ImGui.TableNextRow()
            local function DrawStatValue(stat, label, hStat)
                if itemData[stat] and itemData[stat] > 0 then
                    ImGui.TableNextColumn()

                    ImGui.Text(label)
                    ImGui.SameLine()
                    ImGui.TextColored(LNS_UI.Colors('tangerine'), "%s", itemData[stat])
                    if itemData[hStat] > 0 then
                        ImGui.SameLine()
                        ImGui.TextColored(LNS_UI.Colors('Yellow'), " + %s", itemData[hStat])
                    end
                end
            end
            DrawStatValue('STR', 'STR: ', 'hStr')
            DrawStatValue('AGI', 'AGI: ', 'hAgi')
            DrawStatValue('STA', 'STA: ', 'hSta')
            DrawStatValue('INT', 'INT: ', 'hInt')
            DrawStatValue('WIS', 'WIS: ', 'hWis')
            DrawStatValue('DEX', 'DEX: ', 'hDex')
            DrawStatValue('CHA', 'CHA: ', 'hCha')
            ImGui.EndTable()
        end
    end
    -- resists
    if hasResists then
        ImGui.SeparatorText('Resists')
        if ImGui.BeginTable("Resists##itemResists", 2, ImGuiTableFlags.None) then
            ImGui.TableSetupColumn("Stat##res", ImGuiTableColumnFlags.WidthFixed, 150)
            ImGui.TableSetupColumn("Value##res", ImGuiTableColumnFlags.WidthFixed, 150)

            ImGui.TableNextRow()
            local function DrawResistValue(resist, label, hResist)
                if itemData[resist] and itemData[resist] > 0 then
                    ImGui.TableNextColumn()
                    ImGui.Text(label)
                    ImGui.SameLine()
                    ImGui.TextColored(LNS_UI.Colors('green'), "%s", itemData[resist])
                    if itemData[hResist] > 0 then
                        ImGui.SameLine()
                        ImGui.TextColored(LNS_UI.Colors('Yellow'), " + %s", itemData[hResist])
                    end
                end
            end
            DrawResistValue('MR', 'MR:\t', 'hMr')
            DrawResistValue('FR', 'FR:\t', 'hFr')
            DrawResistValue('DR', 'DR:\t', 'hDr')
            DrawResistValue('PR', 'PR:\t', 'hPr')
            DrawResistValue('CR', 'CR:\t', 'hCr')
            ImGui.EndTable()
        end
    end

    -- Augments
    if itemData.AugSlots > 0 then
        -- ImGui.Dummy(10, 10)
        ImGui.SeparatorText('Augments')
        for i = 1, itemData.AugSlots do
            local augSlotName = itemData['AugSlot' .. i] or 'none'
            local augTypeName = itemData['AugType' .. i] or 'none'
            if augSlotName ~= 'none' or augTypeName ~= 21 then
                ImGui.Text("Slot %s: ", i)
                ImGui.SameLine()
                ImGui.PushTextWrapPos(290)
                ImGui.TextColored(LNS_UI.Colors('teal'), "%s Type (%s)", (augSlotName ~= 'none' and augSlotName or 'Empty'), augTypeName)
                ImGui.PopTextWrapPos()
            end
        end
    end

    if hasCombatEffects or itemData.Clicky or itemData.Spelleffect ~= '' or itemData.Worn ~= 'none' or
        itemData.Focus1 ~= 'none' or itemData.Focus2 ~= 'none' then
        -- ImGui.Dummy(10, 10)

        ImGui.SeparatorText('Efx')
        if itemData.Clicky then
            ImGui.Dummy(10, 10)
            ImGui.Text("Charges: ")
            ImGui.SameLine()
            ImGui.TextColored(LNS_UI.Colors('yellow'), "%s", itemData.Charges)
            ImGui.Text("Clicky Spell: ")
            ImGui.SameLine()
            ImGui.PushTextWrapPos(290)
            ImGui.TextColored(LNS_UI.Colors('teal'), "%s", itemData.Clicky)
            if ImGui.IsItemHovered() then
                if ImGui.IsMouseClicked(ImGuiMouseButton.Left) then
                    mq.TLO.Spell(itemData.ClickyID).Inspect()
                end
            end
            if itemData.ClickyDesc ~= '' then
                ImGui.Indent(5)
                ImGui.TextColored(LNS_UI.Colors('yellow'), itemData.ClickyDesc)
                ImGui.Unindent(5)
            end
            ImGui.PopTextWrapPos()
        end

        if (itemData.Spelleffect ~= "" and
                not ((itemData.Spelleffect == itemData.Clicky) or (itemData.Spelleffect == itemData.Worn) or
                    (itemData.Focus1 == itemData.Spelleffect) or (itemData.Focus2 == itemData.Spelleffect))) then
            ImGui.Dummy(10, 10)
            local effectTypeLabel = itemData.EffectType ~= 'None' and itemData.EffectType or "Spell"
            ImGui.Text("%s Effect: ", effectTypeLabel)
            ImGui.SameLine()
            ImGui.PushTextWrapPos(290)
            ImGui.TextColored(LNS_UI.Colors('teal'), "%s", itemData.Spelleffect)
            if ImGui.IsItemHovered() then
                if ImGui.IsMouseClicked(ImGuiMouseButton.Left) then
                    mq.TLO.Spell(itemData.SpellID).Inspect()
                end
            end
            if itemData.SpellDesc ~= '' then
                ImGui.Indent(5)
                ImGui.TextColored(LNS_UI.Colors('yellow'), itemData.SpellDesc)
                ImGui.Unindent(5)
            end
            ImGui.PopTextWrapPos()
        end

        if itemData.Worn ~= 'none' then
            ImGui.Dummy(10, 10)
            ImGui.Text("Worn Effect: ")
            ImGui.SameLine()
            ImGui.PushTextWrapPos(290)
            ImGui.TextColored(LNS_UI.Colors('teal'), "%s", itemData.Worn)
            if ImGui.IsItemHovered() then
                if ImGui.IsMouseClicked(ImGuiMouseButton.Left) then
                    mq.TLO.Spell(itemData.WornID).Inspect()
                end
            end
            if itemData.WornDesc ~= '' then
                ImGui.Indent(5)
                ImGui.TextColored(LNS_UI.Colors('yellow'), itemData.WornDesc)
                ImGui.Unindent(5)
            end
            ImGui.PopTextWrapPos()
        end

        if itemData.Focus1 ~= 'none' then
            ImGui.Dummy(10, 10)
            ImGui.Text("Focus Effect: ")
            ImGui.SameLine()
            ImGui.PushTextWrapPos(290)
            ImGui.TextColored(LNS_UI.Colors('teal'), "%s", itemData.Focus1)
            if ImGui.IsItemHovered() then
                if ImGui.IsMouseClicked(ImGuiMouseButton.Left) then
                    mq.TLO.Spell(itemData.Focus1ID).Inspect()
                end
            end
            if itemData.Focus1Desc ~= '' then
                ImGui.Indent(5)
                ImGui.TextColored(LNS_UI.Colors('yellow'), itemData.Focus1Desc)
                ImGui.Unindent(5)
            end
            ImGui.PopTextWrapPos()
        end

        if itemData.Focus2 ~= 'none' then
            ImGui.Dummy(10, 10)
            ImGui.Text("Focus2 Effect: ")
            ImGui.SameLine()
            ImGui.PushTextWrapPos(290)
            ImGui.TextColored(LNS_UI.Colors('teal'), "%s", itemData.Focus2)
            if ImGui.IsItemHovered() then
                if ImGui.IsMouseClicked(ImGuiMouseButton.Left) then
                    mq.TLO.Spell(itemData.Focus2ID).Inspect()
                end
            end
            if itemData.Focus2Desc ~= '' then
                ImGui.Indent(5)
                ImGui.TextColored(LNS_UI.Colors('yellow'), itemData.Focus2Desc)
                ImGui.Unindent(5)
            end
            ImGui.PopTextWrapPos()
        end
    end

    if itemData.isEvolving then
        ImGui.SeparatorText('Evolving Info')
        ImGui.Text("Evolving Level: ")
        ImGui.SameLine()
        ImGui.TextColored(LNS_UI.Colors("tangarine"), "%d", itemData.EvolvingLevel)

        ImGui.Text("Evolving Max Level: ")
        ImGui.SameLine()
        ImGui.TextColored(LNS_UI.Colors("teal"), "%d", itemData.EvolvingMaxLevel)

        ImGui.Text("Evolving Exp: ")
        ImGui.SameLine()
        ImGui.TextColored(LNS_UI.Colors("yellow"), "%0.2f%%", itemData.EvolvingExpPct)
    end

    ImGui.SeparatorText('Value')
    ImGui.Dummy(10, 10)
    ImGui.Text("Value: ")
    ImGui.SameLine()
    draw_value(itemData.Value or 0)
    if itemData.TributeValue > 0 then
        ImGui.Text("Tribute Value: ")
        ImGui.SameLine()
        ImGui.TextColored(LNS_UI.Colors('yellow'), "%s", itemData.TributeValue)
    end
end

function LNS_UI.Draw_item_info_window(itemID)
    if settings.TempSettings.NewItemData[itemID] == nil then
        settings.TempSettings.Popped[itemID] = nil
        return
    end
    local itemData = settings.TempSettings.NewItemData[itemID]
    local itemName = itemData.Name

    ImGui.SetNextWindowSize(320, 0.0, ImGuiCond.Always)
    local mouseX, mouseY = ImGui.GetMousePos()
    ImGui.SetNextWindowPos((mouseX - 30), (mouseY - 5), ImGuiCond.FirstUseEver)
    local open, show = ImGui.Begin(string.format("%s##iteminfo_%s", itemName, itemID), true)
    if not open then
        show = false
        settings.TempSettings.Popped[itemID] = nil
        if LNS.NewItems[itemID] == nil then
            settings.TempSettings.NewItemData[itemID] = nil
        end
    end
    if show then
        LNS_UI.Draw_item_tooltip(itemID)
        if ImGui.IsWindowFocused() then
            if ImGui.IsKeyPressed(ImGuiKey.Escape) then
                show = false
                settings.TempSettings.Popped[itemID] = nil
                if LNS.NewItems[itemID] == nil then
                    settings.TempSettings.NewItemData[itemID] = nil
                end
            end
        end
    end
    ImGui.End()
end

function LNS_UI.renderMissingItemsTables()
    ImGui.Text("Imported Global Rules")
    if ImGui.BeginTable("ImportedData##Global", 4, bit32.bor(ImGuiTableFlags.ScrollY, ImGuiTableFlags.Borders), ImVec2(0.0, 300)) then
        ImGui.TableSetupColumn("Item ID##g", ImGuiTableColumnFlags.WidthFixed, 40)
        ImGui.TableSetupColumn("Item Name##g", ImGuiTableColumnFlags.WidthStretch, 100)
        ImGui.TableSetupColumn("Item Rule##g", ImGuiTableColumnFlags.WidthFixed, 60)
        ImGui.TableSetupColumn("Item Classes##g", ImGuiTableColumnFlags.WidthFixed, 60)
        ImGui.TableHeadersRow()
        ImGui.TableNextRow()
        for _, v in ipairs(settings.TempSettings.SortedMissingGlobalNames or {}) do
            if LNS.GlobalItemsMissing[v.id] ~= nil then
                ImGui.TableNextColumn()
                ImGui.TextColored(ImVec4(1.000, 0.557, 0.000, 1.000), "%s", LNS.GlobalItemsMissing[v.id].item_id)
                ImGui.TableNextColumn()
                ImGui.PushStyleColor(ImGuiCol.Text, ImVec4(0.370, 0.704, 1.000, 1.000))
                if ImGui.Selectable(string.format("%s", LNS.GlobalItemsMissing[v.id].item_name), false) then
                    settings.TempSettings.ModifyItemRule = true
                    settings.TempSettings.ModifyItemName = LNS.GlobalItemsMissing[v.id].item_name
                    settings.TempSettings.ModifyItemLink = nil
                    settings.TempSettings.ModifyItemID = LNS.GlobalItemsMissing[v.id].item_id
                    settings.TempSettings.ModifyItemTable = "Global_Items"
                    settings.TempSettings.ModifyClasses = LNS.GlobalItemsMissing[v.id].item_classes
                    settings.TempSettings.ModifyItemSetting = LNS.GlobalItemsMissing[v.id].item_rule
                end
                ImGui.PopStyleColor()
                ImGui.TableNextColumn()
                ImGui.Text(LNS.GlobalItemsMissing[v.id].item_rule or 'Unknown')
                ImGui.TableNextColumn()
                ImGui.Text(LNS.GlobalItemsMissing[v.id].item_classes or 'Unknown')
            end
        end

        ImGui.EndTable()
    end
    ImGui.Separator()
    ImGui.Text("Imported Normal Rules")
    if ImGui.BeginTable("ImportedData##Normal", 4, bit32.bor(ImGuiTableFlags.ScrollY, ImGuiTableFlags.Borders), ImVec2(0.0, 300)) then
        ImGui.TableSetupColumn("Item ID##n", ImGuiTableColumnFlags.WidthFixed, 40)
        ImGui.TableSetupColumn("Item Name##n", ImGuiTableColumnFlags.WidthStretch, 100)
        ImGui.TableSetupColumn("Item Rule##n", ImGuiTableColumnFlags.WidthFixed, 60)
        ImGui.TableSetupColumn("Item Classes##n", ImGuiTableColumnFlags.WidthFixed, 60)
        ImGui.TableHeadersRow()
        ImGui.TableNextRow()

        for _, v in ipairs(settings.TempSettings.SortedMissingNormalNames or {}) do
            if LNS.NormalItemsMissing[v.id] ~= nil then
                ImGui.TableNextColumn()
                ImGui.TextColored(ImVec4(1.000, 0.557, 0.000, 1.000), "%s", LNS.NormalItemsMissing[v.id].item_id)
                ImGui.TableNextColumn()
                ImGui.PushStyleColor(ImGuiCol.Text, ImVec4(0.370, 0.704, 1.000, 1.000))
                if ImGui.Selectable(string.format("%s", LNS.NormalItemsMissing[v.id].item_name), false) then
                    settings.TempSettings.ModifyItemRule = true
                    settings.TempSettings.ModifyItemName = LNS.NormalItemsMissing[v.id].item_name
                    settings.TempSettings.ModifyItemLink = nil
                    settings.TempSettings.ModifyItemID = LNS.NormalItemsMissing[v.id].item_id
                    settings.TempSettings.ModifyItemTable = "Normal_Items"
                    settings.TempSettings.ModifyClasses = LNS.NormalItemsMissing[v.id].item_classes
                    settings.TempSettings.ModifyItemSetting = LNS.NormalItemsMissing[v.id].item_rule
                end
                ImGui.PopStyleColor()
                ImGui.TableNextColumn()
                ImGui.Text(LNS.NormalItemsMissing[v.id].item_rule or 'Unknown')
                ImGui.TableNextColumn()
                ImGui.Text(LNS.NormalItemsMissing[v.id].item_classes or 'Unknown')
            end
        end

        ImGui.EndTable()
    end
end

function LNS_UI.renderImportDBWindow()
    if not settings.TempSettings.ShowImportDB then
        return
    end
    local openImport, drawImport = ImGui.Begin('Loot N Scoot Import DB', true)
    if not openImport then
        settings.TempSettings.ShowImportDB = false
        drawImport = false
    end

    if drawImport then
        ImGui.TextWrapped(
            'This will import the current Loot N Scoot Database from the Old version..\n Specify the name of the file ex. LootRules_Project_Lazarus.db.\nThis file can be found in your MQ/Config folder.')
        ImGui.Spacing()
        ImGui.Separator()
        ImGui.SetNextItemWidth(100)
        settings.TempSettings.ImportDBFileName = ImGui.InputText('Import File Name', settings.TempSettings.ImportDBFileName)
        settings.TempSettings.ImportDBFilePath = string.format("%s/%s", mq.configDir, settings.TempSettings.ImportDBFileName)
        if ImGui.Button('Import Database') then
            printf('Importing Database from: %s', settings.TempSettings.ImportDBFilePath)
            settings.TempSettings.DoImport = true
        end
        ImGui.SameLine()
        if ImGui.Button('Cancel') then
            settings.TempSettings.ShowImportDB = false
        end
        ImGui.Spacing()
        ImGui.Separator()
        LNS_UI.renderMissingItemsTables()
    end

    ImGui.End()
end

function LNS_UI.renderHelpWindow()
    if not settings.TempSettings.ShowHelp then
        return
    end
    local openHelp, drawHelp = ImGui.Begin('Loot N Scoot Help', true)
    if not openHelp then
        settings.TempSettings.ShowHelp = false
        drawHelp = false
    end

    if drawHelp then
        fontScale = ImGui.SliderFloat("Font Scale", fontScale, 1, 2)
        ImGui.SetWindowFontScale(fontScale)
        ImGui.TextWrapped('Loot N Scoot is a plugin for MQ2 that automates looting, selling, banking, and tributing items on EverQuest EMU Servers.')
        ImGui.Separator()
        if ImGui.CollapsingHeader('Commands:##LNSHelp') then
            ImGui.SeparatorText("Startup Commands")

            if ImGui.BeginTable("CommandsTable", 2, bit32.bor(ImGuiTableFlags.Borders, ImGuiTableFlags.Resizable)) then
                ImGui.TableSetupColumn("Command")
                ImGui.TableSetupColumn("Description")
                ImGui.TableHeadersRow()
                ImGui.TableNextRow()
                ImGui.TableNextColumn()
                ImGui.TextWrapped('/lua run lootnscoot once')
                ImGui.TableNextColumn()
                ImGui.TextWrapped('Run LNS once through the loot cycle.')
                ImGui.TableNextColumn()
                ImGui.TextWrapped('/lua run lootnscoot standalone')
                ImGui.TableNextColumn()
                ImGui.TextWrapped('Run LNS in the background.')
                ImGui.TableNextColumn()
                ImGui.TextWrapped('/lua run lootnscoot tributestuff')
                ImGui.TableNextColumn()
                ImGui.TextWrapped('Tribute items to the Targeted Tribute Master then Close.')
                ImGui.TableNextColumn()
                ImGui.TextWrapped('/lua run lootnscoot sellstuff')
                ImGui.TableNextColumn()
                ImGui.TextWrapped('Sell items to the Targeted Vendor then Close.')
                ImGui.TableNextColumn()
                ImGui.TextWrapped('/lua run lootnscoot bankstuff')
                ImGui.TableNextColumn()
                ImGui.TextWrapped('Bank items to the Targeted Banker then Close.')
                ImGui.TableNextColumn()
                ImGui.TextWrapped('/lua run lootnscoot cleanup')
                ImGui.TableNextColumn()
                ImGui.TextWrapped('Destroy items in your inventory flagged Destroy then Close.')
                ImGui.TableNextColumn()
                ImGui.TextWrapped('/lua run lootnscoot directed')
                ImGui.TableNextColumn()
                ImGui.TextWrapped('Run LNS in Directed Mode, you will loot items when told by the directing script.')
                ImGui.TableNextColumn()
                ImGui.TextWrapped('/lua run lootnscoot directed scriptPath')
                ImGui.TableNextColumn()
                ImGui.TextWrapped('Run LNS in Directed Mode with a specific script path if using a bundled version, you will loot items when told by the directing script.')
                ImGui.EndTable()
            end
            ImGui.Spacing()


            ImGui.Spacing()

            ImGui.SeparatorText("Basic Commands##LNSHelp")

            if ImGui.BeginTable("BasicCommandsTable", 2, bit32.bor(ImGuiTableFlags.Borders, ImGuiTableFlags.Resizable)) then
                ImGui.TableSetupColumn("Command")
                ImGui.TableSetupColumn("Description")
                ImGui.TableHeadersRow()
                ImGui.TableNextRow()
                ImGui.TableNextColumn()
                ImGui.TextWrapped('/lns sellstuff')
                ImGui.TableNextColumn()
                ImGui.TextWrapped('Sell items to the Targeted Vendor.')
                ImGui.TableNextColumn()
                ImGui.TextWrapped('/lns bankstuff')
                ImGui.TableNextColumn()
                ImGui.TextWrapped('Bank items in your inventory with the Targeted Banker.')
                ImGui.TableNextColumn()
                ImGui.TextWrapped('/lns tributestuff')
                ImGui.TableNextColumn()
                ImGui.TextWrapped('Tribute items to the Targeted Tribute Master.')
                ImGui.TableNextColumn()
                ImGui.TextWrapped('/lns restock')
                ImGui.TableNextColumn()
                ImGui.TextWrapped('Restock items from the Targeted Vendor.')
                ImGui.TableNextColumn()
                ImGui.TextWrapped('/lns cleanup')
                ImGui.TableNextColumn()
                ImGui.TextWrapped('Destroy items in your inventory flagged Destroy.')
                ImGui.TableNextColumn()
                ImGui.TextWrapped('/lns loot')
                ImGui.TableNextColumn()
                ImGui.TextWrapped('Loot corpses in range.')
                ImGui.TableNextColumn()
                ImGui.TextWrapped('/lns set settingname [on|off|value]')
                ImGui.TableNextColumn()
                ImGui.TextWrapped('Set a setting in LNS. Use "on" or "off" for boolean settings, or a value for numeric settings.')
                ImGui.TableNextColumn()
                ImGui.TextWrapped('/lns pause')
                ImGui.TableNextColumn()
                ImGui.TextWrapped('Pause LNS, this will stop all looting and processing until resumed.')
                ImGui.TableNextColumn()
                ImGui.TextWrapped('/lns resume')
                ImGui.TableNextColumn()
                ImGui.TextWrapped('Resume LNS after it has been paused.')
                ImGui.TableNextColumn()
                ImGui.TextWrapped('/lns corpsereset')
                ImGui.TableNextColumn()
                ImGui.TextWrapped('Reset the list of Already Looted Corpses in the current zone.')
                ImGui.TableNextColumn()
                ImGui.TextWrapped('/lns help')
                ImGui.TableNextColumn()
                ImGui.TextWrapped('Show this help window.')
                ImGui.EndTable()
            end
            ImGui.Spacing()

            ImGui.SeparatorText("Item Commands##LNSHelp")
            if ImGui.BeginTable("ItemCommandsTable", 2, bit32.bor(ImGuiTableFlags.Borders, ImGuiTableFlags.Resizable)) then
                ImGui.TableSetupColumn("Command")
                ImGui.TableSetupColumn("Description")
                ImGui.TableHeadersRow()
                ImGui.TableNextRow()

                ImGui.TableNextColumn()
                ImGui.TextWrapped('/lns [sell|keep|quest|bank|ignore|destroy]')

                ImGui.TableNextColumn()
                ImGui.TextWrapped('Set the item on your cursor to the specified rule.')

                ImGui.TableNextColumn()
                ImGui.TextWrapped('/lns [sell|keep|quest|bank|ignore|destroy] itemName')

                ImGui.TableNextColumn()
                ImGui.TextWrapped(
                    [[Attempt to set the item with the specified name to the specified rule.
Items with duplicate names in the db may not pick the right one.
Recommend using the item lookup table in those cases.]])
                ImGui.TableNextColumn()

                ImGui.TextWrapped('/lns buy itemname [qty]')
                ImGui.TableNextColumn()
                ImGui.TextWrapped(
                    [[Attempt to add the item to the BuyItemsTable for restocking.
If qty is not specified, it defaults to 1.
If the item is already in the table, it will update the quantity.]])
                ImGui.TableNextColumn()
                ImGui.TextWrapped('/lns quest|#')
                ImGui.TableNextColumn()
                ImGui.TextWrapped('Set the item on your cursor to the Quest rule with the specified quantity. If no quantity is specified.')
                ImGui.TableNextColumn()
                ImGui.TextWrapped("/lns [personalitem|globalitem|normalitem] rule itemname [qty]")
                ImGui.TableNextColumn()
                ImGui.TextWrapped(
                    [[Add an item rule to the Items database.
The item will be added to the proper database table based on which is issued normalitem, personalitem, or globalitem.
Qty is only applied if the rule is quest. if an item is on the cursor you can omitt the item name and it will use the item on the cursor.
If the item is already in the database, it will update the quantity.]])
                ImGui.TableNextColumn()
                ImGui.TextWrapped('/lns find itemName')
                ImGui.TableNextColumn()
                ImGui.TextWrapped(
                    [[Search for an item by name in the LNS database.
This will return the item info for the first 20 matching items found.]])
                ImGui.EndTable()
            end
        end


        ImGui.Spacing()

        if ImGui.CollapsingHeader('Toggles:##LNSHelp') then
            if ImGui.BeginTable("TogglesTable##LNSHelp", 2, bit32.bor(ImGuiTableFlags.Borders, ImGuiTableFlags.Resizable)) then
                ImGui.TableSetupColumn("Toggle")
                ImGui.TableSetupColumn("Description")
                ImGui.TableHeadersRow()
                ImGui.TableNextRow()
                for k, v in pairs(settings.Settings) do
                    if type(v) == 'boolean' and not settings.SettingsNoDraw[k] then
                        ImGui.TableNextColumn()
                        ImGui.TextWrapped(k)
                        ImGui.TableNextColumn()
                        ImGui.TextWrapped(settings.Tooltips[k] or "No tooltip available")
                    end
                end
                ImGui.EndTable()
            end
        end

        ImGui.Spacing()

        if ImGui.CollapsingHeader('Settings:##LNSHelp') then
            if ImGui.BeginTable("SettingsTable##LNSHelp", 2, bit32.bor(ImGuiTableFlags.Borders, ImGuiTableFlags.Resizable)) then
                ImGui.TableSetupColumn("Setting")
                ImGui.TableSetupColumn("Description")
                ImGui.TableHeadersRow()
                ImGui.TableNextRow()
                for k, v in pairs(settings.Settings) do
                    if type(v) ~= 'boolean' and not settings.SettingsNoDraw[k] then
                        ImGui.TableNextColumn()
                        ImGui.TextWrapped(k)
                        ImGui.TableNextColumn()
                        ImGui.TextWrapped(settings.Tooltips[k] or "No tooltip available")
                    end
                end
                ImGui.EndTable()
            end
        end
    end
    ImGui.End()
end

function LNS_UI.drawIcon(iconID, iconSize)
    if iconSize == nil then iconSize = 16 end
    if iconID ~= nil then
        iconAnimation:SetTextureCell(iconID - 500)
        ImGui.DrawTextureAnimation(iconAnimation, iconSize, iconSize)
    end
end

---comment
---@param label string Menu Item Display Label
---@param setting_name string Setting Name in settings.Settings
---@param value boolean Setting Value in settings.Settings
---@param tooltip string|nil Optional Tooltip Text
function LNS_UI.DrawMenuItemToggle(label, setting_name, value, tooltip)
    local changed = false
    changed, value = ImGui.MenuItem(label, nil, value)
    if changed then
        settings.TempSettings.NeedSaveToggle = true
        settings.Settings[setting_name] = value
    end
    if tooltip then
        if ImGui.IsItemHovered() then
            ImGui.BeginTooltip()
            ImGui.Text(tooltip)
            ImGui.EndTooltip()
        end
    end
end

function LNS_UI.guiExport()
    -- Define a new menu element function
    local function customMenu()
        ImGui.PushID('LootNScootMenu_Imported')
        if ImGui.BeginMenu('Loot N Scoot##imported') then
            -- Add menu items here
            if ImGui.BeginMenu('Toggles') then
                -- Add menu items here
                LNS_UI.DrawMenuItemToggle("DoLoot", "DoLoot", settings.Settings.DoLoot, "Enable or disable looting of corpses.")
                LNS_UI.DrawMenuItemToggle("GlobalLootOn", "GlobalLootOn", settings.Settings.GlobalLootOn, "Enable or disable global looting across all characters.")
                LNS_UI.DrawMenuItemToggle("CombatLooting", "CombatLooting", settings.Settings.CombatLooting, "Enable or disable looting while in combat.")
                LNS_UI.DrawMenuItemToggle("LootNoDrop", "LootNoDrop", settings.Settings.LootNoDrop, "Enable or disable looting of No Drop items.")
                LNS_UI.DrawMenuItemToggle("LootNoDropNew", "LootNoDropNew", settings.Settings.LootNoDropNew, "Enable or disable looting of No Drop items with new rules.")
                LNS_UI.DrawMenuItemToggle("LootForage", "LootForage", settings.Settings.LootForage, "Enable or disable looting of foraged items.")
                LNS_UI.DrawMenuItemToggle("LootQuest", "LootQuest", settings.Settings.LootQuest, "Enable or disable looting of quest items.")
                LNS_UI.DrawMenuItemToggle("TributeKeep", "TributeKeep", settings.Settings.TributeKeep, "Enable or disable keeping tribute items.")
                LNS_UI.DrawMenuItemToggle("BankTradeskills", "BankTradeskills", settings.Settings.BankTradeskills, "Enable or disable banking of tradeskill items.")
                LNS_UI.DrawMenuItemToggle("StackableOnly", "StackableOnly", settings.Settings.StackableOnly, "Enable or disable looting of only stackable items.")
                ImGui.Separator()
                LNS_UI.DrawMenuItemToggle("AlwaysEval", "AlwaysEval", settings.Settings.AlwaysEval, "Enable or disable always evaluating items.")
                LNS_UI.DrawMenuItemToggle("AddNewSales", "AddNewSales", settings.Settings.AddNewSales, "Enable or disable adding new sales items.")
                LNS_UI.DrawMenuItemToggle("AddNewTributes", "AddNewTributes", settings.Settings.AddNewTributes, "Enable or disable adding new tribute items.")
                LNS_UI.DrawMenuItemToggle("AutoTagSell", "AutoTag", settings.Settings.AutoTag, "Enable or disable automatic tagging of items for selling.")
                LNS_UI.DrawMenuItemToggle("AutoRestock", "AutoRestock", settings.Settings.AutoRestock, "Enable or disable automatic restocking of items.")
                ImGui.Separator()
                LNS_UI.DrawMenuItemToggle("DoDestroy", "DoDestroy", settings.Settings.DoDestroy, "Enable or disable destruction of items.")
                LNS_UI.DrawMenuItemToggle("AlwaysDestroy", "AlwaysDestroy", settings.Settings.AlwaysDestroy, "Enable or disable always destroying items.")
                ImGui.EndMenu()
            end

            local gCmd = (settings.GroupChannel or 'dgge'):find("dg") and "dgg" or settings.GroupChannel
            if string.find(gCmd, 'dg') then
                gCmd = '/' .. gCmd
            elseif string.find(gCmd, 'bc') then
                gCmd = '/' .. gCmd .. ' /'
            end
            if ImGui.BeginMenu('Group Commands##imported') then
                -- Add menu items here
                if ImGui.MenuItem("Sell Stuff##group") then
                    mq.cmdf(string.format('%s /multiline ; /target %s; /timed 5; /lns sellstuff', gCmd, mq.TLO.Target.CleanName()))
                end

                if ImGui.MenuItem('Restock Items##group') then
                    mq.cmdf(string.format('%s /multiline ; /target %s; /timed 5; /lns restock', gCmd, mq.TLO.Target.CleanName()))
                end

                if ImGui.MenuItem("Tribute Stuff##group") then
                    mq.cmdf(string.format('%s /multiline ; /target %s; /timed 5; /lns tributestuff', gCmd, mq.TLO.Target.CleanName()))
                end

                if ImGui.MenuItem("Bank##group") then
                    mq.cmdf(string.format('%s /multiline ; /target %s; /timed 5; /lns bank', gCmd, mq.TLO.Target.CleanName()))
                end

                if ImGui.MenuItem("Cleanup##group") then
                    mq.cmdf(string.format('%s /multiline ; /target %s; /timed 5; /lns cleanup', gCmd, mq.TLO.Target.CleanName()))
                end

                ImGui.EndMenu()
            end

            if ImGui.MenuItem('Sell Stuff##') then
                mq.cmdf('/lns sellstuff')
            end

            if ImGui.MenuItem('Restock##') then
                mq.cmdf('/lns restock')
            end

            if ImGui.MenuItem('Tribute Stuff##') then
                mq.cmdf('/lns tributestuff')
            end

            if ImGui.MenuItem('Bank##') then
                mq.cmdf('/lns bank')
            end

            if ImGui.MenuItem('Cleanup##') then
                mq.cmdf('/lns cleanup')
            end

            ImGui.EndMenu()
        end
        ImGui.PopID()
    end
    -- Add the custom menu element function to the importGUIElements table
    if LNS.guiLoot ~= nil then LNS.guiLoot.importGUIElements[1] = customMenu end
end

function LNS_UI.drawYesNo(decision)
    if decision then
        LNS_UI.drawIcon(4494, 20) -- Checkmark icon
    else
        LNS_UI.drawIcon(4495, 20) -- X icon
    end
end

function LNS_UI.drawNewItemsTable()
    local itemsToRemove = {}
    if LNS.NewItems == nil then LNS.showNewItem = false end
    if LNS.NewItemsCount <= 0 then
        LNS.showNewItem = false
    else
        if ImGui.BeginTable('##newItemTable2', 2, bit32.bor(
                ImGuiTableFlags.Borders, ImGuiTableFlags.ScrollX,
                ImGuiTableFlags.Reorderable, ImGuiTableFlags.SizingStretchProp,
                ImGuiTableFlags.RowBg)) then
            -- Setup Table Columns
            ImGui.TableSetupColumn('Item', ImGuiTableColumnFlags.WidthStretch, 120)
            ImGui.TableSetupColumn('Rule', ImGuiTableColumnFlags.WidthFixed, 130)
            ImGui.TableHeadersRow()
            ImGui.TableNextRow()

            -- Iterate Over New Items
            for idx, itemID in ipairs(settings.TempSettings.NewItemIDs or {}) do
                local item = LNS.NewItems[itemID]

                -- Ensure tmpRules has a default value
                if itemID == nil or item == nil then
                    Logger.Error(LNS.guiLoot.console, "Invalid item in NewItems table: %s", itemID)
                    LNS.NewItemsCount = 0
                    break
                end
                ImGui.PushID(itemID)
                tmpRules[itemID] = tmpRules[itemID] or item.Rule or settingList[1]
                if LNS.tempLootAll == nil then
                    LNS.tempLootAll = {}
                end
                if LNS.tempGlobalRule == nil then
                    LNS.tempGlobalRule = {}
                end
                -- Item Name and Link
                ImGui.TableNextColumn()

                ImGui.Indent(2)

                LNS_UI.drawIcon(item.Icon, 20)
                if ImGui.IsItemHovered() then
                    ImGui.BeginTooltip()
                    LNS_UI.Draw_item_tooltip(itemID)
                    ImGui.Spacing()
                    ImGui.Separator()
                    ImGui.Text("Left Click Icon to open In-Game Details window")
                    ImGui.Text("Right Click to Pop Open Details window.")
                    ImGui.EndTooltip()
                    if ImGui.IsMouseClicked(0) then
                        mq.cmdf('/executelink %s', item.Link)
                    elseif ImGui.IsItemClicked(ImGuiMouseButton.Right) then
                        settings.TempSettings.Popped[itemID] = true
                    end
                end
                ImGui.SameLine()
                ImGui.Text(item.Name or "Unknown")
                ImGui.SameLine()
                ImGui.Text('Corpse ID: %s', item.CorpseID)

                ImGui.Unindent(2)
                ImGui.Indent(2)

                if ImGui.BeginTable("SellData", 3, bit32.bor(ImGuiTableFlags.Borders,
                        ImGuiTableFlags.Reorderable)) then
                    ImGui.TableSetupColumn('Value', ImGuiTableColumnFlags.WidthFixed, 150)
                    ImGui.TableSetupColumn('Tribute', 0)
                    ImGui.TableSetupColumn('Stacks', 0)
                    ImGui.TableHeadersRow()
                    ImGui.TableNextRow()
                    -- Sell Price
                    ImGui.TableNextColumn()
                    if item.SellPrice ~= '0 pp 0 gp 0 sp 0 cp' then
                        ImGui.Text(item.SellPrice or "0")
                    end
                    ImGui.TableNextColumn()
                    ImGui.Text('%s', item.Tribute or '0')
                    ImGui.TableNextColumn()
                    ImGui.Text("%s", item.MaxStacks > 0 and item.MaxStacks or "No")
                    ImGui.EndTable()
                end

                ImGui.Unindent(2)

                -- Classes
                -- ImGui.Indent(2)

                -- ImGui.TableNextColumn()
                if ImGui.BeginTable("ClassesTable", 6, bit32.bor(ImGuiTableFlags.Borders,
                        ImGuiTableFlags.Reorderable)) then
                    ImGui.TableSetupColumn('Classes', ImGuiTableColumnFlags.WidthStretch, 80)
                    ImGui.TableSetupColumn('Loot All', ImGuiTableColumnFlags.WidthFixed, 50)
                    ImGui.TableSetupColumn('NoDrop', ImGuiTableColumnFlags.WidthFixed, 30)
                    ImGui.TableSetupColumn('Lore', ImGuiTableColumnFlags.WidthFixed, 30)
                    ImGui.TableSetupColumn("Aug", ImGuiTableColumnFlags.WidthFixed, 30)
                    ImGui.TableSetupColumn('TS', ImGuiTableColumnFlags.WidthFixed, 30)

                    ImGui.TableHeadersRow()
                    ImGui.TableNextRow()
                    ImGui.TableNextColumn()


                    ImGui.SetNextItemWidth(ImGui.GetColumnWidth(-1) - 8)
                    tmpClasses[itemID] = ImGui.InputText('##Classes' .. itemID, tmpClasses[itemID] or item.Classes)
                    if ImGui.IsItemHovered() then
                        ImGui.SetTooltip("Classes: %s", item.Classes)
                    end

                    ImGui.TableNextColumn()
                    LNS.tempLootAll[itemID] = ImGui.Checkbox('All', LNS.tempLootAll[itemID] or false)

                    --     -- ImGui.Unindent(2)
                    --     ImGui.EndTable()
                    -- end

                    -- -- ImGui.Indent(2)
                    -- if ImGui.BeginTable('ItemFlags', 4, bit32.bor(ImGuiTableFlags.Borders,
                    --         ImGuiTableFlags.Reorderable)) then
                    --     ImGui.TableSetupColumn('NoDrop', ImGuiTableColumnFlags.WidthFixed, 30)
                    --     ImGui.TableSetupColumn('Lore', ImGuiTableColumnFlags.WidthFixed, 30)
                    --     ImGui.TableSetupColumn("Aug", ImGuiTableColumnFlags.WidthFixed, 30)
                    --     ImGui.TableSetupColumn('TS', ImGuiTableColumnFlags.WidthFixed, 30)
                    --     ImGui.TableHeadersRow()
                    --     ImGui.TableNextRow()
                    -- Flags (NoDrop, Lore, Augment, TradeSkill)
                    ImGui.TableNextColumn()
                    LNS_UI.drawYesNo(item.NoDrop)
                    ImGui.TableNextColumn()
                    LNS_UI.drawYesNo(item.Lore)
                    ImGui.TableNextColumn()
                    LNS_UI.drawYesNo(item.Aug)
                    ImGui.TableNextColumn()
                    LNS_UI.drawYesNo(item.Tradeskill)
                    ImGui.EndTable()
                end
                -- ImGui.Unindent(2)

                -- Rule
                ImGui.TableNextColumn()

                item.selectedIndex = item.selectedIndex or LNS.getRuleIndex(item.Rule, settingList)

                ImGui.PushStyleVar(ImGuiStyleVar.FramePadding, ImVec2(1, 1))
                local update
                local totalWidth = ImGui.GetColumnWidth(-1)
                local colWidth = totalWidth / 3 -- Calculate 1/3 of the width for alignment

                for i, setting in ipairs(settingList) do
                    --Calculate which "sub-column" we are in (0, 1, or 2)
                    local colIdx = (i - 1) % 3

                    if colIdx > 0 then
                        --This snaps the button to exactly 33% or 66% of the column width
                        ImGui.SameLine(colIdx * colWidth)
                    end

                    -- We use colWidth - spacing to ensure the button doesn't bleed into the next slot
                    ImGui.SetNextItemWidth(colWidth - ImGui.GetStyle().ItemSpacing.x)
                    update = LNS_UI.drawRuleRadioButton(setting, i, item.selectedIndex)

                    if update then
                        item.selectedIndex = i
                        tmpRules[itemID] = setting
                    end
                end
                ImGui.PopStyleVar()

                -- ImGui.PushStyleVar(ImGuiStyleVar.FramePadding, ImVec2(1, 1))
                -- local update
                -- ImGui.SetNextItemWidth(ImGui.GetColumnWidth(-1))
                -- for idx, setting in ipairs(settingList) do
                --     update = LNS_UI.drawRuleRadioButton(setting, idx, item.selectedIndex)
                --     if update then
                --         item.selectedIndex = idx
                --         tmpRules[itemID] = setting
                --     end
                --     if idx % 3 ~= 0 then ImGui.SameLine() end
                -- end
                -- ImGui.PopStyleVar()

                ImGui.Spacing()
                if LNS.tempGlobalRule[itemID] == nil then
                    LNS.tempGlobalRule[itemID] = settings.Settings.AlwaysGlobal
                end
                ImGui.Indent(10)
                LNS.tempGlobalRule[itemID] = ImGui.Checkbox('Global Rule', LNS.tempGlobalRule[itemID])
                ImGui.Unindent(10)
                ImGui.Indent(35)
                -- ImGui.SetCursorPosX(ImGui.GetCursorPosX() + (ImGui.GetColumnWidth(-1) / 6))
                ImGui.PushStyleColor(ImGuiCol.Button, ImVec4(0.040, 0.294, 0.004, 1.000))
                if ImGui.Button('Save Rule') then
                    local classes = LNS.tempLootAll[itemID] and "All" or tmpClasses[itemID]
                    local ruleTable = LNS.tempGlobalRule[itemID] and "GlobalItems" or "NormalItems"
                    LNS.enterNewItemRuleInfo({
                        ID = itemID,
                        RuleType = ruleTable,
                        ItemName = item.Name,
                        Rule = tmpRules[itemID],
                        Classes = classes,
                        Link = item.Link,
                        CorpseID = item.CorpseID,
                    })
                    LNS.addRule(itemID, ruleTable, tmpRules[itemID], classes, item.Link)

                    table.remove(settings.TempSettings.NewItemIDs, idx)
                    table.insert(itemsToRemove, itemID)
                    Logger.Debug(LNS.guiLoot.console, "\agSaving\ax --\ayNEW ITEM RULE\ax-- Item: \at%s \ax(ID:\ag %s\ax) with rule: \at%s\ax, classes: \at%s\ax, link: \at%s\ax",
                        item.Name, itemID, tmpRules[itemID], tmpClasses[itemID], item.Link)
                end
                ImGui.Unindent(35)
                ImGui.PopStyleColor()
                ImGui.PopID()
            end

            ImGui.EndTable()
        end
    end

    -- Remove Processed Items
    for _, itemID in ipairs(itemsToRemove) do
        LNS.NewItems[itemID]    = nil
        tmpClasses[itemID]      = nil
        tmpRules[itemID]        = nil
        tmpLinks[itemID]        = nil
        LNS.tempLootAll[itemID] = nil
    end

    -- Update New Items Count
    LNS.NewItemsCount = #settings.TempSettings.NewItemIDs or 0
end

function LNS_UI.SafeText(write_value)
    local tmpValue = write_value
    if write_value == nil then
        tmpValue = "N/A"
    end
    if tostring(write_value) == 'true' then
        ImGui.TextColored(ImVec4(0.0, 1.0, 0.0, 1.0), "True")
    elseif tostring(write_value) == 'false' or tostring(write_value) == '0' or tostring(write_value) == 'None' then
    elseif tmpValue == "N/A" then
        ImGui.Indent()
        ImGui.TextColored(ImVec4(1.0, 0.0, 0.0, 1.0), tmpValue)
        ImGui.Unindent()
    else
        ImGui.Indent()
        ImGui.Text(tmpValue)
        ImGui.Unindent()
    end
end

settings.TempSettings.SelectedItems = {}
function LNS_UI.drawTabbedTable(label)
    local varSub = label .. 'Items'

    if ImGui.BeginTabItem(varSub .. "##") then
        if settings.TempSettings.varSub == nil then
            settings.TempSettings.varSub = {}
        end
        if settings.TempSettings[varSub .. 'Classes'] == nil then
            settings.TempSettings[varSub .. 'Classes'] = {}
        end
        local sizeX, _ = ImGui.GetContentRegionAvail()
        ImGui.PushStyleColor(ImGuiCol.ChildBg, ImVec4(0.0, 0.6, 0.0, 0.1))
        if ImGui.BeginChild("Add Rule Drop Area", ImVec2(sizeX, 40), ImGuiChildFlags.Border) then
            ImGui.TextDisabled("Drop Item Here to Add to a %s Rule", label)
            if ImGui.IsWindowHovered() and ImGui.IsMouseClicked(0) then
                if mq.TLO.Cursor() ~= nil then
                    local itemCursor = mq.TLO.Cursor
                    LNS.addToItemDB(mq.TLO.Cursor)
                    settings.TempSettings.ModifyItemRule = true
                    settings.TempSettings.ModifyItemName = itemCursor.Name()
                    settings.TempSettings.ModifyItemLink = itemCursor.ItemLink('CLICKABLE')() or "NULL"
                    settings.TempSettings.ModifyItemID = itemCursor.ID()
                    settings.TempSettings.ModifyItemTable = label .. "_Items"
                    settings.TempSettings.ModifyClasses = LNS[varSub .. 'Classes'][itemCursor.ID()] or "All"
                    settings.TempSettings.ModifyItemSetting = "Ask"
                    settings.TempSettings['Search' .. varSub] = itemCursor.Name()
                    tempValues = {}
                    mq.cmdf("/autoinv")
                end
            end
        end
        ImGui.EndChild()
        ImGui.PopStyleColor()
        ImGui.Spacing()
        ImGui.Spacing()
        ImGui.PushID(varSub .. 'Search')
        ImGui.SetNextItemWidth(180)
        settings.TempSettings['Search' .. varSub] = ImGui.InputTextWithHint("Search", "Search by Name or Rule",
            settings.TempSettings['Search' .. varSub] or '')
        ImGui.PopID()
        if ImGui.IsItemHovered(ImGuiHoveredFlags.DelayShort) and mq.TLO.Cursor() then
            settings.TempSettings['Search' .. varSub] = mq.TLO.Cursor()
            mq.cmdf("/autoinv")
        end

        ImGui.SameLine()

        if ImGui.SmallButton(Icons.MD_DELETE_SWEEP) then
            settings.TempSettings['Search' .. varSub] = nil
        end
        if ImGui.IsItemHovered() then ImGui.SetTooltip("Clear Search") end

        local col = 4
        col = math.max(4, math.floor((ImGui.GetContentRegionAvail() or 0) / 140))
        local colCount = col + (col % 4)
        if colCount % 4 ~= 0 then
            if (colCount - 1) % 4 == 0 then
                colCount = colCount - 1
            elseif (colCount - 2) % 4 == 0 then
                colCount = colCount - 2
            elseif (colCount - 3) % 4 == 0 then
                colCount = colCount - 3
            end
        end

        local filteredItems = {}
        local filteredItemKeys = {}
        for id, rule in pairs(LNS[varSub .. 'Rules']) do
            if LNS.SearchLootTable(settings.TempSettings['Search' .. varSub], LNS.ItemNames[id], rule) then
                local iconID = LNS.ItemIcons[id] or 0
                local itemLink = ''

                if iconID == 0 then
                    if LNS.ALLITEMS[id] then
                        iconID = LNS.ALLITEMS[id].Icon or 0
                        LNS.ItemIcons[id] = iconID
                    end
                end
                if LNS.ALLITEMS[id] then
                    itemLink = LNS.ALLITEMS[id].Link
                elseif LNS.ItemLinks[id] then
                    itemLink = LNS.ItemLinks[id]
                end

                table.insert(filteredItems, {
                    id = id,
                    data = LNS.ItemNames[id],
                    setting = LNS[varSub .. 'Rules'][id],
                    icon = iconID,
                    link = itemLink,
                })
                table.insert(filteredItemKeys, LNS.ItemNames[id])
            end
        end
        table.sort(filteredItems, function(a, b) return a.data < b.data end)

        local totalItems = #filteredItems
        local totalPages = math.ceil(totalItems / ITEMS_PER_PAGE)

        -- Clamp CurrentPage to valid range
        LNS.CurrentPage = math.max(1, math.min(LNS.CurrentPage, totalPages))
        if totalPages > 0 then
            -- Navigation buttons
            if ImGui.Button(Icons.FA_BACKWARD) then
                LNS.CurrentPage = 1
            end
            ImGui.SameLine()
            if ImGui.ArrowButton("##Previous", ImGuiDir.Left) and LNS.CurrentPage > 1 then
                LNS.CurrentPage = LNS.CurrentPage - 1
            end
            ImGui.SameLine()
            ImGui.Text(("Page %d of %d"):format(LNS.CurrentPage, totalPages))
            ImGui.SameLine()
            if ImGui.ArrowButton("##Next", ImGuiDir.Right) and LNS.CurrentPage < totalPages then
                LNS.CurrentPage = LNS.CurrentPage + 1
            end
            ImGui.SameLine()
            if ImGui.Button(Icons.FA_FORWARD) then
                LNS.CurrentPage = totalPages
            end
            ImGui.SameLine()
            ImGui.SetNextItemWidth(80)
            if ImGui.BeginCombo("Max Items", tostring(ITEMS_PER_PAGE)) then
                for i = 10, 100, 10 do
                    if ImGui.Selectable(tostring(i), ITEMS_PER_PAGE == i) then
                        ITEMS_PER_PAGE = i
                    end
                end
                ImGui.EndCombo()
            end
        end

        -- Calculate the range of items to display
        local startIndex = (LNS.CurrentPage - 1) * ITEMS_PER_PAGE + 1
        local endIndex = math.min(startIndex + ITEMS_PER_PAGE - 1, totalItems)

        if ImGui.CollapsingHeader('BulkSet') then
            ImGui.Indent(2)
            ImGui.Text("Set all items to the same rule")
            ImGui.SetNextItemWidth(100)
            ImGui.PushID("BulkSet")
            if settings.TempSettings.BulkRule == nil then
                settings.TempSettings.BulkRule = settingList[1]
            end
            if ImGui.BeginCombo("Rule", settings.TempSettings.BulkRule) then
                for i, setting in ipairs(settingList) do
                    local isSelected = settings.TempSettings.BulkRulee == setting
                    if ImGui.Selectable(setting, isSelected) then
                        settings.TempSettings.BulkRule = setting
                    end
                end
                ImGui.EndCombo()
            end
            ImGui.SameLine()
            if settings.TempSettings.BulkRule == 'Quest' then
                ImGui.SetNextItemWidth(100)
                if settings.TempSettings.BulkQuestAmount == nil then
                    settings.TempSettings.BulkQuestAmount = 0
                end
                settings.TempSettings.BulkQuestAmount = ImGui.InputInt("Amount", settings.TempSettings.BulkQuestAmount, 1, 1)
                ImGui.SameLine()
            end
            ImGui.SetNextItemWidth(100)
            if settings.TempSettings.BulkClasses == nil then
                settings.TempSettings.BulkClasses = "All"
            end
            settings.TempSettings.BulkClasses = ImGui.InputTextWithHint("Classes", "who can loot or all ex: shm clr dru", settings.TempSettings.BulkClasses)

            ImGui.SameLine()
            ImGui.SetNextItemWidth(100)
            if settings.TempSettings.BulkSetTable == nil then
                settings.TempSettings.BulkSetTable = label .. "_Rules"
            end
            if ImGui.BeginCombo("Table", settings.TempSettings.BulkSetTable) then
                for i, v in ipairs(settings.TableListRules) do
                    if ImGui.Selectable(v, settings.TempSettings.BulkSetTable == v) then
                        settings.TempSettings.BulkSetTable = v
                    end
                end
                ImGui.EndCombo()
            end

            ImGui.PopID()

            if ImGui.Button(Icons.FA_CHECK .. " All") then
                for i = startIndex, endIndex do
                    local itemID = filteredItems[i].id
                    settings.TempSettings.SelectedItems[itemID] = true
                end
            end

            ImGui.SameLine()
            if ImGui.Button("Clear Selected") then
                for id, selected in pairs(settings.TempSettings.SelectedItems) do
                    settings.TempSettings.SelectedItems[id] = false
                end
            end

            ImGui.PushStyleColor(ImGuiCol.Button, ImVec4(0.4, 1.0, 0.4, 0.4))
            if ImGui.Button("Set Selected") then
                settings.TempSettings.BulkSet = {}
                for itemID, isSelected in pairs(settings.TempSettings.SelectedItems) do
                    if isSelected then
                        local tmpRule = "Quest"
                        if settings.TempSettings.BulkRule == 'Quest' then
                            if settings.TempSettings.BulkQuestAmount > 0 then
                                tmpRule = string.format("Quest|%s", settings.TempSettings.BulkQuestAmount)
                            end
                        else
                            tmpRule = settings.TempSettings.BulkRule
                        end
                        settings.TempSettings.BulkSet[itemID] = {
                            Rule = tmpRule,
                            Link = LNS.ItemLinks[itemID] or "NULL",
                        }
                    end
                end
                settings.TempSettings.doBulkSet = true
            end
            ImGui.PopStyleColor()


            ImGui.SameLine()

            ImGui.PushStyleColor(ImGuiCol.Button, ImVec4(1.0, 0.4, 0.4, 0.4))
            if ImGui.Button("Delete Selected") then
                settings.TempSettings.BulkSet = {}
                for itemID, isSelected in pairs(settings.TempSettings.SelectedItems) do
                    if isSelected then
                        settings.TempSettings.BulkSet[itemID] = { Rule = "Delete", Link = "NULL", }
                    end
                end
                settings.TempSettings.doBulkSet = true
                settings.TempSettings.bulkDelete = true
            end
            ImGui.PopStyleColor()
            ImGui.Unindent(2)
        end

        if ImGui.BeginTable(label .. " Items", colCount, bit32.bor(ImGuiTableFlags.Borders, ImGuiTableFlags.Resizable, ImGuiTableFlags.ScrollY), ImVec2(0.0, 0.0)) then
            for i = 1, colCount / 4 do
                ImGui.TableSetupColumn(Icons.FA_CHECK, ImGuiTableColumnFlags.WidthFixed, 30)
                ImGui.TableSetupColumn("Item", ImGuiTableColumnFlags.WidthStretch)
                ImGui.TableSetupColumn("Rule", ImGuiTableColumnFlags.WidthFixed, 40)
                ImGui.TableSetupColumn('Classes', ImGuiTableColumnFlags.WidthFixed, 90)
            end
            ImGui.TableSetupScrollFreeze(colCount, 1)
            ImGui.TableHeadersRow()
            ImGui.TableNextRow()

            if LNS[label .. 'ItemsRules'] ~= nil then
                for i = startIndex, endIndex do
                    local itemID = filteredItems[i].id
                    local item = filteredItems[i].data
                    local setting = filteredItems[i].setting
                    local iconID = filteredItems[i].icon
                    local itemLink = filteredItems[i].link

                    ImGui.PushID(itemID)
                    local classes = LNS[label .. 'ItemsClasses'][itemID] or "All"
                    local itemName = LNS.ItemNames[itemID] or item.Name
                    if LNS.SearchLootTable(settings.TempSettings['Search' .. varSub], item, setting) then
                        ImGui.TableNextColumn()
                        ImGui.PushID(itemID .. "_checkbox")
                        if settings.TempSettings.SelectedItems[itemID] == nil then
                            settings.TempSettings.SelectedItems[itemID] = false
                        end
                        local isSelected = settings.TempSettings.SelectedItems[itemID]
                        isSelected = ImGui.Checkbox("##select", isSelected)
                        settings.TempSettings.SelectedItems[itemID] = isSelected
                        ImGui.PopID()
                        ImGui.TableNextColumn()

                        ImGui.Indent(2)
                        local btnColor, btnText = ImVec4(0.0, 0.6, 0.0, 0.4), Icons.FA_PENCIL
                        if LNS.ItemIcons[itemID] == nil then
                            btnColor, btnText = ImVec4(0.6, 0.0, 0.0, 0.4), Icons.MD_CLOSE
                        end
                        ImGui.PushStyleColor(ImGuiCol.Button, btnColor)
                        if ImGui.SmallButton(btnText) then
                            settings.TempSettings.ModifyItemRule = true
                            settings.TempSettings.ModifyItemName = itemName
                            settings.TempSettings.ModifyItemLink = itemLink
                            settings.TempSettings.ModifyItemID = itemID
                            settings.TempSettings.ModifyItemTable = label .. "_Items"
                            settings.TempSettings.ModifyClasses = classes
                            settings.TempSettings.ModifyItemSetting = setting
                            tempValues = {}
                        end
                        ImGui.PopStyleColor()

                        ImGui.SameLine()
                        if iconID then
                            LNS_UI.drawIcon(iconID, iconSize * fontScale) -- icon
                        else
                            LNS_UI.drawIcon(4493, iconSize * fontScale)   -- icon
                        end
                        if ImGui.IsItemHovered() then
                            LNS_UI.DrawRuleToolTip(itemName, setting, classes:upper())
                            if ImGui.IsMouseClicked(0) then
                                mq.cmdf('/executelink %s', itemLink)
                            elseif ImGui.IsItemClicked(ImGuiMouseButton.Right) then
                                settings.TempSettings.Popped[itemID] = true
                            end
                        end
                        ImGui.SameLine(0, 0)

                        ImGui.Text(itemName)
                        if ImGui.IsItemHovered() then
                            LNS_UI.DrawRuleToolTip(itemName, setting, classes:upper())
                            if ImGui.IsMouseClicked(0) then
                                mq.cmdf('/executelink %s', itemLink)
                            elseif ImGui.IsItemClicked(ImGuiMouseButton.Right) then
                                settings.TempSettings.Popped[itemID] = true
                            end
                        end
                        ImGui.Unindent(2)
                        ImGui.TableNextColumn()
                        ImGui.Indent(2)
                        LNS_UI.drawSettingIcon(setting)

                        if ImGui.IsItemHovered() then
                            LNS_UI.DrawRuleToolTip(itemName, setting, classes:upper())
                            if ImGui.IsMouseClicked(0) then
                                mq.cmdf('/executelink %s', itemLink)
                            elseif ImGui.IsItemClicked(ImGuiMouseButton.Right) then
                                settings.TempSettings.Popped[itemID] = true
                            end
                        end
                        ImGui.Unindent(2)
                        ImGui.TableNextColumn()
                        ImGui.Indent(2)
                        if classes ~= 'All' then
                            ImGui.TextColored(ImVec4(0, 1, 1, 0.8), classes:upper())
                        else
                            ImGui.TextDisabled(classes:upper())
                        end

                        if ImGui.IsItemHovered() then
                            LNS_UI.DrawRuleToolTip(itemName, setting, classes:upper())
                            if ImGui.IsMouseClicked(0) then
                                mq.cmdf('/executelink %s', itemLink)
                            elseif ImGui.IsItemClicked(ImGuiMouseButton.Right) then
                                settings.TempSettings.Popped[itemID] = true
                            end
                        end
                        ImGui.Unindent(2)
                    end
                    ImGui.PopID()
                end
            end

            ImGui.EndTable()
        end
        ImGui.EndTabItem()
    end
end

function LNS_UI.drawItemsTables()
    ImGui.SetNextItemWidth(100)
    fontScale = ImGui.SliderFloat("Font Scale", fontScale, 1, 2)
    ImGui.SetWindowFontScale(fontScale)

    if ImGui.BeginTabBar("Items", bit32.bor(ImGuiTabBarFlags.Reorderable, ImGuiTabBarFlags.FittingPolicyScroll)) then
        local col = math.max(2, math.floor((ImGui.GetContentRegionAvail() or 0) / 150))
        col = col > 0 and col or 2
        col = col + (col % 2)

        -- Buy Items
        if ImGui.BeginTabItem("Buy Items") then
            if settings.TempSettings.BuyItems == nil then
                settings.TempSettings.BuyItems = {}
            end

            ImGui.SeparatorText("Add New Item")
            if ImGui.BeginTable("AddItem", 2, ImGuiTableFlags.Borders) then
                ImGui.TableSetupColumn("Item", ImGuiTableColumnFlags.WidthFixed, 280)
                ImGui.TableSetupColumn("Qty", ImGuiTableColumnFlags.WidthFixed, 150)
                ImGui.TableHeadersRow()
                ImGui.TableNextRow()

                ImGui.TableNextColumn()

                ImGui.SetNextItemWidth(150)
                ImGui.PushID("NewBuyItem")
                settings.TempSettings.NewBuyItem = ImGui.InputText("New Item##BuyItems", settings.TempSettings.NewBuyItem)
                ImGui.PopID()
                if ImGui.IsItemHovered() and mq.TLO.Cursor() ~= nil then
                    settings.TempSettings.NewBuyItem = mq.TLO.Cursor()
                    mq.cmdf("/autoinv")
                end
                ImGui.SameLine()
                ImGui.PushStyleColor(ImGuiCol.Button, ImVec4(0.4, 1.0, 0.4, 0.4))
                if ImGui.SmallButton(Icons.MD_ADD) then
                    LNS.BuyItemsTable[settings.TempSettings.NewBuyItem] = settings.TempSettings.NewBuyQty
                    LNS.setBuyItem(settings.TempSettings.NewBuyItem, settings.TempSettings.NewBuyQty)
                    settings.TempSettings.NeedSave = true
                    settings.TempSettings.NewBuyItem = ""
                    settings.TempSettings.NewBuyQty = 1
                end
                ImGui.PopStyleColor()

                ImGui.SameLine()
                ImGui.PushStyleColor(ImGuiCol.Button, ImVec4(1.0, 0.4, 0.4, 0.4))
                if ImGui.SmallButton(Icons.MD_DELETE_SWEEP) then
                    settings.TempSettings.NewBuyItem = ""
                end
                ImGui.PopStyleColor()
                ImGui.TableNextColumn()
                ImGui.SetNextItemWidth(120)

                settings.TempSettings.NewBuyQty = ImGui.InputInt("New Qty##BuyItems", (settings.TempSettings.NewBuyQty or 1),
                    1, 50)
                if settings.TempSettings.NewBuyQty > 1000 then settings.TempSettings.NewBuyQty = 1000 end

                ImGui.EndTable()
            end
            ImGui.SeparatorText("Buy Items Table")
            if ImGui.BeginTable("Buy Items", col, bit32.bor(ImGuiTableFlags.Borders, ImGuiTableFlags.ScrollY), ImVec2(0.0, 0.0)) then
                for i = 1, col / 2 do
                    ImGui.TableSetupColumn("Item##" .. i, ImGuiTableColumnFlags.WidthFixed, 150)
                    ImGui.TableSetupColumn("Qty##" .. i, ImGuiTableColumnFlags.WidthFixed, 160)
                end
                ImGui.TableSetupScrollFreeze(col, 1)
                ImGui.TableHeadersRow()
                ImGui.TableNextRow()

                local numDisplayColumns = col / 2

                if LNS.BuyItemsTable ~= nil and settings.TempSettings.SortedBuyItemKeys ~= nil then
                    local numItems = #settings.TempSettings.SortedBuyItemKeys
                    local numRows = math.ceil(numItems / numDisplayColumns)

                    for row = 1, numRows do
                        for column = 0, numDisplayColumns - 1 do
                            local index = row + column * numRows
                            local k = settings.TempSettings.SortedBuyItemKeys[index]
                            if k and LNS.BuyItemsTable[k] then
                                local v = LNS.BuyItemsTable[k]
                                ImGui.PushID(k .. v)

                                settings.TempSettings.BuyItems[k] = settings.TempSettings.BuyItems[k] or
                                    { Key = k, Value = v, }

                                ImGui.TableNextColumn()

                                ImGui.Text(settings.TempSettings.BuyItems[k].Key)

                                ImGui.TableNextColumn()
                                ImGui.SetNextItemWidth(95)
                                local newValue = ImGui.InputInt("##Value" .. k, settings.TempSettings.BuyItems[k].Value)

                                ImGui.SameLine()
                                ImGui.PushStyleColor(ImGuiCol.Button, ImVec4(1.0, 0.4, 0.4, 0.4))
                                if ImGui.SmallButton(Icons.MD_DELETE) then
                                    settings.TempSettings.DeletedBuyKeys[k] = true
                                    settings.TempSettings.NeedSave = true
                                end
                                ImGui.PopStyleColor()
                                ImGui.SameLine()
                                ImGui.PushStyleColor(ImGuiCol.Button, ImVec4(0.4, 1.0, 0.4, 0.4))
                                if ImGui.SmallButton(Icons.MD_SAVE) then
                                    settings.TempSettings.UpdatedBuyItems[k] = newValue
                                    settings.TempSettings.NeedSave = true
                                end
                                ImGui.PopStyleColor()

                                settings.TempSettings.BuyItems[k].Key = k
                                settings.TempSettings.BuyItems[k].Value = newValue
                                -- end
                                ImGui.PopID()
                            end
                        end
                    end
                end

                ImGui.EndTable()
            end
            ImGui.EndTabItem()
        end


        -- Personal Items
        LNS_UI.drawTabbedTable("Personal")

        -- Global Items

        LNS_UI.drawTabbedTable("Global")

        -- Normal Items
        LNS_UI.drawTabbedTable("Normal")

        -- Missing Items

        if LNS.HasMissingItems then
            if ImGui.BeginTabItem('Missing Items') then
                LNS_UI.renderMissingItemsTables()
                ImGui.EndTabItem()
            end
        end

        if ImGui.BeginTabItem("WildCards") then
            settings.TempSettings.NewWildCard = ImGui.InputTextWithHint("New WildCard", "Enter New WildCard Pattern",
                settings.TempSettings.NewWildCard or '')

            settings.TempSettings.NewWildCardRule = settings.TempSettings.NewWildCardRule or 'Ask'
            if ImGui.BeginCombo("Rule", settings.TempSettings.NewWildCardRule) then
                for i, setting in ipairs(settingList) do
                    local isSelected = settings.TempSettings.NewWildCardRule == setting
                    if ImGui.Selectable(setting, isSelected) then
                        settings.TempSettings.NewWildCardRule = setting
                    end
                end
                ImGui.EndCombo()
            end
            ImGui.SameLine()
            if ImGui.SmallButton(Icons.MD_ADD) then
                if settings.TempSettings.NewWildCard ~= nil and settings.TempSettings.NewWildCard ~= '' then
                    settings.TempSettings.AddWildCard = true
                end
            end

            ImGui.SeparatorText("WildCard Rules")

            if ImGui.BeginTable("WildCard Table", 3, bit32.bor(ImGuiTableFlags.Borders, ImGuiTableFlags.ScrollY), ImVec2(0.0, 0.0)) then
                ImGui.TableSetupColumn("Pattern", ImGuiTableColumnFlags.WidthStretch)
                ImGui.TableSetupColumn("Rule", ImGuiTableColumnFlags.WidthFixed, 100)
                ImGui.TableSetupColumn("Actions", ImGuiTableColumnFlags.WidthFixed, 100)
                ImGui.TableSetupScrollFreeze(0, 1)
                ImGui.TableHeadersRow()
                ImGui.TableNextRow()

                for _, entry in ipairs(LNS.WildCards or {}) do
                    local pattern = entry.wildcard
                    local rule = entry.rule
                    if pattern ~= nil and rule ~= nil then
                        ImGui.PushID(pattern)
                        ImGui.TableNextColumn()
                        ImGui.Text(pattern)
                        ImGui.TableNextColumn()
                        LNS_UI.drawSettingIcon(rule)
                        ImGui.TableNextColumn()
                        ImGui.PushStyleColor(ImGuiCol.Button, ImVec4(1.0, 0.4, 0.4, 0.4))
                        if ImGui.SmallButton(Icons.MD_DELETE) then
                            settings.TempSettings.DeleteWildCard = true
                            settings.TempSettings.DeleteWildCardPattern = pattern
                        end
                        ImGui.PopStyleColor()
                        ImGui.PopID()
                    end
                end

                ImGui.EndTable()
            end

            ImGui.EndTabItem()
        end
        -- Lookup Items

        if LNS.ALLITEMS ~= nil then
            if ImGui.BeginTabItem("Item Lookup") then
                ImGui.TextWrapped("This is a list of All Items you have Rules for, or have looked up this session from the Items DB")
                ImGui.Spacing()
                ImGui.Text("Import your inventory to the DB with /lns importinv")
                local sizeX, sizeY = ImGui.GetContentRegionAvail()
                ImGui.PushStyleColor(ImGuiCol.ChildBg, ImVec4(0.0, 0.6, 0.0, 0.1))
                if ImGui.BeginChild("Add Item Drop Area", ImVec2(sizeX, 40), ImGuiChildFlags.Border) then
                    ImGui.TextDisabled("Drop Item Here to Add to DB")
                    if ImGui.IsWindowHovered() and ImGui.IsMouseClicked(0) then
                        if mq.TLO.Cursor() ~= nil then
                            LNS.addToItemDB(mq.TLO.Cursor)
                            settings.TempSettings['SearchItems'] = mq.TLO.Cursor()
                            Logger.Info(LNS.guiLoot.console, "Added Item to DB: %s", mq.TLO.Cursor.Name())
                            mq.cmdf("/autoinv")
                        end
                    end
                end
                ImGui.EndChild()
                ImGui.PopStyleColor()

                -- search field
                ImGui.PushID("DBLookupSearch")
                ImGui.SetNextItemWidth(250)

                local changed = false
                settings.TempSettings.SearchItems, changed = ImGui.InputTextWithHint("Search Items##AllItems", "Lookup Name or Filter Class",
                    settings.TempSettings.SearchItems or '', ImGuiInputTextFlags.EnterReturnsTrue)

                ImGui.PopID()
                if changed and settings.TempSettings.SearchItems and settings.TempSettings.SearchItems ~= '' then
                    settings.TempSettings.LookUpItem = true
                end

                if ImGui.IsItemHovered(ImGuiHoveredFlags.DelayShort) and mq.TLO.Cursor() then
                    settings.TempSettings.SearchItems = mq.TLO.Cursor.Name()
                    mq.cmdf("/autoinv")
                end
                ImGui.SameLine()

                if ImGui.SmallButton(Icons.MD_DELETE_SWEEP) then
                    settings.TempSettings.SearchItems = nil
                    settings.TempSettings.SearchResults = nil
                end
                if ImGui.IsItemHovered() then ImGui.SetTooltip("Clear Search") end

                ImGui.SameLine()

                ImGui.PushStyleColor(ImGuiCol.Button, ImVec4(0.78, 0.20, 0.05, 0.6))
                if ImGui.SmallButton("LookupItem##AllItems") then
                    settings.TempSettings.LookUpItem = true
                end
                ImGui.PopStyleColor()
                if ImGui.IsItemHovered() then ImGui.SetTooltip("Lookup Item in DB") end
                ImGui.SameLine()
                ImGui.HelpMarker([[
Search items by Name

Advanced Searches can also be done with (<,>,=,<=, >=, and ~) operators
example: hp>=500   this will return items with hp values of 500 and up

You can also do multi searches by placing them in { } curly braces and separated by either ( , or | )
a comma will be treated as AND in the search while a pipe ( | ) will be treated as OR

example: {hp>=500, ac<=100} this will return items with hp values of 500 and up, and ac values of 100 and below
example: {name~"words of" | name~"rune of"} will find items with either "words of" or "rune of" in the name

The ~ symbol can be used on the name field for partial searches.
example {hp>=500, name~robe} this will return items with 500 + Hp and has robe in the name
                ]])
                -- setup the filteredItems for sorting

                local filteredItems = {}
                if settings.TempSettings.SearchResults == nil then
                    for id, item in pairs(LNS.ALLITEMS) do
                        if LNS.SearchLootTable(settings.TempSettings.SearchItems, item.Name, item.ClassList) or
                            LNS.SearchLootTable(settings.TempSettings.SearchItems, id, item.ClassList) then
                            table.insert(filteredItems, { id = id, data = item, })
                        end
                    end
                    table.sort(filteredItems, function(a, b) return a.data.Name < b.data.Name end)
                else
                    filteredItems = settings.TempSettings.SearchResults
                    -- for k, v in pairs(settings.TempSettings.SearchResults) do
                    --     table.insert(filteredItems, { id = k, data = v, })
                    -- end
                end
                -- Calculate total pages
                local totalItems = #filteredItems
                local totalPages = math.ceil(totalItems / ITEMS_PER_PAGE)

                -- Clamp CurrentPage to valid range
                LNS.CurrentPage = math.max(1, math.min(LNS.CurrentPage, totalPages))

                -- Navigation buttons
                if ImGui.Button(Icons.FA_BACKWARD) then
                    LNS.CurrentPage = 1
                end
                ImGui.SameLine()
                if ImGui.ArrowButton("##Previous", ImGuiDir.Left) and LNS.CurrentPage > 1 then
                    LNS.CurrentPage = LNS.CurrentPage - 1
                end
                ImGui.SameLine()
                ImGui.Text(("Page %d of %d"):format(LNS.CurrentPage, totalPages))
                ImGui.SameLine()
                if ImGui.ArrowButton("##Next", ImGuiDir.Right) and LNS.CurrentPage < totalPages then
                    LNS.CurrentPage = LNS.CurrentPage + 1
                end
                ImGui.SameLine()
                if ImGui.Button(Icons.FA_FORWARD) then
                    LNS.CurrentPage = totalPages
                end

                ImGui.SameLine()
                ImGui.SetNextItemWidth(80)
                if ImGui.BeginCombo("Max Items", tostring(ITEMS_PER_PAGE)) then
                    for i = 10, 100, 10 do
                        if ImGui.Selectable(tostring(i), ITEMS_PER_PAGE == i) then
                            ITEMS_PER_PAGE = i
                        end
                    end
                    ImGui.EndCombo()
                end

                -- Calculate the range of items to display
                local startIndex = (LNS.CurrentPage - 1) * ITEMS_PER_PAGE + 1
                local endIndex = math.min(startIndex + ITEMS_PER_PAGE - 1, totalItems)

                if ImGui.CollapsingHeader('BulkSet') then
                    ImGui.Indent(2)
                    ImGui.Text("Set all items to the same rule")
                    ImGui.SetNextItemWidth(100)
                    ImGui.PushID("BulkSet")
                    if settings.TempSettings.BulkRule == nil then
                        settings.TempSettings.BulkRule = settingList[1]
                    end
                    if ImGui.BeginCombo("Rule", settings.TempSettings.BulkRule) then
                        for i, setting in ipairs(settingList) do
                            local isSelected = settings.TempSettings.BulkRulee == setting
                            if ImGui.Selectable(setting, isSelected) then
                                settings.TempSettings.BulkRule = setting
                            end
                        end
                        ImGui.EndCombo()
                    end
                    ImGui.SameLine()
                    ImGui.SetNextItemWidth(100)
                    if settings.TempSettings.BulkClasses == nil then
                        settings.TempSettings.BulkClasses = "All"
                    end
                    settings.TempSettings.BulkClasses = ImGui.InputTextWithHint("Classes", "who can loot or all ex: shm clr dru", settings.TempSettings.BulkClasses)

                    ImGui.SameLine()
                    ImGui.SetNextItemWidth(100)
                    if settings.TempSettings.BulkSetTable == nil then
                        settings.TempSettings.BulkSetTable = "Normal_Rules"
                    end
                    if ImGui.BeginCombo("Table", settings.TempSettings.BulkSetTable) then
                        for i, v in ipairs(settings.TableListRules) do
                            if ImGui.Selectable(v, settings.TempSettings.BulkSetTable == v) then
                                settings.TempSettings.BulkSetTable = v
                            end
                        end
                        ImGui.EndCombo()
                    end

                    ImGui.PopID()
                    if ImGui.Button(Icons.FA_CHECK .. " All") then
                        for i = startIndex, endIndex do
                            local itemID = filteredItems[i].id
                            settings.TempSettings.SelectedItems[itemID] = true
                        end
                    end

                    ImGui.SameLine()
                    if ImGui.Button("Clear Selected") then
                        for id, selected in pairs(settings.TempSettings.SelectedItems) do
                            settings.TempSettings.SelectedItems[id] = false
                        end
                    end

                    ImGui.PushStyleColor(ImGuiCol.Button, ImVec4(0.4, 1.0, 0.4, 0.4))
                    if ImGui.Button("Set Selected") then
                        settings.TempSettings.BulkSet = {}
                        for itemID, isSelected in pairs(settings.TempSettings.SelectedItems) do
                            if isSelected then
                                settings.TempSettings.BulkSet[itemID] = {
                                    Rule = settings.TempSettings.BulkRule,
                                    Link = LNS.ALLITEMS[itemID].Link or "NULL",
                                }
                            end
                        end
                        settings.TempSettings.doBulkSet = true
                    end
                    ImGui.PopStyleColor()

                    ImGui.Unindent(2)
                end -- Render the table
                if ImGui.BeginTable("DB", 60, bit32.bor(ImGuiTableFlags.Borders,
                        ImGuiTableFlags.Hideable, ImGuiTableFlags.Resizable, ImGuiTableFlags.ScrollX, ImGuiTableFlags.ScrollY, ImGuiTableFlags.Reorderable)) then
                    -- Set up column headers
                    ImGui.TableSetupColumn(Icons.FA_CHECK, bit32.bor(ImGuiTableColumnFlags.NoHide, ImGuiTableColumnFlags.WidthFixed), 30)

                    for idx, label in pairs(LNS.AllItemColumnListIndex) do
                        if label == 'name' then
                            ImGui.TableSetupColumn(label .. "##" .. idx, ImGuiTableColumnFlags.NoHide)
                        else
                            ImGui.TableSetupColumn(label .. "##" .. idx, ImGuiTableColumnFlags.DefaultHide)
                        end
                    end
                    ImGui.TableSetupScrollFreeze(2, 1)
                    ImGui.TableHeadersRow()
                    ImGui.TableNextRow()

                    -- Render only the current page's items
                    for i = startIndex, endIndex do
                        local id = filteredItems[i].id or 0
                        local item = filteredItems[i].data or {}
                        ImGui.TableNextColumn()
                        ImGui.PushID(id .. "_checkbox")
                        if settings.TempSettings.SelectedItems[id] == nil then
                            settings.TempSettings.SelectedItems[id] = false
                        end
                        local isSelected = settings.TempSettings.SelectedItems[id]
                        isSelected = ImGui.Checkbox("##select", isSelected)
                        settings.TempSettings.SelectedItems[id] = isSelected
                        ImGui.PopID()
                        ImGui.PushID(id)

                        -- Render each column for the item
                        ImGui.TableNextColumn()
                        ImGui.Indent(2)
                        LNS_UI.drawIcon(item.Icon, iconSize * fontScale)
                        if ImGui.IsItemHovered() then
                            ImGui.BeginTooltip()
                            LNS_UI.Draw_item_tooltip(id)
                            ImGui.Spacing()
                            ImGui.Separator()
                            ImGui.Text("Left Click Icon to open In-Game Details window")
                            ImGui.Text("Right Click to Pop Open Details window.")
                            ImGui.EndTooltip()
                            if ImGui.IsMouseClicked(0) then
                                -- if ImGui.SmallButton(Icons.FA_EYE .. "##" .. itemID) then
                                mq.cmdf('/executelink %s', item.Link)
                            elseif ImGui.IsItemClicked(ImGuiMouseButton.Right) then
                                settings.TempSettings.Popped[id] = true
                            end
                        end
                        ImGui.SameLine()
                        if ImGui.Selectable(item.Name, false) then
                            settings.TempSettings.ModifyItemRule = true
                            settings.TempSettings.ModifyItemID = id
                            settings.TempSettings.ModifyClasses = item.ClassList
                            settings.TempSettings.ModifyItemRaceList = item.RaceList
                            settings.TempSettings.ModifyItemName = item.Name

                            tempValues = {}
                        end
                        ImGui.Unindent(2)
                        ImGui.TableNextColumn()
                        -- sell_value
                        if item.Value ~= '0 pp 0 gp 0 sp 0 cp' then
                            LNS_UI.SafeText(item.Value)
                        end
                        ImGui.TableNextColumn()
                        LNS_UI.SafeText(item.Tribute)     -- tribute_value
                        ImGui.TableNextColumn()
                        LNS_UI.SafeText(item.Stackable)   -- stackable
                        ImGui.TableNextColumn()
                        LNS_UI.SafeText(item.StackSize)   -- stack_size
                        ImGui.TableNextColumn()
                        LNS_UI.SafeText(item.NoDrop)      -- nodrop
                        ImGui.TableNextColumn()
                        LNS_UI.SafeText(item.NoTrade)     -- notrade
                        ImGui.TableNextColumn()
                        LNS_UI.SafeText(item.Tradeskills) -- tradeskill
                        ImGui.TableNextColumn()
                        LNS_UI.SafeText(item.Quest)       -- quest
                        ImGui.TableNextColumn()
                        LNS_UI.SafeText(item.Lore)        -- lore
                        ImGui.TableNextColumn()
                        LNS_UI.SafeText(item.Collectible) -- collectible
                        ImGui.TableNextColumn()
                        LNS_UI.SafeText(item.Augment)     -- augment
                        ImGui.TableNextColumn()
                        LNS_UI.SafeText(item.AugType)     -- augtype
                        ImGui.TableNextColumn()
                        LNS_UI.SafeText(item.Clicky)      -- clickable
                        ImGui.TableNextColumn()
                        local tmpWeight = item.Weight ~= nil and item.Weight or 0
                        LNS_UI.SafeText(tmpWeight)      -- weight
                        ImGui.TableNextColumn()
                        LNS_UI.SafeText(item.AC)        -- ac
                        ImGui.TableNextColumn()
                        LNS_UI.SafeText(item.Damage)    -- damage
                        ImGui.TableNextColumn()
                        LNS_UI.SafeText(item.strength)  -- strength
                        ImGui.TableNextColumn()
                        LNS_UI.SafeText(item.DEX)       -- dexterity
                        ImGui.TableNextColumn()
                        LNS_UI.SafeText(item.AGI)       -- agility
                        ImGui.TableNextColumn()
                        LNS_UI.SafeText(item.STA)       -- stamina
                        ImGui.TableNextColumn()
                        LNS_UI.SafeText(item.INT)       -- intelligence
                        ImGui.TableNextColumn()
                        LNS_UI.SafeText(item.WIS)       -- wisdom
                        ImGui.TableNextColumn()
                        LNS_UI.SafeText(item.CHA)       -- charisma
                        ImGui.TableNextColumn()
                        LNS_UI.SafeText(item.HP)        -- hp
                        ImGui.TableNextColumn()
                        LNS_UI.SafeText(item.HPRegen)   -- regen_hp
                        ImGui.TableNextColumn()
                        LNS_UI.SafeText(item.Mana)      -- mana
                        ImGui.TableNextColumn()
                        LNS_UI.SafeText(item.ManaRegen) -- regen_mana
                        ImGui.TableNextColumn()
                        LNS_UI.SafeText(item.Haste)     -- haste
                        ImGui.TableNextColumn()
                        LNS_UI.SafeText(item.Classes)   -- classes
                        ImGui.TableNextColumn()
                        -- class_list
                        local tmpClassList = item.ClassList ~= nil and item.ClassList or "All"
                        if tmpClassList:lower() ~= 'all' then
                            ImGui.Indent(2)
                            ImGui.TextColored(ImVec4(0, 1, 1, 0.8), tmpClassList)
                            ImGui.Unindent(2)
                        else
                            ImGui.Indent(2)
                            ImGui.TextDisabled(tmpClassList)
                            ImGui.Unindent(2)
                        end
                        if ImGui.IsItemHovered() then
                            ImGui.BeginTooltip()
                            ImGui.Text(item.Name)
                            ImGui.PushTextWrapPos(200)
                            ImGui.PushStyleColor(ImGuiCol.Text, ImVec4(0, 1, 1, 0.8))
                            ImGui.TextWrapped("Classes: %s", tmpClassList)
                            ImGui.PopStyleColor()
                            ImGui.PushStyleColor(ImGuiCol.Text, ImVec4(0.852, 0.589, 0.259, 1.000))
                            ImGui.TextWrapped("Races: %s", item.RaceList)
                            ImGui.PopStyleColor()
                            ImGui.PopTextWrapPos()
                            ImGui.EndTooltip()
                        end
                        ImGui.TableNextColumn()
                        LNS_UI.SafeText(item.svFire)          -- svfire
                        ImGui.TableNextColumn()
                        LNS_UI.SafeText(item.svCold)          -- svcold
                        ImGui.TableNextColumn()
                        LNS_UI.SafeText(item.svDisease)       -- svdisease
                        ImGui.TableNextColumn()
                        LNS_UI.SafeText(item.svPoison)        -- svpoison
                        ImGui.TableNextColumn()
                        LNS_UI.SafeText(item.svCorruption)    -- svcorruption
                        ImGui.TableNextColumn()
                        LNS_UI.SafeText(item.svMagic)         -- svmagic
                        ImGui.TableNextColumn()
                        LNS_UI.SafeText(item.SpellDamage)     -- spelldamage
                        ImGui.TableNextColumn()
                        LNS_UI.SafeText(item.SpellShield)     -- spellshield
                        ImGui.TableNextColumn()
                        LNS_UI.SafeText(item.Size)            -- item_size
                        ImGui.TableNextColumn()
                        LNS_UI.SafeText(item.WeightReduction) -- weightreduction
                        ImGui.TableNextColumn()
                        LNS_UI.SafeText(item.Races)           -- races
                        ImGui.TableNextColumn()
                        -- race_list
                        if item.RaceList ~= nil then
                            if item.RaceList:lower() ~= 'all' then
                                ImGui.Indent(2)
                                ImGui.TextColored(ImVec4(0.852, 0.589, 0.259, 1.000), item.RaceList)
                                ImGui.Unindent(2)
                            else
                                ImGui.Indent(2)
                                ImGui.TextDisabled(item.RaceList)
                                ImGui.Unindent(2)
                            end
                            if ImGui.IsItemHovered() then
                                ImGui.BeginTooltip()
                                ImGui.Text(item.Name)
                                ImGui.PushTextWrapPos(200)
                                ImGui.PushStyleColor(ImGuiCol.Text, ImVec4(0, 1, 1, 0.8))
                                ImGui.TextWrapped("Classes: %s", tmpClassList)
                                ImGui.PopStyleColor()
                                ImGui.PushStyleColor(ImGuiCol.Text, ImVec4(0.852, 0.589, 0.259, 1.000))
                                ImGui.TextWrapped("Races: %s", item.RaceList)
                                ImGui.PopStyleColor()
                                ImGui.PopTextWrapPos()
                                ImGui.EndTooltip()
                            end
                        end
                        ImGui.TableNextColumn()

                        LNS_UI.SafeText(item.Range)              -- item_range
                        ImGui.TableNextColumn()
                        LNS_UI.SafeText(item.Attack)             -- attack
                        ImGui.TableNextColumn()
                        LNS_UI.SafeText(item.StrikeThrough)      -- strikethrough
                        ImGui.TableNextColumn()
                        LNS_UI.SafeText(item.HeroicAGI)          -- heroicagi
                        ImGui.TableNextColumn()
                        LNS_UI.SafeText(item.HeroicCHA)          -- heroiccha
                        ImGui.TableNextColumn()
                        LNS_UI.SafeText(item.HeroicDEX)          -- heroicdex
                        ImGui.TableNextColumn()
                        LNS_UI.SafeText(item.HeroicINT)          -- heroicint
                        ImGui.TableNextColumn()
                        LNS_UI.SafeText(item.HeroicSTA)          -- heroicsta
                        ImGui.TableNextColumn()
                        LNS_UI.SafeText(item.HeroicSTR)          -- heroicstr
                        ImGui.TableNextColumn()
                        LNS_UI.SafeText(item.HeroicSvCold)       -- heroicsvcold
                        ImGui.TableNextColumn()
                        LNS_UI.SafeText(item.HeroicSvCorruption) -- heroicsvcorruption
                        ImGui.TableNextColumn()
                        LNS_UI.SafeText(item.HeroicSvDisease)    -- heroicsvdisease
                        ImGui.TableNextColumn()
                        LNS_UI.SafeText(item.HeroicSvFire)       -- heroicsvfire
                        ImGui.TableNextColumn()
                        LNS_UI.SafeText(item.HeroicSvMagic)      -- heroicsvmagic
                        ImGui.TableNextColumn()
                        LNS_UI.SafeText(item.HeroicSvPoison)     -- heroicsvpoison
                        ImGui.TableNextColumn()
                        LNS_UI.SafeText(item.HeroicWIS)          -- heroicwis

                        ImGui.PopID()
                    end
                    ImGui.EndTable()
                end
                ImGui.EndTabItem()
            end
        end
    end

    if LNS.NewItems ~= nil and LNS.NewItemsCount > 0 then
        if ImGui.BeginTabItem("New Items") then
            LNS_UI.drawNewItemsTable()
            ImGui.EndTabItem()
        end
    end
    ImGui.EndTabBar()
end

function LNS_UI.DrawRuleToolTip(name, setting, classes)
    ImGui.BeginTooltip()

    ImGui.Text("Item:")
    ImGui.SameLine()
    ImGui.TextColored(1, 1, 0.50, 1, name)

    ImGui.Text("Setting:")
    ImGui.SameLine()
    ImGui.TextColored(0.5, 1, 1, 1, setting)

    ImGui.Text("Classes:")
    ImGui.SameLine()
    ImGui.TextColored(0.5, 1, 0.5, 1, classes)

    -- ImGui.Separator()
    -- ImGui.Text("Right Click to View Item Details")
    ImGui.Spacing()
    ImGui.Separator()
    ImGui.Text("Left Click Icon to open In-Game Details window")
    ImGui.Text("Right Click to Pop Open Details window.")
    ImGui.EndTooltip()
end

function LNS_UI.drawRuleRadioButton(setting, idx, selectedIdx)
    local buttonText = setting
    local posX, posY = ImGui.GetCursorPos()
    if idx == selectedIdx then
        ImGui.SetCursorPos(posX + 20, posY - 2)
        -- highlight with a colored square as a background color if selectedIdx == idx

        ImGui.GetWindowDrawList():AddRectFilled(ImGui.GetCursorScreenPosVec(),
            ImGui.GetCursorScreenPosVec() + 20, IM_COL32(69, 50, 145, 255))
        ImGui.SetCursorPos(posX, posY)
    end
    if setting == 'Destroy' then
        ImGui.PushStyleColor(ImGuiCol.Text, 0.860, 0.104, 0.104, 1.000)
        buttonText = Icons.MD_DELETE
    elseif string.find(setting, 'Quest') then
        ImGui.PushStyleColor(ImGuiCol.Text, 1.000, 0.914, 0.200, 1.000)
        buttonText = Icons.MD_SEARCH
    elseif setting == "Tribute" then
        ImGui.PushStyleColor(ImGuiCol.Text, 0.991, 0.506, 0.230, 1.000)
        buttonText = Icons.FA_GIFT
    elseif setting == 'Sell' then
        ImGui.PushStyleColor(ImGuiCol.Text, 0, 1, 0, 1)
        buttonText = Icons.MD_ATTACH_MONEY
    elseif setting == 'Keep' then
        ImGui.PushStyleColor(ImGuiCol.Text, 0.916, 0.094, 0.736, 1.000)
        buttonText = Icons.MD_FAVORITE_BORDER
    elseif setting == 'Ignore' then
        ImGui.PushStyleColor(ImGuiCol.Text, 0.976, 0.218, 0.244, 1.000)
        buttonText = Icons.MD_NOT_INTERESTED
    elseif setting == 'Bank' then
        ImGui.PushStyleColor(ImGuiCol.Text, 0.162, 0.785, 0.877, 1.000)
        buttonText = Icons.MD_ACCOUNT_BALANCE
    elseif setting == 'CanUse' then
        ImGui.PushStyleColor(ImGuiCol.Text, 0.411, 0.462, 0.678, 1.000)
        buttonText = Icons.FA_USER_O
    elseif setting == 'Ask' then
        ImGui.PushStyleColor(ImGuiCol.Text, 1, 1, 1, 1)
        buttonText = Icons.FA_QUESTION_CIRCLE
    end
    local updated = ImGui.RadioButton(buttonText, idx == selectedIdx)
    ImGui.PopStyleColor()
    if ImGui.IsItemHovered() then
        ImGui.BeginTooltip()
        ImGui.Text(setting)
        ImGui.EndTooltip()
    end
    return updated
end

function LNS_UI.drawSettingIcon(setting)
    if string.find(setting, 'Destroy') then
        ImGui.TextColored(0.860, 0.104, 0.104, 1.000, Icons.MD_DELETE)
    elseif string.find(setting, 'Quest') then
        ImGui.TextColored(1.000, 0.914, 0.200, 1.000, Icons.MD_SEARCH)
        if string.find(setting, "|") then
            ImGui.PushID(setting)
            local qty = string.sub(setting, string.find(setting, "|") + 1)
            ImGui.SameLine()
            ImGui.TextColored(0.00, 0.614, 0.800, 1.000, qty)
            ImGui.PopID()
        end
    elseif string.find(setting, "Tribute") then
        ImGui.TextColored(0.991, 0.506, 0.230, 1.000, Icons.FA_GIFT)
    elseif string.find(setting, 'Sell') then
        ImGui.TextColored(0, 1, 0, 1, Icons.MD_ATTACH_MONEY)
    elseif string.find(setting, 'Keep') then
        ImGui.TextColored(0.916, 0.094, 0.736, 1.000, Icons.MD_FAVORITE_BORDER)
    elseif string.find(setting, 'Unknown') then
        ImGui.TextColored(0.5, 0.5, 0.5, 1.000, Icons.FA_QUESTION)
    elseif string.find(setting, 'Ignore') then
        ImGui.TextColored(0.976, 0.218, 0.244, 1.000, Icons.MD_NOT_INTERESTED)
    elseif string.find(setting, 'Bank') then
        ImGui.TextColored(0.162, 0.785, 0.877, 1.000, Icons.MD_ACCOUNT_BALANCE)
    elseif string.find(setting, 'CanUse') then
        ImGui.TextColored(0.411, 0.462, 0.678, 1.000, Icons.FA_USER_O)
    else
        ImGui.Text(setting)
    end
end

---comment
---@param message any Message to display in the tooltip, if a Table is passed it will display each item in the table on a new line
---@return boolean drawn
function LNS_UI.DrawToolTip(message)
    local drawn = false
    if message == nil then return drawn end
    if type(message) == 'table' and #message == 0 then
        return drawn
    end
    ImGui.BeginTooltip()
    if type(message) == 'table' then
        for _, msg in ipairs(message) do
            ImGui.PushTextWrapPos(200)
            ImGui.Text(msg)
            ImGui.PopTextWrapPos()
        end
        drawn = true
    else
        ImGui.PushTextWrapPos(200)
        ImGui.Text(message)
        ImGui.PopTextWrapPos()
        drawn = true
    end
    ImGui.EndTooltip()
    return drawn
end

---@param id string Unique ID for the button
---@param value boolean Current toggle state
---@param on_color ImVec4|nil Color when ON default(green)
---@param off_color ImVec4|nil Color when OFF default(red)
---@param height number|nil Height of the toggle default(20)
---@param width number|nil Width of the toggle default(height * 2)
---@return boolean value New toggle value
---@return boolean clicked Whether the value changed
function LNS_UI.DrawToggle(id, value, on_color, off_color, height, width)
    height = height or 16
    width = width or height * 2
    on_color = on_color or ImVec4(0.2, 0.8, 0.2, 1)   -- Default green
    off_color = off_color or ImVec4(0.8, 0.2, 0.2, 1) -- Default red

    local clicked = false
    local label = id:match("^(.-)##") -- Capture text before ##
    if not id:find("##") then
        label = id
    end

    if label and label ~= "" then
        ImGui.Text(string.format("%s:", label))
        if ImGui.IsItemHovered() then
            if not LNS_UI.DrawToolTip(settings.Tooltips[label]) then
                LNS_UI.DrawToolTip(settings.Tooltips[id:gsub("##", "")])
            end
        end
        if ImGui.IsItemClicked() then
            value = not value
            clicked = true
        end
        ImGui.SameLine()
    end

    local draw_list = ImGui.GetWindowDrawList()
    local pos = { x = 0, y = 0, }
    pos.x, pos.y = ImGui.GetCursorScreenPos()
    local radius = height * 0.5

    local t = value and 1.0 or 0.0
    local knob_x = pos.x + radius + t * (width - height)

    -- Background
    draw_list:AddRectFilled(
        ImVec2(pos.x, pos.y),
        ImVec2(pos.x + width, pos.y + height),
        ImGui.GetColorU32(value and on_color or off_color),
        height * 0.5
    )

    -- Knob
    draw_list:AddCircleFilled(
        ImVec2(knob_x, pos.y + radius),
        radius * 0.8,
        ImGui.GetColorU32(ImVec4(1, 1, 1, 1)),
        0
    )

    ImGui.SetCursorScreenPos(ImVec2(pos.x, pos.y))
    -- Set up bounding box
    ImGui.InvisibleButton(id, width, height)
    if ImGui.IsItemClicked() then
        value = not value
        clicked = true
    end
    if ImGui.IsItemHovered() then
        if not LNS_UI.DrawToolTip(settings.Tooltips[label]) then
            LNS_UI.DrawToolTip(settings.Tooltips[id:gsub("##", "")])
        end
    end

    return value, clicked
end

function LNS_UI.drawSwitch(settingName, who)
    if settings.TempSettings[who] ~= nil then
        local clicked = false
        settings.TempSettings[who][settingName], clicked = LNS_UI.DrawToggle("##" .. settingName, settings.TempSettings[who][settingName],
            ImVec4(0.4, 1.0, 0.4, 0.4), ImVec4(1.0, 0.4, 0.4, 0.4))

        if clicked then
            if LNS.Boxes[who][settingName] ~= settings.TempSettings[who][settingName] then
                LNS.Boxes[who][settingName] = settings.TempSettings[who][settingName]
                if who == settings.MyName then
                    settings.Settings[settingName] = settings.TempSettings[who][settingName]
                    settings.TempSettings.NeedSave = true
                end
            end
            if settingName == 'MasterLooting' then
                actors.Send({ who = settings.MyName, action = 'master_looter', select = settings.Settings.MasterLooting, Server = settings.EqServer, })
            end
            -- LNS.guiLoot.ReportLeft = settings.Settings.ReportSkippedItems
        end
    end
end

function LNS_UI.renderSettingsTables(who)
    if who == nil then return end

    local col = 2
    col = math.max(2, math.floor((ImGui.GetContentRegionAvail() or 0) / 140))
    if col < 2 then
        col = 2
    end
    local colCount = col + (col % 2)
    if colCount % 2 ~= 0 then
        if (colCount - 1) % 2 == 0 then
            colCount = colCount - 1
        else
            colCount = colCount - 2
        end
    end
    local sorted_settings = LNS.SortTableColums(nil, settings.TempSettings.SortedSettingsKeys, colCount / 2)
    local sorted_toggles = LNS.SortTableColums(nil, settings.TempSettings.SortedToggleKeys, colCount / 2)

    if ImGui.CollapsingHeader(string.format("Settings %s##%s", who, who)) then
        if ImGui.BeginTable("##Settings", colCount, bit32.bor(ImGuiTableFlags.Borders, ImGuiTableFlags.Resizable)) then
            for i = 1, colCount / 2 do
                ImGui.TableSetupColumn("Setting##" .. i, ImGuiTableColumnFlags.WidthStretch)
                ImGui.TableSetupColumn("Value##" .. i, ImGuiTableColumnFlags.WidthFixed, 80)
            end
            ImGui.TableSetupScrollFreeze(colCount, 1)
            ImGui.TableHeadersRow()
            ImGui.TableNextRow()

            for i, settingName in ipairs(sorted_settings or {}) do
                if who == nil then break end
                if not settings.SettingsNoDraw[settingName] then
                    if settings.TempSettings[who] == nil then
                        settings.TempSettings[who] = {}
                    end
                    if settings.TempSettings[who][settingName] == nil then
                        settings.TempSettings[who][settingName] = LNS.Boxes[who][settingName]
                    end
                    if who ~= nil and settings.TempSettings[who][settingName] ~= nil and type(LNS.Boxes[who][settingName]) ~= "boolean" then
                        ImGui.PushID(settingName)
                        ImGui.TableNextColumn()
                        ImGui.Indent(2)
                        ImGui.Text(settingName)
                        if ImGui.IsItemHovered() then
                            ImGui.BeginTooltip()
                            ImGui.PushTextWrapPos(200)
                            ImGui.Text("Setting: %s", settingName)
                            ImGui.Text("%s's Current Value: %s", who, LNS.Boxes[who][settingName] and "Enabled" or "Disabled")
                            ImGui.PopTextWrapPos()
                            ImGui.Separator()
                            LNS_UI.DrawToolTip(settings.Tooltips[settingName])
                            ImGui.EndTooltip()
                        end
                        ImGui.Unindent(2)
                        ImGui.TableNextColumn()
                        if type(LNS.Boxes[who][settingName]) == "number" then
                            ImGui.SetNextItemWidth(ImGui.GetColumnWidth(-1))

                            settings.TempSettings[who][settingName] = ImGui.InputInt("##" .. settingName, settings.TempSettings[who][settingName])
                            if LNS.Boxes[who][settingName] ~= settings.TempSettings[who][settingName] then
                                LNS.Boxes[who][settingName] = settings.TempSettings[who][settingName]
                                if who == settings.MyName then
                                    settings.Settings[settingName] = LNS.Boxes[who][settingName]
                                    settings.TempSettings.NeedSave = true
                                end
                            end
                        elseif type(LNS.Boxes[who][settingName]) == "string" then
                            ImGui.SetNextItemWidth(ImGui.GetColumnWidth(-1))
                            settings.TempSettings[who][settingName] = ImGui.InputText("##" .. settingName, settings.TempSettings[who][settingName])
                            if LNS.Boxes[who][settingName] ~= settings.TempSettings[who][settingName] then
                                LNS.Boxes[who][settingName] = settings.TempSettings[who][settingName]
                                if who == settings.MyName then
                                    settings.Settings[settingName] = LNS.Boxes[who][settingName]
                                    settings.TempSettings.NeedSave = true
                                end
                            end
                        end
                        if ImGui.IsItemHovered() then
                            ImGui.BeginTooltip()
                            ImGui.PushTextWrapPos(200)
                            ImGui.Text("Setting: %s", settingName)
                            ImGui.Text("%s's Current Value: %s", who, LNS.Boxes[who][settingName] and "Enabled" or "Disabled")
                            ImGui.PopTextWrapPos()
                            ImGui.Separator()
                            LNS_UI.DrawToolTip(settings.Tooltips[settingName])
                            ImGui.EndTooltip()
                        end
                        ImGui.PopID()
                    end
                end
            end
            ImGui.EndTable()
        end
    end

    if ImGui.CollapsingHeader(string.format("Toggles %s##%s", who, who)) then
        if ImGui.BeginTable("Toggles##1", colCount, bit32.bor(ImGuiTableFlags.Borders, ImGuiTableFlags.Resizable)) then
            for i = 1, colCount / 2 do
                ImGui.TableSetupColumn("Setting##" .. i, ImGuiTableColumnFlags.WidthStretch)
                ImGui.TableSetupColumn("Value##" .. i, ImGuiTableColumnFlags.WidthFixed, 80)
            end
            ImGui.TableSetupScrollFreeze(colCount, 1)
            ImGui.TableHeadersRow()

            ImGui.TableNextRow()

            for i, settingName in ipairs(sorted_toggles or {}) do
                if who == nil then break end
                if not settings.SettingsNoDraw[settingName] then
                    if settings.TempSettings[who] == nil then
                        settings.TempSettings[who] = {}
                    end
                    if settings.TempSettings[who][settingName] == nil then
                        settings.TempSettings[who][settingName] = LNS.Boxes[who][settingName]
                    end
                    if who ~= nil and type(LNS.Boxes[who][settingName]) == "boolean" then
                        ImGui.PushID(settingName)
                        ImGui.TableNextColumn()
                        ImGui.Indent(2)
                        -- ImGui.Text(settingName)
                        if ImGui.Selectable(settingName) then
                            settings.TempSettings[who][settingName] = not settings.TempSettings[who][settingName]
                            if LNS.Boxes[who][settingName] ~= settings.TempSettings[who][settingName] then
                                LNS.Boxes[who][settingName] = settings.TempSettings[who][settingName]
                                if who == settings.MyName then
                                    settings.Settings[settingName] = LNS.Boxes[who][settingName]
                                    settings.TempSettings.NeedSave = true
                                    Logger.Info(LNS.guiLoot.console, "Setting \ay%s\ax to \ag%s\ax", settingName, settings.Settings[settingName])
                                end
                            end
                            if settingName == 'MasterLooting' then
                                actors.Send({ who = settings.MyName, action = 'master_looter', select = settings.Settings.MasterLooting, Server = settings.EqServer, })
                            end
                            -- LNS.guiLoot.ReportLeft = settings.Settings.ReportSkippedItems
                        end
                        if ImGui.IsItemHovered() then
                            ImGui.BeginTooltip()
                            ImGui.PushTextWrapPos(200)
                            ImGui.Text("Setting: %s", settingName)
                            ImGui.Text("%s's Current Value: %s", who, LNS.Boxes[who][settingName] and "Enabled" or "Disabled")
                            ImGui.PopTextWrapPos()
                            ImGui.Separator()
                            LNS_UI.DrawToolTip(settings.Tooltips[settingName])
                            ImGui.EndTooltip()
                        end
                        ImGui.Unindent(2)
                        ImGui.TableNextColumn()
                        LNS_UI.drawSwitch(settingName, who)
                        ImGui.PopID()
                    end
                end
            end
            ImGui.EndTable()
        end
    end
end

function LNS_UI.renderCloneWindow()
    if not settings.TempSettings.PopCloneWindow then
        return
    end
    ImGui.SetNextWindowSize(ImVec2(650, 400), ImGuiCond.Appearing)
    local openClone, showClone = ImGui.Begin("Clone Who##who_settings", true)
    if not openClone then
        settings.TempSettings.CloneTo = nil
        settings.TempSettings.PopCloneWindow = false
        showClone = false
    end
    if showClone then
        ImGui.SeparatorText("Clone Settings")
        ImGui.SetNextItemWidth(120)

        -- if ImGui.BeginCombo('##Source', settings.TempSettings.CloneWho or "Select Source") then
        --     for _, k in ipairs(LNS.BoxKeys) do
        --         if ImGui.Selectable(k) then
        --             settings.TempSettings.CloneWho = k
        --         end
        --     end
        --     ImGui.EndCombo()
        -- end

        -- ImGui.SameLine()

        -- ImGui.SetNextItemWidth(120)
        -- if ImGui.BeginCombo('##Dest', settings.TempSettings.CloneTo or "Select Destination") then
        --     for _, k in ipairs(LNS.BoxKeys) do
        --         if ImGui.Selectable(k) then
        --             settings.TempSettings.CloneTo = k
        --         end
        --     end
        --     ImGui.EndCombo()
        -- end
        ImGui.SetNextItemWidth(150)
        ImGui.InputTextWithHint("Clone Who##CloneWho", "Source Character", settings.TempSettings.CloneWho or "", ImGuiInputTextFlags.ReadOnly)
        ImGui.SameLine()

        ImGui.SetNextItemWidth(150)
        ImGui.InputTextWithHint("Clone To##CloneTo", "Destination Character", settings.TempSettings.CloneTo or "", ImGuiInputTextFlags.ReadOnly)

        if settings.TempSettings.CloneWho and settings.TempSettings.CloneTo then
            ImGui.SameLine()
            settings.TempSettings.PopCloneWindow = true

            if ImGui.SmallButton("Clone Now") then
                LNS.Boxes[settings.TempSettings.CloneTo] = LNS.Boxes[settings.TempSettings.CloneWho]
                local tmpSet = LNS.Boxes[settings.TempSettings.CloneWho]
                actors.Send({
                    action = 'updatesettings',
                    who = settings.TempSettings.CloneTo,
                    settings = tmpSet,
                    Server = settings.EqServer,
                })
                -- settings.TempSettings.CloneWho = nil
                settings.TempSettings.CloneTo = nil
            end
        end
        ImGui.Spacing()
        ImGui.SeparatorText("Clone Settings Tables")
        ImGui.Spacing()
        -- left panel
        if ImGui.BeginChild("Clone Who##list", 200, 0.0, ImGuiChildFlags.Border) then
            --list of boxes right click to select where to set them as cloneWho or cloneTo
            ImGui.TextWrapped("Right click a name to select as either Source or Destination")
            ImGui.Separator()
            for _, k in ipairs(LNS.BoxKeys) do
                ImGui.PushID(k)
                if settings.TempSettings.CloneWho == k then
                    ImGui.PushStyleColor(ImGuiCol.Text, ImVec4(0.4, 1.0, 0.1, 1.0))
                elseif settings.TempSettings.CloneTo == k then
                    ImGui.PushStyleColor(ImGuiCol.Text, ImVec4(0.0, 1.0, 1.0, 1.0))
                else
                    ImGui.PushStyleColor(ImGuiCol.Text, ImVec4(0.8, 0.8, 0.8, 1.0))
                end
                ImGui.Selectable(k, settings.TempSettings.CloneWho == k or settings.TempSettings.CloneTo == k)

                ImGui.PopStyleColor()
                if ImGui.BeginPopupContextItem("##CloneWhoContext") then
                    if ImGui.Selectable("Set as Source") then
                        if settings.TempSettings.CloneTo == k then
                            settings.TempSettings.CloneTo = nil
                        end
                        settings.TempSettings.CloneWho = k
                    end
                    if ImGui.Selectable("Set as Destination") then
                        if settings.TempSettings.CloneWho == k then
                            settings.TempSettings.CloneWho = nil
                        end
                        settings.TempSettings.CloneTo = k
                    end
                    if ImGui.Selectable("Clear Selection") then
                        if k == settings.TempSettings.CloneWho then
                            settings.TempSettings.CloneWho = nil
                        elseif k == settings.TempSettings.CloneTo then
                            settings.TempSettings.CloneTo = nil
                        end
                    end
                    ImGui.EndPopup()
                end
                ImGui.PopID()
            end
        end
        ImGui.EndChild()
        ImGui.SameLine()

        -- middle Panel
        if ImGui.BeginChild("Clone Who##who_settings_left", 200, 0.0, ImGuiChildFlags.Border) then
            ImGui.Text("Select Settings to Clone")
            ImGui.Separator()
            LNS_UI.renderSettingsTables(settings.TempSettings.CloneWho)
        end
        ImGui.EndChild()
        ImGui.SameLine()
        -- right panel

        if ImGui.BeginChild("Clone Who##who_settings_right", 200, 0.0, ImGuiChildFlags.Border) then
            ImGui.Text("Select Settings to Apply")
            ImGui.Separator()
            LNS_UI.renderSettingsTables(settings.TempSettings.CloneTo)
        end
        ImGui.EndChild()
    end
    ImGui.End()
end

function LNS_UI.renderSettingsSection(who)
    if who == nil then who = settings.MyName end


    ImGui.SameLine()

    if ImGui.SmallButton("Send Settings##LootnScoot") then
        actors.Send({
            action = 'updatesettings',
            who = who,
            settings = LNS.Boxes[who],
            Server = settings.EqServer,
        })
    end

    ImGui.SameLine()

    if ImGui.SmallButton("Clone Settings##LootnScoot") then
        settings.TempSettings.PopCloneWindow = true
    end
    if ImGui.IsItemHovered() then
        ImGui.BeginTooltip()
        ImGui.PushTextWrapPos(200)
        ImGui.Text("Opens a window to clone settings from one character to another.")
        ImGui.Text("You can select a source character and a destination character.")
        ImGui.Text("The destination character will receive a copy of the source character's settings.")
        ImGui.PopTextWrapPos()
        ImGui.EndTooltip()
    end
    ImGui.Spacing()

    LNS_UI.renderSettingsTables(who)

    ImGui.Spacing()

    if ImGui.CollapsingHeader('SafeZones##LNS') then
        if settings.TempSettings.NewSafeZone == nil then
            settings.TempSettings.NewSafeZone = ''
        end
        ImGui.SetNextItemWidth(150)
        settings.TempSettings.NewSafeZone = ImGui.InputText("New SafeZone Name", settings.TempSettings.NewSafeZone)
        ImGui.SameLine()
        if ImGui.Button('Add') then
            LNS.AddSafeZone(settings.TempSettings.NewSafeZone)
            settings.TempSettings.NewSafeZone = ''
        end
        ImGui.SameLine()
        if ImGui.Button("Add Current Zone") then
            LNS.SafeZones[LNS.Zone] = true
            LNS.AddSafeZone(LNS.Zone)
        end
        ImGui.Separator()
        if ImGui.BeginTable("SafeZones", 2, bit32.bor(ImGuiTableFlags.Borders, ImGuiTableFlags.Resizable, ImGuiTableFlags.ScrollY)) then
            ImGui.TableSetupColumn("Setting", ImGuiTableColumnFlags.WidthStretch)
            ImGui.TableSetupColumn("Delete", ImGuiTableColumnFlags.WidthFixed, 80)
            ImGui.TableHeadersRow()
            ImGui.TableNextRow()

            for settingName, _ in pairs(LNS.SafeZones or {}) do
                if settingName ~= nil then
                    ImGui.TableNextColumn()
                    ImGui.PushID(settingName .. "SafeZone")
                    ImGui.Indent(2)
                    ImGui.Text(settingName)
                    ImGui.Unindent(2)
                    ImGui.TableNextColumn()
                    if ImGui.Button("Delete##" .. settingName) then
                        LNS.SafeZones[settingName] = nil
                        if settings.TempSettings.RemoveSafeZone == nil then
                            settings.TempSettings.RemoveSafeZone = {}
                        end
                        settings.TempSettings.RemoveSafeZone[settingName] = true
                    end
                    ImGui.PopID()
                end
            end
            ImGui.EndTable()
        end
    end
end

function LNS_UI.renderNewItem()
    if ((settings.Settings.AutoShowNewItem and LNS.NewItemsCount > 0) and LNS.showNewItem) or LNS.showNewItem then
        ImGui.SetNextWindowSize(450, 185, ImGuiCond.FirstUseEver)
        local open, show = ImGui.Begin('New Items', true)
        if not open then
            show = false
            LNS.showNewItem = false
        end
        if show then
            LNS_UI.drawNewItemsTable()
        end
        ImGui.End()
    end
end

------------------------------------
--          GUI WINDOWS
------------------------------------

function LNS_UI.RenderMasterLooterWindow()
    if LNS.MasterLootList == nil then return end
    -- if (LNS.MasterLootList ~= nil and #LNS.MasterLootList == 0) then
    --     return
    -- end

    ImGui.SetNextWindowSize(ImVec2(600, 500), ImGuiCond.FirstUseEver)
    local open, show = ImGui.Begin("Master Looter", true)
    if not open then show = false end

    if show then
        if ImGui.BeginTable("MLoot", 3) then
            ImGui.TableSetupColumn("cID", ImGuiTableColumnFlags.WidthFixed, 30)
            ImGui.TableSetupColumn("Item", ImGuiTableColumnFlags.WidthStretch)
            ImGui.TableSetupColumn("Members", ImGuiTableColumnFlags.WidthFixed, 250)
            ImGui.TableHeadersRow()
            ImGui.TableNextRow()
            for cID, cData in pairs(LNS.MasterLootList or {}) do
                if type(cData) == 'table' then
                    for item, itemData in pairs(cData.Items or {}) do
                        ImGui.PushID(cID .. item)
                        ImGui.TableNextColumn()

                        ImGui.Text("%s", cID)

                        ImGui.TableNextColumn()

                        if ImGui.SmallButton(item .. "##ExecLink" .. cID .. item) then
                            mq.cmdf("/executelink %s", itemData.Link)
                        end

                        if ImGui.BeginTable("ItemDetails", 3, bit32.bor(ImGuiTableFlags.Borders)) then
                            ImGui.TableSetupColumn("Value", ImGuiTableColumnFlags.WidthStretch, 100)
                            ImGui.TableSetupColumn("NoDrop", ImGuiTableColumnFlags.WidthFixed, 30)
                            ImGui.TableSetupColumn("Lore", ImGuiTableColumnFlags.WidthFixed, 30)
                            ImGui.TableHeadersRow()
                            ImGui.TableNextRow()

                            ImGui.TableNextColumn()
                            ImGui.Text("%s", LNS.valueToCoins(itemData.Value) or "N/A") -- value
                            ImGui.TableNextColumn()
                            LNS_UI.drawYesNo(itemData.NoDrop)
                            ImGui.TableNextColumn()
                            LNS_UI.drawYesNo(itemData.Lore)
                            ImGui.EndTable()
                        end
                        ImGui.TableNextColumn()

                        if ImGui.SmallButton(Icons.MD_DELETE .. "##MLRemove" .. cID .. item) then
                            Logger.Info(LNS.guiLoot.console, "Removing CorpseID %s Item %s from Master Loot List", cID, item)

                            settings.TempSettings.RemoveItemData = { action = 'item_gone', CorpseID = cID, item = item, Server = settings.EqServer, }
                            settings.TempSettings.SendRemoveItem = true
                        end

                        ImGui.SameLine()

                        if ImGui.SmallButton("Self Loot##" .. cID .. item) then
                            Logger.Info(LNS.guiLoot.console, "Telling \atMySelf\ax to loot \ay%s\ax from CorpseID \ag%s", itemData.Link, cID)
                            -- settings.TempSettings.SendLootInfo = {}
                            -- settings.TempSettings.SendLootInfo =
                            actors.Send({ who = settings.MyName, action = 'loot_item', CorpseID = cID, item = item, Server = settings.EqServer, })
                            -- settings.TempSettings.SendLoot = true
                        end

                        if ImGui.CollapsingHeader("Members##" .. cID .. item) then
                            if ImGui.SmallButton("Refresh Counts##" .. cID .. item) then
                                Logger.Info(LNS.guiLoot.console, "Refreshing Member Counts for CorpseID %s Item %s", cID, item)
                                actors.Send({ who = settings.MyName, action = 'recheck_item', CorpseID = cID, item = item, Server = settings.EqServer, })
                            end
                            if itemData.Members ~= nil and next(itemData.Members) ~= nil then
                                if ImGui.BeginTable('MemberCounts##List', 3, ImGuiTableFlags.Borders) then
                                    ImGui.TableSetupColumn("Member", ImGuiTableColumnFlags.WidthFixed, 110)
                                    ImGui.TableSetupColumn("Count", ImGuiTableColumnFlags.WidthFixed, 30)
                                    ImGui.TableSetupColumn("Loot", ImGuiTableColumnFlags.WidthFixed, 80)
                                    ImGui.TableHeadersRow()
                                    ImGui.TableNextRow()

                                    for _, k in ipairs(LNS.BoxKeys or {}) do
                                        if itemData.Members[k] ~= nil then
                                            local member = k
                                            local count = itemData.Members[k]
                                            -- ImGui.TableNextRow()
                                            ImGui.TableNextColumn()

                                            if ImGui.Selectable(string.format("%s##%s", member, cID .. item)) then
                                                Logger.Info(LNS.guiLoot.console, "Selected member %s for CorpseID %s Item %s", member, cID, item)
                                                actors.Send({ who = member, action = 'loot_item', Server = settings.EqServer, CorpseID = cID, item = item, })
                                            end
                                            ImGui.TableNextColumn()
                                            if count and count > 0 then
                                                ImGui.PushStyleColor(ImGuiCol.Text, ImVec4(1.0, 1.0, 0.0, 1.0))
                                            else
                                                ImGui.PushStyleColor(ImGuiCol.Text, ImVec4(1.0, 1, 1, 1.0))
                                            end
                                            ImGui.Text("%s", count)
                                            ImGui.PopStyleColor()

                                            ImGui.TableNextColumn()

                                            if ImGui.SmallButton('Loot##' .. cID .. item .. member) then
                                                Logger.Info(LNS.guiLoot.console, "Telling \at%s\ax to loot \ay%s\ax from CorpseID \ag%s", member, itemData.Link, cID)
                                                -- settings.TempSettings.SendLootInfo = {}
                                                -- settings.TempSettings.SendLootInfo =
                                                actors.Send({ who = member, action = 'loot_item', Server = settings.EqServer, CorpseID = cID, item = item, })
                                                -- settings.TempSettings.SendLoot = true
                                            end
                                        end
                                    end
                                    ImGui.EndTable()
                                end
                                -- for member, count in pairs(itemData.Members) do
                                --     ImGui.Text("%s: %s", member, count)
                                --     ImGui.SameLine()
                                --     if ImGui.SmallButton('Loot##' .. cID .. item .. member) then
                                --         Logger.Info(LNS.guiLoot.console, "Telling %s to loot %s from CorpseID %s", member, item, cID)
                                --         actors.Send({ who = member, action = 'loot_item', CorpseID = cID, item = item, })
                                --     end
                                -- end
                            end
                        end
                        ImGui.PopID()
                    end
                end
            end
            ImGui.EndTable()
        end
    end
    ImGui.End()
end

function LNS_UI.RenderModifyItemWindow()
    if not settings.TempSettings.ModifyItemRule then
        Logger.Error(LNS.guiLoot.console, "Item not found in ALLITEMS %s %s", settings.TempSettings.ModifyItemID, settings.TempSettings.ModifyItemTable)
        settings.TempSettings.ModifyItemRule = false
        settings.TempSettings.ModifyItemID = nil
        settings.TempSettings.LastModID = 0
        tempValues = {}
        return
    end
    if settings.TempSettings.ModifyItemTable == 'Personal_Items' then
        settings.TempSettings.ModifyItemTable = settings.PersonalTableName
    end
    if settings.TempSettings.ModifyItemTable == nil then
        settings.TempSettings.ModifyItemTable = settings.TempSettings.LastModTable or 'Normal_Items'
    end
    -- local missingTable = settings.TempSettings.ModifyItemTable:gsub("_Items", "")
    local classes = settings.TempSettings.ModifyClasses
    local rule = settings.TempSettings.ModifyItemSetting

    ImGui.SetNextWindowSizeConstraints(ImVec2(300, 200), ImVec2(-1, -1))
    local open, show = ImGui.Begin("Modify Item", nil, ImGuiWindowFlags.AlwaysAutoResize)
    if show then
        local item = LNS.ALLITEMS[settings.TempSettings.ModifyItemID]
        if not item then
            item = {
                Name = settings.TempSettings.ModifyItemName,
                Link = settings.TempSettings.ModifyItemLink,
                RaceList = settings.TempSettings.ModifyItemRaceList,
            }
        end
        local questRule = "Quest"
        if item == nil then
            Logger.Error(LNS.guiLoot.console, "Item not found in ALLITEMS %s %s", settings.TempSettings.ModifyItemID, settings.TempSettings.ModifyItemTable)
            ImGui.End()
            return
        end
        ImGui.TextUnformatted("Item:")
        ImGui.SameLine()
        ImGui.TextColored(ImVec4(0, 1, 1, 1), item.Name)
        ImGui.SameLine()
        ImGui.TextUnformatted("ID:")
        ImGui.SameLine()
        ImGui.TextColored(ImVec4(1, 1, 0, 1), "%s", settings.TempSettings.ModifyItemID)

        -- if ImGui.BeginCombo("Table", settings.TempSettings.ModifyItemTable) then
        --     for i, v in ipairs(tableList) do
        --         if ImGui.Selectable(v, settings.TempSettings.ModifyItemTable == v) then
        --             settings.TempSettings.ModifyItemTable = v
        --         end
        --     end
        --     ImGui.EndCombo()
        -- end
        if ImGui.RadioButton("Personal Items", settings.TempSettings.ModifyItemTable == settings.PersonalTableName) then
            settings.TempSettings.ModifyItemTable = settings.PersonalTableName
        end
        ImGui.SameLine()
        if ImGui.RadioButton("Global Items", settings.TempSettings.ModifyItemTable == "Global_Items") then
            settings.TempSettings.ModifyItemTable = "Global_Items"
        end
        ImGui.SameLine()
        if ImGui.RadioButton("Normal Items", settings.TempSettings.ModifyItemTable == "Normal_Items") then
            settings.TempSettings.ModifyItemTable = "Normal_Items"
        end

        if tempValues.Classes == nil and classes ~= nil then
            tempValues.Classes = classes
        end

        ImGui.SetNextItemWidth(100)
        tempValues.Classes = ImGui.InputTextWithHint("Classes", "who can loot or all ex: shm clr dru", tempValues.Classes)

        ImGui.SameLine()
        LNS.TempModClass = ImGui.Checkbox("All", LNS.TempModClass)

        if tempValues.Rule == nil then
            if rule ~= nil then
                tempValues.Rule = rule
            else
                tempValues.Rule = 'Ask'
            end
        end

        ImGui.SetNextItemWidth(100)
        if ImGui.BeginCombo("Rule", tempValues.Rule, ImGuiComboFlags.HeightLarge) then
            for i, v in ipairs(settingList) do
                if ImGui.Selectable(v, tempValues.Rule == v) then
                    tempValues.Rule = v
                end
            end
            ImGui.EndCombo()
        end

        if tempValues.Rule == "Quest" then
            ImGui.SameLine()
            ImGui.SetNextItemWidth(100)
            tempValues.Qty = ImGui.InputInt("QuestQty", tempValues.Qty, 1, 1)
            if tempValues.Qty > 0 then
                questRule = string.format("Quest|%s", tempValues.Qty)
            end
        end

        if ImGui.Button("Set Rule") then
            local newRule = tempValues.Rule == "Quest" and questRule or tempValues.Rule
            if tempValues.Classes == nil or tempValues.Classes == '' or LNS.TempModClass then
                tempValues.Classes = "All"
            end
            -- loot.modifyItemRule(loot.TempSettings.ModifyItemID, newRule, loot.TempSettings.ModifyItemTable, tempValues.Classes, item.Link)
            if settings.TempSettings.ModifyItemTable == settings.PersonalTableName then
                LNS.PersonalItemsRules[settings.TempSettings.ModifyItemID] = newRule
                LNS.setPersonalItem(settings.TempSettings.ModifyItemID, newRule, tempValues.Classes, item.Link)
            elseif settings.TempSettings.ModifyItemTable == "Global_Items" then
                LNS.GlobalItemsRules[settings.TempSettings.ModifyItemID] = newRule
                LNS.setGlobalItem(settings.TempSettings.ModifyItemID, newRule, tempValues.Classes, item.Link)
            else
                LNS.NormalItemsRules[settings.TempSettings.ModifyItemID] = newRule
                LNS.setNormalItem(settings.TempSettings.ModifyItemID, newRule, tempValues.Classes, item.Link)
            end
            -- loot.setNormalItem(loot.TempSettings.ModifyItemID, newRule,  tempValues.Classes, item.Link)
            settings.TempSettings.ModifyItemRule = false
            settings.TempSettings.ModifyItemID = nil
            settings.TempSettings.LastModTable = settings.TempSettings.ModifyItemTable
            settings.TempSettings.ModifyItemTable = nil
            settings.TempSettings.ModifyItemClasses = 'All'
            settings.TempSettings.ModifyItemName = nil
            settings.TempSettings.ModifyItemLink = nil
            LNS.TempModClass = false
            settings.TempSettings.LastModID = 0
            ImGui.End()
            return
        end
        ImGui.SameLine()

        ImGui.PushStyleColor(ImGuiCol.Button, ImVec4(1.0, 0.4, 0.4, 0.4))
        if ImGui.Button(Icons.FA_TRASH) then
            if settings.TempSettings.ModifyItemTable == settings.PersonalTableName then
                LNS.PersonalItemsRules[settings.TempSettings.ModifyItemID] = nil
                LNS.setPersonalItem(settings.TempSettings.ModifyItemID, 'delete', 'All', 'NULL')
            elseif settings.TempSettings.ModifyItemTable == "Global_Items" then
                -- loot.GlobalItemsRules[loot.TempSettings.ModifyItemID] = nil
                LNS.setGlobalItem(settings.TempSettings.ModifyItemID, 'delete', 'All', 'NULL')
            else
                LNS.setNormalItem(settings.TempSettings.ModifyItemID, 'delete', 'All', 'NULL')
            end
            settings.TempSettings.ModifyItemRule = false
            settings.TempSettings.ModifyItemID = nil
            settings.TempSettings.ModifyItemTable = nil
            settings.TempSettings.ModifyItemClasses = 'All'
            settings.TempSettings.ModifyItemMatches = nil
            settings.TempSettings.ModifyItemName = nil
            settings.TempSettings.LastModID = 0

            ImGui.PopStyleColor()

            ImGui.End()
            return
        end
        ImGui.PopStyleColor()
        ImGui.SameLine()
        if ImGui.Button("Cancel") then
            settings.TempSettings.ModifyItemRule = false
            settings.TempSettings.ModifyItemID = nil
            settings.TempSettings.ModifyItemTable = nil
            settings.TempSettings.ModifyItemClasses = 'All'
            settings.TempSettings.ModifyItemName = nil
            settings.TempSettings.ModifyItemLink = nil
            settings.TempSettings.ModifyItemMatches = nil
            settings.TempSettings.LastModID = 0
        end

        if settings.TempSettings.ModifyItemMatches ~= nil then
            local oldID = settings.TempSettings.ModifyItemID
            local newRule = tempValues.Rule == "Quest" and questRule or tempValues.Rule
            if tempValues.Classes == nil or tempValues.Classes == '' or LNS.TempModClass then
                tempValues.Classes = "All"
            end
            if ImGui.BeginTable("Matches##LNS.ModifyItemMatches", 3, bit32.bor(ImGuiTableFlags.Borders, ImGuiTableFlags.Resizable, ImGuiTableFlags.ScrollY), ImVec2(300, 200)) then
                ImGui.TableSetupColumn("itemID", ImGuiTableColumnFlags.WidthStretch)
                ImGui.TableSetupColumn("itemName", ImGuiTableColumnFlags.WidthStretch)
                ImGui.TableSetupColumn("Set", ImGuiTableColumnFlags.WidthFixed, 80)
                ImGui.TableHeadersRow()
                ImGui.TableNextRow()

                --[[
retTable[row.item_id] = {
item_id = row.item_id,
item_name = row.name,
item_rule = row.item_rule or 'None',
item_classes = row.item_rule_classes or 'All',
item_link = row.link or 'NULL',
}]]
                for id, data in pairs(settings.TempSettings.ModifyItemMatches) do
                    ImGui.TableNextColumn()
                    ImGui.Text("%s", id)

                    ImGui.TableNextColumn()
                    if ImGui.Selectable(data.item_name .. "##" .. id, false) then
                        mq.cmdf('/executelink %s', data.item_link)
                    end

                    ImGui.TableNextColumn()
                    if ImGui.Button(Icons.FA_CHECK .. "##" .. id) then
                        if settings.TempSettings.ModifyItemTable == settings.PersonalTableName then
                            LNS.setPersonalItem(id, newRule, tempValues.Classes, LNS.ItemLinks[id])
                            LNS.PersonalItemsMissing[oldID] = nil
                            LNS.PersonalItemsRules[oldID] = nil
                            LNS.PersonalItemsClasses[oldID] = nil
                            LNS.setPersonalItem(oldID, 'delete', 'All', 'NULL')
                        elseif settings.TempSettings.ModifyItemTable == "Global_Items" then
                            -- loot.GlobalItemsRules[loot.TempSettings.ModifyItemID] = nil
                            LNS.setGlobalItem(id, newRule, tempValues.Classes, LNS.ItemLinks[id])
                            LNS.GlobalItemsMissing[oldID] = nil
                            LNS.GlobalItemsRules[oldID] = nil
                            LNS.GlobalItemsClasses[oldID] = nil
                            LNS.setGlobalItem(oldID, 'delete', 'All', 'NULL')
                        else
                            LNS.setNormalItem(id, newRule, tempValues.Classes, LNS.ItemLinks[id])
                            LNS.NormalItemsMissing[oldID] = nil
                            LNS.NormalItemsRules[oldID] = nil
                            LNS.NormalItemsClasses[oldID] = nil
                            LNS.setNormalItem(oldID, 'delete', 'All', 'NULL')
                        end

                        LNS.ItemNames[oldID] = nil
                        settings.TempSettings.ModifyItemRule = false
                        settings.TempSettings.ModifyItemID = nil
                        settings.TempSettings.ModifyItemTable = nil
                        settings.TempSettings.ModifyItemClasses = 'All'
                        settings.TempSettings.ModifyItemMatches = nil
                        settings.TempSettings.LastModID = 0
                        ImGui.EndTable()
                        ImGui.End()
                        return
                    end
                end
                ImGui.EndTable()
            end
            --settings.TempSettings.ModifyItemMatches
        end
    end
    if not open then
        settings.TempSettings.ModifyItemRule = false
        settings.TempSettings.ModifyItemID = nil
        settings.TempSettings.ModifyItemTable = nil
        settings.TempSettings.ModifyItemClasses = 'All'
        settings.TempSettings.ModifyItemName = nil
        settings.TempSettings.ModifyItemLink = nil
        settings.TempSettings.ModifyItemMatches = nil
        settings.TempSettings.LastModID = 0
    end
    ImGui.End()
end

function LNS_UI.DrawRecord(tableToDraw)
    if not settings.TempSettings.PastHistory then return end
    if tableToDraw == nil then tableToDraw = settings.TempSettings.SessionHistory or {} end
    if LNS.HistoryDataDate ~= nil and #LNS.HistoryDataDate > 0 then
        tableToDraw = LNS.HistoryDataDate
    elseif LNS.HistoryItemData ~= nil and #LNS.HistoryItemData > 0 then
        tableToDraw = LNS.HistoryItemData
    end
    local openWin, showRecord = ImGui.Begin("Loot PastHistory##", true)
    if not openWin then
        settings.TempSettings.PastHistory = false
    end

    if showRecord then
        if settings.TempSettings.DateLookup == nil then
            settings.TempSettings.DateLookup = os.date("%Y-%m-%d")
        end
        ImGui.SetNextItemWidth(150)
        if ImGui.BeginCombo('##', settings.TempSettings.DateLookup) then
            for i, v in ipairs(LNS.HistoricalDates) do
                if ImGui.Selectable(v, settings.TempSettings.DateLookup == v) then
                    settings.TempSettings.DateLookup = v
                end
            end
            ImGui.EndCombo()
        end
        ImGui.SameLine()
        if ImGui.SmallButton(Icons.FA_CALENDAR .. "Load Date") then
            settings.TempSettings.LookUpDateData = true
            LNS.lookupDate = settings.TempSettings.DateLookup
        end
        if ImGui.IsItemHovered() then
            ImGui.SetTooltip("Load Data for %s", settings.TempSettings.DateLookup)
        end
        ImGui.SameLine()
        if ImGui.SmallButton(Icons.MD_TIMELAPSE .. 'Session') then
            settings.TempSettings.ClearDateData = true
        end
        if ImGui.IsItemHovered() then
            ImGui.SetTooltip("This Session Only", settings.TempSettings.DateLookup)
        end
        if settings.TempSettings.FilterHistory == nil then
            settings.TempSettings.FilterHistory = ''
        end
        -- Pagination Variables
        local filteredTable = {}
        for i = 1, #tableToDraw do
            local item = tableToDraw[i]
            if item then
                if settings.TempSettings.FilterHistory ~= '' then
                    local filterString = settings.TempSettings.FilterHistory:lower()
                    filterString = filterString:gsub("%:", ""):gsub("%-", "")
                    local filterTS = item.TimeStamp:gsub("%:", ""):gsub("%-", "")
                    local filterDate = item.Date:gsub("%:", ""):gsub("%-", "")
                    if not (string.find(item.Item:lower(), filterString) or
                            string.find(filterDate, filterString) or
                            string.find(filterTS, filterString) or
                            string.find(item.Looter:lower(), filterString) or
                            string.find(item.Action:lower(), filterString) or
                            string.find(item.CorpseName:lower(), filterString) or
                            string.find(item.Zone:lower(), filterString)) then
                        goto continue
                    end
                end
                table.insert(filteredTable, item)
            end
            ::continue::
        end
        table.sort(filteredTable, function(a, b)
            return a.Date .. a.TimeStamp > b.Date .. b.TimeStamp
        end)
        ImGui.SeparatorText("Loot History")
        LNS.histItemsPerPage = LNS.histItemsPerPage or 20 -- Items per page
        LNS.histCurrentPage = LNS.histCurrentPage or 1
        local totalItems = #tableToDraw
        local totalFilteredItems = #filteredTable
        local totalPages = math.max(1, math.ceil(totalFilteredItems / LNS.histItemsPerPage))

        -- Filter Input

        ImGui.SetNextItemWidth(150)
        settings.TempSettings.FilterHistory = ImGui.InputTextWithHint("##FilterHistory", "Filter by Fields", settings.TempSettings.FilterHistory)
        ImGui.SameLine()
        if ImGui.SmallButton(Icons.MD_DELETE_SWEEP) then
            settings.TempSettings.FilterHistory = ''
        end
        ImGui.SameLine()
        if ImGui.SmallButton(Icons.MD_SEARCH) then
            settings.TempSettings.FindItemHistory = true
        end
        ImGui.SameLine()
        ImGui.Text("Found: ")
        ImGui.SameLine()
        ImGui.TextColored(ImVec4(0, 1, 1, 1), tostring(totalFilteredItems))
        ImGui.SameLine()
        ImGui.Text("Total: ")
        ImGui.SameLine()
        ImGui.TextColored(ImVec4(1, 1, 0, 1), tostring(totalItems))

        -- Clamp the current page
        LNS.histCurrentPage = math.max(1, math.min(LNS.histCurrentPage, totalPages))

        -- Navigation Buttons
        if ImGui.Button(Icons.FA_BACKWARD) then
            LNS.histCurrentPage = 1
        end
        ImGui.SameLine()
        if ImGui.ArrowButton("##Previous", ImGuiDir.Left) and LNS.histCurrentPage > 1 then
            LNS.histCurrentPage = LNS.histCurrentPage - 1
        end
        ImGui.SameLine()
        ImGui.Text(string.format("Page %d of %d", LNS.histCurrentPage, totalPages))
        ImGui.SameLine()
        if ImGui.ArrowButton("##Next", ImGuiDir.Right) and LNS.histCurrentPage < totalPages then
            LNS.histCurrentPage = LNS.histCurrentPage + 1
        end
        ImGui.SameLine()
        if ImGui.Button(Icons.FA_FORWARD) then
            LNS.histCurrentPage = totalPages
        end

        ImGui.SameLine()

        ImGui.Text("Items Per Page")
        ImGui.SameLine()
        ImGui.SetNextItemWidth(80)
        if ImGui.BeginCombo('##pageSize', tostring(LNS.histItemsPerPage)) then
            for i = 1, 200 do
                if i % 25 == 0 then
                    if ImGui.Selectable(tostring(i), LNS.histItemsPerPage == i) then
                        LNS.histItemsPerPage = i
                    end
                end
            end
            ImGui.EndCombo()
        end


        -- Table

        if ImGui.BeginTable("Items History", 7, bit32.bor(ImGuiTableFlags.ScrollX, ImGuiTableFlags.ScrollY,
                ImGuiTableFlags.Hideable, ImGuiTableFlags.Reorderable, ImGuiTableFlags.Resizable, ImGuiTableFlags.Borders, ImGuiTableFlags.RowBg)) then
            ImGui.TableSetupColumn("Date", ImGuiTableColumnFlags.WidthFixed, 100)
            ImGui.TableSetupColumn("TimeStamp", ImGuiTableColumnFlags.WidthFixed, 100)
            ImGui.TableSetupColumn("Item", ImGuiTableColumnFlags.WidthFixed, 150)
            ImGui.TableSetupColumn("Looter", ImGuiTableColumnFlags.WidthFixed, 75)
            ImGui.TableSetupColumn("Action", ImGuiTableColumnFlags.WidthFixed, 75)
            ImGui.TableSetupColumn("Corpse", ImGuiTableColumnFlags.WidthFixed, 100)
            ImGui.TableSetupColumn("Zone", ImGuiTableColumnFlags.WidthFixed, 100)
            ImGui.TableHeadersRow()
            ImGui.TableNextRow()

            -- Calculate start and end indices for pagination
            local startIdx = (LNS.histCurrentPage - 1) * LNS.histItemsPerPage + 1
            local endIdx = math.min(startIdx + LNS.histItemsPerPage - 1, totalFilteredItems)

            for i = startIdx, endIdx do
                local item = filteredTable[i]
                if item then
                    if settings.TempSettings.FilterHistory ~= '' then
                        local filterString = settings.TempSettings.FilterHistory:lower()
                        filterString = filterString:gsub("%:", ""):gsub("%-", "")
                        local filterTS = item.TimeStamp:gsub("%:", ""):gsub("%-", "")
                        local filterDate = item.Date:gsub("%:", ""):gsub("%-", "")
                        if not (string.find(item.Item:lower(), filterString) or
                                string.find(filterDate, filterString) or
                                string.find(filterTS, filterString) or
                                string.find(item.Looter:lower(), filterString) or
                                string.find(item.Action:lower(), filterString) or
                                string.find(item.CorpseName:lower(), filterString) or
                                string.find(item.Zone:lower(), filterString)) then
                            goto continue
                        end
                    end

                    ImGui.TableNextColumn()
                    ImGui.TextColored(ImVec4(1, 1, 0, 1), item.Date)
                    ImGui.TableNextColumn()
                    ImGui.TextColored(ImVec4(0, 1, 1, 1), item.TimeStamp)
                    ImGui.TableNextColumn()
                    ImGui.Text(item.Item)
                    if ImGui.IsItemHovered() and ImGui.IsItemClicked(0) then
                        mq.cmdf('/executelink %s', item.Link)
                    end
                    ImGui.TableNextColumn()
                    ImGui.TextColored(ImVec4(1.000, 0.557, 0.000, 1.000), item.Looter)
                    ImGui.TableNextColumn()
                    if item.Action:find('Global') then
                        ImGui.PushStyleColor(ImGuiCol.Text, ImVec4(0.523, 0.797, 0.944, 1.000))
                        ImGui.Text(Icons.FA_GLOBE)
                        ImGui.PopStyleColor()
                        ImGui.SameLine()
                    end
                    ImGui.Text(item.Action == 'Looted' and 'Keep' or item.Action:gsub('Global ', ''))
                    ImGui.TableNextColumn()
                    ImGui.TextColored(ImVec4(0.976, 0.518, 0.844, 1.000), item.CorpseName)
                    ImGui.TableNextColumn()
                    ImGui.Text(item.Zone)
                    ::continue::
                end
            end
            ImGui.EndTable()
        end
    end

    ImGui.End()
end

local function RenderBtn()
    -- apply_style()

    ImGui.PushStyleVar(ImGuiStyleVar.WindowPadding, ImVec2(9, 9))
    ImGui.PushStyleVar(ImGuiStyleVar.WindowRounding, 0)
    local openBtn, showBtn = ImGui.Begin(string.format("LootNScoot##Mini"), true,
        bit32.bor(ImGuiWindowFlags.AlwaysAutoResize, ImGuiWindowFlags.NoTitleBar, ImGuiWindowFlags.NoCollapse))
    if not openBtn then
        showBtn = false
    end

    if showBtn then
        local btnLbl = '##LNSBtn'
        local cursorX, cursorY = ImGui.GetCursorScreenPos()    -- grab location for later to draw button over icon.
        if LNS.NewItemsCount > 0 then
            iconAnimation:SetTextureCell(645 - EQ_ICON_OFFSET) -- gold coin
        else
            iconAnimation:SetTextureCell(644 - EQ_ICON_OFFSET) -- platinum coin
        end
        if LNS.PauseLooting then
            iconAnimation:SetTextureCell(1436 - EQ_ICON_OFFSET) -- red gem
            btnLbl = 'Paused##LNSBtn'
        end
        ImGui.DrawTextureAnimation(iconAnimation, 34, 34, true)

        -- draw invis button over icoon
        ImGui.SetCursorScreenPos(cursorX, cursorY)
        ImGui.PushStyleColor(ImGuiCol.Button, ImVec4(0, 0, 0, 0))
        ImGui.PushStyleColor(ImGuiCol.ButtonHovered, ImVec4(1.0, 0.5, 0.2, 0.5))
        ImGui.PushStyleColor(ImGuiCol.ButtonActive, ImVec4(0, 0, 0, 0))
        if ImGui.Button(btnLbl, ImVec2(34, 34)) then
            LNS.ShowUI = not LNS.ShowUI
        end
        ImGui.PopStyleColor(3)
        if ImGui.BeginPopupContextItem("##LootNScoot") then
            if ImGui.MenuItem("Show/Hide LootnScoot") then
                LNS.ShowUI = not LNS.ShowUI
            end
            if LNS.NewItemsCount > 0 then
                if ImGui.MenuItem("Show New Items") then
                    LNS.showNewItem = not LNS.showNewItem
                end
            end
            if ImGui.MenuItem("Toggle Pause Looting") then
                LNS.PauseLooting = not LNS.PauseLooting
            end
            _, LNS.debugPrint = ImGui.MenuItem(Icons.FA_BUG .. " Debug", nil, LNS.debugPrint)
            ImGui.EndPopup()
        end

        -- tooltip and right click event
        if ImGui.IsItemHovered() then
            ImGui.BeginTooltip()
            ImGui.Text("LootnScoot")
            ImGui.Text("Click to Show/Hide")
            ImGui.EndTooltip()
        end

        -- ctrl right click toggle option
        if (ImGui.IsKeyDown(ImGuiMod.Ctrl) and ImGui.IsMouseClicked(2)) then
            LNS.ShowUI = not LNS.ShowUI
        end
    end
    ImGui.PopStyleVar(2)
    ImGui.End()
end

function LNS_UI.RenderMainUI()
    if LNS.ShowUI then
        ImGui.SetNextWindowSize(800, 600, ImGuiCond.FirstUseEver)
        local open, show = ImGui.Begin('LootnScoot', true)
        if not open then
            show = false
            LNS.ShowUI = false
        end
        if show then
            ImGui.PushStyleColor(ImGuiCol.PopupBg, ImVec4(0.002, 0.009, 0.082, 0.991))
            local clicked = false
            LNS.debugPrint, clicked = LNS_UI.DrawToggle("Debug##Toggle",
                LNS.debugPrint,
                ImVec4(0.4, 1.0, 0.4, 0.4),
                ImVec4(1.0, 0.4, 0.4, 0.4),
                16, 36)
            if clicked then
                Logger.Warn(LNS.guiLoot.console, "\ayDebugging\ax is now %s", LNS.debugPrint and "\agon" or "\aroff")
            end
            ImGui.SameLine()

            if ImGui.SmallButton(Icons.MD_HELP_OUTLINE) then
                settings.TempSettings.ShowHelp = not settings.TempSettings.ShowHelp
            end
            if ImGui.IsItemHovered() then
                ImGui.SetTooltip("Show/Hide Help Window")
            end

            ImGui.SameLine()
            if ImGui.SmallButton(string.format("%s Report", Icons.MD_INSERT_CHART)) then
                -- loot.guiLoot.showReport = not loot.guiLoot.showReport
                settings.Settings.ShowReport = not settings.Settings.ShowReport
                LNS.guiLoot.GetSettings(settings.Settings.HideNames,

                    settings.Settings.RecordData,
                    true,
                    settings.Settings.UseActors,
                    'lootnscoot',
                    settings.Settings.ShowReport,
                    settings.Settings.ReportSkippedItems)
                settings.TempSettings.NeedSave = true
            end
            if ImGui.IsItemHovered() then ImGui.SetTooltip("Show/Hide Report Window") end

            ImGui.SameLine()

            if ImGui.SmallButton(Icons.MD_HISTORY .. " Historical") then
                settings.TempSettings.PastHistory = not settings.TempSettings.PastHistory
            end
            if ImGui.IsItemHovered() then ImGui.SetTooltip("Show/Hide Historical Data") end

            ImGui.SameLine()


            if ImGui.SmallButton(string.format("%s Console", Icons.FA_TERMINAL)) then
                LNS.guiLoot.openGUI = not LNS.guiLoot.openGUI
                settings.Settings.ShowConsole = LNS.guiLoot.openGUI
                settings.TempSettings.NeedSave = true
            end
            if ImGui.IsItemHovered() then ImGui.SetTooltip("Show/Hide Console Window") end

            ImGui.SameLine()

            local labelBtn = not showSettings and
                string.format("%s Settings", Icons.FA_COG) or string.format("%s   Items  ", Icons.FA_SHOPPING_BASKET)
            if showSettings and LNS.NewItemsCount > 0 then
                ImGui.PushStyleColor(ImGuiCol.Button, ImVec4(1.0, 0.4, 0.4, 0.4))
                if ImGui.SmallButton(labelBtn) then
                    showSettings = not showSettings
                end
                ImGui.PopStyleColor()
            else
                if ImGui.SmallButton(labelBtn) then
                    showSettings = not showSettings
                end
            end

            ImGui.SameLine()

            if ImGui.SmallButton(string.format('%s Perf', Icons.FA_AREA_CHART)) then
                perf.EnablePerfMonitoring = not perf.EnablePerfMonitoring
            end

            ImGui.Spacing()
            ImGui.Separator()
            ImGui.Spacing()
            -- Settings Section
            if showSettings then
                if settings.TempSettings.SelectedActor == nil then
                    settings.TempSettings.SelectedActor = settings.MyName
                end
                ImGui.Indent(2)
                ImGui.TextWrapped("You can change any setting by issuing `/lootutils set settingname value` use [on|off] for true false values.")
                ImGui.TextWrapped("You can also change settings for other characters by selecting them from the dropdown.")
                ImGui.Unindent(2)
                ImGui.Spacing()

                ImGui.Separator()
                ImGui.Spacing()
                ImGui.SetNextItemWidth(180)
                if ImGui.BeginCombo("Select Actor", settings.TempSettings.SelectedActor) then
                    for k, v in pairs(LNS.Boxes) do
                        if ImGui.Selectable(k, settings.TempSettings.SelectedActor == k) then
                            settings.TempSettings.SelectedActor = k
                        end
                    end
                    ImGui.EndCombo()
                end
                LNS_UI.renderSettingsSection(settings.TempSettings.SelectedActor)
            else
                -- Items and Rules Section
                LNS_UI.drawItemsTables()
            end
            ImGui.PopStyleColor()
        end

        ImGui.End()
    end
end

function LNS_UI.RenderUIs()
    -- local pcallSuccess, pcallResult = pcall(function()
    local colCount, styCount = LNS.guiLoot.DrawTheme()

    if LNS.NewItemDecisions ~= nil then
        LNS.enterNewItemRuleInfo(LNS.NewItemDecisions)
        LNS.NewItemDecisions = nil
    end

    if settings.TempSettings.ModifyItemRule then
        -- check if we need to modify an item.
        if settings.TempSettings.ModifyItemRule and settings.TempSettings.ModifyItemID < 0 and settings.TempSettings.LastModID ~= settings.TempSettings.ModifyItemID then
            settings.TempSettings.LastModID = settings.TempSettings.ModifyItemID
            Logger.Info(LNS.guiLoot.console, "Searching for item matches for: \at%s\ax", settings.TempSettings.ModifyItemName)
            local count = 0
            settings.TempSettings.ModifyItemMatches = {}
            _, settings.TempSettings.ModifyItemMatches = LNS.findItem(settings.TempSettings.ModifyItemName, nil, true)
            Logger.Info(LNS.guiLoot.console, "Found \ag%s\ax matches for: \at%s\ax", #settings.TempSettings.ModifyItemMatches, settings.TempSettings.ModifyItemName)
            for k, v in pairs(settings.TempSettings.ModifyItemMatches or {}) do
                Logger.Info(LNS.guiLoot.console, "Match: \ag%s\ax - \at%s\ax", v.item_id, v.item_name)
            end
        end

        LNS_UI.RenderModifyItemWindow()
    end

    if LNS.NewItemsCount > 0 then
        LNS_UI.renderNewItem()
        for k, v in pairs(settings.TempSettings.Popped or {}) do
            if k ~= nil and v then
                LNS_UI.Draw_item_info_window(k)
            end
        end
    end

    if LNS.pendingItemData ~= nil then
        LNS.processPendingItem()
    end

    if settings.TempSettings.ShowImportDB then
        LNS_UI.renderImportDBWindow()
    end

    LNS_UI.RenderMainUI()

    RenderBtn()

    LNS_UI.renderCloneWindow()

    if LNS.MasterLootList ~= nil and next(LNS.MasterLootList) ~= nil then
        LNS_UI.RenderMasterLooterWindow()
    end

    if settings.TempSettings.ShowMailbox then
        LNS_UI.DebugMailBox()
    end

    LNS_UI.renderHelpWindow()

    if settings.TempSettings.PastHistory then
        LNS_UI.DrawRecord()
    end

    if perf:ShouldRender() then perf:Render() end

    if colCount > 0 then ImGui.PopStyleColor(colCount) end
    if styCount > 0 then ImGui.PopStyleVar(styCount) end
    -- end)
    -- if not pcallSuccess then
    --     Logger.Info(LNS.guiLoot.console, "Error in LNS UI: %s", pcallResult)
    -- end
end

function LNS_UI.DebugMailBox()
    if not settings.TempSettings.ShowMailbox then return end
    if not LNS.debugPrint then
        settings.TempSettings.MailBox = nil
        return
    end

    ImGui.SetNextWindowSize(400, 300, ImGuiCond.FirstUseEver)
    local open, show = ImGui.Begin("MailBox Debug##", true)
    if not open then
        show = false
    end

    if show then
        ImGui.Text("MailBox Debug")
        ImGui.SameLine()
        if ImGui.Button(Icons.FA_TRASH) then
            settings.TempSettings.MailBox = nil
            settings.TempSettings.MPS = nil
        end

        ImGui.SameLine()
        if settings.TempSettings.MailboxFilter == nil then
            settings.TempSettings.MailboxFilter = ''
        end
        ImGui.SetNextItemWidth(150)
        settings.TempSettings.MailboxFilter = ImGui.InputTextWithHint("##MailBoxFilter", "Filter by Fields", settings.TempSettings.MailboxFilter)

        ImGui.Text("Messages:")
        ImGui.SameLine()
        ImGui.TextColored(ImVec4(0, 1, 1, 1), "%d", (settings.TempSettings.MailBox ~= nil and (#settings.TempSettings.MailBox or 0) or 0))
        ImGui.SameLine()
        ImGui.Text("Mps:")
        ImGui.SameLine()
        ImGui.TextColored(ImVec4(1, 1, 0, 1), "%0.2f", settings.TempSettings.MPS or 0.0)
        ImGui.Spacing()
        ImGui.Separator()
        ImGui.Spacing()
        local sizeX, sizeY = ImGui.GetContentRegionAvail()

        if ImGui.BeginTable("MailBox", 3, bit32.bor(ImGuiTableFlags.Borders, ImGuiTableFlags.Resizable, ImGuiTableFlags.ScrollY), ImVec2(0, sizeY - 10)) then
            ImGui.TableSetupColumn("Time", ImGuiTableColumnFlags.WidthFixed, 80)
            ImGui.TableSetupColumn("Subject", ImGuiTableColumnFlags.WidthFixed, 100)
            ImGui.TableSetupColumn("Sender", ImGuiTableColumnFlags.WidthFixed, 100)
            ImGui.TableHeadersRow()
            ImGui.TableNextRow()

            for _, Data in ipairs(settings.TempSettings.MailBox or {}) do
                if settings.TempSettings.MailboxFilter == '' or ((Data.Subject:lower():find(settings.TempSettings.MailboxFilter:lower()) or
                        Data.Sender:lower():find(settings.TempSettings.MailboxFilter:lower()))) then
                    ImGui.TableNextColumn()
                    ImGui.Text(Data.Time)
                    ImGui.TableNextColumn()
                    ImGui.Text(Data.Subject)
                    ImGui.TableNextColumn()
                    ImGui.Text(Data.Sender)
                end
            end

            ImGui.EndTable()
        end
    end

    ImGui.End()
end

return LNS_UI
