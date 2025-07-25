-- -@diagnostic disable: undefined-global, param-type-mismatch
-- -@diagnostic disable: undefined-field

local mq              = require 'mq'
local PackageMan      = require('mq.PackageMan')
local SQLite3         = PackageMan.Require('lsqlite3')
local Icons           = require('mq.ICONS')
local success, Logger = pcall(require, 'lib.Write')
-- local MasterLooter = require('MasterLooter')

if not success then
    printf('\arERROR: Write.lua could not be loaded\n%s\ax', Logger)
    return
end
local eqServer                          = string.gsub(mq.TLO.EverQuest.Server(), ' ', '_')
local version                           = 6
local MyName                            = mq.TLO.Me.DisplayName()
local Mode                              = 'once'
local Files                             = require('mq.Utils')
local SettingsFile                      = string.format('%s/LootNScoot/%s/%s.lua', mq.configDir, eqServer, MyName)
local imported                          = true
local lootDBUpdateFile                  = string.format('%s/LootNScoot/%s/DB_Updated.lua', mq.configDir, eqServer)
local zoneID                            = 0
local lootedCorpses                     = {}
local tmpRules, tmpClasses, tmpLinks    = {}, {}, {}
local ProcessItemsState                 = nil
local reportPrefixEQChat                = '/%s '
local reportPrefix                      = '/%s \a-t[\at%s\a-t][\ax\ayLootUtils\ax\a-t]\ax '
Logger.prefix                           = "[\atLootnScoot\ax] "
local eqChatChannels                    = { g = true, gu = true, rs = true, say = true, }
local newItem                           = nil
local debugPrint                        = false
local iconAnimation                     = mq.FindTextureAnimation('A_DragItem')
-- Internal settings
local cantLootList                      = {}
local cantLootID                        = 0
local itemNoValue                       = nil
local noDropItems, loreItems            = {}, {}
local allItems                          = {}
local foragingLoot                      = false
-- Constants
local spawnSearch                       = '%s radius %d zradius 50'
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
local saveOptionTypes                   = { string = 1, number = 1, boolean = 1, }
local NEVER_SELL                        = { ['Diamond Coin'] = true, ['Celestial Crest'] = true, ['Gold Coin'] = true, ['Taelosian Symbols'] = true, ['Planar Symbols'] = true, }
local showNewItem                       = false
local lookupDate                        = ''
local Actors                            = require('actors')

-- paths
local resourceDir                       = mq.TLO.MacroQuest.Path('resources')() .. "/"
local RulesDB                           = string.format('%s/LootNScoot/%s/AdvLootRules.db', resourceDir, eqServer)
local lootDB                            = string.format('%s/LootNScoot/%s/Items.db', resourceDir, eqServer)
local HistoryDB                         = string.format('%s/LootNScoot/%s/LootHistory.db', resourceDir, eqServer)

-- gui
local fontScale                         = 1
local iconSize                          = 16
local tempValues                        = {}
local animMini                          = mq.FindTextureAnimation("A_DragItem")
local EQ_ICON_OFFSET                    = 500
local showSettings                      = false
local enteredSafeZone                   = false
-- tables
local settingsEnum                      = {
    checkcorpseonce = 'CheckCorpseOnce',
    ignoremynearcorpses = 'IgnoreMyNearCorpses',
    autoshownewitem = 'AutoShowNewItem',
    keepspells = 'KeepSpells',
    canwear = 'CanWear',
    globallooton = 'GlobalLootOn',
    combatlooting = 'CombatLooting',
    corpseradius = 'CorpseRadius',
    mobstooclose = 'MobsTooClose',
    savebagslots = 'SaveBagSlots',
    tributekeep = 'TributeKeep',
    mintributevalue = 'MinTributeValue',
    minsellprice = 'MinSellPrice',
    stackplatvalue = 'StackPlatValue',
    stackableonly = 'StackableOnly',
    alwayseval = 'AlwaysEval',
    banktradeskills = 'BankTradeskills',
    doloot = 'DoLoot',
    lootforage = 'LootForage',
    lootnodrop = 'LootNoDrop',
    lootnodropnew = 'LootNoDropNew',
    lootquest = 'LootQuest',
    dodestroy = 'DoDestroy',
    alwaysdestroy = 'AlwaysDestroy',
    questkeep = 'QuestKeep',
    lootchannel = 'LootChannel',
    groupchannel = 'GroupChannel',
    reportloot = 'ReportLoot',
    reportskippeditems = 'ReportSkippedItems',
    spamlootinfo = 'SpamLootInfo',
    lootforagespam = 'LootForageSpam',
    addnewsales = 'AddNewSales',
    addnewtributes = 'AddNewTributes',
    masterlooting = 'MasterLooting',
    lootcheckdelay = 'LootCheckDelay',
    hidenames = 'HideNames',
    recorddata = 'RecordData',
    autotag = 'AutoTag',
    autorestock = 'AutoRestock',
    lootmycorpse = 'LootMyCorpse',
    lootaugments = 'LootAugments',
    showinfomessages = 'ShowInfoMessages',
    showconsole = 'ShowConsole',
    showreport = 'ShowReport',
    maxcorpsespercycle = 'MaxCorpsesPerCycle',
    ignorebagslot = 'IgnoreBagSlot',
    processingeval = 'ProcessingEval',
    alwaysglobal = 'AlwaysGlobal',

}
local doSell, doBuy, doTribute, areFull = false, false, false, false
local settingList                       = {
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

local settingsNoDraw                    = {
    Version = true,
    logger = true,
    LootFile = true,
    SettingsFile = true,
    NoDropDefaults = true,
    CorpseRotTime = true,
    Terminate = true,
    BuyItemsTable = true,
    ShowReport = true,
    ShowConsole = true,
    LookupLinks = true,
    MasterLooting = false,
}

-- table stuff

-- Pagination state
local ITEMS_PER_PAGE                    = 25
local selectedIndex                     = 1


-- Public default settings, also read in from Loot.ini [Settings] section


-- Module Settings
local LNS       = {}
LNS.CurrentPage = LNS.CurrentPage or 1

LNS.Settings    = {
    Version             = '"' .. tostring(version) .. '"',
    GlobalLootOn        = true,   -- Enable Global Loot Items. not implimented yet
    CombatLooting       = false,  -- Enables looting during combat. Not recommended on the MT
    CorpseRadius        = 100,    -- Radius to activly loot corpses
    MobsTooClose        = 40,     -- Don't loot if mobs are in this range.
    SaveBagSlots        = 3,      -- Number of bag slots you would like to keep empty at all times. Stop looting if we hit this number
    TributeKeep         = false,  -- Keep items flagged Tribute
    MinTributeValue     = 100,    -- Minimun Tribute points to keep item if TributeKeep is enabled.
    MinSellPrice        = -1,     -- Minimum Sell price to keep item. -1                                    = any
    StackPlatValue      = 0,      -- Minimum sell value for full stack
    StackableOnly       = false,  -- Only loot stackable items
    AlwaysEval          = false,  -- Re-Evaluate all *Non Quest* items. useful to update loot.ini after changing min sell values.
    BankTradeskills     = false,  -- Toggle flagging Tradeskill items as Bank or not.
    DoLoot              = true,   -- Enable auto looting in standalone mode
    LootForage          = true,   -- Enable Looting of Foraged Items
    LootNoDrop          = false,  -- Enable Looting of NoDrop items.
    LootNoDropNew       = false,  -- Enable looting of new NoDrop items.
    LootQuest           = true,   -- Enable Looting of Items Marked 'Quest', requires LootNoDrop on to loot NoDrop quest items
    DoDestroy           = false,  -- Enable Destroy functionality. Otherwise 'Destroy' acts as 'Ignore'
    AlwaysDestroy       = false,  -- Always Destroy items to clean corpese Will Destroy Non-Quest items marked 'Ignore' items REQUIRES DoDestroy set to true
    QuestKeep           = 10,     -- Default number to keep if item not set using Quest|# format.
    LootChannel         = "dgt",  -- Channel we report loot to.
    GroupChannel        = "dgze", -- Channel we use for Group Commands Default(dgze)
    ReportLoot          = true,   -- Report loot items to group or not.
    ReportSkippedItems  = false,  -- Report skipped items to group or not.
    SpamLootInfo        = false,  -- Echo Spam for Looting
    LootForageSpam      = false,  -- Echo spam for Foraged Items
    AddNewSales         = true,   -- Adds 'Sell' Flag to items automatically if you sell them while the script is running.
    AddNewTributes      = true,   -- Adds 'Tribute' Flag to items automatically if you Tribute them while the script is running.
    MasterLooting       = false,  -- Master Looter Mode, you will be prompted for who to loot for items marked as (Sell, Keep, Tribute).
    LootCheckDelay      = 0,      -- How long between checks to wait before checking again (seconds)
    HideNames           = false,  -- Hides names and uses class shortname in looted window
    RecordData          = true,   -- Enables recording data to report later.
    AutoTag             = false,  -- Automatically tag items to sell if they meet the MinSellPrice
    AutoRestock         = true,   -- Automatically restock items from the BuyItems list when selling
    LootMyCorpse        = false,  -- Loot your own corpse if its nearby (Does not check for REZ)
    LootAugments        = false,  -- Loot Augments
    CheckCorpseOnce     = true,   -- Check Corpse once and move on. Ignore the next time it is in range if enabled
    AutoShowNewItem     = false,  -- Automatically show new items in the looted window
    KeepSpells          = true,   -- Keep spells
    CanWear             = false,  -- Only loot items you can wear
    ShowInfoMessages    = true,
    ShowConsole         = false,
    ShowReport          = false,
    MaxCorpsesPerCycle  = 5,     -- Maximum number of corpses to loot per cycle
    IgnoreBagSlot       = 0,     -- Ignore this Bag Slot when buying, selling, tributing and destroying of items.
    AlwaysGlobal        = false, -- Always assign new rules to global as well as normal rules.
    IgnoreMyNearCorpses = false, -- Ignore my own corpses when looting nearby corpses, some servers you spawn after death with all your gear so this setting is handy.
    -- ProcessingEval   = true, -- Re evaluate when processing items for sell\tribute? this will re check our settings and not sell or tribute items outside the new parameters
    BuyItemsTable       = {
        ['Iron Ration'] = 20,
        ['Water Flask'] = 20,
    },
}

LNS.Tooltips    = {
    GlobalLootOn        = "Toggle using Global Rules if off we will only use Normal or Personal Rules. This setting is old and will probably be removed in the future.",
    CombatLooting       = "Enables looting during combat. Not recommended on the MT",
    CorpseRadius        = "Radius to activly loot corpses",
    MobsTooClose        = "Don't loot if mobs are in this range.",
    SaveBagSlots        = "Number of bag slots you would like to keep empty at all times. Stop looting if we hit this number",
    TributeKeep         = "Keep items flagged Tribute",
    MinTributeValue     = "Minimun Tribute points to keep item if TributeKeep is enabled.",
    MinSellPrice        = "Minimum Sell price to keep item. -1 = any",
    StackPlatValue      = "Minimum sell value for full stack",
    StackableOnly       = "Only loot stackable items",
    AlwaysEval          = "Re-Evaluate all *Non Quest* (Normal Item Rules) items. useful to update loot.ini after changing min sell values.",
    BankTradeskills     = "Toggle flagging Tradeskill items as Bank or not.",
    DoLoot              = "Enable auto looting in standalone mode",
    LootForage          = "Enable Looting of Foraged Items",
    LootNoDrop          = "Enable Looting of NoDrop items.",
    LootNoDropNew       = "Enable looting of new NoDrop items.",
    LootQuest           = "Enable Looting of Items Marked 'Quest', requires LootNoDrop on to loot NoDrop quest items",
    DoDestroy           = "Enable Destroy functionality. Otherwise 'Destroy' acts as 'Ignore'",
    AlwaysDestroy       = [[
Always Destroy items to clean corpese Will Destroy Non-Quest items marked 'Ignore' items",
REQUIRES DoDestroy set to true.]],
    QuestKeep           = "Default number to keep if item not set using Quest|# format.",
    LootChannel         = "Channel we report loot to. ex dgt",
    GroupChannel        = "Channel we use for Group Commands Default(dgze)",
    ReportLoot          = "Report loot items to group or not.",
    ReportSkippedItems  = "Report skipped items to group or not.",
    SpamLootInfo        = "Echo Spam for Looting",
    LootForageSpam      = "Echo spam for Foraged Items",
    AddNewSales         = "Adds 'Sell' Flag to items automatically if you sell them while the script is running.",
    AddNewTributes      = "Adds 'Tribute' Flag to items automatically if you Tribute them while the script is running.",
    MasterLooting       = "If Enabled you are in Master Looter Mode, you will be prompted for who to loot for items marked as (Sell, Keep, Tribute).",
    LootCheckDelay      = "How log to wait between loot checks. also applied to locked corpses before rechecking",
    HideNames           = "Hides names and uses class shortname in looted window",
    RecordData          = "Enables recording data to report later.",
    AutoTag             = "Automatically tag items to sell if they meet the MinSellPrice",
    AutoRestock         = "Automatically restock items from the BuyItems list after selling",
    LootMyCorpse        = "Loot your own corpse if its nearby (Does not check for REZ)",
    LootAugments        = "Loot Augments Overrides Normal Rules for Augments, Global and Personal Rules will override this setting",
    CheckCorpseOnce     = "Check Corpse once and move on. Ignore the next time it is in range if enabled",
    AutoShowNewItem     = "Automatically show new items in the looted window",
    KeepSpells          = "Keep spells reguardless of Normal Rule Global or Personal Rules will override this setting",
    CanWear             = "(Applies to No Drop New Items) Only loot items you can wear",
    ShowInfoMessages    = "Show or Hide [INFO] Messages in the loot console",
    ShowConsole         = "Show or Hide the Loot Console window",
    ShowReport          = "Prints report to the Console also toggles the report table window open if its closed.",
    IgnoreBagSlot       = "gnore this Bag Slot when buying, selling, tributing and destroying of items.",
    MaxCorpsesPerCycle  = "Maximum number of corpses to loot per cycle.",
    AlwaysGlobal        = "Always assign new rules to global as well as normal rules.",
    IgnoreMyNearCorpses = "Ignore my own corpses when looting nearby corpses, some servers you spawn after death with all your gear so this setting is handy.",
}

local tmpCmd    = LNS.GroupChannel or 'dgae'

LNS.MyClass     = mq.TLO.Me.Class.ShortName():lower()
LNS.MyRace      = mq.TLO.Me.Race.Name()
LNS.guiLoot     = require('loot_hist')
if LNS.guiLoot ~= nil then
    LNS.UseActors = true
    LNS.guiLoot.GetSettings(LNS.Settings.HideNames,
        LNS.Settings.RecordData,
        true,
        true,
        'lootnscoot',
        false,
        false
    )
end

LNS.DirectorScript                  = 'none'
LNS.DirectorLNSPath                 = nil
LNS.BuyItemsTable                   = {}
LNS.ALLITEMS                        = {}
LNS.GlobalItemsRules                = {}
LNS.NormalItemsRules                = {}
LNS.NormalItemsClasses              = {}
LNS.GlobalItemsClasses              = {}
LNS.NormalItemsMissing              = {}
LNS.GlobalItemsMissing              = {}
LNS.GlobalMissingNames              = {}
LNS.NormalMissingNames              = {}
LNS.HasMissingItems                 = false
LNS.NewItems                        = {}
LNS.TempSettings                    = {}
LNS.PersonalItemsRules              = {}
LNS.PersonalItemsClasses            = {}
LNS.BoxKeys                         = {}
LNS.NewItemDecisions                = nil
LNS.ItemNames                       = {}
LNS.ItemLinks                       = {}
LNS.ItemIcons                       = {}
LNS.NewItemsCount                   = 0
LNS.TempItemClasses                 = "All"
LNS.itemSelectionPending            = false -- Flag to indicate an item selection is in progress
LNS.pendingItemData                 = nil   -- Temporary storage for item data
LNS.doImportInventory               = false
LNS.TempModClass                    = false
LNS.ShowUI                          = false
LNS.Terminate                       = true
LNS.Boxes                           = {}
LNS.LootNow                         = false
LNS.histCurrentPage                 = 1
LNS.histItemsPerPage                = 25
LNS.histTotalPages                  = 1
LNS.histTotalItems                  = 0
LNS.HistoricalDates                 = {}
LNS.HistoryDataDate                 = {}
LNS.MasterLootList                  = nil
LNS.PersonalTableName               = string.format("%s_Rules", MyName)
LNS.TempSettings.Edit               = {}
LNS.TempSettings.ImportDBFileName   = ''
LNS.TempSettings.ImportDBFilePath   = ''
LNS.TempSettings.ItemsToLoot        = {}
LNS.TempSettings.UpdatedBuyItems    = {}
LNS.TempSettings.DeletedBuyKeys     = {}
LNS.TempSettings.RemoveMLItemInfo   = {}
LNS.TempSettings.RemoveMLCorpseInfo = {}
LNS.TempSettings.SortedSettingsKeys = {}
LNS.TempSettings.SortedToggleKeys   = {}
LNS.TempSettings.ModifyItemMatches  = nil
LNS.TempSettings.ShowHelp           = false
LNS.TempSettings.ShowImportDB       = false
LNS.TempSettings.UpdateSettings     = false
LNS.TempSettings.SendSettings       = false
LNS.TempSettings.LastModID          = 0
LNS.TempSettings.LastZone           = nil
LNS.TempSettings.SafeZoneWarned     = false
LNS.SafeZones                       = {}
LNS.PauseLooting                    = false
LNS.Zone                            = mq.TLO.Zone.ShortName()

local tableList                     = {
    "Global_Items", "Normal_Items", LNS.PersonalTableName,
}

local tableListRules                = {
    "Global_Rules", "Normal_Rules", LNS.PersonalTableName,
}

-- FORWARD DECLARATIONS
LNS.AllItemColumnListIndex          = {
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
    if LNS.MasterLootList[corpseID].Items[item_name].Members[MyName] == nil then
        LNS.send({
            who = MyName,
            action = 'check_item',
            item = item_name,
            link = LNS.ItemLinks[item_id],
            Count = myCount,
            Server = eqServer,
            CorpseID = corpseID,
            Value = item_value,
            NoDrop = item_is_nodrop,
            IsLore = item_is_lore,
        })
    end

    LNS.MasterLootList[corpseID].Items[item_name].Members[MyName] = myCount
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
    LNS.TempSettings.SortedSettingsKeys = {}
    LNS.TempSettings.SortedToggleKeys   = {}
    for k in pairs(LNS.Settings) do
        if not settingsNoDraw[k] then
            if type(LNS.Settings[k]) == 'boolean' then
                table.insert(LNS.TempSettings.SortedToggleKeys, k)
            else
                table.insert(LNS.TempSettings.SortedSettingsKeys, k)
            end
        end
    end
    table.sort(LNS.TempSettings.SortedToggleKeys, function(a, b) return a < b end)
    table.sort(LNS.TempSettings.SortedSettingsKeys, function(a, b) return a < b end)
end

function LNS.SortTables()
    LNS.TempSettings.SortedGlobalItemKeys     = {}
    LNS.TempSettings.SortedBuyItemKeys        = {}
    LNS.TempSettings.SortedNormalItemKeys     = {}
    LNS.TempSettings.SortedMissingGlobalNames = {}
    LNS.TempSettings.SortedMissingNormalNames = {}

    for k in pairs(LNS.GlobalItemsRules) do
        table.insert(LNS.TempSettings.SortedGlobalItemKeys, k)
    end
    table.sort(LNS.TempSettings.SortedGlobalItemKeys, function(a, b) return a < b end)

    for k in pairs(LNS.BuyItemsTable) do
        table.insert(LNS.TempSettings.SortedBuyItemKeys, k)
    end
    table.sort(LNS.TempSettings.SortedBuyItemKeys, function(a, b) return a < b end)

    for k in pairs(LNS.NormalItemsRules) do
        table.insert(LNS.TempSettings.SortedNormalItemKeys, k)
    end
    table.sort(LNS.TempSettings.SortedNormalItemKeys, function(a, b) return a < b end)

    local tmpTbl = {}
    for name, id in pairs(LNS.GlobalMissingNames) do
        table.insert(tmpTbl, { name = name, id = id, })
    end
    table.sort(tmpTbl, function(a, b)
        return a.name < b.name
    end)
    LNS.TempSettings.SortedMissingGlobalNames = tmpTbl


    tmpTbl = {}
    for name, id in pairs(LNS.NormalMissingNames) do
        table.insert(tmpTbl, { name = name, id = id, })
    end
    table.sort(tmpTbl, function(a, b)
        return a.name < b.name
    end)
    LNS.TempSettings.SortedMissingNormalNames = tmpTbl
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
    mq.cmdf("/squelch /mapfilter CastRadius %d", LNS.Settings.CorpseRadius)

    LNS.guiLoot.GetSettings(LNS.Settings.HideNames,
        LNS.Settings.RecordData,
        true, true, 'lootnscoot',
        LNS.Settings.ShowReport, LNS.Settings.ReportSkippedItems)

    LNS.Settings.BuyItemsTable = LNS.FixBuyQty(LNS.BuyItemsTable)
    mq.pickle(SettingsFile, LNS.Settings)
    LNS.Boxes[MyName] = LNS.Settings

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
    end
    local needDBUpdate = false
    local needSave     = false
    local tmpSettings  = {}

    if not Files.File.Exists(SettingsFile) then
        Logger.Warn(LNS.guiLoot.console, "Settings file not found, creating it now.")
        needSave = true
        mq.pickle(SettingsFile, LNS.Settings)
    else
        tmpSettings = dofile(SettingsFile)
    end
    -- check if the DB structure needs updating

    if not Files.File.Exists(lootDBUpdateFile) then
        tmpSettings.Version = version
        needSave            = true
        mq.pickle(lootDBUpdateFile, { version = version, })
    else
        LNS.TempSettings.VersionInfo = dofile(lootDBUpdateFile)
        if LNS.TempSettings.VersionInfo.version < version then
            needDBUpdate        = true
            tmpSettings.Version = version
            needSave            = true
        end
    end

    if not Files.File.Exists(RulesDB) then
        -- touch path to create the directory
        mq.pickle(RulesDB .. "touch", {})
    end
    -- process settings file

    for k, v in pairs(LNS.Settings) do
        if type(v) ~= 'table' then
            if tmpSettings[k] == nil then
                tmpSettings[k] = LNS.Settings[k]
                needSave       = true
                Logger.Info(LNS.guiLoot.console, "\agAdded\ax \ayNEW\ax \aySetting\ax: \at%s \aoDefault\ax: \at(\ay%s\ax)", k, v)
            end
        end
    end
    if tmpSettings.BuyItemsTable == nil then
        tmpSettings.BuyItemsTable = LNS.Settings.BuyItemsTable
        needSave                  = true
        Logger.Info(LNS.guiLoot.console, "\agAdded\ax \ayNEW\ax \aySetting\ax: \atBuyItemsTable\ax")
    end
    -- -- check for deprecated settings and remove them
    for k, v in pairs(tmpSettings) do
        if type(v) ~= 'table' then
            if LNS.Settings[k] == nil then
                tmpSettings[k] = nil
                needSave       = true
                Logger.Info(LNS.guiLoot.console, "\rRemoving\ax \ayOLD\ax \aySetting\ax: \at%s ", k)
            end
        end
    end
    Logger.loglevel = tmpSettings.ShowInfoMessages and 'info' or 'warn'

    tmpCmd = tmpSettings.GroupChannel or 'dgge'
    if tmpCmd == string.find(tmpCmd, 'dg') then
        tmpCmd = '/' .. tmpCmd
    elseif tmpCmd == string.find(tmpCmd, 'bc') then
        tmpCmd = '/' .. tmpCmd .. ' /'
    end

    shouldLootActions.Destroy = tmpSettings.DoDestroy
    shouldLootActions.Tribute = tmpSettings.TributeKeep
    shouldLootActions.Quest   = tmpSettings.LootQuest
    LNS.BuyItemsTable         = tmpSettings.BuyItemsTable

    if firstRun then
        -- SQL setup
        if not Files.File.Exists(RulesDB) then
            Logger.Warn(LNS.guiLoot.console, "\ayLoot Rules Database \arNOT found\ax, \atCreating it now\ax.")
        else
            Logger.Info(LNS.guiLoot.console, "\ayLoot Rules Database \agFound, \atloading it now.")
        end

        -- load the rules database

        -- check if the DB structure needs updating
        local db = LNS.OpenItemsSQL()
        db:exec("BEGIN TRANSACTION")
        db:exec([[
CREATE TABLE IF NOT EXISTS Items (
item_id INTEGER PRIMARY KEY NOT NULL UNIQUE,
name TEXT NOT NULL,
nodrop INTEGER DEFAULT 0,
notrade INTEGER DEFAULT 0,
tradeskill INTEGER DEFAULT 0,
quest INTEGER DEFAULT 0,
lore INTEGER DEFAULT 0,
augment INTEGER DEFAULT 0,
stackable INTEGER DEFAULT 0,
sell_value INTEGER DEFAULT 0,
tribute_value INTEGER DEFAULT 0,
stack_size INTEGER DEFAULT 0,
clickable TEXT,
augtype INTEGER DEFAULT 0,
strength INTEGER DEFAULT 0,
dexterity INTEGER DEFAULT 0,
agility INTEGER DEFAULT 0,
stamina INTEGER DEFAULT 0,
intelligence INTEGER DEFAULT 0,
wisdom INTEGER DEFAULT 0,
charisma INTEGER DEFAULT 0,
mana INTEGER DEFAULT 0,
hp INTEGER DEFAULT 0,
ac INTEGER DEFAULT 0,
regen_hp INTEGER DEFAULT 0,
regen_mana INTEGER DEFAULT 0,
haste INTEGER DEFAULT 0,
classes INTEGER DEFAULT 0,
class_list TEXT DEFAULT 'All',
svfire INTEGER DEFAULT 0,
svcold INTEGER DEFAULT 0,
svdisease INTEGER DEFAULT 0,
svpoison INTEGER DEFAULT 0,
svcorruption INTEGER DEFAULT 0,
svmagic INTEGER DEFAULT 0,
spelldamage INTEGER DEFAULT 0,
spellshield INTEGER DEFAULT 0,
damage INTEGER DEFAULT 0,
weight INTEGER DEFAULT 0,
item_size INTEGER DEFAULT 0,
weightreduction INTEGER DEFAULT 0,
races INTEGER DEFAULT 0,
race_list TEXT DEFAULT 'All',
icon INTEGER,
item_range INTEGER DEFAULT 0,
attack INTEGER DEFAULT 0,
collectible INTEGER DEFAULT 0,
strikethrough INTEGER DEFAULT 0,
heroicagi INTEGER DEFAULT 0,
heroiccha INTEGER DEFAULT 0,
heroicdex INTEGER DEFAULT 0,
heroicint INTEGER DEFAULT 0,
heroicsta INTEGER DEFAULT 0,
heroicstr INTEGER DEFAULT 0,
heroicsvcold INTEGER DEFAULT 0,
heroicsvcorruption INTEGER DEFAULT 0,
heroicsvdisease INTEGER DEFAULT 0,
heroicsvfire INTEGER DEFAULT 0,
heroicsvmagic INTEGER DEFAULT 0,
heroicsvpoison INTEGER DEFAULT 0,
heroicwis INTEGER DEFAULT 0,
link TEXT
);
]])
        db:exec("CREATE INDEX IF NOT EXISTS idx_item_name ON Items (name);")
        db:exec("CREATE INDEX IF NOT EXISTS idx_item_id ON Items (item_id);")

        db:exec("COMMIT")
        db:close()

        LNS.LoadRuleDB()

        LNS.LoadHistoricalData()
    end
    LNS.Settings = {}
    LNS.Settings = tmpSettings
    LNS.Boxes[MyName] = {}
    LNS.Boxes[MyName] = LNS.Settings
    if firstRun then table.insert(LNS.BoxKeys, MyName) end
    LNS.guiLoot.openGUI = LNS.Settings.ShowConsole
    local needFixBuyQty = false
    LNS.BuyItemsTable, needFixBuyQty = LNS.FixBuyQty(LNS.BuyItemsTable)
    if needFixBuyQty then
        needSave = true
        Logger.Warn(LNS.guiLoot.console, "BuyItemsTable had invalid values, fixed them and saved the settings.")
    end

    return needSave
end

local function convertTimestamp(timeStr)
    local h, mi, s = timeStr:match("(%d+):(%d+):(%d+)")
    local hour = tonumber(h)
    local min = tonumber(mi)
    local sec = tonumber(s)
    local timeSeconds = (hour * 3600) + (min * 60) + sec
    return timeSeconds
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
            if LNS.Settings.SpamLootInfo then Logger.Warn(LNS.guiLoot.console, 'Inventory full, item stuck on cursor') end
            mq.cmdf('/autoinv')
            return
        end
        currentItem = mq.TLO.Cursor()
        mq.cmdf('/autoinv')
        mq.delay(3000, function() return not mq.TLO.Cursor() end)
    end
end

function LNS.navToID(spawnID)
    mq.cmdf('/nav id %d dist=10 log=off', spawnID)
    mq.delay(50)
    if mq.TLO.Navigation.Active() then
        local startTime = os.time()
        while mq.TLO.Navigation.Active() do
            mq.delay(100)
            if os.difftime(os.time(), startTime) > 5 then
                break
            end
        end
    end
end

function LNS.report(message, ...)
    if LNS.Settings.ReportLoot then
        LNS.doReport(message, ...)
    end
end

function LNS.doReport(message, ...)
    local prefixWithChannel = not eqChatChannels[LNS.Settings.LootChannel] and reportPrefix:format(LNS.Settings.LootChannel, mq.TLO.Time()) or
        reportPrefixEQChat:format(LNS.Settings.LootChannel)
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
        LNS.TempSettings.ShowMailbox = not LNS.TempSettings.ShowMailbox
        if not debugPrint then
            debugPrint = LNS.TempSettings.ShowMailbox
        end
        return
    end
    if args[1] == 'set' then
        local setting    = args[2]:lower()
        local settingVal = args[3]
        if settingsEnum[setting] ~= nil then
            local settingName = settingsEnum[setting]
            if type(LNS.Settings[settingName]) == 'table' then
                Logger.Error(LNS.guiLoot.console, "Setting \ay%s\ax is a table and cannot be set directly.", settingName)
                return
            end
            if type(LNS.Settings[settingName]) == 'boolean' then
                LNS.Settings[settingName] = settingVal == 'on'
                if settingName == 'MasterLooting' then
                    LNS.send({
                        who = MyName,
                        action = 'master_looter',
                        Server = eqServer,
                        select = LNS.Settings.MasterLooting,
                    })
                    Logger.Info(LNS.guiLoot.console, "Setting \ay%s\ax to \ag%s\ax", settingName, settingVal)
                end
            elseif type(LNS.Settings[settingName]) == 'number' then
                LNS.Settings[settingName] = tonumber(settingVal)
            else
                LNS.Settings[settingName] = settingVal
            end
            Logger.Info(LNS.guiLoot.console, "Setting \ay%s\ax to \ag%s\ax", settingName, settingVal)
            LNS.TempSettings[MyName] = nil
            LNS.TempSettings.NeedSave = true
        else
            Logger.Warn(LNS.guiLoot.console, "Invalid setting name: %s", setting)
        end
        if needSave then LNS.writeSettings("CommandHandler:set") end
        LNS.sendMySettings()
        return
    end
    if args[1] == 'corpsereset' then
        local numCorpses = lootedCorpses ~= nil and LNS.GetTableSize(lootedCorpses) or 0
        lootedCorpses = {}
        Logger.Info(LNS.guiLoot.console, "Corpses (\ay%s\ax) have been \agReset\ax", numCorpses)
        LNS.send({ Who = MyName, CorpsesToIgnore = lootedCorpses, Server = eqServer, LNSSettings = LNS.Settings, }, 'loot_module')
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
            count, data = LNS.findItemInDb(nil, itemID)
            if count > 0 then
                Logger.Info(LNS.guiLoot.console, "Found item in DB: \ay%s\ax Link: %s", data[itemID].item_name, data[itemID].item_link)
            else
                Logger.Warn(LNS.guiLoot.console, "Item \ar%s\ax not found in DB", args[2])
            end
        else
            count, data = LNS.findItemInDb(args[2])
            if count > 0 then
                for k, row in pairs(data) do
                    Logger.Info(LNS.guiLoot.console, "Found %s item in DB: \ay%s\ax ID: \at%s Link: \al%s", count, row.item_name, row.item_id, row.item_link)
                end
            else
                Logger.Warn(LNS.guiLoot.console, "Item \ar%s\ax not found in DB", args[2])
            end
            -- LNS.findItemInDb(args[2])
        end
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
                    Logger.Warn(LNS.guiLoot.console, "Item \ar%s\ax not found in DB", args[3])
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
                    Logger.Warn(LNS.guiLoot.console, "Item \ar%s\ax not found in DB", args[3])
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
                    Logger.Warn(LNS.guiLoot.console, "Item \ar%s\ax not found in DB", args[3])
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
            LNS.TempSettings.ShowImportDB = true
        elseif command == 'debug' then
            debugPrint = not debugPrint
            Logger.Warn(LNS.guiLoot.console, "\ayDebugging\ax is now %s", debugPrint and "\agon" or "\aroff")
        elseif command == 'reload' then
            local needSave = LNS.loadSettings()
            if needSave then
                LNS.writeSettings("CommandHandler:reload")
            end
            if LNS.guiLoot then
                LNS.guiLoot.GetSettings(
                    LNS.Settings.HideNames,
                    LNS.Settings.RecordData,
                    true,
                    LNS.Settings.UseActors,
                    'lootnscoot', LNS.Settings.ShowReport,
                    LNS.Settings.ReportSkippedItems
                )
            end
            Logger.Info(LNS.guiLoot.console, "\ayReloaded Settings \axand \atLoot Files")
        elseif command == 'update' then
            if LNS.guiLoot then
                LNS.guiLoot.GetSettings(
                    LNS.Settings.HideNames,

                    LNS.Settings.RecordData,
                    true,
                    LNS.Settings.UseActors,
                    'lootnscoot', LNS.Settings.ShowReport,
                    LNS.Settings.ReportSkippedItems
                )
            end
            LNS.UpdateDB()
            Logger.Info(LNS.guiLoot.console, "\ayUpdated the DB from loot.ini \axand \atreloaded settings")
        elseif command == 'importinv' then
            LNS.addMyInventoryToDB()
        elseif command == 'bankstuff' then
            LNS.processItems('Bank')
        elseif command == 'cleanup' then
            LNS.processItems('Destroy')
            LNS.TempSettings.NeedsCleanup = true
        elseif command == 'help' then
            LNS.TempSettings.ShowHelp = true
        elseif command == 'gui' or command == 'console' and LNS.guiLoot then
            LNS.guiLoot.openGUI = not LNS.guiLoot.openGUI
        elseif command == 'report' and LNS.guiLoot then
            LNS.guiLoot.ReportLoot()
        elseif command == 'hidenames' and LNS.guiLoot then
            LNS.guiLoot.hideNames = not LNS.guiLoot.hideNames
        elseif command == 'config' then
            local confReport = "\ayLoot N Scoot Settings\ax"
            for key, value in pairs(LNS.Settings) do
                if type(value) ~= "function" and type(value) ~= "table" then
                    confReport = confReport .. string.format("\n\at%s\ax                                    = \ag%s\ax", key, tostring(value))
                end
            end
            Logger.Info(LNS.guiLoot.console, confReport)
        elseif command == 'tributestuff' then
            LNS.processItems('Tribute')
        elseif command == 'shownew' or command == 'newitems' then
            showNewItem = not showNewItem
        elseif command == 'loot' then
            LNS.lootMobs(LNS.Settings.MaxCorpsesPerCycle)
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
            LNS.Terminate = true
        end
        if command == 'buy' and mq.TLO.Cursor() ~= nil then
            local itemName = mq.TLO.Cursor.Name()
            LNS.BuyItemsTable[itemName] = 1
            LNS.setBuyItem(itemName, 1)
            LNS.TempSettings.NeedSave = true
            LNS.TempSettings.NewBuyItem = ""
            LNS.TempSettings.NewBuyQty = 1

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
                debugPrint = true
                Logger.Info(LNS.guiLoot.console, "\ayDebugging\ax is now \agON\ax")
            elseif args[2] == 'off' then
                debugPrint = false
                Logger.Info(LNS.guiLoot.console, "\ayDebugging\ax is now \arOFF\ax")
            end
        end
        if action == 'buy' and mq.TLO.Cursor() ~= nil then
            if tonumber(args[2]) then
                local cursorItem = mq.TLO.Cursor.Name()
                LNS.BuyItemsTable[cursorItem] = args[2]

                LNS.setBuyItem(cursorItem, args[2])
                LNS.TempSettings.NeedSave = true
                LNS.TempSettings.NewBuyItem = ""
                LNS.TempSettings.NewBuyQty = tonumber(args[2]) or 0

                Logger.Info(LNS.guiLoot.console, "Setting \ay%s\ax to \agBuy Item\ax", cursorItem)
            end
        elseif action == 'buy' and type(item_name) == 'string' then
            LNS.BuyItemsTable[item_name] = 1
            LNS.setBuyItem(item_name, 1)
            LNS.TempSettings.NeedSave = true
            LNS.TempSettings.NewBuyItem = ""
            LNS.TempSettings.NewBuyQty = 1

            Logger.Info(LNS.guiLoot.console, "Setting \ay%s\ax to \agBuy Item\ax", item_name)
        end
    elseif args[1] == 'buy' then
        LNS.BuyItemsTable[args[2]] = args[3]
        LNS.setBuyItem(args[2], args[3])
        LNS.TempSettings.NeedSave = true
        LNS.TempSettings.NewBuyItem = ""
        LNS.TempSettings.NewBuyQty = tonumber(args[3]) or 0
        Logger.Info(LNS.guiLoot.console, "Setting \ay%s\ax to \agBuy Item\ax", args[2])
    end
    if LNS.TempSettings.NeedSave then
        LNS.writeSettings("CommandHandler:args")
        LNS.TempSettings.NeedSave = false
    end
end

function LNS.setupBinds()
    mq.bind('/lootutils', LNS.commandHandler)
    mq.bind('/lns', LNS.commandHandler)
end

function LNS.CheckBags()
    if LNS.Settings.SaveBagSlots == nil then return false end
    -- Logger.Warn(loot.guiLoot.console,"\agBag CHECK\ax free: \at%s\ax, save: \ag%s\ax", mq.TLO.Me.FreeInventory(), loot.Settings.SaveBagSlots)
    areFull = mq.TLO.Me.FreeInventory() <= LNS.Settings.SaveBagSlots
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

function LNS.reportSkippedItems(noDropItems, loreItems, corpseName, corpseID)
    -- Ensure parameters are valid
    noDropItems = noDropItems or {}
    loreItems   = loreItems or {}

    -- Log skipped items
    if next(noDropItems) then
        Logger.Info(LNS.guiLoot.console, "\aySkipped NoDrop\ax items from corpse \at%s\ax (ID:\at %s\ax):\ay %s\ax",
            corpseName, tostring(corpseID), table.concat(noDropItems, ", "))
        if LNS.Settings.ReportSkippedItems then
            LNS.doReport("Skipped NoDrop: %s (%s): %s", corpseName, tostring(corpseID), table.concat(noDropItems, ", "))
        end
    end

    if next(loreItems) then
        Logger.Info(LNS.guiLoot.console, "\aySkipped Lore\ax items from corpse \at%s\ax (ID:\at %s\ax):\ay %s\ax",
            corpseName, tostring(corpseID), table.concat(loreItems, ", "))
        if LNS.Settings.ReportSkippedItems then
            LNS.doReport("Skipped Lore: %s (%s): %s", corpseName, tostring(corpseID), table.concat(loreItems, ", "))
        end
    end
end

function LNS.corpseLocked(corpseID)
    if not cantLootList[corpseID] then return false end
    if os.difftime(os.clock(), cantLootList[corpseID]) > ((LNS.Settings.LootCheckDelay or 0) > 0 and LNS.Settings.LootCheckDelay or 0.25) then
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
        who        = MyName,
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
        Server     = eqServer,
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

    if LNS.Settings.AlwaysGlobal then
        modMessage.section = "GlobalItems"
    end
    LNS.send(modMessage)
end

------------------------------------
--          SQL Functions
------------------------------------


function LNS.ImportOldRulesDB(path)
    if not Files.File.Exists(path) then
        Logger.Error(LNS.guiLoot.console, "loot.ImportOldRulesDB() \arFile not found: \at%s\ax", path)
        return
    end

    local db = SQLite3.open(path)
    if not db then
        Logger.Error(LNS.guiLoot.console, "loot.ImportOldRulesDB() \arFailed to open database: \at%s\ax", RulesDB)
        return
    end

    local tmpGlobalDB = {}
    local tmpNormalDB = {}
    local tmpNamesGlobal = {}
    local tmpNamesNormal = {}

    db:exec("PRAGMA journal_mode=WAL;")
    db:exec("BEGIN TRANSACTION")
    local query = "SELECT * From Global_Rules;"
    local stmt = db:prepare(query)
    local cntr = 1
    for row in stmt:nrows() do
        local itemID = cntr * -1
        tmpGlobalDB[itemID] = {
            item_id      = itemID,
            item_name    = row.item_name,
            item_rule    = row.item_rule,
            item_classes = row.item_classes or 'All',
        }
        tmpNamesGlobal[row.item_name] = itemID
        cntr = cntr + 1
    end

    query = "SELECT * From Normal_Rules;"
    stmt = db:prepare(query)
    cntr = 1
    for row in stmt:nrows() do
        local itemID = cntr * -1

        tmpNormalDB[itemID] = {
            item_id      = itemID,
            item_name    = row.item_name,
            item_rule    = row.item_rule,
            item_classes = row.item_classes or 'All',
        }
        tmpNamesNormal[row.item_name] = itemID
        cntr = cntr + 1
    end
    stmt:finalize()
    db:exec("COMMIT")
    db:close()


    local nameSet = {}
    for _, v in pairs(tmpGlobalDB) do nameSet[v.item_name] = true end
    for _, v in pairs(tmpNormalDB) do nameSet[v.item_name] = true end

    -- Resolve IDs in one DB pass
    local resolvedNames = LNS.ResolveItemIDs(nameSet)

    -- Replace IDs for tmpGlobalDB
    local newGlobal = {}
    for k, v in pairs(tmpGlobalDB) do
        local realID = resolvedNames[v.item_name]
        local id = realID or v.item_id
        if id < 0 then LNS.HasMissingItems = true end
        newGlobal[id] = {
            item_id = id,
            item_name = v.item_name,
            item_rule = v.item_rule,
            item_classes = v.item_classes,

        }
    end
    tmpGlobalDB = newGlobal

    local newNormal = {}
    -- Replace IDs for tmpNormalDB
    for k, v in pairs(tmpNormalDB) do
        local realID = resolvedNames[v.item_name]
        local id = realID or v.item_id
        if id < 0 then LNS.HasMissingItems = true end
        newNormal[id] = {
            item_id = id,
            item_name = v.item_name,
            item_rule = v.item_rule,
            item_classes = v.item_classes,
        }
    end

    tmpNormalDB = newNormal

    -- insert into the current rules DB
    db = SQLite3.open(RulesDB)
    if not db then return end
    db:exec("PRAGMA journal_mode=WAL;")

    local qry = string.format([[
INSERT INTO Global_Rules (item_id, item_name, item_rule, item_rule_classes, item_link)
VALUES (?, ?, ?, ?, ?)
ON CONFLICT(item_id) DO UPDATE SET
item_name = excluded.item_name,
item_rule = excluded.item_rule,
item_rule_classes = excluded.item_rule_classes,
item_link = excluded.item_link
]])

    stmt = db:prepare(qry)
    if not stmt then
        db:close()
        return
    end

    db:exec("BEGIN TRANSACTION;")

    for itemID, data in pairs(tmpGlobalDB or {}) do
        local itemName = data.item_name
        local itemLink = LNS.ItemLinks[itemID] or 'NULL'
        local classes = data.item_classes or 'All'
        local rule = data.item_rule or 'Ask'

        if itemName then
            stmt:bind_values(itemID, itemName, rule, classes, itemLink)
            stmt:step()
            stmt:reset()
            LNS.GlobalItemsRules[itemID] = rule
            LNS.GlobalItemsClasses[itemID] = classes
            LNS.ItemNames[itemID] = itemName
            if itemID > 0 then tmpGlobalDB[itemID] = nil end
        end
    end

    qry = string.format([[
INSERT INTO Normal_Rules (item_id, item_name, item_rule, item_rule_classes, item_link)
VALUES (?, ?, ?, ?, ?)
ON CONFLICT(item_id) DO UPDATE SET
item_name = excluded.item_name,
item_rule = excluded.item_rule,
item_rule_classes = excluded.item_rule_classes,
item_link = excluded.item_link
]])

    stmt = db:prepare(qry)
    if not stmt then
        db:exec("COMMIT;")

        db:close()
        return
    end

    for itemID, data in pairs(tmpNormalDB or {}) do
        local itemName = data.item_name
        local itemLink = LNS.ItemLinks[itemID] or 'NULL'
        local classes = data.item_classes or 'All'
        local rule = data.item_rule or 'Ask'
        if itemName then
            stmt:bind_values(itemID, itemName, rule, classes, itemLink)
            stmt:step()
            stmt:reset()
            LNS.NormalItemsRules[itemID] = rule
            LNS.NormalItemsClasses[itemID] = classes
            LNS.ItemNames[itemID] = itemName
            if itemID > 0 then tmpNormalDB[itemID] = nil end
        end
    end
    stmt:finalize()


    -- check items and if we find only one update the rule
    db:exec("COMMIT;")
    db:close()
    Logger.Info(LNS.guiLoot.console, "loot.ImportOldRulesDB() \agSuccessfully imported old rules from \at%s\ax", path)

    -- update our missing tables
    LNS.GlobalItemsMissing = tmpGlobalDB or {}
    LNS.NormalItemsMissing = tmpNormalDB or {}
    LNS.GlobalMissingNames = tmpNamesGlobal or {}
    LNS.NormalMissingNames = tmpNamesNormal or {}
end

function LNS.OpenItemsSQL()
    local db = SQLite3.open(lootDB)
    if db then
        db:exec("PRAGMA journal_mode=WAL;")
    end
    return db
end

function LNS.LoadHistoricalData()
    LNS.HistoricalDates = {}
    local db = SQLite3.open(HistoryDB)
    db:exec("PRAGMA journal_mode=WAL;")
    db:exec("BEGIN TRANSACTION")
    db:exec([[
CREATE TABLE IF NOT EXISTS LootHistory (
"id" INTEGER PRIMARY KEY AUTOINCREMENT,
"Item" TEXT NOT NULL,
"CorpseName" TEXT NOT NULL,
"Action" TEXT NOT NULL,
"Date" TEXT NOT NULL,
"TimeStamp" TEXT NOT NULL ,
"Link" TEXT NOT NULL,
"Looter" TEXT NOT NULL,
"Zone" TEXT NOT NULL
);
]])
    db:exec("COMMIT")

    db:exec("BEGIN TRANSACTION")

    local stmt = db:prepare("SELECT DISTINCT Date FROM LootHistory ORDER BY Date DESC")

    for row in stmt:nrows() do
        table.insert(LNS.HistoricalDates, row.Date)
    end

    stmt:finalize()
    db:exec("COMMIT")
    db:close()
end

function LNS.LoadDateHistory(lookup_Date)
    local db = SQLite3.open(HistoryDB)
    db:exec("PRAGMA journal_mode=WAL;")
    db:exec("BEGIN TRANSACTION")

    LNS.HistoryDataDate = {}
    local stmt = db:prepare("SELECT * FROM LootHistory WHERE Date = ?")
    stmt:bind_values(lookup_Date)
    for row in stmt:nrows() do
        table.insert(LNS.HistoryDataDate, row)
    end

    stmt:finalize()
    db:exec("COMMIT")
    db:close()
end

function LNS.AddSafeZone(zoneName)
    if not zoneName or zoneName == "" then return end
    local db = SQLite3.open(RulesDB)
    db:exec("PRAGMA journal_mode=WAL;")
    db:exec("BEGIN TRANSACTION")

    local stmt = db:prepare("INSERT OR IGNORE INTO SafeZones (zone) VALUES (?)")
    stmt:bind_values(zoneName)
    local res, err = stmt:step()
    if res ~= SQLite3.DONE then
        printf("Error inserting safe zone: %s ", err)
    end
    stmt:finalize()

    db:exec("COMMIT")
    db:close()
    LNS.SafeZones[zoneName] = true
    LNS.send({
        who = MyName,
        action = 'addsafezone',
        Server = eqServer,
        zone = zoneName,
    })
    if LNS.SafeZones[LNS.Zone] and not LNS.TempSettings.SafeZoneWarned then
        Logger.Warn(LNS.guiLoot.console, "You are in a safe zone: \at%s\ax \ayLooting Disabled", LNS.Zone)
        LNS.TempSettings.SafeZoneWarned = true
    end
end

function LNS.RemoveSafeZone(zoneName)
    if not zoneName or zoneName == "" then return end
    local db = SQLite3.open(RulesDB)
    db:exec("PRAGMA journal_mode=WAL;")
    db:exec("BEGIN TRANSACTION")

    local stmt = db:prepare("DELETE FROM SafeZones WHERE zone = ?")
    stmt:bind_values(zoneName)
    local res, err = stmt:step()
    if res ~= SQLite3.DONE then
        printf("Error deleting safe zone: %s ", err)
    end
    stmt:finalize()

    db:exec("COMMIT")
    db:close()
    LNS.SafeZones[zoneName] = nil
    LNS.send({
        who = MyName,
        Server = eqServer,
        action = 'removesafezone',
        zone = zoneName,
    })
end

function LNS.LoadItemHistory(lookup_name)
    local db = SQLite3.open(HistoryDB)
    db:exec("PRAGMA journal_mode=WAL;")
    db:exec("BEGIN TRANSACTION")

    LNS.HistoryItemData = {}
    local stmt = db:prepare("SELECT * FROM LootHistory WHERE Item LIKE ?")
    stmt:bind_values(string.format("%%%s%%", lookup_name))
    for row in stmt:nrows() do
        table.insert(LNS.HistoryItemData, row)
    end

    stmt:finalize()
    db:exec("COMMIT")
    db:close()
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
    local db = SQLite3.open(HistoryDB)
    if not db then
        print("Error: Failed to open database.")
        return
    end
    local eval = action:find('Ignore') and 'Left' or action

    db:exec("PRAGMA journal_mode=WAL;")

    -- Convert current date+time to epoch
    local currentTime = convertTimestamp(timestamp)

    -- Skip if a duplicate "Ignore" or "Left" action exists within the last minute
    if action:find("Ignore") or action:find("Left") then
        local checkStmt = db:prepare([[
SELECT Date, TimeStamp FROM LootHistory
WHERE Item = ? AND CorpseName = ? AND Action = ? AND Date = ?
ORDER BY Date DESC, TimeStamp DESC LIMIT 1
]])
        if checkStmt then
            checkStmt:bind_values(itemName, corpseName, action, date)
            local res = checkStmt:step()
            if res == SQLite3.ROW then
                local lastTimestamp = checkStmt:get_value(1)
                local recoredTime = convertTimestamp(lastTimestamp)
                if (currentTime - recoredTime) <= 60 then
                    checkStmt:finalize()
                    db:close()
                    return
                end
            end
            checkStmt:finalize()
        end
    end

    db:exec("BEGIN TRANSACTION")
    local stmt = db:prepare([[
INSERT INTO LootHistory (Item, CorpseName, Action, Date, TimeStamp, Link, Looter, Zone)
VALUES (?, ?, ?, ?, ?, ?, ?, ?)
]])
    if stmt then
        stmt:bind_values(itemName, corpseName, action, date, timestamp, link, looter, zone)
        local res, err = stmt:step()
        if res ~= SQLite3.DONE then
            printf("Error inserting data: %s ", err)
        end
        stmt:finalize()
    else
        print("Error preparing statement")
    end

    db:exec("COMMIT")
    db:close()

    local actLabel = action:find('Destroy') and 'Destroyed' or action
    if not action:find('Destroy') and not action:find('Ignore') and not action:find('Left') then
        actLabel = 'Looted'
    end
    if LNS.guiLoot.ReportLeft and (action:find('Left') or action:find('Ignore')) then
        actLabel = 'Left'
    end
    if allItems == nil then
        allItems = {}
    end
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

function LNS.LoadIcons()
    local db = LNS.OpenItemsSQL()
    local stmt = db:prepare("SELECT item_id, icon FROM Items")

    for row in stmt:nrows() do
        LNS.ItemIcons[row.item_id] = row.icon
    end

    stmt:finalize()
    db:close()
end

function LNS.LoadRuleDB()
    local db = SQLite3.open(RulesDB)
    local charTableName = string.format("%s_Rules", MyName)

    db:exec("PRAGMA journal_mode=WAL;")
    db:exec("BEGIN TRANSACTION")

    -- Creating tables
    db:exec(string.format([[
CREATE TABLE IF NOT EXISTS Global_Rules (
item_id INTEGER PRIMARY KEY NOT NULL UNIQUE,
item_name TEXT NOT NULL,
item_rule TEXT NOT NULL,
item_rule_classes TEXT,
item_link TEXT
);
CREATE TABLE IF NOT EXISTS Normal_Rules (
item_id INTEGER PRIMARY KEY NOT NULL UNIQUE,
item_name TEXT NOT NULL,
item_rule TEXT NOT NULL,
item_rule_classes TEXT,
item_link TEXT
);
CREATE TABLE IF NOT EXISTS %s (
item_id INTEGER PRIMARY KEY NOT NULL UNIQUE,
item_name TEXT NOT NULL,
item_rule TEXT NOT NULL,
item_rule_classes TEXT,
item_link TEXT
);
CREATE TABLE IF NOT EXISTS SafeZones (
zone TEXT PRIMARY KEY NOT NULL UNIQUE
);
]], charTableName))

    local function processRules(stmt, ruleTable, classTable, linkTable, missingItemTable, missingNames)
        if not db then db = SQLite3.open(RulesDB) end
        for row in stmt:nrows() do
            local id = row.item_id
            local classes = row.item_rule_classes
            if classes == nil then classes = 'None' end
            local classTmp = string.gsub(classes, ' ', '')
            if classes == 'None' or classTmp == '' then classes = 'All' end
            ruleTable[id] = row.item_rule
            classTable[id] = classes
            linkTable[id] = row.item_link or "NULL"
            if id < 0 then
                missingItemTable[id] = { item_id = id, item_name = row.item_name, item_rule = row.item_rule, item_classes = classes, }
                missingNames[row.item_name] = id
                LNS.HasMissingItems = true
            end
            LNS.ItemNames[id] = row.item_name
        end
    end

    for _, tbl in ipairs({ "Global_Rules", "Normal_Rules", charTableName, }) do
        local stmt = db:prepare("SELECT * FROM " .. tbl)
        local lbl = tbl:gsub("_Rules", "")
        if tbl == charTableName then lbl = 'Personal' end
        if stmt then
            processRules(stmt, LNS[lbl .. "ItemsRules"], LNS[lbl .. "ItemsClasses"],
                LNS.ItemLinks, LNS[lbl .. 'ItemsMissing'], LNS[lbl .. 'MissingNames'])
            stmt:finalize()
        end
    end

    LNS.SafeZones = {}
    local sz_stmt = db:prepare("SELECT * FROM SafeZones")
    for row in sz_stmt:nrows() do
        local zone = row.zone
        if zone then
            LNS.SafeZones[zone] = true
        end
    end
    sz_stmt:finalize()

    db:exec("COMMIT")
    db:close()

    -- Load icons
    LNS.LoadIcons()
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
function LNS.GetItemFromDB(itemName, itemID, rules, db, exact)
    if not itemID and not itemName then return 0 end
    itemID = itemID or 0
    itemName = itemName or 'NULL'
    db = db or LNS.OpenItemsSQL()
    local noDBConnection = db == nil
    LNS.TempSettings.SearchResults = nil
    -- --===============================

    local conditions = {}
    local orderBy = "ORDER BY name ASC"
    local query = ""
    local stmt

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

    stmt = db:prepare(query)
    if not stmt then
        Logger.Error(LNS.guiLoot.console, "Failed to prepare SQL statement: %s", db:errmsg())
        if noDBConnection then
            db:close()
        end
        return 0
    end
    Logger.Debug(LNS.guiLoot.console, "SQL Query: \ay%s\ax ", query)

    --===========================

    local rowsFetched = 0
    for row in stmt:nrows() do
        local id = row.item_id
        if id then
            local itemData = {
                Name = row.name or 'NULL',
                NoDrop = row.nodrop == 1,
                NoTrade = row.notrade == 1,
                Tradeskills = row.tradeskill == 1,
                Quest = row.quest == 1,
                Lore = row.lore == 1,
                Augment = row.augment == 1,
                Stackable = row.stackable == 1,
                Value = LNS.valueToCoins(row.sell_value),
                Tribute = row.tribute_value,
                StackSize = row.stack_size,
                Clicky = row.clickable or 'None',
                AugType = row.augtype,
                strength = row.strength,
                DEX = row.dexterity,
                AGI = row.agility,
                STA = row.stamina,
                INT = row.intelligence,
                WIS = row.wisdom,
                CHA = row.charisma,
                Mana = row.mana,
                HP = row.hp,
                AC = row.ac,
                HPRegen = row.regen_hp,
                ManaRegen = row.regen_mana,
                Haste = row.haste,
                Classes = row.classes,
                ClassList = row.class_list:gsub(" ", '') ~= '' and row.class_list or 'All',
                svFire = row.svfire,
                svCold = row.svcold,
                svDisease = row.svdisease,
                svPoison = row.svpoison,
                svCorruption = row.svcorruption,
                svMagic = row.svmagic,
                SpellDamage = row.spelldamage,
                SpellShield = row.spellshield,
                Damage = row.damage,
                Weight = row.weight / 10,
                Size = row.item_size,
                WeightReduction = row.weightreduction,
                Races = row.races,
                RaceList = row.race_list or 'All',
                Icon = row.icon,
                Attack = row.attack,
                Collectible = row.collectible == 1,
                StrikeThrough = row.strikethrough,
                HeroicAGI = row.heroicagi,
                HeroicCHA = row.heroiccha,
                HeroicDEX = row.heroicdex,
                HeroicINT = row.heroicint,
                HeroicSTA = row.heroicsta,
                HeroicSTR = row.heroicstr,
                HeroicSvCold = row.heroicsvcold,
                HeroicSvCorruption = row.heroicsvcorruption,
                HeroicSvDisease = row.heroicsvdisease,
                HeroicSvFire = row.heroicsvfire,
                HeroicSvMagic = row.heroicsvmagic,
                HeroicSvPoison = row.heroicsvpoison,
                HeroicWIS = row.heroicwis,
                Link = row.link,
            }
            LNS.ALLITEMS[id] = itemData
            LNS.ItemNames[id] = row.name
            LNS.ItemIcons[id] = row.icon
            LNS.ItemLinks[id] = row.link
            rowsFetched = rowsFetched + 1
            if LNS.TempSettings.SearchResults == nil then
                LNS.TempSettings.SearchResults = {}
            end
            table.insert(LNS.TempSettings.SearchResults, { id = id, data = itemData, })
        end
    end
    Logger.Info(LNS.guiLoot.console, "loot.GetItemFromDB() \agFound \ay%d\ax items matching the query: \ay%s\ax", rowsFetched, query)
    stmt:finalize()
    if noDBConnection then
        db:close()
    end
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
    Logger.Info(LNS.guiLoot.console, "\at%s \axImported \ag%d\ax items from \aoInventory\ax, and \ag%d\ax items from the \ayBank\ax, into the DB", MyName, counter, counterBank)
    LNS.report(string.format("%s Imported %d items from Inventory, and %d items from the Bank, into the DB", MyName, counter, counterBank))
    LNS.send({
        who = MyName,
        Server = eqServer,
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
    local itemID                            = item.ID()
    local itemName                          = item.Name()
    local itemIcon                          = item.Icon()
    local value                             = item.Value() or 0
    LNS.ItemNames[itemID]                   = itemName
    LNS.ItemIcons[itemID]                   = itemIcon

    LNS.ALLITEMS[itemID]                    = {}
    LNS.ALLITEMS[itemID].Name               = item.Name()
    LNS.ALLITEMS[itemID].NoDrop             = item.NoDrop()
    LNS.ALLITEMS[itemID].NoTrade            = item.NoTrade()
    LNS.ALLITEMS[itemID].Tradeskills        = item.Tradeskills()
    LNS.ALLITEMS[itemID].Quest              = item.Quest()
    LNS.ALLITEMS[itemID].Lore               = item.Lore()
    LNS.ALLITEMS[itemID].Augment            = item.AugType() > 0
    LNS.ALLITEMS[itemID].Stackable          = item.Stackable()
    LNS.ALLITEMS[itemID].Value              = LNS.valueToCoins(value) or 0
    LNS.ALLITEMS[itemID].Tribute            = item.Tribute() or 0
    LNS.ALLITEMS[itemID].StackSize          = item.StackSize() or 0
    LNS.ALLITEMS[itemID].Clicky             = item.Clicky() or nil
    LNS.ALLITEMS[itemID].AugType            = item.AugType() or 0
    LNS.ALLITEMS[itemID].strength           = item.STR() or 0
    LNS.ALLITEMS[itemID].DEX                = item.DEX() or 0
    LNS.ALLITEMS[itemID].AGI                = item.AGI() or 0
    LNS.ALLITEMS[itemID].STA                = item.STA() or 0
    LNS.ALLITEMS[itemID].INT                = item.INT() or 0
    LNS.ALLITEMS[itemID].WIS                = item.WIS() or 0
    LNS.ALLITEMS[itemID].CHA                = item.CHA() or 0
    LNS.ALLITEMS[itemID].Mana               = item.Mana() or 0
    LNS.ALLITEMS[itemID].HP                 = item.HP() or 0
    LNS.ALLITEMS[itemID].AC                 = item.AC() or 0
    LNS.ALLITEMS[itemID].HPRegen            = item.HPRegen() or 0
    LNS.ALLITEMS[itemID].ManaRegen          = item.ManaRegen() or 0
    LNS.ALLITEMS[itemID].Haste              = item.Haste() or 0
    LNS.ALLITEMS[itemID].Link               = item.ItemLink('CLICKABLE')() or 'NULL'
    LNS.ALLITEMS[itemID].Weight             = (item.Weight() or 0) * 10
    LNS.ALLITEMS[itemID].Classes            = item.Classes() or 0
    LNS.ALLITEMS[itemID].ClassList          = LNS.retrieveClassList(item)
    LNS.ALLITEMS[itemID].svFire             = item.svFire() or 0
    LNS.ALLITEMS[itemID].svCold             = item.svCold() or 0
    LNS.ALLITEMS[itemID].svDisease          = item.svDisease() or 0
    LNS.ALLITEMS[itemID].svPoison           = item.svPoison() or 0
    LNS.ALLITEMS[itemID].svCorruption       = item.svCorruption() or 0
    LNS.ALLITEMS[itemID].svMagic            = item.svMagic() or 0
    LNS.ALLITEMS[itemID].SpellDamage        = item.SpellDamage() or 0
    LNS.ALLITEMS[itemID].SpellShield        = item.SpellShield() or 0
    LNS.ALLITEMS[itemID].Races              = item.Races() or 0
    LNS.ALLITEMS[itemID].RaceList           = LNS.retrieveRaceList(item)
    LNS.ALLITEMS[itemID].Collectible        = item.Collectible()
    LNS.ALLITEMS[itemID].Attack             = item.Attack() or 0
    LNS.ALLITEMS[itemID].Damage             = item.Damage() or 0
    LNS.ALLITEMS[itemID].WeightReduction    = item.WeightReduction() or 0
    LNS.ALLITEMS[itemID].Size               = item.Size() or 0
    LNS.ALLITEMS[itemID].Icon               = itemIcon
    LNS.ALLITEMS[itemID].StrikeThrough      = item.StrikeThrough() or 0
    LNS.ALLITEMS[itemID].HeroicAGI          = item.HeroicAGI() or 0
    LNS.ALLITEMS[itemID].HeroicCHA          = item.HeroicCHA() or 0
    LNS.ALLITEMS[itemID].HeroicDEX          = item.HeroicDEX() or 0
    LNS.ALLITEMS[itemID].HeroicINT          = item.HeroicINT() or 0
    LNS.ALLITEMS[itemID].HeroicSTA          = item.HeroicSTA() or 0
    LNS.ALLITEMS[itemID].HeroicSTR          = item.HeroicSTR() or 0
    LNS.ALLITEMS[itemID].HeroicSvCold       = item.HeroicSvCold() or 0
    LNS.ALLITEMS[itemID].HeroicSvCorruption = item.HeroicSvCorruption() or 0
    LNS.ALLITEMS[itemID].HeroicSvDisease    = item.HeroicSvDisease() or 0
    LNS.ALLITEMS[itemID].HeroicSvFire       = item.HeroicSvFire() or 0
    LNS.ALLITEMS[itemID].HeroicSvMagic      = item.HeroicSvMagic() or 0
    LNS.ALLITEMS[itemID].HeroicSvPoison     = item.HeroicSvPoison() or 0
    LNS.ALLITEMS[itemID].HeroicWIS          = item.HeroicWIS() or 0
    LNS.ItemLinks[itemID]                   = item.ItemLink('CLICKABLE')() or 'NULL'

    -- insert the item into the database

    local db                                = SQLite3.open(lootDB)

    if not db then
        Logger.Error(LNS.guiLoot.console, "\arFailed to open\ax loot database.")
        return
    end
    db:exec("PRAGMA journal_mode=WAL;")
    local sql  = [[
INSERT INTO Items (
item_id, name, nodrop, notrade, tradeskill, quest, lore, augment,
stackable, sell_value, tribute_value, stack_size, clickable, augtype,
strength, dexterity, agility, stamina, intelligence, wisdom,
charisma, mana, hp, ac, regen_hp, regen_mana, haste, link, weight, classes, class_list,
svfire, svcold, svdisease, svpoison, svcorruption, svmagic, spelldamage, spellshield, races, race_list, collectible,
attack, damage, weightreduction, item_size, icon, strikethrough, heroicagi, heroiccha, heroicdex, heroicint,
heroicsta, heroicstr, heroicsvcold, heroicsvcorruption, heroicsvdisease, heroicsvfire, heroicsvmagic, heroicsvpoison,
heroicwis
)
VALUES (
?,?,?,?,?,?,?,?,?,?,
?,?,?,?,?,?,?,?,?,?,
?,?,?,?,?,?,?,?,?,?,
?,?,?,?,?,?,?,?,?,?,
?,?,?,?,?,?,?,?,?,?,
?,?,?,?,?,?,?,?,?,?,
?
)
ON CONFLICT(item_id) DO UPDATE SET
name                                    = excluded.name,
nodrop                                    = excluded.nodrop,
notrade                                    = excluded.notrade,
tradeskill                                    = excluded.tradeskill,
quest                                    = excluded.quest,
lore                                    = excluded.lore,
augment                                    = excluded.augment,
stackable                                    = excluded.stackable,
sell_value                                    = excluded.sell_value,
tribute_value                                    = excluded.tribute_value,
stack_size                                    = excluded.stack_size,
clickable                                    = excluded.clickable,
augtype                                    = excluded.augtype,
strength                                    = excluded.strength,
dexterity                                    = excluded.dexterity,
agility                                    = excluded.agility,
stamina                                    = excluded.stamina,
intelligence                                    = excluded.intelligence,
wisdom                                    = excluded.wisdom,
charisma                                    = excluded.charisma,
mana                                    = excluded.mana,
hp                                    = excluded.hp,
ac                                    = excluded.ac,
regen_hp                                    = excluded.regen_hp,
regen_mana                                    = excluded.regen_mana,
haste                                    = excluded.haste,
link                                    = excluded.link,
weight                                    = excluded.weight,
item_size                                    = excluded.item_size,
classes                                    = excluded.classes,
class_list                                    = excluded.class_list,
svfire                                    = excluded.svfire,
svcold                                    = excluded.svcold,
svdisease                                    = excluded.svdisease,
svpoison                                    = excluded.svpoison,
svcorruption                                    = excluded.svcorruption,
svmagic                                    = excluded.svmagic,
spelldamage                                    = excluded.spelldamage,
spellshield                                    = excluded.spellshield,
races                                    = excluded.races,
race_list                               = excluded.race_list,
collectible                                    = excluded.collectible,
attack                                    = excluded.attack,
damage                                    = excluded.damage,
weightreduction                                    = excluded.weightreduction,
strikethrough                                    = excluded.strikethrough,
heroicagi                                    = excluded.heroicagi,
heroiccha                                    = excluded.heroiccha,
heroicdex                                    = excluded.heroicdex,
heroicint                                    = excluded.heroicint,
heroicsta                                    = excluded.heroicsta,
heroicstr                                    = excluded.heroicstr,
heroicsvcold                                    = excluded.heroicsvcold,
heroicsvcorruption                                    = excluded.heroicsvcorruption,
heroicsvdisease                                    = excluded.heroicsvdisease,
heroicsvfire                                    = excluded.heroicsvfire,
heroicsvmagic                                    = excluded.heroicsvmagic,
heroicsvpoison                                    = excluded.heroicsvpoison,
heroicwis                                    = excluded.heroicwis
]]
    local stmt = db:prepare(sql)
    if not stmt then
        Logger.Error(LNS.guiLoot.console, "\arFailed to prepare \ax[\ayINSERT\ax] \aoSQL\ax statement: \at%s", db:errmsg())
        db:close()
        return
    end

    local success, errmsg = pcall(function()
        stmt:bind_values(
            itemID,
            itemName,
            LNS.ALLITEMS[itemID].NoDrop and 1 or 0,
            LNS.ALLITEMS[itemID].NoTrade and 1 or 0,
            LNS.ALLITEMS[itemID].Tradeskills and 1 or 0,
            LNS.ALLITEMS[itemID].Quest and 1 or 0,
            LNS.ALLITEMS[itemID].Lore and 1 or 0,
            LNS.ALLITEMS[itemID].Augment and 1 or 0,
            LNS.ALLITEMS[itemID].Stackable and 1 or 0,
            value,
            LNS.ALLITEMS[itemID].Tribute,
            LNS.ALLITEMS[itemID].StackSize,
            LNS.ALLITEMS[itemID].Clicky,
            LNS.ALLITEMS[itemID].AugType,
            LNS.ALLITEMS[itemID].strength,
            LNS.ALLITEMS[itemID].DEX,
            LNS.ALLITEMS[itemID].AGI,
            LNS.ALLITEMS[itemID].STA,
            LNS.ALLITEMS[itemID].INT,
            LNS.ALLITEMS[itemID].WIS,
            LNS.ALLITEMS[itemID].CHA,
            LNS.ALLITEMS[itemID].Mana,
            LNS.ALLITEMS[itemID].HP,
            LNS.ALLITEMS[itemID].AC,
            LNS.ALLITEMS[itemID].HPRegen,
            LNS.ALLITEMS[itemID].ManaRegen,
            LNS.ALLITEMS[itemID].Haste,
            LNS.ALLITEMS[itemID].Link,
            LNS.ALLITEMS[itemID].Weight,
            LNS.ALLITEMS[itemID].Classes,
            LNS.ALLITEMS[itemID].ClassList,
            LNS.ALLITEMS[itemID].svFire,
            LNS.ALLITEMS[itemID].svCold,
            LNS.ALLITEMS[itemID].svDisease,
            LNS.ALLITEMS[itemID].svPoison,
            LNS.ALLITEMS[itemID].svCorruption,
            LNS.ALLITEMS[itemID].svMagic,
            LNS.ALLITEMS[itemID].SpellDamage,
            LNS.ALLITEMS[itemID].SpellShield,
            LNS.ALLITEMS[itemID].Races,
            LNS.ALLITEMS[itemID].RaceList,
            LNS.ALLITEMS[itemID].Collectible and 1 or 0,
            LNS.ALLITEMS[itemID].Attack,
            LNS.ALLITEMS[itemID].Damage,
            LNS.ALLITEMS[itemID].WeightReduction,
            LNS.ALLITEMS[itemID].Size,
            itemIcon,
            LNS.ALLITEMS[itemID].StrikeThrough,
            LNS.ALLITEMS[itemID].HeroicAGI,
            LNS.ALLITEMS[itemID].HeroicCHA,
            LNS.ALLITEMS[itemID].HeroicDEX,
            LNS.ALLITEMS[itemID].HeroicINT,
            LNS.ALLITEMS[itemID].HeroicSTA,
            LNS.ALLITEMS[itemID].HeroicSTR,
            LNS.ALLITEMS[itemID].HeroicSvCold,
            LNS.ALLITEMS[itemID].HeroicSvCorruption,
            LNS.ALLITEMS[itemID].HeroicSvDisease,
            LNS.ALLITEMS[itemID].HeroicSvFire,
            LNS.ALLITEMS[itemID].HeroicSvMagic,
            LNS.ALLITEMS[itemID].HeroicSvPoison,
            LNS.ALLITEMS[itemID].HeroicWIS)
        stmt:step()
    end)

    if not success then
        Logger.Error(LNS.guiLoot.console, "Error executing SQL statement: %s", errmsg)
    end
    db:exec("BEGIN TRANSACTION")
    stmt:finalize()
    db:exec("COMMIT")
    db:close()
end

--- Resolve a set of item names to IDs, ignoring not unique matches.
--- @param namesTable table A set of item names as keys (e.g., {["Sword"]=true})
--- @return table A map of item names to item_id (only if exactly one match)
function LNS.ResolveItemIDs(namesTable)
    local resolved = {}
    local seenCount = {}

    local db = LNS.OpenItemsSQL()
    local stmt = db:prepare("SELECT item_id, name FROM Items")
    for row in stmt:nrows() do
        if namesTable[row.name] then
            seenCount[row.name] = (seenCount[row.name] or 0) + 1
            if seenCount[row.name] == 1 then
                resolved[row.name] = row.item_id
            else
                resolved[row.name] = nil -- not unique
            end
        end
    end
    stmt:finalize()
    db:close()

    return resolved
end

--- Finds matching items in the Items DB by name or ID.
--- @param itemName string|nil The item name to match
--- @param itemId number|nil The item ID to match
--- @param exact boolean|nil If true, performs exact name match
--- @param maxResults number|nil Limit number of results returned (default 20)
--- @return number counter The number of items found
--- @return table retTable A table of item data indexed by item_id
function LNS.findItemInDb(itemName, itemId, exact, maxResults)
    local db = LNS.OpenItemsSQL()
    local counter = 0
    local retTable = {}
    if not db then return counter, retTable end

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
        db:close()
        return 0, {}
    end

    db:exec("BEGIN TRANSACTION")
    local stmt = db:prepare(query)
    if param then stmt:bind_values(param) end

    for row in stmt:nrows() do
        counter = counter + 1
        if counter <= maxResults then
            retTable[row.item_id] = {
                item_id      = row.item_id,
                item_name    = row.name,
                item_classes = row.item_rule_classes or 'All',
                item_link    = row.link or 'NULL',
            }
        end

        LNS.ItemLinks[row.item_id] = row.link or 'NULL'
    end

    stmt:finalize()
    db:exec("COMMIT")
    db:close()

    if counter >= maxResults then
        Logger.Info(LNS.guiLoot.console, "\aoMore than\ax \ay%d\ax items found, showing only first\ax \at%d\ax.", counter, maxResults)
    end

    return counter, retTable
end

---comment
---@param item_table table Index of ItemId's to set
---@param setting any Setting to set all items to
---@param classes any Classes to set all items to
---@param which_table string Which Rules table
---@param delete_items boolean Delete items from the table
function LNS.bulkSet(item_table, setting, classes, which_table, delete_items)
    if item_table == nil or type(item_table) ~= "table" then return end
    if which_table == 'Personal_Rules' then which_table = LNS.PersonalTableName end
    local localName = which_table == 'Normal_Rules' and 'NormalItems' or 'GlobalItems'
    localName = which_table == LNS.PersonalTableName and 'PersonalItems' or localName

    local db = SQLite3.open(RulesDB)
    if not db then return end
    db:exec("PRAGMA journal_mode=WAL;")

    local qry = string.format([[
INSERT INTO %s (item_id, item_name, item_rule, item_rule_classes, item_link)
VALUES (?, ?, ?, ?, ?)
ON CONFLICT(item_id) DO UPDATE SET
item_name = excluded.item_name,
item_rule = excluded.item_rule,
item_rule_classes = excluded.item_rule_classes,
item_link = excluded.item_link;
]], which_table)
    if delete_items then
        qry = string.format([[
DELETE FROM %s WHERE item_id = ?;
]], which_table)
    end
    local stmt = db:prepare(qry)
    if not stmt then
        db:close()
        return
    end

    db:exec("BEGIN TRANSACTION;")

    for itemID, data in pairs(item_table) do
        local itemName = LNS.ItemNames[itemID] or nil
        local itemLink = data.Link
        Logger.Debug(LNS.guiLoot.console, "\nQuery: %s\ayValues\ax: itemID (\at%s\ax) itemName (\ay%s\ax), setting (\at%s)", qry, itemID, itemName, item_table[itemID].Rule)

        if itemName then
            if not delete_items then
                stmt:bind_values(itemID, itemName, item_table[itemID].Rule, classes, itemLink)
                stmt:step()
                stmt:reset()
                LNS[localName .. 'Rules'][itemID] = item_table[itemID].Rule
                LNS[localName .. 'Classes'][itemID] = classes
            else
                stmt:bind_values(itemID)
                stmt:step()
                stmt:reset()
                LNS[localName .. 'Rules'][itemID] = nil
                LNS[localName .. 'Classes'][itemID] = nil
            end
        end
    end

    db:exec("COMMIT;")
    stmt:finalize()
    db:close()
    if localName ~= 'PersonalItems' then
        LNS.TempSettings.NeedSave = true
        LNS.send({
            action = 'reloadrules',
            who = MyName,
            Server = eqServer,
            bulkLabel = localName,
            bulkRules = LNS[localName .. 'Rules'],
            bulkClasses = LNS[localName .. 'Classes'],
            bulkLink = LNS.ItemLinks,
        })
    end
    LNS.TempSettings.BulkSet = {}
end

function LNS.UpdateRuleLink(itemID, link, which_table)
    local localName = which_table == 'Normal_Rules' and 'NormalItems' or 'GlobalItems'
    localName = which_table == LNS.PersonalTableName and 'PersonalItems' or localName

    local alreadyMatched = false

    local db = SQLite3.open(RulesDB)
    if not db then return end
    db:exec("PRAGMA journal_mode=WAL;")
    -- grab the link from the db and if it doesn't match then update it
    if not link or link == 'NULL' or link == '' then
        Logger.Warn(LNS.guiLoot.console, "\arLink is \ax[\ayNULL\ax] for itemID: %d", itemID)
        return
    end
    local qry = string.format("SELECT item_link FROM %s WHERE item_id = ?", which_table)

    -- local qry = string.format([[UPDATE %s SET item_link = ? WHERE item_id = ?;]], which_table)
    local stmt = db:prepare(qry)
    stmt:bind_values(itemID)

    if not stmt then
        db:close()
        return
    end
    for row in stmt:nrows() do
        if row.item_link and row.item_link == link then
            alreadyMatched = true
        end
    end
    stmt:finalize()

    if not alreadyMatched then
        qry = string.format([[UPDATE %s SET item_link = ? WHERE item_id = ?;]], which_table)
        db:exec("BEGIN TRANSACTION;")
        stmt = db:prepare(qry)
        if not stmt then
            db:close()
            return
        end
        stmt:bind_values(link, itemID)
        stmt:step()
        stmt:reset()
        db:exec("COMMIT;")
        stmt:finalize()

        LNS.ItemLinks[itemID] = link
        Logger.Debug(LNS.guiLoot.console, "\aoUpdated link for\ax\at %d\ax to %s", itemID, link)
    else
        LNS.ItemLinks[itemID] = link
        LNS.ALLITEMS[itemID] = LNS.ALLITEMS[itemID] or {}
        LNS.ALLITEMS[itemID].Link = link
        Logger.Debug(LNS.guiLoot.console, "\aoLink for\ax\at %d\ax \agALREADY MATCHES %s", itemID, link)
    end
    db:close()
end

------------------------------------
--         RULES FUNCTIONS
------------------------------------


---@param mq_item MQItem|nil
---@param itemID any
---@param tablename any|nil
---@param item_link string|nil
---@return string rule
---@return string classes
---@return string link
---@return string which_table
function LNS.lookupLootRule(mq_item, itemID, tablename, item_link)
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

    if item_link and item_link ~= link and LNS.ALLITEMS[itemID] then
        LNS.ALLITEMS[itemID].Link = item_link
    end

    LNS.ItemLinks[itemID] = item_link and (item_link ~= (LNS.ItemLinks[itemID] or '0') and item_link or LNS.ItemLinks[itemID]) or (LNS.ItemLinks[itemID] or 'NULL')

    if tablename == nil then
        if LNS.PersonalItemsRules[itemID] then
            if link ~= 'NULL' or (item_link and link ~= item_link) then
                LNS.UpdateRuleLink(itemID, LNS.ItemLinks[itemID], LNS.PersonalTableName)
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
    elseif tablename == 'Global_Rules' then
        if LNS.GlobalItemsRules[itemID] then
            if link ~= 'NULL' or (item_link and link ~= item_link) then
                LNS.UpdateRuleLink(itemID, LNS.ItemLinks[itemID], 'Global_Rules')
            end
            return LNS.GlobalItemsRules[itemID], LNS.GlobalItemsClasses[itemID], LNS.ItemLinks[itemID], 'Global'
        end
    elseif tablename == 'Normal_Rules' then
        if LNS.NormalItemsRules[itemID] then
            if link ~= 'NULL' or (item_link and link ~= item_link) then
                LNS.UpdateRuleLink(itemID, LNS.ItemLinks[itemID], 'Normal_Rules')
            end
            return LNS.NormalItemsRules[itemID], LNS.NormalItemsClasses[itemID], LNS.ItemLinks[itemID], 'Normal'
        end
    elseif tablename == LNS.PersonalTableName then
        if LNS.PersonalItemsRules[itemID] then
            if link ~= 'NULL' or (item_link and link ~= item_link) then
                LNS.UpdateRuleLink(itemID, LNS.ItemLinks[itemID], LNS.PersonalTableName)
            end
            return LNS.PersonalItemsRules[itemID], LNS.PersonalItemsClasses[itemID], LNS.ItemLinks[itemID], 'Personal'
        end
    end

    -- check SQLite DB if lua tables don't have the data
    local function checkDB(id, tbl)
        local db = SQLite3.open(RulesDB)
        local found = false
        if not db then
            Logger.Warn(LNS.guiLoot.console, "\atSQL \arFailed\ax to open \atRulesDB:\ax for \aolookupLootRule\ax.")
            return found, 'NULL', 'All', 'NULL'
        end
        db:exec("PRAGMA journal_mode=WAL;")
        local sql  = string.format("SELECT item_rule, item_rule_classes, item_link FROM %s WHERE item_id = ?", tbl)
        local stmt = db:prepare(sql)

        if not stmt then
            Logger.Warn(LNS.guiLoot.console, "\atSQL \arFAILED \axto prepare statement for \atlookupLootRule\ax.")
            db:close()
            return found, 'NULL', 'All', 'NULL'
        end

        stmt:bind_values(id)
        local stepResult = stmt:step()

        local rule       = 'NULL'
        local classes    = 'None'
        local returnLink = 'NULL'

        -- Extract values if a row is returned
        if stepResult == SQLite3.ROW then
            local row  = stmt:get_named_values()
            rule       = row.item_rule or 'NULL'
            classes    = row.item_rule_classes
            returnLink = row.item_link or (LNS.ItemLinks[id] or 'NULL')
            found      = true
        end
        if classes == nil then classes = 'None' end
        local tmpClass = string.gsub(classes, " ", '')
        if classes == 'None' or tmpClass == '' then
            classes = 'All'
        end
        -- Finalize the statement and close the database
        stmt:finalize()
        db:close()
        return found, rule, classes, returnLink
    end

    local rule       = 'NULL'
    local classes    = (mq_item and mq_item()) and LNS.retrieveClassList(mq_item) or 'NULL'
    local lookupLink = 'NULL'

    if tablename == nil then
        -- check global rules
        local found = false
        found, rule, classes, lookupLink = checkDB(itemID, LNS.PersonalTableName)
        which_table = 'Personal'
        if not found then
            found, rule, classes, lookupLink = checkDB(itemID, 'Global_Rules')
            which_table = 'Global'
        end
        if not found then
            found, rule, classes, lookupLink = checkDB(itemID, 'Normal_Rules')
            which_table = 'Normal'
        end

        if not found then
            rule = 'NULL'
            classes = 'None'
            lookupLink = 'NULL'
        end
    else
        _, rule, classes, lookupLink = checkDB(itemID, tablename)
    end

    -- if SQL has the item add the rules to the lua table for next time

    if rule ~= 'NULL' then
        local localTblName                     = tablename == 'Global_Rules' and 'GlobalItems' or 'NormalItems'
        localTblName                           = tablename == LNS.PersonalTableName and 'PersonalItems' or localTblName

        LNS[localTblName .. 'Rules'][itemID]   = rule
        LNS[localTblName .. 'Classes'][itemID] = classes
        LNS.ItemLinks[itemID]                  = lookupLink
        LNS.ItemNames[itemID]                  = LNS.ALLITEMS[itemID].Name
    end
    return rule, classes, lookupLink, which_table
end

function LNS.addNewItem(corpseItem, itemRule, itemLink, corpseID, addDB)
    if corpseItem == nil or itemRule == nil then
        Logger.Warn(LNS.guiLoot.console, "\aoInvalid parameters for addNewItem:\ax corpseItem=\at%s\ax, itemRule=\ag%s",
            tostring(corpseItem), tostring(itemRule))
        return
    end
    if LNS.TempSettings.NewItemIDs == nil then
        LNS.TempSettings.NewItemIDs = {}
    end
    -- Retrieve the itemID from corpseItem
    local itemID = corpseItem.ID()
    local itemName = corpseItem.Name()
    if not itemID then
        Logger.Warn(LNS.guiLoot.console, "\arFailed to retrieve \axitemID\ar for corpseItem:\ax %s", itemName)
        return
    end
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
        Classes    = LNS.TempItemClasses,
        Races      = LNS.TempItemRaces,
        CorpseID   = corpseID,
    }
    table.insert(LNS.TempSettings.NewItemIDs, itemID)

    -- Increment the count of new items
    -- LNS.NewItemsCount = LNS.NewItemsCount + 1
    LNS.NewItemsCount = #LNS.TempSettings.NewItemIDs or 0

    if LNS.Settings.AutoShowNewItem then
        showNewItem = true
    end

    -- Notify the loot actor of the new item
    Logger.Info(LNS.guiLoot.console, "\agNew Loot\ay Item Detected! \ax[\at %s\ax ]\ao Sending actors", itemName)
    local newMessage = {
        who        = MyName,
        action     = 'new',
        item       = itemName,
        itemID     = itemID,
        Server     = eqServer,
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
        corpse     = corpseID,

    }

    Logger.Info(LNS.guiLoot.console, "\agAdding 1 \ayNEW\ax item: \at%s \ay(\axID: \at%s\at) \axwith rule: \ag%s", itemName, itemID, itemRule)
    -- LNS.actorAddRule(itemID, itemName, 'Normal', itemRule, LNS.TempItemClasses, itemLink)
    if addDB then
        LNS.addRule(itemID, 'NormalItems', itemRule, LNS.TempItemClasses, itemLink)
    end
    -- if LNS.Settings.AlwaysGlobal then
    --     LNS.addRule(itemID, 'GlobalItems', itemRule, LNS.TempItemClasses, itemLink)
    -- end
    LNS.send(newMessage)
end

---comment: Takes in an item to modify the rules for, You can add, delete, or modify the rules for an item.
---Upon completeion it will notify the loot actor to update the loot settings, for any other character that is using the loot actor.
---@param itemID integer The ID for the item we are modifying
---@param action string The action to perform (add, delete, modify)
---@param tableName string The table to modify
---@param classes string The classes to apply the rule to
---@param link string|nil The item link if available for the item
function LNS.modifyItemRule(itemID, action, tableName, classes, link)
    if not itemID or not tableName or not action then
        Logger.Warn(LNS.guiLoot.console, "Invalid parameters for modifyItemRule. itemID: %s, tableName: %s, action: %s",
            tostring(itemID), tostring(tableName), tostring(action))
        return
    end

    local section = tableName == "Normal_Rules" and "NormalItems" or "GlobalItems"
    section = tableName == LNS.PersonalTableName and 'PersonalItems' or section
    -- Validate RulesDB
    if not RulesDB or type(RulesDB) ~= "string" then
        Logger.Warn(LNS.guiLoot.console, "Invalid RulesDB path: %s", tostring(RulesDB))
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
    classes  = classes or 'All'

    -- Open the database
    local db = SQLite3.open(RulesDB)
    if not db then
        Logger.Warn(LNS.guiLoot.console, "Failed to open database.")
        return
    end

    local stmt
    local sql
    db:exec("PRAGMA journal_mode=WAL;")
    db:exec("BEGIN TRANSACTION")
    if action == 'delete' then
        -- DELETE operation
        Logger.Info(LNS.guiLoot.console, "\aoloot.modifyItemRule\ax \arDeleting rule\ax for item \at%s\ax in table \at%s", itemName, tableName)
        sql = string.format("DELETE FROM %s WHERE item_id = ?", tableName)
        stmt = db:prepare(sql)

        if stmt then
            stmt:bind_values(itemID)
        end
    else
        -- UPSERT operation
        -- if tableName == "Normal_Rules" then
        sql  = string.format([[
INSERT INTO %s
(item_id, item_name, item_rule, item_rule_classes, item_link)
VALUES (?, ?, ?, ?, ?)
ON CONFLICT(item_id) DO UPDATE SET
item_name                                    = excluded.item_name,
item_rule                                    = excluded.item_rule,
item_rule_classes                                    = excluded.item_rule_classes,
item_link                                    = excluded.item_link
]], tableName)
        stmt = db:prepare(sql)
        if stmt then
            stmt:bind_values(itemID, itemName, action, classes, link)
        end
    end

    if not stmt then
        Logger.Warn(LNS.guiLoot.console, "Failed to prepare SQL statement for table: %s, item:%s (%s), rule: %s, classes: %s", tableName, itemName, itemID, action, classes)
        db:close()
        return
    end

    -- Execute the statement
    local success, errmsg = pcall(function() stmt:step() end)
    if not success then
        Logger.Warn(LNS.guiLoot.console, "Failed to execute SQL statement for table %s. Error: %s", tableName, errmsg)
    else
        Logger.Debug(LNS.guiLoot.console, "SQL statement executed successfully for item %s in table %s.", itemName, tableName)
    end

    -- Finalize and close the database
    stmt:finalize()
    db:exec("COMMIT")
    db:close()

    if success then
        -- Notify other actors about the rule change
        LNS.send({
            who     = MyName,
            Server  = eqServer,
            action  = action ~= 'delete' and 'addrule' or 'deleteitem',
            item    = itemName,
            itemID  = itemID,
            rule    = action,
            section = section,
            link    = link,
            classes = classes,
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
function LNS.addRule(itemID, section, rule, classes, link)
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

    -- Update the in-memory data structure
    LNS.ItemNames[itemID]             = itemName

    LNS[section .. "Rules"][itemID]   = rule
    LNS[section .. "Classes"][itemID] = classes
    LNS.ItemLinks[itemID]             = link
    local tblName                     = section == 'GlobalItems' and 'Global_Rules' or 'Normal_Rules'
    if section == 'PersonalItems' then
        tblName = LNS.PersonalTableName
    end
    LNS.modifyItemRule(itemID, rule, tblName, classes, link)
    if LNS.Settings.AlwaysGlobal and section == 'NormalItems' then
        LNS.modifyItemRule(itemID, rule, 'Global_Rules', classes, link)
    end

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

    local foundItems = LNS.GetItemFromDB(itemName, 0, false, nil, exactMatch)
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

    if not allowDuplicates then
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
    if not stackable and sellPrice < LNS.Settings.MinSellPrice then newDecision = "Ignore" end
    if not stackable and LNS.Settings.StackableOnly then newDecision = "Ignore" end
    if stackable and sellPrice * stackSize < LNS.Settings.StackPlatValue then newDecision = "Ignore" end
    if tributeValue >= LNS.Settings.MinTributeValue and sellPrice < LNS.Settings.MinSellPrice then newDecision = "Tribute" end
    if LNS.Settings.AutoTag and newDecision == "Keep" then
        if not stackable and sellPrice > LNS.Settings.MinSellPrice and not tsItem then
            newDecision = "Sell"
        end
        if stackable and sellPrice * stackSize >= LNS.Settings.StackPlatValue and not tsItem then
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

function LNS.checkWearable(isEqupiable, decision, ruletype, nodrop, newrule, isAug, item)
    local msgTbl = {}
    local iCanWear = false
    if isEqupiable then
        if ruletype ~= 'Personal' and ((LNS.Settings.CanWear and (decision == 'Keep' or decision == 'CanUse')) or
                (decision == 'Keep' or decision == 'CanUse') or (nodrop and newrule)) then
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
        if nodrop and LNS.Settings.CanWear and ruletype == 'Normal' and not isAug then
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
    if not LNS.Settings.LootQuest then
        Logger.Warn(LNS.guiLoot.console, "\aoQuest Item\ax Rule: (\ay%s\ax) is (\ardDISABLED\ax) in settings. Ignoring.", curRule)
        return 'Ignore', 0
    end

    local tmpDecision = "Quest"
    local qKeep = LNS.Settings.QuestKeep or 1
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
        table.insert(loreItems, itemLink)
        return 'Ignore', false
    end
    local ret = decision
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
    local alwaysAsk    = LNS.Settings.AlwaysAsk
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
        if LNS.findItemInDb(itemName) == 1 then
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
        if LNS.findItemInDb(itemName) == 1 then
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

    local lootRule, lootClasses, lootLink, ruletype = LNS.lookupLootRule(item, itemID, nil, itemLink)
    Logger.Info(LNS.guiLoot.console, "\ax\ao Lookup Rule \axItem: (\at%s\ax) ID: (\ag%s\ax) Rule: (\ay%s\ax) Classes: (\at%s\ax)",
        itemName, itemID, lootRule, lootClasses)
    -- check for always eval
    if LNS.Settings.AlwaysEval and ruletype == 'Normal' then
        if lootRule ~= "Quest" and lootRule ~= "Keep" and lootRule ~= "Destroy" and lootRule ~= 'CanUse' and lootRule ~= 'Ask' and lootRule ~= 'Bank' then
            lootRule = 'NULL'
        end
    end

    newRule = lootRule == 'NULL' or false

    ---- NEW RULES ----

    if newRule then
        Logger.Info(LNS.guiLoot.console, "\ax\ag NEW RULE Detected!\ax Item: (\at%s\ax)", itemName, lootRule)
        lootClasses = LNS.retrieveClassList(item)
        ruletype = 'Normal'
        local addToDB = true
        -- NODROP
        if isNoDrop then
            if not isEquippable then
                lootRule = "Ask"
            else
                lootRule = "CanUse"
            end
            addToDB = (LNS.Settings.LootNoDropNew and LNS.Settings.LootNoDrop) or false

            if not addToDB then
                lootRule = 'Ask'
                lootDecision = 'Ask'
                -- Logger.Info(LNS.guiLoot.console, "\ax\ag New Rule for \ayNODROP\ax Item: (\at%s\ax) Rule: (\ag%s\ax)",
                --     itemName, lootRule)
                return lootRule, 0, newRule, isEquippable
            else
                Logger.Info(LNS.guiLoot.console, "\ax\ag Setting New Rule\ax \ayNODROP\ax Item: (\at%s\ax) Rule: (\ag%s\ax)",
                    itemName, lootRule)
            end
            LNS.addNewItem(item, lootRule, itemLink, mq.TLO.Corpse.ID() or 0, addToDB)
        else
            if not isEquippable then
                if sellPrice > 0 then
                    lootRule = 'Sell'
                elseif tributeValue > 0 then
                    lootRule = 'Tribute'
                else
                    lootRule = 'Ask'
                end
            else
                lootRule = 'Keep'
            end
            Logger.Info(LNS.guiLoot.console, "\ax\agSetting NEW RULE\ax Item: (\at%s\ax) Rule: (\ag%s\ax)",
                itemName, lootRule)

            LNS.addNewItem(item, lootRule, itemLink, mq.TLO.Corpse.ID() or 0, addToDB)
        end
    end

    lootDecision = lootRule

    -- Handle AlwaysAsk setting
    if alwaysAsk then
        newRule = true
        lootDecision = "Ask"
        dbgTbl = {
            Lookup = '\ax\ag Check for ALWAYSASK',
            Decision = lootDecision,
            Classes = lootClasses,
            Item = itemName,
            Link = lootLink,
        }
        Logger.Debug(LNS.guiLoot.console, dbgTbl)
        LNS.addNewItem(item, lootRule, itemLink, mq.TLO.Corpse.ID() or 0, false)
        if LNS.Settings.MasterLooting and ruletype ~= 'Personal' then
            LNS.send({
                who = MyName,
                Server = eqServer,
                action = 'check_item',
                CorpseID = cID or 0,
            })
            mq.delay(5)
        end
        return lootDecision, 0, newRule, isEquippable
    end

    -- handle ignore and destroy rules
    if lootRule == 'Ignore' and not (LNS.Settings.DoDestroy and LNS.Settings.AlwaysDestroy) then
        Logger.Info(LNS.guiLoot.console, "\ax\aoRule\ax: (\ayIGNORE\ax) \aoSkipping\ax (\at%s\ax)", itemName)
        if LNS.Settings.MasterLooting and ruletype ~= 'Personal' then
            LNS.send({
                who = MyName,
                Server = eqServer,
                action = 'check_item',
                CorpseID = mq.TLO.Corpse.ID() or 0,
            })
            mq.delay(5)
        end
        return 'Ignore', 0, newRule, isEquippable
    elseif lootRule == 'Ignore' and LNS.Settings.DoDestroy and LNS.Settings.AlwaysDestroy then
        Logger.Info(LNS.guiLoot.console, "\ax\ao Rule\ax: (\ayIGNORE\ax) and (\ayALWAYS DESTROY\ax) \at%s\ax", itemName)
        if LNS.Settings.MasterLooting and ruletype ~= 'Personal' then
            LNS.send({
                who = MyName,
                Server = eqServer,
                action = 'check_item',
                CorpseID = mq.TLO.Corpse.ID() or 0,
            })
            mq.delay(5)
        end
        return 'Destroy', 0, newRule, isEquippable
    end

    if lootRule == 'Destroy' then
        Logger.Info(LNS.guiLoot.console, "\ax\ao Rule\ax: (\arDESTROY\ax) \at%s\ax", itemName)
        if LNS.Settings.MasterLooting and ruletype ~= 'Personal' then
            LNS.send({
                who = MyName,
                Server = eqServer,
                action = 'check_item',
                CorpseID = mq.TLO.Corpse.ID() or 0,
            })
            mq.delay(5)
        end
        return 'Destroy', 0, newRule, isEquippable
    end

    if LNS.Settings.StackableOnly and not stackable and not LNS.Settings.MasterLooting then
        Logger.Info(LNS.guiLoot.console, "\ax\ao Rule\ax: \aySTACKABLE ONLY\ax and item is \arNOT stackable \at%s\ax", itemName)

        return 'Ignore', 0, newRule, isEquippable
    end

    ---check lore
    if isLore then
        lootLore = countHave == 0
        if not lootLore and not LNS.Settings.MasterLooting then
            table.insert(loreItems, itemLink)
            Logger.Info(LNS.guiLoot.console, "\aoItem \ax(\at%s\ax) is \ayLORE\ax and I \aoHAVE\ax it. Ignoring.", itemName)
            return 'Ignore', 0, newRule, isEquippable
        end
    end

    --handle NoDrop
    if isNoDrop and not LNS.Settings.LootNoDrop and not LNS.Settings.MasterLooting then
        Logger.Info(LNS.guiLoot.console, "\axItem is \aoNODROP\ax \at%s\ax and LootNoDrop is \arNOT \axenabled\ax", itemName)
        table.insert(noDropItems, itemLink)
        return 'Ignore', 0, newRule, isEquippable
    end

    -- check Classes that can loot
    if ruletype ~= 'Personal' and lootRule ~= 'Sell' and
        lootRule ~= 'Ask' and lootRule ~= 'Tribute' and not (lootRule:find('Quest'))
        and not (LNS.Settings.KeepSpells and (itemName:find('Spell:') or itemName:find('Song:'))) and
        not (LNS.Settings.LootAugments and isAug) and not LNS.Settings.MasterLooting then
        Logger.Debug(LNS.guiLoot.console, "\ax\ag Checking Classes for Rule: \at%s\ax", lootRule)

        lootDecision = LNS.checkClasses(lootRule, lootClasses, fromFunction, newRule)

        if lootDecision == 'Ignore' then
            Logger.Info(LNS.guiLoot.console, "\ax\aoItem\ax (\ag%s\ax) Classes: (\at%s)\ax MyClass: (\ay%s\ax) Decision: (\at%s\ax)",
                itemName, lootClasses, LNS.MyClass, lootDecision)

            return lootDecision, qKeep, newRule, isEquippable
        end

        Logger.Info(LNS.guiLoot.console, "\ax\aoItem\ax (\ag%s\ax) Classes: (\at%s)\ax MyClass: (\ay%s\ax) Decision: (\at%s\ax)",
            itemName, lootClasses, LNS.MyClass, lootDecision)
    end

    if ((lootRule == 'Sell' or lootRule == 'Tribute') and ruletype == 'Normal') then
        Logger.Debug(LNS.guiLoot.console, "\ax\ag Checking Decision for \aySELL\ax or \ayTRIBUTE\ax: \at%s\ax", lootRule)
        lootDecision = LNS.checkDecision(item, lootRule)
    end

    -- check bag space
    if not (freeSpace > LNS.Settings.SaveBagSlots or (stackable and freeStack > 0)) and not LNS.Settings.MasterLooting then
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
    if LNS.Settings.LootAugments and isAug and ruletype == 'Normal' and not LNS.Settings.MasterLooting then
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
    if LNS.Settings.KeepSpells and LNS.checkSpells(itemName) and ruletype == 'Normal' and not LNS.Settings.MasterLooting then
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
    if string.find(lootRule, "Quest") and not LNS.Settings.MasterLooting then
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

    if LNS.Settings.MasterLooting and ((lootRule == 'Ignore' and ruletype ~= 'Personal') or lootDecision == 'Destroy') then
        LNS.send({
            who = MyName,
            Server = eqServer,
            action = 'check_item',
            CorpseID = mq.TLO.Corpse.ID() or 0,
        })
        mq.delay(5)

        return 'Ignore', qKeep, newRule, isEquippable
    elseif LNS.Settings.MasterLooting then
        LNS.InsertMasterLootList(itemName, cID, itemID, LNS.ItemLinks[itemID],
            isLore, isNoDrop, item.Value())

        mq.delay(5)
        return 'MasterLooter', qKeep, newRule, iCanUse
    end

    Logger.Debug(LNS.guiLoot.console, "\aoLEAVING getRule()\ax: Rule: \at%s\ax, \ayClasses\ax: \at%s\ax, Item: \ao%s\ax, ID: \ay%s\ax, \atLink: %s",
        lootDecision, lootClasses, itemName, itemID, lootLink)

    return lootDecision, qKeep, newRule, iCanUse
end

function LNS.setBuyItem(itemID, qty)
    LNS.BuyItemsTable[itemID] = qty
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
        LNS.GlobalItemsMissing[LNS.TempSettings.ModifyItemID] = nil
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
        LNS.NormalItemsMissing[LNS.TempSettings.ModifyItemID] = nil
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
    LNS.modifyItemRule(itemID, val, LNS.PersonalTableName, classes, link)
end

------------------------------------
--          ACTORS
------------------------------------

function LNS.send(message, mailbox)
    message.Server = eqServer
    if mailbox == 'loot_module' then
        LNS.lootActor:send({ mailbox = mailbox, script = LNS.DirectorScript, }, message)
    elseif mailbox == 'looted' then
        LNS.lootActor:send({ mailbox = mailbox, script = LNS.DirectorLNSPath or 'lootnscoot', }, message)
    else
        LNS.lootActor:send({ mailbox = 'lootnscoot', script = LNS.DirectorLNSPath or 'lootnscoot', }, message)
    end
end

function LNS.sendMySettings()
    LNS.Boxes[MyName] = LNS.Settings
    LNS.send({
        who             = MyName,
        action          = 'sendsettings',
        settings        = LNS.Settings,
        CorpsesToIgnore = lootedCorpses or {},
        CombatLooting   = LNS.Settings.CombatLooting,
        CorpseRadius    = LNS.Settings.CorpseRadius,
        LootMyCorpse    = LNS.Settings.LootMyCorpse,
        IgnoreNearby    = LNS.Settings.IgnoreMyNearCorpses,
        Server          = eqServer,
    })

    LNS.Boxes[MyName] = LNS.Settings

    LNS.TempSettings.LastSent = os.time()
end

function LNS.finishedLooting()
    if Mode == 'directed' then
        LNS.send({
            Subject = 'done_looting',
            Who = MyName,
            LNSSettings = LNS.Settings,
            CorpsesToIgnore = lootedCorpses or {},
            CombatLooting = LNS.Settings.CombatLooting,
            CorpseRadius = LNS.Settings.CorpseRadius,
            LootMyCorpse = LNS.Settings.LootMyCorpse,
            IgnoreNearby = LNS.Settings.IgnoreMyNearCorpses,
        }, 'loot_module')
    end
    LNS.LootNow = false
end

function LNS.informProcessing()
    if Mode == 'directed' then
        Logger.Info(LNS.guiLoot.console, "\ayInforming \ax\aw[\at%s\ax\aw]\ax that I am \agProcessing.", LNS.DirectorScript)
        LNS.send({
            Subject = "processing",
            Who = MyName,
            LNSSettings = LNS.Settings,
            Server = eqServer,
            CorpsesToIgnore = lootedCorpses or {},
            CombatLooting = LNS.Settings.CombatLooting,
            CorpseRadius = LNS.Settings.CorpseRadius,
            LootMyCorpse = LNS.Settings.LootMyCorpse,
            IgnoreNearby = LNS.Settings.IgnoreMyNearCorpses,
        }, 'loot_module')
    end
end

function LNS.doneProcessing()
    if Mode == 'directed' then
        Logger.Info(LNS.guiLoot.console, "\ayInforming \ax\aw[\at%s\ax\aw]\ax that I am \agDone Processing.", LNS.DirectorScript)
        LNS.send({
            Subject = "done_processing",
            Who = MyName,
            Server = eqServer,
            LNSSettings = LNS.Settings,
            CorpsesToIgnore = lootedCorpses or {},
            CombatLooting = LNS.Settings.CombatLooting,
            CorpseRadius = LNS.Settings.CorpseRadius,
            LootMyCorpse = LNS.Settings.LootMyCorpse,
            IgnoreNearby = LNS.Settings.IgnoreMyNearCorpses,
        }, 'loot_module')
    end
end

function LNS.GetTableSize(tbl)
    local count = 0
    if tbl == nil then return count end
    for _ in pairs(tbl) do
        count = count + 1
    end
    return count
end

function LNS.RegisterActors()
    LNS.lootActor = Actors.register('lootnscoot', function(message)
        local lootMessage = message()
        local server      = lootMessage.Server and lootMessage.Server or (lootMessage.server or 'NULL')
        if server ~= eqServer and server ~= 'NULL' then return end -- if they sent the server name then only answer if it matches our server

        local who           = lootMessage.who or ''
        local action        = lootMessage.action or ''
        local itemID        = lootMessage.itemID or 0
        local rule          = lootMessage.rule or 'NULL'
        local section       = lootMessage.section or 'NormalItems'
        local itemName      = lootMessage.item or 'NULL'
        local itemLink      = lootMessage.link or 'NULL'
        local itemClasses   = lootMessage.classes or 'All'
        local itemRaces     = lootMessage.races or 'All'
        local boxSettings   = lootMessage.settings or {}
        local directions    = lootMessage.directions or 'NULL'
        local combatLooting = lootMessage.CombatLooting
        local corpseradius  = lootMessage.CorpseRadius or LNS.Settings.CorpseRadius
        local lootmycorpse  = lootMessage.LootMyCorpse
        local ignorenearby  = lootMessage.IgnoreNearby
        if ignorenearby == nil then
            ignorenearby = LNS.Settings.IgnoreMyNearCorpses
        end
        if combatLooting == nil then
            combatLooting = LNS.Settings.CombatLooting
        end
        if lootmycorpse == nil then
            lootmycorpse = LNS.Settings.LootMyCorpse
        end
        local dbgTbl = {}
        dbgTbl       = {
            Lookup = 'loot.RegisterActors()',
            Event = '\ax\agReceived\ax message',
            Action = action,
            ItemID = itemID,
            Rule = rule,
            Classes = itemClasses,
            Directions = directions,
            Who = who,
            Link = itemLink,
            LNS_Mode = Mode,
        }

        ------- DEBUG MESSAGES PER SECOND ---------
        -- keep a running Average of the Total MPS (Messages Per Second)
        local now    = os.clock()
        if LNS.TempSettings.MPS == nil then
            LNS.TempSettings.MPS = 0
            LNS.TempSettings.MPSStart = now
            LNS.TempSettings.MPSCount = 0
            LNS.TempSettings.LastMsg = now
        end

        if now - LNS.TempSettings.LastMsg >= 10 then
            LNS.TempSettings.MPSStart = now
            LNS.TempSettings.MPSCount = 0
        end

        LNS.TempSettings.MPSCount = LNS.TempSettings.MPSCount + 1

        if now - LNS.TempSettings.MPSStart >= 1 then
            LNS.TempSettings.MPS = LNS.TempSettings.MPSCount / (now - LNS.TempSettings.MPSStart)
        else
            LNS.TempSettings.MPS = LNS.TempSettings.MPSCount
        end

        LNS.TempSettings.LastMsg = now

        if debugPrint then
            -- reset after 10 seconds of inactivity
            if LNS.TempSettings.MailBox == nil then
                LNS.TempSettings.MailBox = {}
            end
            local sub = ''
            if directions ~= nil and directions ~= 'NULL' then
                sub = directions
            elseif action ~= nil and action ~= 'NULL' then
                sub = action
            else
                sub = 'unknown'
            end
            table.insert(LNS.TempSettings.MailBox, {
                Time = string.format("%s.%s", os.date('%H:%M:%S'), string.format("%.3f", (os.clock() % 1)):gsub("0%.", '')),
                Subject = sub,
                Sender = who or 'unknown',
            })
            table.sort(LNS.TempSettings.MailBox, function(a, b)
                return a.Time > b.Time
            end)
        end
        ------------------------------------------


        if Mode == 'directed' and who == MyName then
            if directions == 'doloot' and (LNS.Settings.DoLoot or LNS.Settings.LootMyCorpse) and not LNS.LootNow then
                if os.time() - (LNS.TempSettings.DirectedLoot or 0) <= 2 then
                    LNS.TempSettings.DirectedLoot = os.time()
                    Logger.Debug(LNS.guiLoot.console, dbgTbl)
                end
                if lootMessage.limit then
                    LNS.TempSettings.LootLimit = lootMessage.limit
                end
                LNS.LootNow = true
                return
            end
            if directions == 'setsetting_directed' or directions == 'combatlooting' then
                dbgTbl['CombatLooting'] = combatLooting
                dbgTbl['CorpseRadius'] = corpseradius
                dbgTbl['LootMyCorpse'] = lootmycorpse
                dbgTbl['IgnoreNearby'] = ignorenearby
                Logger.Debug(LNS.guiLoot.console, dbgTbl)
                LNS.Settings.CombatLooting = combatLooting
                LNS.Settings.CorpseRadius = corpseradius
                LNS.Settings.LootMyCorpse = lootmycorpse
                LNS.Settings.IgnoreMyNearCorpses = ignorenearby
                LNS.Boxes[MyName] = LNS.Settings
                -- LNS.writeSettings()
                -- LNS.sendMySettings()
                LNS.TempSettings[MyName] = nil
                LNS.TempSettings.NeedSave = true
                return
            end
            if directions == 'getsettings_directed' or directions == 'getcombatsetting' then
                Logger.Debug(LNS.guiLoot.console, dbgTbl)
                LNS.send({
                    Subject = 'mysetting',
                    Who = MyName,
                    Server = eqServer,
                    LNSSettings = LNS.Settings,
                    CorpsesToIgnore = lootedCorpses or {},
                }, 'loot_module')
                LNS.TempSettings.SentSettings = true
                LNS.TempSettings.NeedSave = true
                return
            end
        end
        if itemName == 'NULL' then
            itemName = LNS.ItemNames[itemID] and LNS.ItemNames[itemID] or 'NULL'
        end
        if action == 'Hello' and who ~= MyName then
            LNS.TempSettings.SendSettings = true
            LNS.TempSettings[who] = {}
            table.insert(LNS.BoxKeys, who)
            table.sort(LNS.BoxKeys)
            return
        end

        if action == 'check_item' and who ~= MyName then
            local corpseID = lootMessage.CorpseID
            lootedCorpses[corpseID] = true

            if itemName ~= 'NULL' then
                local MyCount = mq.TLO.FindItemCount(string.format("=%s", itemName))() + mq.TLO.FindItemBankCount(string.format("=%s", itemName))()

                if LNS.MasterLootList == nil then
                    LNS.MasterLootList = {}
                end
                if LNS.MasterLootList[corpseID] == nil then
                    LNS.MasterLootList[corpseID] = {}
                end
                if LNS.MasterLootList[corpseID].Items == nil then
                    LNS.MasterLootList[corpseID].Items = {}
                end
                if LNS.MasterLootList[corpseID].Items[itemName] == nil then
                    LNS.MasterLootList[corpseID].Items[itemName] = {
                        Link = itemLink,
                        Value = lootMessage.Value or 0,
                        NoDrop = lootMessage.NoDrop or false,
                        Lore = lootMessage.Lore or false,
                    }
                end
                if LNS.MasterLootList[corpseID].Items[itemName].Members == nil then
                    LNS.MasterLootList[corpseID].Items[itemName].Members = {}
                end

                LNS.MasterLootList[corpseID].Items[itemName].Members[who] = lootMessage.Count

                if LNS.MasterLootList[corpseID].Items[itemName].Members[MyName] == nil then
                    LNS.MasterLootList[corpseID].Items[itemName].Members[MyName] = MyCount
                    LNS.send({
                        who = MyName,
                        action = 'check_item',
                        item = itemName,
                        link = itemLink,
                        Count = MyCount,
                        Server = eqServer,
                        CorpseID = corpseID,
                        Value = lootMessage.Value or 0,
                        NoDrop = lootMessage.NoDrop or false,
                        Lore = lootMessage.Lore or false,
                    })
                end
            end

            return
        end

        if action == 'recheck_item' and who ~= MyName then
            local MyCount = mq.TLO.FindItemCount(string.format("=%s", itemName))() + mq.TLO.FindItemBankCount(string.format("=%s", itemName))()
            local corpseID = lootMessage.CorpseID
            LNS.send({
                who = MyName,
                action = 'check_item',
                item = itemName,
                link = itemLink,
                Count = MyCount,
                CorpseID = corpseID,
                Server = eqServer,
            })
            return
        end

        if action == 'item_gone' then
            LNS.TempSettings.RemoveMLItemInfo = {
                ['itemName'] = itemName,
                ['corpseID'] = lootMessage.CorpseID,
            }
            LNS.TempSettings.RemoveMLItem = true
            return
        end

        if action == 'corpse_gone' and who ~= MyName then
            LNS.TempSettings.RemoveMLCorpseInfo = {
                ['corpseID'] = lootMessage.CorpseID,
            }
            LNS.TempSettings.RemoveMLCorpse = true
            return
        end

        if action == 'master_looter' and who ~= MyName and LNS.Settings.MasterLooting ~= lootMessage.select then
            LNS.Settings.MasterLooting          = lootMessage.select
            LNS.TempSettings[who].MasterLooting = lootMessage.select
            LNS.Boxes[MyName]                   = LNS.Settings
            LNS.TempSettings[MyName]            = nil
            LNS.TempSettings.NeedSave           = true
            LNS.TempSettings.UpdateSettings     = true
            Logger.Debug(LNS.guiLoot.console, dbgTbl)
            Logger.Info(LNS.guiLoot.console, "Setting \ay%s\ax to \ag%s\ax", 'MasterLooting', lootMessage.select)

            return
        end

        if action == 'loot_item' and who == MyName then
            --LNS.send({ who = member, action = 'loot_item', CorpseID = cID, item = item, })
            Logger.Info(LNS.guiLoot.console, "\agLooting Item\ax: \at%s\ax, \ayLink\ax: \at%s\ax, \awFrom\ax: \ag%s\ax", itemName, itemLink, who)
            table.insert(LNS.TempSettings.ItemsToLoot, { corpseID = lootMessage.CorpseID, itemName = itemName, })
            return
        end

        if action == 'sendsettings' and who ~= MyName then
            if LNS.Boxes[who] == nil then LNS.Boxes[who] = {} end

            LNS.Boxes[who] = boxSettings
            LNS.TempSettings[who] = boxSettings
            return
        end

        if action == 'updatesettings' then
            if LNS.Boxes[who] == nil then LNS.Boxes[who] = {} end
            LNS.Boxes[who] = {}
            LNS.Boxes[who] = boxSettings
            LNS.TempSettings[who] = nil
            if who == MyName then
                for k, v in pairs(boxSettings) do
                    if type(v) ~= 'table' then
                        LNS.Settings[k] = v
                    end
                end
                LNS.Boxes[MyName] = LNS.Settings
                LNS.TempSettings[MyName] = nil
                LNS.TempSettings.UpdateSettings = true
            end
            return
        end

        if action == 'addsafezone' then
            if who == MyName then return end
            LNS.SafeZones[lootMessage.zone] = true
            LNS.TempSettings[MyName] = nil
            LNS.TempSettings.UpdateSettings = true
            Logger.Debug(LNS.guiLoot.console, dbgTbl)

            return
        end

        if action == 'removesafezone' then
            if who == MyName then return end
            LNS.SafeZones[lootMessage.zone] = nil
            LNS.TempSettings[MyName] = nil
            LNS.TempSettings.UpdateSettings = true
            Logger.Debug(LNS.guiLoot.console, dbgTbl)

            return
        end

        if server ~= eqServer then return end

        -- Reload loot settings
        if action == 'reloadrules' and who ~= MyName then
            LNS[lootMessage.bulkLabel .. 'Rules']   = {}
            LNS[lootMessage.bulkLabel .. 'Classes'] = {}
            LNS[lootMessage.bulkLabel .. 'Rules']   = lootMessage.bulkRules or {}
            LNS[lootMessage.bulkLabel .. 'Classes'] = lootMessage.bulkClasses or {}
            LNS.ItemLinks                           = lootMessage.bulkLink or {}
            return
        end
        -- -- Handle actions

        if action == 'addrule' or action == 'modifyitem' then
            Logger.Debug(LNS.guiLoot.console, dbgTbl)

            if section == 'PersonalItems' and who == MyName then
                LNS.PersonalItemsRules[itemID]   = rule
                LNS.PersonalItemsClasses[itemID] = itemClasses
                LNS.ItemLinks[itemID]            = itemLink
                LNS.ItemNames[itemID]            = itemName
                infoMsg                          = {
                    Lookup = 'loot.RegisterActors()',
                    Action = action,
                    RuleType = "Personal Rule",
                    Classes = itemClasses,
                    Rule = rule,
                    Item = itemName,
                }
            elseif section == 'GlobalItems' then
                LNS.GlobalItemsRules[itemID]   = rule
                LNS.GlobalItemsClasses[itemID] = itemClasses
                LNS.ItemLinks[itemID]          = itemLink
                LNS.ItemNames[itemID]          = itemName
                infoMsg                        = {
                    Lookup = 'loot.RegisterActors()',
                    Action = action,
                    RuleType = "Global Rule",
                    Classes = itemClasses,
                    Rule = rule,
                    Item = itemName,
                }
            elseif section == 'NormalItems' then
                LNS.NormalItemsRules[itemID]   = rule
                LNS.NormalItemsClasses[itemID] = itemClasses
                LNS.ItemLinks[itemID]          = itemLink
                LNS.ItemNames[itemID]          = itemName
                infoMsg                        = {
                    Lookup = 'loot.RegisterActors()',
                    Action = action,
                    RuleType = "Normal Rule",
                    Classes = itemClasses,
                    Rule = rule,
                    Item = itemName,
                }
            end
            Logger.Info(LNS.guiLoot.console, infoMsg)

            if lootMessage.entered and action ~= 'deleteitem' then
                if lootedCorpses[lootMessage.corpse] and lootMessage.hasChanged and rule ~= 'Ignore' and rule ~= 'Ask' then
                    lootedCorpses[lootMessage.corpse] = nil
                end

                LNS.NewItems[itemID] = nil
                if LNS.TempSettings.NewItemIDs ~= nil then
                    for idx, id in ipairs(LNS.TempSettings.NewItemIDs) do
                        if id == itemID then
                            table.remove(LNS.TempSettings.NewItemIDs, idx)
                            break
                        end
                    end
                end
                if LNS.TempSettings.NewItemIDs ~= nil then
                    LNS.NewItemsCount = #LNS.TempSettings.NewItemIDs or 0
                else
                    LNS.NewItemsCount = 0
                end
                infoMsg = {
                    Lookup = 'loot.RegisterActors()',
                    Action = 'New Item Rule',
                    Updated = lootMessage.entered,
                    Changed = lootMessage.hasChanged,
                    NewItemCountRemaining = LNS.NewItemsCount,
                    Item = itemName,
                    CorpseID = lootMessage.corpse,
                    CorpseLooted = lootedCorpses[lootMessage.corpse] or false,
                }
                Logger.Info(LNS.guiLoot.console, infoMsg)
            end

            LNS.TempSettings.GetItem = { Name = itemName, ID = itemID, }
            LNS.TempSettings.DoGet = true

            -- clean bags of items marked as destroy so we don't collect garbage
            if rule:lower() == 'destroy' then
                LNS.TempSettings.NeedsCleanup = true
            end
        elseif action == 'deleteitem' and who ~= MyName then
            Logger.Debug(LNS.guiLoot.console, dbgTbl)

            LNS[section .. 'Rules'][itemID]   = nil
            LNS[section .. 'Classes'][itemID] = nil
            infoMsg                           = {
                Lookup = 'loot.RegisterActors()',
                Action = action,
                RuleType = section,
                Rule = rule,
                Item = itemName,
            }
            Logger.Info(LNS.guiLoot.console, infoMsg)
        elseif action == 'new' and who ~= MyName and LNS.NewItems[itemID] == nil then
            Logger.Debug(LNS.guiLoot.console, dbgTbl)

            LNS.NewItems[itemID] = {
                Name       = lootMessage.item,
                Rule       = rule,
                Link       = itemLink,
                Lore       = lootMessage.lore,
                NoDrop     = lootMessage.noDrop,
                SellPrice  = lootMessage.sellPrice,
                Tradeskill = lootMessage.tradeskill,
                Icon       = lootMessage.icon or 0,
                MaxStacks  = lootMessage.maxStacks,
                Aug        = lootMessage.aug,
                Classes    = itemClasses,
                Races      = itemRaces,
                CorpseID   = lootMessage.corpse,
            }
            if LNS.TempSettings.NewItemIDs == nil then
                LNS.TempSettings.NewItemIDs = {}
            end
            table.insert(LNS.TempSettings.NewItemIDs, itemID)
            infoMsg = {
                Lookup = 'loot.RegisterActors()',
                Action = action,
                RuleType = section,
                Rule = rule,
                Item = itemName,
            }
            Logger.Info(LNS.guiLoot.console, infoMsg)
            -- LNS.NewItemsCount = LNS.NewItemsCount + 1
            LNS.NewItemsCount = #LNS.TempSettings.NewItemIDs or 0

            if LNS.Settings.AutoShowNewItem then
                showNewItem = true
            end
        elseif action == 'ItemsDB_UPDATE' and who ~= MyName then
            -- loot.LoadItemsDB()
        end

        -- Notify modules of loot setting changes
    end)
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
    local isGlobalItem   = LNS.Settings.GlobalLootOn and (LNS.GlobalItemsRules[cItemID] ~= nil) --or LNS.BuyItemsTable[itemName] ~= nil)
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
        else
            Logger.Debug(LNS.guiLoot.console, string.format("eval = %s", eval))

            eval = isGlobalItem == true and 'Global ' .. actionToTake or actionToTake
            eval = isPersonalItem == true and 'Personal ' .. actionToTake or eval
            if type(eval) == 'boolean' then eval = 'Ask' end

            Logger.Debug(LNS.guiLoot.console, string.format("eval = %s", eval))

            LNS.report('%sing \ay%s\ax', eval, itemLink)
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

        Logger.Debug(LNS.guiLoot.console, "\aoINSERT HISTORY CHECK 4\ax: \ayAction\ax: \at%s\ax, Item: \ao%s\ax, \atLink: %s", eval, itemName, itemLink)
        local allItemsEntry = LNS.insertIntoHistory(itemName, corpseName, eval,
            os.date('%Y-%m-%d'), os.date('%H:%M:%S'), itemLink, MyName, LNS.Zone, allItems, cantWear, rule)

        if allItemsEntry and LNS.GetTableSize(allItemsEntry) > 0 then
            table.insert(allItems, allItemsEntry)
        end

        local consoleAction = rule or ''
        if cantWear then
            consoleAction = consoleAction .. ' \ax(\arCant Wear\ax)'
        end
        local text = string.format('\ao[\at%s\ax] \at%s \ax%s %s Corpse \at%s\ax (\at%s\ax)', os.date('%H:%M:%S'), MyName, consoleAction,
            itemLink, corpseName, mq.TLO.Corpse.ID() or 0)
        if rule == 'Destroyed' then
            text = string.format('\ao[\at%s\ax] \at%s \ar%s \ax%s \axCorpse \at%s\ax (\at%s\ax)', os.date('%H:%M:%S'), MyName, string.upper(rule), itemLink, corpseName,
                mq.TLO.Corpse.ID() or 0)
        end
        LNS.guiLoot.console:AppendText(text)
    end
end

function LNS.lootCorpse(corpseID)
    Logger.Debug(LNS.guiLoot.console, 'Enter lootCorpse')
    shouldLootActions.Destroy = LNS.Settings.DoDestroy
    shouldLootActions.Tribute = LNS.Settings.TributeKeep
    shouldLootActions.Quest   = LNS.Settings.QuestKeep
    if corpseID == nil then
        Logger.Warn(LNS.guiLoot.console, "lootCorpse(): No corpseID provided.")
        return false
    end
    if allItems == nil then allItems = {} end
    noDropItems, loreItems = {}, {}

    if mq.TLO.Cursor() then LNS.checkCursor() end

    for i = 1, 3 do
        mq.cmdf('/loot')
        mq.delay(1000, function() return mq.TLO.Window('LootWnd').Open() end)
        if mq.TLO.Window('LootWnd').Open() then break end
    end

    mq.doevents('CantLoot')
    mq.delay(1000, function() return cantLootID > 0 or mq.TLO.Window('LootWnd').Open() end)

    if not mq.TLO.Window('LootWnd').Open() then
        if mq.TLO.Target.CleanName() then
            Logger.Warn(LNS.guiLoot.console, "lootCorpse(): Can't loot %s right now", mq.TLO.Target.CleanName())
            cantLootList[corpseID] = os.clock()
        end
        return false
    end

    local corpseName = mq.TLO.Corpse.CleanName() or 'none'
    corpseName = corpseName:lower()

    mq.delay(1000, function() return mq.TLO.Corpse.Items() end)
    local numItems = mq.TLO.Corpse.Items() or 0
    Logger.Debug(LNS.guiLoot.console, "lootCorpse(): Loot window open. Items: %s", numItems)
    if numItems == 0 then
        mq.cmdf('/nomodkey /notify LootWnd LW_DoneButton leftmouseup')
        mq.TLO.Window('LootWnd').DoClose()
        Logger.Debug(LNS.guiLoot.console, "lootCorpse(): \arNo items\ax to loot on corpse \at%s\ax (\ay%s\ax)", corpseName, corpseID)
        return true
    end

    if mq.TLO.Window('LootWnd').Open() and numItems > 0 then
        if (mq.TLO.Corpse.DisplayName():lower() == mq.TLO.Me.DisplayName():lower() .. "'s corpse") then
            if LNS.Settings.LootMyCorpse then
                mq.cmdf('/lootall')
                mq.delay("45s", function() return not mq.TLO.Window('LootWnd').Open() end)
            end
            return false
        end

        local iList = ""
        local corpseItems = {}
        for i = 1, numItems do
            local corpseItem = mq.TLO.Corpse.Item(i)
            if corpseItem() then
                local corpseItemID = corpseItem.ID() or 0
                local itemName = corpseItem.Name() or 'none'
                local itemLink = corpseItem.ItemLink('CLICKABLE')() or 'NULL'
                local itemRule, qKeep, newRule, iCanUse = LNS.getRule(corpseItem, 'loot', i)

                LNS.addToItemDB(corpseItem)

                iList = string.format("%s (\at%s\ax [\ay%s\ax])", iList, corpseItem.Name() or 'none', itemRule)

                if itemRule ~= 'MasterLooter' and not (itemRule == 'Ignore' or itemRule == 'Ask' or itemRule == 'NULL') then
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

                    local allItemsEntry = LNS.insertIntoHistory(itemName, corpseName, eval,
                        os.date('%Y-%m-%d'), os.date('%H:%M:%S'), itemLink, MyName, LNS.Zone, allItems, not iCanUse, itemRule)
                    if allItemsEntry and LNS.GetTableSize(allItemsEntry) > 0 then
                        table.insert(allItems, allItemsEntry)
                    end

                    local consoleAction = itemRule or ''
                    if not iCanUse then
                        consoleAction = consoleAction .. ' \ax(\arCant Wear\ax)'
                    end
                    local text = string.format('\ao[\at%s\ax] \at%s \ax%s %s Corpse \at%s\ax (\at%s\ax)', os.date('%H:%M:%S'), MyName, consoleAction,
                        itemLink, corpseName, corpseID)
                    if itemRule == 'Destroyed' then
                        text = string.format('\ao[\at%s\ax] \at%s \ar%s \ax%s \axCorpse \at%s\ax (\at%s\ax)', os.date('%H:%M:%S'), MyName, string.upper(itemRule), itemLink,
                            corpseName, corpseID)
                    end
                    LNS.guiLoot.console:AppendText(text)
                    -- local lbl = itemRule
                    -- if itemRule == 'Ignore' then
                    --     lbl = 'Left'
                    -- elseif itemRule == 'Ask' then
                    --     lbl = 'Asking'
                    -- end
                    -- if LNS.Settings.ReportSkippedItems then
                    --     LNS.report('%s (\ao%s\ax) %s', MyName, lbl, itemLink)
                    -- end
                end
            end
            -- if allItems ~= nil and #allItems > 0 then
            --     LNS.send({
            --         ID = corpseID,
            --         Items = allItems,
            --         Zone = LNS.Zone,
            --         Server = eqServer,
            --         LootedAt = mq.TLO.Time(),
            --         CorpseName = mq.TLO.Corpse.DisplayName() or 'unknown',
            --         LootedBy = MyName,
            --     }, 'looted')
            --     allItems = nil
            -- end
        end

        -- if allItems ~= nil and #allItems > 0 then
        --     LNS.send({
        --         ID = corpseID,
        --         Items = allItems,
        --         Zone = LNS.Zone,
        --         Server = eqServer,
        --         LootedAt = mq.TLO.Time(),
        --         CorpseName = mq.TLO.Corpse.DisplayName() or 'unknown',
        --         LootedBy = MyName,
        --     }, 'looted')
        --     allItems = nil
        -- end

        Logger.Info(LNS.guiLoot.console, "lootCorpse(): Looting \at%s\ax Found (\ay%s\ax) Items:%s", corpseName, numItems, iList)

        for _, item in ipairs(corpseItems) do
            if not item then break end
            local itemRule = item.itemRule

            Logger.Debug(LNS.guiLoot.console, "\agLooting Corpse:\ax itemID=\ao%s\ax, Slot: \ay%s\ax, Decision=\at%s\ax, qKeep=\ay%s\ax, newRule=\ag%s",
                item.ID, item.Index, itemRule, item.qKeep, item.newRule)

            LNS.lootItem(item.mq_item, item.Index, itemRule, 'leftmouseup', item.qKeep, not item.iCanUse)

            mq.delay(1)
            if mq.TLO.Cursor() then LNS.checkCursor() end

            mq.delay(1)
            if not mq.TLO.Window('LootWnd').Open() then break end
        end

        mq.cmdf('/nomodkey /notify LootWnd LW_DoneButton leftmouseup')
        mq.delay(2000, function() return not mq.TLO.Window('LootWnd').Open() end)
    end

    if mq.TLO.Cursor() then LNS.checkCursor() end
    LNS.reportSkippedItems(noDropItems, loreItems, corpseName, corpseID)

    return true
end

function LNS.lootMobs(limit)
    local didLoot = false
    LNS.TempSettings.LastCheck = os.clock()

    if LNS.PauseLooting or LNS.SafeZones[LNS.Zone] then
        LNS.finishedLooting()
        return false
    end
    -- check for normal, undead, animal invis should not see rogue sneak\hide
    if mq.TLO.Me.Invis(1)() or mq.TLO.Me.Invis(2)() or mq.TLO.Me.Invis(3)() then
        Logger.Warn(LNS.guiLoot.console, "lootMobs(): You are Invis and we don't want to break it so skipping.")
        LNS.finishedLooting()
        return false
    end

    if limit == nil then limit = 50 end
    if zoneID ~= mq.TLO.Zone.ID() then
        zoneID        = mq.TLO.Zone.ID()
        lootedCorpses = {}
    end

    if mq.TLO.Window('LootWnd').Open() then
        Logger.Warn(LNS.guiLoot.console, 'lootMobs(): Already Looting, Aborting!.')
        return false
    end


    -- Logger.Debug(loot.guiLoot.console, 'lootMobs(): Entering lootMobs function.')
    local deadCount      = mq.TLO.SpawnCount(string.format('npccorpse radius %s zradius 50', LNS.Settings.CorpseRadius or 100))()
    local mobsNearby     = mq.TLO.SpawnCount(string.format('npc xtarhater radius %s zradius 50', LNS.Settings.MobsTooClose + LNS.Settings.CorpseRadius))()
    local corpseList     = {}
    -- Logger.Debug(loot.guiLoot.console, 'lootMobs(): Found %s corpses in range.', deadCount)

    -- Handle looting of the player's own corpse
    local pcCorpseFilter = string.format("pccorpse %s's radius %s zradius 50", mq.TLO.Me.CleanName(), LNS.Settings.CorpseRadius)
    local myCorpseCount  = mq.TLO.SpawnCount(pcCorpseFilter)()
    local foundMine      = myCorpseCount > 0

    if not LNS.Settings.LootMyCorpse and not LNS.Settings.IgnoreMyNearCorpses and foundMine then
        Logger.Debug(LNS.guiLoot.console, 'lootMobs(): Puasing looting until finished looting my own corpse.')
        LNS.finishedLooting()
        return false
    end

    if LNS.Settings.LootMyCorpse and not LNS.Settings.IgnoreMyNearCorpses and foundMine then
        Logger.Debug(LNS.guiLoot.console, 'lootMobs(): Found my own corpse, attempting to loot it.')
        for i = 1, myCorpseCount do
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
    if (deadCount + myCorpseCount) == 0 or (mobsNearby > 0 and not LNS.Settings.CombatLooting) or (mq.TLO.Me.Combat() and not LNS.Settings.CombatLooting) then
        LNS.finishedLooting()
        return false
    end

    -- Add other corpses to the loot list if not limited by the player's own corpse
    if (myCorpseCount == 0 or (myCorpseCount > 0 and LNS.Settings.IgnoreMyNearCorpses)) and LNS.Settings.DoLoot then
        for i = 1, deadCount do
            local corpse = mq.TLO.NearestSpawn(('%d,' .. spawnSearch):format(i, 'npccorpse', LNS.Settings.CorpseRadius))
            if corpse() and not (lootedCorpses[corpse.ID()] and LNS.Settings.CheckCorpseOnce) then
                if not LNS.corpseLocked(corpse.ID()) or
                    (mq.TLO.Navigation.PathLength('spawn id ' .. corpse.ID())() or 100) > LNS.Settings.CorpseRadius then
                    table.insert(corpseList, corpse)
                end
            end
        end
    else
        if LNS.Settings.DoLoot then
            Logger.Debug(LNS.guiLoot.console, 'lootMobs(): Skipping other corpses due to nearby player corpse.')
        end
        LNS.finishedLooting()
        return false
    end

    if Mode == 'directed' and not LNS.LootNow then
        LNS.finishedLooting()
        return false
    end

    -- Process the collected corpse list
    local counter = 0
    if #corpseList > 0 then
        Logger.Debug(LNS.guiLoot.console, 'lootMobs(): Attempting to loot \at%d\ax corpses.', #corpseList)
        for _, corpse in ipairs(corpseList) do
            local check = false
            local corpseID = corpse.ID() or 0

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

            if mq.TLO.Me.Casting() ~= nil then
                goto continue
            end

            LNS.navToID(corpseID)

            if mobsNearby > 0 and not LNS.Settings.CombatLooting then
                Logger.Debug(LNS.guiLoot.console, 'lootMobs(): \arStopping\ax looting due to \ayAGGRO!')
                LNS.finishedLooting()
                return false
            end

            corpse.DoTarget()
            check                   = LNS.lootCorpse(corpseID)
            lootedCorpses[corpseID] = check
            mq.TLO.Window('LootWnd').DoClose()

            ::continue::

            if allItems ~= nil and #allItems > 0 then
                LNS.send({
                    ID = corpseID,
                    Items = allItems,
                    Zone = LNS.Zone,
                    Server = eqServer,
                    LootedAt = mq.TLO.Time(),
                    CorpseName = corpse.DisplayName() or 'unknown',
                    LootedBy = MyName,
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

    LNS.finishedLooting()

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
        for idx, data in ipairs(LNS.TempSettings.ItemsToLoot or {}) do
            if data.corpseID == corpseID and data.itemName == itemName then
                Logger.Debug(LNS.guiLoot.console, 'corpseGone(): Removing item %s from ItemsToLoot for corpse ID %d', data.ItemName, corpseID)
                LNS.TempSettings.ItemsToLoot[idx] = nil
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

        for idx, data in ipairs(LNS.TempSettings.ItemsToLoot or {}) do
            if data.corpseID == corpseID then
                Logger.Debug(LNS.guiLoot.console, 'corpseGone(): Removing item %s from ItemsToLoot for corpse ID %d', data.ItemName, corpseID)
                LNS.TempSettings.ItemsToLoot[idx] = nil
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
        LNS.send({ who = MyName, action = 'corpse_gone', Server = eqServer, CorpseID = corpseID, })
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
            -- LNS.send({
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
            --     Server = eqServer,S
            --     LootedAt = mq.TLO.Time(),
            --     CorpseName = corpseName,
            --     LootedBy = MyName,
            -- }, 'looted')

            break
        end
    end
    if allItems ~= nil and #allItems > 0 then
        LNS.send({
            ID = corpseID,
            Items = allItems,
            Zone = LNS.Zone,
            Server = eqServer,
            LootedAt = mq.TLO.Time(),
            CorpseName = mq.TLO.Corpse.DisplayName() or 'unknown',
            LootedBy = MyName,
        }, 'looted')
        allItems = nil
    end

    checkMore = mq.TLO.Corpse.Item(string.format("=%s", itemName))() ~= nil or false

    if not checkMore then
        LNS.send({ action = 'item_gone', item = itemName, CorpseID = corpseID, Server = eqServer, })
    end
    mq.TLO.Window('LootWnd').DoClose()
    mq.delay(1000, function() return not mq.TLO.Window('LootWnd').Open() end)
    if not mq.TLO.Spawn(corpseID)() then
        LNS.send({ action = 'corpse_gone', CorpseID = corpseID, Server = eqServer, })
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

    -- Add a rule to mark the item as "Sell"
    LNS.addRule(itemID, "NormalItems", "Sell", "All", 'NULL')
    Logger.Info(LNS.guiLoot.console, "Added rule: \ay%s\ax set to \agSell\ax.", itemName)
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
        mq.delay(1000, function() return mq.TLO.Window("MerchantWnd/MW_Sell_Button")() == "TRUE" and mq.TLO.Window("MerchantWnd/MW_Sell_Button").Enabled() end)
        if mq.TLO.Window("MerchantWnd/MW_SelectedPriceLabel").Text() ~= "0c" then
            mq.cmdf('/nomodkey /shiftkey /notify merchantwnd MW_Sell_Button leftmouseup')
            mq.delay(5000, function() return mq.TLO.Window("MerchantWnd/MW_Sell_Button")() ~= "TRUE" end)
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
    mq.delay(10000, function() return mq.TLO.Cursor() end)
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
        mq.delay(500, function() return mq.TLO.Window("MerchantWnd/MW_ItemList").List(string.format("=%s", itemName), 2)() end)
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
            mq.delay(3000, function() return mq.TLO.Window('MerchantWnd/MW_SelectedItemLabel').Text() == itemName end)
            if mq.TLO.Window('MerchantWnd/MW_SelectedItemLabel').Text() ~= itemName then
                Logger.Warn(LNS.guiLoot.console, "\arFailed\ax to select item: \ay%s\ax, retrying...", itemName)
                if LNS.TempSettings.RestockAttempts == nil then
                    LNS.TempSettings.RestockAttempts = 0
                end
                if LNS.TempSettings.RestockAttempts >= 5 then
                    Logger.Warn(LNS.guiLoot.console, "\arFailed to select item\ax: \ay%s\ax after 5 attempts, skipping...", itemName)
                    LNS.TempSettings.RestockAttempts = 0
                    goto next_item
                end
                LNS.TempSettings.RestockAttempts = LNS.TempSettings.RestockAttempts + 1
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
    LNS.TempSettings.RestockAttempts = 0
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
    -- Add a rule to mark the item as "Tribute"
    LNS.addRule(itemID, "NormalItems", "Tribute", "All", link)
    Logger.Info(LNS.guiLoot.console, "Added rule: \ay%s\ax set to \agTribute\ax.", itemName)
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
    if not LNS.Settings.LootForage then return end
    Logger.Debug(LNS.guiLoot.console, 'Enter eventForage')
    -- allow time for item to be on cursor incase message is faster or something?
    mq.delay(1000, function() return mq.TLO.Cursor() end)
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
                if LNS.Settings.LootForageSpam then Logger.Info(LNS.guiLoot.console, 'Destroying foraged item \ao%s', foragedItem) end
                mq.cmdf('/destroy')
                mq.delay(2000, function() return (mq.TLO.Cursor.ID() or -1) ~= cursorID end)
            end
            -- will a lore item we already have even show up on cursor?
            -- free inventory check won't cover an item too big for any container so may need some extra check related to that?
        elseif (shouldLootActions[ruleAction]) and cursorItem() and
            (not cursorItem.Lore() or (cursorItem.Lore() and currentItemAmount == 0)) and
            (mq.TLO.Me.FreeInventory() > LNS.Settings.SaveBagSlots) or (cursorItem.Stackable() and cursorItem.FreeStack()) then
            if LNS.Settings.LootForageSpam then Logger.Info(LNS.guiLoot.console, 'Keeping foraged item \at%s', foragedItem) end
            mq.cmdf('/autoinv')
            mq.delay(2000, function() return (mq.TLO.Cursor.ID() or -1) ~= cursorID end)
        else
            if LNS.Settings.LootForageSpam then Logger.Warn(LNS.guiLoot.console, 'Unable to process item \ao%s', foragedItem) end
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
    LNS.informProcessing()
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
            rule = (tradeskill and LNS.Settings.BankTradeskills) and 'Bank' or rule
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
    if LNS.Settings.AlwaysEval then
        flag, LNS.Settings.AlwaysEval = true, false
    end

    -- Iterate through bags and process items

    for i = 1, 10 do
        if i == LNS.Settings.IgnoreBagSlot then
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
    if action == 'Sell' and LNS.Settings.AutoRestock then
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
        flag, LNS.Settings.AlwaysEval = false, true
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
    LNS.doneProcessing()
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
--          GUI FUNCTIONS
------------------------------------

function LNS.renderMissingItemsTables()
    ImGui.Text("Imported Global Rules")
    if ImGui.BeginTable("ImportedData##Global", 4, bit32.bor(ImGuiTableFlags.ScrollY, ImGuiTableFlags.Borders), ImVec2(0.0, 300)) then
        ImGui.TableSetupColumn("Item ID##g", ImGuiTableColumnFlags.WidthFixed, 40)
        ImGui.TableSetupColumn("Item Name##g", ImGuiTableColumnFlags.WidthStretch, 100)
        ImGui.TableSetupColumn("Item Rule##g", ImGuiTableColumnFlags.WidthFixed, 60)
        ImGui.TableSetupColumn("Item Classes##g", ImGuiTableColumnFlags.WidthFixed, 60)
        ImGui.TableHeadersRow()
        ImGui.TableNextRow()
        for _, v in ipairs(LNS.TempSettings.SortedMissingGlobalNames or {}) do
            if LNS.GlobalItemsMissing[v.id] ~= nil then
                ImGui.TableNextColumn()
                ImGui.TextColored(ImVec4(1.000, 0.557, 0.000, 1.000), "%s", LNS.GlobalItemsMissing[v.id].item_id)
                ImGui.TableNextColumn()
                ImGui.PushStyleColor(ImGuiCol.Text, ImVec4(0.370, 0.704, 1.000, 1.000))
                if ImGui.Selectable(string.format("%s", LNS.GlobalItemsMissing[v.id].item_name), false) then
                    LNS.TempSettings.ModifyItemRule = true
                    LNS.TempSettings.ModifyItemName = LNS.GlobalItemsMissing[v.id].item_name
                    LNS.TempSettings.ModifyItemLink = nil
                    LNS.TempSettings.ModifyItemID = LNS.GlobalItemsMissing[v.id].item_id
                    LNS.TempSettings.ModifyItemTable = "Global_Items"
                    LNS.TempSettings.ModifyClasses = LNS.GlobalItemsMissing[v.id].item_classes
                    LNS.TempSettings.ModifyItemSetting = LNS.GlobalItemsMissing[v.id].item_rule
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

        for _, v in ipairs(LNS.TempSettings.SortedMissingNormalNames or {}) do
            if LNS.NormalItemsMissing[v.id] ~= nil then
                ImGui.TableNextColumn()
                ImGui.TextColored(ImVec4(1.000, 0.557, 0.000, 1.000), "%s", LNS.NormalItemsMissing[v.id].item_id)
                ImGui.TableNextColumn()
                ImGui.PushStyleColor(ImGuiCol.Text, ImVec4(0.370, 0.704, 1.000, 1.000))
                if ImGui.Selectable(string.format("%s", LNS.NormalItemsMissing[v.id].item_name), false) then
                    LNS.TempSettings.ModifyItemRule = true
                    LNS.TempSettings.ModifyItemName = LNS.NormalItemsMissing[v.id].item_name
                    LNS.TempSettings.ModifyItemLink = nil
                    LNS.TempSettings.ModifyItemID = LNS.NormalItemsMissing[v.id].item_id
                    LNS.TempSettings.ModifyItemTable = "Normal_Items"
                    LNS.TempSettings.ModifyClasses = LNS.NormalItemsMissing[v.id].item_classes
                    LNS.TempSettings.ModifyItemSetting = LNS.NormalItemsMissing[v.id].item_rule
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

function LNS.renderImportDBWindow()
    if not LNS.TempSettings.ShowImportDB then
        return
    end
    local openImport, drawImport = ImGui.Begin('Loot N Scoot Import DB', true)
    if not openImport then
        LNS.TempSettings.ShowImportDB = false
        drawImport = false
    end

    if drawImport then
        ImGui.TextWrapped(
            'This will import the current Loot N Scoot Database from the Old version..\n Specify the name of the file ex. LootRules_Project_Lazarus.db.\nThis file can be found in your MQ/Config folder.')
        ImGui.Spacing()
        ImGui.Separator()
        ImGui.SetNextItemWidth(100)
        LNS.TempSettings.ImportDBFileName = ImGui.InputText('Import File Name', LNS.TempSettings.ImportDBFileName)
        LNS.TempSettings.ImportDBFilePath = string.format("%s/%s", mq.configDir, LNS.TempSettings.ImportDBFileName)
        if ImGui.Button('Import Database') then
            printf('Importing Database from: %s', LNS.TempSettings.ImportDBFilePath)
            LNS.TempSettings.DoImport = true
        end
        ImGui.SameLine()
        if ImGui.Button('Cancel') then
            LNS.TempSettings.ShowImportDB = false
        end
        ImGui.Spacing()
        ImGui.Separator()
        LNS.renderMissingItemsTables()
    end

    ImGui.End()
end

function LNS.renderHelpWindow()
    if not LNS.TempSettings.ShowHelp then
        return
    end
    local openHelp, drawHelp = ImGui.Begin('Loot N Scoot Help', true)
    if not openHelp then
        LNS.TempSettings.ShowHelp = false
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
                for k, v in pairs(LNS.Settings) do
                    if type(v) == 'boolean' and not settingsNoDraw[k] then
                        ImGui.TableNextRow()
                        ImGui.TableNextColumn()
                        ImGui.TextWrapped(k)
                        ImGui.TableNextColumn()
                        ImGui.TextWrapped(LNS.Tooltips[k] or "No tooltip available")
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
                for k, v in pairs(LNS.Settings) do
                    if type(v) ~= 'boolean' and not settingsNoDraw[k] then
                        ImGui.TableNextRow()
                        ImGui.TableNextColumn()
                        ImGui.TextWrapped(k)
                        ImGui.TableNextColumn()
                        ImGui.TextWrapped(LNS.Tooltips[k] or "No tooltip available")
                    end
                end
                ImGui.EndTable()
            end
        end
    end
    ImGui.End()
end

function LNS.drawIcon(iconID, iconSize)
    if iconSize == nil then iconSize = 16 end
    if iconID ~= nil then
        iconAnimation:SetTextureCell(iconID - 500)
        ImGui.DrawTextureAnimation(iconAnimation, iconSize, iconSize)
    end
end

---comment
---@param label string Menu Item Display Label
---@param setting_name string Setting Name in LNS.Settings
---@param value boolean Setting Value in LNS.Settings
---@param tooltip string|nil Optional Tooltip Text
function LNS.DrawMenuItemToggle(label, setting_name, value, tooltip)
    local changed = false
    changed, value = ImGui.MenuItem(label, nil, value)
    if changed then
        LNS.TempSettings.NeedSaveToggle = true
        LNS.Settings[setting_name] = value
    end
    if tooltip then
        if ImGui.IsItemHovered() then
            ImGui.BeginTooltip()
            ImGui.Text(tooltip)
            ImGui.EndTooltip()
        end
    end
end

function LNS.guiExport()
    -- Define a new menu element function
    local function customMenu()
        ImGui.PushID('LootNScootMenu_Imported')
        if ImGui.BeginMenu('Loot N Scoot##') then
            -- Add menu items here
            if ImGui.BeginMenu('Toggles') then
                -- Add menu items here
                LNS.DrawMenuItemToggle("DoLoot", "DoLoot", LNS.Settings.DoLoot, "Enable or disable looting of corpses.")
                LNS.DrawMenuItemToggle("GlobalLootOn", "GlobalLootOn", LNS.Settings.GlobalLootOn, "Enable or disable global looting across all characters.")
                LNS.DrawMenuItemToggle("CombatLooting", "CombatLooting", LNS.Settings.CombatLooting, "Enable or disable looting while in combat.")
                LNS.DrawMenuItemToggle("LootNoDrop", "LootNoDrop", LNS.Settings.LootNoDrop, "Enable or disable looting of No Drop items.")
                LNS.DrawMenuItemToggle("LootNoDropNew", "LootNoDropNew", LNS.Settings.LootNoDropNew, "Enable or disable looting of No Drop items with new rules.")
                LNS.DrawMenuItemToggle("LootForage", "LootForage", LNS.Settings.LootForage, "Enable or disable looting of foraged items.")
                LNS.DrawMenuItemToggle("LootQuest", "LootQuest", LNS.Settings.LootQuest, "Enable or disable looting of quest items.")
                LNS.DrawMenuItemToggle("TributeKeep", "TributeKeep", LNS.Settings.TributeKeep, "Enable or disable keeping tribute items.")
                LNS.DrawMenuItemToggle("BankTradeskills", "BankTradeskills", LNS.Settings.BankTradeskills, "Enable or disable banking of tradeskill items.")
                LNS.DrawMenuItemToggle("StackableOnly", "StackableOnly", LNS.Settings.StackableOnly, "Enable or disable looting of only stackable items.")
                ImGui.Separator()
                LNS.DrawMenuItemToggle("AlwaysEval", "AlwaysEval", LNS.Settings.AlwaysEval, "Enable or disable always evaluating items.")
                LNS.DrawMenuItemToggle("AddNewSales", "AddNewSales", LNS.Settings.AddNewSales, "Enable or disable adding new sales items.")
                LNS.DrawMenuItemToggle("AddNewTributes", "AddNewTributes", LNS.Settings.AddNewTributes, "Enable or disable adding new tribute items.")
                LNS.DrawMenuItemToggle("AutoTagSell", "AutoTag", LNS.Settings.AutoTag, "Enable or disable automatic tagging of items for selling.")
                LNS.DrawMenuItemToggle("AutoRestock", "AutoRestock", LNS.Settings.AutoRestock, "Enable or disable automatic restocking of items.")
                ImGui.Separator()
                LNS.DrawMenuItemToggle("DoDestroy", "DoDestroy", LNS.Settings.DoDestroy, "Enable or disable destruction of items.")
                LNS.DrawMenuItemToggle("AlwaysDestroy", "AlwaysDestroy", LNS.Settings.AlwaysDestroy, "Enable or disable always destroying items.")
                ImGui.EndMenu()
            end

            local gCmd = tmpCmd:find("dg") and "/dgg" or tmpCmd
            if ImGui.BeginMenu('Group Commands##') then
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

function LNS.drawYesNo(decision)
    if decision then
        LNS.drawIcon(4494, 20) -- Checkmark icon
    else
        LNS.drawIcon(4495, 20) -- X icon
    end
end

function LNS.drawNewItemsTable()
    local itemsToRemove = {}
    if LNS.NewItems == nil then showNewItem = false end
    if LNS.NewItemsCount <= 0 then
        showNewItem = false
    else
        if ImGui.BeginTable('##newItemTable', 3, bit32.bor(
                ImGuiTableFlags.Borders, ImGuiTableFlags.ScrollX,
                ImGuiTableFlags.Reorderable,
                ImGuiTableFlags.RowBg)) then
            -- Setup Table Columns
            ImGui.TableSetupColumn('Item', bit32.bor(ImGuiTableColumnFlags.WidthStretch), 130)
            ImGui.TableSetupColumn('Classes', ImGuiTableColumnFlags.NoResize, 150)
            ImGui.TableSetupColumn('Rule', bit32.bor(ImGuiTableColumnFlags.NoResize), 90)
            ImGui.TableHeadersRow()

            -- Iterate Over New Items
            for idx, itemID in ipairs(LNS.TempSettings.NewItemIDs or {}) do
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
                ImGui.TableNextRow()
                -- Item Name and Link
                ImGui.TableNextColumn()

                ImGui.Indent(2)

                LNS.drawIcon(item.Icon, 20)
                if ImGui.IsItemHovered() and ImGui.IsMouseClicked(0) then
                    -- if ImGui.SmallButton(Icons.FA_EYE .. "##" .. itemID) then
                    mq.cmdf('/executelink %s', item.Link)
                end
                ImGui.SameLine()
                ImGui.Text(item.Name or "Unknown")

                ImGui.Unindent(2)
                ImGui.Indent(2)

                if ImGui.BeginTable("SellData", 2, bit32.bor(ImGuiTableFlags.Borders,
                        ImGuiTableFlags.Reorderable)) then
                    ImGui.TableSetupColumn('Value', ImGuiTableColumnFlags.WidthStretch)
                    ImGui.TableSetupColumn('Stacks', ImGuiTableColumnFlags.WidthFixed, 30)
                    ImGui.TableHeadersRow()
                    ImGui.TableNextRow()
                    -- Sell Price
                    ImGui.TableNextColumn()
                    if item.SellPrice ~= '0 pp 0 gp 0 sp 0 cp' then
                        ImGui.Text(item.SellPrice or "0")
                    end
                    ImGui.TableNextColumn()
                    ImGui.Text("%s", item.MaxStacks > 0 and item.MaxStacks or "No")
                    ImGui.EndTable()
                end

                ImGui.Unindent(2)

                -- Classes

                ImGui.TableNextColumn()

                ImGui.Indent(2)

                ImGui.SetNextItemWidth(ImGui.GetColumnWidth(-1) - 50)
                tmpClasses[itemID] = ImGui.InputText('##Classes' .. itemID, tmpClasses[itemID] or item.Classes)
                if ImGui.IsItemHovered() then
                    ImGui.SetTooltip("Classes: %s", item.Classes)
                end

                ImGui.SameLine()
                LNS.tempLootAll[itemID] = ImGui.Checkbox('All', LNS.tempLootAll[itemID])

                ImGui.Unindent(2)


                ImGui.Indent(2)
                if ImGui.BeginTable('ItemFlags', 4, bit32.bor(ImGuiTableFlags.Borders,
                        ImGuiTableFlags.Reorderable)) then
                    ImGui.TableSetupColumn('NoDrop', ImGuiTableColumnFlags.WidthFixed, 30)
                    ImGui.TableSetupColumn('Lore', ImGuiTableColumnFlags.WidthFixed, 30)
                    ImGui.TableSetupColumn("Aug", ImGuiTableColumnFlags.WidthFixed, 30)
                    ImGui.TableSetupColumn('TS', ImGuiTableColumnFlags.WidthFixed, 30)
                    ImGui.TableHeadersRow()
                    ImGui.TableNextRow()
                    -- Flags (NoDrop, Lore, Augment, TradeSkill)
                    ImGui.TableNextColumn()
                    LNS.drawYesNo(item.NoDrop)
                    ImGui.TableNextColumn()
                    LNS.drawYesNo(item.Lore)
                    ImGui.TableNextColumn()
                    LNS.drawYesNo(item.Aug)
                    ImGui.TableNextColumn()
                    LNS.drawYesNo(item.Tradeskill)
                    ImGui.EndTable()
                end
                ImGui.Unindent(2)
                -- Rule
                ImGui.TableNextColumn()

                item.selectedIndex = item.selectedIndex or LNS.getRuleIndex(item.Rule, settingList)

                ImGui.Indent(2)

                ImGui.SetNextItemWidth(ImGui.GetColumnWidth(-1))
                if ImGui.BeginCombo('##Setting' .. itemID, settingList[item.selectedIndex]) then
                    for i, setting in ipairs(settingList) do
                        local isSelected = item.selectedIndex == i
                        if ImGui.Selectable(setting, isSelected) then
                            item.selectedIndex = i
                            tmpRules[itemID]   = setting
                        end
                    end
                    ImGui.EndCombo()
                end
                ImGui.Unindent(2)

                ImGui.Spacing()
                if LNS.tempGlobalRule[itemID] == nil then
                    LNS.tempGlobalRule[itemID] = LNS.Settings.AlwaysGlobal
                end
                LNS.tempGlobalRule[itemID] = ImGui.Checkbox('Global Rule', LNS.tempGlobalRule[itemID])

                ImGui.SetCursorPosX(ImGui.GetCursorPosX() + (ImGui.GetColumnWidth(-1) / 6))
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

                    table.remove(LNS.TempSettings.NewItemIDs, idx)
                    table.insert(itemsToRemove, itemID)
                    Logger.Debug(LNS.guiLoot.console, "\agSaving\ax --\ayNEW ITEM RULE\ax-- Item: \at%s \ax(ID:\ag %s\ax) with rule: \at%s\ax, classes: \at%s\ax, link: \at%s\ax",
                        item.Name, itemID, tmpRules[itemID], tmpClasses[itemID], item.Link)
                end
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
    LNS.NewItemsCount = #LNS.TempSettings.NewItemIDs or 0
end

function LNS.SafeText(write_value)
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

LNS.TempSettings.SelectedItems = {}
function LNS.drawTabbedTable(label)
    local varSub = label .. 'Items'

    if ImGui.BeginTabItem(varSub .. "##") then
        if LNS.TempSettings.varSub == nil then
            LNS.TempSettings.varSub = {}
        end
        if LNS.TempSettings[varSub .. 'Classes'] == nil then
            LNS.TempSettings[varSub .. 'Classes'] = {}
        end
        local sizeX, _ = ImGui.GetContentRegionAvail()
        ImGui.PushStyleColor(ImGuiCol.ChildBg, ImVec4(0.0, 0.6, 0.0, 0.1))
        if ImGui.BeginChild("Add Rule Drop Area", ImVec2(sizeX, 40), ImGuiChildFlags.Border) then
            ImGui.TextDisabled("Drop Item Here to Add to a %s Rule", label)
            if ImGui.IsWindowHovered() and ImGui.IsMouseClicked(0) then
                if mq.TLO.Cursor() ~= nil then
                    local itemCursor = mq.TLO.Cursor
                    LNS.addToItemDB(mq.TLO.Cursor)
                    LNS.TempSettings.ModifyItemRule = true
                    LNS.TempSettings.ModifyItemName = itemCursor.Name()
                    LNS.TempSettings.ModifyItemLink = itemCursor.ItemLink('CLICKABLE')() or "NULL"
                    LNS.TempSettings.ModifyItemID = itemCursor.ID()
                    LNS.TempSettings.ModifyItemTable = label .. "_Items"
                    LNS.TempSettings.ModifyClasses = LNS[varSub .. 'Classes'][itemCursor.ID()] or "All"
                    LNS.TempSettings.ModifyItemSetting = "Ask"
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
        LNS.TempSettings['Search' .. varSub] = ImGui.InputTextWithHint("Search", "Search by Name or Rule",
            LNS.TempSettings['Search' .. varSub]) or nil
        ImGui.PopID()
        if ImGui.IsItemHovered(ImGuiHoveredFlags.DelayShort) and mq.TLO.Cursor() then
            LNS.TempSettings['Search' .. varSub] = mq.TLO.Cursor()
            mq.cmdf("/autoinv")
        end

        ImGui.SameLine()

        if ImGui.SmallButton(Icons.MD_DELETE_SWEEP) then
            LNS.TempSettings['Search' .. varSub] = nil
        end
        if ImGui.IsItemHovered() then ImGui.SetTooltip("Clear Search") end

        local col = 4
        col = math.max(4, math.floor(ImGui.GetContentRegionAvail() / 140))
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
            if LNS.SearchLootTable(LNS.TempSettings['Search' .. varSub], LNS.ItemNames[id], rule) then
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
            if LNS.TempSettings.BulkRule == nil then
                LNS.TempSettings.BulkRule = settingList[1]
            end
            if ImGui.BeginCombo("Rule", LNS.TempSettings.BulkRule) then
                for i, setting in ipairs(settingList) do
                    local isSelected = LNS.TempSettings.BulkRulee == setting
                    if ImGui.Selectable(setting, isSelected) then
                        LNS.TempSettings.BulkRule = setting
                    end
                end
                ImGui.EndCombo()
            end
            ImGui.SameLine()
            if LNS.TempSettings.BulkRule == 'Quest' then
                ImGui.SetNextItemWidth(100)
                if LNS.TempSettings.BulkQuestAmount == nil then
                    LNS.TempSettings.BulkQuestAmount = 0
                end
                LNS.TempSettings.BulkQuestAmount = ImGui.InputInt("Amount", LNS.TempSettings.BulkQuestAmount, 1, 1)
                ImGui.SameLine()
            end
            ImGui.SetNextItemWidth(100)
            if LNS.TempSettings.BulkClasses == nil then
                LNS.TempSettings.BulkClasses = "All"
            end
            LNS.TempSettings.BulkClasses = ImGui.InputTextWithHint("Classes", "who can loot or all ex: shm clr dru", LNS.TempSettings.BulkClasses)

            ImGui.SameLine()
            ImGui.SetNextItemWidth(100)
            if LNS.TempSettings.BulkSetTable == nil then
                LNS.TempSettings.BulkSetTable = label .. "_Rules"
            end
            if ImGui.BeginCombo("Table", LNS.TempSettings.BulkSetTable) then
                for i, v in ipairs(tableListRules) do
                    if ImGui.Selectable(v, LNS.TempSettings.BulkSetTable == v) then
                        LNS.TempSettings.BulkSetTable = v
                    end
                end
                ImGui.EndCombo()
            end

            ImGui.PopID()

            if ImGui.Button(Icons.FA_CHECK .. " All") then
                for i = startIndex, endIndex do
                    local itemID = filteredItems[i].id
                    LNS.TempSettings.SelectedItems[itemID] = true
                end
            end

            ImGui.SameLine()
            if ImGui.Button("Clear Selected") then
                for id, selected in pairs(LNS.TempSettings.SelectedItems) do
                    LNS.TempSettings.SelectedItems[id] = false
                end
            end

            ImGui.PushStyleColor(ImGuiCol.Button, ImVec4(0.4, 1.0, 0.4, 0.4))
            if ImGui.Button("Set Selected") then
                LNS.TempSettings.BulkSet = {}
                for itemID, isSelected in pairs(LNS.TempSettings.SelectedItems) do
                    if isSelected then
                        local tmpRule = "Quest"
                        if LNS.TempSettings.BulkRule == 'Quest' then
                            if LNS.TempSettings.BulkQuestAmount > 0 then
                                tmpRule = string.format("Quest|%s", LNS.TempSettings.BulkQuestAmount)
                            end
                        else
                            tmpRule = LNS.TempSettings.BulkRule
                        end
                        LNS.TempSettings.BulkSet[itemID] = {
                            Rule = tmpRule,
                            Link = LNS.ItemLinks[itemID] or "NULL",
                        }
                    end
                end
                LNS.TempSettings.doBulkSet = true
            end
            ImGui.PopStyleColor()


            ImGui.SameLine()

            ImGui.PushStyleColor(ImGuiCol.Button, ImVec4(1.0, 0.4, 0.4, 0.4))
            if ImGui.Button("Delete Selected") then
                LNS.TempSettings.BulkSet = {}
                for itemID, isSelected in pairs(LNS.TempSettings.SelectedItems) do
                    if isSelected then
                        LNS.TempSettings.BulkSet[itemID] = { Rule = "Delete", Link = "NULL", }
                    end
                end
                LNS.TempSettings.doBulkSet = true
                LNS.TempSettings.bulkDelete = true
            end
            ImGui.PopStyleColor()
            ImGui.Unindent(2)
        end

        if ImGui.BeginTable(label .. " Items", colCount, bit32.bor(ImGuiTableFlags.Borders, ImGuiTableFlags.Resizable, ImGuiTableFlags.ScrollY), ImVec2(0.0, 0.0)) then
            ImGui.TableSetupScrollFreeze(colCount, 1)
            for i = 1, colCount / 4 do
                ImGui.TableSetupColumn(Icons.FA_CHECK, ImGuiTableColumnFlags.WidthFixed, 30)
                ImGui.TableSetupColumn("Item", ImGuiTableColumnFlags.WidthStretch)
                ImGui.TableSetupColumn("Rule", ImGuiTableColumnFlags.WidthFixed, 40)
                ImGui.TableSetupColumn('Classes', ImGuiTableColumnFlags.WidthFixed, 90)
            end
            ImGui.TableSetupScrollFreeze(colCount, 1)
            ImGui.TableHeadersRow()

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
                    if LNS.SearchLootTable(LNS.TempSettings['Search' .. varSub], item, setting) then
                        ImGui.TableNextColumn()
                        ImGui.PushID(itemID .. "_checkbox")
                        if LNS.TempSettings.SelectedItems[itemID] == nil then
                            LNS.TempSettings.SelectedItems[itemID] = false
                        end
                        local isSelected = LNS.TempSettings.SelectedItems[itemID]
                        isSelected = ImGui.Checkbox("##select", isSelected)
                        LNS.TempSettings.SelectedItems[itemID] = isSelected
                        ImGui.PopID()
                        ImGui.TableNextColumn()

                        ImGui.Indent(2)
                        local btnColor, btnText = ImVec4(0.0, 0.6, 0.0, 0.4), Icons.FA_PENCIL
                        if LNS.ItemIcons[itemID] == nil then
                            btnColor, btnText = ImVec4(0.6, 0.0, 0.0, 0.4), Icons.MD_CLOSE
                        end
                        ImGui.PushStyleColor(ImGuiCol.Button, btnColor)
                        if ImGui.SmallButton(btnText) then
                            LNS.TempSettings.ModifyItemRule = true
                            LNS.TempSettings.ModifyItemName = itemName
                            LNS.TempSettings.ModifyItemLink = itemLink
                            LNS.TempSettings.ModifyItemID = itemID
                            LNS.TempSettings.ModifyItemTable = label .. "_Items"
                            LNS.TempSettings.ModifyClasses = classes
                            LNS.TempSettings.ModifyItemSetting = setting
                            tempValues = {}
                        end
                        ImGui.PopStyleColor()

                        ImGui.SameLine()
                        if iconID then
                            LNS.drawIcon(iconID, iconSize * fontScale) -- icon
                        else
                            LNS.drawIcon(4493, iconSize * fontScale)   -- icon
                        end
                        if ImGui.IsItemHovered() and ImGui.IsMouseClicked(0) then
                            mq.cmdf('/executelink %s', itemLink)
                        end
                        ImGui.SameLine(0, 0)

                        ImGui.Text(itemName)
                        if ImGui.IsItemHovered() then
                            LNS.DrawRuleToolTip(itemName, setting, classes:upper())

                            if ImGui.IsMouseClicked(1) and itemLink ~= nil then
                                mq.cmdf('/executelink %s', itemLink)
                            end
                        end
                        ImGui.Unindent(2)
                        ImGui.TableNextColumn()
                        ImGui.Indent(2)
                        LNS.drawSettingIcon(setting)

                        if ImGui.IsItemHovered() then
                            LNS.DrawRuleToolTip(itemName, setting, classes:upper())
                            if ImGui.IsMouseClicked(1) and itemLink ~= nil then
                                mq.cmdf('/executelink %s', itemLink)
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
                            LNS.DrawRuleToolTip(itemName, setting, classes:upper())
                            if ImGui.IsMouseClicked(1) and itemLink ~= nil then
                                mq.cmdf('/executelink %s', itemLink)
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

function LNS.drawItemsTables()
    ImGui.SetNextItemWidth(100)
    fontScale = ImGui.SliderFloat("Font Scale", fontScale, 1, 2)
    ImGui.SetWindowFontScale(fontScale)

    if ImGui.BeginTabBar("Items", bit32.bor(ImGuiTabBarFlags.Reorderable, ImGuiTabBarFlags.FittingPolicyScroll)) then
        local col = math.max(2, math.floor(ImGui.GetContentRegionAvail() / 150))
        col = col + (col % 2)

        -- Buy Items
        if ImGui.BeginTabItem("Buy Items") then
            if LNS.TempSettings.BuyItems == nil then
                LNS.TempSettings.BuyItems = {}
            end
            -- ImGui.Text("Delete the Item Name to remove it from the table")

            -- if ImGui.SmallButton("Save Changes##BuyItems") then
            --     LNS.TempSettings.NeedSave = true
            -- end

            ImGui.SeparatorText("Add New Item")
            if ImGui.BeginTable("AddItem", 2, ImGuiTableFlags.Borders) then
                ImGui.TableSetupColumn("Item", ImGuiTableColumnFlags.WidthFixed, 280)
                ImGui.TableSetupColumn("Qty", ImGuiTableColumnFlags.WidthFixed, 150)
                ImGui.TableHeadersRow()
                ImGui.TableNextColumn()

                ImGui.SetNextItemWidth(150)
                ImGui.PushID("NewBuyItem")
                LNS.TempSettings.NewBuyItem = ImGui.InputText("New Item##BuyItems", LNS.TempSettings.NewBuyItem)
                ImGui.PopID()
                if ImGui.IsItemHovered() and mq.TLO.Cursor() ~= nil then
                    LNS.TempSettings.NewBuyItem = mq.TLO.Cursor()
                    mq.cmdf("/autoinv")
                end
                ImGui.SameLine()
                ImGui.PushStyleColor(ImGuiCol.Button, ImVec4(0.4, 1.0, 0.4, 0.4))
                if ImGui.SmallButton(Icons.MD_ADD) then
                    LNS.BuyItemsTable[LNS.TempSettings.NewBuyItem] = LNS.TempSettings.NewBuyQty
                    LNS.setBuyItem(LNS.TempSettings.NewBuyItem, LNS.TempSettings.NewBuyQty)
                    LNS.TempSettings.NeedSave = true
                    LNS.TempSettings.NewBuyItem = ""
                    LNS.TempSettings.NewBuyQty = 1
                end
                ImGui.PopStyleColor()

                ImGui.SameLine()
                ImGui.PushStyleColor(ImGuiCol.Button, ImVec4(1.0, 0.4, 0.4, 0.4))
                if ImGui.SmallButton(Icons.MD_DELETE_SWEEP) then
                    LNS.TempSettings.NewBuyItem = ""
                end
                ImGui.PopStyleColor()
                ImGui.TableNextColumn()
                ImGui.SetNextItemWidth(120)

                LNS.TempSettings.NewBuyQty = ImGui.InputInt("New Qty##BuyItems", (LNS.TempSettings.NewBuyQty or 1),
                    1, 50)
                if LNS.TempSettings.NewBuyQty > 1000 then LNS.TempSettings.NewBuyQty = 1000 end

                ImGui.EndTable()
            end
            ImGui.SeparatorText("Buy Items Table")
            if ImGui.BeginTable("Buy Items", col, bit32.bor(ImGuiTableFlags.Borders, ImGuiTableFlags.ScrollY), ImVec2(0.0, 0.0)) then
                ImGui.TableSetupScrollFreeze(col, 1)
                for i = 1, col / 2 do
                    ImGui.TableSetupColumn("Item")
                    ImGui.TableSetupColumn("Qty")
                end
                ImGui.TableHeadersRow()

                local numDisplayColumns = col / 2

                if LNS.BuyItemsTable ~= nil and LNS.TempSettings.SortedBuyItemKeys ~= nil then
                    local numItems = #LNS.TempSettings.SortedBuyItemKeys
                    local numRows = math.ceil(numItems / numDisplayColumns)

                    for row = 1, numRows do
                        for column = 0, numDisplayColumns - 1 do
                            local index = row + column * numRows
                            local k = LNS.TempSettings.SortedBuyItemKeys[index]
                            if k then
                                local v = LNS.BuyItemsTable[k]
                                ImGui.PushID(k .. v)

                                LNS.TempSettings.BuyItems[k] = LNS.TempSettings.BuyItems[k] or
                                    { Key = k, Value = v, }

                                ImGui.TableNextColumn()

                                ImGui.Text(LNS.TempSettings.BuyItems[k].Key)

                                ImGui.TableNextColumn()
                                ImGui.SetNextItemWidth(60)

                                local newValue = ImGui.InputText("##Value" .. k,
                                    LNS.TempSettings.BuyItems[k].Value)

                                ImGui.SameLine()
                                ImGui.PushStyleColor(ImGuiCol.Button, ImVec4(1.0, 0.4, 0.4, 0.4))
                                if ImGui.SmallButton(Icons.MD_DELETE) then
                                    LNS.TempSettings.DeletedBuyKeys[k] = true
                                    LNS.TempSettings.NeedSave = true
                                end
                                ImGui.PopStyleColor()
                                ImGui.SameLine()
                                ImGui.PushStyleColor(ImGuiCol.Button, ImVec4(0.4, 1.0, 0.4, 0.4))
                                if ImGui.SmallButton(Icons.MD_SAVE) then
                                    LNS.TempSettings.UpdatedBuyItems[k] = newValue
                                    LNS.TempSettings.NeedSave = true
                                end
                                ImGui.PopStyleColor()

                                LNS.TempSettings.BuyItems[k].Key = k
                                LNS.TempSettings.BuyItems[k].Value = newValue
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
        LNS.drawTabbedTable("Personal")

        -- Global Items

        LNS.drawTabbedTable("Global")

        -- Normal Items
        LNS.drawTabbedTable("Normal")

        -- Missing Items

        if LNS.HasMissingItems then
            if ImGui.BeginTabItem('Missing Items') then
                LNS.renderMissingItemsTables()
                ImGui.EndTabItem()
            end
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
                LNS.TempSettings.SearchItems, changed = ImGui.InputTextWithHint("Search Items##AllItems", "Lookup Name or Filter Class",
                    LNS.TempSettings.SearchItems, ImGuiInputTextFlags.EnterReturnsTrue)

                ImGui.PopID()
                if changed and LNS.TempSettings.SearchItems and LNS.TempSettings.SearchItems ~= '' then
                    LNS.TempSettings.LookUpItem = true
                end

                if ImGui.IsItemHovered(ImGuiHoveredFlags.DelayShort) and mq.TLO.Cursor() then
                    LNS.TempSettings.SearchItems = mq.TLO.Cursor.Name()
                    mq.cmdf("/autoinv")
                end
                ImGui.SameLine()

                if ImGui.SmallButton(Icons.MD_DELETE_SWEEP) then
                    LNS.TempSettings.SearchItems = nil
                    LNS.TempSettings.SearchResults = nil
                end
                if ImGui.IsItemHovered() then ImGui.SetTooltip("Clear Search") end

                ImGui.SameLine()

                ImGui.PushStyleColor(ImGuiCol.Button, ImVec4(0.78, 0.20, 0.05, 0.6))
                if ImGui.SmallButton("LookupItem##AllItems") then
                    LNS.TempSettings.LookUpItem = true
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
                if LNS.TempSettings.SearchResults == nil then
                    for id, item in pairs(LNS.ALLITEMS) do
                        if LNS.SearchLootTable(LNS.TempSettings.SearchItems, item.Name, item.ClassList) or
                            LNS.SearchLootTable(LNS.TempSettings.SearchItems, id, item.ClassList) then
                            table.insert(filteredItems, { id = id, data = item, })
                        end
                    end
                    table.sort(filteredItems, function(a, b) return a.data.Name < b.data.Name end)
                else
                    filteredItems = LNS.TempSettings.SearchResults
                    -- for k, v in pairs(LNS.TempSettings.SearchResults) do
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
                    if LNS.TempSettings.BulkRule == nil then
                        LNS.TempSettings.BulkRule = settingList[1]
                    end
                    if ImGui.BeginCombo("Rule", LNS.TempSettings.BulkRule) then
                        for i, setting in ipairs(settingList) do
                            local isSelected = LNS.TempSettings.BulkRulee == setting
                            if ImGui.Selectable(setting, isSelected) then
                                LNS.TempSettings.BulkRule = setting
                            end
                        end
                        ImGui.EndCombo()
                    end
                    ImGui.SameLine()
                    ImGui.SetNextItemWidth(100)
                    if LNS.TempSettings.BulkClasses == nil then
                        LNS.TempSettings.BulkClasses = "All"
                    end
                    LNS.TempSettings.BulkClasses = ImGui.InputTextWithHint("Classes", "who can loot or all ex: shm clr dru", LNS.TempSettings.BulkClasses)

                    ImGui.SameLine()
                    ImGui.SetNextItemWidth(100)
                    if LNS.TempSettings.BulkSetTable == nil then
                        LNS.TempSettings.BulkSetTable = "Normal_Rules"
                    end
                    if ImGui.BeginCombo("Table", LNS.TempSettings.BulkSetTable) then
                        for i, v in ipairs(tableListRules) do
                            if ImGui.Selectable(v, LNS.TempSettings.BulkSetTable == v) then
                                LNS.TempSettings.BulkSetTable = v
                            end
                        end
                        ImGui.EndCombo()
                    end

                    ImGui.PopID()
                    if ImGui.Button(Icons.FA_CHECK .. " All") then
                        for i = startIndex, endIndex do
                            local itemID = filteredItems[i].id
                            LNS.TempSettings.SelectedItems[itemID] = true
                        end
                    end

                    ImGui.SameLine()
                    if ImGui.Button("Clear Selected") then
                        for id, selected in pairs(LNS.TempSettings.SelectedItems) do
                            LNS.TempSettings.SelectedItems[id] = false
                        end
                    end

                    ImGui.PushStyleColor(ImGuiCol.Button, ImVec4(0.4, 1.0, 0.4, 0.4))
                    if ImGui.Button("Set Selected") then
                        LNS.TempSettings.BulkSet = {}
                        for itemID, isSelected in pairs(LNS.TempSettings.SelectedItems) do
                            if isSelected then
                                LNS.TempSettings.BulkSet[itemID] = {
                                    Rule = LNS.TempSettings.BulkRule,
                                    Link = LNS.ALLITEMS[itemID].Link or "NULL",
                                }
                            end
                        end
                        LNS.TempSettings.doBulkSet = true
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
                            ImGui.TableSetupColumn(label, ImGuiTableColumnFlags.NoHide)
                        else
                            ImGui.TableSetupColumn(label, ImGuiTableColumnFlags.DefaultHide)
                        end
                    end
                    ImGui.TableSetupScrollFreeze(2, 1)
                    ImGui.TableHeadersRow()

                    -- Render only the current page's items
                    for i = startIndex, endIndex do
                        local id = filteredItems[i].id
                        local item = filteredItems[i].data
                        ImGui.TableNextColumn()
                        ImGui.PushID(id .. "_checkbox")
                        if LNS.TempSettings.SelectedItems[id] == nil then
                            LNS.TempSettings.SelectedItems[id] = false
                        end
                        local isSelected = LNS.TempSettings.SelectedItems[id]
                        isSelected = ImGui.Checkbox("##select", isSelected)
                        LNS.TempSettings.SelectedItems[id] = isSelected
                        ImGui.PopID()
                        ImGui.PushID(id)

                        -- Render each column for the item
                        ImGui.TableNextColumn()
                        ImGui.Indent(2)
                        LNS.drawIcon(item.Icon, iconSize * fontScale)
                        if ImGui.IsItemHovered() and ImGui.IsMouseClicked(0) then
                            mq.cmdf('/executelink %s', item.Link)
                        end
                        ImGui.SameLine()
                        if ImGui.Selectable(item.Name, false) then
                            LNS.TempSettings.ModifyItemRule = true
                            LNS.TempSettings.ModifyItemID = id
                            LNS.TempSettings.ModifyClasses = item.ClassList
                            LNS.TempSettings.ModifyItemRaceList = item.RaceList
                            LNS.TempSettings.ModifyItemName = item.Name

                            tempValues = {}
                        end
                        if ImGui.IsItemHovered() and ImGui.IsMouseClicked(1) then
                            mq.cmdf('/executelink %s', item.Link)
                        end
                        ImGui.Unindent(2)
                        ImGui.TableNextColumn()
                        -- sell_value
                        if item.Value ~= '0 pp 0 gp 0 sp 0 cp' then
                            LNS.SafeText(item.Value)
                        end
                        ImGui.TableNextColumn()
                        LNS.SafeText(item.Tribute)     -- tribute_value
                        ImGui.TableNextColumn()
                        LNS.SafeText(item.Stackable)   -- stackable
                        ImGui.TableNextColumn()
                        LNS.SafeText(item.StackSize)   -- stack_size
                        ImGui.TableNextColumn()
                        LNS.SafeText(item.NoDrop)      -- nodrop
                        ImGui.TableNextColumn()
                        LNS.SafeText(item.NoTrade)     -- notrade
                        ImGui.TableNextColumn()
                        LNS.SafeText(item.Tradeskills) -- tradeskill
                        ImGui.TableNextColumn()
                        LNS.SafeText(item.Quest)       -- quest
                        ImGui.TableNextColumn()
                        LNS.SafeText(item.Lore)        -- lore
                        ImGui.TableNextColumn()
                        LNS.SafeText(item.Collectible) -- collectible
                        ImGui.TableNextColumn()
                        LNS.SafeText(item.Augment)     -- augment
                        ImGui.TableNextColumn()
                        LNS.SafeText(item.AugType)     -- augtype
                        ImGui.TableNextColumn()
                        LNS.SafeText(item.Clicky)      -- clickable
                        ImGui.TableNextColumn()
                        local tmpWeight = item.Weight ~= nil and item.Weight or 0
                        LNS.SafeText(tmpWeight)      -- weight
                        ImGui.TableNextColumn()
                        LNS.SafeText(item.AC)        -- ac
                        ImGui.TableNextColumn()
                        LNS.SafeText(item.Damage)    -- damage
                        ImGui.TableNextColumn()
                        LNS.SafeText(item.strength)  -- strength
                        ImGui.TableNextColumn()
                        LNS.SafeText(item.DEX)       -- dexterity
                        ImGui.TableNextColumn()
                        LNS.SafeText(item.AGI)       -- agility
                        ImGui.TableNextColumn()
                        LNS.SafeText(item.STA)       -- stamina
                        ImGui.TableNextColumn()
                        LNS.SafeText(item.INT)       -- intelligence
                        ImGui.TableNextColumn()
                        LNS.SafeText(item.WIS)       -- wisdom
                        ImGui.TableNextColumn()
                        LNS.SafeText(item.CHA)       -- charisma
                        ImGui.TableNextColumn()
                        LNS.SafeText(item.HP)        -- hp
                        ImGui.TableNextColumn()
                        LNS.SafeText(item.HPRegen)   -- regen_hp
                        ImGui.TableNextColumn()
                        LNS.SafeText(item.Mana)      -- mana
                        ImGui.TableNextColumn()
                        LNS.SafeText(item.ManaRegen) -- regen_mana
                        ImGui.TableNextColumn()
                        LNS.SafeText(item.Haste)     -- haste
                        ImGui.TableNextColumn()
                        LNS.SafeText(item.Classes)   -- classes
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
                        LNS.SafeText(item.svFire)          -- svfire
                        ImGui.TableNextColumn()
                        LNS.SafeText(item.svCold)          -- svcold
                        ImGui.TableNextColumn()
                        LNS.SafeText(item.svDisease)       -- svdisease
                        ImGui.TableNextColumn()
                        LNS.SafeText(item.svPoison)        -- svpoison
                        ImGui.TableNextColumn()
                        LNS.SafeText(item.svCorruption)    -- svcorruption
                        ImGui.TableNextColumn()
                        LNS.SafeText(item.svMagic)         -- svmagic
                        ImGui.TableNextColumn()
                        LNS.SafeText(item.SpellDamage)     -- spelldamage
                        ImGui.TableNextColumn()
                        LNS.SafeText(item.SpellShield)     -- spellshield
                        ImGui.TableNextColumn()
                        LNS.SafeText(item.Size)            -- item_size
                        ImGui.TableNextColumn()
                        LNS.SafeText(item.WeightReduction) -- weightreduction
                        ImGui.TableNextColumn()
                        LNS.SafeText(item.Races)           -- races
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

                        LNS.SafeText(item.Range)              -- item_range
                        ImGui.TableNextColumn()
                        LNS.SafeText(item.Attack)             -- attack
                        ImGui.TableNextColumn()
                        LNS.SafeText(item.StrikeThrough)      -- strikethrough
                        ImGui.TableNextColumn()
                        LNS.SafeText(item.HeroicAGI)          -- heroicagi
                        ImGui.TableNextColumn()
                        LNS.SafeText(item.HeroicCHA)          -- heroiccha
                        ImGui.TableNextColumn()
                        LNS.SafeText(item.HeroicDEX)          -- heroicdex
                        ImGui.TableNextColumn()
                        LNS.SafeText(item.HeroicINT)          -- heroicint
                        ImGui.TableNextColumn()
                        LNS.SafeText(item.HeroicSTA)          -- heroicsta
                        ImGui.TableNextColumn()
                        LNS.SafeText(item.HeroicSTR)          -- heroicstr
                        ImGui.TableNextColumn()
                        LNS.SafeText(item.HeroicSvCold)       -- heroicsvcold
                        ImGui.TableNextColumn()
                        LNS.SafeText(item.HeroicSvCorruption) -- heroicsvcorruption
                        ImGui.TableNextColumn()
                        LNS.SafeText(item.HeroicSvDisease)    -- heroicsvdisease
                        ImGui.TableNextColumn()
                        LNS.SafeText(item.HeroicSvFire)       -- heroicsvfire
                        ImGui.TableNextColumn()
                        LNS.SafeText(item.HeroicSvMagic)      -- heroicsvmagic
                        ImGui.TableNextColumn()
                        LNS.SafeText(item.HeroicSvPoison)     -- heroicsvpoison
                        ImGui.TableNextColumn()
                        LNS.SafeText(item.HeroicWIS)          -- heroicwis

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
            LNS.drawNewItemsTable()
            ImGui.EndTabItem()
        end
    end
    ImGui.EndTabBar()
end

function LNS.DrawRuleToolTip(name, setting, classes)
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

    ImGui.Separator()
    ImGui.Text("Right Click to View Item Details")

    ImGui.EndTooltip()
end

function LNS.drawSettingIcon(setting)
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
function LNS.DrawToolTip(message)
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
function LNS.DrawToggle(id, value, on_color, off_color, height, width)
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
            if not LNS.DrawToolTip(LNS.Tooltips[label]) then
                LNS.DrawToolTip(LNS.Tooltips[id:gsub("##", "")])
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
        if not LNS.DrawToolTip(LNS.Tooltips[label]) then
            LNS.DrawToolTip(LNS.Tooltips[id:gsub("##", "")])
        end
    end

    return value, clicked
end

function LNS.drawSwitch(settingName, who)
    if LNS.TempSettings[who] ~= nil then
        local clicked = false
        LNS.TempSettings[who][settingName], clicked = LNS.DrawToggle("##" .. settingName, LNS.TempSettings[who][settingName],
            ImVec4(0.4, 1.0, 0.4, 0.4), ImVec4(1.0, 0.4, 0.4, 0.4))

        if clicked then
            if LNS.Boxes[who][settingName] ~= LNS.TempSettings[who][settingName] then
                LNS.Boxes[who][settingName] = LNS.TempSettings[who][settingName]
                if who == MyName then
                    LNS.Settings[settingName] = LNS.TempSettings[who][settingName]
                    LNS.TempSettings.NeedSave = true
                end
            end
            if settingName == 'MasterLooting' then
                LNS.send({ who = MyName, action = 'master_looter', select = LNS.Settings.MasterLooting, Server = eqServer, })
            end
        end
    end
end

function LNS.renderSettingsTables(who)
    if who == nil then return end

    local col = 2
    col = math.max(2, math.floor(ImGui.GetContentRegionAvail() / 140))
    local colCount = col + (col % 2)
    if colCount % 2 ~= 0 then
        if (colCount - 1) % 2 == 0 then
            colCount = colCount - 1
        else
            colCount = colCount - 2
        end
    end
    local sorted_settings = LNS.SortTableColums(nil, LNS.TempSettings.SortedSettingsKeys, colCount / 2)
    local sorted_toggles = LNS.SortTableColums(nil, LNS.TempSettings.SortedToggleKeys, colCount / 2)

    if ImGui.CollapsingHeader(string.format("Settings %s##%s", who, who)) then
        if ImGui.BeginTable("##Settings", colCount, bit32.bor(ImGuiTableFlags.Borders, ImGuiTableFlags.AutoResizeY, ImGuiTableFlags.Resizable)) then
            ImGui.TableSetupScrollFreeze(colCount, 1)
            for i = 1, colCount / 2 do
                ImGui.TableSetupColumn("Setting", ImGuiTableColumnFlags.WidthStretch)
                ImGui.TableSetupColumn("Value", ImGuiTableColumnFlags.WidthFixed, 80)
            end
            ImGui.TableHeadersRow()

            for i, settingName in ipairs(sorted_settings or {}) do
                if who == nil then break end
                if not settingsNoDraw[settingName] then
                    if LNS.TempSettings[who] == nil then
                        LNS.TempSettings[who] = {}
                    end
                    if LNS.TempSettings[who][settingName] == nil then
                        LNS.TempSettings[who][settingName] = LNS.Boxes[who][settingName]
                    end
                    if who ~= nil and LNS.TempSettings[who][settingName] ~= nil and type(LNS.Boxes[who][settingName]) ~= "boolean" then
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
                            LNS.DrawToolTip(LNS.Tooltips[settingName])
                            ImGui.EndTooltip()
                        end
                        ImGui.Unindent(2)
                        ImGui.TableNextColumn()
                        if type(LNS.Boxes[who][settingName]) == "number" then
                            ImGui.SetNextItemWidth(ImGui.GetColumnWidth(-1))

                            LNS.TempSettings[who][settingName] = ImGui.InputInt("##" .. settingName, LNS.TempSettings[who][settingName])
                            if LNS.Boxes[who][settingName] ~= LNS.TempSettings[who][settingName] then
                                LNS.Boxes[who][settingName] = LNS.TempSettings[who][settingName]
                                if who == MyName then
                                    LNS.Settings[settingName] = LNS.Boxes[who][settingName]
                                    LNS.TempSettings.NeedSave = true
                                end
                            end
                        elseif type(LNS.Boxes[who][settingName]) == "string" then
                            ImGui.SetNextItemWidth(ImGui.GetColumnWidth(-1))
                            LNS.TempSettings[who][settingName] = ImGui.InputText("##" .. settingName, LNS.TempSettings[who][settingName])
                            if LNS.Boxes[who][settingName] ~= LNS.TempSettings[who][settingName] then
                                LNS.Boxes[who][settingName] = LNS.TempSettings[who][settingName]
                                if who == MyName then
                                    LNS.Settings[settingName] = LNS.Boxes[who][settingName]
                                    LNS.TempSettings.NeedSave = true
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
                            LNS.DrawToolTip(LNS.Tooltips[settingName])
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
        if ImGui.BeginTable("Toggles##1", colCount, bit32.bor(ImGuiTableFlags.Borders, ImGuiTableFlags.Resizable, ImGuiTableFlags.ScrollY)) then
            ImGui.TableSetupScrollFreeze(2, 1)
            for i = 1, 2 / 2 do
                ImGui.TableSetupColumn("Setting", ImGuiTableColumnFlags.WidthStretch)
                ImGui.TableSetupColumn("Value", ImGuiTableColumnFlags.WidthFixed, 80)
            end
            ImGui.TableHeadersRow()

            for i, settingName in ipairs(sorted_toggles or {}) do
                if who == nil then break end
                if not settingsNoDraw[settingName] then
                    if LNS.TempSettings[who] == nil then
                        LNS.TempSettings[who] = {}
                    end
                    if LNS.TempSettings[who][settingName] == nil then
                        LNS.TempSettings[who][settingName] = LNS.Boxes[who][settingName]
                    end
                    if who ~= nil and type(LNS.Boxes[who][settingName]) == "boolean" then
                        ImGui.PushID(settingName)
                        ImGui.TableNextColumn()
                        ImGui.Indent(2)
                        -- ImGui.Text(settingName)
                        if ImGui.Selectable(settingName) then
                            LNS.TempSettings[who][settingName] = not LNS.TempSettings[who][settingName]
                            if LNS.Boxes[who][settingName] ~= LNS.TempSettings[who][settingName] then
                                LNS.Boxes[who][settingName] = LNS.TempSettings[who][settingName]
                                if who == MyName then
                                    LNS.Settings[settingName] = LNS.Boxes[who][settingName]
                                    LNS.TempSettings.NeedSave = true
                                    Logger.Info(LNS.guiLoot.console, "Setting \ay%s\ax to \ag%s\ax", settingName, LNS.Settings[settingName])
                                end
                            end
                            if settingName == 'MasterLooting' then
                                LNS.send({ who = MyName, action = 'master_looter', select = LNS.Settings.MasterLooting, Server = eqServer, })
                            end
                        end
                        if ImGui.IsItemHovered() then
                            ImGui.BeginTooltip()
                            ImGui.PushTextWrapPos(200)
                            ImGui.Text("Setting: %s", settingName)
                            ImGui.Text("%s's Current Value: %s", who, LNS.Boxes[who][settingName] and "Enabled" or "Disabled")
                            ImGui.PopTextWrapPos()
                            ImGui.Separator()
                            LNS.DrawToolTip(LNS.Tooltips[settingName])
                            ImGui.EndTooltip()
                        end
                        ImGui.Unindent(2)
                        ImGui.TableNextColumn()
                        LNS.drawSwitch(settingName, who)
                        ImGui.PopID()
                    end
                end
            end
            ImGui.EndTable()
        end
    end
end

function LNS.renderCloneWindow()
    if not LNS.TempSettings.PopCloneWindow then
        return
    end
    ImGui.SetNextWindowSize(ImVec2(650, 400), ImGuiCond.Appearing)
    local openClone, showClone = ImGui.Begin("Clone Who##who_settings", true)
    if not openClone then
        LNS.TempSettings.CloneTo = nil
        LNS.TempSettings.PopCloneWindow = false
        showClone = false
    end
    if showClone then
        ImGui.SeparatorText("Clone Settings")
        ImGui.SetNextItemWidth(120)

        -- if ImGui.BeginCombo('##Source', LNS.TempSettings.CloneWho or "Select Source") then
        --     for _, k in ipairs(LNS.BoxKeys) do
        --         if ImGui.Selectable(k) then
        --             LNS.TempSettings.CloneWho = k
        --         end
        --     end
        --     ImGui.EndCombo()
        -- end

        -- ImGui.SameLine()

        -- ImGui.SetNextItemWidth(120)
        -- if ImGui.BeginCombo('##Dest', LNS.TempSettings.CloneTo or "Select Destination") then
        --     for _, k in ipairs(LNS.BoxKeys) do
        --         if ImGui.Selectable(k) then
        --             LNS.TempSettings.CloneTo = k
        --         end
        --     end
        --     ImGui.EndCombo()
        -- end
        ImGui.SetNextItemWidth(150)
        ImGui.InputTextWithHint("Clone Who##CloneWho", "Source Character", LNS.TempSettings.CloneWho or "", ImGuiInputTextFlags.ReadOnly)
        ImGui.SameLine()

        ImGui.SetNextItemWidth(150)
        ImGui.InputTextWithHint("Clone To##CloneTo", "Destination Character", LNS.TempSettings.CloneTo or "", ImGuiInputTextFlags.ReadOnly)

        if LNS.TempSettings.CloneWho and LNS.TempSettings.CloneTo then
            ImGui.SameLine()
            LNS.TempSettings.PopCloneWindow = true

            if ImGui.SmallButton("Clone Now") then
                LNS.Boxes[LNS.TempSettings.CloneTo] = LNS.Boxes[LNS.TempSettings.CloneWho]
                local tmpSet = LNS.Boxes[LNS.TempSettings.CloneWho]
                LNS.send({
                    action = 'updatesettings',
                    who = LNS.TempSettings.CloneTo,
                    settings = tmpSet,
                    Server = eqServer,
                })
                -- LNS.TempSettings.CloneWho = nil
                LNS.TempSettings.CloneTo = nil
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
                if LNS.TempSettings.CloneWho == k then
                    ImGui.PushStyleColor(ImGuiCol.Text, ImVec4(0.4, 1.0, 0.1, 1.0))
                elseif LNS.TempSettings.CloneTo == k then
                    ImGui.PushStyleColor(ImGuiCol.Text, ImVec4(0.0, 1.0, 1.0, 1.0))
                else
                    ImGui.PushStyleColor(ImGuiCol.Text, ImVec4(0.8, 0.8, 0.8, 1.0))
                end
                ImGui.Selectable(k, LNS.TempSettings.CloneWho == k or LNS.TempSettings.CloneTo == k)

                ImGui.PopStyleColor()
                if ImGui.BeginPopupContextItem("##CloneWhoContext") then
                    if ImGui.Selectable("Set as Source") then
                        if LNS.TempSettings.CloneTo == k then
                            LNS.TempSettings.CloneTo = nil
                        end
                        LNS.TempSettings.CloneWho = k
                    end
                    if ImGui.Selectable("Set as Destination") then
                        if LNS.TempSettings.CloneWho == k then
                            LNS.TempSettings.CloneWho = nil
                        end
                        LNS.TempSettings.CloneTo = k
                    end
                    if ImGui.Selectable("Clear Selection") then
                        if k == LNS.TempSettings.CloneWho then
                            LNS.TempSettings.CloneWho = nil
                        elseif k == LNS.TempSettings.CloneTo then
                            LNS.TempSettings.CloneTo = nil
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
            LNS.renderSettingsTables(LNS.TempSettings.CloneWho)
        end
        ImGui.EndChild()
        ImGui.SameLine()
        -- right panel

        if ImGui.BeginChild("Clone Who##who_settings_right", 200, 0.0, ImGuiChildFlags.Border) then
            ImGui.Text("Select Settings to Apply")
            ImGui.Separator()
            LNS.renderSettingsTables(LNS.TempSettings.CloneTo)
        end
        ImGui.EndChild()
    end
    ImGui.End()
end

function LNS.renderSettingsSection(who)
    if who == nil then who = MyName end


    ImGui.SameLine()

    if ImGui.SmallButton("Send Settings##LootnScoot") then
        LNS.send({
            action = 'updatesettings',
            who = who,
            settings = LNS.Boxes[who],
            Server = eqServer,
        })
    end

    ImGui.SameLine()

    if ImGui.SmallButton("Clone Settings##LootnScoot") then
        LNS.TempSettings.PopCloneWindow = true
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

    LNS.renderSettingsTables(who)

    ImGui.Spacing()

    if ImGui.CollapsingHeader('SafeZones##LNS') then
        if LNS.TempSettings.NewSafeZone == nil then
            LNS.TempSettings.NewSafeZone = ''
        end
        ImGui.SetNextItemWidth(150)
        LNS.TempSettings.NewSafeZone = ImGui.InputText("New SafeZone Name", LNS.TempSettings.NewSafeZone)
        ImGui.SameLine()
        if ImGui.Button('Add') then
            LNS.AddSafeZone(LNS.TempSettings.NewSafeZone)
            LNS.TempSettings.NewSafeZone = ''
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
                        if LNS.TempSettings.RemoveSafeZone == nil then
                            LNS.TempSettings.RemoveSafeZone = {}
                        end
                        LNS.TempSettings.RemoveSafeZone[settingName] = true
                    end
                    ImGui.PopID()
                end
            end
            ImGui.EndTable()
        end
    end
end

function LNS.renderNewItem()
    if ((LNS.Settings.AutoShowNewItem and LNS.NewItemsCount > 0) and showNewItem) or showNewItem then
        ImGui.SetNextWindowSize(600, 400, ImGuiCond.FirstUseEver)
        local open, show = ImGui.Begin('New Items', true)
        if not open then
            show = false
            showNewItem = false
        end
        if show then
            LNS.drawNewItemsTable()
        end
        ImGui.End()
    end
end

------------------------------------
--          GUI WINDOWS
------------------------------------

function LNS.RenderMasterLooterWindow()
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
                            LNS.drawYesNo(itemData.NoDrop)
                            ImGui.TableNextColumn()
                            LNS.drawYesNo(itemData.Lore)
                            ImGui.EndTable()
                        end
                        ImGui.TableNextColumn()

                        if ImGui.SmallButton(Icons.MD_DELETE .. "##MLRemove" .. cID .. item) then
                            Logger.Info(LNS.guiLoot.console, "Removing CorpseID %s Item %s from Master Loot List", cID, item)

                            LNS.TempSettings.RemoveItemData = { action = 'item_gone', CorpseID = cID, item = item, Server = eqServer, }
                            LNS.TempSettings.SendRemoveItem = true
                        end

                        ImGui.SameLine()

                        if ImGui.SmallButton("Self Loot##" .. cID .. item) then
                            Logger.Info(LNS.guiLoot.console, "Telling \atMySelf\ax to loot \ay%s\ax from CorpseID \ag%s", itemData.Link, cID)
                            -- LNS.TempSettings.SendLootInfo = {}
                            -- LNS.TempSettings.SendLootInfo =
                            LNS.send({ who = MyName, action = 'loot_item', CorpseID = cID, item = item, Server = eqServer, })
                            -- LNS.TempSettings.SendLoot = true
                        end

                        if ImGui.CollapsingHeader("Members##" .. cID .. item) then
                            if ImGui.SmallButton("Refresh Counts##" .. cID .. item) then
                                Logger.Info(LNS.guiLoot.console, "Refreshing Member Counts for CorpseID %s Item %s", cID, item)
                                LNS.send({ who = MyName, action = 'recheck_item', CorpseID = cID, item = item, Server = eqServer, })
                            end
                            if itemData.Members ~= nil and next(itemData.Members) ~= nil then
                                if ImGui.BeginTable('MemberCounts##List', 3, ImGuiTableFlags.Borders) then
                                    ImGui.TableSetupColumn("Member", ImGuiTableColumnFlags.WidthFixed, 110)
                                    ImGui.TableSetupColumn("Count", ImGuiTableColumnFlags.WidthFixed, 30)
                                    ImGui.TableSetupColumn("Loot", ImGuiTableColumnFlags.WidthFixed, 80)
                                    ImGui.TableHeadersRow()
                                    for _, k in ipairs(LNS.BoxKeys) do
                                        if itemData.Members[k] ~= nil then
                                            local member = k
                                            local count = itemData.Members[k]
                                            ImGui.TableNextRow()
                                            ImGui.TableNextColumn()

                                            if ImGui.Selectable(string.format("%s##%s", member, cID .. item)) then
                                                Logger.Info(LNS.guiLoot.console, "Selected member %s for CorpseID %s Item %s", member, cID, item)
                                                LNS.send({ who = member, action = 'loot_item', Server = eqServer, CorpseID = cID, item = item, })
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
                                                -- LNS.TempSettings.SendLootInfo = {}
                                                -- LNS.TempSettings.SendLootInfo =
                                                LNS.send({ who = member, action = 'loot_item', Server = eqServer, CorpseID = cID, item = item, })
                                                -- LNS.TempSettings.SendLoot = true
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
                                --         LNS.send({ who = member, action = 'loot_item', CorpseID = cID, item = item, })
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

function LNS.RenderModifyItemWindow()
    if not LNS.TempSettings.ModifyItemRule then
        Logger.Error(LNS.guiLoot.console, "Item not found in ALLITEMS %s %s", LNS.TempSettings.ModifyItemID, LNS.TempSettings.ModifyItemTable)
        LNS.TempSettings.ModifyItemRule = false
        LNS.TempSettings.ModifyItemID = nil
        LNS.TempSettings.LastModID = 0
        tempValues = {}
        return
    end
    if LNS.TempSettings.ModifyItemTable == 'Personal_Items' then
        LNS.TempSettings.ModifyItemTable = LNS.PersonalTableName
    end
    if LNS.TempSettings.ModifyItemTable == nil then
        LNS.TempSettings.ModifyItemTable = LNS.TempSettings.LastModTable or 'Normal_Items'
    end
    -- local missingTable = LNS.TempSettings.ModifyItemTable:gsub("_Items", "")
    local classes = LNS.TempSettings.ModifyClasses
    local rule = LNS.TempSettings.ModifyItemSetting

    ImGui.SetNextWindowSizeConstraints(ImVec2(300, 200), ImVec2(-1, -1))
    local open, show = ImGui.Begin("Modify Item", nil, ImGuiWindowFlags.AlwaysAutoResize)
    if show then
        local item = LNS.ALLITEMS[LNS.TempSettings.ModifyItemID]
        if not item then
            item = {
                Name = LNS.TempSettings.ModifyItemName,
                Link = LNS.TempSettings.ModifyItemLink,
                RaceList = LNS.TempSettings.ModifyItemRaceList,
            }
        end
        local questRule = "Quest"
        if item == nil then
            Logger.Error(LNS.guiLoot.console, "Item not found in ALLITEMS %s %s", LNS.TempSettings.ModifyItemID, LNS.TempSettings.ModifyItemTable)
            ImGui.End()
            return
        end
        ImGui.TextUnformatted("Item:")
        ImGui.SameLine()
        ImGui.TextColored(ImVec4(0, 1, 1, 1), item.Name)
        ImGui.SameLine()
        ImGui.TextUnformatted("ID:")
        ImGui.SameLine()
        ImGui.TextColored(ImVec4(1, 1, 0, 1), "%s", LNS.TempSettings.ModifyItemID)

        -- if ImGui.BeginCombo("Table", LNS.TempSettings.ModifyItemTable) then
        --     for i, v in ipairs(tableList) do
        --         if ImGui.Selectable(v, LNS.TempSettings.ModifyItemTable == v) then
        --             LNS.TempSettings.ModifyItemTable = v
        --         end
        --     end
        --     ImGui.EndCombo()
        -- end
        if ImGui.RadioButton("Personal Items", LNS.TempSettings.ModifyItemTable == LNS.PersonalTableName) then
            LNS.TempSettings.ModifyItemTable = LNS.PersonalTableName
        end
        ImGui.SameLine()
        if ImGui.RadioButton("Global Items", LNS.TempSettings.ModifyItemTable == "Global_Items") then
            LNS.TempSettings.ModifyItemTable = "Global_Items"
        end
        ImGui.SameLine()
        if ImGui.RadioButton("Normal Items", LNS.TempSettings.ModifyItemTable == "Normal_Items") then
            LNS.TempSettings.ModifyItemTable = "Normal_Items"
        end

        if tempValues.Classes == nil and classes ~= nil then
            tempValues.Classes = classes
        end

        ImGui.SetNextItemWidth(100)
        tempValues.Classes = ImGui.InputTextWithHint("Classes", "who can loot or all ex: shm clr dru", tempValues.Classes)

        ImGui.SameLine()
        LNS.TempModClass = ImGui.Checkbox("All", LNS.TempModClass)

        if tempValues.Rule == nil and rule ~= nil then
            tempValues.Rule = rule
        end

        ImGui.SetNextItemWidth(100)
        if ImGui.BeginCombo("Rule", tempValues.Rule) then
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
            if LNS.TempSettings.ModifyItemTable == LNS.PersonalTableName then
                LNS.PersonalItemsRules[LNS.TempSettings.ModifyItemID] = newRule
                LNS.setPersonalItem(LNS.TempSettings.ModifyItemID, newRule, tempValues.Classes, item.Link)
            elseif LNS.TempSettings.ModifyItemTable == "Global_Items" then
                LNS.GlobalItemsRules[LNS.TempSettings.ModifyItemID] = newRule
                LNS.setGlobalItem(LNS.TempSettings.ModifyItemID, newRule, tempValues.Classes, item.Link)
            else
                LNS.NormalItemsRules[LNS.TempSettings.ModifyItemID] = newRule
                LNS.setNormalItem(LNS.TempSettings.ModifyItemID, newRule, tempValues.Classes, item.Link)
            end
            -- loot.setNormalItem(loot.TempSettings.ModifyItemID, newRule,  tempValues.Classes, item.Link)
            LNS.TempSettings.ModifyItemRule = false
            LNS.TempSettings.ModifyItemID = nil
            LNS.TempSettings.LastModTable = LNS.TempSettings.ModifyItemTable
            LNS.TempSettings.ModifyItemTable = nil
            LNS.TempSettings.ModifyItemClasses = 'All'
            LNS.TempSettings.ModifyItemName = nil
            LNS.TempSettings.ModifyItemLink = nil
            LNS.TempModClass = false
            LNS.TempSettings.LastModID = 0
            ImGui.End()
            return
        end
        ImGui.SameLine()

        ImGui.PushStyleColor(ImGuiCol.Button, ImVec4(1.0, 0.4, 0.4, 0.4))
        if ImGui.Button(Icons.FA_TRASH) then
            if LNS.TempSettings.ModifyItemTable == LNS.PersonalTableName then
                LNS.PersonalItemsRules[LNS.TempSettings.ModifyItemID] = nil
                LNS.setPersonalItem(LNS.TempSettings.ModifyItemID, 'delete', 'All', 'NULL')
            elseif LNS.TempSettings.ModifyItemTable == "Global_Items" then
                -- loot.GlobalItemsRules[loot.TempSettings.ModifyItemID] = nil
                LNS.setGlobalItem(LNS.TempSettings.ModifyItemID, 'delete', 'All', 'NULL')
            else
                LNS.setNormalItem(LNS.TempSettings.ModifyItemID, 'delete', 'All', 'NULL')
            end
            LNS.TempSettings.ModifyItemRule = false
            LNS.TempSettings.ModifyItemID = nil
            LNS.TempSettings.ModifyItemTable = nil
            LNS.TempSettings.ModifyItemClasses = 'All'
            LNS.TempSettings.ModifyItemMatches = nil
            LNS.TempSettings.ModifyItemName = nil
            LNS.TempSettings.LastModID = 0

            ImGui.PopStyleColor()

            ImGui.End()
            return
        end
        ImGui.PopStyleColor()
        ImGui.SameLine()
        if ImGui.Button("Cancel") then
            LNS.TempSettings.ModifyItemRule = false
            LNS.TempSettings.ModifyItemID = nil
            LNS.TempSettings.ModifyItemTable = nil
            LNS.TempSettings.ModifyItemClasses = 'All'
            LNS.TempSettings.ModifyItemName = nil
            LNS.TempSettings.ModifyItemLink = nil
            LNS.TempSettings.ModifyItemMatches = nil
            LNS.TempSettings.LastModID = 0
        end

        if LNS.TempSettings.ModifyItemMatches ~= nil then
            local oldID = LNS.TempSettings.ModifyItemID
            local newRule = tempValues.Rule == "Quest" and questRule or tempValues.Rule
            if tempValues.Classes == nil or tempValues.Classes == '' or LNS.TempModClass then
                tempValues.Classes = "All"
            end
            if ImGui.BeginTable("Matches##LNS.ModifyItemMatches", 3, bit32.bor(ImGuiTableFlags.Borders, ImGuiTableFlags.Resizable, ImGuiTableFlags.ScrollY), ImVec2(300, 200)) then
                ImGui.TableSetupColumn("itemID", ImGuiTableColumnFlags.WidthStretch)
                ImGui.TableSetupColumn("itemName", ImGuiTableColumnFlags.WidthStretch)
                ImGui.TableSetupColumn("Set", ImGuiTableColumnFlags.WidthFixed, 80)
                ImGui.TableHeadersRow()

                --[[
retTable[row.item_id] = {
item_id = row.item_id,
item_name = row.name,
item_rule = row.item_rule or 'None',
item_classes = row.item_rule_classes or 'All',
item_link = row.link or 'NULL',
}]]
                for id, data in pairs(LNS.TempSettings.ModifyItemMatches) do
                    ImGui.TableNextColumn()
                    ImGui.Text("%s", id)

                    ImGui.TableNextColumn()
                    if ImGui.Selectable(data.item_name .. "##" .. id, false) then
                        mq.cmdf('/executelink %s', data.item_link)
                    end

                    ImGui.TableNextColumn()
                    if ImGui.Button(Icons.FA_CHECK .. "##" .. id) then
                        if LNS.TempSettings.ModifyItemTable == LNS.PersonalTableName then
                            LNS.setPersonalItem(id, newRule, tempValues.Classes, LNS.ItemLinks[id])
                            LNS.PersonalItemsMissing[oldID] = nil
                            LNS.PersonalItemsRules[oldID] = nil
                            LNS.PersonalItemsClasses[oldID] = nil
                            LNS.setPersonalItem(oldID, 'delete', 'All', 'NULL')
                        elseif LNS.TempSettings.ModifyItemTable == "Global_Items" then
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
                        LNS.TempSettings.ModifyItemRule = false
                        LNS.TempSettings.ModifyItemID = nil
                        LNS.TempSettings.ModifyItemTable = nil
                        LNS.TempSettings.ModifyItemClasses = 'All'
                        LNS.TempSettings.ModifyItemMatches = nil
                        LNS.TempSettings.LastModID = 0
                        ImGui.EndTable()
                        ImGui.End()
                        return
                    end
                end
                ImGui.EndTable()
            end
            --LNS.TempSettings.ModifyItemMatches
        end
    end
    if not open then
        LNS.TempSettings.ModifyItemRule = false
        LNS.TempSettings.ModifyItemID = nil
        LNS.TempSettings.ModifyItemTable = nil
        LNS.TempSettings.ModifyItemClasses = 'All'
        LNS.TempSettings.ModifyItemName = nil
        LNS.TempSettings.ModifyItemLink = nil
        LNS.TempSettings.ModifyItemMatches = nil
        LNS.TempSettings.LastModID = 0
    end
    ImGui.End()
end

function LNS.DrawRecord(tableToDraw)
    if not LNS.TempSettings.PastHistory then return end
    if tableToDraw == nil then tableToDraw = LNS.TempSettings.SessionHistory or {} end
    if LNS.HistoryDataDate ~= nil and #LNS.HistoryDataDate > 0 then
        tableToDraw = LNS.HistoryDataDate
    elseif LNS.HistoryItemData ~= nil and #LNS.HistoryItemData > 0 then
        tableToDraw = LNS.HistoryItemData
    end
    local openWin, showRecord = ImGui.Begin("Loot PastHistory##", true)
    if not openWin then
        LNS.TempSettings.PastHistory = false
    end

    if showRecord then
        if LNS.TempSettings.DateLookup == nil then
            LNS.TempSettings.DateLookup = os.date("%Y-%m-%d")
        end
        ImGui.SetNextItemWidth(150)
        if ImGui.BeginCombo('##', LNS.TempSettings.DateLookup) then
            for i, v in ipairs(LNS.HistoricalDates) do
                if ImGui.Selectable(v, LNS.TempSettings.DateLookup == v) then
                    LNS.TempSettings.DateLookup = v
                end
            end
            ImGui.EndCombo()
        end
        ImGui.SameLine()
        if ImGui.SmallButton(Icons.FA_CALENDAR .. "Load Date") then
            LNS.TempSettings.LookUpDateData = true
            lookupDate = LNS.TempSettings.DateLookup
        end
        if ImGui.IsItemHovered() then
            ImGui.SetTooltip("Load Data for %s", LNS.TempSettings.DateLookup)
        end
        ImGui.SameLine()
        if ImGui.SmallButton(Icons.MD_TIMELAPSE .. 'Session') then
            LNS.TempSettings.ClearDateData = true
        end
        if ImGui.IsItemHovered() then
            ImGui.SetTooltip("This Session Only", LNS.TempSettings.DateLookup)
        end
        if LNS.TempSettings.FilterHistory == nil then
            LNS.TempSettings.FilterHistory = ''
        end
        -- Pagination Variables
        local filteredTable = {}
        for i = 1, #tableToDraw do
            local item = tableToDraw[i]
            if item then
                if LNS.TempSettings.FilterHistory ~= '' then
                    local filterString = LNS.TempSettings.FilterHistory:lower()
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
        LNS.TempSettings.FilterHistory = ImGui.InputTextWithHint("##FilterHistory", "Filter by Fields", LNS.TempSettings.FilterHistory)
        ImGui.SameLine()
        if ImGui.SmallButton(Icons.MD_DELETE_SWEEP) then
            LNS.TempSettings.FilterHistory = ''
        end
        ImGui.SameLine()
        if ImGui.SmallButton(Icons.MD_SEARCH) then
            LNS.TempSettings.FindItemHistory = true
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

            -- Calculate start and end indices for pagination
            local startIdx = (LNS.histCurrentPage - 1) * LNS.histItemsPerPage + 1
            local endIdx = math.min(startIdx + LNS.histItemsPerPage - 1, totalFilteredItems)

            for i = startIdx, endIdx do
                local item = filteredTable[i]
                if item then
                    if LNS.TempSettings.FilterHistory ~= '' then
                        local filterString = LNS.TempSettings.FilterHistory:lower()
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
        local cursorX, cursorY = ImGui.GetCursorScreenPos() -- grab location for later to draw button over icon.
        if LNS.NewItemsCount > 0 then
            animMini:SetTextureCell(645 - EQ_ICON_OFFSET)   -- gold coin
        else
            animMini:SetTextureCell(644 - EQ_ICON_OFFSET)   -- platinum coin
        end
        if LNS.PauseLooting then
            animMini:SetTextureCell(1436 - EQ_ICON_OFFSET) -- red gem
            btnLbl = 'Paused##LNSBtn'
        end
        ImGui.DrawTextureAnimation(animMini, 34, 34, true)

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
                    showNewItem = not showNewItem
                end
            end
            if ImGui.MenuItem("Toggle Pause Looting") then
                LNS.PauseLooting = not LNS.PauseLooting
            end
            _, debugPrint = ImGui.MenuItem(Icons.FA_BUG .. " Debug", nil, debugPrint)
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

function LNS.RenderMainUI()
    if LNS.ShowUI then
        ImGui.SetNextWindowSize(800, 600, ImGuiCond.FirstUseEver)
        local open, show = ImGui.Begin('LootnScoot', true)
        if not open then
            show = false
            LNS.ShowUI = false
        end
        if show then
            local sizeY = ImGui.GetWindowHeight() - 10
            if ImGui.BeginChild('Main', 0.0, 400, bit32.bor(ImGuiChildFlags.ResizeY, ImGuiChildFlags.Border)) then
                ImGui.PushStyleColor(ImGuiCol.PopupBg, ImVec4(0.002, 0.009, 0.082, 0.991))
                local clicked = false
                debugPrint, clicked = LNS.DrawToggle("Debug##Toggle",
                    debugPrint,
                    ImVec4(0.4, 1.0, 0.4, 0.4),
                    ImVec4(1.0, 0.4, 0.4, 0.4),
                    16, 36)
                if clicked then
                    Logger.Warn(LNS.guiLoot.console, "\ayDebugging\ax is now %s", debugPrint and "\agon" or "\aroff")
                end
                ImGui.SameLine()

                if ImGui.SmallButton(Icons.MD_HELP_OUTLINE) then
                    LNS.TempSettings.ShowHelp = not LNS.TempSettings.ShowHelp
                end
                if ImGui.IsItemHovered() then
                    ImGui.SetTooltip("Show/Hide Help Window")
                end

                ImGui.SameLine()
                if ImGui.SmallButton(string.format("%s Report", Icons.MD_INSERT_CHART)) then
                    -- loot.guiLoot.showReport = not loot.guiLoot.showReport
                    LNS.Settings.ShowReport = not LNS.Settings.ShowReport
                    LNS.guiLoot.GetSettings(LNS.Settings.HideNames,

                        LNS.Settings.RecordData,
                        true,
                        LNS.Settings.UseActors,
                        'lootnscoot',
                        LNS.Settings.ShowReport,
                        LNS.Settings.ReportSkippedItems)
                    LNS.TempSettings.NeedSave = true
                end
                if ImGui.IsItemHovered() then ImGui.SetTooltip("Show/Hide Report Window") end

                ImGui.SameLine()

                if ImGui.SmallButton(Icons.MD_HISTORY .. " Historical") then
                    LNS.TempSettings.PastHistory = not LNS.TempSettings.PastHistory
                end
                if ImGui.IsItemHovered() then ImGui.SetTooltip("Show/Hide Historical Data") end

                ImGui.SameLine()


                if ImGui.SmallButton(string.format("%s Console", Icons.FA_TERMINAL)) then
                    LNS.guiLoot.openGUI = not LNS.guiLoot.openGUI
                    LNS.Settings.ShowConsole = LNS.guiLoot.openGUI
                    LNS.TempSettings.NeedSave = true
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


                ImGui.Spacing()
                ImGui.Separator()
                ImGui.Spacing()
                -- Settings Section
                if showSettings then
                    if LNS.TempSettings.SelectedActor == nil then
                        LNS.TempSettings.SelectedActor = MyName
                    end
                    ImGui.Indent(2)
                    ImGui.TextWrapped("You can change any setting by issuing `/lootutils set settingname value` use [on|off] for true false values.")
                    ImGui.TextWrapped("You can also change settings for other characters by selecting them from the dropdown.")
                    ImGui.Unindent(2)
                    ImGui.Spacing()

                    ImGui.Separator()
                    ImGui.Spacing()
                    ImGui.SetNextItemWidth(180)
                    if ImGui.BeginCombo("Select Actor", LNS.TempSettings.SelectedActor) then
                        for k, v in pairs(LNS.Boxes) do
                            if ImGui.Selectable(k, LNS.TempSettings.SelectedActor == k) then
                                LNS.TempSettings.SelectedActor = k
                            end
                        end
                        ImGui.EndCombo()
                    end
                    LNS.renderSettingsSection(LNS.TempSettings.SelectedActor)
                else
                    -- Items and Rules Section
                    LNS.drawItemsTables()
                end
                ImGui.PopStyleColor()
            end
            ImGui.EndChild()
        end

        ImGui.End()
    end
end

function LNS.RenderUIs()
    local colCount, styCount = LNS.guiLoot.DrawTheme()

    if LNS.NewItemDecisions ~= nil then
        LNS.enterNewItemRuleInfo(LNS.NewItemDecisions)
        LNS.NewItemDecisions = nil
    end

    if LNS.TempSettings.ModifyItemRule then
        -- check if we need to modify an item.
        if LNS.TempSettings.ModifyItemRule and LNS.TempSettings.ModifyItemID < 0 and LNS.TempSettings.LastModID ~= LNS.TempSettings.ModifyItemID then
            LNS.TempSettings.LastModID = LNS.TempSettings.ModifyItemID
            Logger.Info(LNS.guiLoot.console, "Searching for item matches for: \at%s\ax", LNS.TempSettings.ModifyItemName)
            local count = 0
            LNS.TempSettings.ModifyItemMatches = {}
            _, LNS.TempSettings.ModifyItemMatches = LNS.findItemInDb(LNS.TempSettings.ModifyItemName, nil, true)
            Logger.Info(LNS.guiLoot.console, "Found \ag%s\ax matches for: \at%s\ax", #LNS.TempSettings.ModifyItemMatches, LNS.TempSettings.ModifyItemName)
            for k, v in pairs(LNS.TempSettings.ModifyItemMatches or {}) do
                Logger.Info(LNS.guiLoot.console, "Match: \ag%s\ax - \at%s\ax", v.item_id, v.item_name)
            end
        end

        LNS.RenderModifyItemWindow()
    end

    if LNS.NewItemsCount > 0 then
        LNS.renderNewItem()
    end

    if LNS.pendingItemData ~= nil then
        LNS.processPendingItem()
    end

    if LNS.TempSettings.ShowImportDB then
        LNS.renderImportDBWindow()
    end

    LNS.RenderMainUI()

    RenderBtn()

    LNS.renderCloneWindow()

    if LNS.MasterLootList ~= nil and next(LNS.MasterLootList) ~= nil then
        LNS.RenderMasterLooterWindow()
    end

    if LNS.TempSettings.ShowMailbox then
        LNS.DebugMailBox()
    end

    LNS.renderHelpWindow()

    if LNS.TempSettings.PastHistory then
        LNS.DrawRecord()
    end

    if colCount > 0 then ImGui.PopStyleColor(colCount) end
    if styCount > 0 then ImGui.PopStyleVar(styCount) end
end

------------------------------------
--         MAIN INIT AND LOOP
------------------------------------



function LNS.processArgs(args)
    LNS.Terminate = true
    if args == nil then return end
    if args[1] == 'directed' and args[2] ~= nil then
        if LNS.guiLoot ~= nil then
            LNS.guiLoot.GetSettings(LNS.Settings.HideNames,
                LNS.Settings.RecordData,
                true,
                LNS.Settings.UseActors,
                'lootnscoot',
                LNS.Settings.ShowReport,
                LNS.Settings.ReportSkippedItems)
        end
        LNS.DirectorScript = args[2]
        if args[3] ~= nil then
            LNS.DirectorLNSPath = args[3]
        end
        Mode = 'directed'
        LNS.Terminate = false
        LNS.send({ action = 'Hello', Server = eqServer, who = MyName, })
    elseif args[1] == 'sellstuff' then
        LNS.processItems('Sell')
    elseif args[1] == 'tributestuff' then
        LNS.processItems('Tribute')
    elseif args[1] == 'cleanup' then
        LNS.TempSettings.NeedsCleanup = true
        -- LNS.processItems('Destroy')
    elseif args[1] == 'once' then
        LNS.lootMobs(LNS.Settings.MaxCorpsesPerCycle)
    elseif args[1] == 'standalone' then
        if LNS.guiLoot ~= nil then
            LNS.guiLoot.GetSettings(LNS.Settings.HideNames,

                LNS.Settings.RecordData,
                true,
                LNS.Settings.UseActors,
                'lootnscoot',
                LNS.Settings.ShowReport,
                LNS.Settings.ReportSkippedItems)
        end
        Mode = 'standalone'
        LNS.Terminate = false
        LNS.send({ action = 'Hello', Server = eqServer, who = MyName, })
    end
end

----------------- DEBUG ACTORS -------------------

LNS.TempSettings.MailBox = nil
LNS.TempSettings.ShowMailbox = false

function LNS.DebugMailBox()
    if not LNS.TempSettings.ShowMailbox then return end
    if not debugPrint then
        LNS.TempSettings.MailBox = nil
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
            LNS.TempSettings.MailBox = nil
            LNS.TempSettings.MPS = nil
        end
        ImGui.Text("Messages:")
        ImGui.SameLine()
        ImGui.TextColored(ImVec4(0, 1, 1, 1), "%d", (LNS.TempSettings.MailBox ~= nil and (#LNS.TempSettings.MailBox or 0) or 0))
        ImGui.SameLine()
        ImGui.Text("Mps:")
        ImGui.SameLine()
        ImGui.TextColored(ImVec4(1, 1, 0, 1), "%0.2f", LNS.TempSettings.MPS or 0.0)
        ImGui.Spacing()
        ImGui.Separator()
        ImGui.Spacing()
        if ImGui.BeginTable("MailBox", 3, bit32.bor(ImGuiTableFlags.Borders, ImGuiTableFlags.Resizable, ImGuiTableFlags.ScrollY), ImVec2(0, 220)) then
            ImGui.TableSetupColumn("Time", ImGuiTableColumnFlags.WidthFixed, 80)
            ImGui.TableSetupColumn("Subject", ImGuiTableColumnFlags.WidthFixed, 100)
            ImGui.TableSetupColumn("Sender", ImGuiTableColumnFlags.WidthFixed, 100)
            ImGui.TableHeadersRow()

            for _, Data in ipairs(LNS.TempSettings.MailBox or {}) do
                ImGui.TableNextColumn()
                ImGui.Text(Data.Time)
                ImGui.TableNextColumn()
                ImGui.Text(Data.Subject)
                ImGui.TableNextColumn()
                ImGui.Text(Data.Sender)
            end

            ImGui.EndTable()
        end
    end

    ImGui.End()
end

---------------- Main Function and Init -----------
function LNS.init(args)
    local needsSave = false
    if Mode ~= 'once' then
        LNS.Terminate = false
    end
    needsSave = LNS.loadSettings(true)
    mq.cmdf("/squelch /mapfilter CastRadius %d", LNS.Settings.CorpseRadius)
    LNS.SortSettings()
    LNS.SortTables()
    LNS.RegisterActors()
    LNS.CheckBags()
    LNS.setupEvents()
    LNS.setupBinds()
    zoneID = mq.TLO.Zone.ID()
    Logger.Debug(LNS.guiLoot.console, "Loot::init() \aoSaveRequired: \at%s", needsSave and "TRUE" or "FALSE")
    LNS.processArgs(args)
    LNS.sendMySettings()
    mq.imgui.init('LootnScoot', LNS.RenderUIs)
    LNS.guiLoot.GetSettings(LNS.Settings.HideNames,

        LNS.Settings.RecordData,
        true,
        LNS.UseActors,
        'lootnscoot',
        LNS.Settings.ShowReport,
        LNS.Settings.ReportSkippedItems)

    if needsSave then LNS.writeSettings("Init()") end
    if Mode == 'directed' then
        -- send them our combat setting
        LNS.send({
            Subject = 'settings',
            Who = MyName,
            CombatLooting = LNS.Settings.CombatLooting,
            CorpseRadius = LNS.Settings.CorpseRadius,
            LootMyCorpse = LNS.Settings.LootMyCorpse,
            IgnoreNearby = LNS.Settings.IgnoreMyNearCorpses,
            CorpsesToIgnore = lootedCorpses or {},
            Server = eqServer,
            LNSSettings = LNS.Settings,
        }, 'loot_module')
    end
    return needsSave
end

if LNS.guiLoot ~= nil then
    LNS.guiLoot.GetSettings(LNS.Settings.HideNames,

        LNS.Settings.RecordData,
        true,
        LNS.Settings.UseActors,
        'lootnscoot',
        LNS.Settings.ShowReport,
        LNS.Settings.ReportSkippedItems
    )
    LNS.guiLoot.init(true, true, 'lootnscoot')
    LNS.guiExport()
end
function LNS.MainLoop()
    while not LNS.Terminate do
        LNS.Zone = mq.TLO.Zone.ShortName()
        if mq.TLO.MacroQuest.GameState() ~= "INGAME" then LNS.Terminate = true end -- exit sctipt if at char select.

        -- check if the director script is running.
        local directorRunning = mq.TLO.Lua.Script(LNS.DirectorScript).Status() == 'RUNNING' or false
        if not directorRunning and Mode == 'directed' then
            LNS.Terminate = true
        end

        if LNS.TempSettings.LastZone ~= LNS.Zone then
            mq.delay(5000, function() return not mq.TLO.Me.Zoning() end) -- wait for zoning to finish.
            LNS.TempSettings.ItemsToLoot = {}
            lootedCorpses = {}

            if Mode == 'directed' then
                -- send them our combat setting
                LNS.send({
                    Subject = 'settings',
                    Who = MyName,
                    CombatLooting = LNS.Settings.CombatLooting,
                    CorpseRadius = LNS.Settings.CorpseRadius,
                    LootMyCorpse = LNS.Settings.LootMyCorpse,
                    IgnoreNearby = LNS.Settings.IgnoreMyNearCorpses,
                    CorpsesToIgnore = lootedCorpses or {},
                    Server = eqServer,
                    LNSSettings = LNS.Settings,
                }, 'loot_module')
            end
            LNS.TempSettings.LastZone = LNS.Zone
            LNS.MasterLootList = nil
            LNS.TempSettings.SafeZoneWarned = false
        end

        if LNS.SafeZones[LNS.Zone] and not LNS.TempSettings.SafeZoneWarned then
            Logger.Debug(LNS.guiLoot.console, "You are in a safe zone: \at%s\ax \ayLooting Disabled", LNS.Zone)
            LNS.TempSettings.SafeZoneWarned = true
        end

        -- check if we need to import the old rules db.
        if LNS.TempSettings.DoImport then
            Logger.Info(LNS.guiLoot.console, "Importing Old Rules DB:\n\at%s", LNS.TempSettings.ImportDBFilePath)
            LNS.ImportOldRulesDB(LNS.TempSettings.ImportDBFilePath)
            LNS.TempSettings.DoImport = false
        end

        -- check if we need to remove safe zones.
        if LNS.TempSettings.RemoveSafeZone ~= nil then
            for k, v in pairs(LNS.TempSettings.RemoveSafeZone or {}) do
                if k ~= nil then LNS.RemoveSafeZone(k) end
            end
            LNS.TempSettings.RemoveSafeZone = nil
        end

        if LNS.TempSettings.RemoveMLItem then
            LNS.itemGone(LNS.TempSettings.RemoveMLItemInfo.itemName, LNS.TempSettings.RemoveMLItemInfo.corpseID)
            LNS.TempSettings.RemoveMLItem = false
            LNS.TempSettings.RemoveMLItemInfo = {}
        end

        if LNS.TempSettings.RemoveMLCorpse then
            LNS.corpseGone(LNS.TempSettings.RemoveMLCorpseInfo.corpseID)
            LNS.TempSettings.RemoveMLCorpse = false
            LNS.TempSettings.RemoveMLCorpseInfo = {}
        end

        if LNS.GetTableSize(LNS.TempSettings.ItemsToLoot) > 0 and (not mq.TLO.Me.Combat() or LNS.Settings.CombatLooting) then
            local lootedIdx = {}
            for idx, data in ipairs(LNS.TempSettings.ItemsToLoot or {}) do
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
                LNS.TempSettings.ItemsToLoot[idx] = nil
            end
        end

        if LNS.TempSettings.SendLoot then
            LNS.send(LNS.TempSettings.SendLootInfo)
            LNS.TempSettings.SendLoot = false
        end

        if LNS.TempSettings.SendRemoveItem then
            LNS.send(LNS.TempSettings.RemoveItemData)
            LNS.TempSettings.SendRemoveItem = false
        end

        -- check shared settings
        if LNS.TempSettings.LastCombatSetting == nil then
            LNS.TempSettings.LastCombatSetting = LNS.Settings.CombatLooting
        end

        if LNS.TempSettings.LastCorpseRadius == nil then
            LNS.TempSettings.LastCorpseRadius = LNS.Settings.CorpseRadius
        end

        if LNS.TempSettings.LastLootMyCorpse == nil then
            LNS.TempSettings.LastLootMyCorpse = LNS.Settings.LootMyCorpse
        end

        if LNS.TempSettings.LastIgnoreNearby == nil then
            LNS.TempSettings.LastIgnoreNearby = LNS.Settings.IgnoreMyNearCorpses
        end

        -- check if we need to send actors any settings
        if LNS.TempSettings.NeedSave then
            if (LNS.TempSettings.LastCombatSetting ~= LNS.Settings.CombatLooting) or
                (LNS.TempSettings.LastCorpseRadius ~= LNS.Settings.CorpseRadius) or
                (LNS.TempSettings.LastLootMyCorpse ~= LNS.Settings.LootMyCorpse) or
                (LNS.TempSettings.LastIgnoreNearby ~= LNS.Settings.IgnoreMyNearCorpses) then
                LNS.TempSettings.LastCombatSetting = LNS.Settings.CombatLooting
                LNS.TempSettings.LastCorpseRadius = LNS.Settings.CorpseRadius
                LNS.TempSettings.LastLootMyCorpse = LNS.Settings.LootMyCorpse
                LNS.TempSettings.LastIgnoreNearby = LNS.Settings.IgnoreMyNearCorpses
                LNS.send({
                    Subject = 'combatsetting',
                    Who = MyName,
                    CombatLooting = LNS.Settings.CombatLooting,
                    CorpseRadius = LNS.Settings.CorpseRadius,
                    LootMyCorpse = LNS.Settings.LootMyCorpse,
                    IgnoreNearby = LNS.Settings.IgnoreMyNearCorpses,
                    CorpsesToIgnore = lootedCorpses or {},
                    LNSSettings = LNS.Settings,
                    Server = eqServer,
                }, 'loot_module')
            end
        end

        if debugPrint then
            Logger.loglevel = 'debug'
        elseif not LNS.Settings.ShowInfoMessages then
            Logger.loglevel = 'warn'
        else
            Logger.loglevel = 'info'
        end

        local checkDif = os.clock() - (LNS.TempSettings.LastCheck or 0)

        -- check if we need to loot mobs
        if (LNS.Settings.DoLoot or LNS.Settings.LootMyCorpse) and Mode ~= 'directed' then
            if checkDif > LNS.Settings.LootCheckDelay then
                LNS.lootMobs(LNS.Settings.MaxCorpsesPerCycle or 1)
            else
                -- Logger.Debug(LNS.guiLoot.console, "\atToo Soon\ax CheckDelay: \ag%s\ax seconds, LastCheck: \ag%0.2f\ax seconds ago",
                -- LNS.Settings.LootCheckDelay, checkDif)
            end
        elseif LNS.LootNow and Mode == 'directed' then
            if checkDif > LNS.Settings.LootCheckDelay then
                LNS.lootMobs(LNS.TempSettings.LootLimit or LNS.Settings.MaxCorpsesPerCycle)
            else
                -- Logger.Debug(LNS.guiLoot.console, "\atToo Soon\ax CheckDelay: \ag%s\ax seconds, LastCheck: \ag%0.2f\ax seconds ago",
                -- LNS.Settings.LootCheckDelay, checkDif)
                LNS.finishedLooting()
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

        if LNS.TempSettings.doBulkSet then
            local doDelete = LNS.TempSettings.bulkDelete
            LNS.bulkSet(LNS.TempSettings.BulkSet, LNS.TempSettings.BulkRule,
                LNS.TempSettings.BulkClasses, LNS.TempSettings.BulkSetTable, doDelete)
            LNS.TempSettings.doBulkSet = false
            LNS.TempSettings.bulkDelete = false
            LNS.TempSettings.SelectedItems = {}
        end

        if LNS.guiLoot ~= nil then
            if LNS.guiLoot.SendHistory then
                LNS.LoadHistoricalData()
                LNS.guiLoot.SendHistory = false
            end
            if LNS.guiLoot.showReport ~= LNS.Settings.ShowReport then
                LNS.Settings.ShowReport = LNS.guiLoot.showReport
                LNS.TempSettings.NeedSave = true
            end
            if LNS.guiLoot.openGUI ~= LNS.Settings.ShowConsole then
                LNS.Settings.ShowConsole = LNS.guiLoot.openGUI
                LNS.TempSettings.NeedSave = true
            end
            LNS.TempSettings.SessionHistory = LNS.guiLoot.SessionLootRecord or {}
        end

        mq.doevents()

        if LNS.TempSettings.UpdateSettings then
            Logger.Info(LNS.guiLoot.console, "Updating Settings")
            mq.pickle(SettingsFile, LNS.Settings)
            LNS.loadSettings()
            LNS.TempSettings.UpdateSettings = false
        end

        if LNS.TempSettings.SendSettings then
            LNS.TempSettings.SendSettings = false
            if os.difftime(os.time(), LNS.TempSettings.LastSent or 0) > 10 then
                Logger.Debug(LNS.guiLoot.console, "Sending Settings")
                LNS.sendMySettings()
            end
        end

        -- if LNS.TempSettings.WriteSettings then
        --     LNS.writeSettings()
        --     LNS.SortTables()
        --     LNS.TempSettings.WriteSettings = false
        -- end

        if LNS.TempSettings.ClearDateData then
            LNS.TempSettings.ClearDateData = false
            LNS.HistoryDataDate = {}
            LNS.HistoryItemData = {}
        end

        if LNS.TempSettings.LookUpDateData then
            LNS.TempSettings.LookUpDateData = false
            LNS.LoadDateHistory(lookupDate)
            LNS.HistoryItemData = {}
        end

        if LNS.TempSettings.FindItemHistory then
            LNS.TempSettings.FindItemHistory = false
            if LNS.TempSettings.FilterHistory ~= nil and LNS.TempSettings.FilterHistory ~= "" then
                LNS.LoadItemHistory(LNS.TempSettings.FilterHistory)
                LNS.HistoryDataDate = {}
                LNS.TempSettings.FilterHistory = ''
            end
        end

        if LNS.TempSettings.DoGet then
            LNS.TempSettings.DoGet = false
            if LNS.TempSettings.GetItem == nil then return end
            local itemName = LNS.TempSettings.GetItem.Name or 'None'
            local itemID = LNS.TempSettings.GetItem.ID or 0
            local db = LNS.OpenItemsSQL()
            LNS.GetItemFromDB(itemName, itemID)
            db:close()
            LNS.lookupLootRule(nil, itemID)
            LNS.TempSettings.GetItem = nil
        end

        if LNS.TempSettings.NeedSave then
            for k, v in pairs(LNS.TempSettings.UpdatedBuyItems or {}) do
                if k ~= "" then
                    LNS.BuyItemsTable[k] = tonumber(v)
                end
            end

            LNS.TempSettings.UpdatedBuyItems = {}
            for k in pairs(LNS.TempSettings.DeletedBuyKeys or {}) do
                LNS.BuyItemsTable[k] = nil
                LNS.TempSettings.NewBuyItem = ""
                LNS.TempSettings.NewBuyQty = 1
            end

            LNS.TempSettings.DeletedBuyKeys = {}
            LNS.writeSettings("MainLoop()")
            LNS.TempSettings.NeedSave = false
            LNS.sendMySettings()
            LNS.SortTables()
        end

        if LNS.TempSettings.LookUpItem then
            if LNS.TempSettings.SearchItems ~= nil and LNS.TempSettings.SearchItems ~= "" then
                LNS.GetItemFromDB(LNS.TempSettings.SearchItems, 0)
            end
            LNS.TempSettings.LookUpItem = false
        end

        if LNS.NewItemsCount <= 0 then
            LNS.NewItemsCount = 0
        end

        if LNS.NewItemsCount == 0 then
            showNewItem = false
        end

        if LNS.TempSettings.NeedsCleanup and not mq.TLO.Me.Casting() then
            LNS.TempSettings.NeedsCleanup = false
            LNS.processItems('Destroy')
        end

        -- if LNS.MyClass:lower() == 'brd' and LNS.Settings.DoDestroy then
        --     LNS.Settings.DoDestroy = false
        --     Logger.Warn(LNS.guiLoot.console, "\ayBard Detected\ax, \arDisabling\ax [\atDoDestroy\ax].")
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

LNS.init({ ..., })
LNS.MainLoop()

return LNS
