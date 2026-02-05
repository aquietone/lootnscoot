-- -@diagnostic disable: undefined-global, param-type-mismatch
-- -@diagnostic disable: undefined-field

local mq              = require 'mq'
local PackageMan      = require('mq.PackageMan')
local sql             = PackageMan.Require('lsqlite3')
local Files           = require('mq.Utils')
local success, Logger = pcall(require, 'lib.Logger')
local actors          = require('modules.actor')
local db              = require('modules.db')
local perf            = require('modules.performance')
local settings        = require('modules.settings')
local ui              = require('modules.ui')
-- local MasterLooter = require('MasterLooter')

if not success then
    printf('\arERROR: Write.lua could not be loaded\n%s\ax', Logger)
    return
end
local version                           = 6
local SettingsFile                      = string.format('%s/LootNScoot/%s/%s.lua', mq.configDir, settings.EqServer, settings.MyName)
local lootDBUpdateFile                  = string.format('%s/LootNScoot/%s/DB_Updated.lua', mq.configDir, settings.EqServer)
local zoneID                            = 0
local ProcessItemsState                 = nil
local reportPrefixEQChat                = '/%s '
local reportPrefix                      = '/%s \a-t[\at%s\a-t][\ax\ayLootUtils\ax\a-t]\ax '
Logger.prefix                           = "[\atLootnScoot\ax] "
local eqChatChannels                    = { g = true, gu = true, rs = true, say = true, }
-- Internal settings
local cantLootList                      = {}
local cantLootID                        = 0
local itemNoValue                       = nil
local skippedLoots                      = {}
local allItems                          = {}
local foragingLoot                      = false
-- Constants
local spawnSearch                       = '%s radius %d zradius %s'
local shouldLootActions                 = { Ask = false, CanUse = false, Keep = true, Bank = true, Sell = true, Destroy = false, Ignore = false, Tribute = false, Quest = false, }
local validActions                      = {
    ask = "Ask",
    canuse = "CanUse",
    keep = 'Keep',
    bank = 'Bank',
    sell = 'Sell',
    ignore = 'Ignore',
    destroy = 'Destroy',
    quest = 'Quest',
    tribute = 'Tribute',
}
local NEVER_SELL                        = { ['Diamond Coin'] = true, ['Celestial Crest'] = true, ['Gold Coin'] = true, ['Taelosian Symbols'] = true, ['Planar Symbols'] = true, }

local doSell, doBuy, doTribute, areFull = false, false, false, false

-- local SECTIONS = {
--     ['NormalItems']='Normal_Rules',
--     ['GlobalItems']='Global_Rules',
--     ['PersonalItems']=settings.PersonalTableName,
-- }

local equipSlots                        = {
    [0] = 'Charm',
    [1] = 'Ears',
    [2] = 'Head',
    [3] = 'Face',
    [4] = 'Ears',
    [5] = 'Neck',
    [6] = 'Shoulder',
    [7] = 'Arms',
    [8] = 'Back',
    [9] = 'Wrists',
    [10] = 'Wrists',
    [11] = 'Ranged',
    [12] = 'Hands',
    [13] = 'Primary',
    [14] = 'Secondary',
    [15] = 'Fingers',
    [16] = 'Fingers',
    [17] = 'Chest',
    [18] = 'Legs',
    [19] = 'Feet',
    [20] = 'Waist',
    [21] = 'Powersource',
    [22] = 'Ammo',
}
-- Public default settings, also read in from Loot.ini [Settings] section


-- Module Settings
local LNS   = {}

LNS.MyClass = mq.TLO.Me.Class.ShortName():lower()
LNS.MyRace  = mq.TLO.Me.Race.Name()
LNS.guiLoot = require('modules.loot_hist')
if LNS.guiLoot ~= nil then
    LNS.UseActors = true
    LNS.guiLoot.GetSettings(settings.Settings.HideNames,
        settings.Settings.RecordData,
        true,
        true,
        'lootnscoot',
        false,
        false
    )
end

LNS.Mode                   = 'once'
LNS.debugPrint             = false
LNS.lootedCorpses          = {}
LNS.showNewItem            = false
LNS.lookupDate             = ''
LNS.DirectorScript         = 'none'
LNS.DirectorLNSPath        = nil
LNS.CurrentPage            = LNS.CurrentPage or 1
LNS.BuyItemsTable          = {}
LNS.ALLITEMS               = {}
LNS.GlobalItemsRules       = {}
LNS.NormalItemsRules       = {}
LNS.NormalItemsClasses     = {}
LNS.GlobalItemsClasses     = {}
LNS.NormalItemsMissing     = {}
LNS.GlobalItemsMissing     = {}
LNS.GlobalMissingNames     = {}
LNS.NormalMissingNames     = {}
LNS.HasMissingItems        = false
LNS.NewItems               = {}
LNS.PersonalItemsRules     = {}
LNS.PersonalItemsClasses   = {}
LNS.BoxKeys                = {}
LNS.NewItemDecisions       = nil
LNS.ItemNames              = {}
LNS.ItemLinks              = {}
LNS.ItemIcons              = {}
LNS.NewItemsCount          = 0
LNS.TempItemClasses        = "All"
LNS.itemSelectionPending   = false -- Flag to indicate an item selection is in progress
LNS.pendingItemData        = nil   -- Temporary storage for item data
LNS.doImportInventory      = false
LNS.TempModClass           = false
LNS.ShowUI                 = false
LNS.Terminate              = true
LNS.Boxes                  = {}
LNS.LootNow                = false
LNS.histCurrentPage        = 1
LNS.histItemsPerPage       = 25
LNS.histTotalPages         = 1
LNS.histTotalItems         = 0
LNS.HistoricalDates        = {}
LNS.HistoryDataDate        = {}
LNS.MasterLootList         = nil
LNS.SafeZones              = {}
LNS.PauseLooting           = false
LNS.Zone                   = mq.TLO.Zone.ShortName()
LNS.Instance               = mq.TLO.Me.Instance()
LNS.WildCards              = {}
LNS.IsLooting              = false
-- FORWARD DECLARATIONS
LNS.AllItemColumnListIndex = {
    [1]  = 'name',
    [2]  = 'sell_value',
    [3]  = 'tribute_value',
    [4]  = 'stackable',
    [5]  = 'stack_size',
    [6]  = 'nodrop',
    [7]  = 'notrade',
    [8]  = 'tradeskill',
    [9]  = 'quest',
    [10] = 'lore',
    [11] = 'collectible',
    [12] = 'augment',
    [13] = 'augtype',
    [14] = 'clickable',
    [15] = 'weight',
    [16] = 'ac',
    [17] = 'damage',
    [18] = 'strength',
    [19] = 'dexterity',
    [20] = 'agility',
    [21] = 'stamina',
    [22] = 'intelligence',
    [23] = 'wisdom',
    [24] = 'charisma',
    [25] = 'hp',
    [26] = 'regen_hp',
    [27] = 'mana',
    [28] = 'regen_mana',
    [29] = 'haste',
    [30] = 'classes',
    [31] = 'class_list',
    [32] = 'svfire',
    [33] = 'svcold',
    [34] = 'svdisease',
    [35] = 'svpoison',
    [36] = 'svcorruption',
    [37] = 'svmagic',
    [38] = 'spelldamage',
    [39] = 'spellshield',
    [40] = 'item_size',
    [41] = 'weightreduction',
    [42] = 'races',
    [43] = 'race_list',
    [44] = 'item_range',
    [45] = 'attack',
    [46] = 'strikethrough',
    [47] = 'heroicagi',
    [48] = 'heroiccha',
    [49] = 'heroicdex',
    [50] = 'heroicint',
    [51] = 'heroicsta',
    [52] = 'heroicstr',
    [53] = 'heroicsvcold',
    [54] = 'heroicsvcorruption',
    [55] = 'heroicsvdisease',
    [56] = 'heroicsvfire',
    [57] = 'heroicsvmagic',
    [58] = 'heroicsvpoison',
    [59] = 'heroicwis',
}

------------------------------------
--      UTILITY functions
------------------------------------

---comment
---@param item_name string
---@param corpseID string|number
---@param item_id string|number
---@param itemLink string|nil
---@param item_is_lore boolean
---@param item_is_nodrop boolean
---@param item_value string|number
function LNS.InsertMasterLootList(item_name, corpseID, item_id, itemLink, item_is_lore, item_is_nodrop, item_value)
    if not item_name then return end
    if itemLink == nil then
        itemLink = LNS.ItemLinks[item_id] or 'NULL'
    end

    local myCount = mq.TLO.FindItemCount(string.format("=%s", item_name))() + mq.TLO.FindItemBankCount(string.format("=%s", item_name))()
    if LNS.MasterLootList == nil then
        LNS.MasterLootList = {}
    end
    if LNS.MasterLootList[corpseID] == nil then
        LNS.MasterLootList[corpseID] = {}
    end
    if LNS.MasterLootList[corpseID].Items == nil then
        LNS.MasterLootList[corpseID].Items = {}
    end
    if LNS.MasterLootList[corpseID].Items[item_name] == nil then
        LNS.MasterLootList[corpseID].Items[item_name] = {
            Members = {},
        }
    end
    LNS.MasterLootList[corpseID].Items[item_name].Link = LNS.ItemLinks[item_id] or itemLink
    LNS.MasterLootList[corpseID].Items[item_name].Value = item_value
    LNS.MasterLootList[corpseID].Items[item_name].NoDrop = item_is_nodrop
    LNS.MasterLootList[corpseID].Items[item_name].IsLore = item_is_lore
    if LNS.MasterLootList[corpseID].Items[item_name].Members[settings.MyName] == nil then
        actors.Send({
            who = settings.MyName,
            action = 'check_item',
            item = item_name,
            link = LNS.ItemLinks[item_id],
            Count = myCount,
            Server = settings.EqServer,
            CorpseID = corpseID,
            Value = item_value,
            NoDrop = item_is_nodrop,
            IsLore = item_is_lore,
        })
    end

    LNS.MasterLootList[corpseID].Items[item_name].Members[settings.MyName] = myCount
end

---This will keep your table sorted by columns instead of rows.
---@param input_table table|nil the table to sort (optional) You can send a set of sorted keys if you have already custom sorted it.
---@param sorted_keys table|nil  the sorted keys table (optional) if you have already sorted the keys
---@param num_columns integer  the number of column groups to sort the keys into
---@return table
function LNS.SortTableColums(input_table, sorted_keys, num_columns)
    if input_table == nil and sorted_keys == nil then return {} end

    -- If sorted_keys is provided, use it, otherwise extract the keys from the input_table
    local keys = sorted_keys or {}
    if #keys == 0 then
        for k, _ in pairs(input_table) do
            table.insert(keys, k)
        end
        table.sort(keys, function(a, b)
            return a < b
        end)
    end

    local total_items = #keys
    local base_rows = math.floor(total_items / num_columns) -- number of rows per column
    local extra_rows = total_items % num_columns            -- incase we have a remainder

    local column_sorted = {}
    local column_entries = {}

    local start_index = 1
    for col = 1, num_columns do
        local rows_in_col = base_rows + (col <= extra_rows and 1 or 0)
        column_entries[col] = {}

        for row = 1, rows_in_col do
            if start_index <= total_items then
                table.insert(column_entries[col], keys[start_index])
                start_index = start_index + 1
            end
        end
    end

    -- Rearrange into the final sorted order, maintaining column-first layout
    local max_rows = base_rows + (extra_rows > 0 and 1 or 0)
    for row = 1, max_rows do
        for col = 1, num_columns do
            if column_entries[col][row] then
                table.insert(column_sorted, column_entries[col][row])
            end
        end
    end

    return column_sorted
end

---comment
---@param search any Search string we are looking for, can be a string or number
---@param key any Table field we are checking against, for Lookups this is only Name. for other tables this can be ItemId, Name, Class, Race
---@param value any Field value we are checking against
---@return boolean True if the search string is found in the key or value, false otherwise
function LNS.SearchLootTable(search, key, value)
    if key == nil or value == nil or search == nil then return false end
    key = tostring(key)
    search = tostring(search)
    search = search and search:gsub("[%^%$%(%)%%%.%[%]%*%+%-%?]", "%%%1") or ""
    if (search == nil or search == "") or key:lower():find(search:lower()) or value:lower():find(search:lower()) then
        return true
    else
        return false
    end
end

function LNS.SortSettings()
    settings.TempSettings.SortedSettingsKeys = {}
    settings.TempSettings.SortedToggleKeys   = {}
    for k in pairs(settings.Settings) do
        if not settings.SettingsNoDraw[k] then
            if type(settings.Settings[k]) == 'boolean' then
                table.insert(settings.TempSettings.SortedToggleKeys, k)
            else
                table.insert(settings.TempSettings.SortedSettingsKeys, k)
            end
        end
    end
    table.sort(settings.TempSettings.SortedToggleKeys, function(a, b) return a < b end)
    table.sort(settings.TempSettings.SortedSettingsKeys, function(a, b) return a < b end)
end

function LNS.SortTables()
    settings.TempSettings.SortedGlobalItemKeys     = {}
    settings.TempSettings.SortedBuyItemKeys        = {}
    settings.TempSettings.SortedNormalItemKeys     = {}
    settings.TempSettings.SortedMissingGlobalNames = {}
    settings.TempSettings.SortedMissingNormalNames = {}

    for k in pairs(LNS.GlobalItemsRules) do
        table.insert(settings.TempSettings.SortedGlobalItemKeys, k)
    end
    table.sort(settings.TempSettings.SortedGlobalItemKeys, function(a, b) return a < b end)

    for k in pairs(LNS.BuyItemsTable) do
        table.insert(settings.TempSettings.SortedBuyItemKeys, k)
    end
    table.sort(settings.TempSettings.SortedBuyItemKeys, function(a, b) return a < b end)

    for k in pairs(LNS.NormalItemsRules) do
        table.insert(settings.TempSettings.SortedNormalItemKeys, k)
    end
    table.sort(settings.TempSettings.SortedNormalItemKeys, function(a, b) return a < b end)

    local tmpTbl = {}
    for name, id in pairs(LNS.GlobalMissingNames) do
        table.insert(tmpTbl, { name = name, id = id, })
    end
    table.sort(tmpTbl, function(a, b)
        return a.name < b.name
    end)
    settings.TempSettings.SortedMissingGlobalNames = tmpTbl


    tmpTbl = {}
    for name, id in pairs(LNS.NormalMissingNames) do
        table.insert(tmpTbl, { name = name, id = id, })
    end
    table.sort(tmpTbl, function(a, b)
        return a.name < b.name
    end)
    settings.TempSettings.SortedMissingNormalNames = tmpTbl
end

function LNS.SortKeys(input_table)
    local keys = {}
    for k, _ in pairs(input_table) do
        table.insert(keys, k)
    end

    table.sort(keys) -- Sort the keys
    return keys
end

function LNS.FixBuyQty(input_table)
    local fixed_table = {}
    local needSave = false
    for k, v in pairs(input_table or {}) do
        if type(v) == 'number' then
            fixed_table[k] = v
        elseif type(v) == 'string' then
            local num = tonumber(v)
            if num then
                fixed_table[k] = num
            else
                fixed_table[k] = 0 -- Default to 0 if conversion fails
            end
            needSave = true
        else
            fixed_table[k] = 0 -- Default to 0 for unsupported types
            needSave = true
        end
    end
    return fixed_table, needSave
end

function LNS.writeSettings(caller)
    mq.cmdf("/squelch /mapfilter CastRadius %d", settings.Settings.CorpseRadius)

    LNS.guiLoot.GetSettings(settings.Settings.HideNames,
        settings.Settings.RecordData,
        true, true, 'lootnscoot',
        settings.Settings.ShowReport, settings.Settings.ReportSkippedItems)

    settings.Settings.BuyItemsTable = LNS.FixBuyQty(LNS.BuyItemsTable)
    mq.pickle(SettingsFile, settings.Settings)
    LNS.Boxes[settings.MyName] = settings.Settings

    Logger.Debug(LNS.guiLoot.console, { Lookup = "Loot::writeSettings()", CalledFrom = caller, })
end

---@param firstRun boolean|nil if passed true then we will load the DB's again
---@return boolean
function LNS.loadSettings(firstRun)
    if firstRun == nil then firstRun = false end
    if firstRun then
        LNS.NormalItemsRules     = {}
        LNS.GlobalItemsRules     = {}
        LNS.NormalItemsClasses   = {}
        LNS.GlobalItemsClasses   = {}
        LNS.ItemLinks            = {}
        LNS.BuyItemsTable        = {}
        LNS.PersonalItemsRules   = {}
        LNS.PersonalItemsClasses = {}
        LNS.ItemNames            = {}
        LNS.ALLITEMS             = {}
        LNS.SafeZones            = {}
        LNS.WildCards            = {}
    end
    local needDBUpdate = false
    local needSave     = false
    local tmpSettings  = {}

    if not Files.File.Exists(SettingsFile) then
        Logger.Warn(LNS.guiLoot.console, "Settings file not found, creating it now.")
        needSave = true
        mq.pickle(SettingsFile, settings.Settings)
    else
        tmpSettings = dofile(SettingsFile)
    end
    -- check if the DB structure needs updating

    if not Files.File.Exists(lootDBUpdateFile) then
        tmpSettings.Version = version
        needSave            = true
        mq.pickle(lootDBUpdateFile, { version = version, })
    else
        settings.TempSettings.VersionInfo = dofile(lootDBUpdateFile)
        if settings.TempSettings.VersionInfo.version < version then
            needDBUpdate        = true
            tmpSettings.Version = version
            needSave            = true
        end
    end

    -- process settings file

    for k, v in pairs(settings.Settings) do
        if type(v) ~= 'table' then
            if tmpSettings[k] == nil then
                tmpSettings[k] = settings.Settings[k]
                needSave       = true
                Logger.Info(LNS.guiLoot.console, "\agAdded\ax \ayNEW\ax \aySetting\ax: \at%s \aoDefault\ax: \at(\ay%s\ax)", k, v)
            end
        end
    end
    if tmpSettings.BuyItemsTable == nil then
        tmpSettings.BuyItemsTable = settings.Settings.BuyItemsTable
        needSave                  = true
        Logger.Info(LNS.guiLoot.console, "\agAdded\ax \ayNEW\ax \aySetting\ax: \atBuyItemsTable\ax")
    end
    -- -- check for deprecated settings and remove them
    for k, v in pairs(tmpSettings) do
        if type(v) ~= 'table' then
            if settings.Settings[k] == nil then
                tmpSettings[k] = nil
                needSave       = true
                Logger.Info(LNS.guiLoot.console, "\rRemoving\ax \ayOLD\ax \aySetting\ax: \at%s ", k)
            end
        end
    end
    Logger.loglevel           = tmpSettings.ShowInfoMessages and 'info' or 'warn'

    shouldLootActions.Destroy = tmpSettings.DoDestroy
    shouldLootActions.Tribute = tmpSettings.TributeKeep
    shouldLootActions.Quest   = tmpSettings.LootQuest
    LNS.BuyItemsTable         = tmpSettings.BuyItemsTable

    if firstRun then
        db.SetupItemsTable()

        db.LoadRuleDB()
        LNS.ItemIcons = db.LoadIcons()

        LNS.HistoricalDates = db.LoadHistoricalData()
    end
    settings.Settings = {}
    settings.Settings = tmpSettings
    LNS.Boxes[settings.MyName] = {}
    LNS.Boxes[settings.MyName] = settings.Settings
    if firstRun then table.insert(LNS.BoxKeys, settings.MyName) end
    LNS.guiLoot.openGUI = settings.Settings.ShowConsole
    local needFixBuyQty = false
    LNS.BuyItemsTable, needFixBuyQty = LNS.FixBuyQty(LNS.BuyItemsTable)
    if needFixBuyQty then
        needSave = true
        Logger.Warn(LNS.guiLoot.console, "BuyItemsTable had invalid values, fixed them and saved the settings.")
    end

    return needSave
end

function LNS.valueToCoins(sellVal)
    if sellVal == nil then return "0 pp 0 gp 0 sp 0 cp" end
    local platVal   = math.floor(sellVal / 1000)
    local goldVal   = math.floor((sellVal % 1000) / 100)
    local silverVal = math.floor((sellVal % 100) / 10)
    local copperVal = sellVal % 10
    return string.format("%s pp %s gp %s sp %s cp", platVal, goldVal, silverVal, copperVal)
end

function LNS.checkSpells(item_name)
    if string.find(item_name, "Spell: ") or string.find(item_name, "Song: ") then
        Logger.Debug(LNS.guiLoot.console, "Loot::checkSpells() \ay%s\ax \agFound\ax a spell", item_name)
        return true
    end
    Logger.Debug(LNS.guiLoot.console, "Loot::checkSpells() \ay%s\ax is \arnot\ax a spell", item_name)
    return false
end

function LNS.checkCursor()
    local currentItem = nil
    while mq.TLO.Cursor() do
        -- can't do anything if there's nowhere to put the item, either due to no free inventory space
        -- or no slot of appropriate size
        if mq.TLO.Me.FreeInventory() == 0 or mq.TLO.Cursor() == currentItem then
            if settings.Settings.SpamLootInfo then Logger.Warn(LNS.guiLoot.console, 'Inventory full, item stuck on cursor') end
            mq.cmdf('/autoinv')
            return
        end
        currentItem = mq.TLO.Cursor()
        mq.cmdf('/autoinv')
        mq.delay(3000, function() return not mq.TLO.Cursor() end)
    end
end

function LNS.navToID(spawnID)
    if (mq.TLO.Spawn(spawnID).Distance3D() or 0) < 10 then return end
    if mq.TLO.Window('LootWnd').Open() then
        mq.delay(25, function() return not mq.TLO.Window('LootWnd').Open() end)
        if mq.TLO.Window('LootWnd').Open() then return end
    end
    mq.cmdf('/nav id %d dist=10 log=off', spawnID)
    mq.delay(50, function() return (mq.TLO.Spawn(spawnID).Distance3D() or 0) < 10 end)
    if mq.TLO.Navigation.Active() then
        local startTime = os.time()
        while mq.TLO.Navigation.Active() do
            mq.delay(50)
            if os.difftime(os.time(), startTime) > (settings.Settings.NavTimeout or 5) then
                break
            end
        end
    end
    mq.delay(100, function() return not mq.TLO.Me.Moving() end)
end

function LNS.report(message, ...)
    if settings.Settings.ReportLoot then
        LNS.doReport(message, ...)
    end
end

function LNS.doReport(message, ...)
    local prefixWithChannel = not eqChatChannels[settings.Settings.LootChannel] and reportPrefix:format(settings.Settings.LootChannel, mq.TLO.Time()) or
        reportPrefixEQChat:format(settings.Settings.LootChannel)
    mq.cmdf(prefixWithChannel .. message, ...)
    if LNS.guiLoot.console ~= nil then
        LNS.guiLoot.console:AppendText(string.format(message, ...))
    end
end

function LNS.AreBagsOpen()
    local total = {
        bags = 0,
        open = 0,
    }
    for i = 23, 32 do
        local slot = mq.TLO.Me.Inventory(i)
        if slot and slot.Container() and slot.Container() > 0 then
            total.bags = total.bags + 1
            if slot.Open() then
                total.open = total.open + 1
            end
        end
    end
    if total.bags == total.open then
        return true
    else
        return false
    end
end

function LNS.eventNovalue(line, item)
    itemNoValue = item
end

function LNS.setupEvents()
    mq.event("CantLoot", "#*#may not loot this corpse#*#", LNS.eventCantLoot)
    mq.event("NoSlot", "#*#There are no open slots for the held item in your inventory#*#", LNS.eventNoSlot)
    mq.event("Sell", "#*#You receive#*# for the #1#(s)#*#", LNS.eventSell)
    -- mq.event("ForageExtras", "Your forage mastery has enabled you to find something else!", LNS.eventForage)
    mq.event("Forage", "You have scrounged up #*#", LNS.eventForage)
    mq.event("Novalue", "#*#give you absolutely nothing for the #1#.#*#", LNS.eventNovalue)
    mq.event("Tribute", "#*#We graciously accept your #1# as tribute, thank you!#*#", LNS.eventTribute)
end

------------------------------------
--      Main command handler
------------------------------------


function LNS.commandHandler(...)
    local args = { ..., }
    local item = mq.TLO.Cursor -- Capture the cursor item early for reuse
    local needSave = false
    if args[1] == 'mailbox' then
        settings.TempSettings.ShowMailbox = not settings.TempSettings.ShowMailbox
        if not LNS.debugPrint then
            LNS.debugPrint = settings.TempSettings.ShowMailbox
        end
        return
    end
    if args[1] == 'set' then
        local setting    = args[2]:lower()
        local settingVal = args[3]
        if settings.SettingsEnum[setting] ~= nil then
            local settingName = settings.SettingsEnum[setting]
            if type(settings.Settings[settingName]) == 'table' then
                Logger.Error(LNS.guiLoot.console, "Setting \ay%s\ax is a table and cannot be set directly.", settingName)
                return
            end
            if type(settings.Settings[settingName]) == 'boolean' then
                settings.Settings[settingName] = settingVal == 'on'
                if settingName == 'MasterLooting' then
                    actors.Send({
                        who = settings.MyName,
                        action = 'master_looter',
                        Server = settings.EqServer,
                        select = settings.Settings.MasterLooting,
                    })
                    Logger.Info(LNS.guiLoot.console, "Setting \ay%s\ax to \ag%s\ax", settingName, settingVal)
                end
            elseif type(settings.Settings[settingName]) == 'number' then
                settings.Settings[settingName] = tonumber(settingVal)
            else
                settings.Settings[settingName] = settingVal
            end
            Logger.Info(LNS.guiLoot.console, "Setting \ay%s\ax to \ag%s\ax", settingName, settingVal)
            settings.TempSettings[settings.MyName] = nil
            settings.TempSettings.NeedSave = true
        else
            Logger.Warn(LNS.guiLoot.console, "Invalid setting name: %s", setting)
        end
        if needSave then LNS.writeSettings("CommandHandler:set") end
        actors.SendMySettings()
        return
    end
    if args[1] == 'corpsereset' then
        local numCorpses = LNS.lootedCorpses ~= nil and LNS.GetTableSize(LNS.lootedCorpses) or 0
        LNS.lootedCorpses = {}
        Logger.Info(LNS.guiLoot.console, "Corpses (\ay%s\ax) have been \agReset\ax", numCorpses)
        actors.Send({ Who = settings.MyName, CorpsesToIgnore = LNS.lootedCorpses, Server = settings.EqServer, LNSSettings = settings.Settings, }, 'loot_module')
        return
    end
    if args[1] == 'pause' then
        LNS.PauseLooting = true
        Logger.Info(LNS.guiLoot.console, "\ayLooting\ax is now \aoPaused\ax")
        return
    elseif args[1] == 'unpause' or args[1] == 'resume' then
        LNS.PauseLooting = false
        Logger.Info(LNS.guiLoot.console, "\ayLooting\ax is now \agUnPaused\ax")
    end
    local dbgTbl = {
        CommandHandler = "/lns command issued",
    }
    for i, v in ipairs(args) do
        dbgTbl['Argument ' .. i] = v
    end
    Logger.Debug(LNS.guiLoot.console, dbgTbl)

    if args[1] == 'find' and args[2] ~= nil then
        local data = {}
        local count = 0
        if tonumber(args[2]) then
            local itemID = tonumber(args[2])
            count, data = LNS.findItem(nil, itemID)
            if count > 0 then
                Logger.Info(LNS.guiLoot.console, "Found item in DB: \ay%s\ax Link: %s", data[itemID].item_name, data[itemID].item_link)
            else
                Logger.Warn(LNS.guiLoot.console, "Item \ar%s\ax not found in DB", args[2])
            end
        else
            count, data = LNS.findItem(args[2])
            if count > 0 then
                for k, row in pairs(data) do
                    Logger.Info(LNS.guiLoot.console, "Found %s item in DB: \ay%s\ax ID: \at%s Link: \al%s", count, row.item_name, row.item_id, row.item_link)
                end
            else
                Logger.Warn(LNS.guiLoot.console, "Item \ar%s\ax not found in DB", args[2])
            end
            -- LNS.findItem(args[2])
        end
    end
    if args[1] == 'lowest' then
        local normal_low = db.GetLowestID('Normal_Rules') or 0
        local global_low = db.GetLowestID('Global_Rules') or 0
        -- local personal_low = db.GetLowestID(string.format('%s_Rules', settings.MyName)) or 0
        Logger.Info(LNS.guiLoot.console, string.format("Lowest Normal Item ID: \ay%s\ax", normal_low or 'None'))
        Logger.Info(LNS.guiLoot.console, string.format("Lowest Global Item ID: \ay%s\ax", global_low or 'None'))
        -- Logger.Info(LNS.guiLoot.console, "Lowest Personal Item ID: \ay%s\ax", personal_low or 'None')

        return
    end
    if args[1] == 'personalitem' then
        if validActions[args[2]] then
            local rule = validActions[args[2]]
            if args[2] == 'quest' then
                if not item() then
                    if args[4] then
                        rule = 'Quest|' .. args[4]
                    end
                else
                    if args[3] then
                        rule = 'Quest|' .. args[3]
                    end
                end
            end

            if not item() and args[3] then
                local itemID = LNS.resolveItemIDbyName(args[3], false)
                if itemID then
                    LNS.addRule(itemID, 'PersonalItems', rule, 'All', 'NULL')
                    Logger.Info(LNS.guiLoot.console, "Setting \ay%s\ax to \ay%s\ax", args[3], rule)
                else
                    local newID = db.GetLowestID(string.format('%s_Rules', settings.MyName)) or -1
                    -- then add rule as a missing item for now.
                    LNS.addRule(newID, 'PersonalItems', rule, 'All', 'NULL')

                    Logger.Warn(LNS.guiLoot.console, "Item \ar%s\ax not found in DB. adding rule as a missing item.", args[3])
                end
            end
            if item() then
                local itemID = item.ID()
                LNS.addRule(itemID, 'PersonalItems', rule, 'All', item.ItemLink('CLICKABLE')())
                Logger.Info(LNS.guiLoot.console, "Setting \ay%s\ax to \ay%s\ax", item.Name(), rule)
            end
            return
        end
    end

    if args[1] == 'globalitem' then
        if validActions[args[2]] then
            local rule = validActions[args[2]]
            if args[2] == 'quest' then
                if not item() then
                    if args[4] then
                        rule = 'Quest|' .. args[4]
                    end
                else
                    if args[3] then
                        rule = 'Quest|' .. args[3]
                    end
                end
            end

            if not item() and args[3] then
                local itemID = LNS.resolveItemIDbyName(args[3], false)
                if itemID then
                    LNS.addRule(itemID, 'GlobalItems', rule, 'All', 'NULL')
                    Logger.Info(LNS.guiLoot.console, "Setting \ay%s\ax to \ay%s\ax", args[3], rule)
                else
                    local newID = db.GetLowestID('Global_Rules') or -1
                    -- then add rule as a missing item for now.
                    LNS.addRule(newID, 'GlobalItems', rule, 'All', 'NULL')

                    Logger.Warn(LNS.guiLoot.console, "Item \ar%s\ax not found in DB. adding rule as a missing item.", args[3])
                end
            end
            if item() then
                local itemID = item.ID()
                LNS.addRule(itemID, 'GlobalItems', rule, 'All', item.ItemLink('CLICKABLE')())
                Logger.Info(LNS.guiLoot.console, "Setting \ay%s\ax to \ay%s\ax", item.Name(), rule)
            end
            return
        end
    end

    if args[1] == 'normalitem' then
        if validActions[args[2]] then
            local rule = validActions[args[2]]
            if args[2] == 'quest' then
                if not item() then
                    if args[4] then
                        rule = 'Quest|' .. args[4]
                    end
                else
                    if args[3] then
                        rule = 'Quest|' .. args[3]
                    end
                end
            end

            if not item() and args[3] then
                local itemID = LNS.resolveItemIDbyName(args[3], false)
                if itemID then
                    LNS.addRule(itemID, 'NormalItems', rule, 'All', 'NULL')
                    Logger.Info(LNS.guiLoot.console, "Setting \ay%s\ax to \ay%s\ax", args[3], rule)
                else
                    -- get lowest item ID from the table multiply times -1 and subtract one to make a unique negative ID
                    -- local newID = db.GetLowestID('Normal_Rules') or -1
                    LNS.EnterNegIDRule(args[3], rule, 'All', 'NULL', 'Normal_Rules')
                    -- then add rule as a missing item for now.
                    -- LNS.addRule(newID, 'NormalItems', rule, 'All', 'NULL')

                    Logger.Warn(LNS.guiLoot.console, "Item \ar%s\ax not found in DB. adding rule as a missing item.", args[3])
                end
            end
            if item() then
                local itemID = item.ID()
                LNS.addRule(itemID, 'NormalItems', rule, 'All', item.ItemLink('CLICKABLE')())
                Logger.Info(LNS.guiLoot.console, "Setting \ay%s\ax to \ay%s\ax", item.Name(), rule)
            end
            return
        end
    end

    if #args == 1 then
        local command = args[1]
        if command == 'sellstuff' then
            LNS.processItems('Sell')
        elseif command == 'restock' then
            LNS.processItems('Buy')
        elseif command == 'importold' then
            settings.TempSettings.ShowImportDB = true
        elseif command == 'debug' then
            LNS.debugPrint = not LNS.debugPrint
            Logger.Warn(LNS.guiLoot.console, "\ayDebugging\ax is now %s", LNS.debugPrint and "\agon" or "\aroff")
        elseif command == 'reload' then
            local needSave = LNS.loadSettings()
            if needSave then
                LNS.writeSettings("CommandHandler:reload")
            end
            if LNS.guiLoot then
                LNS.guiLoot.GetSettings(
                    settings.Settings.HideNames,
                    settings.Settings.RecordData,
                    true,
                    settings.Settings.UseActors,
                    'lootnscoot', settings.Settings.ShowReport,
                    settings.Settings.ReportSkippedItems
                )
            end
            Logger.Info(LNS.guiLoot.console, "\ayReloaded Settings \axand \atLoot Files")
            -- elseif command == 'update' then
            -- -- UpdateDB() doesn't exist, is this not supported?
            --     if LNS.guiLoot then
            --         LNS.guiLoot.GetSettings(
            --             settings.Settings.HideNames,

            --             settings.Settings.RecordData,
            --             true,
            --             settings.Settings.UseActors,
            --             'lootnscoot', settings.Settings.ShowReport,
            --             settings.Settings.ReportSkippedItems
            --         )
            --     end
            --     LNS.UpdateDB()
            --     Logger.Info(LNS.guiLoot.console, "\ayUpdated the DB from loot.ini \axand \atreloaded settings")
        elseif command == 'importinv' then
            LNS.addMyInventoryToDB()
        elseif command == 'bankstuff' then
            LNS.processItems('Bank')
        elseif command == 'cleanup' then
            LNS.processItems('Destroy')
            settings.TempSettings.NeedsCleanup = true
        elseif command == 'help' then
            settings.TempSettings.ShowHelp = true
        elseif command == 'gui' or command == 'console' and LNS.guiLoot then
            LNS.guiLoot.openGUI = not LNS.guiLoot.openGUI
        elseif command == 'report' and LNS.guiLoot then
            LNS.guiLoot.ReportLoot()
        elseif command == 'hidenames' and LNS.guiLoot then
            LNS.guiLoot.hideNames = not LNS.guiLoot.hideNames
        elseif command == 'config' then
            local confReport = "\ayLoot N Scoot Settings\ax"
            for key, value in pairs(settings.Settings) do
                if type(value) ~= "function" and type(value) ~= "table" then
                    confReport = confReport .. string.format("\n\at%s\ax                                    = \ag%s\ax", key, tostring(value))
                end
            end
            Logger.Info(LNS.guiLoot.console, confReport)
        elseif command == 'tributestuff' then
            LNS.processItems('Tribute')
        elseif command == 'shownew' or command == 'newitems' then
            LNS.showNewItem = not LNS.showNewItem
        elseif command == 'loot' then
            LNS.lootMobs(settings.Settings.MaxCorpsesPerCycle)
        elseif command == 'show' then
            LNS.ShowUI = not LNS.ShowUI
        elseif command == 'tsbank' then
            LNS.markTradeSkillAsBank()
        elseif validActions[command] and item() then
            local itemID = item.ID()
            LNS.addRule(itemID, 'NormalItems', validActions[command], 'All', item.ItemLink('CLICKABLE')())
            Logger.Info(LNS.guiLoot.console, "Setting \ay%s\ax to \ay%s\ax", item.Name(), validActions[command])
        elseif string.find(command, "quest%|") and item() then
            local itemID = item.ID()
            local val    = string.gsub(command, "quest", "Quest")
            LNS.addRule(itemID, 'NormalItems', val, 'All', item.ItemLink('CLICKABLE')())
            Logger.Info(LNS.guiLoot.console, "Setting \ay%s\ax to \ay%s\ax", item.Name(), val)
        elseif command == 'quit' or command == 'exit' then
            printf('LootNScoot stopping due to quit command received.')
            mq.cmdf('/dg /pop 1 [%s] LootNScoot exiting due to quit command received.', mq.TLO.Me.CleanName())
            LNS.Terminate = true
        end
        if command == 'buy' and mq.TLO.Cursor() ~= nil then
            local itemName = mq.TLO.Cursor.Name()
            LNS.BuyItemsTable[itemName] = 1
            LNS.setBuyItem(itemName, 1)
            settings.TempSettings.NeedSave = true
            settings.TempSettings.NewBuyItem = ""
            settings.TempSettings.NewBuyQty = 1

            Logger.Info(LNS.guiLoot.console, "Setting \ay%s\ax to \agBuy Item\ax", itemName)
        end
    elseif #args == 2 then
        local action, item_name = args[1], args[2]
        if validActions[action] then
            local lootID = LNS.resolveItemIDbyName(item_name, false)
            Logger.Debug(LNS.guiLoot.console, "lootID: %s", lootID)
            if lootID then
                if LNS.ALLITEMS[lootID] then
                    LNS.addRule(lootID, 'NormalItems', validActions[action], 'All', LNS.ALLITEMS[lootID].Link)
                    Logger.Info(LNS.guiLoot.console, "Setting \ay%s (%s)\ax to \ay%s\ax", item_name, lootID, validActions[action])
                end
            end
        end
        if action == 'debug' then
            if args[2] == 'on' then
                LNS.debugPrint = true
                Logger.Info(LNS.guiLoot.console, "\ayDebugging\ax is now \agON\ax")
            elseif args[2] == 'off' then
                LNS.debugPrint = false
                Logger.Info(LNS.guiLoot.console, "\ayDebugging\ax is now \arOFF\ax")
            end
        end
        if action == 'buy' and mq.TLO.Cursor() ~= nil then
            if tonumber(args[2]) then
                local cursorItem = mq.TLO.Cursor.Name()
                LNS.BuyItemsTable[cursorItem] = args[2]

                LNS.setBuyItem(cursorItem, args[2])
                settings.TempSettings.NeedSave = true
                settings.TempSettings.NewBuyItem = ""
                settings.TempSettings.NewBuyQty = tonumber(args[2]) or 0

                Logger.Info(LNS.guiLoot.console, "Setting \ay%s\ax to \agBuy Item\ax", cursorItem)
            end
        elseif action == 'buy' and type(item_name) == 'string' then
            LNS.BuyItemsTable[item_name] = 1
            LNS.setBuyItem(item_name, 1)
            settings.TempSettings.NeedSave = true
            settings.TempSettings.NewBuyItem = ""
            settings.TempSettings.NewBuyQty = 1
            Logger.Info(LNS.guiLoot.console, "Setting \ay%s\ax to \agBuy Item\ax", item_name)
        end
    elseif args[1] == 'buy' then
        LNS.BuyItemsTable[args[2]] = args[3] or 0
        LNS.setBuyItem(args[2], tonumber(args[3]) or 0)
        settings.TempSettings.NeedSave = true
        Logger.Info(LNS.guiLoot.console, "Setting \ay%s\ax to \agBuy Item\ax", args[2])
    end
    if settings.TempSettings.NeedSave then
        LNS.writeSettings("CommandHandler:args")
        settings.TempSettings.NeedSave = false
        LNS.SortTables()
        LNS.SortSettings()
    end
end

function LNS.setupBinds()
    mq.bind('/lootutils', LNS.commandHandler)
    mq.bind('/lns', LNS.commandHandler)
end

function LNS.CheckBags()
    if settings.Settings.SaveBagSlots == nil then return false end
    -- Logger.Warn(loot.guiLoot.console,"\agBag CHECK\ax free: \at%s\ax, save: \ag%s\ax", mq.TLO.Me.FreeInventory(), loot.Settings.SaveBagSlots)
    areFull = mq.TLO.Me.FreeInventory() <= settings.Settings.SaveBagSlots
end

function LNS.eventCantLoot()
    cantLootID = mq.TLO.Target.ID()
end

function LNS.eventNoSlot()
    -- we don't have a slot big enough for the item on cursor. Dropping it to the ground.
    local cantLootItemName = mq.TLO.Cursor()
    mq.cmdf('/drop')
    mq.delay(1)
    LNS.report("\ay[WARN]\arI can't loot %s, dropping it on the ground!\ax", cantLootItemName)
end

function LNS.reportSkippedItems(skippedLoots, corpseName, corpseID)
    -- Ensure parameters are valid
    skippedLoots = skippedLoots or {}

    if next(skippedLoots) then
        Logger.Info(LNS.guiLoot.console, "\aySkipped Loot\ax items from corpse \at%s\ax (ID:\at %s\ax):\ay %s\ax",
            corpseName, tostring(corpseID), table.concat(skippedLoots, ", "))
        if settings.Settings.ReportSkippedItems then
            LNS.doReport("Skipped Loot: %s (%s): %s", corpseName, tostring(corpseID), table.concat(skippedLoots, ", "))
        end
    end
end

function LNS.checkLockedCorpse(corpseID)
    if cantLootList[corpseID] == nil then return false end
    local dTimer = settings.Settings.LootCheckDelay > 0 and settings.Settings.LootCheckDelay or 0.25
    if (os.difftime(os.clock(), cantLootList[corpseID]) or 1) > dTimer then
        cantLootList[corpseID] = nil
        return false
    end
    return true
end

function LNS.handleSelectedItem(itemID)
    -- Process the selected item (e.g., add to a rule, perform an action, etc.)
    local itemData = LNS.ALLITEMS[itemID]
    if not itemData then
        Logger.Error(LNS.guiLoot.console, "Invalid item selected: " .. tostring(itemID))
        return
    end

    Logger.Info(LNS.guiLoot.console, "Item selected: " .. itemData.Name .. " (ID: " .. itemID .. ")")
    -- You can now use itemID for further actions
end

function LNS.enterNewItemRuleInfo(data_table)
    if data_table == nil then
        if LNS.NewItemDecisions == nil then return end
        data_table = LNS.NewItemDecisions
    end

    if data_table.ID == nil then
        Logger.Error(LNS.guiLoot.console, "loot.enterNewItemRuleInfo \arInvalid item \atID \axfor new item rule.")
        return
    end
    local dbgTbl = {
        Check    = 'loot.enterNewItemRuleInfo() \axBegin \ayENTER ITEM',
        ItemName = data_table.ItemName,
        ItemID   = data_table.ID,
        Rule     = data_table.Rule,
        Classes  = data_table.Classes,
        Link     = data_table.Link,
        CorpseID = data_table.CorpseID,
    }
    Logger.Debug(LNS.guiLoot.console, dbgTbl)

    local itemID     = data_table.ID
    local item       = data_table.ItemName
    local rule       = data_table.Rule
    local classes    = data_table.Classes
    local link       = data_table.Link
    local corpse     = data_table.CorpseID
    local modMessage = {
        who        = settings.MyName,
        action     = 'modifyitem',
        section    = "NormalItems",
        item       = item,
        itemID     = itemID,
        rule       = rule,
        link       = link,
        classes    = classes,
        entered    = true,
        corpse     = corpse,
        hasChanged = false,
        Server     = settings.EqServer,
    }
    if (classes ~= (LNS.NormalItemsClasses[itemID] or 'new') or rule ~= (LNS.NormalItemsRules[itemID] or 'new')) and rule ~= 'Ignore' and rule ~= 'Ask' then
        modMessage.hasChanged = true
        dbgTbl = {
            Check  = 'loot.enterNewItemRuleInfo() \ax\agChanges Made to Item:',
            Item   = item,
            ID     = itemID,
            Rule   = rule,
            Class  = classes,
            Link   = link,
            Corpse = corpse,
        }
        Logger.Debug(LNS.guiLoot.console, dbgTbl)
    else
        dbgTbl = {
            Check   = "loot.enterNewItemRuleInfo() \axSending \agENTERED ITEM",
            MailBox = 'lootnscoot',
            Item    = item,
            ID      = itemID,
            Rule    = rule,
            Class   = classes,
            Link    = link,
            Corpse  = corpse,
        }
        Logger.Debug(LNS.guiLoot.console, dbgTbl)
    end

    if settings.Settings.AlwaysGlobal then
        modMessage.section = "GlobalItems"
    end
    actors.Send(modMessage)
end

function LNS.EnterNegIDRule(itemName, rule, classes, link, tableName)
    if db.EnterNegIDRule(itemName, rule, classes, link, tableName) then
        LNS.ItemNames[newID] = itemName

        if tableName == 'Global_Rules' then
            LNS.GlobalItemsRules[newID] = rule
            LNS.GlobalItemsClasses[newID] = classes
            LNS.GlobalItemsMissing[newID] = {
                item_id      = newID,
                item_name    = itemName,
                item_rule    = rule,
                item_classes = classes,
            }
            LNS.GlobalMissingNames[itemName] = newID
        elseif tableName == 'Normal_Rules' then
            LNS.NormalItemsRules[newID] = rule
            LNS.NormalItemsClasses[newID] = classes
            LNS.NormalItemsMissing[newID] = {
                item_id      = newID,
                item_name    = itemName,
                item_rule    = rule,
                item_classes = classes,
            }
            LNS.NormalMissingNames[itemName] = newID
        end
        LNS.enterNewItemRuleInfo({
            ID       = newID,
            ItemName = itemName,
            Rule     = rule,
            Classes  = classes,
            Link     = link,
            CorpseID = nil,
        })
        LNS.HasMissingItems = true
        LNS.SortTables()
        Logger.Info(LNS.guiLoot.console, "Added rule for missing item \ay%s\ax with temporary ID \at%s\ax", itemName, newID)
        return newID
    else
        Logger.Error(LNS.guiLoot.console, "Failed to add rule for missing item \ay%s\ax", itemName)
        return nil
    end
end

function LNS.AddSafeZone(zoneName)
    if not zoneName or zoneName == "" then return end
    if not db.AddSafeZone(zoneName) then return end
    LNS.SafeZones[zoneName] = true
    actors.Send({
        who = settings.MyName,
        action = 'addsafezone',
        Server = settings.EqServer,
        zone = zoneName,
    })
    if LNS.SafeZones[LNS.Zone] and not settings.TempSettings.SafeZoneWarned then
        Logger.Warn(LNS.guiLoot.console, "You are in a safe zone: \at%s\ax \ayLooting Disabled", LNS.Zone)
        settings.TempSettings.SafeZoneWarned = true
    end
end

function LNS.RemoveSafeZone(zoneName)
    if not zoneName or zoneName == "" then return end
    if not db.RemoveSafeZone(zoneName) then return end
    LNS.SafeZones[zoneName] = nil
    actors.Send({
        who = settings.MyName,
        Server = settings.EqServer,
        action = 'removesafezone',
        zone = zoneName,
    })
end

---comment
---@param itemName string the name of the item
---@param corpseName string the name of the corpse
---@param action string the action taken
---@param date string the date the item was looted (YYYY-MM-DD)
---@param timestamp string the time the item was looted (HH:MM:SS)
---@param link string the item link
---@param looter string the name of the looter
---@param zone string the zone the item was looted in (ShortName)
---@param items_table table items table sent to looted.
---@param cantWear boolean|nil if the item can be worn
---@param rule string|nil the rule applied to the item
function LNS.insertIntoHistory(itemName, corpseName, action, date, timestamp, link, looter, zone, items_table, cantWear, rule)
    if itemName == nil then return end
    local tooSoon = false

    local eval = action:find('Ignore') and 'Left' or action

    -- Skip if a duplicate "Ignore" or "Left" action exists within the last minute
    if action:find("Ignore") or action:find("Left") then
        tooSoon = db.CheckHistory(itemName, corpseName, action, date, timestamp)
    end

    if not tooSoon then
        db.InsertHistory(itemName, corpseName, action, date, timestamp, link, looter, zone)
    end

    local actLabel = action:find('Destroy') and 'Destroyed' or action
    if not action:find('Destroy') and not action:find('Ignore') and not action:find('Left') then
        actLabel = 'Looted'
    end
    if (action:find('Left') or action:find('Ignore')) then
        actLabel = 'Left'
    end
    if allItems == nil then
        allItems = {}
    end
    --======================

    local tmpTable = {
        Name = itemName,
        CorpseName = corpseName,
        Action = actLabel,
        Link = link,
        Eval = eval,
        Rule = rule or eval,
        cantWear = cantWear,
    }
    -- table.insert(allItems,
    --     {
    --         Name = itemName,
    --         CorpseName = corpseName,
    --         Action = actLabel,
    --         Link = link,
    --         Eval = eval,
    --         Rule = rule or eval,
    --         cantWear = cantWear,
    --     })
    return tmpTable
    --======================
end

--- check for field>=value or some other operation using < > = <= >=
--- split the field, operator, and values to create the query from.
---@param search string search string to parse
---@return string|nil field string the field to search in
---@return string|nil op string the operator to use for comparison
---@return string|nil value string the value to compare against
local function parseSearchString(search)
    -- check for values with Quotes
    local field, op, quoted_value = search:match("^([%w_]+)%s*([><=~]=?)%s*\"([^\"]+)\"$")
    if field and op and quoted_value then
        return field:lower(), op, quoted_value
    end
    local value
    -- no quoted values
    field, op, value = search:match("^([%w_]+)%s*([><=~]=?)%s*(.+)$")
    if field and op and value then
        return field:lower(), op, value
    end

    return nil, nil, nil
end

--- Retrieve item data from the DB
---@param itemName string|nil The name of the item to retrieve. [string]
---@param itemID integer|nil The ID of the item to retrieve. [integer] [optional]
---@param rules boolean|nil If true, only load items with rules (exact name matches) [boolean] [optional]
---@param db any DB Connection SQLite3 [optional]
---@return integer Quantity of items found
function LNS.GetItemFromDB(itemName, itemID, rules, exact)
    if not itemID and not itemName then return 0 end
    itemID = itemID or 0
    itemName = itemName or 'NULL'
    settings.TempSettings.SearchResults = nil

    local conditions = {}
    local orderBy = "ORDER BY name ASC"
    local query = ""

    if itemID > 0 then
        query = string.format("SELECT * FROM Items WHERE item_id = %d %s", itemID, orderBy)
    elseif itemName:match("^%b{}$") then
        local ConditionalClauses = itemName:sub(2, -2)

        -- Handles multiple conditions {hp>=1000, name~"words of" | name~"rune of" | name~"pg."} treates pipes as OR and comma's as AND for compiling the query
        for clause in ConditionalClauses:gmatch("[^,]+") do
            clause = clause:match("^%s*(.-)%s*$") -- trim spaces
            if clause:find("|") then
                local orGroup = {}
                for or_clause in clause:gmatch("[^|]+") do
                    local field, op, value = parseSearchString(or_clause:match("^%s*(.-)%s*$"))
                    if field and op and value then
                        if op == "~" then
                            value = value:gsub("'", "''")
                            table.insert(orGroup, string.format("%s LIKE '%%%s%%'", field, value))
                        elseif tonumber(value) then
                            table.insert(orGroup, string.format("%s %s %s", field, op, value))
                        elseif op == "=" then
                            table.insert(orGroup, string.format("%s = '%s'", field, value:gsub("'", "''")))
                        else
                            value = value:gsub("'", "''")
                            table.insert(orGroup, string.format("%s LIKE '%%%s%%'", field, value))
                        end
                    end
                end
                if #orGroup > 0 then
                    table.insert(conditions, "(" .. table.concat(orGroup, " OR ") .. ")")
                end
            else
                local field, op, value = parseSearchString(clause)
                if field and op and value then
                    if op == "~" then
                        value = value:gsub("'", "''")
                        table.insert(conditions, string.format("%s LIKE '%%%s%%'", field, value))
                    elseif tonumber(value) then
                        table.insert(conditions, string.format("%s %s %s", field, op, value))
                        orderBy = string.format("ORDER BY %s DESC, name ASC", field)
                    elseif op == "=" then
                        table.insert(conditions, string.format("%s = '%s'", field, value:gsub("'", "''")))
                    else
                        value = value:gsub("'", "''")
                        table.insert(conditions, string.format("%s LIKE '%%%s%%'", field, value))
                    end
                end
            end
        end

        if #conditions > 0 then
            query = string.format("SELECT * FROM Items WHERE %s %s", table.concat(conditions, " AND "), orderBy)
        else
            query = string.format("SELECT * FROM Items WHERE 1=0 %s", orderBy) -- no valid clauses
        end
    else
        -- Handle single condition or default to name search
        local field, op, value = parseSearchString(itemName)
        if field and op and value then
            if tonumber(value) then
                orderBy = string.format("ORDER BY %s DESC, name ASC", field)
                query = string.format("SELECT * FROM Items WHERE %s %s %s %s", field, op, value, orderBy)
            else
                value = value:gsub("'", "''")
                if op == "=" then
                    query = string.format("SELECT * FROM Items WHERE %s = '%s' %s", field, value, orderBy)
                else
                    query = string.format("SELECT * FROM Items WHERE %s LIKE '%%%s%%' %s", field, value, orderBy)
                end
            end
        else
            -- Default to name search
            query = string.format("SELECT * FROM Items WHERE name LIKE '%%%s%%' %s", itemName:gsub("'", "''"), orderBy)
        end
    end

    local rowsFetched = db.GetItemFromDB(itemName, itemID, query, itemID > 0 and true or false)
    Logger.Info(LNS.guiLoot.console, "loot.GetItemFromDB() \agFound \ay%d\ax items matching the query: \ay%s\ax", rowsFetched, query)
    return rowsFetched
end

function LNS.addMyInventoryToDB()
    local counter = 0
    local counterBank = 0
    Logger.Info(LNS.guiLoot.console, "\atImporting Inventory\ax into the DB")

    for i = 1, 32 do
        local invItem = mq.TLO.Me.Inventory(i)

        -- Items in Bags
        local containerSize = invItem.Container()
        if invItem() ~= nil then
            LNS.addToItemDB(invItem)
            counter = counter + 1
            mq.delay(10) -- Delay to prevent spamming the DB

            if containerSize then
                -- grab items inside the bags
                mq.delay(5) -- Delay to prevent spamming the DB
                for j = 1, containerSize do
                    local item = invItem.Item(j)
                    if item and item.ID() then
                        LNS.addToItemDB(item)
                        counter = counter + 1
                        mq.delay(10)
                    end
                end
            end
        end
    end

    for i = 1, 24 do
        local bankSlot = mq.TLO.Me.Bank(i)
        local bankBagSize = bankSlot.Container()
        if bankSlot() ~= nil then
            LNS.addToItemDB(bankSlot)
            counterBank = counterBank + 1
            if bankBagSize then
                mq.delay(5) -- Delay to prevent spamming the DB
                for j = 1, bankBagSize do
                    local item = bankSlot.Item(j)
                    if item and item.ID() then
                        LNS.addToItemDB(item)
                        counterBank = counterBank + 1
                        mq.delay(10)
                    end
                end
            end
        end
    end
    Logger.Info(LNS.guiLoot.console, "\at%s \axImported \ag%d\ax items from \aoInventory\ax, and \ag%d\ax items from the \ayBank\ax, into the DB", settings.MyName, counter,
        counterBank)
    LNS.report(string.format("%s Imported %d items from Inventory, and %d items from the Bank, into the DB", settings.MyName, counter, counterBank))
    actors.Send({
        who = settings.MyName,
        Server = settings.EqServer,
        action = 'ItemsDB_UPDATE',
    })
end

function LNS.addToItemDB(item)
    if item == nil then
        if mq.TLO.Cursor() ~= nil then
            item = mq.TLO.Cursor
        else
            Logger.Error(LNS.guiLoot.console, "Item is \arnil.")
            return
        end
    end
    local itemID          = item.ID()
    local itemName        = item.Name()
    local itemIcon        = item.Icon()
    local value           = item.Value() or 0
    LNS.ItemNames[itemID] = itemName
    LNS.ItemIcons[itemID] = itemIcon

    LNS.ALLITEMS[itemID]  = {
        Name               = item.Name(),
        NoDrop             = item.NoDrop(),
        NoTrade            = item.NoTrade(),
        Tradeskills        = item.Tradeskills(),
        Quest              = item.Quest(),
        Lore               = item.Lore(),
        Augment            = item.AugType() > 0,
        Stackable          = item.Stackable(),
        Value              = LNS.valueToCoins(value) or 0,
        Tribute            = item.Tribute() or 0,
        StackSize          = item.StackSize() or 0,
        Clicky             = item.Clicky() or nil,
        AugType            = item.AugType() or 0,
        STR                = item.STR() or 0,
        DEX                = item.DEX() or 0,
        AGI                = item.AGI() or 0,
        STA                = item.STA() or 0,
        INT                = item.INT() or 0,
        WIS                = item.WIS() or 0,
        CHA                = item.CHA() or 0,
        Mana               = item.Mana() or 0,
        HP                 = item.HP() or 0,
        AC                 = item.AC() or 0,
        HPRegen            = item.HPRegen() or 0,
        ManaRegen          = item.ManaRegen() or 0,
        Haste              = item.Haste() or 0,
        Link               = item.ItemLink('CLICKABLE')() or 'NULL',
        Weight             = (item.Weight() or 0) * 10,
        Classes            = item.Classes() or 0,
        ClassList          = LNS.retrieveClassList(item),
        svFire             = item.svFire() or 0,
        svCold             = item.svCold() or 0,
        svDisease          = item.svDisease() or 0,
        svPoison           = item.svPoison() or 0,
        svCorruption       = item.svCorruption() or 0,
        svMagic            = item.svMagic() or 0,
        SpellDamage        = item.SpellDamage() or 0,
        SpellShield        = item.SpellShield() or 0,
        Races              = item.Races() or 0,
        RaceList           = LNS.retrieveRaceList(item),
        Collectible        = item.Collectible(),
        Attack             = item.Attack() or 0,
        Damage             = item.Damage() or 0,
        WeightReduction    = item.WeightReduction() or 0,
        Size               = item.Size() or 0,
        Icon               = itemIcon,
        StrikeThrough      = item.StrikeThrough() or 0,
        HeroicAGI          = item.HeroicAGI() or 0,
        HeroicCHA          = item.HeroicCHA() or 0,
        HeroicDEX          = item.HeroicDEX() or 0,
        HeroicINT          = item.HeroicINT() or 0,
        HeroicSTA          = item.HeroicSTA() or 0,
        HeroicSTR          = item.HeroicSTR() or 0,
        HeroicSvCold       = item.HeroicSvCold() or 0,
        HeroicSvCorruption = item.HeroicSvCorruption() or 0,
        HeroicSvDisease    = item.HeroicSvDisease() or 0,
        HeroicSvFire       = item.HeroicSvFire() or 0,
        HeroicSvMagic      = item.HeroicSvMagic() or 0,
        HeroicSvPoison     = item.HeroicSvPoison() or 0,
        HeroicWIS          = item.HeroicWIS() or 0,
    }
    LNS.ItemLinks[itemID] = item.ItemLink('CLICKABLE')() or 'NULL'

    -- insert the item into the database
    db.AddItemToDB(itemID, itemName, value, itemIcon)
end

--- Finds matching items in the Items DB by name or ID.
--- @param itemName string|nil The item name to match
--- @param itemId number|nil The item ID to match
--- @param exact boolean|nil If true, performs exact name match
--- @param maxResults number|nil Limit number of results returned (default 20)
--- @return number counter The number of items found
--- @return table retTable A table of item data indexed by item_id
function LNS.findItem(itemName, itemId, exact, maxResults)
    -- Shift args if passed as (name, exact)
    if itemId ~= nil and type(itemId) == 'boolean' then
        exact = itemId
        itemId = nil
    end

    maxResults = maxResults or 20
    local query = "SELECT * FROM Items"
    local param = nil
    local cleanName = itemName and itemName:gsub("'", "''") or nil
    if exact and itemName then
        query = "SELECT * FROM Items WHERE name = ?"
        param = cleanName
    elseif itemId then
        query = "SELECT * FROM Items WHERE item_id = ?"
        param = itemId
    elseif itemName then
        query = "SELECT * FROM Items WHERE name LIKE ?"
        param = "%" .. cleanName .. "%"
    else
        return 0, {}
    end

    local counter, retTable = db.FindItemInDB(query, param, maxResults)

    if counter >= maxResults then
        Logger.Info(LNS.guiLoot.console, "\aoMore than\ax \ay%d\ax items found, showing only first\ax \at%d\ax.", counter, maxResults)
    end

    return counter, retTable
end

function LNS.UpdateRuleLink(itemID, link, which_table)
    -- grab the link from the db and if it doesn't match then update it
    if not link or link == 'NULL' or link == '' then
        Logger.Warn(LNS.guiLoot.console, "\arLink is \ax[\ayNULL\ax] for itemID: %d", itemID)
        return
    end
    local alreadyMatched = db.GetItemLink(itemID, link, which_table)

    if not alreadyMatched then
        db.UpdateRuleLink(itemID, link, which_table)
    else
        LNS.ItemLinks[itemID] = link
        LNS.ALLITEMS[itemID] = LNS.ALLITEMS[itemID] or {}
        LNS.ALLITEMS[itemID].Link = link
        Logger.Debug(LNS.guiLoot.console, "\aoLink for\ax\at %d\ax \agALREADY MATCHES %s", itemID, link)
    end
end

function LNS.NormalizePattern(pattern)
    local out = {}
    local i = 1
    local len = #pattern

    while i <= len do
        local c = pattern:sub(i, i)

        if c == '%' and i < len then
            -- Preserve Lua pattern escapes exactly
            table.insert(out, pattern:sub(i, i + 1))
            i = i + 2
        else
            -- Lowercase literal characters only
            table.insert(out, c:lower())
            i = i + 1
        end
    end

    return table.concat(out)
end

function LNS.CheckWildCards(itemName)
    local name = itemName:lower()

    for _, entry in ipairs(LNS.WildCards or {}) do
        local patternOrig = entry.wildcard
        local rule = entry.rule
        if patternOrig then
            local pattern = LNS.NormalizePattern(patternOrig)

            if name:match(pattern) then
                Logger.Debug(
                    LNS.guiLoot.console,
                    "Wildcard match found: \ay%s\ax matches pattern \at%s\ax",
                    itemName,
                    patternOrig
                )
                return rule or ''
            end
        end
    end

    return ''
end

------------------------------------
--         RULES FUNCTIONS
------------------------------------


---@param mq_item MQItem|nil
---@param itemID any
---@param tablename any|nil
---@param item_link string|nil
---@param skipWildcard bool|nil
---@return string rule
---@return string classes
---@return string link
---@return string which_table
function LNS.lookupLootRule(mq_item, itemID, tablename, item_link, skipWildcard)
    if mq_item and mq_item() then
        itemID = mq_item.ID()
        item_link = mq_item.ItemLink('CLICKABLE')() or 'NULL'
    end

    if itemID == nil or itemID == 0 then
        return 'NULL', 'All', 'NULL', 'None'
    end
    local which_table = 'Normal'

    -- check lua tables first
    -- local link = LNS.ALLITEMS[itemID] and LNS.ALLITEMS[itemID].Link or 'NULL'
    local link = LNS.ItemLinks[itemID] or 'NULL'

    if not LNS.ALLITEMS[itemID] then
        LNS.ALLITEMS[itemID] = {}
    end

    if item_link and item_link ~= link and LNS.ALLITEMS[itemID] then
        LNS.ALLITEMS[itemID].Link = item_link
    end

    LNS.ItemLinks[itemID] = item_link and (item_link ~= (LNS.ItemLinks[itemID] or '0') and item_link or LNS.ItemLinks[itemID]) or (LNS.ItemLinks[itemID] or 'NULL')

    if tablename == nil then
        if LNS.PersonalItemsRules[itemID] then
            if link ~= 'NULL' or (item_link and link ~= item_link) then
                LNS.UpdateRuleLink(itemID, LNS.ItemLinks[itemID], settings.PersonalTableName)
            end
            return LNS.PersonalItemsRules[itemID], LNS.PersonalItemsClasses[itemID], LNS.ItemLinks[itemID], 'Personal'
        end
        if LNS.GlobalItemsRules[itemID] then
            if link ~= 'NULL' or (item_link and link ~= item_link) then
                LNS.UpdateRuleLink(itemID, LNS.ItemLinks[itemID], 'Global_Rules')
            end
            return LNS.GlobalItemsRules[itemID], LNS.GlobalItemsClasses[itemID], LNS.ItemLinks[itemID], 'Global'
        end
        if LNS.NormalItemsRules[itemID] then
            if link ~= 'NULL' or (item_link and link ~= item_link) then
                LNS.UpdateRuleLink(itemID, LNS.ItemLinks[itemID], 'Normal_Rules')
            end
            return LNS.NormalItemsRules[itemID], LNS.NormalItemsClasses[itemID], LNS.ItemLinks[itemID], 'Normal'
        end
        -- Never called with a tablename
        -- elseif tablename == 'Global_Rules' then
        --     if LNS.GlobalItemsRules[itemID] then
        --         if link ~= 'NULL' or (item_link and link ~= item_link) then
        --             LNS.UpdateRuleLink(itemID, LNS.ItemLinks[itemID], 'Global_Rules')
        --         end
        --         return LNS.GlobalItemsRules[itemID], LNS.GlobalItemsClasses[itemID], LNS.ItemLinks[itemID], 'Global'
        --     end
        -- elseif tablename == 'Normal_Rules' then
        --     if LNS.NormalItemsRules[itemID] then
        --         if link ~= 'NULL' or (item_link and link ~= item_link) then
        --             LNS.UpdateRuleLink(itemID, LNS.ItemLinks[itemID], 'Normal_Rules')
        --         end
        --         return LNS.NormalItemsRules[itemID], LNS.NormalItemsClasses[itemID], LNS.ItemLinks[itemID], 'Normal'
        --     end
        -- elseif tablename == settings.PersonalTableName then
        --     if LNS.PersonalItemsRules[itemID] then
        --         if link ~= 'NULL' or (item_link and link ~= item_link) then
        --             LNS.UpdateRuleLink(itemID, LNS.ItemLinks[itemID], settings.PersonalTableName)
        --         end
        --         return LNS.PersonalItemsRules[itemID], LNS.PersonalItemsClasses[itemID], LNS.ItemLinks[itemID], 'Personal'
        --     end
    end

    local rule       = 'NULL'
    local classes    = (mq_item and mq_item()) and LNS.retrieveClassList(mq_item) or 'NULL'
    local lookupLink = 'NULL'

    if tablename == nil then
        -- check global rules
        local found = false
        found, rule, classes, lookupLink = db.CheckRulesDB(itemID, db.PreparedStatements.CHECK_DB_PERSONAL)
        which_table = 'Personal'
        tablename = settings.PersonalTableName
        if not found then
            found, rule, classes, lookupLink = db.CheckRulesDB(itemID, db.PreparedStatements.CHECK_DB_GLOBAL)
            which_table = 'Global'
            tablename = 'Global_Rules'
        end
        if not found then
            found, rule, classes, lookupLink = db.CheckRulesDB(itemID, db.PreparedStatements.CHECK_DB_NORMAL)
            which_table = 'Normal'
            tablename = 'Normal_Rules'
        end

        if not found and not skipWildcard then
            if mq_item and mq_item() then
                local wildCardRule = LNS.CheckWildCards(mq_item.Name()) or ''
                if wildCardRule ~= '' then
                    classes            = classes ~= 'NULL' and classes or 'All'
                    lookupLink         = item_link
                    found              = true
                    which_table        = 'Normal'

                    local isEquippable = (mq_item.WornSlots() or 0) > 0
                    local isNoDrop     = mq_item.NoDrop() or mq_item.NoTrade()
                    local addToDB      = true

                    -- NODROP
                    if isNoDrop then
                        addToDB = (settings.Settings.LootNoDropNew and settings.Settings.LootNoDrop) or false
                        -- if not (isEquippable and addToDB) then
                        --     wildCardRule = "Ask"
                        -- end
                    end
                    LNS.addNewItem(mq_item, wildCardRule, item_link, mq.TLO.Corpse.ID() or 0, addToDB)
                    rule = wildCardRule
                end
            end
        end

        if not found then
            rule = 'NULL'
            classes = 'None'
            lookupLink = 'NULL'
        end
        -- never called with a table name
        -- else
        --     _, rule, classes, lookupLink = checkDB(itemID, tablename)
    end

    -- if SQL has the item add the rules to the lua table for next time

    if rule ~= 'NULL' then
        local localTblName                     = tablename == 'Global_Rules' and 'GlobalItems' or 'NormalItems'
        localTblName                           = tablename == settings.PersonalTableName and 'PersonalItems' or localTblName

        LNS[localTblName .. 'Rules'][itemID]   = rule
        LNS[localTblName .. 'Classes'][itemID] = classes
        LNS.ItemLinks[itemID]                  = lookupLink
        LNS.ItemNames[itemID]                  = LNS.ALLITEMS[itemID].Name or (mq_item and mq_item.Name() or "Unknown")
    end
    return rule, classes, lookupLink, which_table
end

function LNS.Get_worn_slots(item)
    local SlotsString = ""
    local tmp = {}
    for i = 1, item.WornSlots() do
        local slotID = item.WornSlot(i)() or '-1'
        tmp[equipSlots[tonumber(slotID)]] = true
    end
    for slotID, _ in pairs(tmp) do
        SlotsString = SlotsString .. slotID .. " "
    end
    return SlotsString
end

function LNS.Get_item_data(item)
    if not item() then
        return nil
    end
    local tmpItemData = {
        Name = item.Name(),
        Type = item.Type(),
        ID = item.ID(),
        ReqLvl = item.RequiredLevel() or 0,
        RecLvl = item.RecommendedLevel() or 0,
        AC = item.AC() or 0,
        BaseDMG = item.Damage() or 0,
        Delay = item.ItemDelay() or 0,
        Value = item.Value() or 0,
        Weight = item.Weight() or 0,
        Stack = item.Stack() or 0,
        MaxStack = item.StackSize() or 0,
        Clicky = item.Clicky(),
        Charges = (item.Charges() or 0) ~= -1 and (item.Charges() or 0) or 'Infinite',
        ClassList = LNS.retrieveClassList(item),
        RaceList = LNS.retrieveRaceList(item),
        Icon = item.Icon() or 0,
        WornSlots = LNS.Get_worn_slots(item),
        TributeValue = item.Tribute() or 0,
        EffectType = item.EffectType() or 'None',
        --base stats
        HP = item.HP() or 0,
        Mana = item.Mana() or 0,
        Endurance = item.Endurance() or 0,

        -- stats
        STR = item.STR() or 0,
        AGI = item.AGI() or 0,
        STA = item.STA() or 0,
        INT = item.INT() or 0,
        WIS = item.WIS() or 0,
        DEX = item.DEX() or 0,
        CHA = item.CHA() or 0,
        -- resists
        MR = item.svMagic() or 0,
        FR = item.svFire() or 0,
        DR = item.svDisease() or 0,
        PR = item.svPoison() or 0,
        CR = item.svCold() or 0,
        svCor = item.svCorruption() or 0,

        --heroic stats
        hStr = item.HeroicSTR() or 0,
        hAgi = item.HeroicAGI() or 0,
        hSta = item.HeroicSTA() or 0,
        hInt = item.HeroicINT() or 0,
        hDex = item.HeroicDEX() or 0,
        hCha = item.HeroicCHA() or 0,
        hWis = item.HeroicWIS() or 0,

        --heroic resists
        hMr = item.HeroicSvMagic() or 0,
        hFr = item.HeroicSvFire() or 0,
        hDr = item.HeroicSvDisease() or 0,
        hPr = item.HeroicSvPoison() or 0,
        hCr = item.HeroicSvCold() or 0,
        hCor = item.HeroicSvCorruption() or 0,

        --augments
        AugSlots = item.Augs() or 0,
        AugSlot1 = item.AugSlot(1).Name() or 'none',
        AugSlot2 = item.AugSlot(2).Name() or 'none',
        AugSlot3 = item.AugSlot(3).Name() or 'none',
        AugSlot4 = item.AugSlot(4).Name() or 'none',
        AugSlot5 = item.AugSlot(5).Name() or 'none',
        AugSlot6 = item.AugSlot(6).Name() or 'none',

        AugType1 = item.AugSlot1() or 'none',
        AugType2 = item.AugSlot2() or 'none',
        AugType3 = item.AugSlot3() or 'none',
        AugType4 = item.AugSlot4() or 'none',
        AugType5 = item.AugSlot5() or 'none',
        AugType6 = item.AugSlot6() or 'none',

        -- bonus efx
        Spelleffect = item.Spell() or "",
        -- spell userdata should never be nil and yet here we are...
        Worn = item.Worn and item.Worn.Spell and item.Worn.Spell.Name() or 'none',
        Focus1 = item.Focus and item.Focus.Spell and item.Focus.Spell.Name() or 'none',
        Focus2 = item.Focus2 and item.Focus2.Spell and item.Focus2.Spell.Name() or 'none',
        -- ElementalDamage = item.ElementalDamage() or 0,
        Haste = item.Haste() or 0,
        DmgShield = item.DamShield() or 0,
        DmgShieldMit = item.DamageShieldMitigation() or 0,
        Avoidance = item.Avoidance() or 0,
        DotShield = item.DoTShielding() or 0,
        InstrumentMod = item.InstrumentMod() or 0,
        HPRegen = item.HPRegen() or 0,
        ManaRegen = item.ManaRegen() or 0,
        EnduranceRegen = item.EnduranceRegen() or 0,
        Accuracy = item.Accuracy() or 0,
        -- https://github.com/macroquest/macroquest/issues/953
        BonusDmgType = 'None', -- item.DMGBonusType() or 'None',
        SpellShield = item.SpellShield() or 0,
        Clairvoyance = item.Clairvoyance() or 0,
        HealAmount = item.HealAmount() or 0,
        SpellDamage = item.SpellDamage() or 0,
        StunResist = item.StunResist() or 0,
        CanUse = item.CanUse() or false,

        --restrictions
        isNoDrop = item.NoDrop() or false,
        isNoRent = item.NoRent() or false,
        isNoTrade = item.NoTrade() or false,
        isAttuneable = item.Attuneable() or false,
        isLore = item.Lore() or false,
        isEvolving = (item.Evolving.ExpPct() > 0 and item.Evolving.ExpOn()) or false,
        isMagic = item.Magic() or false,

        -- evolution
        EvolvingLevel = item.Evolving.Level() or 0,
        EvolvingExpPct = item.Evolving.ExpPct() or 0,
        EvolvingMaxLevel = item.Evolving.MaxLevel() or 0,

        --descriptions
        SpellDesc = item.Spell.Description() or "",
        WornDesc = item.Worn and item.Worn.Spell and item.Worn.Spell.Description() or '',
        Focus1Desc = item.Focus and item.Focus.Spell and item.Focus.Spell.Description() or '',
        Focus2Desc = item.Focus2 and item.Focus2.Spell and item.Focus2.Spell.Description() or '',
        ClickyDesc = item.Clicky and item.Clicky.Spell and item.Clicky.Spell.Description() or '',

        -- links
        SpellID = item.Spell.ID() or 0,
        WornID = item.Worn and item.Worn.Spell and item.Worn.Spell.ID() or 0,
        Focus1ID = item.Focus and item.Focus.Spell and item.Focus.Spell.ID() or 0,
        Focus2ID = item.Focus2 and item.Focus2.Spell and item.Focus2.Spell.ID() or 0,
        ClickyID = item.Clicky and item.Clicky.Spell and item.Clicky.Spell.ID() or 0,

        CombatEffects = item.CombatEffects() or 0,
        -- slots
        NumSlots = item.Container() or 0,
        Size = item.Size() or 0,
        SizeCapacity = item.SizeCapacity() or 0,

    }

    return tmpItemData
end

---comment
---@param corpseItem MQItem
---@param itemRule string|nil
---@param itemLink string|nil
---@param corpseID number
---@param addDB boolean
function LNS.addNewItem(corpseItem, itemRule, itemLink, corpseID, addDB)
    if corpseItem == nil or itemRule == nil then
        Logger.Warn(LNS.guiLoot.console, "\aoInvalid parameters for addNewItem:\ax corpseItem=\at%s\ax, itemRule=\ag%s",
            tostring(corpseItem), tostring(itemRule))
        return
    end
    if settings.TempSettings.NewItemIDs == nil then
        settings.TempSettings.NewItemIDs = {}
    end
    -- Retrieve the itemID from corpseItem
    local itemID = corpseItem.ID()
    local itemName = corpseItem.Name()
    if not itemID then
        Logger.Warn(LNS.guiLoot.console, "\arFailed to retrieve \axitemID\ar for corpseItem:\ax %s", itemName)
        return
    end
    LNS.ItemNames[itemID] = itemName
    if LNS.NewItems[itemID] ~= nil then return end
    local isNoDrop       = corpseItem.NoDrop() or corpseItem.NoTrade()
    LNS.TempItemClasses  = LNS.retrieveClassList(corpseItem)
    LNS.TempItemRaces    = LNS.retrieveRaceList(corpseItem)
    -- Add the new item to the loot.NewItems table
    LNS.NewItems[itemID] = {
        Name       = itemName,
        ItemID     = itemID, -- Include itemID for display and handling
        Link       = itemLink,
        Rule       = itemRule,
        NoDrop     = isNoDrop,
        Icon       = corpseItem.Icon(),
        Lore       = corpseItem.Lore(),
        Tradeskill = corpseItem.Tradeskills(),
        Aug        = corpseItem.AugType() > 0,
        Stackable  = corpseItem.Stackable(),
        MaxStacks  = corpseItem.StackSize() or 0,
        SellPrice  = LNS.valueToCoins(corpseItem.Value()),
        Tribute    = corpseItem.Tribute() or 0,
        Classes    = LNS.TempItemClasses,
        Races      = LNS.TempItemRaces,
        CorpseID   = corpseID,
    }
    table.insert(settings.TempSettings.NewItemIDs, itemID)

    -- Increment the count of new items
    -- LNS.NewItemsCount = LNS.NewItemsCount + 1
    LNS.NewItemsCount = #settings.TempSettings.NewItemIDs or 0

    if settings.Settings.AutoShowNewItem then
        LNS.showNewItem = true
    end

    if settings.TempSettings.NewItemData[itemID] == nil then
        settings.TempSettings.NewItemData[itemID] = {}
        settings.TempSettings.NewItemData[itemID] = LNS.Get_item_data(corpseItem)
    end

    -- Notify the loot actor of the new item
    Logger.Info(LNS.guiLoot.console, "\agNew Loot\ay Item Detected! \ax[\at %s\ax ]\ao Sending actors", itemName)
    local newMessage = {
        who        = settings.MyName,
        action     = 'new',
        item       = itemName,
        itemID     = itemID,
        Server     = settings.EqServer,
        rule       = itemRule,
        classes    = LNS.retrieveClassList(corpseItem),
        races      = LNS.retrieveRaceList(corpseItem),
        link       = itemLink,
        lore       = corpseItem.Lore(),
        icon       = corpseItem.Icon(),
        aug        = corpseItem.AugType() > 0 and true or false,
        noDrop     = isNoDrop,
        tradeskill = corpseItem.Tradeskills(),
        stackable  = corpseItem.Stackable(),
        maxStacks  = corpseItem.StackSize() or 0,
        sellPrice  = LNS.valueToCoins(corpseItem.Value()),
        tribute    = corpseItem.Tribute() or 0,
        corpse     = corpseID,
        details    = LNS.Get_item_data(corpseItem),
    }

    Logger.Info(LNS.guiLoot.console, "\agAdding 1 \ayNEW\ax item: \at%s \ay(\axID: \at%s\at) \axwith rule: \ag%s", itemName, itemID, itemRule)
    -- LNS.actorAddRule(itemID, itemName, 'Normal', itemRule, LNS.TempItemClasses, itemLink)
    if addDB then
        LNS.addRule(itemID, 'NormalItems', itemRule, LNS.TempItemClasses, itemLink, true)
    end
    local sections = { NormalItems = 1, }
    if settings.Settings.AlwaysGlobal then
        sections['GlobalItems'] = 1
    end
    newMessage.sections = sections
    actors.Send(newMessage)
end

---comment: Takes in an item to modify the rules for, You can add, delete, or modify the rules for an item.
---Upon completeion it will notify the loot actor to update the loot settings, for any other character that is using the loot actor.
---@param itemID integer The ID for the item we are modifying
---@param action string The action to perform (add, delete, modify)
---@param tableName string The table to modify
---@param classes string The classes to apply the rule to
---@param link string|nil The item link if available for the item
---@param skipMsg bool|nil Whether to send addrule/deleterule actor message on success
function LNS.modifyItemRule(itemID, action, tableName, classes, link, skipMsg)
    if not itemID or not tableName or not action then
        Logger.Warn(LNS.guiLoot.console, "Invalid parameters for modifyItemRule. itemID: %s, tableName: %s, action: %s",
            tostring(itemID), tostring(tableName), tostring(action))
        return
    end

    local section = tableName == "Normal_Rules" and "NormalItems" or "GlobalItems"
    section = tableName == settings.PersonalTableName and 'PersonalItems' or section
    -- Validate RulesDB
    if not db.RulesDB or type(db.RulesDB) ~= "string" then
        Logger.Warn(LNS.guiLoot.console, "Invalid RulesDB path: %s", tostring(db.RulesDB))
        return
    end
    LNS.GetItemFromDB(nil, itemID)
    -- Retrieve the item name from loot.ALLITEMS
    local itemName = LNS.ItemNames[itemID] ~= nil and LNS.ItemNames[itemID] or nil

    if not itemName then
        Logger.Warn(LNS.guiLoot.console, "Item ID \at%s\ax \arNOT\ax found in \ayloot.ALLITEMS", tostring(itemID))
        return
    end

    if LNS.ALLITEMS[itemID] == nil then
        LNS.ALLITEMS[itemID] = {}
        LNS.ALLITEMS[itemID].Name = itemName
    end
    -- Set default values
    if link == nil then
        link = LNS.ItemLinks[itemID] or 'NULL'
    end
    classes       = classes or 'All'

    local success = false
    if action == 'delete' then
        success = db.DeleteItemRule(action, tableName, itemName, itemID)
        if settings.Settings.AlwaysGlobal and section == 'NormalItems' then
            success = db.DeleteItemRule(action, 'Global_Rules', itemName, itemID)
        end
    else
        success = db.UpsertItemRule(action, tableName, itemName, itemID, classes, link)
        if settings.Settings.AlwaysGlobal and section == 'NormalItems' then
            success = db.UpsertItemRule(action, 'Global_Rules', itemName, itemID, classes, link)
        end
    end

    if success and not skipMsg then
        local sections = { section = 1, }
        if settings.Settings.AlwaysGlobal and section == 'NormalItems' then
            sections['GlobalItems'] = 1
        end
        -- Notify other actors about the rule change
        actors.Send({
            who      = settings.MyName,
            Server   = settings.EqServer,
            action   = action ~= 'delete' and 'addrule' or 'deleteitem',
            item     = itemName,
            itemID   = itemID,
            rule     = action,
            section  = section,
            sections = sections,
            link     = link,
            classes  = classes,
        })
    end
end

---comment
---@param itemID integer
---@param section string
---@param rule string
---@param classes string
---@param link string
---@return boolean success
function LNS.addRule(itemID, section, rule, classes, link, skipMsg)
    if not itemID or not section or not rule then
        Logger.Warn(LNS.guiLoot.console, "Invalid parameters for addRule. itemID: %s, section: %s, rule: %s",
            tostring(itemID), tostring(section), tostring(rule))
        return false
    end

    -- Retrieve the item name from loot.ALLITEMS
    local itemName = LNS.ItemNames[itemID] and LNS.ItemNames[itemID] or nil
    if not itemName then
        Logger.Warn(LNS.guiLoot.console, "Item ID \at%s\ax \arNOT\ax found in \ayloot.ALLITEMS", tostring(itemID))
        return false
    end

    -- Set default values for optional parameters
    classes                           = classes or 'All'
    link                              = link or 'NULL'

    -- Log the action
    -- Logger.Info(loot.guiLoot.console,"\agAdding\ax rule for item \at%s\ax\ao (\ayID\ax:\ag %s\ax\ao)\ax in [section] \at%s \axwith [rule] \at%s\ax and [classes] \at%s",
    -- itemName, itemID, section, rule, classes)

    -- -- Update the in-memory data structure
    -- LNS.ItemNames[itemID]             = itemName

    LNS[section .. "Rules"][itemID]   = rule
    LNS[section .. "Classes"][itemID] = classes
    LNS.ItemLinks[itemID]             = link

    if settings.Settings.AlwaysGlobal and section == 'NormalItems' then
        LNS["GlobalItemsRules"][itemID]   = rule
        LNS["GlobalItemsClasses"][itemID] = classes
    end

    local tblName = section == 'GlobalItems' and 'Global_Rules' or 'Normal_Rules'
    if section == 'PersonalItems' then
        tblName = settings.PersonalTableName
    end
    LNS.modifyItemRule(itemID, rule, tblName, classes, link, skipMsg)
    -- if settings.Settings.AlwaysGlobal and section == 'NormalItems' then
    --     LNS.modifyItemRule(itemID, rule, 'Global_Rules', classes, link, true)
    -- end

    -- Refresh the loot settings to apply the changes
    return true
end

function LNS.processPendingItem()
    if not LNS.pendingItemData and not LNS.pendingItemData.selectedItem then
        Logger.Warn(LNS.guiLoot.console, "No item selected for processing.")
        return
    end

    -- Extract the selected item and callback
    local selectedItem = LNS.pendingItemData.selectedItem
    local callback     = LNS.pendingItemData.callback

    -- Call the callback with the selected item
    if callback then
        callback(selectedItem)
    else
        Logger.Warn(LNS.guiLoot.console, "No callback defined for selected item.")
    end

    -- Clear pending data after processing
    LNS.pendingItemData = nil
end

function LNS.getRuleIndex(rule, ruleList)
    for i, v in ipairs(ruleList) do
        if v == rule then
            return i
        end
    end
    return 1
end

function LNS.retrieveClassList(item)
    local classList = ""
    local numClasses = item.Classes()
    if numClasses == 0 then return 'None' end
    if numClasses < 16 then
        for i = 1, numClasses do
            classList = string.format("%s %s", classList, item.Class(i).ShortName():lower())
        end
    elseif numClasses == 16 then
        classList = "All"
    else
        classList = "None"
    end
    return classList
end

function LNS.retrieveRaceList(item)
    local racesShort = {
        ['Human'] = 'HUM',
        ['Barbarian'] = 'BAR',
        ['Erudite'] = 'ERU',
        ['Wood Elf'] = 'ELF',
        ['High Elf'] = 'HIE',
        ['Dark Elf'] = 'DEF',
        ['Half Elf'] = 'HEF',
        ['Dwarf'] = 'DWF',
        ['Troll'] = 'TRL',
        ['Ogre'] = 'OGR',
        ['Halfling'] = 'HFL',
        ['Gnome'] = 'GNM',
        ['Iksar'] = 'IKS',
        ['Vah Shir'] = 'VAH',
        ['Froglok'] = 'FRG',
        ['Drakkin'] = 'DRK',
    }
    local raceList = ""
    local numRaces = item.Races() or 16
    if numRaces < 16 then
        for i = 1, numRaces do
            local raceName = racesShort[item.Race(i).Name()] or ''
            raceList = string.format("%s %s", raceList, raceName)
        end
    else
        raceList = "All"
    end
    return raceList
end

---@param itemName string Item's Name
---@param allowDuplicates boolean|nil optional just return first matched item_id
---@return integer|nil ItemID or nil if no matches found
function LNS.resolveItemIDbyName(itemName, allowDuplicates, exactMatch)
    if allowDuplicates == nil then allowDuplicates = false end
    local matches = {}

    local foundItems = LNS.GetItemFromDB(itemName, 0, false, exactMatch)
    if foundItems > 1 and (not allowDuplicates or exactMatch) then
        Logger.Warn(LNS.guiLoot.console, "\ayMultiple \atMatches Found for ItemName: \am%s \ax #\ag%d\ax Returning \aoFirst Match.", itemName, foundItems)
    end

    local count = LNS.GetItemFromDB(itemName, 0)
    if count > 0 then
        for id, item in pairs(LNS.ALLITEMS or {}) do
            if item.Name:lower() == itemName:lower() then
                if allowDuplicates and item.Value ~= '0 pp 0 gp 0 sp 0 cp' and item.Value ~= nil then
                    table.insert(matches,
                        { ID = id, Link = item.Link, Name = item.Name, Value = item.Value, })
                else
                    table.insert(matches,
                        { ID = id, Link = item.Link, Name = item.Name, Value = item.Value, })
                end
            end
        end
    end

    if not allowDuplicates and matches[1] then
        return matches[1].ID
    end

    if #matches == 0 then
        return nil           -- No matches found
    elseif #matches == 1 then
        return matches[1].ID -- Single match
    else
        return nil           -- Wait for user resolution
    end
end

---comment
---@param item MQItem the item to ckeck
---@param lootDecision string the current decision
---@return string @the new decision
function LNS.checkDecision(item, lootDecision)
    if lootDecision == nil then return 'Ask' end
    if item == nil or lootDecision == 'Ask' then return lootDecision end
    local newDecision  = lootDecision or 'Keep'
    local sellPrice    = (item.Value() or 0) / 1000
    local stackable    = item.Stackable()
    local tributeValue = item.Tribute() or 0
    local stackSize    = item.StackSize() or 0
    local tsItem       = item.Tradeskills()

    -- handle sell and tribute
    if not stackable and sellPrice < settings.Settings.MinSellPrice then newDecision = "Ignore" end
    if not stackable and settings.Settings.StackableOnly then newDecision = "Ignore" end
    if stackable and sellPrice * stackSize < settings.Settings.StackPlatValue then newDecision = "Ignore" end
    if tributeValue >= settings.Settings.MinTributeValue and sellPrice < settings.Settings.MinSellPrice then newDecision = "Tribute" end
    if settings.Settings.AutoTag and newDecision == "Keep" then
        if not stackable and sellPrice > settings.Settings.MinSellPrice and not tsItem then
            newDecision = "Sell"
        end
        if stackable and sellPrice * stackSize >= settings.Settings.StackPlatValue and not tsItem then
            newDecision = "Sell"
        end
    end
    Logger.Debug(LNS.guiLoot.console,
        "\aoCheck Decision\ax (\ay%s\ax) Old: (\at%s\ax) SellPrice: (\ag%.2f\ax) Stackable: (\ag%s\ax) StackSize: (\ag%d\ax) TributeValue: (\ag%d\ax) \agNEW Decision\ax: (\at%s\ax)",
        item.Name(), lootDecision, sellPrice, tostring(stackable), stackSize, tributeValue, newDecision)
    return newDecision
end

--- comment
--- @param decision string
--- @param allowedClasses string
--- @param fromFunction string
--- @param is_new_item boolean
--- @return string
function LNS.checkClasses(decision, allowedClasses, fromFunction, is_new_item)
    local ret = decision
    if fromFunction ~= 'loot' then return ret end
    local tmp_classes = allowedClasses:lower() or 'all'
    if tmp_classes == 'none' or tmp_classes == '' then
        tmp_classes = 'all'
    end

    if (ret:lower() == 'keep' or ret:lower() == 'canuse') then
        if string.find(tmp_classes, LNS.MyClass) then
            ret = "Keep"
        else
            ret = "Ignore"
        end

        if tmp_classes == 'all' then
            ret = "Keep"
        end
    end

    local dbgTbl = {
        Lookup = '\ax\ag Check for \ayClass Rules',
        OldDecision = decision,
        NewDecision = ret,
        AllowedClasses = allowedClasses,
        Classes = tmp_classes,
        MyClass = LNS.MyClass,
    }
    Logger.Debug(LNS.guiLoot.console, dbgTbl)
    return ret
end

function LNS.checkWearable(isEquippable, decision, ruletype, nodrop, newrule, isAug, item)
    local msgTbl = {}
    local iCanWear = false
    if isEquippable then
        if ruletype ~= 'Personal' and ((settings.Settings.CanWear and (decision == 'Keep' or decision == 'CanUse')) or
                -- (decision == 'Keep' or decision == 'CanUse') or (nodrop and newrule)) then
                (decision == 'CanUse') or (nodrop and newrule)) then
            if not item.CanUse() then
                decision = 'Ignore'
                iCanWear = false
                msgTbl = {
                    Check = "Check Decision \ax\agWEARABLE",
                    CanUse = item.CanUse() or false,
                    Decision = decision,
                }
                Logger.Debug(LNS.guiLoot.console, msgTbl)
            else
                decision = 'Keep'
                iCanWear = true
            end
        end
    else
        if nodrop and settings.Settings.CanWear and ruletype == 'Normal' and not isAug then
            decision = 'Ignore'
            iCanWear = false
        end
    end
    return iCanWear, decision
end

---comment
---@param curRule string Current Rule
---@param onhand number Number of items on hand
---@param curClasses string Current Classes
---@return string tmpDecision The new decision
---@return number qKeep The number of items to keep
function LNS.checkQuest(curRule, onhand, curClasses)
    if not settings.Settings.LootQuest then
        Logger.Warn(LNS.guiLoot.console, "\aoQuest Item\ax Rule: (\ay%s\ax) is (\ardDISABLED\ax) in settings. Ignoring.", curRule)
        return 'Ignore', 0
    end

    local tmpDecision = "Quest"
    local qKeep = settings.Settings.QuestKeep or 1
    local _, position = string.find(curRule, "|")
    if position then
        qKeep = tonumber(curRule:sub(position + 1)) or qKeep
    end
    local dbgTbl = {}

    if onhand >= qKeep then
        tmpDecision = "Ignore"
    end
    dbgTbl = {
        Lookup = '\ax\ag Check for QUEST',
        Decision = tmpDecision,
        Rule = curRule,
    }
    Logger.Debug(LNS.guiLoot.console, dbgTbl)
    if tmpDecision == "Ignore" then
        Logger.Info(LNS.guiLoot.console, "\aoQuest Item\ax Rule: (\ay%s\ax), Decision\ax: (\ao%s)\ax Status\ax: (\agHave Enough\ax)",
            curRule, tmpDecision, onhand, qKeep)
        return tmpDecision, qKeep
    end

    tmpDecision = LNS.checkClasses('Keep', curClasses, 'loot', false)
    if tmpDecision == 'Ignore' then
        Logger.Info(LNS.guiLoot.console, "\aoQuest Item\ax Rule: (\ay%s\ax), Decision\ax: (\ao%s)\ax Status\ax: (\aoWrong Class\ax)",
            curRule, tmpDecision)
        return tmpDecision, qKeep
    end

    if tmpDecision == 'Keep' then
        tmpDecision = 'Quest'
    end

    dbgTbl = {
        Lookup = '\ax\ag Check for QUEST CLASSES',
        Decision = tmpDecision,
        Classes = curClasses,
        Rule = curRule,
    }
    Logger.Debug(LNS.guiLoot.console, dbgTbl)
    Logger.Info(LNS.guiLoot.console, "\aoQuest Item\ax Rule: (\ay%s\ax), Decision\ax: (\ao%s)\ax Status\ax: (\ay%s\ax / \at%s\ax)",
        curRule, tmpDecision, onhand, qKeep)
    return tmpDecision, qKeep
end

--- Check if the item is a Lore item and if we should keep it.
---@param itemName string The name of the item
---@param itemLink string The item link
---@param decision string The current decision
---@param countHave number The number of items on hand
---@param isLore boolean True if the item is Lore
---@return string ret The new decision
---@return boolean lootable True if the item is lootable
function LNS.checkLore(itemName, itemLink, decision, countHave, isLore)
    if not isLore then
        return decision, true
    end
    if countHave > 0 then
        Logger.Warn(LNS.guiLoot.console, "Item is \ayLORE\ax and I \arHAVE\ax it. Ignoring.")
        if shouldLootActions[decision] then
            if not skippedLoots[itemLink] then
                table.insert(skippedLoots, itemLink)
                skippedLoots[itemLink] = true
            end
        end
        return 'Ignore', false
    end
    local ret = decision
    local lootable = true
    local freeSpace = mq.TLO.Me.FreeInventory()
    if freeSpace <= settings.Settings.SaveBagSlots then
        if not skippedLoots[itemLink] then
            table.insert(skippedLoots, itemLink)
            skippedLoots[itemLink] = true
        end
        ret = 'Ignore'
        lootable = false
    end
    -- if shouldLootActions[decision] and not skippedLoots[itemLink] then table.insert(skippedLoots, itemLink) skippedLoots[itemLink] = true end
    local dbgTbl = {
        Lookup = '\ax\ag Check for LORE',
        IsLore = isLore,
        Have = (countHave > 0),
        Decision = ret,
        Item = itemName,
        Link = itemLink,
    }
    Logger.Debug(LNS.guiLoot.console, dbgTbl)
    return ret, true
end

--- Evaluate and return the rule for an item.
---@param item MQItem Item object
---@param fromFunction string Source of the of the callback (loot, bank, etc.)
---@return string Rule The Loot Rule or decision of no Rule
---@return integer Count The number of items to keep if Quest Item
---@return boolean newRule True if Item does not exist in the Rules Tables
---@return boolean cantWear True if the item is not wearable by the character
function LNS.getRule(item, fromFunction, index)
    if item == nil or not item() then return 'NULL', 0, false, true end
    local itemID = item.ID() or 0
    if itemID == 0 then return 'NULL', 0, false, true end

    -- Initialize values
    local lootDecision = 'Ignore'
    local sellPrice    = (item.Value() or 0) / 1000
    local stackable    = item.Stackable()
    local isAug        = item.Type() == 'Augmentation'
    local tributeValue = item.Tribute() or 0

    local countHave    = mq.TLO.FindItemCount(item.Name())() + mq.TLO.FindItemBankCount(item.Name())()
    local itemName     = item.Name()
    local newRule      = false
    local alwaysAsk    = true
    local qKeep        = 0
    local iCanUse      = true
    local freeSpace    = mq.TLO.Me.FreeInventory()
    local isEquippable = (item.WornSlots() or 0) > 0
    local itemLink     = item.ItemLink('CLICKABLE')() or 'NULL'
    local dbgTbl       = {}
    local freeStack    = item.FreeStack()
    local isLore       = item.Lore()
    local isNoDrop     = item.NoDrop() or item.NoTrade()
    local lootLore     = true -- i don't have item and its lore so i can loot it
    local cID          = mq.TLO.Corpse.ID() or 0

    -- check imported items missing ID's if there is a matching name and only 1 or less items in the db update the rule with the items ID.
    if LNS.GlobalMissingNames[itemName] then
        if LNS.findItem(itemName) == 1 then
            local negID = LNS.GlobalMissingNames[itemName] or 0
            if negID < 0 then
                LNS.modifyItemRule(itemID,
                    LNS.GlobalItemsMissing[negID].item_rule,
                    'Global_Rules',
                    LNS.GlobalItemsMissing[negID].item_classes,
                    itemLink)

                Logger.Info(LNS.guiLoot.console, "\arItem \ax%s\ar is missing from the database. Re-adding with \ayImported rule\ax: \ag%s\ax",
                    itemName, LNS.GlobalItemsMissing[negID].item_rule)
                LNS.GlobalMissingNames[itemName] = nil
                LNS.GlobalItemsMissing[negID] = nil
            end
        end
    end
    if LNS.NormalMissingNames[itemName] then
        if LNS.findItem(itemName) == 1 then
            local negID = LNS.NormalMissingNames[itemName] or 0
            if negID < 0 then
                LNS.modifyItemRule(itemID,
                    LNS.NormalItemsMissing[negID].item_rule,
                    'Normal_Rules',
                    LNS.NormalItemsMissing[negID].item_classes,
                    itemLink)

                Logger.Info(LNS.guiLoot.console, "\arItem \ax%s\ar is missing from the database. Re-adding with \ayImported rule\ax: \ag%s\ax",
                    itemName, LNS.NormalItemsMissing[negID].item_rule)
                LNS.NormalMissingNames[itemName] = nil
                LNS.NormalItemsMissing[negID] = nil
            end
        end
    end
    -- Lookup existing rule in the databases

    local lootRule, lootClasses, lootLink, ruletype = LNS.lookupLootRule(item, itemID, nil, itemLink, false)
    Logger.Debug(LNS.guiLoot.console, "\ax\ao Lookup Rule \axItem: (\at%s\ax) ID: (\ag%s\ax) Rule: (\ay%s\ax) Classes: (\at%s\ax)",
        itemName, itemID, lootRule, lootClasses)
    -- check for always eval
    if settings.Settings.AlwaysEval and ruletype == 'Normal' then
        if lootRule ~= "Quest" and lootRule ~= "Keep" and lootRule ~= "Destroy" and lootRule ~= 'CanUse' and lootRule ~= 'Ask' and lootRule ~= 'Bank' then
            lootRule = 'NULL'
        end
    end

    local existingIgnoreRule = lootRule == 'Ignore'
    newRule = lootRule == 'NULL' or false

    ---- NEW RULES ----

    if newRule then
        Logger.Info(LNS.guiLoot.console, "\ax\ag NEW RULE Detected!\ax Item: (\at%s\ax)", itemName, lootRule)
        lootClasses = LNS.retrieveClassList(item)
        ruletype = 'Normal'
        local addToDB = true
        lootRule = "Ask"

        if settings.Settings.UseAutoRules then
            -- NODROP
            if isNoDrop then
                addToDB = (settings.Settings.LootNoDropNew and settings.Settings.LootNoDrop) or false
                if isEquippable and addToDB then
                    lootRule = "CanUse"
                else
                    return 'Ask', 0, newRule, isEquippable
                end
            else
                if not isEquippable then
                    if sellPrice > 0 then
                        lootRule = 'Sell'
                    elseif tributeValue > 0 then
                        lootRule = 'Tribute'
                    end
                else
                    lootRule = 'Keep'
                end
            end
        end
        Logger.Info(LNS.guiLoot.console, "\ax\agSetting NEW RULE\ax Item: (\at%s\ax) Rule: (\ag%s\ax)",
            itemName, lootRule)
        LNS.addNewItem(item, lootRule, itemLink, mq.TLO.Corpse.ID() or 0, addToDB)
    end

    lootDecision = lootRule

    -- Handle AlwaysAsk setting
    if settings.Settings.AlwaysAsk or lootRule == "Ask" then
        newRule = true
        lootDecision = "Ask"
        dbgTbl = {
            Lookup = '\ax\ag Check for ASK',
            Decision = lootDecision,
            Classes = lootClasses,
            Item = itemName,
            Link = lootLink,
        }
        Logger.Debug(LNS.guiLoot.console, dbgTbl)

        LNS.addNewItem(item, lootRule, itemLink, mq.TLO.Corpse.ID() or 0, false)
        if settings.Settings.MasterLooting and ruletype ~= 'Personal' then
            actors.Send({
                who = settings.MyName,
                Server = settings.EqServer,
                action = 'check_item',
                CorpseID = cID or 0,
            })
            mq.delay(5)
        end
        return lootDecision, 0, newRule, isEquippable
    end

    -- handle ignore and destroy rules
    if lootRule == 'Ignore' and not (settings.Settings.DoDestroy and settings.Settings.AlwaysDestroy) then
        Logger.Info(LNS.guiLoot.console, "\ax\aoRule\ax: (\ayIGNORE\ax) \aoSkipping\ax (\at%s\ax)", itemName)
        if settings.Settings.MasterLooting and ruletype ~= 'Personal' then
            actors.Send({
                who = settings.MyName,
                Server = settings.EqServer,
                action = 'check_item',
                CorpseID = mq.TLO.Corpse.ID() or 0,
            })
            mq.delay(5)
        end
        return 'Ignore', 0, newRule, isEquippable
    elseif lootRule == 'Ignore' and settings.Settings.DoDestroy and settings.Settings.AlwaysDestroy then
        Logger.Info(LNS.guiLoot.console, "\ax\ao Rule\ax: (\ayIGNORE\ax) and (\ayALWAYS DESTROY\ax) \at%s\ax", itemName)
        if settings.Settings.MasterLooting and ruletype ~= 'Personal' then
            actors.Send({
                who = settings.MyName,
                Server = settings.EqServer,
                action = 'check_item',
                CorpseID = mq.TLO.Corpse.ID() or 0,
            })
            mq.delay(5)
        end
        return 'Destroy', 0, newRule, isEquippable
    end

    if lootRule == 'Destroy' then
        Logger.Info(LNS.guiLoot.console, "\ax\ao Rule\ax: (\arDESTROY\ax) \at%s\ax", itemName)
        if settings.Settings.MasterLooting and ruletype ~= 'Personal' then
            actors.Send({
                who = settings.MyName,
                Server = settings.EqServer,
                action = 'check_item',
                CorpseID = mq.TLO.Corpse.ID() or 0,
            })
            mq.delay(5)
        end
        return 'Destroy', 0, newRule, isEquippable
    end

    if settings.Settings.StackableOnly and not stackable and not settings.Settings.MasterLooting then
        Logger.Info(LNS.guiLoot.console, "\ax\ao Rule\ax: \aySTACKABLE ONLY\ax and item is \arNOT stackable \at%s\ax", itemName)

        return 'Ignore', 0, newRule, isEquippable
    end

    ---check lore
    if isLore then
        lootLore = countHave == 0
        if not lootLore and not settings.Settings.MasterLooting then
            if not existingIgnoreRule and not skippedLoots[itemLink] then
                table.insert(skippedLoots, itemLink)
                skippedLoots[itemLink] = true
            end
            Logger.Info(LNS.guiLoot.console, "\aoItem \ax(\at%s\ax) is \ayLORE\ax and I \aoHAVE\ax it. Ignoring.", itemName)
            return 'Ignore', 0, newRule, isEquippable
        end
    end

    --handle NoDrop
    if isNoDrop and not settings.Settings.LootNoDrop and not settings.Settings.MasterLooting then
        Logger.Info(LNS.guiLoot.console, "\axItem is \aoNODROP\ax \at%s\ax and LootNoDrop is \arNOT \axenabled\ax", itemName)
        if not existingIgnoreRule and not skippedLoots[itemLink] then
            table.insert(skippedLoots, itemLink)
            skippedLoots[itemLink] = true
        end
        return 'Ignore', 0, newRule, isEquippable
    end

    -- check Classes that can loot
    if ruletype ~= 'Personal' and lootRule ~= 'Sell' and
        lootRule ~= 'Ask' and lootRule ~= 'Tribute' and not (lootRule:find('Quest'))
        and not (settings.Settings.KeepSpells and (itemName:find('Spell:') or itemName:find('Song:'))) and
        not (settings.Settings.LootAugments and isAug) and not settings.Settings.MasterLooting then
        Logger.Debug(LNS.guiLoot.console, "\ax\ag Checking Classes for Rule: \at%s\ax", lootRule)

        lootDecision = LNS.checkClasses(lootRule, lootClasses, fromFunction, newRule)

        if lootDecision == 'Ignore' then
            Logger.Info(LNS.guiLoot.console, "\ax\aoItem\ax (\ag%s\ax) Classes: (\at%s)\ax MyClass: (\ay%s\ax) Decision: (\at%s\ax)",
                itemName, lootClasses, LNS.MyClass, lootDecision)

            return lootDecision, qKeep, newRule, isEquippable
        end

        Logger.Debug(LNS.guiLoot.console, "\ax\aoItem\ax (\ag%s\ax) Classes: (\at%s)\ax MyClass: (\ay%s\ax) Decision: (\at%s\ax)",
            itemName, lootClasses, LNS.MyClass, lootDecision)
    end

    if lootRule == 'CanUse' and isEquippable then
        lootDecision = LNS.checkClasses(lootRule, lootClasses, fromFunction, newRule)
        iCanUse, lootDecision = LNS.checkWearable(isEquippable, lootRule, ruletype, isNoDrop, newRule, isAug, item)
    end

    if ((lootRule == 'Sell' or lootRule == 'Tribute') and ruletype == 'Normal') then
        Logger.Debug(LNS.guiLoot.console, "\ax\ag Checking Decision for \aySELL\ax or \ayTRIBUTE\ax: \at%s\ax", lootRule)
        lootDecision = LNS.checkDecision(item, lootRule)
    end

    -- check bag space
    if not (freeSpace > settings.Settings.SaveBagSlots or (stackable and freeStack > 0)) and not settings.Settings.MasterLooting then
        dbgTbl = {
            Lookup = '\ax\ag Check for BAGSPACE',
            Decision = lootDecision,
            Classes = lootClasses,
            Item = itemName,
            Link = lootLink,
        }
        Logger.Warn(LNS.guiLoot.console, "You are \arOUT OF BAG SPACE\ax. \aoIgnoring.")
        Logger.Debug(LNS.guiLoot.console, dbgTbl)
        -- loot.lootItem(i, itemRule, 'leftmouseup', qKeep, allItems)

        return 'Ignore', 0, newRule, isEquippable
    end

    -- Handle augments
    if settings.Settings.LootAugments and isAug and ruletype == 'Normal' and not settings.Settings.MasterLooting then
        lootDecision = "Keep"
        dbgTbl = {
            Lookup = '\ax\ag Check for AUGMENTS',
            Decision = lootDecision,
            Classes = lootClasses,
            Item = itemName,
            Link = lootLink,
        }
        Logger.Debug(LNS.guiLoot.console, dbgTbl)
        Logger.Info(LNS.guiLoot.console, "\at%s\ax is an \agAUG\ax", itemName)
    end

    -- Handle Spell Drops
    if settings.Settings.KeepSpells and LNS.checkSpells(itemName) and ruletype == 'Normal' and not settings.Settings.MasterLooting then
        lootDecision = "Keep"
        dbgTbl = {
            Lookup = '\ax\ag Check for SPELLS',
            Decision = lootDecision,
            Classes = lootClasses,
            Item = itemName,
            Link = lootLink,
        }
        Logger.Debug(LNS.guiLoot.console, dbgTbl)
        Logger.Info(LNS.guiLoot.console, "\at%s\ax is a \agSPELL\ax", itemName)
    end

    -- check Quests
    if string.find(lootRule, "Quest") and not settings.Settings.MasterLooting then
        Logger.Debug(LNS.guiLoot.console, "\ag Checking for QUEST Rule: \at%s\ax", lootRule)
        lootDecision, qKeep = LNS.checkQuest(lootRule, countHave, lootClasses)
        if lootDecision == 'Ignore' then
            return lootDecision, qKeep, newRule, isEquippable
        end
    end

    if type(lootDecision) ~= 'string' then
        Logger.Warn(LNS.guiLoot.console, "Invalid lootDecision type: %s for item: %s", type(lootDecision), itemName)
        lootDecision = 'Ignore'
    end

    if settings.Settings.MasterLooting and ((lootRule == 'Ignore' and ruletype ~= 'Personal') or lootDecision == 'Destroy') then
        actors.Send({
            who = settings.MyName,
            Server = settings.EqServer,
            action = 'check_item',
            CorpseID = mq.TLO.Corpse.ID() or 0,
        })
        mq.delay(5)

        return 'Ignore', qKeep, newRule, isEquippable
    elseif settings.Settings.MasterLooting then
        LNS.InsertMasterLootList(itemName, cID, itemID, LNS.ItemLinks[itemID],
            isLore, isNoDrop, item.Value())

        mq.delay(5)
        return 'MasterLooter', qKeep, newRule, iCanUse
    end

    if lootDecision == 'Ask' then
        if not skippedLoots[itemLink] then
            table.insert(skippedLoots, itemLink)
            skippedLoots[itemLink] = true
        end
    end
    Logger.Debug(LNS.guiLoot.console, "\aoLEAVING getRule()\ax: Rule: \at%s\ax, \ayClasses\ax: \at%s\ax, Item: \ao%s\ax, ID: \ay%s\ax, \atLink: %s",
        lootDecision, lootClasses, itemName, itemID, lootLink)

    return lootDecision, qKeep, newRule, iCanUse
end

function LNS.setBuyItem(itemName, qty)
    settings.TempSettings.BuyItems[itemName] = { Key = itemName, Value = qty, }
    settings.Settings.BuyItemsTable[itemName] = qty
    LNS.BuyItemsTable[itemName] = qty
end

-- Sets a Global Item rule
function LNS.setGlobalItem(itemID, val, classes, link)
    if itemID == nil then
        Logger.Warn(LNS.guiLoot.console, "Invalid itemID for setGlobalItem.")
        return
    end
    LNS.modifyItemRule(itemID, val, 'Global_Rules', classes, link)

    LNS.GlobalItemsRules[itemID] = val ~= 'delete' and val or nil
    if val ~= 'delete' then
        LNS.GlobalItemsClasses[itemID] = classes or 'All'
        LNS.ItemLinks[itemID]          = link or (LNS.ItemLinks[itemID] or 'NULL')
    else
        LNS.GlobalItemsClasses[itemID] = nil
        LNS.GlobalItemsMissing[settings.TempSettings.ModifyItemID] = nil
    end
end

-- Sets a Normal Item rule
function LNS.setNormalItem(itemID, val, classes, link)
    if itemID == nil then
        Logger.Warn(LNS.guiLoot.console, "Invalid itemID for setNormalItem.")
        return
    end
    LNS.NormalItemsRules[itemID] = val ~= 'delete' and val or nil
    if val ~= 'delete' then
        LNS.NormalItemsClasses[itemID] = classes or 'All'
        LNS.ItemLinks[itemID]          = link or (LNS.ItemLinks[itemID] or 'NULL')
    else
        LNS.NormalItemsClasses[itemID] = nil
        LNS.NormalItemsMissing[settings.TempSettings.ModifyItemID] = nil
    end
    LNS.modifyItemRule(itemID, val, 'Normal_Rules', classes, link)
end

function LNS.setPersonalItem(itemID, val, classes, link)
    if itemID == nil then
        Logger.Warn(LNS.guiLoot.console, "Invalid itemID for setPersonalItem.")
        return
    end
    LNS.PersonalItemsRules[itemID] = val ~= 'delete' and val or nil
    if val ~= 'delete' then
        LNS.PersonalItemsClasses[itemID] = classes or 'All'
        LNS.ItemLinks[itemID]            = link or (LNS.ItemLinks[itemID] or 'NULL')
    else
        LNS.PersonalItemsClasses[itemID] = nil
    end
    LNS.modifyItemRule(itemID, val, settings.PersonalTableName, classes, link)
end

function LNS.GetTableSize(tbl)
    local count = 0
    if tbl == nil then return count end
    for _ in pairs(tbl) do
        count = count + 1
    end
    return count
end

------------------------------------
--      LOOTING
------------------------------------


---@param mq_item MQItem|nil @The item to loot.
---@param index number @The current index in the loot window, 1-based.
---@param doWhat string @The action to take for the item.
---@param button string @The mouse button to use to loot the item. Only "leftmouseup" is currently implemented.
---@param qKeep number @The count to keep for quest items.
---@param cantWear boolean|nil @ Whether the character canwear the item
function LNS.lootItem(mq_item, index, doWhat, button, qKeep, cantWear)
    local startTime = mq.gettime()
    Logger.Debug(LNS.guiLoot.console, 'Enter lootItem')
    if doWhat == nil or type(doWhat) ~= 'string' then return end
    local actionToTake = doWhat:gsub("%s$", "")
    local actionLower = actionToTake:lower()
    local corpseName = mq.TLO.Corpse.CleanName() or 'none'
    local cItem = mq_item or mq.TLO.Corpse.Item(index)
    if not cItem then return end
    local cItemID = cItem.ID() or 0

    if cItemID == 0 or (mq_item and mq_item() and mq_item.ID() ~= cItemID) then
        Logger.Warn(LNS.guiLoot.console, "lootItem(): ID does not match corpse item ID.")
        return
    end

    local itemName       = cItem.Name() or 'none'
    local itemLink       = cItem.ItemLink('CLICKABLE')()
    local isGlobalItem   = settings.Settings.GlobalLootOn and (LNS.GlobalItemsRules[cItemID] ~= nil) --or LNS.BuyItemsTable[itemName] ~= nil)
    local isPersonalItem = LNS.PersonalItemsRules[cItemID] ~= nil
    local corpsePos      = corpseName:find("corpse")
    local tmpLabel       = corpsePos and corpseName:sub(1, corpsePos - 4) or corpseName
    corpseName           = tmpLabel
    local eval           = type(actionToTake) == 'string' and actionToTake or '?'
    local dbgTbl         = {}
    local rule           = isGlobalItem and LNS.GlobalItemsRules[cItemID] or
        (isPersonalItem and LNS.PersonalItemsRules[cItemID] or (LNS.NormalItemsRules[cItemID] or nil))
    if allItems == nil then allItems = {} end
    dbgTbl = {
        Lookup = 'loot.lootItem()',
        Check = 'Loot ITEM Entry',
        Evaluation = eval,
        Item = itemName,
        Link = itemLink,
        Action = actionToTake,
        Index = index,
        Corpse = corpseName,
    }
    Logger.Debug(LNS.guiLoot.console, dbgTbl)
    if cItem and not shouldLootActions[actionToTake] then
        Logger.Warn(LNS.guiLoot.console, "lootItem():\ay We Don't Belong here!!,\ax either the item is \arMissing\ax or the Action [\at%s\ax] is \arNot\ax a valid loot action.",
            actionToTake)
        return
    end

    -- Check to see if we are allowed to loot this item
    if shouldLootActions[actionToTake] then
        if mq.TLO.Window('ConfirmationDialogBox').Open() then
            Logger.Warn(LNS.guiLoot.console, "lootItem(): ConfirmationDialogBox is open. Closing it.")
            mq.TLO.Window('ConfirmationDialogBox').DoClose()
            mq.delay(1000, function() return not mq.TLO.Window('ConfirmationDialogBox').Open() end)
        end
        Logger.Info(LNS.guiLoot.console, "lootItem(): \agLooting\ax item: \at%s\ax with action: \ay%s", itemName, actionToTake)
        mq.delay(1)
        mq.cmdf('/nomodkey /shift /itemnotify loot%s %s', index, button)
        mq.delay(1) -- Small delay to ensure command execution.

        mq.delay(5000, function()
            return mq.TLO.Window('ConfirmationDialogBox').Open() or mq.TLO.Cursor() ~= nil
        end)

        -- Handle confirmation dialog for no-drop items
        if mq.TLO.Window('ConfirmationDialogBox').Open() then
            mq.cmdf('/nomodkey /notify ConfirmationDialogBox Yes_Button leftmouseup')
        end

        mq.delay(5000, function()
            return mq.TLO.Cursor() ~= nil or not mq.TLO.Window('LootWnd').Open()
        end)
        -- Ensure next frame processes
        mq.delay(1)

        -- If loot window closes unexpectedly, exit the function
        if not mq.TLO.Window('LootWnd').Open() then
            Logger.Warn(LNS.guiLoot.console, "lootItem(): Loot window closed unexpectedly. Cannot loot item: %s", itemName)
            return
        end
        Logger.Debug(LNS.guiLoot.console, string.format("eval = %s", eval))
        if actionLower == 'destroy' then
            mq.delay(10000, function() return mq.TLO.Cursor.ID() == cItemID end)
            eval = isGlobalItem == true and 'Global Destroy' or 'Destroy'
            eval = isPersonalItem == true and 'Personal Destroy' or eval
            Logger.Debug(LNS.guiLoot.console, string.format("Destroying (\ay%s\ax) Eval (\ao%s\ax)", itemName, eval))
            mq.cmdf('/destroy')
            dbgTbl = {
                Lookup = 'loot.lootItem()',
                Check = 'Check Destroy',
                Evaluation = eval,
                Item = itemName,
                Link = itemLink,
            }
            Logger.Debug(LNS.guiLoot.console, dbgTbl)
        end

        LNS.checkCursor()

        -- Handle quest item logic
        if qKeep == nil then qKeep = 0 end
        if qKeep > 0 and actionLower == 'quest' then
            eval = isGlobalItem == true and 'Global Quest' or 'Quest'
            eval = isPersonalItem == true and 'Personal Quest' or eval
            if type(eval) == 'boolean' then eval = 'Ask' end

            local countHave = mq.TLO.FindItemCount(itemName)() + mq.TLO.FindItemBankCount(itemName)()
            LNS.report("\awQuest Item:\ag %s \awCount:\ao %s \awof\ag %s", itemLink, tostring(countHave), qKeep)
            Logger.Info(LNS.guiLoot.console, string.format("\awQuest Item:\ag %s \awCount:\ao %s \awof\ag %s", itemLink, countHave, qKeep))
        else
            Logger.Debug(LNS.guiLoot.console, string.format("eval = %s", eval))

            eval = isGlobalItem == true and 'Global ' .. actionToTake or actionToTake
            eval = isPersonalItem == true and 'Personal ' .. actionToTake or eval
            if type(eval) == 'boolean' then eval = 'Ask' end

            Logger.Debug(LNS.guiLoot.console, string.format("eval = %s", eval))
        end

        if actionLower == 'ignore' then eval = 'Left' end
        -- Log looted items
        dbgTbl = {
            Lookup = 'loot.lootItem()',
            Action = 'INSERT HISTORY',
            Evaluation = eval,
            Item = itemName,
            Link = itemLink,
        }

        LNS.CheckBags()

        -- Check for full inventory
        if areFull == true then
            LNS.report('My bags are full, I can\'t loot anymore! \aoOnly Looting \ayCoin\ax and Items I have \atStack Space\ax for')
        end
        perf:OnFrameExec('lootitem', mq.gettime() - startTime)

        if settings.Settings.TrackHistory then
            startTime = mq.gettime()
            Logger.Debug(LNS.guiLoot.console, "\aoINSERT HISTORY CHECK 4\ax: \ayAction\ax: \at%s\ax, Item: \ao%s\ax, \atLink: %s", eval, itemName, itemLink)
            local allItemsEntry = LNS.insertIntoHistory(itemName, corpseName, eval,
                os.date('%Y-%m-%d'), os.date('%H:%M:%S'), itemLink, settings.MyName, LNS.Zone, allItems, cantWear, rule)

            if allItemsEntry and LNS.GetTableSize(allItemsEntry) > 0 then
                table.insert(allItems, allItemsEntry)
            end

            local consoleAction = rule or ''
            if cantWear then
                consoleAction = consoleAction .. ' \ax(\aoCant Wear\ax)'
            end
            local text = string.format('\ao[\at%s\ax] \at%s \ax%s %s Corpse \at%s\ax (\at%s\ax)', os.date('%H:%M:%S'), settings.MyName, consoleAction,
                itemLink, corpseName, mq.TLO.Corpse.ID() or 0)
            if rule == 'Destroyed' then
                text = string.format('\ao[\at%s\ax] \at%s \ar%s \ax%s \axCorpse \at%s\ax (\at%s\ax)', os.date('%H:%M:%S'), settings.MyName, string.upper(rule), itemLink, corpseName,
                    mq.TLO.Corpse.ID() or 0)
            end
            if LNS.guiLoot.console ~= nil then
                LNS.guiLoot.console:AppendText(text)
            end
            perf:OnFrameExec('history', mq.gettime() - startTime)
        end
    end
end

function LNS.lootCorpse(corpseID)
    Logger.Debug(LNS.guiLoot.console, 'Enter lootCorpse')
    local didLootMob          = false
    shouldLootActions.Destroy = settings.Settings.DoDestroy
    shouldLootActions.Tribute = settings.Settings.TributeKeep
    shouldLootActions.Quest   = settings.Settings.QuestKeep
    if corpseID == nil then
        Logger.Warn(LNS.guiLoot.console, "lootCorpse(): No corpseID provided.")
        return didLootMob
    end
    if allItems == nil then allItems = {} end
    skippedLoots = {}

    if mq.TLO.Cursor() then LNS.checkCursor() end

    mq.delay(500, function() return not mq.TLO.Me.Moving() and not mq.TLO.Me.Casting() end)
    for i = 1, 3 do
        if not mq.TLO.Target() then return didLootMob end
        mq.cmdf('/loot')
        mq.delay(1000, function() return mq.TLO.Window('LootWnd').Open() or not mq.TLO.Target() end)
        if mq.TLO.Window('LootWnd').Open() then break end
    end

    mq.doevents('CantLoot')
    mq.delay(1000, function() return cantLootID > 0 or mq.TLO.Window('LootWnd').Open() or not mq.TLO.Target() end)

    if not mq.TLO.Window('LootWnd').Open() then
        if cantLootID == 0 and mq.TLO.Target.ID() == corpseID and not mq.TLO.Window('LootWnd').Open() then
            -- try a little harder
            mq.cmdf('/loot')
            mq.delay(1000, function() return mq.TLO.Window('LootWnd').Open() end)
        end
        cantLootID = 0
        if not mq.TLO.Window('LootWnd').Open() then
            if mq.TLO.Target() and mq.TLO.Target.CleanName() then
                Logger.Warn(LNS.guiLoot.console, "lootCorpse(): Can't loot %s right now", mq.TLO.Target.CleanName() or "unknown")
                cantLootList[corpseID] = os.clock()
            end
            return didLootMob
        end
    end

    local corpseName = mq.TLO.Corpse.CleanName() or 'none'
    corpseName = corpseName:lower()

    mq.delay(1000, function() return (mq.TLO.Corpse.Items() or 0) > 0 end)
    mq.delay(1)
    local numItems = mq.TLO.Corpse.Items() or 0
    Logger.Debug(LNS.guiLoot.console, "lootCorpse(): Loot window open. Items: %s", numItems)
    if numItems == 0 then
        mq.cmdf('/nomodkey /notify LootWnd LW_DoneButton leftmouseup')
        mq.TLO.Window('LootWnd').DoClose()
        mq.delay(2000, function() return not mq.TLO.Window('LootWnd').Open() end)
        Logger.Debug(LNS.guiLoot.console, "lootCorpse(): \arNo items\ax to loot on corpse \at%s\ax (\ay%s\ax)", corpseName, corpseID)
    end

    if mq.TLO.Window('LootWnd').Open() and numItems > 0 then
        if (mq.TLO.Corpse.DisplayName():lower() == mq.TLO.Me.DisplayName():lower() .. "'s corpse") then
            if settings.Settings.LootMyCorpse then
                mq.cmdf('/lootall')
                mq.delay("45s", function() return not mq.TLO.Window('LootWnd').Open() end)
            end
            return didLootMob
        end

        local iList = ""
        local corpseItems = {}
        local loreCorpseItems = {}
        for i = 1, numItems do
            local corpseItem = mq.TLO.Corpse.Item(i)
            if corpseItem() then
                local corpseItemID = corpseItem.ID() or 0
                local itemName = corpseItem.Name() or 'none'
                local itemLink = corpseItem.ItemLink('CLICKABLE')() or 'NULL'
                local itemRule, qKeep, newRule, iCanUse = LNS.getRule(corpseItem, 'loot', i)
                if settings.TempSettings.NewItemData[corpseItemID] == nil then
                    settings.TempSettings.NewItemData[corpseItemID] = {}
                    settings.TempSettings.NewItemData[corpseItemID] = LNS.Get_item_data(corpseItem)
                end
                LNS.addToItemDB(corpseItem)

                iList = string.format("%s (\at%s\ax [\ay%s\ax])", iList, corpseItem.Name() or 'none', itemRule)

                if itemRule ~= 'MasterLooter' and not (itemRule == 'Ignore' or itemRule == 'Ask' or itemRule == 'NULL') then
                    if corpseItem.Lore() then
                        table.insert(loreCorpseItems, {
                            Name = itemName,
                            ID = corpseItemID,
                            ItemLink = itemLink,
                            Index = i,
                            itemRule = itemRule,
                            qKeep = qKeep,
                            newRule = newRule,
                            iCanUse = iCanUse,
                            CorpseID = corpseID,
                            mq_item = corpseItem,
                        })
                    else
                        table.insert(corpseItems, {
                            Name = itemName,
                            ID = corpseItemID,
                            ItemLink = itemLink,
                            Index = i,
                            itemRule = itemRule,
                            qKeep = qKeep,
                            newRule = newRule,
                            iCanUse = iCanUse,
                            CorpseID = corpseID,
                            mq_item = corpseItem,
                        })
                    end
                elseif (itemRule == 'Ignore' or itemRule == 'Ask' or itemRule == 'NULL') then
                    local eval = itemRule == 'Ignore' and 'Left' or 'Ask'
                    local dbgTbl = {
                        Lookup = 'loot.lootCorpse()',
                        Check = 'Skipping Item',
                        Evaluation = itemRule,
                        Item = itemName,
                        Link = itemLink,
                    }
                    Logger.Debug(LNS.guiLoot.console, dbgTbl)

                    if settings.Settings.TrackHistory then
                        local startTime = mq.gettime()
                        local allItemsEntry = LNS.insertIntoHistory(itemName, corpseName, eval,
                            os.date('%Y-%m-%d'), os.date('%H:%M:%S'), itemLink, settings.MyName, LNS.Zone, allItems, not iCanUse, itemRule)
                        if allItemsEntry and LNS.GetTableSize(allItemsEntry) > 0 then
                            table.insert(allItems, allItemsEntry)
                        end

                        local consoleAction = itemRule or ''
                        if not iCanUse then
                            consoleAction = consoleAction .. ' \ax(\aoCant Wear\ax)'
                        end
                        local text = string.format('\ao[\at%s\ax] \at%s \ax%s %s Corpse \at%s\ax (\at%s\ax)', os.date('%H:%M:%S'), settings.MyName, consoleAction,
                            itemLink, corpseName, corpseID)
                        if itemRule == 'Destroyed' then
                            text = string.format('\ao[\at%s\ax] \at%s \ar%s \ax%s \axCorpse \at%s\ax (\at%s\ax)', os.date('%H:%M:%S'), settings.MyName, string.upper(itemRule),
                                itemLink,
                                corpseName, corpseID)
                        end
                        if LNS.guiLoot.console ~= nil then
                            LNS.guiLoot.console:AppendText(text)
                        end
                        perf:OnFrameExec('history', mq.gettime() - startTime)
                    end
                    -- local lbl = itemRule
                    -- if itemRule == 'Ignore' then
                    --     lbl = 'Left'
                    -- elseif itemRule == 'Ask' then
                    --     lbl = 'Asking'
                    -- end
                    -- if settings.Settings.ReportSkippedItems then
                    --     LNS.report('%s (\ao%s\ax) %s', settings.MyName, lbl, itemLink)
                    -- end
                end
            end
            -- if allItems ~= nil and #allItems > 0 then
            --     actors.Send({
            --         ID = corpseID,
            --         Items = allItems,
            --         Zone = LNS.Zone,
            --         Server = settings.EqServer,
            --         LootedAt = mq.TLO.Time(),
            --         CorpseName = mq.TLO.Corpse.DisplayName() or 'unknown',
            --         LootedBy = settings.MyName,
            --     }, 'looted')
            --     allItems = nil
            -- end
        end

        -- if allItems ~= nil and #allItems > 0 then
        --     actors.Send({
        --         ID = corpseID,
        --         Items = allItems,
        --         Zone = LNS.Zone,
        --         Server = settings.EqServer,
        --         LootedAt = mq.TLO.Time(),
        --         CorpseName = mq.TLO.Corpse.DisplayName() or 'unknown',
        --         LootedBy = settings.MyName,
        --     }, 'looted')
        --     allItems = nil
        -- end

        Logger.Debug(LNS.guiLoot.console, "lootCorpse(): Checked \at%s\ax Found (\ay%s\ax) Items:%s", corpseName, numItems, iList)

        for _, itemList in ipairs({ corpseItems, loreCorpseItems, }) do
            for itemIdx, item in ipairs(itemList) do
                if not item then break end
                local itemRule = item.itemRule

                Logger.Debug(LNS.guiLoot.console, "\agLooting Corpse:\ax itemID=\ao%s\ax, Slot: \ay%s\ax, Decision=\at%s\ax, qKeep=\ay%s\ax, newRule=\ag%s",
                    item.ID, item.Index, itemRule, item.qKeep, item.newRule)

                LNS.lootItem(item.mq_item, item.Index, itemRule, 'leftmouseup', item.qKeep, not item.iCanUse)
                if mq.TLO.Corpse.Item(item.Index)() then
                    Logger.Debug(LNS.guiLoot.console, "\ayRetry looting corpse:\ax itemID=\ao%s\ax, Slot: \ay%s\ax, Decision=\at%s\ax, qKeep=\ay%s\ax, newRule=\ag%s",
                        item.ID, item.Index, itemRule, item.qKeep, item.newRule)
                    LNS.lootItem(item.mq_item, item.Index, itemRule, 'leftmouseup', item.qKeep, not item.iCanUse)
                end

                mq.delay(1)
                if mq.TLO.Cursor() then LNS.checkCursor() end
                if not mq.TLO.Window('LootWnd').Open() then
                    if itemIdx < #itemList then Logger.Warn(LNS.guiLoot.console, "\ayCorpse window closed unexpectedly before finishing looting, corpseID=%s", corpseID) end
                    break
                end
            end
        end

        mq.cmdf('/nomodkey /notify LootWnd LW_DoneButton leftmouseup')
        mq.delay(2000, function() return not mq.TLO.Window('LootWnd').Open() end)
        didLootMob = true
    end

    if mq.TLO.Cursor() then LNS.checkCursor() end
    LNS.reportSkippedItems(skippedLoots, corpseName, corpseID)

    return didLootMob
end

function LNS.lootMobs(limit)
    local didLoot = false
    settings.TempSettings.LastCheck = os.clock()

    if LNS.PauseLooting or LNS.SafeZones[LNS.Zone] then
        actors.FinishedLooting()
        return false
    end
    -- check for normal, undead, animal invis should not see rogue sneak\hide
    if mq.TLO.Me.Invis(1)() or mq.TLO.Me.Invis(2)() or mq.TLO.Me.Invis(3)() then
        Logger.Warn(LNS.guiLoot.console, "lootMobs(): You are Invis and we don't want to break it so skipping.")
        actors.FinishedLooting()
        return false
    end

    if limit == nil then limit = 50 end
    if zoneID ~= mq.TLO.Zone.ID() then
        zoneID            = mq.TLO.Zone.ID()
        LNS.lootedCorpses = {}
    end

    if mq.TLO.Window('LootWnd').Open() then
        Logger.Warn(LNS.guiLoot.console, 'lootMobs(): Already Looting, Aborting!.')
        return false
    end


    -- Logger.Debug(loot.guiLoot.console, 'lootMobs(): Entering lootMobs function.')
    local deadCount      = mq.TLO.SpawnCount(string.format('npccorpse radius %s zradius %s', settings.Settings.CorpseRadius or 100, settings.Settings.CorpseZRadius or 50))()
    local mobsNearby     = mq.TLO.SpawnCount(string.format('npc xtarhater radius %s zradius %s', settings.Settings.MobsTooClose + settings.Settings.CorpseRadius,
        settings.Settings.CorpseZRadius or 50))()
    local corpseList     = {}
    -- Logger.Debug(loot.guiLoot.console, 'lootMobs(): Found %s corpses in range.', deadCount)

    -- Handle looting of the player's own corpse
    local pcCorpseFilter = string.format("pccorpse %s's radius %s zradius %s", mq.TLO.Me.CleanName(), settings.Settings.CorpseRadius, settings.Settings.CorpseZRadius or 50)
    local myCorpseCount  = mq.TLO.SpawnCount(pcCorpseFilter)()
    local foundMine      = myCorpseCount > 0

    if not settings.Settings.LootMyCorpse and not settings.Settings.IgnoreMyNearCorpses and foundMine then
        Logger.Debug(LNS.guiLoot.console, 'lootMobs(): Puasing looting until finished looting my own corpse.')
        actors.FinishedLooting()
        return false
    end

    if settings.Settings.LootMyCorpse and not settings.Settings.IgnoreMyNearCorpses and foundMine then
        Logger.Debug(LNS.guiLoot.console, 'lootMobs(): Found my own corpse, attempting to loot it.')
        for i = 1, myCorpseCount do
            LNS.IsLooting = true
            local corpse = mq.TLO.NearestSpawn(string.format("%d, %s", i, pcCorpseFilter))
            if corpse() then
                if (corpse.DisplayName():lower() == mq.TLO.Me.DisplayName():lower()) then
                    corpse.DoTarget()
                    mq.delay(2000, function() return (mq.TLO.Target.ID() or 0) == corpse.ID() end)
                    mq.cmd("/corpse")
                    mq.delay(2000, function() return mq.TLO.Target.Distance() <= 10 end)
                    corpse.RightClick()
                    mq.delay(2000, function() return mq.TLO.Window('LootWnd').Open() end)
                    mq.cmdf('/lootall')
                    mq.delay("45s", function() return not mq.TLO.Window('LootWnd').Open() end)
                end
            end
        end
    end

    -- Stop looting if conditions aren't met
    if (deadCount + myCorpseCount) == 0 or (mobsNearby > 0 and not settings.Settings.CombatLooting) or (mq.TLO.Me.Combat() and not settings.Settings.CombatLooting) then
        actors.FinishedLooting()
        return false
    end

    -- Add other corpses to the loot list if not limited by the player's own corpse
    if (myCorpseCount == 0 or (myCorpseCount > 0 and settings.Settings.IgnoreMyNearCorpses)) and settings.Settings.DoLoot then
        for i = 1, deadCount do
            LNS.IsLooting = true

            local corpse = mq.TLO.NearestSpawn(('%d,' .. spawnSearch):format(i, 'npccorpse', settings.Settings.CorpseRadius, settings.Settings.CorpseZRadius or 50))
            if corpse() and not (LNS.lootedCorpses[corpse.ID()] and settings.Settings.CheckCorpseOnce) then
                if not LNS.checkLockedCorpse(corpse.ID()) and
                    (mq.TLO.Navigation.PathLength('spawn id ' .. corpse.ID())() or 100) < settings.Settings.CorpseRadius then
                    table.insert(corpseList, corpse)
                end
            end
        end
    else
        if settings.Settings.DoLoot then
            Logger.Debug(LNS.guiLoot.console, 'lootMobs(): Skipping other corpses due to nearby player corpse.')
        end
        actors.FinishedLooting()
        return false
    end

    if LNS.Mode == 'directed' and not LNS.LootNow then
        actors.FinishedLooting()
        return false
    end

    -- Process the collected corpse list
    local counter = 0
    if #corpseList > 0 then
        LNS.IsLooting = true

        Logger.Debug(LNS.guiLoot.console, 'lootMobs(): Attempting to loot \at%d\ax corpses.', #corpseList)
        for _, corpse in ipairs(corpseList) do
            local check = false
            local corpseID = corpse.ID() or 0

            if LNS.PauseLooting then
                actors.FinishedLooting()
                return false
            end

            if not mq.TLO.Spawn(corpseID)() then
                Logger.Info(LNS.guiLoot.console, 'lootMobs(): Corpse ID \ay%d \axis \arNO Longer Valid.\ax \atMoving to Next Corpse...', corpseID)
                goto continue
            end

            -- Attempt to move and loot the corpse
            if corpse.DisplayName() == mq.TLO.Me.DisplayName() .. "'s corpse" then
                Logger.Debug(LNS.guiLoot.console, 'lootMobs(): Pulling own corpse closer. Corpse ID: \ag%d', corpseID)
                corpse.DoTarget()
                mq.delay(1)
                mq.cmdf("/corpse")
                mq.delay(10)
            end

            Logger.Debug(LNS.guiLoot.console, 'lootMobs(): Navigating to corpse ID\at %d.', corpseID)

            if mq.TLO.Me.Casting() ~= nil and mq.TLO.Me.Class.ShortName() ~= 'BRD' then
                return false
            end

            LNS.navToID(corpseID)

            if mobsNearby > 0 and not settings.Settings.CombatLooting then
                Logger.Debug(LNS.guiLoot.console, 'lootMobs(): \arStopping\ax looting due to \ayAGGRO!')
                actors.FinishedLooting()
                return false
            end

            corpse.DoTarget()
            check                       = LNS.lootCorpse(corpseID)
            LNS.lootedCorpses[corpseID] = check
            mq.TLO.Window('LootWnd').DoClose()
            mq.delay(100, function() return not mq.TLO.Window('LootWnd').Open() end)

            ::continue::
            mq.delay(1)

            if allItems ~= nil and #allItems > 0 then
                actors.Send({
                    ID = corpseID,
                    Items = allItems,
                    Zone = LNS.Zone,
                    Instance = LNS.Instance,
                    Server = settings.EqServer,
                    LootedAt = mq.TLO.Time(),
                    CorpseName = corpse.DisplayName() or 'unknown',
                    LootedBy = settings.MyName,
                }, 'looted')
                allItems = nil
            end

            counter = check and counter + 1 or counter

            if counter >= limit then
                Logger.Debug(LNS.guiLoot.console, 'lootMobs(): Reached loot limit of \at%d\ax corpses.', limit)
                goto limit_reached
            end
        end

        ::limit_reached::
        didLoot = true
        -- Logger.Debug(loot.guiLoot.console, 'lootMobs(): Finished processing corpse list.')
    end

    actors.FinishedLooting()

    return didLoot
end

function LNS.itemGone(itemName, corpseID)
    if LNS.MasterLootList ~= nil then
        if LNS.MasterLootList[corpseID] ~= nil then
            LNS.MasterLootList[corpseID].Items[itemName] = nil
            if LNS.GetTableSize(LNS.MasterLootList[corpseID].Items) == 0 then
                LNS.MasterLootList[corpseID] = nil
            end
        end

        -- if you were told to loot this and its gone remove it from your list of items to loot so we don't get stuck in a loop
        for idx, data in ipairs(settings.TempSettings.ItemsToLoot or {}) do
            if data.corpseID == corpseID and data.itemName == itemName then
                Logger.Debug(LNS.guiLoot.console, 'corpseGone(): Removing item %s from ItemsToLoot for corpse ID %d', data.ItemName, corpseID)
                settings.TempSettings.ItemsToLoot[idx] = nil
            end
        end

        if LNS.MasterLootList and LNS.GetTableSize(LNS.MasterLootList or {}) == 0 then
            LNS.MasterLootList = nil
        end
    end
end

function LNS.corpseGone(corpseID)
    if corpseID == nil or corpseID <= 0 then
        Logger.Warn(LNS.guiLoot.console, 'corpseGone(): Invalid corpse ID: %s', tostring(corpseID))
        return
    end
    if LNS.MasterLootList ~= nil then
        LNS.MasterLootList[corpseID] = nil

        for idx, data in ipairs(settings.TempSettings.ItemsToLoot or {}) do
            if data.corpseID == corpseID then
                Logger.Debug(LNS.guiLoot.console, 'corpseGone(): Removing item %s from ItemsToLoot for corpse ID %d', data.ItemName, corpseID)
                settings.TempSettings.ItemsToLoot[idx] = nil
            end
        end

        Logger.Info(LNS.guiLoot.console, 'corpseGone(): Removed corpse ID %d from MasterLootList.', corpseID)
        if LNS.MasterLootList and LNS.GetTableSize(LNS.MasterLootList or {}) == 0 then
            LNS.MasterLootList = nil
        end
    end
end

function LNS.LootItemML(itemName, corpseID)
    local startCount = mq.TLO.FindItemCount(string.format("=%s", itemName))()
    local checkMore = false

    Logger.Info(LNS.guiLoot.console, 'Looting item: %s from corpse ID: %s MyCount: %s', itemName, corpseID, startCount)
    if not mq.TLO.Spawn(corpseID)() then
        Logger.Warn(LNS.guiLoot.console, 'LootItemML(): Corpse ID %d does not exist.', corpseID)
        LNS.corpseGone(corpseID)
        actors.Send({ who = settings.MyName, action = 'corpse_gone', Server = settings.EqServer, CorpseID = corpseID, })
        return false
    end
    LNS.navToID(corpseID)
    mq.TLO.Spawn(corpseID).DoTarget()
    mq.delay(1000, function() return mq.TLO.Target.ID() == corpseID end)
    mq.cmdf('/loot')
    mq.delay(4000, function() return mq.TLO.Window('LootWnd').Open() end)
    local corpseName = mq.TLO.Corpse.CleanName() or 'none'
    local itemCount = mq.TLO.Corpse.Items() or 0
    for i = 1, itemCount do
        local item = mq.TLO.Corpse.Item(i)
        if item() and item.Name() == itemName then
            Logger.Debug(LNS.guiLoot.console, 'Looting item: %s from corpse ID: %d', itemName, corpseID)
            LNS.lootItem(nil, i, 'Keep', 'leftmouseup', 0, not false)
            mq.delay(4000, function() return mq.TLO.FindItemCount(string.format("=%s", itemName))() > startCount end)
            LNS.checkCursor()
            if mq.TLO.FindItemCount(string.format("=%s", itemName))() == startCount then
                return false
            end
            checkMore = mq.TLO.Corpse.Item(string.format("=%s", itemName))() ~= nil or false
            -- actors.Send({
            --     ID = corpseID,
            --     Items = {
            --         Name = itemName,
            --         CorpseName = corpseName,
            --         Action = 'Keep',
            --         Link = item.ItemLink('CLICKABLE')(),
            --         Eval = 'Keep',
            --         cantWear = not item.CanUse(),
            --     },
            --     Zone = LNS.Zone,
            --     Server = settings.EqServer,S
            --     LootedAt = mq.TLO.Time(),
            --     CorpseName = corpseName,
            --     LootedBy = settings.MyName,
            -- }, 'looted')

            break
        end
    end
    if allItems ~= nil and #allItems > 0 then
        actors.Send({
            ID = corpseID,
            Items = allItems,
            Zone = LNS.Zone,
            Instance = LNS.Instance,
            Server = settings.EqServer,
            LootedAt = mq.TLO.Time(),
            CorpseName = mq.TLO.Corpse.DisplayName() or 'unknown',
            LootedBy = settings.MyName,
        }, 'looted')
        allItems = nil
    end

    checkMore = mq.TLO.Corpse.Item(string.format("=%s", itemName))() ~= nil or false

    if not checkMore then
        actors.Send({ action = 'item_gone', item = itemName, CorpseID = corpseID, Server = settings.EqServer, })
    end
    mq.TLO.Window('LootWnd').DoClose()
    mq.delay(1000, function() return not mq.TLO.Window('LootWnd').Open() end)
    if not mq.TLO.Spawn(corpseID)() then
        actors.Send({ action = 'corpse_gone', CorpseID = corpseID, Server = settings.EqServer, })
    end

    return mq.TLO.FindItemCount(string.format("=%s", itemName))() > startCount
end

------------------------------------
--      PROCESSING ITEMS
------------------------------------

-- SELLING


function LNS.eventSell(_, itemName)
    if ProcessItemsState ~= nil then return end
    -- Resolve the item ID from the given name
    local itemID = LNS.resolveItemIDbyName(itemName, true, true)

    if not itemID then
        Logger.Warn(LNS.guiLoot.console, "Unable to resolve item ID for: " .. itemName)
        return
    end

    if settings.Settings.AddNewSales then
        -- Add a rule to mark the item as "Sell"
        LNS.addRule(itemID, "NormalItems", "Sell", "All", 'NULL')
        Logger.Info(LNS.guiLoot.console, "Added rule: \ay%s\ax set to \agSell\ax.", itemName)
    end
end

function LNS.goToVendor()
    if not mq.TLO.Target() then
        Logger.Warn(LNS.guiLoot.console, 'Please target a vendor')
        return false
    end
    local vendorID = mq.TLO.Target.ID()
    if mq.TLO.Target.Distance() > 15 then
        LNS.navToID(vendorID)
    end
    return true
end

function LNS.openVendor()
    Logger.Debug(LNS.guiLoot.console, 'Opening merchant window')
    mq.TLO.Target.RightClick()
    mq.delay(5000, function() return mq.TLO.Window('MerchantWnd').Open() end)
    mq.delay(500) -- give the item list time to populate

    return mq.TLO.Window('MerchantWnd').Open()
end

function LNS.SellToVendor(itemID, bag, slot, name)
    local itemName = LNS.ItemNames[itemID] ~= nil and LNS.ItemNames[itemID] or 'Unknown'
    if itemName == 'Unknown' and name ~= nil then itemName = name end
    if NEVER_SELL[itemName] then return end
    if mq.TLO.Window('MerchantWnd').Open() then
        Logger.Info(LNS.guiLoot.console, 'Selling item: %s', itemName)
        local notify = slot == (nil or -1)
            and ('/itemnotify %s leftmouseup'):format(bag)
            or ('/itemnotify in pack%s %s leftmouseup'):format(bag, slot)
        mq.cmdf(notify)
        mq.delay(1000,
            function() return mq.TLO.Window("MerchantWnd/MW_Sell_Button").Enabled() and ((mq.TLO.Window("MerchantWnd/MW_SelectedItemLabel").Text() or "") == itemName) end)
        if mq.TLO.Window("MerchantWnd/MW_Sell_Button").Enabled() and mq.TLO.Window("MerchantWnd/MW_SelectedPriceLabel").Text() ~= "0c" then
            mq.cmdf('/nomodkey /shiftkey /notify merchantwnd MW_Sell_Button leftmouseup')
            mq.delay(5000, function() return (mq.TLO.Window("MerchantWnd/MW_SelectedItemLabel").Text() ~= itemName) end)
        end
    end
end

-- BANKING
function LNS.openBanker()
    Logger.Debug(LNS.guiLoot.console, 'Opening bank window')
    mq.cmdf('/nomodkey /click right target')
    mq.delay(1000, function() return mq.TLO.Window('BigBankWnd').Open() end)
    return mq.TLO.Window('BigBankWnd').Open()
end

function LNS.bankItem(itemID, bag, slot)
    local notify = slot == nil or slot == -1
        and ('/shift /itemnotify %s leftmouseup'):format(bag)
        or ('/shift /itemnotify in pack%s %s leftmouseup'):format(bag, slot)
    mq.cmdf(notify)
    mq.delay(10000, function() return mq.TLO.Cursor() ~= nil end)
    mq.cmdf('/notify BigBankWnd BIGB_AutoButton leftmouseup')
    mq.delay(1000, function() return not mq.TLO.Cursor() end)
    if mq.TLO.Cursor() ~= nil then
        mq.cmd("/autoinventory")
        Logger.Warn(LNS.guiLoot.console, "Banking \ayNO Free Slot \axInventorying and trying next item...")
    end
end

function LNS.markTradeSkillAsBank()
    for i = 1, 10 do
        local bagSlot = mq.TLO.InvSlot('pack' .. i).Item
        if bagSlot.ID() and bagSlot.Tradeskills() then
            LNS.NormalItemsRules[bagSlot.ID()] = 'Bank'
            LNS.addRule(bagSlot.ID(), 'NormalItems', 'Bank', 'All', bagSlot.ItemLink('CLICKABLE')())
        end
    end
end

-- BUYING

function LNS.RestockItems()
    for itemName, qty in pairs(LNS.BuyItemsTable) do
        local rowNum = -1
        ::try_again::
        Logger.Info(LNS.guiLoot.console, 'Checking \ao%s \axfor \at%s \axto \agRestock', mq.TLO.Target.CleanName(), itemName)
        mq.delay(500, function() return mq.TLO.Window("MerchantWnd/MW_ItemList").List(string.format("=%s", itemName), 2)() ~= nil end)
        rowNum = mq.TLO.Window("MerchantWnd/MW_ItemList").List(string.format("=%s", itemName), 2)() or -1
        mq.delay(1)
        if rowNum <= 0 then
            Logger.Warn(LNS.guiLoot.console, "\arItem \ax%s \arnot found in vendor list\ax, skipping...", itemName)
            goto next_item
        end
        local onHand = mq.TLO.FindItemCount(itemName)()
        local tmpQty = (qty - onHand > 0) and qty - onHand or 0
        Logger.Debug(LNS.guiLoot.console, "\agHave\ax: \at%s\ax \aoNeed\ax: \ay%s \ax\ayROW\ax: \at%s", onHand, tmpQty, rowNum)
        if tmpQty > 0 then
            ::need_more::
            mq.TLO.Window("MerchantWnd/MW_ItemList").Select(rowNum)()
            Logger.Debug(LNS.guiLoot.console, "\ayRestocking \ax%s \aoHave\ax: \at%s\ax \agBuying\ax: \ay%s", itemName, onHand, tmpQty)
            mq.delay(3000, function() return mq.TLO.Window('MerchantWnd/MW_SelectedItemLabel').Text():lower() == itemName:lower() end)
            if mq.TLO.Window('MerchantWnd/MW_SelectedItemLabel').Text():lower() ~= itemName:lower() then
                Logger.Warn(LNS.guiLoot.console, "\arFailed\ax to select item: \ay%s\ax, retrying...", itemName)
                if settings.TempSettings.RestockAttempts == nil then
                    settings.TempSettings.RestockAttempts = 0
                end
                if settings.TempSettings.RestockAttempts >= 5 then
                    Logger.Warn(LNS.guiLoot.console, "\arFailed to select item\ax: \ay%s\ax after 5 attempts, skipping...", itemName)
                    settings.TempSettings.RestockAttempts = 0
                    goto next_item
                end
                settings.TempSettings.RestockAttempts = settings.TempSettings.RestockAttempts + 1
                goto try_again
            end
            mq.TLO.Window("MerchantWnd/MW_Buy_Button").LeftMouseUp()
            mq.delay(1)
            mq.delay(2000, function() return mq.TLO.Window("QuantityWnd").Open() or mq.TLO.FindItemCount(itemName)() > onHand end)
            if mq.TLO.Window("QuantityWnd").Open() then
                mq.TLO.Window("QuantityWnd/QTYW_SliderInput").SetText(tostring(tmpQty))()
                mq.delay(200, function() return mq.TLO.Window("QuantityWnd/QTYW_SliderInput").Text() == tostring(tmpQty) end)
                Logger.Info(LNS.guiLoot.console, "\agBuying\ay " .. mq.TLO.Window("QuantityWnd/QTYW_SliderInput").Text() .. "\at " .. itemName)
                mq.TLO.Window("QuantityWnd/QTYW_Accept_Button").LeftMouseUp()
                mq.delay(2000, function() return not mq.TLO.Window("QuantityWnd").Open() end)
            end
            mq.delay(2000, function() return (onHand < mq.TLO.FindItemCount(itemName)()) end) -- delay before checking counts so things can update or we get into a loop of rebuying the same item
            onHand = mq.TLO.FindItemCount(itemName)()
            mq.delay(1)

            if onHand < qty then
                Logger.Info(LNS.guiLoot.console, "\ayStack Max Size \axis \arLess\ax than \ax%s \aoHave\ax: \at%s\ax", qty, onHand)
                tmpQty = (qty - onHand > 0) and qty - onHand or 0
                mq.delay(10)
                goto need_more
            end
        end
        mq.delay(500, function() return mq.TLO.FindItemCount(itemName)() >= qty end)
        ::next_item::
    end
    settings.TempSettings.RestockAttempts = 0
    Logger.Info(LNS.guiLoot.console, '\ayRestock \agComplete.')
    -- close window when done buying
    return mq.TLO.Window('MerchantWnd').DoClose()
end

-- TRIBUTEING

function LNS.openTribMaster()
    Logger.Debug(LNS.guiLoot.console, 'Opening Tribute Window')
    mq.cmdf('/nomodkey /click right target')
    Logger.Debug(LNS.guiLoot.console, 'Waiting for Tribute Window to populate')
    mq.delay(1000, function() return mq.TLO.Window('TributeMasterWnd').Open() end)
    if not mq.TLO.Window('TributeMasterWnd').Open() then return false end
    return mq.TLO.Window('TributeMasterWnd').Open()
end

function LNS.eventTribute(_, itemName)
    if ProcessItemsState ~= nil then return end

    -- Resolve the item ID from the given name
    local itemID = LNS.resolveItemIDbyName(itemName, false, true)

    if not itemID then
        Logger.Warn(LNS.guiLoot.console, "Unable to resolve item ID for: " .. itemName)
        return
    end

    local link = 'NULL'

    if LNS.ALLITEMS[itemID] then
        link = LNS.ALLITEMS[itemID].Link
    end
    if settings.Settings.AddNewTributes then
        -- Add a rule to mark the item as "Tribute"
        LNS.addRule(itemID, "NormalItems", "Tribute", "All", link)
        Logger.Info(LNS.guiLoot.console, "Added rule: \ay%s\ax set to \agTribute\ax.", itemName)
    end
end

function LNS.TributeToVendor(itemToTrib, bag, slot)
    if NEVER_SELL[itemToTrib.Name()] then return end
    if mq.TLO.Window('TributeMasterWnd').Open() then
        Logger.Info(LNS.guiLoot.console, 'Tributeing ' .. itemToTrib.Name())
        LNS.report('\ayTributing \at%s \axfor\ag %s \axpoints!', itemToTrib.Name(), itemToTrib.Tribute())
        mq.cmdf('/shift /itemnotify in pack%s %s leftmouseup', bag, slot)
        mq.delay(1) -- progress frame

        mq.delay(5000, function()
            return mq.TLO.Window('TributeMasterWnd').Child('TMW_ValueLabel').Text() == tostring(itemToTrib.Tribute()) and
                mq.TLO.Window('TributeMasterWnd').Child('TMW_DonateButton').Enabled()
        end)

        mq.TLO.Window('TributeMasterWnd/TMW_DonateButton').LeftMouseUp()
        mq.delay(1)
        mq.delay(5000, function() return not mq.TLO.Window('TributeMasterWnd/TMW_DonateButton').Enabled() end)
        if mq.TLO.Window("QuantityWnd").Open() then
            mq.TLO.Window("QuantityWnd/QTYW_Accept_Button").LeftMouseUp()
            mq.delay(5000, function() return not mq.TLO.Window("QuantityWnd").Open() end)
        end
        mq.delay(1000) -- This delay is necessary because there is seemingly a delay between donating and selecting the next item.
    end
end

-- CLEANUP

function LNS.DestroyItem(itemToDestroy, bag, slot)
    if itemToDestroy == nil then return end
    if NEVER_SELL[itemToDestroy.Name()] then return end
    Logger.Info(LNS.guiLoot.console, '!!Destroying!! ' .. itemToDestroy.Name())
    -- Logger.Info(loot.guiLoot.console, "Bag: %s, Slot: %s", bag, slot)
    mq.cmdf('/shift /itemnotify in pack%s %s leftmouseup', bag, slot)
    mq.delay(10000, function() return mq.TLO.Cursor.Name() == itemToDestroy.Name() end) -- progress frame
    mq.cmdf('/destroy')
    mq.delay(1)
    mq.delay(1000, function() return not mq.TLO.Cursor() end)
    mq.delay(1)
end

-- FORAGING

function LNS.eventForage()
    if foragingLoot then return end
    foragingLoot = true
    if not settings.Settings.LootForage then return end
    Logger.Debug(LNS.guiLoot.console, 'Enter eventForage')
    -- allow time for item to be on cursor incase message is faster or something?
    mq.delay(1000, function() return mq.TLO.Cursor() ~= nil end)
    -- there may be more than one item on cursor so go until its cleared
    local loopStatus = true
    while loopStatus do
        local cursorItem  = mq.TLO.Cursor
        local foragedItem = cursorItem.Name() or 'unknown_item'
        local cursorID    = cursorItem.ID() or 0
        mq.delay(10)
        local ruleAction, ruleAmount = LNS.getRule(cursorItem, 'forage', 0)
        --LNS.lookupLootRule(itemID,)
        local currentItemAmount      = mq.TLO.FindItemCount('=' .. foragedItem)()
        -- >= because .. does finditemcount not count the item on the cursor?
        if mq.TLO.Cursor() and (not shouldLootActions[ruleAction] or (ruleAction == 'Quest' and currentItemAmount >= ruleAmount)) then
            if mq.TLO.Cursor.Name() == foragedItem then
                if settings.Settings.LootForageSpam then Logger.Info(LNS.guiLoot.console, 'Destroying foraged item \ao%s', foragedItem) end
                mq.cmdf('/destroy')
                mq.delay(2000, function() return (mq.TLO.Cursor.ID() or -1) ~= cursorID end)
            end
            -- will a lore item we already have even show up on cursor?
            -- free inventory check won't cover an item too big for any container so may need some extra check related to that?
        elseif (shouldLootActions[ruleAction]) and cursorItem() and
            (not cursorItem.Lore() or (cursorItem.Lore() and currentItemAmount == 0)) and
            (mq.TLO.Me.FreeInventory() > settings.Settings.SaveBagSlots) or (cursorItem.Stackable() and cursorItem.FreeStack()) then
            if settings.Settings.LootForageSpam then Logger.Info(LNS.guiLoot.console, 'Keeping foraged item \at%s', foragedItem) end
            mq.cmdf('/autoinv')
            mq.delay(2000, function() return (mq.TLO.Cursor.ID() or -1) ~= cursorID end)
        else
            if settings.Settings.LootForageSpam then Logger.Warn(LNS.guiLoot.console, 'Unable to process item \ao%s', foragedItem) end
            break
        end
        if not mq.TLO.Cursor() then loopStatus = false end
    end
    foragingLoot = false
end

-- Process Items

function LNS.processItems(action)
    local flag        = false
    local totalPlat   = 0
    ProcessItemsState = action
    local myCoins     = mq.TLO.Me.Cash()
    local soldVal     = 0
    local spentVal    = 0
    actors.InformProcessing()
    -- Helper function to process individual items based on action
    local function processItem(item, todo, bag, slot)
        if not item or not item.ID() then return end
        local itemID     = item.ID()
        local tradeskill = item.Tradeskills()
        local rule       = LNS.NormalItemsRules[itemID] or "Ignore"
        if LNS.PersonalItemsRules[itemID] then
            rule = LNS.PersonalItemsRules[itemID]
        elseif LNS.GlobalItemsRules[itemID] then
            rule = LNS.GlobalItemsRules[itemID]
        elseif tradeskill and todo == 'Bank' then
            rule = (tradeskill and settings.Settings.BankTradeskills) and 'Bank' or rule
        end
        if rule == todo then
            if todo == 'Sell' then
                if not mq.TLO.Window('MerchantWnd').Open() then
                    if not LNS.goToVendor() or not LNS.openVendor() then return end
                end
                -- local sellPrice = item.Value() and item.Value() / 1000 or 0
                -- local stackSize = item.StackSize() or 0
                -- local haveAmt = mq.TLO.FindItemCount(item.Name())()

                -- if stackSize > 1 and haveAmt > 1 then
                --     if haveAmt > stackSize then
                --         sellPrice = sellPrice * stackSize
                --     else
                --         sellPrice = sellPrice * haveAmt
                --     end
                -- end

                LNS.SellToVendor(itemID, bag, slot, item.Name())

                -- totalPlat = totalPlat + sellPrice
                mq.delay(1)
            elseif todo == 'Tribute' then
                if not mq.TLO.Window('TributeMasterWnd').Open() then
                    if not LNS.goToVendor() or not LNS.openTribMaster() then return end
                end
                mq.cmdf('/keypress OPEN_INV_BAGS')
                mq.delay(1000, LNS.AreBagsOpen)
                LNS.TributeToVendor(item, bag, slot)
            elseif todo == ('Destroy' or 'Cleanup') then
                LNS.DestroyItem(item, bag, slot)
            elseif todo == 'Bank' then
                if not mq.TLO.Window('BigBankWnd').Open() then
                    if not LNS.goToVendor() or not LNS.openBanker() then return end
                end
                LNS.bankItem(item.Name(), bag, slot)
            end
        end
    end

    -- Temporarily disable AlwaysEval during processing
    if settings.Settings.AlwaysEval then
        flag, settings.Settings.AlwaysEval = true, false
    end

    -- Iterate through bags and process items

    for i = 1, 10 do
        if i == settings.Settings.IgnoreBagSlot then
            Logger.Debug(LNS.guiLoot.console, 'Bag Slot \at%s\ao is set to be ignored, \ax\aySkipping\ax %s.', i, mq.TLO.Me.Inventory('pack' .. i).Name())
            goto next_bag
        end
        local bagSlot       = mq.TLO.InvSlot('pack' .. i).Item
        local containerSize = bagSlot.Container()

        if containerSize then
            for j = 1, containerSize do
                local item = bagSlot.Item(j)
                if item and item.ID() then
                    processItem(item, action, i, j)
                end
            end
        else
            Logger.Warn(LNS.guiLoot.console, 'Item is \arNOT\ax in a Bag! \ayPlease place items inside of Bags!', i)
        end
        ::next_bag::
    end
    if action == 'Sell' then
        soldVal = (mq.TLO.Me.Cash() - myCoins) / 1000
    end
    -- Handle restocking if AutoRestock is enabled
    if action == 'Sell' and settings.Settings.AutoRestock then
        local tmp = mq.TLO.Me.Cash()
        LNS.RestockItems()
        spentVal = (mq.TLO.Me.Cash() - tmp) / 1000
    end

    -- Handle buying items
    if action == 'Buy' then
        if not mq.TLO.Window('MerchantWnd').Open() then
            if not LNS.goToVendor() or not LNS.openVendor() then return end
        end
        LNS.RestockItems()
        spentVal = (mq.TLO.Me.Cash() - myCoins) / 1000
    end

    -- Restore AlwaysEval state if it was modified
    if flag then
        flag, settings.Settings.AlwaysEval = false, true
    end

    -- Handle specific post-action tasks
    if action == 'Tribute' then
        mq.flushevents('Tribute')
        if mq.TLO.Window('TributeMasterWnd').Open() then
            mq.TLO.Window('TributeMasterWnd').DoClose()
        end
        mq.cmdf('/keypress CLOSE_INV_BAGS')
    elseif action == 'Sell' then
        if mq.TLO.Window('MerchantWnd').Open() then
            mq.TLO.Window('MerchantWnd').DoClose()
        end
        -- totalPlat = math.floor(totalPlat)
        totalPlat = (mq.TLO.Me.Cash() - myCoins) / 1000
        LNS.report('Plat Spent: \ao%0.3f\ax, Gained: \ag%0.3f\ax, \awTotal Profit\ax: \ag%0.3f', spentVal, soldVal, totalPlat)
        Logger.Info(LNS.guiLoot.console, 'Plat Spent: \ay%0.3f\ax, Gained: \ag%0.3f\ax, \awTotal Profit\ax: \ag%0.3f', spentVal, soldVal, totalPlat)
    elseif action == 'Bank' then
        if mq.TLO.Window('BigBankWnd').Open() then
            mq.TLO.Window('BigBankWnd').DoClose()
        end
    end

    -- Final check for bag status

    LNS.CheckBags()
    ProcessItemsState = nil
    actors.DoneProcessing()
end

function LNS.sellStuff()
    LNS.processItems('Sell')
end

function LNS.bankStuff()
    LNS.processItems('Bank')
end

function LNS.cleanupBags()
    LNS.processItems('Destroy')
end

function LNS.tributeStuff()
    LNS.processItems('Tribute')
end

------------------------------------
--         MAIN INIT AND LOOP
------------------------------------

function LNS.processArgs(args)
    LNS.Terminate = true
    if args == nil then return end
    if args[1] == 'directed' and args[2] ~= nil then
        if LNS.guiLoot ~= nil then
            LNS.guiLoot.GetSettings(settings.Settings.HideNames,
                settings.Settings.RecordData,
                true,
                settings.Settings.UseActors,
                'lootnscoot',
                settings.Settings.ShowReport,
                settings.Settings.ReportSkippedItems)
        end
        LNS.DirectorScript = args[2]
        if args[3] ~= nil then
            LNS.DirectorLNSPath = args[3]
        end
        LNS.Mode = 'directed'
        LNS.Terminate = false
        actors.Send({ action = 'Hello', Server = settings.EqServer, who = settings.MyName, })
    elseif args[1] == 'sellstuff' then
        LNS.processItems('Sell')
    elseif args[1] == 'restock' then
        LNS.processItems('Buy')
    elseif args[1] == 'bankstuff' then
        LNS.processItems('Bank')
    elseif args[1] == 'tributestuff' then
        LNS.processItems('Tribute')
    elseif args[1] == 'cleanup' then
        settings.TempSettings.NeedsCleanup = true
        -- LNS.processItems('Destroy')
    elseif args[1] == 'once' then
        LNS.lootMobs(settings.Settings.MaxCorpsesPerCycle)
    elseif args[1] == 'standalone' then
        if LNS.guiLoot ~= nil then
            LNS.guiLoot.GetSettings(settings.Settings.HideNames,

                settings.Settings.RecordData,
                true,
                settings.Settings.UseActors,
                'lootnscoot',
                settings.Settings.ShowReport,
                settings.Settings.ReportSkippedItems)
        end
        LNS.Mode = 'standalone'
        LNS.Terminate = false
        actors.Send({ action = 'Hello', Server = settings.EqServer, who = settings.MyName, })
    end
end

----------------- DEBUG ACTORS -------------------

settings.TempSettings.MailBox = nil
settings.TempSettings.ShowMailbox = false

---------------- Main Function and Init -----------
function LNS.init(args)
    local needsSave = false
    if LNS.Mode ~= 'once' then
        LNS.Terminate = false
    end
    db.SetLNS(LNS)
    needsSave = LNS.loadSettings(true)
    db.PrepareStatements()
    mq.cmdf("/squelch /mapfilter CastRadius %d", settings.Settings.CorpseRadius)
    LNS.SortSettings()
    LNS.SortTables()
    actors.SetLNS(LNS)
    actors.RegisterActors()
    LNS.CheckBags()
    LNS.setupEvents()
    LNS.setupBinds()
    zoneID = mq.TLO.Zone.ID()
    Logger.Debug(LNS.guiLoot.console, "Loot::init() \aoSaveRequired: \at%s", needsSave and "TRUE" or "FALSE")
    LNS.processArgs(args)
    actors.SendMySettings()
    mq.imgui.init('LootnScoot', ui.RenderUIs)
    LNS.guiLoot.GetSettings(settings.Settings.HideNames,

        settings.Settings.RecordData,
        true,
        LNS.UseActors,
        'lootnscoot',
        settings.Settings.ShowReport,
        settings.Settings.ReportSkippedItems)

    if needsSave then LNS.writeSettings("Init()") end
    if LNS.Mode == 'directed' then
        -- send them our combat setting
        actors.Send({
            Subject = 'settings',
            Who = settings.MyName,
            CombatLooting = settings.Settings.CombatLooting,
            CorpseRadius = settings.Settings.CorpseRadius,
            LootMyCorpse = settings.Settings.LootMyCorpse,
            IgnoreNearby = settings.Settings.IgnoreMyNearCorpses,
            CorpsesToIgnore = LNS.lootedCorpses or {},
            Server = settings.EqServer,
            LNSSettings = settings.Settings,
        }, 'loot_module')
    end
    return needsSave
end

ui.SetLNS(LNS)
if LNS.guiLoot ~= nil then
    LNS.guiLoot.GetSettings(settings.Settings.HideNames,

        settings.Settings.RecordData,
        true,
        settings.Settings.UseActors,
        'lootnscoot',
        settings.Settings.ShowReport,
        settings.Settings.ReportSkippedItems
    )
    LNS.guiLoot.init(true, true, 'lootnscoot')
    ui.guiExport()
end
function LNS.MainLoop()
    while not LNS.Terminate do
        -- local pcallSuccess, pcallResult = pcall(function()
        LNS.Zone = mq.TLO.Zone.ShortName()
        LNS.Instance = mq.TLO.Me.Instance()
        if mq.TLO.MacroQuest.GameState() ~= "INGAME" then
            -- exit sctipt if at char select.
            printf('LootNScoot Terminate = true due to GameState != INGAME (%s).', mq.TLO.MacroQuest.GameState())
            mq.cmdf('/dg /pop 5 [%s] LootNScoot exiting due to GameState != INGAME (%s).', mq.TLO.Me.CleanName(), mq.TLO.MacroQuest.GameState())
            LNS.Terminate = true
        end
        -- LNS.guiLoot.ReportLeft = settings.Settings.ReportSkippedItems
        LNS.guiLoot.GetSettings(settings.Settings.HideNames,
            settings.Settings.RecordData,
            true, true, 'lootnscoot',
            LNS.guiLoot.showReport, LNS.guiLoot.ReportSkippedItems)

        -- check if the director script is running.
        local directorRunning = mq.TLO.Lua.Script(LNS.DirectorScript).Status() == 'RUNNING' or false
        if not directorRunning and LNS.Mode == 'directed' then
            printf('LootNScoot Terminate = true due to director not running (%s).', directorRunning)
            -- mq.cmdf('/dg /pop 5 [%s] LootNScoot exiting due to director not running (%s).', mq.TLO.Me.CleanName(), directorRunning)
            LNS.Terminate = true
        end

        if settings.TempSettings.LastZone ~= LNS.Zone or settings.TempSettings.LastInstance ~= LNS.Instance then
            mq.delay(5000, function() return not mq.TLO.Me.Zoning() end) -- wait for zoning to finish.
            settings.TempSettings.ItemsToLoot = {}
            LNS.lootedCorpses = {}

            if LNS.Mode == 'directed' then
                -- send them our combat setting
                actors.Send({
                    Subject = 'settings',
                    Who = settings.MyName,
                    CombatLooting = settings.Settings.CombatLooting,
                    CorpseRadius = settings.Settings.CorpseRadius,
                    LootMyCorpse = settings.Settings.LootMyCorpse,
                    IgnoreNearby = settings.Settings.IgnoreMyNearCorpses,
                    CorpsesToIgnore = LNS.lootedCorpses or {},
                    Server = settings.EqServer,
                    LNSSettings = settings.Settings,
                }, 'loot_module')
            end
            settings.TempSettings.LastZone = LNS.Zone
            settings.TempSettings.LastInstance = LNS.Instance
            LNS.MasterLootList = nil
            settings.TempSettings.SafeZoneWarned = false
        end

        if LNS.debugPrint and LNS.guiLoot.MailBox ~= nil and LNS.GetTableSize(LNS.guiLoot.MailBox) > 0 then
            for _, v in ipairs(LNS.guiLoot.MailBox) do
                settings.TempSettings.MailBox = settings.TempSettings.MailBox or {}
                table.insert(settings.TempSettings.MailBox, v)
            end
            LNS.guiLoot.MailBox = {}
            table.sort(settings.TempSettings.MailBox, function(a, b)
                return a.Time < b.Time
            end)
        end

        if LNS.SafeZones[LNS.Zone] and not settings.TempSettings.SafeZoneWarned then
            Logger.Debug(LNS.guiLoot.console, "You are in a safe zone: \at%s\ax \ayLooting Disabled", LNS.Zone)
            settings.TempSettings.SafeZoneWarned = true
        end

        -- check if we need to import the old rules db.
        if settings.TempSettings.DoImport then
            Logger.Info(LNS.guiLoot.console, "Importing Old Rules DB:\n\at%s", settings.TempSettings.ImportDBFilePath)
            db.ImportOldRulesDB(settings.TempSettings.ImportDBFilePath)
            settings.TempSettings.DoImport = false
        end

        -- check if we need to remove safe zones.
        if settings.TempSettings.RemoveSafeZone ~= nil then
            for k, v in pairs(settings.TempSettings.RemoveSafeZone or {}) do
                if k ~= nil then LNS.RemoveSafeZone(k) end
            end
            settings.TempSettings.RemoveSafeZone = nil
        end

        if settings.TempSettings.RemoveMLItem then
            LNS.itemGone(settings.TempSettings.RemoveMLItemInfo.itemName, settings.TempSettings.RemoveMLItemInfo.corpseID)
            settings.TempSettings.RemoveMLItem = false
            settings.TempSettings.RemoveMLItemInfo = {}
        end

        if settings.TempSettings.RemoveMLCorpse then
            LNS.corpseGone(settings.TempSettings.RemoveMLCorpseInfo.corpseID)
            settings.TempSettings.RemoveMLCorpse = false
            settings.TempSettings.RemoveMLCorpseInfo = {}
        end

        if LNS.GetTableSize(settings.TempSettings.ItemsToLoot) > 0 and (not mq.TLO.Me.Combat() or settings.Settings.CombatLooting) then
            local lootedIdx = {}
            for idx, data in ipairs(settings.TempSettings.ItemsToLoot or {}) do
                if data ~= nil and data.corpseID ~= nil and data.itemName ~= nil then
                    Logger.Info(LNS.guiLoot.console, "Looting Item: \ag%s\ax from Corpse: \ag%s\ax",
                        data.itemName, data.corpseID)
                    if LNS.LootItemML(data.itemName, data.corpseID) then
                        lootedIdx[idx] = true
                    end
                end
            end
            -- remove looted items from the list
            for idx, _ in pairs(lootedIdx) do
                settings.TempSettings.ItemsToLoot[idx] = nil
            end
        end

        if settings.TempSettings.SendLoot then
            actors.Send(settings.TempSettings.SendLootInfo)
            settings.TempSettings.SendLoot = false
        end

        if settings.TempSettings.SendRemoveItem then
            actors.Send(settings.TempSettings.RemoveItemData)
            settings.TempSettings.SendRemoveItem = false
        end

        if settings.TempSettings.AddWildCard then
            if settings.TempSettings.NewWildCard ~= '' then
                db.AddWildCard(settings.TempSettings.NewWildCard, settings.TempSettings.NewWildCardRule)
                settings.TempSettings.NewWildCard = ''
                settings.TempSettings.NewWildCardRule = 'Ask'
            end
            settings.TempSettings.AddWildCard = false
        end

        if settings.TempSettings.DeleteWildCard then
            if settings.TempSettings.DeleteWildCardPattern ~= '' then
                db.DeleteWildCard(settings.TempSettings.DeleteWildCardPattern)
                settings.TempSettings.DeleteWildCardPattern = ''
            end
            settings.TempSettings.DeleteWildCard = false
        end

        if settings.TempSettings.NeedReloadWildCards then
            LNS.WildCards = db.LoadWildCardRules()
            settings.TempSettings.NeedReloadWildCards = false
        end
        -- check shared settings
        if settings.TempSettings.LastCombatSetting == nil then
            settings.TempSettings.LastCombatSetting = settings.Settings.CombatLooting
        end

        if settings.TempSettings.LastCorpseRadius == nil then
            settings.TempSettings.LastCorpseRadius = settings.Settings.CorpseRadius
        end

        if settings.TempSettings.LastLootMyCorpse == nil then
            settings.TempSettings.LastLootMyCorpse = settings.Settings.LootMyCorpse
        end

        if settings.TempSettings.LastIgnoreNearby == nil then
            settings.TempSettings.LastIgnoreNearby = settings.Settings.IgnoreMyNearCorpses
        end

        -- check if we need to send actors any settings
        if settings.TempSettings.NeedSave then
            if (settings.TempSettings.LastCombatSetting ~= settings.Settings.CombatLooting) or
                (settings.TempSettings.LastCorpseRadius ~= settings.Settings.CorpseRadius) or
                (settings.TempSettings.LastLootMyCorpse ~= settings.Settings.LootMyCorpse) or
                (settings.TempSettings.LastIgnoreNearby ~= settings.Settings.IgnoreMyNearCorpses) then
                settings.TempSettings.LastCombatSetting = settings.Settings.CombatLooting
                settings.TempSettings.LastCorpseRadius = settings.Settings.CorpseRadius
                settings.TempSettings.LastLootMyCorpse = settings.Settings.LootMyCorpse
                settings.TempSettings.LastIgnoreNearby = settings.Settings.IgnoreMyNearCorpses
                actors.Send({
                    Subject = 'combatsetting',
                    Who = settings.MyName,
                    CombatLooting = settings.Settings.CombatLooting,
                    CorpseRadius = settings.Settings.CorpseRadius,
                    LootMyCorpse = settings.Settings.LootMyCorpse,
                    IgnoreNearby = settings.Settings.IgnoreMyNearCorpses,
                    CorpsesToIgnore = LNS.lootedCorpses or {},
                    LNSSettings = settings.Settings,
                    Server = settings.EqServer,
                }, 'loot_module')
            end
        end

        if LNS.debugPrint then
            Logger.loglevel = 'debug'
        elseif not settings.Settings.ShowInfoMessages then
            Logger.loglevel = 'warn'
        else
            Logger.loglevel = 'info'
        end

        local checkDif = os.clock() - (settings.TempSettings.LastCheck or 0)

        -- check if we need to loot mobs
        if (settings.Settings.DoLoot or settings.Settings.LootMyCorpse) and LNS.Mode ~= 'directed' then
            if checkDif > settings.Settings.LootCheckDelay then
                LNS.lootMobs(settings.Settings.MaxCorpsesPerCycle or 1)
            else
                -- Logger.Debug(LNS.guiLoot.console, "\atToo Soon\ax CheckDelay: \ag%s\ax seconds, LastCheck: \ag%0.2f\ax seconds ago",
                -- settings.Settings.LootCheckDelay, checkDif)
            end
        elseif LNS.LootNow and LNS.Mode == 'directed' then
            if checkDif > settings.Settings.LootCheckDelay then
                LNS.lootMobs(settings.TempSettings.LootLimit or settings.Settings.MaxCorpsesPerCycle)
            else
                -- Logger.Debug(LNS.guiLoot.console, "\atToo Soon\ax CheckDelay: \ag%s\ax seconds, LastCheck: \ag%0.2f\ax seconds ago",
                -- settings.Settings.LootCheckDelay, checkDif)
                actors.FinishedLooting()
            end
        end

        if doSell then
            LNS.processItems('Sell')
            doSell = false
        end

        if doBuy then
            LNS.processItems('Buy')
            doBuy = false
        end

        if doTribute then
            LNS.processItems('Tribute')
            doTribute = false
        end

        if settings.TempSettings.doBulkSet then
            local doDelete = settings.TempSettings.bulkDelete
            db.BulkSet(settings.TempSettings.BulkSet, settings.TempSettings.BulkRule,
                settings.TempSettings.BulkClasses, settings.TempSettings.BulkSetTable, doDelete)
            settings.TempSettings.doBulkSet = false
            settings.TempSettings.bulkDelete = false
            settings.TempSettings.SelectedItems = {}
        end

        if LNS.guiLoot ~= nil then
            if LNS.guiLoot.SendHistory then
                LNS.HistoricalDates = db.LoadHistoricalData()
                LNS.guiLoot.SendHistory = false
            end
            if LNS.guiLoot.showReport ~= settings.Settings.ShowReport then
                settings.Settings.ShowReport = LNS.guiLoot.showReport
                settings.TempSettings.NeedSave = true
            end
            if LNS.guiLoot.openGUI ~= settings.Settings.ShowConsole then
                settings.Settings.ShowConsole = LNS.guiLoot.openGUI
                settings.TempSettings.NeedSave = true
            end
            settings.TempSettings.SessionHistory = LNS.guiLoot.SessionLootRecord or {}
        end

        mq.doevents()

        if settings.TempSettings.UpdateSettings then
            Logger.Info(LNS.guiLoot.console, "Updating Settings")
            mq.pickle(SettingsFile, settings.Settings)
            LNS.loadSettings()
            settings.TempSettings.UpdateSettings = false
        end

        if settings.TempSettings.SendSettings then
            settings.TempSettings.SendSettings = false
            if os.difftime(os.time(), settings.TempSettings.LastSent or 0) > 10 then
                Logger.Debug(LNS.guiLoot.console, "Sending Settings")
                actors.SendMySettings()
            end
        end

        -- if settings.TempSettings.WriteSettings then
        --     LNS.writeSettings()
        --     LNS.SortTables()
        --     settings.TempSettings.WriteSettings = false
        -- end

        if settings.TempSettings.ClearDateData then
            settings.TempSettings.ClearDateData = false
            LNS.HistoryDataDate = {}
            LNS.HistoryItemData = {}
        end

        if settings.TempSettings.LookUpDateData then
            settings.TempSettings.LookUpDateData = false
            LNS.HistoryDataDate = db.LoadDateHistory(LNS.lookupDate)
            LNS.HistoryItemData = {}
        end

        if settings.TempSettings.FindItemHistory then
            settings.TempSettings.FindItemHistory = false
            if settings.TempSettings.FilterHistory ~= nil and settings.TempSettings.FilterHistory ~= "" then
                LNS.HistoryItemData = db.LoadItemHistory(settings.TempSettings.FilterHistory)
                LNS.HistoryDataDate = {}
                settings.TempSettings.FilterHistory = ''
            end
        end

        if #settings.TempSettings.GetItems > 0 then
            local itemToGet = table.remove(settings.TempSettings.GetItems, 1)
            LNS.GetItemFromDB(itemToGet.Name or 'None', itemToGet.ID or 0)
            LNS.lookupLootRule(nil, itemToGet.ID, nil, itemToGet.ItemLink, true)
        end

        if settings.TempSettings.NeedSave then
            for k, v in pairs(settings.TempSettings.UpdatedBuyItems or {}) do
                if k ~= "" then
                    LNS.BuyItemsTable[k] = tonumber(v)
                end
            end

            settings.TempSettings.UpdatedBuyItems = {}
            for k in pairs(settings.TempSettings.DeletedBuyKeys or {}) do
                LNS.BuyItemsTable[k] = nil
                settings.TempSettings.NewBuyItem = ""
                settings.TempSettings.NewBuyQty = 1
            end

            settings.TempSettings.DeletedBuyKeys = {}
            LNS.writeSettings("MainLoop()")
            settings.TempSettings.NeedSave = false
            LNS.loadSettings()
            actors.SendMySettings()
            LNS.SortTables()
        end

        if settings.TempSettings.LookUpItem then
            if settings.TempSettings.SearchItems ~= nil and settings.TempSettings.SearchItems ~= "" then
                LNS.GetItemFromDB(settings.TempSettings.SearchItems, 0)
            end
            settings.TempSettings.LookUpItem = false
        end

        if LNS.NewItemsCount <= 0 then
            LNS.NewItemsCount = 0
            LNS.showNewItem = false
        end

        if settings.TempSettings.NeedsCleanup and not mq.TLO.Me.Casting() then
            settings.TempSettings.NeedsCleanup = false
            LNS.processItems('Destroy')
        end

        -- if LNS.MyClass:lower() == 'brd' and settings.Settings.DoDestroy then
        --     settings.Settings.DoDestroy = false
        --     Logger.Warn(LNS.guiLoot.console, "\ayBard Detected\ax, \arDisabling\ax [\atDoDestroy\ax].")
        -- end
        -- end)
        -- if not pcallSuccess then
        --     printf('LNS MainLoop encountered an error: %s', pcallResult)
        -- end
        mq.delay(10)
    end
    if LNS.Terminate then
        mq.unbind("/lootutils")
        mq.unbind("/lns")
        mq.unbind("/looted")
        mq.exit()
    end
end

---@class LNSDataType
---@field Looting boolean
---@field Paused boolean
---@field Mode string
---@type DataType
local LNSDataType = mq.DataType.new('LNS', {
    Members = {

        Looting = function(self)
            return 'bool', LNS.IsLooting
        end,

        Paused = function(self)
            return 'bool', LNS.PauseLooting
        end,

        Mode = function(self)
            return 'string', LNS.Mode
        end,

        ---Checks if the current zone or specified zone is marked as a safe zone
        ---@param param string|nil zone short name or nil
        ---@return string
        ---@return boolean
        SafeZone = function(param, self)
            if param and param:len() > 0 then
                return 'bool', LNS.SafeZones[param] or false
            end
            return 'bool', LNS.SafeZones[mq.TLO.Zone.ShortName()] or false
        end,
    },
    ToString = function(self)
        return 'LootNScoot'
    end,
})

function LNS.TLOHandler(param)
    return LNSDataType, LNS.PauseLooting
end

mq.AddTopLevelObject('LNS', LNS.TLOHandler)

LNS.init({ ..., })
LNS.MainLoop()

return LNS
