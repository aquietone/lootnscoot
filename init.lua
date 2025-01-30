--[[
loot.lua v1.7 - aquietone, grimmier

This is a port of the RedGuides copy of ninjadvloot.inc with some updates as well.
I may have glossed over some of the events or edge cases so it may have some issues
around things like:
- lore items
- full inventory
- not full inventory but no slot large enough for an item
- ...
Or those things might just work, I just haven't tested it very much using lvl 1 toons
on project lazarus.

Settings are saved per character in config\LootNScoot_[ServerName]_[CharName].ini
if you would like to use a global settings file. you can Change this inside the above file to point at your global file instead.
example= SettingsFile=D:\MQ_EMU\Config/LootNScoot_GlobalSettings.ini

This script can be used in two ways:
1. Included within a larger script using require, for example if you have some KissAssist-like lua script:
To loot mobs, call lootutils.lootMobs():

local mq                                    = require 'mq'
local lootutils                                    = require 'lootnscoot'
while true do
lootutils.lootMobs()
mq.delay(1000)
end

lootUtils.lootMobs() will run until it has attempted to loot all corpses within the defined radius.

To sell to a vendor, call lootutils.sellStuff():

local mq                                    = require 'mq'
local lootutils                                    = require 'lootnscoot'
local doSell                                    = false
local function binds(...)
local args                                    = {...}
if args[1]                                    == 'sell' then doSell                                    = true end
end
mq.bind('/myscript', binds)
while true do
lootutils.lootMobs()
if doSell then lootutils.sellStuff() doSell                                    = false end
mq.delay(1000)
end

lootutils.sellStuff() will run until it has attempted to sell all items marked as sell to the targeted vendor.

Note that in the above example, loot.sellStuff() isn't being called directly from the bind callback.
Selling may take some time and includes delays, so it is best to be called from your main loop.

Optionally, configure settings using:
Set the radius within which corpses should be looted (radius from you, not a camp location)
lootutils.CorpseRadius                                    = number
Set whether loot.ini should be updated based off of sell item events to add manually sold items.
lootutils.AddNewSales                                    = boolean
Several other settings can be found in the "loot" table defined in the code.

2. Run as a standalone script:
/lua run lootnscoot standalone
Will keep the script running, checking for corpses once per second.
/lua run lootnscoot once
Will run one iteration of loot.lootMobs().
/lua run lootnscoot sell
Will run one iteration of loot.sellStuff().
/lua run lootnscoot cleanup
Will run one iteration of loot.cleanupBags().

The script will setup a bind for "/lootutils":
/lootutils <action> "${Cursor.Name}"
Set the loot rule for an item. "action" may be one of:
- Keep
- Bank
- Sell
- Tribute
- Ignore
- Destroy
- Quest|#

/lootutils reload
Reload the contents of Loot.ini
/lootutils bank
Put all items from inventory marked as Bank into the bank
/lootutils tsbank
Mark all tradeskill items in inventory as Bank

If running in standalone mode, the bind also supports:
/lootutils sellstuff
Runs lootutils.sellStuff() one time
/lootutils tributestuff
Runs lootutils.tributeStuff() one time
/lootutils cleanup
Runs lootutils.cleanupBags() one time

The following events are used:
- eventCantLoot - #*#may not loot this corpse#*#
Add corpse to list of corpses to avoid for a few minutes if someone is already looting it.
- eventSell - #*#You receive#*# for the #1#(s)#*#
Set item rule to Sell when an item is manually sold to a vendor
- eventInventoryFull - #*#Your inventory appears full!#*#
Stop attempting to loot once inventory is full. Note that currently this never gets set back to false
even if inventory space is made available.
- eventNovalue - #*#give you absolutely nothing for the #1#.#*#
Warn and move on when attempting to sell an item which the merchant will not buy.

This does not include the buy routines from ninjadvloot. It does include the sell routines
but lootly sell routines seem more robust than the code that was in ninjadvloot.inc.
The forage event handling also does not handle fishing events like ninjadvloot did.
There is also no flag for combat looting. It will only loot if no mobs are within the radius.

]]

local mq              = require 'mq'
local PackageMan      = require('mq.PackageMan')
local SQLite3         = PackageMan.Require('lsqlite3')
local Icons           = require('mq.ICONS')
local success, Logger = pcall(require, 'lib.Write')

if not success then
    printf('\arERROR: Write.lua could not be loaded\n%s\ax', Logger)
    return
end
local eqServer                       = string.gsub(mq.TLO.EverQuest.Server(), ' ', '_')
-- Check for looted module, if found use that. else fall back on our copy, which may be outdated.

local version                        = 5
local MyName                         = mq.TLO.Me.CleanName()

local Files                          = require('mq.Utils')
local SettingsFile                   = string.format('%s/LootNScoot/%s/%s.lua', mq.configDir, eqServer, MyName)
local imported                       = true
local lootDBUpdateFile               = string.format('%s/LootNScoot/%s/DB_Updated.lua', mq.configDir, eqServer)
local zoneID                         = 0
local lootedCorpses                  = {}
local tmpRules, tmpClasses, tmpLinks = {}, {}, {}
local ProcessItemsState              = nil
local reportPrefix                   = '/%s \a-t[\at%s\a-t][\ax\ayLootUtils\ax\a-t]\ax '
Logger.prefix                        = "[\atLootnScoot\ax] "
-- Public default settings, also read in from Loot.ini [Settings] section
local loot                           = {}
loot.Settings                        = {
    Version         = '"' .. tostring(version) .. '"',
    GlobalLootOn    = true,   -- Enable Global Loot Items. not implimented yet
    CombatLooting   = false,  -- Enables looting during combat. Not recommended on the MT
    CorpseRadius    = 100,    -- Radius to activly loot corpses
    MobsTooClose    = 40,     -- Don't loot if mobs are in this range.
    SaveBagSlots    = 3,      -- Number of bag slots you would like to keep empty at all times. Stop looting if we hit this number
    TributeKeep     = false,  -- Keep items flagged Tribute
    MinTributeValue = 100,    -- Minimun Tribute points to keep item if TributeKeep is enabled.
    MinSellPrice    = -1,     -- Minimum Sell price to keep item. -1                                    = any
    StackPlatValue  = 0,      -- Minimum sell value for full stack
    StackableOnly   = false,  -- Only loot stackable items
    AlwaysEval      = false,  -- Re-Evaluate all *Non Quest* items. useful to update loot.ini after changing min sell values.
    BankTradeskills = true,   -- Toggle flagging Tradeskill items as Bank or not.
    DoLoot          = true,   -- Enable auto looting in standalone mode
    LootForage      = true,   -- Enable Looting of Foraged Items
    LootNoDrop      = false,  -- Enable Looting of NoDrop items.
    LootNoDropNew   = false,  -- Enable looting of new NoDrop items.
    LootQuest       = false,  -- Enable Looting of Items Marked 'Quest', requires LootNoDrop on to loot NoDrop quest items
    DoDestroy       = false,  -- Enable Destroy functionality. Otherwise 'Destroy' acts as 'Ignore'
    AlwaysDestroy   = false,  -- Always Destroy items to clean corpese Will Destroy Non-Quest items marked 'Ignore' items REQUIRES DoDestroy set to true
    QuestKeep       = 10,     -- Default number to keep if item not set using Quest|# format.
    LootChannel     = "dgt",  -- Channel we report loot to.
    GroupChannel    = "dgze", -- Channel we use for Group Commands Default(dgze)
    ReportLoot      = true,   -- Report loot items to group or not.
    SpamLootInfo    = false,  -- Echo Spam for Looting
    LootForageSpam  = false,  -- Echo spam for Foraged Items
    AddNewSales     = true,   -- Adds 'Sell' Flag to items automatically if you sell them while the script is running.
    AddNewTributes  = true,   -- Adds 'Tribute' Flag to items automatically if you Tribute them while the script is running.
    GMLSelect       = true,   -- not implimented yet
    LootLagDelay    = 0,      -- not implimented yet
    HideNames       = false,  -- Hides names and uses class shortname in looted window
    LookupLinks     = false,  -- Enables Looking up Links for items not on that character. *recommend only running on one charcter that is monitoring.
    RecordData      = false,  -- Enables recording data to report later.
    AutoTag         = false,  -- Automatically tag items to sell if they meet the MinSellPrice
    AutoRestock     = false,  -- Automatically restock items from the BuyItems list when selling
    LootMyCorpse    = false,  -- Loot your own corpse if its nearby (Does not check for REZ)
    LootAugments    = false,  -- Loot Augments
    CheckCorpseOnce = false,  -- Check Corpse once and move on. Ignore the next time it is in range if enabled
    AutoShowNewItem = false,  -- Automatically show new items in the looted window
    KeepSpells      = true,   -- Keep spells
    CanWear         = false,  -- Only loot items you can wear
    BuyItemsTable   = {
        ['Iron Ration'] = 20,
        ['Water Flask'] = 20,
    },
}

loot.MyClass                         = mq.TLO.Me.Class.ShortName():lower()
loot.MyRace                          = mq.TLO.Me.Race.Name()
-- SQL information
local resourceDir                    = mq.TLO.MacroQuest.Path('resources')() .. "/"
local RulesDB                        = string.format('%s/LootNScoot/%s/AdvLootRules.db', resourceDir, eqServer)
local lootDB                         = string.format('%s/LootNScoot/%s/Items.db', resourceDir, eqServer)
local newItem                        = nil
loot.guiLoot                         = require('loot_hist')
if loot.guiLoot ~= nil then
    loot.UseActors = true
    loot.guiLoot.GetSettings(loot.HideNames, loot.LookupLinks, loot.RecordData, true, loot.UseActors, 'lootnscoot', false)
end

local iconAnimation                     = mq.FindTextureAnimation('A_DragItem')
-- Internal settings
local cantLootList                      = {}
local cantLootID                        = 0
-- Constants
local spawnSearch                       = '%s radius %d zradius 50'
-- If you want destroy to actually loot and destroy items, change DoDestroy=false to DoDestroy=true in the Settings Ini.
-- Otherwise, destroy behaves the same as ignore.
local shouldLootActions                 = { CanUse = false, Ask = false, Keep = true, Bank = true, Sell = true, Destroy = false, Ignore = false, Tribute = false, }
local validActions                      = {
    canuse = "CanUse",
    ask = "Ask",
    keep = 'Keep',
    bank = 'Bank',
    sell = 'Sell',
    ignore = 'Ignore',
    destroy = 'Destroy',
    quest = 'Quest',
    tribute =
    'Tribute',
}
local saveOptionTypes                   = { string = 1, number = 1, boolean = 1, }
local NEVER_SELL                        = { ['Diamond Coin'] = true, ['Celestial Crest'] = true, ['Gold Coin'] = true, ['Taelosian Symbols'] = true, ['Planar Symbols'] = true, }
local tmpCmd                            = loot.GroupChannel or 'dgae'
local showNewItem                       = false
local myName                            = mq.TLO.Me.Name()

local Actors                            = require('actors')
loot.BuyItemsTable                      = {}
loot.ALLITEMS                           = {}
loot.GlobalItemsRules                   = {}
loot.NormalItemsRules                   = {}
loot.NormalItemsClasses                 = {}
loot.GlobalItemsClasses                 = {}
loot.NormalItemsLink                    = {}
loot.GlobalItemsLink                    = {}
loot.NewItems                           = {}
loot.TempSettings                       = {}
loot.PersonalItemsRules                 = {}
loot.PersonalItemsClasses               = {}
loot.PersonalItemsLink                  = {}
loot.NewItemDecisions                   = nil
loot.ItemNames                          = {}
loot.NewItemsCount                      = 0
loot.TempItemClasses                    = "All"
loot.itemSelectionPending               = false -- Flag to indicate an item selection is in progress
loot.pendingItemData                    = nil   -- Temporary storage for item data
loot.doImportInventory                  = false
loot.TempModClass                       = false
loot.ShowUI                             = false
loot.Terminate                          = true
loot.Boxes                              = {}
-- FORWARD DECLARATIONS
loot.AllItemColumnListIndex             = {
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

local settingsEnum                      = {
    checkcorpseonce = 'CheckCorpseOnce',
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
    spamlootinfo = 'SpamLootInfo',
    lootforagespam = 'LootForageSpam',
    addnewsales = 'AddNewSales',
    addnewtributes = 'AddNewTributes',
    gmlselect = 'GMLSelect',
    lootlagdelay = 'LootLagDelay',
    hidenames = 'HideNames',
    lookuplinks = 'LookupLinks',
    recorddata = 'RecordData',
    autotag = 'AutoTag',
    autorestock = 'AutoRestock',
    lootmycorpse = 'LootMyCorpse',
    lootaugments = 'LootAugments',

}

local doSell, doBuy, doTribute, areFull = false, false, false, false
local settingList                       = {
    "CanUse",
    "Keep",
    "Ignore",
    "Destroy",
    "Quest",
    "Sell",
    "Tribute",
    "Bank",
}
local settingsNoDraw                    = { Version = true, logger = true, LootFile = true, SettingsFile = true, NoDropDefaults = true, CorpseRotTime = true, LootLagDelay = true, Terminate = true, BuyItemsTable = true, }

local selectedIndex                     = 1

-- Pagination state
local ITEMS_PER_PAGE                    = 25
loot.CurrentPage                        = loot.CurrentPage or 1

-- UTILITIES



---
---This will keep your table sorted by columns instead of rows.
---@param input_table table|nil  the table to sort (optional) You can send a set of sorted keys if you have already custom sorted it.
---@param sorted_keys table|nil  the sorted keys table (optional) if you have already sorted the keys
---@param num_columns integer  the number of column groups to sort the keys into
---@return table
function loot.SortTableColums(input_table, sorted_keys, num_columns)
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
    local num_rows = math.ceil(total_items / num_columns)
    local column_sorted = {}

    -- Reorganize the keys to fill vertically by columns
    for row = 1, num_rows do
        for col = 1, num_columns do
            local index = (col - 1) * num_rows + row
            if index <= total_items then
                table.insert(column_sorted, keys[index])
            end
        end
    end

    return column_sorted
end

function loot.SortKeys(input_table)
    local keys = {}
    for k, _ in pairs(input_table) do
        table.insert(keys, k)
    end

    table.sort(keys) -- Sort the keys
    return keys
end

---comment: Returns a table containing all the data from the INI file.
---@param fileName string The name of the INI file to parse. [string]
---@param sec string The section of the INI file to parse. [string]
---@return table DataTable containing all data from the INI file. [table]
function loot.load(fileName, sec)
    if sec == nil then sec = "items" end
    -- this came from Knightly's LIP.lua
    assert(type(fileName) == 'string', 'Parameter "fileName" must be a string.');
    local file  = assert(io.open(fileName, 'r'), 'Error loading file : ' .. fileName);
    local data  = {};
    local section;
    local count = 0
    for line in file:lines() do
        local tempSection = line:match('^%[([^%[%]]+)%]$');
        if (tempSection) then
            -- print(tempSection)
            section = tonumber(tempSection) and tonumber(tempSection) or tempSection;
            -- data[section]                                    = data[section] or {};
            count   = 0
        end
        local param, value = line:match("^([%w|_'.%s-]+)=%s-(.+)$");

        if (param and value ~= nil) then
            if (tonumber(value)) then
                value = tonumber(value);
            elseif (value == 'true') then
                value = true;
            elseif (value == 'false') then
                value = false;
            end
            if (tonumber(param)) then
                param = tonumber(param);
            end
            if string.find(tostring(param), 'Spawn') then
                count = count + 1
                param = string.format("Spawn%d", count)
            end
            if sec == "items" and param ~= nil then
                if section ~= "Settings" and section ~= "GlobalItems" then
                    data[param] = value;
                end
            elseif section == sec and param ~= nil then
                data[param] = value;
            end
        end
    end
    file:close();
    Logger.Debug("Loot::load()")
    return data;
end

function loot.writeSettings()
    loot.Settings.BuyItemsTable = loot.BuyItemsTable
    mq.pickle(SettingsFile, loot.Settings)

    Logger.Debug("Loot::writeSettings()")
end

function loot.split(input, sep)
    if sep == nil then
        sep = "|"
    end
    local t = {}
    for str in string.gmatch(input, "([^" .. sep .. "]+)") do
        table.insert(t, str)
    end
    return t
end

function loot.drawIcon(iconID, iconSize)
    if iconSize == nil then iconSize = 16 end
    if iconID ~= nil then
        iconAnimation:SetTextureCell(iconID - 500)
        ImGui.DrawTextureAnimation(iconAnimation, iconSize, iconSize)
    end
end

function loot.OpenItemsSQL()
    local db = SQLite3.open(lootDB)
    return db
end

function loot.LoadRuleDB()
    -- Create the database and its table if it doesn't exist
    -- local db = SQLite3.open(RulesDB)
    -- db:exec([[
    --     CREATE TABLE IF NOT EXISTS Global_Rules (
    --     "item_id" INTEGER PRIMARY KEY NOT NULL UNIQUE,
    --     "item_name" TEXT NOT NULL,
    --     "item_rule" TEXT NOT NULL,
    --     "item_rule_classes" TEXT,
    --     "item_link" TEXT
    --     );
    --     CREATE TABLE IF NOT EXISTS Normal_Rules (
    --     "item_id" INTEGER PRIMARY KEY NOT NULL UNIQUE,
    --     "item_name" TEXT NOT NULL,
    --     "item_rule" TEXT NOT NULL,
    --     "item_rule_classes" TEXT,
    --     "item_link" TEXT
    --     );
    --     ]])
    -- db:close()
    local db = SQLite3.open(RulesDB)
    local charTableName = string.format("%s_Rules", MyName)

    local createTablesQuery = string.format([[
        CREATE TABLE IF NOT EXISTS Global_Rules (
            "item_id" INTEGER PRIMARY KEY NOT NULL UNIQUE,
            "item_name" TEXT NOT NULL,
            "item_rule" TEXT NOT NULL,
            "item_rule_classes" TEXT,
            "item_link" TEXT
        );
        CREATE TABLE IF NOT EXISTS Normal_Rules (
            "item_id" INTEGER PRIMARY KEY NOT NULL UNIQUE,
            "item_name" TEXT NOT NULL,
            "item_rule" TEXT NOT NULL,
            "item_rule_classes" TEXT,
            "item_link" TEXT
        );
        CREATE TABLE IF NOT EXISTS %s (
            "item_id" INTEGER PRIMARY KEY NOT NULL UNIQUE,
            "item_name" TEXT NOT NULL,
            "item_rule" TEXT NOT NULL,
            "item_rule_classes" TEXT,
            "item_link" TEXT
        );
    ]], charTableName)

    db:exec(createTablesQuery)
    db:close()


    -- process the loaded data
    db         = SQLite3.open(RulesDB)
    local stmt = db:prepare("SELECT * FROM Global_Rules")
    for row in stmt:nrows() do
        loot.GlobalItemsRules[row.item_id]   = row.item_rule
        loot.GlobalItemsClasses[row.item_id] = row.item_rule_classes ~= nil and row.item_rule_classes or 'All'
        loot.GlobalItemsLink[row.item_id]    = row.item_link ~= nil and row.item_link or 'NULL'
        loot.ItemNames[row.item_id]          = row.item_name
    end
    stmt:finalize()
    stmt = db:prepare("SELECT * FROM Normal_Rules")
    for row in stmt:nrows() do
        loot.NormalItemsRules[row.item_id]   = row.item_rule
        loot.NormalItemsClasses[row.item_id] = row.item_rule_classes ~= nil and row.item_rule_classes or 'All'
        loot.NormalItemsLink[row.item_id]    = row.item_link ~= nil and row.item_link or 'NULL'
        loot.ItemNames[row.item_id]          = row.item_name
    end

    stmt:finalize()
    db:close()
end

---comment
---@param firstRun boolean|nil if passed true then we will load the DB's again
---@return boolean
function loot.loadSettings(firstRun)
    if firstRun == nil then firstRun = false end
    if firstRun then
        loot.NormalItemsRules   = {}
        loot.GlobalItemsRules   = {}
        loot.NormalItemsClasses = {}
        loot.GlobalItemsClasses = {}
        loot.NormalItemsLink    = {}
        loot.GlobalItemsLink    = {}
        loot.BuyItemsTable      = {}
        loot.ItemNames          = {}
        loot.ALLITEMS           = {}
    end
    local needDBUpdate = false
    local needSave     = false
    local tmpSettings  = {}

    if not Files.File.Exists(SettingsFile) then
        Logger.Warn("Settings file not found, creating it now.")
        needSave = true
        mq.pickle(SettingsFile, loot.Settings)
    else
        tmpSettings = dofile(SettingsFile)
    end
    -- check if the DB structure needs updating

    if not Files.File.Exists(lootDBUpdateFile) then
        needDBUpdate        = true
        tmpSettings.Version = version
        needSave            = true
    else
        local tmp = dofile(lootDBUpdateFile)
        if tmp.version < version then
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

    for k, v in pairs(loot.Settings) do
        if tmpSettings[k] == nil then
            tmpSettings[k] = loot.Settings[k]
            needSave       = true
            if type(tmpSettings[k]) ~= 'table' then
                Logger.Info("\agAdded\ax \ayNEW\ax \aySetting\ax: \at%s \aoDefault\ax: \at(\ay%s\ax)", k, v)
            else
                Logger.Info("\agAdded\ax \ayNEW\ax \aySetting\ax: \at%s \aoTable\ax", k)
            end
        end
    end
    -- check for deprecated settings and remove them
    for k, v in pairs(tmpSettings) do
        if loot.Settings[k] == nil and settingsNoDraw[k] == nil then
            tmpSettings[k] = nil
            needSave       = true
            Logger.Warn("\arRemoved\ax \atdeprecated setting\ax: \ao%s", k)
        end
    end

    tmpCmd = loot.Settings.GroupChannel or 'dgge'
    if tmpCmd == string.find(tmpCmd, 'dg') then
        tmpCmd = '/' .. tmpCmd
    elseif tmpCmd == string.find(tmpCmd, 'bc') then
        tmpCmd = '/' .. tmpCmd .. ' /'
    end

    shouldLootActions.Destroy = loot.Settings.DoDestroy
    shouldLootActions.Tribute = loot.Settings.TributeKeep
    loot.BuyItemsTable        = loot.Settings.BuyItemsTable

    if firstRun then
        -- SQL setup
        if not Files.File.Exists(RulesDB) then
            Logger.Warn("\ayLoot Rules Database \arNOT found\ax, \atCreating it now\ax. Please run \at/rgl lootimport\ax to Import your \atloot.ini \axfile.")
            Logger.Warn("\arOnly run this one One Character\ax. use \at/rgl lootreload\ax to update the data on the other characters.")
        else
            Logger.Info("Loot Rules Database found, loading it now.")
        end

        -- load the rules database
        loot.LoadRuleDB()

        -- check if the DB structure needs updating
        local db = loot.OpenItemsSQL()
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
        db:close()

        -- load the items database
        db = loot.OpenItemsSQL()
        -- Set up the Items DB
        db:exec("BEGIN TRANSACTION")

        for id, name in pairs(loot.ItemNames) do
            loot.GetItemFromDB(name, id, true, db)
        end

        db:exec("COMMIT")
        db:close()
    end
    loot.Settings = tmpSettings
    -- Modules:ExecModule("Loot", "ModifyLootSettings")
    return needSave
end

---comment Retrieve item data from the DB
---@param itemName string The name of the item to retrieve. [string]
---@param itemID integer|nil The ID of the item to retrieve. [integer] [optional]
---@param rules boolean|nil If true, only load items with rules (exact name matches) [boolean] [optional]
---@param db any DB Connection SQLite3 [optional]
---@return integer Quantity of items found
function loot.GetItemFromDB(itemName, itemID, rules, db)
    if itemID == nil and itemName == nil then return 0 end
    if itemID == nil then itemID = 0 end
    if itemName == nil then itemName = 'NULL' end
    if db == nil then db = loot.OpenItemsSQL() end

    local stmt
    if not rules then
        stmt = db:prepare("SELECT * FROM Items WHERE item_id = ? OR name LIKE ? ORDER BY name")
        stmt:bind(1, itemID)
        stmt:bind(2, "%" .. itemName .. "%")
    else
        stmt = db:prepare("SELECT * FROM Items WHERE item_id = ? ORDER BY name")
        stmt:bind(1, itemID)
    end
    local rowsFetched = 0

    for row in stmt:nrows() do
        rowsFetched = rowsFetched + 1
        if row.item_id ~= nil then
            loot.ALLITEMS[row.item_id]                    = {}
            loot.ALLITEMS[row.item_id].Name               = row.name or 'NULL'
            loot.ALLITEMS[row.item_id].NoDrop             = row.nodrop == 1
            loot.ALLITEMS[row.item_id].NoTrade            = row.notrade == 1
            loot.ALLITEMS[row.item_id].Tradeskills        = row.tradeskill == 1
            loot.ALLITEMS[row.item_id].Quest              = row.quest == 1
            loot.ALLITEMS[row.item_id].Lore               = row.lore == 1
            loot.ALLITEMS[row.item_id].Augment            = row.augment == 1
            loot.ALLITEMS[row.item_id].Stackable          = row.stackable == 1
            loot.ALLITEMS[row.item_id].Value              = loot.valueToCoins(row.sell_value)
            loot.ALLITEMS[row.item_id].Tribute            = row.tribute_value
            loot.ALLITEMS[row.item_id].StackSize          = row.stack_size
            loot.ALLITEMS[row.item_id].Clicky             = row.clickable or 'None'
            loot.ALLITEMS[row.item_id].AugType            = row.augtype
            loot.ALLITEMS[row.item_id].STR                = row.strength
            loot.ALLITEMS[row.item_id].DEX                = row.dexterity
            loot.ALLITEMS[row.item_id].AGI                = row.agility
            loot.ALLITEMS[row.item_id].STA                = row.stamina
            loot.ALLITEMS[row.item_id].INT                = row.intelligence
            loot.ALLITEMS[row.item_id].WIS                = row.wisdom
            loot.ALLITEMS[row.item_id].CHA                = row.charisma
            loot.ALLITEMS[row.item_id].Mana               = row.mana
            loot.ALLITEMS[row.item_id].HP                 = row.hp
            loot.ALLITEMS[row.item_id].AC                 = row.ac
            loot.ALLITEMS[row.item_id].HPRegen            = row.regen_hp
            loot.ALLITEMS[row.item_id].ManaRegen          = row.regen_mana
            loot.ALLITEMS[row.item_id].Haste              = row.haste
            loot.ALLITEMS[row.item_id].Classes            = row.classes
            loot.ALLITEMS[row.item_id].ClassList          = row.class_list or 'All'
            loot.ALLITEMS[row.item_id].svFire             = row.svfire
            loot.ALLITEMS[row.item_id].svCold             = row.svcold
            loot.ALLITEMS[row.item_id].svDisease          = row.svdisease
            loot.ALLITEMS[row.item_id].svPoison           = row.svpoison
            loot.ALLITEMS[row.item_id].svCorruption       = row.svcorruption
            loot.ALLITEMS[row.item_id].svMagic            = row.svmagic
            loot.ALLITEMS[row.item_id].SpellDamage        = row.spelldamage
            loot.ALLITEMS[row.item_id].SpellShield        = row.spellshield
            loot.ALLITEMS[row.item_id].Damage             = row.damage
            loot.ALLITEMS[row.item_id].Weight             = row.weight / 10
            loot.ALLITEMS[row.item_id].Size               = row.item_size
            loot.ALLITEMS[row.item_id].WeightReduction    = row.weightreduction
            loot.ALLITEMS[row.item_id].Races              = row.races
            loot.ALLITEMS[row.item_id].RaceList           = row.race_list or 'All'
            loot.ALLITEMS[row.item_id].Icon               = row.icon
            loot.ALLITEMS[row.item_id].Attack             = row.attack
            loot.ALLITEMS[row.item_id].Collectible        = row.collectible == 1
            loot.ALLITEMS[row.item_id].StrikeThrough      = row.strikethrough
            loot.ALLITEMS[row.item_id].HeroicAGI          = row.heroicagi
            loot.ALLITEMS[row.item_id].HeroicCHA          = row.heroiccha
            loot.ALLITEMS[row.item_id].HeroicDEX          = row.heroicdex
            loot.ALLITEMS[row.item_id].HeroicINT          = row.heroicint
            loot.ALLITEMS[row.item_id].HeroicSTA          = row.heroicsta
            loot.ALLITEMS[row.item_id].HeroicSTR          = row.heroicstr
            loot.ALLITEMS[row.item_id].HeroicSvCold       = row.heroicsvcold
            loot.ALLITEMS[row.item_id].HeroicSvCorruption = row.heroicsvcorruption
            loot.ALLITEMS[row.item_id].HeroicSvDisease    = row.heroicsvdisease
            loot.ALLITEMS[row.item_id].HeroicSvFire       = row.heroicsvfire
            loot.ALLITEMS[row.item_id].HeroicSvMagic      = row.heroicsvmagic
            loot.ALLITEMS[row.item_id].HeroicSvPoison     = row.heroicsvpoison
            loot.ALLITEMS[row.item_id].HeroicWIS          = row.heroicwis
            loot.ALLITEMS[row.item_id].Link               = row.link
        end
    end

    stmt:finalize()

    return rowsFetched
end

function loot.addMyInventoryToDB()
    local counter = 0
    local counterBank = 0
    Logger.Info("\atImporting Inventory\ax into the DB")

    for i = 1, 22 do
        if i < 11 then
            -- Items in Bags and Main Inventory
            local bagSlot       = mq.TLO.InvSlot('pack' .. i).Item
            local containerSize = bagSlot.Container()
            if bagSlot() ~= nil then
                loot.addToItemDB(bagSlot)
                counter = counter + 1
                if containerSize then
                    mq.delay(5) -- Delay to prevent spamming the DB
                    for j = 1, containerSize do
                        local item = bagSlot.Item(j)
                        if item and item.ID() then
                            loot.addToItemDB(item)
                            counter = counter + 1
                            mq.delay(10)
                        end
                    end
                end
            end
        else
            -- Worn Items
            local invItem = mq.TLO.Me.Inventory(i)
            if invItem() ~= nil then
                loot.addToItemDB(invItem)
                counter = counter + 1
                mq.delay(10) -- Delay to prevent spamming the DB
            end
        end
    end
    -- Banked Items
    for i = 1, 24 do
        local bankSlot = mq.TLO.Me.Bank(i)
        local bankBagSize = bankSlot.Container()
        if bankSlot() ~= nil then
            loot.addToItemDB(bankSlot)
            counterBank = counterBank + 1
            if bankBagSize then
                mq.delay(5) -- Delay to prevent spamming the DB
                for j = 1, bankBagSize do
                    local item = bankSlot.Item(j)
                    if item and item.ID() then
                        loot.addToItemDB(item)
                        counterBank = counterBank + 1
                        mq.delay(10)
                    end
                end
            end
        end
    end
    Logger.Info("\at%s \axImported \ag%d\ax items from \aoInventory\ax, and \ag%d\ax items from the \ayBank\ax, into the DB", myName, counter, counterBank)
    loot.report(string.format("%s Imported %d items from Inventory, and %d items from the Bank, into the DB", myName, counter, counterBank))
    loot.lootActor:send({ mailbox = 'lootnscoot', },
        { who = myName, Server = eqServer, action = 'ItemsDB_UPDATE', })
end

function loot.addToItemDB(item)
    if item == nil then
        if mq.TLO.Cursor() ~= nil then
            item = mq.TLO.Cursor
        else
            Logger.Error("Item is \arnil.")
            return
        end
    end
    if loot.ItemNames[item.ID()] ~= nil then return end

    -- insert the item into the database

    local db = SQLite3.open(lootDB)
    if not db then
        Logger.Error("\arFailed to open\ax loot database.")
        return
    end

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
        Logger.Error("\arFailed to prepare \ax[\ayINSERT\ax] \aoSQL\ax statement: \at%s", db:errmsg())
        db:close()
        return
    end

    local success, errmsg = pcall(function()
        stmt:bind_values(
            item.ID(),
            item.Name(),
            item.NoDrop() and 1 or 0,
            item.NoTrade() and 1 or 0,
            item.Tradeskills() and 1 or 0,
            item.Quest() and 1 or 0,
            item.Lore() and 1 or 0,
            item.AugType() > 0 and 1 or 0,
            item.Stackable() and 1 or 0,
            item.Value() or 0,
            item.Tribute() or 0,
            item.StackSize() or 0,
            item.Clicky() or nil,
            item.AugType() or 0,
            item.STR() or 0,
            item.DEX() or 0,
            item.AGI() or 0,
            item.STA() or 0,
            item.INT() or 0,
            item.WIS() or 0,
            item.CHA() or 0,
            item.Mana() or 0,
            item.HP() or 0,
            item.AC() or 0,
            item.HPRegen() or 0,
            item.ManaRegen() or 0,
            item.Haste() or 0,
            item.ItemLink('CLICKABLE')() or nil,
            (item.Weight() or 0) * 10,
            item.Classes() or 0,
            loot.retrieveClassList(item),
            item.svFire() or 0,
            item.svCold() or 0,
            item.svDisease() or 0,
            item.svPoison() or 0,
            item.svCorruption() or 0,
            item.svMagic() or 0,
            item.SpellDamage() or 0,
            item.SpellShield() or 0,
            item.Races() or 0,
            loot.retrieveRaceList(item),
            item.Collectible() and 1 or 0,
            item.Attack() or 0,
            item.Damage() or 0,
            item.WeightReduction() or 0,
            item.Size() or 0,
            item.Icon() or 0,
            item.StrikeThrough() or 0,
            item.HeroicAGI() or 0,
            item.HeroicCHA() or 0,
            item.HeroicDEX() or 0,
            item.HeroicINT() or 0,
            item.HeroicSTA() or 0,
            item.HeroicSTR() or 0,
            item.HeroicSvCold() or 0,
            item.HeroicSvCorruption() or 0,
            item.HeroicSvDisease() or 0,
            item.HeroicSvFire() or 0,
            item.HeroicSvMagic() or 0,
            item.HeroicSvPoison() or 0,
            item.HeroicWIS() or 0
        )
        stmt:step()
    end)

    if not success then
        Logger.Error("Error executing SQL statement: %s", errmsg)
    end

    stmt:finalize()
    db:close()

    -- insert the item into the lua table for easier lookups

    local itemID                             = item.ID()
    loot.ALLITEMS[itemID]                    = {}
    loot.ALLITEMS[itemID].Name               = item.Name()
    loot.ALLITEMS[itemID].NoDrop             = item.NoDrop()
    loot.ALLITEMS[itemID].NoTrade            = item.NoTrade()
    loot.ALLITEMS[itemID].Tradeskills        = item.Tradeskills()
    loot.ALLITEMS[itemID].Quest              = item.Quest()
    loot.ALLITEMS[itemID].Lore               = item.Lore()
    loot.ALLITEMS[itemID].Augment            = item.AugType() > 0
    loot.ALLITEMS[itemID].Stackable          = item.Stackable()
    loot.ALLITEMS[itemID].Value              = loot.valueToCoins(item.Value())
    loot.ALLITEMS[itemID].Tribute            = item.Tribute()
    loot.ALLITEMS[itemID].StackSize          = item.StackSize()
    loot.ALLITEMS[itemID].Clicky             = item.Clicky()
    loot.ALLITEMS[itemID].AugType            = item.AugType()
    loot.ALLITEMS[itemID].STR                = item.STR()
    loot.ALLITEMS[itemID].DEX                = item.DEX()
    loot.ALLITEMS[itemID].AGI                = item.AGI()
    loot.ALLITEMS[itemID].STA                = item.STA()
    loot.ALLITEMS[itemID].INT                = item.INT()
    loot.ALLITEMS[itemID].WIS                = item.WIS()
    loot.ALLITEMS[itemID].CHA                = item.CHA()
    loot.ALLITEMS[itemID].Mana               = item.Mana()
    loot.ALLITEMS[itemID].HP                 = item.HP()
    loot.ALLITEMS[itemID].AC                 = item.AC()
    loot.ALLITEMS[itemID].HPRegen            = item.HPRegen()
    loot.ALLITEMS[itemID].ManaRegen          = item.ManaRegen()
    loot.ALLITEMS[itemID].Haste              = item.Haste()
    loot.ALLITEMS[itemID].Classes            = item.Classes()
    loot.ALLITEMS[itemID].ClassList          = loot.retrieveClassList(item)
    loot.ALLITEMS[itemID].svFire             = item.svFire()
    loot.ALLITEMS[itemID].svCold             = item.svCold()
    loot.ALLITEMS[itemID].svDisease          = item.svDisease()
    loot.ALLITEMS[itemID].svPoison           = item.svPoison()
    loot.ALLITEMS[itemID].svCorruption       = item.svCorruption()
    loot.ALLITEMS[itemID].svMagic            = item.svMagic()
    loot.ALLITEMS[itemID].SpellDamage        = item.SpellDamage()
    loot.ALLITEMS[itemID].SpellShield        = item.SpellShield()
    loot.ALLITEMS[itemID].Damage             = item.Damage()
    loot.ALLITEMS[itemID].Weight             = item.Weight()
    loot.ALLITEMS[itemID].Size               = item.Size()
    loot.ALLITEMS[itemID].WeightReduction    = item.WeightReduction()
    loot.ALLITEMS[itemID].Races              = item.Races() or 0
    loot.ALLITEMS[itemID].RaceList           = loot.retrieveRaceList(item)
    loot.ALLITEMS[itemID].Icon               = item.Icon()
    loot.ALLITEMS[itemID].Attack             = item.Attack()
    loot.ALLITEMS[itemID].Collectible        = item.Collectible()
    loot.ALLITEMS[itemID].StrikeThrough      = item.StrikeThrough()
    loot.ALLITEMS[itemID].HeroicAGI          = item.HeroicAGI()
    loot.ALLITEMS[itemID].HeroicCHA          = item.HeroicCHA()
    loot.ALLITEMS[itemID].HeroicDEX          = item.HeroicDEX()
    loot.ALLITEMS[itemID].HeroicINT          = item.HeroicINT()
    loot.ALLITEMS[itemID].HeroicSTA          = item.HeroicSTA()
    loot.ALLITEMS[itemID].HeroicSTR          = item.HeroicSTR()
    loot.ALLITEMS[itemID].HeroicSvCold       = item.HeroicSvCold()
    loot.ALLITEMS[itemID].HeroicSvCorruption = item.HeroicSvCorruption()
    loot.ALLITEMS[itemID].HeroicSvDisease    = item.HeroicSvDisease()
    loot.ALLITEMS[itemID].HeroicSvFire       = item.HeroicSvFire()
    loot.ALLITEMS[itemID].HeroicSvMagic      = item.HeroicSvMagic()
    loot.ALLITEMS[itemID].HeroicSvPoison     = item.HeroicSvPoison()
    loot.ALLITEMS[itemID].HeroicWIS          = item.HeroicWIS()
    loot.ALLITEMS[itemID].Link               = item.ItemLink('CLICKABLE')()
end

function loot.valueToCoins(sellVal)
    local platVal   = math.floor(sellVal / 1000)
    local goldVal   = math.floor((sellVal % 1000) / 100)
    local silverVal = math.floor((sellVal % 100) / 10)
    local copperVal = sellVal % 10
    return string.format("%s pp %s gp %s sp %s cp", platVal, goldVal, silverVal, copperVal)
end

function loot.checkSpells(item_name)
    if string.find(item_name, "Spell: ") then
        return true
    end
    return false
end

function loot.addNewItem(corpseItem, itemRule, itemLink, corpseID)
    if not corpseItem or not itemRule then
        Logger.Warn("\aoInvalid parameters for addNewItem:\ax corpseItem=\at%s\ax, itemRule=\ag%s",
            tostring(corpseItem), tostring(itemRule))
        return
    end

    -- Retrieve the itemID from corpseItem
    local itemID = corpseItem.ID()
    if not itemID then
        Logger.Warn("\arFailed to retrieve \axitemID\ar for corpseItem:\ax %s", tostring(corpseItem.Name()))
        return
    end
    if loot.NewItems[itemID] ~= nil then return end
    local isNoDrop        = corpseItem.NoDrop()
    loot.TempItemClasses  = loot.retrieveClassList(corpseItem)
    loot.TempItemRaces    = loot.retrieveRaceList(corpseItem)
    -- Add the new item to the loot.NewItems table
    loot.NewItems[itemID] = {
        Name       = corpseItem.Name(),
        ItemID     = itemID, -- Include itemID for display and handling
        Link       = itemLink,
        Rule       = isNoDrop and "CanUse" or itemRule,
        NoDrop     = isNoDrop,
        Icon       = corpseItem.Icon(),
        Lore       = corpseItem.Lore(),
        Tradeskill = corpseItem.Tradeskills(),
        Aug        = corpseItem.AugType() > 0,
        Stackable  = corpseItem.Stackable(),
        MaxStacks  = corpseItem.StackSize() or 0,
        SellPrice  = loot.valueToCoins(corpseItem.Value()),
        Classes    = loot.TempItemClasses,
        Races      = loot.TempItemRaces,
        CorpseID   = corpseID,
    }

    -- Increment the count of new items
    loot.NewItemsCount    = loot.NewItemsCount + 1

    if loot.Settings.AutoShowNewItem then
        showNewItem = true
    end

    -- Notify the loot actor of the new item
    Logger.Info("\agNew Loot\ay Item Detected! \ax[\at %s\ax ]\ao Sending actors", corpseItem.Name())
    loot.lootActor:send(
        { mailbox = 'lootnscoot', },
        {
            who        = MyName,
            action     = 'new',
            item       = corpseItem.Name(),
            itemID     = itemID,
            Server     = eqServer,
            rule       = isNoDrop and "CanUse" or itemRule,
            classes    = loot.retrieveClassList(corpseItem),
            races      = loot.retrieveRaceList(corpseItem),
            link       = itemLink,
            lore       = corpseItem.Lore(),
            icon       = corpseItem.Icon(),
            aug        = corpseItem.AugType() > 0 and true or false,
            noDrop     = isNoDrop,
            tradeskill = corpseItem.Tradeskills(),
            stackable  = corpseItem.Stackable(),
            maxStacks  = corpseItem.StackSize() or 0,
            sellPrice  = loot.valueToCoins(corpseItem.Value()),
            corpse     = corpseID,
        }
    )

    Logger.Info("\agAdding \ayNEW\ax item: \at%s \ay(\axID: \at%s\at) \axwith rule: \ag%s", corpseItem.Name(), itemID, itemRule)
end

function loot.checkCursor()
    local currentItem = nil
    while mq.TLO.Cursor() do
        -- can't do anything if there's nowhere to put the item, either due to no free inventory space
        -- or no slot of appropriate size
        if mq.TLO.Me.FreeInventory() == 0 or mq.TLO.Cursor() == currentItem then
            if loot.Settings.SpamLootInfo then Logger.Debug('Inventory full, item stuck on cursor') end
            mq.cmdf('/autoinv')
            return
        end
        currentItem = mq.TLO.Cursor()
        mq.cmdf('/autoinv')
        mq.delay(100)
    end
end

function loot.navToID(spawnID)
    mq.cmdf('/nav id %d log=off', spawnID)
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

---comment: Takes in an item to modify the rules for, You can add, delete, or modify the rules for an item.
---Upon completeion it will notify the loot actor to update the loot settings, for any other character that is using the loot actor.
---@param itemID integer The ID for the item we are modifying
---@param action string The action to perform (add, delete, modify)
---@param tableName string The table to modify (Normal_Rules, Global_Rules)
---@param classes string The classes to apply the rule to
---@param link string|nil The item link if available for the item
function loot.modifyItemRule(itemID, action, tableName, classes, link)
    if not itemID or not tableName or not action then
        Logger.Warn("Invalid parameters for modifyItemRule. itemID: %s, tableName: %s, action: %s",
            tostring(itemID), tostring(tableName), tostring(action))
        return
    end

    local section = tableName == "Normal_Rules" and "NormalItems" or "GlobalItems"

    -- Validate RulesDB
    if not RulesDB or type(RulesDB) ~= "string" then
        Logger.Warn("Invalid RulesDB path: %s", tostring(RulesDB))
        return
    end

    -- Retrieve the item name from loot.ALLITEMS
    local itemName = loot.ALLITEMS[itemID] and loot.ALLITEMS[itemID].Name
    if not itemName then
        Logger.Warn("Item ID \at%s\ax \arNOT\ax found in \ayloot.ALLITEMS", tostring(itemID))
        return
    end

    -- Set default values
    if link == nil then
        link = loot.ALLITEMS[itemID].Link or 'NULL'
    end
    classes  = classes or 'All'

    -- Open the database
    local db = SQLite3.open(RulesDB)
    if not db then
        Logger.Warn("Failed to open database.")
        return
    end

    local stmt
    local sql

    if action == 'delete' then
        -- DELETE operation
        Logger.Info("\aoloot.modifyItemRule\ax \arDeleting rule\ax for item \at%s\ax in table \at%s", itemName, tableName)
        if tableName == "Normal_Rules" then
            sql = string.format("DELETE FROM Normal_Rules WHERE item_id = ?")
        else
            sql = string.format("DELETE FROM Global_Rules WHERE item_id = ?")
        end

        stmt = db:prepare(sql)

        if stmt then
            stmt:bind_values(itemID)
        end
    else
        -- UPSERT operation
        if tableName == "Normal_Rules" then
            sql  = [[
                INSERT INTO Normal_Rules
                (item_id, item_name, item_rule, item_rule_classes, item_link)
                VALUES (?, ?, ?, ?, ?)
                ON CONFLICT(item_id) DO UPDATE SET
                item_name                                    = excluded.item_name,
                item_rule                                    = excluded.item_rule,
                item_rule_classes                                    = excluded.item_rule_classes,
                item_link                                    = excluded.item_link
                ]]
            stmt = db:prepare(sql)
            if stmt then
                stmt:bind_values(itemID, itemName, action, classes, link)
            end
        else
            sql  = [[
                INSERT INTO Global_Rules
                (item_id, item_name, item_rule, item_rule_classes, item_link)
                VALUES (?, ?, ?, ?, ?)
                ON CONFLICT(item_id) DO UPDATE SET
                item_name                                    = excluded.item_name,
                item_rule                                    = excluded.item_rule,
                item_rule_classes                                    = excluded.item_rule_classes,
                item_link                                    = excluded.item_link
                ]]
            stmt = db:prepare(sql)
            if stmt then
                stmt:bind_values(itemID, itemName, action, classes, link)
            end
        end
    end

    if not stmt then
        Logger.Warn("Failed to prepare SQL statement for table: %s, item:%s (%s), rule: %s, classes: %s", tableName, itemName, itemID, action, classes)
        db:close()
        return
    end

    -- Execute the statement
    local success, errmsg = pcall(function() stmt:step() end)
    if not success then
        Logger.Warn("Failed to execute SQL statement for table %s. Error: %s", tableName, errmsg)
    else
        Logger.Info("SQL statement executed successfully for item %s in table %s.", itemName, tableName)
    end

    -- Finalize and close the database
    stmt:finalize()
    db:close()

    if success then
        -- Notify other actors about the rule change
        loot.lootActor:send({ mailbox = 'lootnscoot', }, {
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
function loot.addRule(itemID, section, rule, classes, link)
    if not itemID or not section or not rule then
        Logger.Warn("Invalid parameters for addRule. itemID: %s, section: %s, rule: %s",
            tostring(itemID), tostring(section), tostring(rule))
        return false
    end

    -- Retrieve the item name from loot.ALLITEMS
    local itemName = loot.ALLITEMS[itemID] and loot.ALLITEMS[itemID].Name or nil
    if not itemName then
        Logger.Warn("Item ID \at%s\ax \arNOT\ax found in \ayloot.ALLITEMS", tostring(itemID))
        return false
    end

    -- Set default values for optional parameters
    classes                = classes or 'All'
    link                   = link or 'NULL'

    -- Log the action
    -- Logger.Info("\agAdding\ax rule for item \at%s\ax\ao (\ayID\ax:\ag %s\ax\ao)\ax in [section] \at%s \axwith [rule] \at%s\ax and [classes] \at%s",
    -- itemName, itemID, section, rule, classes)

    -- Update the in-memory data structure
    loot.ItemNames[itemID] = itemName

    if section == 'GlobalItems' then
        loot.GlobalItemsRules[itemID]   = rule
        loot.GlobalItemsClasses[itemID] = classes
        loot.GlobalItemsLink[itemID]    = link
        loot.modifyItemRule(itemID, rule, 'Global_Rules', classes, link)
    else
        loot.NormalItemsRules[itemID]   = rule
        loot.NormalItemsLink[itemID]    = link
        loot.NormalItemsClasses[itemID] = classes
        loot.modifyItemRule(itemID, rule, 'Normal_Rules', classes, link)
    end


    -- Refresh the loot settings to apply the changes
    return true
end

function loot.actorAddRule(itemID, itemName, tableName, rule, classes, link)
    loot.ItemNames[itemID] = itemName

    if tableName == 'GlobalItems' then
        loot.GlobalItemsRules[itemID]   = rule
        loot.GlobalItemsClasses[itemID] = classes
        loot.GlobalItemsLink[itemID]    = link
        loot.modifyItemRule(itemID, rule, 'Global_Rules', classes, link)
    else
        loot.NormalItemsRules[itemID]   = rule
        loot.NormalItemsLink[itemID]    = link
        loot.NormalItemsClasses[itemID] = classes
        loot.modifyItemRule(itemID, rule, 'Normal_Rules', classes, link)
    end
end

---@param itemID any
---@param tablename any|nil
---@return string rule
---@return string classes
---@return string link
function loot.lookupLootRule(itemID, tablename)
    if not itemID then
        return 'NULL', 'All', 'NULL'
    end
    -- check lua tables first

    if tablename == 'Global_Rules' then
        if loot.GlobalItemsRules[itemID] ~= nil then
            return loot.GlobalItemsRules[itemID], loot.GlobalItemsClasses[itemID], loot.GlobalItemsLink[itemID]
        end
    elseif tablename == 'Normal_Rules' then
        if loot.NormalItemsRules[itemID] ~= nil then
            return loot.NormalItemsRules[itemID], loot.NormalItemsClasses[itemID], loot.NormalItemsLink[itemID]
        end
    elseif tablename == nil then
        if loot.GlobalItemsRules[itemID] ~= nil then
            return loot.GlobalItemsRules[itemID], loot.GlobalItemsClasses[itemID], loot.GlobalItemsLink[itemID]
        end
        if loot.NormalItemsRules[itemID] ~= nil then
            return loot.NormalItemsRules[itemID], loot.NormalItemsClasses[itemID], loot.NormalItemsLink[itemID]
        end
    end

    -- check SQLite DB if lua tables don't have the data
    local function checkDB(id, tbl)
        local db = SQLite3.open(RulesDB)
        local found = false
        if not db then
            Logger.Warn("\atSQL \arFailed\ax to open \atRulesDB:\ax for \aolookupLootRule\ax.")
            return found, 'NULL', 'All', 'NULL'
        end

        local sql  = string.format("SELECT item_rule, item_rule_classes, item_link FROM %s WHERE item_id = ?", tbl)
        local stmt = db:prepare(sql)

        if not stmt then
            Logger.Warn("\atSQL \arFAILED \axto prepare statement for \atlookupLootRule\ax.")
            db:close()
            return found, 'NULL', 'All', 'NULL'
        end

        stmt:bind_values(id)
        local stepResult = stmt:step()

        local rule       = 'NULL'
        local classes    = 'All'
        local link       = 'NULL'

        -- Extract values if a row is returned
        if stepResult == SQLite3.ROW then
            local row = stmt:get_named_values()
            rule      = row.item_rule or 'NULL'
            classes   = row.item_rule_classes or 'All'
            link      = row.item_link or 'NULL'
            found     = true
        end

        -- Finalize the statement and close the database
        stmt:finalize()
        db:close()
        return found, rule, classes, link
    end

    local rule    = 'NULL'
    local classes = 'All'
    local link    = 'NULL'

    if tablename == nil then
        -- check global rules
        local found = false
        found, rule, classes, link = checkDB(itemID, 'Global_Rules')
        if not found then
            found, rule, classes, link = checkDB(itemID, 'Normal_Rules')
        end

        if not found then
            rule = 'NULL'
            classes = 'All'
            link = 'NULL'
        end
    else
        _, rule, classes, link = checkDB(itemID, tablename)
    end

    -- if SQL has the item add the rules to the lua table for next time

    if rule ~= 'NULL' then
        if tablename == 'Normal_Rules' then
            loot.NormalItemsRules[itemID]   = rule
            loot.NormalItemsClasses[itemID] = classes
            loot.NormalItemsLink[itemID]    = link
            loot.ItemNames[itemID]          = loot.ALLITEMS[itemID].Name
        else
            loot.GlobalItemsRules[itemID]   = rule
            loot.GlobalItemsClasses[itemID] = classes
            loot.GlobalItemsLink[itemID]    = link
            loot.ItemNames[itemID]          = loot.ALLITEMS[itemID].Name
        end
    end
    return rule, classes, link
end

function loot.report(message, ...)
    if loot.Settings.ReportLoot then
        local prefixWithChannel = reportPrefix:format(loot.Settings.LootChannel, mq.TLO.Time())
        mq.cmdf(prefixWithChannel .. message, ...)
    end
end

function loot.AreBagsOpen()
    local total = {
        bags = 0,
        open = 0,
    }
    for i = 23, 32 do
        local slot = mq.TLO.Me.Inventory(i)
        if slot and slot.Container() and slot.Container() > 0 then
            total.bags = total.bags + 1
            ---@diagnostic disable-next-line: undefined-field
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

function loot.processPendingItem()
    if not loot.pendingItemData and not loot.pendingItemData.selectedItem then
        Logger.Warn("No item selected for processing.")
        return
    end

    -- Extract the selected item and callback
    local selectedItem = loot.pendingItemData.selectedItem
    local callback     = loot.pendingItemData.callback

    -- Call the callback with the selected item
    if callback then
        callback(selectedItem)
    else
        Logger.Warn("No callback defined for selected item.")
    end

    -- Clear pending data after processing
    loot.pendingItemData = nil
end

function loot.resolveDuplicateItems(itemName, duplicates, callback)
    loot.itemSelectionPending = true
    loot.pendingItemData      = { callback = callback, }

    -- Render the selection UI
    ImGui.SetNextWindowSize(400, 300, ImGuiCond.FirstUseEver)
    local open = ImGui.Begin("Resolve Duplicates", true)
    if open then
        ImGui.Text("Multiple items found for: " .. itemName)
        ImGui.Separator()

        for _, item in ipairs(duplicates) do
            if ImGui.Button("Select##" .. item.ID) then
                loot.itemSelectionPending         = false
                loot.pendingItemData.selectedItem = item.ID
                ImGui.CloseCurrentPopup()
                callback(item.ID) -- Trigger the callback with the selected ID
                break
            end
            ImGui.SameLine()
            ImGui.Text(item.Link)
        end
    end
    ImGui.End()
end

function loot.getMatchingItemsByName(itemName)
    local matches = {}
    for _, item in pairs(loot.ALLITEMS) do
        if item.Name == itemName then
            table.insert(matches, item)
        end
    end
    return matches
end

function loot.getRuleIndex(rule, ruleList)
    for i, v in ipairs(ruleList) do
        if v == rule then
            return i
        end
    end
    return 1 -- Default to the first rule if not found
end

function loot.retrieveClassList(item)
    local classList = ""
    local numClasses = item.Classes()
    if numClasses < 16 then
        for i = 1, numClasses do
            classList = string.format("%s %s", classList, item.Class(i).ShortName())
        end
    else
        classList = "All"
    end
    return classList
end

function loot.retrieveRaceList(item)
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
    local numRaces = item.Races()
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
function loot.resolveItemIDbyName(itemName, allowDuplicates)
    if allowDuplicates == nil then allowDuplicates = false end
    local matches = {}

    local foundItems = loot.GetItemFromDB(itemName, 0)

    if foundItems > 1 and not allowDuplicates then
        printf("\ayMultiple \atMatches Found for ItemName: \am%s \ax #\ag%d\ax", itemName, foundItems)
    end

    for id, item in pairs(loot.ALLITEMS or {}) do
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

    if allowDuplicates then
        return matches[1].ID
    end

    if #matches == 0 then
        return nil           -- No matches found
    elseif #matches == 1 then
        return matches[1].ID -- Single match
    else
        -- Display a selection window to the user
        loot.resolveDuplicateItems(itemName, matches, function(selectedItemID)
            loot.pendingItemData.selectedItem = selectedItemID
        end)
        return nil -- Wait for user resolution
    end
end

function loot.sendMySettings()
    local tmpTable = {}
    for k, v in pairs(loot.Settings) do
        if type(v) == 'table' then
            tmpTable[k] = {}
            for kk, vv in pairs(v) do
                tmpTable[k][kk] = vv
            end
        else
            tmpTable[k] = v
        end
    end
    loot.lootActor:send({ mailbox = 'lootnscoot', }, {
        who      = MyName,
        action   = 'sendsettings',
        settings = tmpTable,
    })
    loot.Boxes[MyName] = {}
    for k, v in pairs(loot.Settings) do
        if type(v) == 'table' then
            loot.Boxes[MyName][k] = {}
            for kk, vv in pairs(v) do
                loot.Boxes[MyName][k][kk] = vv
            end
        else
            loot.Boxes[MyName][k] = v
        end
    end
end

--- Evaluate and return the rule for an item.
---@param item MQItem Item object
---@param from string Source of the of the callback (loot, bank, etc.)
---@return string Rule The Loot Rule or decision of no Rule
---@return integer Count The number of items to keep if Quest Item
---@return boolean newRule True if Item does not exist in the Rules Tables
---@return boolean|nil cantWear True if the item is not wearable by the character
function loot.getRule(item, from)
    if item == nil then return 'NULL', 0, false end
    local itemID = item.ID() or 0
    if itemID == 0 then return 'NULL', 0, false end

    -- Initialize values
    local lootDecision                    = 'Keep'
    local tradeskill                      = item.Tradeskills()
    local sellPrice                       = (item.Value() or 0) / 1000
    local stackable                       = item.Stackable()
    local augment                         = item.AugType() or 0
    local tributeValue                    = item.Tribute()
    local stackSize                       = item.StackSize()
    local countHave                       = mq.TLO.FindItemCount(item.Name())() + mq.TLO.FindItemBankCount(item.Name())()
    local itemName                        = item.Name()
    local newRule                         = false
    local alwaysAsk                       = false

    -- Lookup existing rule in the databases
    local lootRule, lootClasses, lootLink = loot.lookupLootRule(itemID)
    Logger.Info("Item: %s, Rule: %s, Classes: %s, Link: %s", itemName, lootRule, lootClasses, lootLink)
    if lootRule == 'NULL' and item.NoDrop() then
        lootRule = "CanUse"
        loot.addRule(itemID, 'NormalItems', lootRule, lootClasses, item.ItemLink('CLICKABLE')())
    end


    if lootRule == 'Ask' then alwaysAsk = true end

    -- -- Update link if missing and rule exists
    -- if lootRule ~= "NULL" and lootLink == "NULL" then
    --     loot.addRule(itemID, 'NormalItems', lootRule, lootClasses, item.ItemLink('CLICKABLE')())
    -- end

    -- Re-evaluate settings if AlwaysEval is enabled
    if loot.Settings.AlwaysEval then
        local resetDecision = "NULL"
        if lootRule == "Quest" or lootRule == "Keep" or lootRule == "Destroy" or lootRule == 'CanUse' then
            resetDecision = lootRule
        elseif lootRule == "Sell" then
            if (not stackable and sellPrice >= loot.Settings.MinSellPrice) or
                (stackable and sellPrice * stackSize >= loot.Settings.StackPlatValue) then
                resetDecision = lootRule
            end
        elseif lootRule == "Bank" and tradeskill and loot.Settings.BankTradeskills then
            resetDecision = lootRule
        end
        lootRule = resetDecision
    end

    -- Evaluate new rules if no valid rule exists
    if lootRule == "NULL" then
        if tradeskill and loot.Settings.BankTradeskills then lootDecision = "Bank" end
        if not stackable and sellPrice < loot.Settings.MinSellPrice then lootDecision = "Ignore" end
        if not stackable and loot.Settings.StackableOnly then lootDecision = "Ignore" end
        if stackable and sellPrice * stackSize < loot.Settings.StackPlatValue then lootDecision = "Ignore" end
        if tributeValue >= loot.Settings.MinTributeValue and sellPrice < loot.Settings.MinSellPrice then lootDecision = "Tribute" end

        if loot.Settings.AutoTag and lootDecision == "Keep" then
            if not stackable and sellPrice > loot.Settings.MinSellPrice then lootDecision = "Sell" end
            if stackable and sellPrice * stackSize >= loot.Settings.StackPlatValue then lootDecision = "Sell" end
        end

        loot.addRule(itemID, 'NormalItems', lootDecision, "All", item.ItemLink('CLICKABLE')())
        newRule = true
    else
        lootDecision = lootRule
    end

    -- Handle GlobalItems override
    if loot.Settings.GlobalLootOn then
        local globalRule, globalClasses = loot.GlobalItemsRules[itemID] or "NULL", loot.GlobalItemsClasses[itemID] or "All"
        if globalRule ~= "NULL" then
            if globalClasses:lower() ~= "all" and from == "loot" and not string.find(globalClasses:lower(), loot.MyClass) then
                lootDecision = "Ignore"
            else
                lootDecision = globalRule
            end
        end
    end

    -- Handle specific class-based rules
    if lootClasses:lower() ~= "all" then
        if from == "loot" and not string.find(lootClasses:lower(), loot.MyClass) then
            lootDecision = "Ignore"
        end
    end

    -- Handle augments
    if loot.Settings.LootAugments and augment > 0 then
        lootDecision = "Keep"
    end

    -- Handle Quest items
    if string.find(lootDecision, "Quest") then
        local qKeep = "0"
        if loot.Settings.LootQuest then
            local _, position = string.find(lootDecision, "|")
            if position then qKeep = lootDecision:sub(position + 1) else qKeep = tostring(loot.Settings.QuestKeep) end
            if countHave < tonumber(qKeep) then
                return "Keep", tonumber(qKeep), newRule
            end
            if loot.Settings.AlwaysDestroy then
                return "Destroy", tonumber(qKeep), newRule
            end
        end
        return "Ignore", tonumber(qKeep), newRule
    end

    local cantWear = false
    -- Handle Optionally Loot Only items you can use.
    if (loot.Settings.CanWear and lootDecision == 'Keep') or lootDecision == 'CanUse' then
        -- if (lootClasses:lower() == 'all' or (string.find(loot.resolveClassList(item):lower(), loot.MyClass))) and
        --     (loot.resolveRaceList(item):lower() == 'all' or (string.find(loot.resolveRaceList(item):lower(), loot.MyRace:lower()))) then
        --     lootDecision = 'Keep'
        -- else
        --     lootDecision = 'Ignore'
        -- end
        if not item.CanUse() then
            lootDecision = 'Ignore'
            cantWear = true
        end
    end

    -- Handle Spell Drops
    if loot.Settings.KeepSpells and loot.checkSpells(itemName) then
        lootDecision = "Keep"
        newRule      = true
    end

    -- Handle AlwaysDestroy setting
    if loot.Settings.AlwaysDestroy and lootDecision == "Ignore" then
        lootDecision = "Destroy"
    end

    -- Handle AlwaysKeep setting
    if alwaysAsk then
        newRule = true
        lootDecision = "Ask"
    end



    return lootDecision, 0, newRule, cantWear
end

-- EVENTS

function loot.RegisterActors()
    loot.lootActor = Actors.register('lootnscoot', function(message)
        local lootMessage = message()
        local who         = lootMessage.who or ''
        local action      = lootMessage.action or ''
        local itemID      = lootMessage.itemID or 0
        local rule        = lootMessage.rule or 'NULL'
        local section     = lootMessage.section or 'NormalItems'
        local server      = lootMessage.Server or 'NULL'
        local itemName    = lootMessage.item or 'NULL'
        local itemLink    = lootMessage.link or 'NULL'
        local itemClasses = lootMessage.classes or 'All'
        local itemRaces   = lootMessage.races or 'All'
        local boxSettings = lootMessage.settings or {}
        if itemName == 'NULL' then
            itemName = loot.ALLITEMS[itemID] and loot.ALLITEMS[itemID].Name or 'NULL'
        end
        if action == 'Hello' and who ~= MyName then
            loot.sendMySettings()
            return
        end
        -- Logger.Info("loot.RegisterActors: \agReceived\ax message:\atSub \ay%s\aw, \atItem \ag%s\aw, \atRule \ag%s", action, itemID, rule)
        if action == 'sendsettings' and who ~= MyName then
            loot.Boxes[who] = {}
            for k, v in pairs(boxSettings) do
                if type(k) ~= 'table' then
                    loot.Boxes[who][k] = v
                else
                    loot.Boxes[who][k] = {}
                    for i, j in pairs(v) do
                        loot.Boxes[who][k][i] = j
                    end
                end
            end
        end

        if action == 'updatesettings' and who == MyName then
            for k, v in pairs(boxSettings) do
                if type(k) ~= 'table' then
                    loot.Settings[k] = v
                else
                    for i, j in pairs(v) do
                        loot.Settings[k][i] = j
                    end
                end
            end
            mq.pickle(SettingsFile, loot.Settings)
            loot.loadSettings()
            loot.sendMySettings()
        end
        if server ~= eqServer then return end

        -- Reload loot settings
        if action == 'lootreload' then
            loot.commandHandler('reload')
            return
        end
        -- Handle actions
        if lootMessage.noChange then
            if lootedCorpses[lootMessage.corpse] then
                lootedCorpses[lootMessage.corpse] = nil
            end

            loot.NewItems[itemID] = nil
            loot.NewItemsCount = loot.NewItemsCount - 1
            Logger.Info("loot.RegisterActors: \atNew Item Rule \ax\agConfirmed:\ax [\ay%s\ax] NewItemCount Remaining \ag%s\ax", itemLink, loot.NewItemsCount)
            return
        end

        if action == 'addrule' or action == 'modifyitem' then
            if section == 'GlobalItems' then
                loot.GlobalItemsRules[itemID]   = rule
                loot.GlobalItemsClasses[itemID] = itemClasses
                loot.GlobalItemsLink[itemID]    = itemLink
                loot.ItemNames[itemID]          = itemName
            else
                loot.NormalItemsRules[itemID]   = rule
                loot.NormalItemsClasses[itemID] = itemClasses
                loot.NormalItemsLink[itemID]    = itemLink
                loot.ItemNames[itemID]          = itemName
            end

            Logger.Info("loot.RegisterActors: \atAction:\ax [\ay%s\ax] \ag%s\ax rule for item \at%s\ax", action, rule, lootMessage.item)
            if lootMessage.entered then
                if lootedCorpses[lootMessage.corpse] then
                    lootedCorpses[lootMessage.corpse] = nil
                end

                loot.NewItems[itemID] = nil
                loot.NewItemsCount = loot.NewItemsCount - 1
                Logger.Info("loot.RegisterActors: \atNew Item Rule \ax\agUpdated:\ax [\ay%s\ax] NewItemCount Remaining \ag%s\ax", lootMessage.entered, loot.NewItemsCount)
            end

            local db = loot.OpenItemsSQL()
            loot.GetItemFromDB(itemName, itemID)
            db:close()
            loot.lookupLootRule(itemID)

            -- clean bags of items marked as destroy so we don't collect garbage
            if rule:lower() == 'destroy' then
                loot.cleanupBags()
            end
        elseif action == 'deleteitem' and who ~= MyName then
            if section == 'GlobalItems' then
                loot.GlobalItemsRules[itemID]   = nil
                loot.GlobalItemsClasses[itemID] = nil
                loot.GlobalItemsLink[itemID]    = nil
            else
                loot.NormalItemsRules[itemID]   = nil
                loot.NormalItemsClasses[itemID] = nil
                loot.NormalItemsLink[itemID]    = nil
                Logger.Info("loot.RegisterActors: \atAction:\ax [\ay%s\ax] \ag%s\ax rule for item \at%s\ax", action, rule, lootMessage.item)
            end
        elseif action == 'new' and who ~= MyName and loot.NewItems[itemID] == nil then
            loot.NewItems[itemID] = {
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
            Logger.Info("loot.RegisterActors: \atAction:\ax [\ay%s\ax] \ag%s\ax rule for item \at%s\ax", action, rule, lootMessage.item)
            loot.NewItemsCount = loot.NewItemsCount + 1
            if loot.Settings.AutoShowNewItem then
                showNewItem = true
            end
        elseif action == 'ItemsDB_UPDATE' and who ~= MyName then
            -- loot.LoadItemsDB()
        end

        -- Notify modules of loot setting changes
    end)
end

local itemNoValue = nil
function loot.eventNovalue(line, item)
    itemNoValue = item
end

function loot.setupEvents()
    mq.event("CantLoot", "#*#may not loot this corpse#*#", loot.eventCantLoot)
    mq.event("NoSlot", "#*#There are no open slots for the held item in your inventory#*#", loot.eventNoSlot)
    mq.event("Sell", "#*#You receive#*# for the #1#(s)#*#", loot.eventSell)
    mq.event("ForageExtras", "Your forage mastery has enabled you to find something else!", loot.eventForage)
    mq.event("Forage", "You have scrounged up #*#", loot.eventForage)
    mq.event("Novalue", "#*#give you absolutely nothing for the #1#.#*#", loot.eventNovalue)
    mq.event("Tribute", "#*#We graciously accept your #1# as tribute, thank you!#*#", loot.eventTribute)
end

-- BINDS

function loot.setBuyItem(itemID, qty)
    loot.BuyItemsTable[itemID] = qty
end

-- Changes the class restriction for an item
function loot.ChangeClasses(itemID, classes, tableName)
    if tableName == 'GlobalItems' then
        loot.GlobalItemsClasses[itemID] = classes
        loot.modifyItemRule(itemID, loot.GlobalItemsRules[itemID], 'Global_Rules', classes)
    elseif tableName == 'NormalItems' then
        loot.NormalItemsClasses[itemID] = classes
        loot.modifyItemRule(itemID, loot.NormalItemsRules[itemID], 'Normal_Rules', classes)
    end
end

-- Sets a Global Item rule
function loot.setGlobalItem(itemID, val, classes, link)
    if itemID == nil then
        Logger.Warn("Invalid itemID for setGlobalItem.")
        return
    end
    loot.modifyItemRule(itemID, val, 'Global_Rules', classes, link)

    loot.GlobalItemsRules[itemID] = val ~= 'delete' and val or nil
    if val ~= 'delete' then
        loot.GlobalItemsClasses[itemID] = classes or 'All'
        loot.GlobalItemsLink[itemID]    = link or 'NULL'
    else
        loot.GlobalItemsClasses[itemID] = nil
        loot.GlobalItemsLink[itemID]    = nil
    end
end

-- Sets a Normal Item rule
function loot.setNormalItem(itemID, val, classes, link)
    if itemID == nil then
        Logger.Warn("Invalid itemID for setNormalItem.")
        return
    end
    loot.NormalItemsRules[itemID] = val ~= 'delete' and val or nil
    if val ~= 'delete' then
        loot.NormalItemsClasses[itemID] = classes or 'All'
        loot.NormalItemsLink[itemID]    = link or 'NULL'
    else
        loot.NormalItemsClasses[itemID] = nil
        loot.NormalItemsLink[itemID]    = nil
    end
    loot.modifyItemRule(itemID, val, 'Normal_Rules', classes, link)
end

-- Sets a Global Item rule for the item currently on the cursor
function loot.setGlobalBind(value)
    local itemID = mq.TLO.Cursor.ID()
    loot.setGlobalItem(itemID, value)
end

-- Main command handler
function loot.commandHandler(...)
    local args = { ..., }
    local item = mq.TLO.Cursor -- Capture the cursor item early for reuse

    if args[1] == 'set' then
        local setting    = args[2]:lower()
        local settingVal = args[3]
        if settingsEnum[setting] ~= nil then
            local settingName = settingsEnum[setting]
            if type(loot.Settings[settingName]) == 'table' then
                Logger.Error("Setting \ay%s\ax is a table and cannot be set directly.", settingName)
                return
            end
            if type(loot.Settings[settingName]) == 'boolean' then
                loot.Settings[settingName] = settingVal == 'on'
            elseif type(loot.Settings[settingName]) == 'number' then
                loot.Settings[settingName] = tonumber(settingVal)
            else
                loot.Settings[settingName] = settingVal
            end
            Logger.Info("Setting \ay%s\ax to \ag%s\ax", settingName, settingVal)
            loot.writeSettings()
        else
            Logger.Warn("Invalid setting name: %s", setting)
        end
        loot.writeSettings()
        loot.sendMySettings()
        return
    end
    Logger.Debug("arg1: %s, arg2: %s, arg3: %s, arg4: %s", tostring(args[1]), tostring(args[2]), tostring(args[3]), tostring(args[4]))

    if #args == 1 then
        local command = args[1]
        if command == 'sellstuff' then
            loot.processItems('Sell')
        elseif command == 'restock' then
            loot.processItems('Buy')
        elseif command == 'reload' then
            local needSave = loot.loadSettings()
            if needSave then
                loot.writeSettings()
            end
            if loot.guiLoot then
                loot.guiLoot.GetSettings(
                    loot.Settings.HideNames,
                    loot.Settings.LookupLinks,
                    loot.Settings.RecordData,
                    true,
                    loot.Settings.UseActors,
                    'lootnscoot', false
                )
            end
            Logger.Info("\ayReloaded Settings \axand \atLoot Files")
        elseif command == 'update' then
            if loot.guiLoot then
                loot.guiLoot.GetSettings(
                    loot.Settings.HideNames,
                    loot.Settings.LookupLinks,
                    loot.Settings.RecordData,
                    true,
                    loot.Settings.UseActors,
                    'lootnscoot', false
                )
            end
            loot.UpdateDB()
            Logger.Info("\ayUpdated the DB from loot.ini \axand \atreloaded settings")
        elseif command == 'importinv' then
            loot.addMyInventoryToDB()
        elseif command == 'bank' then
            loot.processItems('Bank')
        elseif command == 'cleanup' then
            loot.processItems('Destroy')
        elseif command == 'gui' and loot.guiLoot then
            loot.guiLoot.openGUI = not loot.guiLoot.openGUI
        elseif command == 'report' and loot.guiLoot then
            loot.guiLoot.ReportLoot()
        elseif command == 'hidenames' and loot.guiLoot then
            loot.guiLoot.hideNames = not loot.guiLoot.hideNames
        elseif command == 'config' then
            local confReport = "\ayLoot N Scoot Settings\ax"
            for key, value in pairs(loot.Settings) do
                if type(value) ~= "function" and type(value) ~= "table" then
                    confReport = confReport .. string.format("\n\at%s\ax                                    = \ag%s\ax", key, tostring(value))
                end
            end
            Logger.Info(confReport)
        elseif command == 'tributestuff' then
            loot.processItems('Tribute')
        elseif command == 'loot' then
            loot.lootMobs()
        elseif command == 'show' then
            loot.ShowUI = not loot.ShowUI
        elseif command == 'tsbank' then
            loot.markTradeSkillAsBank()
        elseif validActions[command] and item() then
            local itemID = item.ID()
            loot.addRule(itemID, 'NormalItems', validActions[command], 'All', item.ItemLink('CLICKABLE')())
            Logger.Info("Setting \ay%s\ax to \ay%s\ax", item.Name(), validActions[command])
        elseif string.find(command, "quest%|") and item() then
            local itemID = item.ID()
            local val    = string.gsub(command, "quest", "Quest")
            loot.addRule(itemID, 'NormalItems', val, 'All', item.ItemLink('CLICKABLE')())
            Logger.Info("Setting \ay%s\ax to \ay%s\ax", item.Name(), val)
        elseif command == 'quit' or command == 'exit' then
            loot.Terminate = true
        end
    elseif #args == 2 then
        local action, itemName = args[1], args[2]
        if validActions[action] then
            local lootID = loot.resolveItemIDbyName(itemName, false)
            Logger.Warn("lootID: %s", lootID)
            if lootID then
                if loot.ALLITEMS[lootID] then
                    loot.addRule(lootID, 'NormalItems', validActions[action], 'All', loot.ALLITEMS[lootID].Link)
                    Logger.Info("Setting \ay%s (%s)\ax to \ay%s\ax", itemName, lootID, validActions[action])
                end
            end
        end
    elseif #args == 3 then
        if args[1] == 'globalitem' and args[2] == 'quest' and item() then
            local itemID = item.ID()
            loot.addRule(itemID, 'GlobalItems', 'Quest|' .. args[3], 'All', item.ItemLink('CLICKABLE')())
            Logger.Info("Setting \ay%s\ax to \agGlobal Item \ayQuest|%s\ax", item.Name(), args[3], item.ItemLink('CLICKABLE')())
        elseif args[1] == 'globalitem' and validActions[args[2]] and item() then
            loot.addRule(item.ID(), 'GlobalItems', validActions[args[2]], args[3] ~= nil or 'All', item.ItemLink('CLICKABLE')())
            Logger.Info("Setting \ay%s\ax to \agGlobal Item \ay%s \ax(\at%s\ax)", item.Name(), item.ID(), validActions[args[2]])
        elseif args[1] == 'globalitem' and validActions[args[2]] and args[3] ~= nil then
            local itemName = args[3]
            local itemID   = loot.resolveItemIDbyName(itemName, false)
            if itemID then
                if loot.ALLITEMS[itemID] then
                    loot.addRule(itemID, 'GlobalItems', validActions[args[2]], 'All', loot.ALLITEMS[itemID].Link)
                    Logger.Info("Setting \ay%s\ax to \agGlobal Item \ay%s|%s\ax", loot.ALLITEMS[itemID].Name, validActions[args[2]], args[3])
                end
            else
                Logger.Warn("Item \ay%s\ax ID: %s\ax not found in loot.ALLITEMS.", itemName, itemID)
            end
        end
    end
    loot.writeSettings()
end

function loot.setupBinds()
    mq.bind('/lootutils', loot.commandHandler)
    mq.bind('/lns', loot.commandHandler)
end

-- LOOTING

function loot.CheckBags()
    if loot.Settings.SaveBagSlots == nil then return false end
    -- printf("\agBag CHECK\ax free: \at%s\ax, save: \ag%s\ax", mq.TLO.Me.FreeInventory(), loot.Settings.SaveBagSlots)
    areFull = mq.TLO.Me.FreeInventory() <= loot.Settings.SaveBagSlots
end

function loot.eventCantLoot()
    cantLootID = mq.TLO.Target.ID()
end

function loot.eventNoSlot()
    -- we don't have a slot big enough for the item on cursor. Dropping it to the ground.
    local cantLootItemName = mq.TLO.Cursor()
    mq.cmdf('/drop')
    mq.delay(1)
    loot.report("\ay[WARN]\arI can't loot %s, dropping it on the ground!\ax", cantLootItemName)
end

---@param index number @The current index in the loot window, 1-based.
---@param doWhat string @The action to take for the item.
---@param button string @The mouse button to use to loot the item. Only "leftmouseup" is currently implemented.
---@param qKeep number @The count to keep for quest items.
---@param allItems table @A table of all items seen on the corpse, left or looted.
---@param cantWear boolean|nil @ Whether the character canwear the item
function loot.lootItem(index, doWhat, button, qKeep, allItems, cantWear)
    Logger.Debug('Enter lootItem')

    local corpseItem = mq.TLO.Corpse.Item(index)
    if corpseItem and not shouldLootActions[doWhat] then
        if (doWhat == 'Ignore' and not (loot.Settings.DoDestroy and loot.Settings.AlwaysDestroy)) or
            (doWhat == 'Destroy' and not loot.Settings.DoDestroy) then
            table.insert(allItems,
                { Name = corpseItem.Name(), Action = 'Left', Link = corpseItem.ItemLink('CLICKABLE')(), Eval = doWhat, cantWear = cantWear, })
            return
        end
    end

    local corpseItemID = corpseItem.ID()
    local itemName     = corpseItem.Name()
    local itemLink     = corpseItem.ItemLink('CLICKABLE')()
    local isGlobalItem = loot.Settings.GlobalLootOn and (loot.GlobalItemsRules[corpseItemID] ~= nil or loot.BuyItemsTable[corpseItemID] ~= nil)

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
        return
    end

    local eval = doWhat
    if doWhat == 'Destroy' and mq.TLO.Cursor.ID() == corpseItemID then
        eval = isGlobalItem and 'Global Destroy' or 'Destroy'
        mq.cmdf('/destroy')
        table.insert(allItems,
            { Name = itemName, Action = 'Destroyed', Link = itemLink, Eval = eval, cantWear = cantWear, })
    end

    loot.checkCursor()

    -- Handle quest item logic
    if qKeep > 0 and doWhat == 'Keep' then
        eval            = isGlobalItem and 'Global Quest' or 'Quest'
        local countHave = mq.TLO.FindItemCount(itemName)() + mq.TLO.FindItemBankCount(itemName)()
        loot.report("\awQuest Item:\ag %s \awCount:\ao %s \awof\ag %s", itemLink, tostring(countHave), qKeep)
    else
        eval = isGlobalItem and 'Global ' .. doWhat or doWhat
        loot.report('%sing \ay%s\ax', doWhat, itemLink)
    end

    -- Log looted items
    if doWhat ~= 'Destroy' then
        if not string.find(eval, 'Quest') then
            eval = isGlobalItem and 'Global ' .. doWhat or doWhat
        end
        table.insert(allItems,
            { Name = itemName, Action = 'Looted', Link = itemLink, Eval = eval, cantWear = cantWear, })
    end

    loot.CheckBags()

    -- Check for full inventory
    if areFull == true then
        loot.report('My bags are full, I can\'t loot anymore! Turning OFF Looting Items until we sell.')
    end
end

function loot.reportSkippedItems(noDropItems, loreItems, corpseName, corpseID)
    -- Ensure parameters are valid
    noDropItems = noDropItems or {}
    loreItems   = loreItems or {}

    -- Log skipped items
    if next(noDropItems) then
        Logger.Info("Skipped NoDrop items from corpse %s (ID: %s): %s",
            corpseName, tostring(corpseID), table.concat(noDropItems, ", "))
    end

    if next(loreItems) then
        Logger.Info("Skipped Lore items from corpse %s (ID: %s): %s",
            corpseName, tostring(corpseID), table.concat(loreItems, ", "))
    end
end

function loot.lootCorpse(corpseID)
    Logger.Debug('Enter lootCorpse')
    shouldLootActions.Destroy = loot.Settings.DoDestroy
    shouldLootActions.Tribute = loot.Settings.TributeKeep

    local allItems = {}
    if mq.TLO.Cursor() then loot.checkCursor() end

    for i = 1, 3 do
        mq.cmdf('/loot')
        mq.delay(1000, function() return mq.TLO.Window('LootWnd').Open() end)
        if mq.TLO.Window('LootWnd').Open() then break end
    end

    mq.doevents('CantLoot')
    mq.delay(3000, function() return cantLootID > 0 or mq.TLO.Window('LootWnd').Open() end)

    if not mq.TLO.Window('LootWnd').Open() then
        if mq.TLO.Target.CleanName() then
            Logger.Warn("lootCorpse(): Can't loot %s right now", mq.TLO.Target.CleanName())
            cantLootList[corpseID] = os.time()
        end
        return
    end

    mq.delay(1000, function() return (mq.TLO.Corpse.Items() or 0) > 0 end)
    local items = mq.TLO.Corpse.Items() or 0
    Logger.Debug("lootCorpse(): Loot window open. Items: %s", items)

    local corpseName = mq.TLO.Corpse.Name()
    if mq.TLO.Window('LootWnd').Open() and items > 0 then
        if mq.TLO.Corpse.DisplayName() == mq.TLO.Me.DisplayName() then
            if loot.Settings.LootMyCorpse then
                mq.cmdf('/lootall')
                mq.delay("45s", function() return not mq.TLO.Window('LootWnd').Open() end)
            end
            return
        end

        local noDropItems, loreItems = {}, {}
        for i = 1, items do
            local freeSpace           = mq.TLO.Me.FreeInventory()
            local corpseItem          = mq.TLO.Corpse.Item(i)
            local lootActionPreformed = "Looted"
            if corpseItem() then
                local corpseItemID = corpseItem.ID()
                local itemLink     = corpseItem.ItemLink('CLICKABLE')()
                local isNoDrop     = corpseItem.NoDrop()
                local newNoDrop    = false
                if loot.ItemNames[corpseItemID] == nil then
                    loot.addToItemDB(corpseItem)
                    if isNoDrop then
                        loot.addRule(corpseItemID, 'NormalItems', 'CanUse', 'All', itemLink)
                        newNoDrop = true
                    end
                end
                local itemRule, qKeep, newRule, cantWear = loot.getRule(corpseItem, 'loot')

                Logger.Debug("LootCorpse(): itemID=\ao%s\ax, rule=\at%s\ax, qKeep=\ay%s\ax, newRule=\ag%s", corpseItemID, itemRule, qKeep, newRule)
                newRule         = newNoDrop == true and true or newRule

                local stackable = corpseItem.Stackable()
                local freeStack = corpseItem.FreeStack()
                local isLore    = corpseItem.Lore()

                if isLore then
                    local haveItem     = mq.TLO.FindItem(('=%s'):format(corpseItem.Name()))()
                    local haveItemBank = mq.TLO.FindItemBank(('=%s'):format(corpseItem.Name()))()
                    if haveItem or haveItemBank or freeSpace <= loot.Settings.SaveBagSlots then
                        table.insert(loreItems, itemLink)
                        loot.lootItem(i, 'Ignore', 'leftmouseup', 0, allItems)
                    elseif isNoDrop then
                        if loot.Settings.LootNoDrop then
                            if (not newRule or (newRule and loot.Settings.LootNoDropNew)) and not cantWear then
                                loot.lootItem(i, itemRule, 'leftmouseup', qKeep, allItems)
                            end
                        else
                            table.insert(noDropItems, itemLink)
                            loot.lootItem(i, 'Ignore', 'leftmouseup', 0, allItems)
                        end
                    else
                        loot.lootItem(i, itemRule, 'leftmouseup', qKeep, allItems)
                    end
                elseif isNoDrop then
                    if loot.Settings.LootNoDrop then
                        if (not newRule or (newRule and loot.Settings.LootNoDropNew)) and not cantWear then
                            loot.lootItem(i, itemRule, 'leftmouseup', qKeep, allItems)
                        end
                    else
                        table.insert(noDropItems, itemLink)
                        loot.lootItem(i, 'Ignore', 'leftmouseup', 0, allItems)
                    end
                elseif freeSpace > loot.Settings.SaveBagSlots or (stackable and freeStack > 0) then
                    loot.lootItem(i, itemRule, 'leftmouseup', qKeep, allItems)
                end

                if newRule then
                    -- if isNoDrop then itemRule = 'CanUse' end
                    loot.addNewItem(corpseItem, itemRule, itemLink, corpseID)
                end
            end

            mq.delay(1)
            if mq.TLO.Cursor() then loot.checkCursor() end
            mq.delay(1)
            if not mq.TLO.Window('LootWnd').Open() then break end
        end

        loot.reportSkippedItems(noDropItems, loreItems, corpseName, corpseID)
    end

    if mq.TLO.Cursor() then loot.checkCursor() end
    mq.cmdf('/nomodkey /notify LootWnd LW_DoneButton leftmouseup')
    mq.delay(3000, function() return not mq.TLO.Window('LootWnd').Open() end)

    if mq.TLO.Spawn(('corpse id %s'):format(corpseID))() then
        cantLootList[corpseID] = os.time()
    end

    if #allItems > 0 then
        loot.lootActor:send({ mailbox = 'looted', },
            { ID = corpseID, Items = allItems, Server = eqServer, LootedAt = mq.TLO.Time(), LootedBy = MyName, })
    end
end

function loot.corpseLocked(corpseID)
    if not cantLootList[corpseID] then return false end
    if os.difftime(os.time(), cantLootList[corpseID]) > 60 then
        cantLootList[corpseID] = nil
        return false
    end
    return true
end

function loot.lootMobs(limit)
    if zoneID ~= mq.TLO.Zone.ID() then
        zoneID        = mq.TLO.Zone.ID()
        lootedCorpses = {}
    end

    Logger.Debug('lootMobs(): Entering lootMobs function.')
    local deadCount  = mq.TLO.SpawnCount(string.format('npccorpse radius %s zradius 50', loot.Settings.CorpseRadius or 100))()
    local mobsNearby = mq.TLO.SpawnCount(string.format('xtarhater radius %s zradius 50', loot.Settings.MobsTooClose or 40))()
    local corpseList = {}

    Logger.Debug('lootMobs(): Found %s corpses in range.', deadCount)

    -- Handle looting of the player's own corpse
    local myCorpseCount = mq.TLO.SpawnCount(string.format("pccorpse %s radius %d zradius 100", mq.TLO.Me.CleanName(), loot.Settings.CorpseRadius))()

    if loot.Settings.LootMyCorpse and myCorpseCount > 0 then
        for i = 1, (limit or myCorpseCount) do
            local corpse = mq.TLO.NearestSpawn(string.format("%d, pccorpse %s radius %d zradius 100", i, mq.TLO.Me.CleanName(), loot.Settings.CorpseRadius))
            if corpse() then
                Logger.Debug('lootMobs(): Adding my corpse to loot list. Corpse ID: %d', corpse.ID())
                table.insert(corpseList, corpse)
            end
        end
    end

    -- Stop looting if conditions aren't met
    if (deadCount + myCorpseCount) == 0 or ((mobsNearby > 0 or mq.TLO.Me.Combat()) and not loot.Settings.CombatLooting) then
        return false
    end

    -- Add other corpses to the loot list if not limited by the player's own corpse
    if myCorpseCount == 0 then
        for i = 1, (limit or deadCount) do
            local corpse = mq.TLO.NearestSpawn(('%d,' .. spawnSearch):format(i, 'npccorpse', loot.Settings.CorpseRadius))
            if corpse() and (not lootedCorpses[corpse.ID()] or not loot.Settings.CheckCorpseOnce) then
                table.insert(corpseList, corpse)
            end
        end
    else
        Logger.Debug('lootMobs(): Skipping other corpses due to nearby player corpse.')
    end

    -- Process the collected corpse list
    local didLoot = false
    if #corpseList > 0 then
        Logger.Debug('lootMobs(): Attempting to loot %d corpses.', #corpseList)
        for _, corpse in ipairs(corpseList) do
            local corpseID = corpse.ID()

            if not corpseID or corpseID <= 0 or loot.corpseLocked(corpseID) or
                (mq.TLO.Navigation.PathLength('spawn id ' .. corpseID)() or 100) >= 60 then
                Logger.Debug('lootMobs(): Skipping corpse ID: %d.', corpseID)
                goto continue
            end

            -- Attempt to move and loot the corpse
            if corpse.DisplayName() == mq.TLO.Me.DisplayName() then
                Logger.Debug('lootMobs(): Pulling own corpse closer. Corpse ID: %d', corpseID)
                mq.cmdf("/corpse")
                mq.delay(10)
            end

            Logger.Debug('lootMobs(): Navigating to corpse ID=%d.', corpseID)
            loot.navToID(corpseID)

            if mobsNearby > 0 and not loot.Settings.CombatLooting then
                Logger.Debug('lootMobs(): Stopping looting due to aggro.')
                return didLoot
            end

            corpse.DoTarget()
            loot.lootCorpse(corpseID)
            didLoot                 = true
            lootedCorpses[corpseID] = true

            ::continue::
        end
        Logger.Debug('lootMobs(): Finished processing corpse list.')
    end

    return didLoot
end

-- SELLING
function loot.eventSell(_, itemName)
    if ProcessItemsState ~= nil then return end
    -- Resolve the item ID from the given name
    local itemID = loot.resolveItemIDbyName(itemName, false)

    if not itemID then
        Logger.Warn("Unable to resolve item ID for: " .. itemName)
        return
    end

    -- Add a rule to mark the item as "Sell"
    loot.addRule(itemID, "NormalItems", "Sell", "All", loot.ALLITEMS[itemID].Link)
    Logger.Info("Added rule: \ay%s\ax set to \agSell\ax.", itemName)
end

function loot.goToVendor()
    if not mq.TLO.Target() then
        Logger.Warn('Please target a vendor')
        return false
    end
    local vendorID = mq.TLO.Target.ID()
    if mq.TLO.Target.Distance() > 15 then
        loot.navToID(vendorID)
    end
    return true
end

function loot.openVendor()
    Logger.Debug('Opening merchant window')
    mq.cmdf('/nomodkey /click right target')
    mq.delay(1000, function() return mq.TLO.Window('MerchantWnd').Open() end)
    return mq.TLO.Window('MerchantWnd').Open()
end

function loot.SellToVendor(itemID, bag, slot, name)
    local itemName = loot.ALLITEMS[itemID] ~= nil and loot.ALLITEMS[itemID].Name or 'Unknown'
    if itemName == 'Unknown' and name ~= nil then itemName = name end
    if NEVER_SELL[itemName] then return end
    if mq.TLO.Window('MerchantWnd').Open() then
        Logger.Info('Selling item: %s', itemName)
        local notify = slot == nil or slot == -1
            and ('/itemnotify %s leftmouseup'):format(bag)
            or ('/itemnotify in pack%s %s leftmouseup'):format(bag, slot)
        mq.cmdf(notify)
        mq.delay(1000, function() return mq.TLO.Window('MerchantWnd/MW_SelectedItemLabel').Text() == itemName end)
        mq.cmdf('/nomodkey /shiftkey /notify merchantwnd MW_Sell_Button leftmouseup')
        mq.delay(1000, function() return mq.TLO.Window('MerchantWnd/MW_SelectedItemLabel').Text() == '' end)
    end
end

-- BANKING
function loot.openBanker()
    Logger.Debug('Opening bank window')
    mq.cmdf('/nomodkey /click right target')
    mq.delay(1000, function() return mq.TLO.Window('BigBankWnd').Open() end)
    return mq.TLO.Window('BigBankWnd').Open()
end

function loot.bankItem(itemID, bag, slot)
    local notify = slot == nil or slot == -1
        and ('/shift /itemnotify %s leftmouseup'):format(bag)
        or ('/shift /itemnotify in pack%s %s leftmouseup'):format(bag, slot)
    mq.cmdf(notify)
    mq.delay(10000, function() return mq.TLO.Cursor() end)
    mq.cmdf('/notify BigBankWnd BIGB_AutoButton leftmouseup')
    mq.delay(10000, function() return not mq.TLO.Cursor() end)
end

function loot.markTradeSkillAsBank()
    for i = 1, 10 do
        local bagSlot = mq.TLO.InvSlot('pack' .. i).Item
        if bagSlot.ID() and bagSlot.Tradeskills() then
            loot.NormalItemsRules[bagSlot.ID()] = 'Bank'
            loot.addRule(bagSlot.ID(), 'NormalItems', 'Bank', 'All', bagSlot.ItemLink('CLICKABLE')())
        end
    end
end

-- BUYING

function loot.RestockItems()
    local rowNum = 0
    for itemName, qty in pairs(loot.BuyItemsTable) do
        Logger.Info('Checking \ao%s \axfor \at%s \axto \agRestock', mq.TLO.Target.CleanName(), itemName)
        local tmpVal = tonumber(qty) or 0
        rowNum       = mq.TLO.Window("MerchantWnd/MW_ItemList").List(string.format("=%s", itemName), 2)() or 0
        mq.delay(20)
        local onHand = mq.TLO.FindItemCount(itemName)()
        local tmpQty = tmpVal - onHand
        if rowNum ~= 0 and tmpQty > 0 then
            Logger.Info("\ayRestocking \ax%s \aoHave\ax: \at%s\ax \agBuying\ax: \ay%s", itemName, onHand, tmpVal)
            mq.TLO.Window("MerchantWnd/MW_ItemList").Select(rowNum)()
            mq.delay(100)
            mq.TLO.Window("MerchantWnd/MW_Buy_Button").LeftMouseUp()
            mq.delay(500, function() return mq.TLO.Window("QuantityWnd").Open() end)
            mq.TLO.Window("QuantityWnd/QTYW_SliderInput").SetText(tostring(tmpQty))()
            mq.delay(100, function() return mq.TLO.Window("QuantityWnd/QTYW_SliderInput").Text() == tostring(tmpQty) end)
            Logger.Info("\agBuying\ay " .. tmpQty .. "\at " .. itemName)
            mq.TLO.Window("QuantityWnd/QTYW_Accept_Button").LeftMouseUp()
            mq.delay(100)
        end
        mq.delay(500, function() return mq.TLO.FindItemCount(itemName)() == qty end)
    end
    -- close window when done buying
    return mq.TLO.Window('MerchantWnd').DoClose()
end

-- TRIBUTEING

function loot.openTribMaster()
    Logger.Debug('Opening Tribute Window')
    mq.cmdf('/nomodkey /click right target')
    Logger.Debug('Waiting for Tribute Window to populate')
    mq.delay(1000, function() return mq.TLO.Window('TributeMasterWnd').Open() end)
    if not mq.TLO.Window('TributeMasterWnd').Open() then return false end
    return mq.TLO.Window('TributeMasterWnd').Open()
end

function loot.eventTribute(_, itemName)
    if ProcessItemsState ~= nil then return end

    -- Resolve the item ID from the given name
    local itemID = loot.resolveItemIDbyName(itemName)

    if not itemID then
        Logger.Warn("Unable to resolve item ID for: " .. itemName)
        return
    end

    -- Add a rule to mark the item as "Tribute"
    loot.addRule(itemID, "NormalItems", "Tribute", "All", loot.ALLITEMS[itemID].Link)
    Logger.Info("Added rule: \ay%s\ax set to \agTribute\ax.", itemName)
end

function loot.TributeToVendor(itemToTrib, bag, slot)
    if NEVER_SELL[itemToTrib.Name()] then return end
    if mq.TLO.Window('TributeMasterWnd').Open() then
        Logger.Info('Tributeing ' .. itemToTrib.Name())
        loot.report('\ayTributing \at%s \axfor\ag %s \axpoints!', itemToTrib.Name(), itemToTrib.Tribute())
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

function loot.DestroyItem(itemToDestroy, bag, slot)
    if itemToDestroy == nil then return end
    if NEVER_SELL[itemToDestroy.Name()] then return end
    Logger.Info('!!Destroying!! ' .. itemToDestroy.Name())
    mq.cmdf('/shift /itemnotify in pack%s %s leftmouseup', bag, slot)
    mq.delay(1) -- progress frame
    mq.cmdf('/destroy')
    mq.delay(1)
    mq.delay(1000, function() return not mq.TLO.Cursor() end)
    mq.delay(1)
end

-- FORAGING

function loot.eventForage()
    if not loot.Settings.LootForage then return end
    Logger.Debug('Enter eventForage')
    -- allow time for item to be on cursor incase message is faster or something?
    mq.delay(1000, function() return mq.TLO.Cursor() end)
    -- there may be more than one item on cursor so go until its cleared
    while mq.TLO.Cursor() do
        local cursorItem        = mq.TLO.Cursor
        local foragedItem       = cursorItem.Name()
        local forageRule        = loot.split(loot.getRule(cursorItem, 'forage'))
        local ruleAction        = forageRule[1] -- what to do with the item
        local ruleAmount        = forageRule[2] -- how many of the item should be kept
        local currentItemAmount = mq.TLO.FindItemCount('=' .. foragedItem)()
        -- >= because .. does finditemcount not count the item on the cursor?
        if not shouldLootActions[ruleAction] or (ruleAction == 'Quest' and currentItemAmount >= ruleAmount) then
            if mq.TLO.Cursor.Name() == foragedItem then
                if loot.Settings.LootForageSpam then Logger.Info('Destroying foraged item ' .. foragedItem) end
                mq.cmdf('/destroy')
                mq.delay(500)
            end
            -- will a lore item we already have even show up on cursor?
            -- free inventory check won't cover an item too big for any container so may need some extra check related to that?
        elseif (shouldLootActions[ruleAction] or currentItemAmount < ruleAmount) and (not cursorItem.Lore() or currentItemAmount == 0) and (mq.TLO.Me.FreeInventory() or (cursorItem.Stackable() and cursorItem.FreeStack())) then
            if loot.Settings.LootForageSpam then Logger.Info('Keeping foraged item ' .. foragedItem) end
            mq.cmdf('/autoinv')
        else
            if loot.Settings.LootForageSpam then Logger.Warn('Unable to process item ' .. foragedItem) end
            break
        end
        mq.delay(50)
    end
end

-- Process Items

function loot.processItems(action)
    local flag        = false
    local totalPlat   = 0
    ProcessItemsState = action
    -- Helper function to process individual items based on action
    local function processItem(item, action, bag, slot)
        if not item or not item.ID() then return end
        local itemID = item.ID()
        local rule   = loot.GlobalItemsRules[itemID] and loot.GlobalItemsRules[itemID] or loot.NormalItemsRules[itemID]

        if rule == action then
            if action == 'Sell' then
                if not mq.TLO.Window('MerchantWnd').Open() then
                    if not loot.goToVendor() or not loot.openVendor() then return end
                end
                local sellPrice = item.Value() and item.Value() / 1000 or 0
                if sellPrice == 0 then
                    Logger.Warn('Item \ay%s\ax is set to Sell but has no sell value!', item.Name())
                else
                    loot.SellToVendor(itemID, bag, slot, item.Name())
                    -- loot.SellToVendor(item.Name(), bag, slot, item.ItemLink('CLICKABLE')() or "NULL")
                    totalPlat = totalPlat + sellPrice
                    mq.delay(1)
                end
            elseif action == 'Tribute' then
                if not mq.TLO.Window('TributeMasterWnd').Open() then
                    if not loot.goToVendor() or not loot.openTribMaster() then return end
                end
                mq.cmdf('/keypress OPEN_INV_BAGS')
                mq.delay(1000, loot.AreBagsOpen)
                loot.TributeToVendor(item, bag, slot)
            elseif action == 'Destroy' then
                loot.TempSettings.NeedDestroy = { item = item, container = bag, slot = slot, }
                -- loot.DestroyItem(item, bag, slot)
            elseif action == 'Bank' then
                if not mq.TLO.Window('BigBankWnd').Open() then
                    if not loot.goToVendor() or not loot.openBanker() then return end
                end
                loot.bankItem(item.Name(), bag, slot)
            end
        end
    end

    -- Temporarily disable AlwaysEval during processing
    if loot.Settings.AlwaysEval then
        flag, loot.Settings.AlwaysEval = true, false
    end

    -- Iterate through bags and process items

    for i = 1, 10 do
        local bagSlot       = mq.TLO.InvSlot('pack' .. i).Item
        local containerSize = bagSlot.Container()

        if containerSize then
            for j = 1, containerSize do
                local item = bagSlot.Item(j)
                if item and item.ID() then
                    processItem(item, action, i, j)
                end
            end
        end
    end

    -- Handle restocking if AutoRestock is enabled
    if action == 'Sell' and loot.Settings.AutoRestock then
        loot.RestockItems()
    end

    -- Handle buying items
    if action == 'Buy' then
        if not mq.TLO.Window('MerchantWnd').Open() then
            if not loot.goToVendor() or not loot.openVendor() then return end
        end
        loot.RestockItems()
    end

    -- Restore AlwaysEval state if it was modified
    if flag then
        flag, loot.Settings.AlwaysEval = false, true
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
        totalPlat = math.floor(totalPlat)
        loot.report('Total plat value sold: \ag%s\ax', totalPlat)
    elseif action == 'Bank' then
        if mq.TLO.Window('BigBankWnd').Open() then
            mq.TLO.Window('BigBankWnd').DoClose()
        end
    end

    -- Final check for bag status
    loot.CheckBags()
    ProcessItemsState = nil
end

function loot.sellStuff()
    loot.processItems('Sell')
end

function loot.bankStuff()
    loot.processItems('Bank')
end

function loot.cleanupBags()
    loot.processItems('Destroy')
end

function loot.tributeStuff()
    loot.processItems('Tribute')
end

function loot.guiExport()
    -- Define a new menu element function
    local function customMenu()
        ImGui.PushID('LootNScootMenu_Imported')
        if ImGui.BeginMenu('Loot N Scoot##') then
            -- Add menu items here
            if ImGui.BeginMenu('Toggles') then
                -- Add menu items here
                _, loot.Settings.DoLoot = ImGui.MenuItem("DoLoot", nil, loot.Settings.DoLoot)
                if _ then loot.writeSettings() end
                _, loot.Settings.GlobalLootOn = ImGui.MenuItem("GlobalLootOn", nil, loot.Settings.GlobalLootOn)
                if _ then loot.writeSettings() end
                _, loot.Settings.CombatLooting = ImGui.MenuItem("CombatLooting", nil, loot.Settings.CombatLooting)
                if _ then loot.writeSettings() end
                _, loot.Settings.LootNoDrop = ImGui.MenuItem("LootNoDrop", nil, loot.Settings.LootNoDrop)
                if _ then loot.writeSettings() end
                _, loot.Settings.LootNoDropNew = ImGui.MenuItem("LootNoDropNew", nil, loot.Settings.LootNoDropNew)
                if _ then loot.writeSettings() end
                _, loot.Settings.LootForage = ImGui.MenuItem("LootForage", nil, loot.Settings.LootForage)
                if _ then loot.writeSettings() end
                _, loot.Settings.LootQuest = ImGui.MenuItem("LootQuest", nil, loot.Settings.LootQuest)
                if _ then loot.writeSettings() end
                _, loot.Settings.TributeKeep = ImGui.MenuItem("TributeKeep", nil, loot.Settings.TributeKeep)
                if _ then loot.writeSettings() end
                _, loot.Settings.BankTradeskills = ImGui.MenuItem("BankTradeskills", nil, loot.Settings.BankTradeskills)
                if _ then loot.writeSettings() end
                _, loot.Settings.StackableOnly = ImGui.MenuItem("StackableOnly", nil, loot.Settings.StackableOnly)
                if _ then loot.writeSettings() end
                ImGui.Separator()
                _, loot.Settings.AlwaysEval = ImGui.MenuItem("AlwaysEval", nil, loot.Settings.AlwaysEval)
                if _ then loot.writeSettings() end
                _, loot.Settings.AddNewSales = ImGui.MenuItem("AddNewSales", nil, loot.Settings.AddNewSales)
                if _ then loot.writeSettings() end
                _, loot.Settings.AddNewTributes = ImGui.MenuItem("AddNewTributes", nil, loot.Settings.AddNewTributes)
                if _ then loot.writeSettings() end
                _, loot.Settings.AutoTag = ImGui.MenuItem("AutoTagSell", nil, loot.Settings.AutoTag)
                if _ then loot.writeSettings() end
                _, loot.Settings.AutoRestock = ImGui.MenuItem("AutoRestock", nil, loot.Settings.AutoRestock)
                if _ then loot.writeSettings() end
                ImGui.Separator()
                _, loot.Settings.DoDestroy = ImGui.MenuItem("DoDestroy", nil, loot.Settings.DoDestroy)
                if _ then loot.writeSettings() end
                _, loot.Settings.AlwaysDestroy = ImGui.MenuItem("AlwaysDestroy", nil, loot.Settings.AlwaysDestroy)
                if _ then loot.writeSettings() end

                ImGui.EndMenu()
            end

            if ImGui.BeginMenu('Group Commands##') then
                -- Add menu items here
                if ImGui.MenuItem("Sell Stuff##group") then
                    mq.cmdf(string.format('/%s /lootutils sellstuff', tmpCmd))
                end

                if ImGui.MenuItem('Restock Items##group') then
                    mq.cmdf(string.format('/%s /lootutils restock', tmpCmd))
                end

                if ImGui.MenuItem("Tribute Stuff##group") then
                    mq.cmdf(string.format('/%s /lootutils tributestuff', tmpCmd))
                end

                if ImGui.MenuItem("Bank##group") then
                    mq.cmdf(string.format('/%s /lootutils bank', tmpCmd))
                end

                if ImGui.MenuItem("Cleanup##group") then
                    mq.cmdf(string.format('/%s /lootutils cleanup', tmpCmd))
                end

                ImGui.Separator()

                if ImGui.MenuItem("Reload##group") then
                    mq.cmdf(string.format('/%s /lootutils reload', tmpCmd))
                end

                ImGui.EndMenu()
            end

            if ImGui.MenuItem('Sell Stuff##') then
                mq.cmdf('/lootutils sellstuff')
            end

            if ImGui.MenuItem('Restock##') then
                mq.cmdf('/lootutils restock')
            end

            if ImGui.MenuItem('Tribute Stuff##') then
                mq.cmdf('/lootutils tributestuff')
            end

            if ImGui.MenuItem('Bank##') then
                mq.cmdf('/lootutils bank')
            end

            if ImGui.MenuItem('Cleanup##') then
                mq.cmdf('/lootutils cleanup')
            end

            ImGui.Separator()

            if ImGui.MenuItem('Reload##') then
                mq.cmdf('/lootutils reload')
            end

            ImGui.EndMenu()
        end
        ImGui.PopID()
    end
    -- Add the custom menu element function to the importGUIElements table
    if loot.guiLoot ~= nil then loot.guiLoot.importGUIElements[1] = customMenu end
end

function loot.handleSelectedItem(itemID)
    -- Process the selected item (e.g., add to a rule, perform an action, etc.)
    local itemData = loot.ALLITEMS[itemID]
    if not itemData then
        Logger.Error("Invalid item selected: " .. tostring(itemID))
        return
    end

    Logger.Info("Item selected: " .. itemData.Name .. " (ID: " .. itemID .. ")")
    -- You can now use itemID for further actions
end

function loot.drawYesNo(decision)
    if decision then
        loot.drawIcon(4494, 20) -- Checkmark icon
    else
        loot.drawIcon(4495, 20) -- X icon
    end
end

function loot.SearchLootTable(search, key, value)
    if key == nil or value == nil then return false end
    search = search and search:gsub("[%^%$%(%)%%%.%[%]%*%+%-%?]", "%%%1") or ""
    if (search == nil or search == "") or key:lower():find(search:lower()) or value:lower():find(search:lower()) then
        return true
    else
        return false
    end
end

local fontScale = 1
local iconSize = 16
local tempValues = {}

function loot.SortItemTables()
    loot.TempSettings.SortedGlobalItemKeys = {}
    loot.TempSettings.SortedBuyItemKeys    = {}
    loot.TempSettings.SortedNormalItemKeys = {}
    loot.TempSettings.SortedSettingsKeys   = {}

    for k in pairs(loot.GlobalItemsRules) do
        table.insert(loot.TempSettings.SortedGlobalItemKeys, k)
    end
    table.sort(loot.TempSettings.SortedGlobalItemKeys, function(a, b) return a < b end)

    for k in pairs(loot.BuyItemsTable) do
        table.insert(loot.TempSettings.SortedBuyItemKeys, k)
    end
    table.sort(loot.TempSettings.SortedBuyItemKeys, function(a, b) return a < b end)

    for k in pairs(loot.NormalItemsRules) do
        table.insert(loot.TempSettings.SortedNormalItemKeys, k)
    end

    table.sort(loot.TempSettings.SortedNormalItemKeys, function(a, b) return a < b end)

    for k in pairs(loot.Settings) do
        if settingsNoDraw[k] == nil then
            table.insert(loot.TempSettings.SortedSettingsKeys, k)
        end
    end
    table.sort(loot.TempSettings.SortedSettingsKeys, function(a, b) return a < b end)
end

function loot.RenderModifyItemWindow()
    if not loot.TempSettings.ModifyItemRule then
        Logger.Error("Item not found in ALLITEMS %s %s", loot.TempSettings.ModifyItemID, loot.TempSettings.ModifyItemTable)
        loot.TempSettings.ModifyItemRule = false
        loot.TempSettings.ModifyItemID = nil
        tempValues = {}
        return
    end

    local classes = loot.TempSettings.ModifyClasses
    local rule = loot.TempSettings.ModifyItemSetting
    local colCount, styCount = loot.guiLoot.DrawTheme()

    ImGui.SetNextWindowSizeConstraints(ImVec2(300, 200), ImVec2(-1, -1))
    local open, show = ImGui.Begin("Modify Item", nil, ImGuiWindowFlags.AlwaysAutoResize)
    if show then
        local tableList = {
            "Global_Items", "Normal_Items",
        }
        local item      = loot.ALLITEMS[loot.TempSettings.ModifyItemID]
        if not item then
            item = {
                Name = loot.TempSettings.ModifyItemName,
                Link = loot.TempSettings.ModifyItemLink,
                RaceList = loot.TempSettings.ModifyItemRaceList,
            }
        end
        local questRule = "Quest"
        if item == nil then
            Logger.Error("Item not found in ALLITEMS %s %s", loot.TempSettings.ModifyItemID, loot.TempSettings.ModifyItemTable)
            ImGui.End()
            return
        end
        ImGui.TextUnformatted("Item:")
        ImGui.SameLine()
        ImGui.TextColored(ImVec4(0, 1, 1, 1), item.Name)
        ImGui.SameLine()
        ImGui.TextUnformatted("ID:")
        ImGui.SameLine()
        ImGui.TextColored(ImVec4(1, 1, 0, 1), "%s", loot.TempSettings.ModifyItemID)

        if ImGui.BeginCombo("Table", loot.TempSettings.ModifyItemTable) then
            for i, v in ipairs(tableList) do
                if ImGui.Selectable(v, loot.TempSettings.ModifyItemTable == v) then
                    loot.TempSettings.ModifyItemTable = v
                end
            end
            ImGui.EndCombo()
        end

        if tempValues.Classes == nil and classes ~= nil then
            tempValues.Classes = classes
        end

        ImGui.SetNextItemWidth(100)
        tempValues.Classes = ImGui.InputTextWithHint("Classes", "who can loot or all ex: shm clr dru", tempValues.Classes)

        ImGui.SameLine()
        loot.TempModClass = ImGui.Checkbox("All", loot.TempModClass)

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
            if tempValues.Classes == nil or tempValues.Classes == '' or loot.TempModClass then
                tempValues.Classes = "All"
            end
            -- loot.modifyItemRule(loot.TempSettings.ModifyItemID, newRule, loot.TempSettings.ModifyItemTable, tempValues.Classes, item.Link)
            if loot.TempSettings.ModifyItemTable == "Global_Items" then
                loot.GlobalItemsRules[loot.TempSettings.ModifyItemID] = newRule
                loot.setGlobalItem(loot.TempSettings.ModifyItemID, newRule, tempValues.Classes, item.Link)
            else
                loot.NormalItemsRules[loot.TempSettings.ModifyItemID] = newRule
                loot.setNormalItem(loot.TempSettings.ModifyItemID, newRule, tempValues.Classes, item.Link)
            end
            -- loot.setNormalItem(loot.TempSettings.ModifyItemID, newRule,  tempValues.Classes, item.Link)
            loot.TempSettings.ModifyItemRule = false
            loot.TempSettings.ModifyItemID = nil
            loot.TempSettings.ModifyItemTable = nil
            loot.TempSettings.ModifyItemClasses = 'All'
            loot.TempSettings.ModifyItemName = nil
            loot.TempSettings.ModifyItemLink = nil
            loot.TempModClass = false
            if colCount > 0 then ImGui.PopStyleColor(colCount) end
            if styCount > 0 then ImGui.PopStyleVar(styCount) end

            ImGui.End()
            return
        end
        ImGui.SameLine()

        ImGui.PushStyleColor(ImGuiCol.Button, ImVec4(1.0, 0.4, 0.4, 0.4))
        if ImGui.Button(Icons.FA_TRASH) then
            if loot.TempSettings.ModifyItemTable == "Global_Items" then
                -- loot.GlobalItemsRules[loot.TempSettings.ModifyItemID] = nil
                loot.setGlobalItem(loot.TempSettings.ModifyItemID, 'delete', 'All', 'NULL')
            else
                loot.setNormalItem(loot.TempSettings.ModifyItemID, 'delete', 'All', 'NULL')
            end
            loot.TempSettings.ModifyItemRule = false
            loot.TempSettings.ModifyItemID = nil
            loot.TempSettings.ModifyItemTable = nil
            loot.TempSettings.ModifyItemClasses = 'All'
            ImGui.PopStyleColor()
            if colCount > 0 then ImGui.PopStyleColor(colCount) end
            if styCount > 0 then ImGui.PopStyleVar(styCount) end

            ImGui.End()
            return
        end
        ImGui.PopStyleColor()

        ImGui.SameLine()
        if ImGui.Button("Cancel") then
            loot.TempSettings.ModifyItemRule = false
            loot.TempSettings.ModifyItemID = nil
            loot.TempSettings.ModifyItemTable = nil
            loot.TempSettings.ModifyItemClasses = 'All'
            loot.TempSettings.ModifyItemName = nil
            loot.TempSettings.ModifyItemLink = nil
        end
    end
    if not open then
        loot.TempSettings.ModifyItemRule = false
        loot.TempSettings.ModifyItemID = nil
        loot.TempSettings.ModifyItemTable = nil
        loot.TempSettings.ModifyItemClasses = 'All'
        loot.TempSettings.ModifyItemName = nil
        loot.TempSettings.ModifyItemLink = nil
    end
    if colCount > 0 then ImGui.PopStyleColor(colCount) end
    if styCount > 0 then ImGui.PopStyleVar(styCount) end
    ImGui.End()
end

function loot.drawNewItemsTable()
    local itemsToRemove = {}
    if loot.NewItems == nil then showNewItem = false end
    if #loot.NewItems < 0 then
        showNewItem = false
        loot.NewItemsCount = 0
    end
    if loot.NewItemsCount > 0 then
        if ImGui.BeginTable('##newItemTable', 3, bit32.bor(
                ImGuiTableFlags.Borders, ImGuiTableFlags.ScrollX,
                -- ImGuiTableFlags.ScrollY, -- ImGuiTableFlags.Resizable,
                ImGuiTableFlags.Reorderable,
                ImGuiTableFlags.RowBg)) then
            -- Setup Table Columns
            ImGui.TableSetupColumn('Item', bit32.bor(ImGuiTableColumnFlags.WidthStretch), 130)
            ImGui.TableSetupColumn('Classes', ImGuiTableColumnFlags.NoResize, 150)
            ImGui.TableSetupColumn('Rule', bit32.bor(ImGuiTableColumnFlags.NoResize), 90)
            ImGui.TableHeadersRow()

            -- Iterate Over New Items
            for itemID, item in pairs(loot.NewItems) do
                -- Ensure tmpRules has a default value
                if itemID == nil or item == nil then
                    Logger.Error("Invalid item in NewItems table: %s", itemID)
                    loot.NewItemsCount = 0
                    break
                end
                ImGui.PushID(itemID)
                tmpRules[itemID] = tmpRules[itemID] or item.Rule or settingList[1]
                if loot.tempLootAll == nil then
                    loot.tempLootAll = {}
                end
                ImGui.TableNextRow()
                -- Item Name and Link
                ImGui.TableNextColumn()

                ImGui.Indent(2)

                loot.drawIcon(item.Icon, 20)
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
                loot.tempLootAll[itemID] = ImGui.Checkbox('All', loot.tempLootAll[itemID])

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
                    loot.drawYesNo(item.NoDrop)
                    ImGui.TableNextColumn()
                    loot.drawYesNo(item.Lore)
                    ImGui.TableNextColumn()
                    loot.drawYesNo(item.Aug)
                    ImGui.TableNextColumn()
                    loot.drawYesNo(item.Tradeskill)
                    ImGui.EndTable()
                end
                ImGui.Unindent(2)
                -- Rule
                ImGui.TableNextColumn()

                item.selectedIndex = item.selectedIndex or loot.getRuleIndex(item.Rule, settingList)

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
                ImGui.Spacing()

                ImGui.SetCursorPosX(ImGui.GetCursorPosX() + (ImGui.GetColumnWidth(-1) / 6))
                ImGui.PushStyleColor(ImGuiCol.Button, ImVec4(0.040, 0.294, 0.004, 1.000))
                if ImGui.Button('Save Rule') then
                    local classes = loot.tempLootAll[itemID] and "All" or tmpClasses[itemID]


                    loot.addRule(itemID, "NormalItems", tmpRules[itemID], classes, item.Link)
                    loot.enterNewItemRuleInfo({
                        ID = itemID,
                        ItemName = item.Name,
                        Rule = tmpRules[itemID],
                        Classes = classes,
                        Link = item.Link,
                        CorpseID = item.CorpseID,
                    })
                    table.insert(itemsToRemove, itemID)
                    Logger.Debug("\agSaving\ax --\ayNEW ITEM RULE\ax-- Item: \at%s \ax(ID:\ag %s\ax) with rule: \at%s\ax, classes: \at%s\ax, link: \at%s\ax",
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
        loot.NewItems[itemID]    = nil
        tmpClasses[itemID]       = nil
        tmpRules[itemID]         = nil
        tmpLinks[itemID]         = nil
        loot.tempLootAll[itemID] = nil
        -- loot.NewItemsCount       = loot.NewItemsCount - 1
    end

    -- Update New Items Count
    if loot.NewItemsCount < 0 then loot.NewItemsCount = 0 end
    if loot.NewItemsCount == 0 then showNewItem = false end
end

function loot.SafeText(write_value)
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

function loot.drawTable(label)
    local varSub = label .. 'Items'
    if ImGui.BeginTabItem(varSub .. "##") then
        if loot.TempSettings.varSub == nil then
            loot.TempSettings.varSub = {}
        end
        if loot.TempSettings[varSub .. 'Classes'] == nil then
            loot.TempSettings[varSub .. 'Classes'] = {}
        end
        local sizeX, _ = ImGui.GetContentRegionAvail()
        ImGui.PushStyleColor(ImGuiCol.ChildBg, ImVec4(0.0, 0.6, 0.0, 0.1))
        if ImGui.BeginChild("Add Rule Drop Area", ImVec2(sizeX, 40), ImGuiChildFlags.Border) then
            ImGui.TextDisabled("Drop Item Here to Add to a %s Rule", label)
            if ImGui.IsWindowHovered() and ImGui.IsMouseClicked(0) then
                if mq.TLO.Cursor() ~= nil then
                    local itemCursor = mq.TLO.Cursor
                    loot.addToItemDB(mq.TLO.Cursor)
                    loot.TempSettings.ModifyItemRule = true
                    loot.TempSettings.ModifyItemName = itemCursor.Name()
                    loot.TempSettings.ModifyItemLink = itemCursor.ItemLink('CLICKABLE')() or "NULL"
                    loot.TempSettings.ModifyItemID = itemCursor.ID()
                    loot.TempSettings.ModifyItemTable = label .. "_Items"
                    loot.TempSettings.ModifyClasses = loot.ALLITEMS[itemCursor.ID()].ClassList or "All"
                    loot.TempSettings.ModifyItemSetting = "Ask"
                    tempValues = {}
                    mq.cmdf("/autoinv")
                end
            end
        end
        ImGui.EndChild()
        ImGui.PopStyleColor()

        ImGui.PushID(varSub .. 'Search')
        ImGui.SetNextItemWidth(180)
        loot.TempSettings['Search' .. varSub] = ImGui.InputTextWithHint("Search", "Search by Name or Rule",
            loot.TempSettings['Search' .. varSub]) or nil
        ImGui.PopID()
        if ImGui.IsItemHovered() and mq.TLO.Cursor() then
            loot.TempSettings['Search' .. varSub] = mq.TLO.Cursor()
            mq.cmdf("/autoinv")
        end

        ImGui.SameLine()

        if ImGui.SmallButton(Icons.MD_DELETE_SWEEP) then
            loot.TempSettings['Search' .. varSub] = nil
        end
        if ImGui.IsItemHovered() then ImGui.SetTooltip("Clear Search") end

        local col = 3
        col = math.max(3, math.floor(ImGui.GetContentRegionAvail() / 140))
        local colCount = col + (col % 3)
        if colCount % 3 ~= 0 then
            if (colCount - 1) % 3 == 0 then
                colCount = colCount - 1
            else
                colCount = colCount - 2
            end
        end

        local filteredItems = {}
        local filteredItemKeys = {}
        for id, rule in pairs(loot[varSub .. 'Rules']) do
            if loot.SearchLootTable(loot.TempSettings['Search' .. varSub], loot.ItemNames[id], rule) then
                local iconID = 0
                local itemLink = ''
                if loot.ALLITEMS[id] then
                    iconID = loot.ALLITEMS[id].Icon or 0
                    itemLink = loot.ALLITEMS[id].Link or ''
                end
                if loot[varSub .. 'Link'][id] then
                    itemLink = loot[varSub .. 'Link'][id]
                end
                table.insert(filteredItems, {
                    id = id,
                    data = loot.ItemNames[id],
                    setting = loot[varSub .. 'Rules'][id],
                    icon = iconID,
                    link = itemLink,
                })
                table.insert(filteredItemKeys, loot.ItemNames[id])
            end
        end
        table.sort(filteredItems, function(a, b) return a.data < b.data end)

        local totalItems = #filteredItems
        local totalPages = math.ceil(totalItems / ITEMS_PER_PAGE)

        -- Clamp CurrentPage to valid range
        loot.CurrentPage = math.max(1, math.min(loot.CurrentPage, totalPages))

        -- Navigation buttons
        if ImGui.Button(Icons.FA_BACKWARD) then
            loot.CurrentPage = 1
        end
        ImGui.SameLine()
        if ImGui.ArrowButton("##Previous", ImGuiDir.Left) and loot.CurrentPage > 1 then
            loot.CurrentPage = loot.CurrentPage - 1
        end
        ImGui.SameLine()
        ImGui.Text(("Page %d of %d"):format(loot.CurrentPage, totalPages))
        ImGui.SameLine()
        if ImGui.ArrowButton("##Next", ImGuiDir.Right) and loot.CurrentPage < totalPages then
            loot.CurrentPage = loot.CurrentPage + 1
        end
        ImGui.SameLine()
        if ImGui.Button(Icons.FA_FORWARD) then
            loot.CurrentPage = totalPages
        end

        ImGui.SameLine()
        ImGui.SetNextItemWidth(80)
        if ImGui.BeginCombo("Max Items", tostring(ITEMS_PER_PAGE)) then
            for i = 25, 100, 25 do
                if ImGui.Selectable(tostring(i), ITEMS_PER_PAGE == i) then
                    ITEMS_PER_PAGE = i
                end
            end
            ImGui.EndCombo()
        end
        -- Calculate the range of items to display
        local startIndex = (loot.CurrentPage - 1) * ITEMS_PER_PAGE + 1
        local endIndex = math.min(startIndex + ITEMS_PER_PAGE - 1, totalItems)


        if ImGui.BeginTable(label .. " Items", colCount, bit32.bor(ImGuiTableFlags.Borders, ImGuiTableFlags.Resizable, ImGuiTableFlags.ScrollY), ImVec2(0.0, 0.0)) then
            ImGui.TableSetupScrollFreeze(colCount, 1)
            for i = 1, colCount / 3 do
                ImGui.TableSetupColumn("Item", ImGuiTableColumnFlags.WidthStretch)
                ImGui.TableSetupColumn("Rule", ImGuiTableColumnFlags.WidthFixed, 40)
                ImGui.TableSetupColumn('Classes', ImGuiTableColumnFlags.WidthFixed, 90)
            end
            ImGui.TableHeadersRow()

            if loot[label .. 'ItemsRules'] ~= nil then
                for i = startIndex, endIndex do
                    local itemID = filteredItems[i].id
                    local item = filteredItems[i].data
                    local setting = filteredItems[i].setting
                    local iconID = filteredItems[i].icon
                    local itemLink = filteredItems[i].link

                    ImGui.PushID(itemID)
                    local classes = loot.NormalItemsClasses[itemID] or "All"
                    local itemName = loot.ItemNames[itemID] or item.Name
                    if loot.SearchLootTable(loot.TempSettings['Search' .. varSub], item, setting) then
                        ImGui.TableNextColumn()
                        ImGui.Indent(2)
                        local btnColor, btnText = ImVec4(0.0, 0.6, 0.0, 0.4), Icons.FA_PENCIL
                        if loot.ALLITEMS[itemID] == nil then
                            btnColor, btnText = ImVec4(0.6, 0.0, 0.0, 0.4), Icons.MD_CLOSE
                        end
                        ImGui.PushStyleColor(ImGuiCol.Button, btnColor)
                        if ImGui.SmallButton(btnText) then
                            loot.TempSettings.ModifyItemRule = true
                            loot.TempSettings.ModifyItemName = itemName
                            loot.TempSettings.ModifyItemLink = itemLink
                            loot.TempSettings.ModifyItemID = itemID
                            loot.TempSettings.ModifyItemTable = label .. "_Items"
                            loot.TempSettings.ModifyClasses = classes
                            loot.TempSettings.ModifyItemSetting = setting
                            tempValues = {}
                        end
                        ImGui.PopStyleColor()

                        ImGui.SameLine()
                        if iconID then
                            loot.drawIcon(iconID, iconSize * fontScale) -- icon
                        else
                            loot.drawIcon(4493, iconSize * fontScale)   -- icon
                        end
                        if ImGui.IsItemHovered() and ImGui.IsMouseClicked(0) then
                            mq.cmdf('/executelink %s', itemLink)
                        end
                        ImGui.SameLine(0, 0)

                        ImGui.Text(itemName)
                        if ImGui.IsItemHovered() then
                            loot.DrawRuleToolTip(itemName, setting, classes:upper())

                            if ImGui.IsMouseClicked(1) and itemLink ~= nil then
                                mq.cmdf('/executelink %s', itemLink)
                            end
                        end
                        ImGui.Unindent(2)
                        ImGui.TableNextColumn()
                        ImGui.Indent(2)
                        loot.drawSettingIcon(setting)

                        if ImGui.IsItemHovered() then
                            loot.DrawRuleToolTip(itemName, setting, classes:upper())
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
                            loot.DrawRuleToolTip(itemName, setting, classes:upper())
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

function loot.drawItemsTables()
    if ImGui.CollapsingHeader("Items Tables") then
        ImGui.SetNextItemWidth(100)
        fontScale = ImGui.SliderFloat("Font Scale", fontScale, 1, 2)
        ImGui.SetWindowFontScale(fontScale)

        if ImGui.BeginTabBar("Items") then
            local col = math.max(2, math.floor(ImGui.GetContentRegionAvail() / 150))
            col = col + (col % 2)

            -- Buy Items
            if ImGui.BeginTabItem("Buy Items") then
                if loot.TempSettings.BuyItems == nil then
                    loot.TempSettings.BuyItems = {}
                end
                ImGui.Text("Delete the Item Name to remove it from the table")

                if ImGui.SmallButton("Save Changes##BuyItems") then
                    for k, v in pairs(loot.TempSettings.UpdatedBuyItems) do
                        if k ~= "" then
                            loot.BuyItemsTable[k] = v
                        end
                    end

                    for k in pairs(loot.TempSettings.DeletedBuyKeys) do
                        loot.BuyItemsTable[k] = nil
                    end

                    loot.TempSettings.UpdatedBuyItems = {}
                    loot.TempSettings.DeletedBuyKeys = {}

                    loot.TempSettings.NeedSave = true
                end

                ImGui.SeparatorText("Add New Item")
                if ImGui.BeginTable("AddItem", 2, ImGuiTableFlags.Borders) then
                    ImGui.TableSetupColumn("Item", ImGuiTableColumnFlags.WidthFixed, 280)
                    ImGui.TableSetupColumn("Qty", ImGuiTableColumnFlags.WidthFixed, 150)
                    ImGui.TableHeadersRow()
                    ImGui.TableNextColumn()

                    ImGui.SetNextItemWidth(150)
                    ImGui.PushID("NewBuyItem")
                    loot.TempSettings.NewBuyItem = ImGui.InputText("New Item##BuyItems", loot.TempSettings.NewBuyItem)
                    ImGui.PopID()
                    if ImGui.IsItemHovered() and mq.TLO.Cursor() ~= nil then
                        loot.TempSettings.NewBuyItem = mq.TLO.Cursor()
                        mq.cmdf("/autoinv")
                    end
                    ImGui.SameLine()
                    ImGui.PushStyleColor(ImGuiCol.Button, ImVec4(0.4, 1.0, 0.4, 0.4))
                    if ImGui.SmallButton(Icons.MD_ADD) then
                        loot.BuyItemsTable[loot.TempSettings.NewBuyItem] = loot.TempSettings.NewBuyQty
                        loot.setBuyItem(loot.TempSettings.NewBuyItem, loot.TempSettings.NewBuyQty)
                        loot.TempSettings.NeedSave = true
                        loot.TempSettings.NewBuyItem = ""
                        loot.TempSettings.NewBuyQty = 1
                    end
                    ImGui.PopStyleColor()

                    ImGui.SameLine()
                    ImGui.PushStyleColor(ImGuiCol.Button, ImVec4(1.0, 0.4, 0.4, 0.4))
                    if ImGui.SmallButton(Icons.MD_DELETE_SWEEP) then
                        loot.TempSettings.NewBuyItem = ""
                    end
                    ImGui.PopStyleColor()
                    ImGui.TableNextColumn()
                    ImGui.SetNextItemWidth(120)

                    loot.TempSettings.NewBuyQty = ImGui.InputInt("New Qty##BuyItems", (loot.TempSettings.NewBuyQty or 1),
                        1, 50)
                    if loot.TempSettings.NewBuyQty > 1000 then loot.TempSettings.NewBuyQty = 1000 end

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

                    if loot.BuyItemsTable ~= nil and loot.TempSettings.SortedBuyItemKeys ~= nil then
                        loot.TempSettings.UpdatedBuyItems = {}
                        loot.TempSettings.DeletedBuyKeys = {}

                        local numItems = #loot.TempSettings.SortedBuyItemKeys
                        local numRows = math.ceil(numItems / numDisplayColumns)

                        for row = 1, numRows do
                            for column = 0, numDisplayColumns - 1 do
                                local index = row + column * numRows
                                local k = loot.TempSettings.SortedBuyItemKeys[index]
                                if k then
                                    local v = loot.BuyItemsTable[k]

                                    loot.TempSettings.BuyItems[k] = loot.TempSettings.BuyItems[k] or
                                        { Key = k, Value = v, }

                                    ImGui.TableNextColumn()

                                    ImGui.SetNextItemWidth(ImGui.GetColumnWidth(-1))
                                    local newKey = ImGui.InputText("##Key" .. k, loot.TempSettings.BuyItems[k].Key)

                                    ImGui.TableNextColumn()
                                    ImGui.SetNextItemWidth(ImGui.GetColumnWidth(-1))
                                    local newValue = ImGui.InputText("##Value" .. k,
                                        loot.TempSettings.BuyItems[k].Value)

                                    if newValue ~= v and newKey == k then
                                        if newValue == "" then newValue = "NULL" end
                                        loot.TempSettings.UpdatedBuyItems[newKey] = newValue
                                    elseif newKey ~= "" and newKey ~= k then
                                        loot.TempSettings.DeletedBuyKeys[k] = true
                                        if newValue == "" then newValue = "NULL" end
                                        loot.TempSettings.UpdatedBuyItems[newKey] = newValue
                                    elseif newKey ~= k and newKey == "" then
                                        loot.TempSettings.DeletedBuyKeys[k] = true
                                    end

                                    loot.TempSettings.BuyItems[k].Key = newKey
                                    loot.TempSettings.BuyItems[k].Value = newValue
                                    -- end
                                end
                            end
                        end
                    end

                    ImGui.EndTable()
                end
                ImGui.EndTabItem()
            end

            -- Global Items

            loot.drawTable("Global")

            -- Normal Items
            loot.drawTable("Normal")

            if loot.ALLITEMS ~= nil then
                if ImGui.BeginTabItem("Item Lookup") then
                    ImGui.TextWrapped("This is a list of All Items you have Rules for, or have looked up this session from the Items DB")
                    ImGui.Spacing()
                    ImGui.Text("Import your inventory to the DB with /rgl importinv")
                    local sizeX, sizeY = ImGui.GetContentRegionAvail()
                    ImGui.PushStyleColor(ImGuiCol.ChildBg, ImVec4(0.0, 0.6, 0.0, 0.1))
                    if ImGui.BeginChild("Add Item Drop Area", ImVec2(sizeX, 40), ImGuiChildFlags.Border) then
                        ImGui.TextDisabled("Drop Item Here to Add to DB")
                        if ImGui.IsWindowHovered() and ImGui.IsMouseClicked(0) then
                            if mq.TLO.Cursor() ~= nil then
                                loot.addToItemDB(mq.TLO.Cursor)
                                Logger.Info("Added Item to DB: %s", mq.TLO.Cursor.Name())
                                mq.cmdf("/autoinv")
                            end
                        end
                    end
                    ImGui.EndChild()
                    ImGui.PopStyleColor()

                    -- search field
                    ImGui.PushID("DBLookupSearch")
                    ImGui.SetNextItemWidth(180)

                    loot.TempSettings.SearchItems = ImGui.InputTextWithHint("Search Items##AllItems", "Lookup Name or Filter Class",
                        loot.TempSettings.SearchItems) or nil
                    ImGui.PopID()
                    if ImGui.IsItemHovered() and mq.TLO.Cursor() then
                        loot.TempSettings.SearchItems = mq.TLO.Cursor.Name()
                        mq.cmdf("/autoinv")
                    end
                    ImGui.SameLine()

                    if ImGui.SmallButton(Icons.MD_DELETE_SWEEP) then
                        loot.TempSettings.SearchItems = nil
                    end
                    if ImGui.IsItemHovered() then ImGui.SetTooltip("Clear Search") end

                    ImGui.SameLine()

                    ImGui.PushStyleColor(ImGuiCol.Button, ImVec4(0.78, 0.20, 0.05, 0.6))
                    if ImGui.SmallButton("LookupItem##AllItems") then
                        loot.TempSettings.LookUpItem = true
                    end
                    ImGui.PopStyleColor()
                    if ImGui.IsItemHovered() then ImGui.SetTooltip("Lookup Item in DB") end

                    -- setup the filteredItems for sorting
                    local filteredItems = {}
                    for id, item in pairs(loot.ALLITEMS) do
                        if loot.SearchLootTable(loot.TempSettings.SearchItems, item.Name, item.ClassList) then
                            table.insert(filteredItems, { id = id, data = item, })
                        end
                    end
                    table.sort(filteredItems, function(a, b) return a.data.Name < b.data.Name end)
                    -- Calculate total pages
                    local totalItems = #filteredItems
                    local totalPages = math.ceil(totalItems / ITEMS_PER_PAGE)

                    -- Clamp CurrentPage to valid range
                    loot.CurrentPage = math.max(1, math.min(loot.CurrentPage, totalPages))

                    -- Navigation buttons
                    if ImGui.Button(Icons.FA_BACKWARD) then
                        loot.CurrentPage = 1
                    end
                    ImGui.SameLine()
                    if ImGui.ArrowButton("##Previous", ImGuiDir.Left) and loot.CurrentPage > 1 then
                        loot.CurrentPage = loot.CurrentPage - 1
                    end
                    ImGui.SameLine()
                    ImGui.Text(("Page %d of %d"):format(loot.CurrentPage, totalPages))
                    ImGui.SameLine()
                    if ImGui.ArrowButton("##Next", ImGuiDir.Right) and loot.CurrentPage < totalPages then
                        loot.CurrentPage = loot.CurrentPage + 1
                    end
                    ImGui.SameLine()
                    if ImGui.Button(Icons.FA_FORWARD) then
                        loot.CurrentPage = totalPages
                    end

                    ImGui.SameLine()
                    ImGui.SetNextItemWidth(80)
                    if ImGui.BeginCombo("Max Items", tostring(ITEMS_PER_PAGE)) then
                        for i = 25, 100, 25 do
                            if ImGui.Selectable(tostring(i), ITEMS_PER_PAGE == i) then
                                ITEMS_PER_PAGE = i
                            end
                        end
                        ImGui.EndCombo()
                    end

                    -- Calculate the range of items to display
                    local startIndex = (loot.CurrentPage - 1) * ITEMS_PER_PAGE + 1
                    local endIndex = math.min(startIndex + ITEMS_PER_PAGE - 1, totalItems)

                    -- Render the table
                    if ImGui.BeginTable("DB", 59, bit32.bor(ImGuiTableFlags.Borders,
                            ImGuiTableFlags.Hideable, ImGuiTableFlags.Resizable, ImGuiTableFlags.ScrollX, ImGuiTableFlags.ScrollY, ImGuiTableFlags.Reorderable)) then
                        -- Set up column headers
                        for idx, label in pairs(loot.AllItemColumnListIndex) do
                            if label == 'name' then
                                ImGui.TableSetupColumn(label, ImGuiTableColumnFlags.NoHide)
                            else
                                ImGui.TableSetupColumn(label, ImGuiTableColumnFlags.DefaultHide)
                            end
                        end
                        ImGui.TableSetupScrollFreeze(1, 1)
                        ImGui.TableHeadersRow()

                        -- Render only the current page's items
                        for i = startIndex, endIndex do
                            local id = filteredItems[i].id
                            local item = filteredItems[i].data

                            ImGui.PushID(id)

                            -- Render each column for the item
                            ImGui.TableNextColumn()
                            ImGui.Indent(2)
                            loot.drawIcon(item.Icon, iconSize * fontScale)
                            if ImGui.IsItemHovered() and ImGui.IsMouseClicked(0) then
                                mq.cmdf('/executelink %s', item.Link)
                            end
                            ImGui.SameLine()
                            if ImGui.Selectable(item.Name, false) then
                                loot.TempSettings.ModifyItemRule = true
                                loot.TempSettings.ModifyItemID = id
                                loot.TempSettings.ModifyClasses = item.ClassList
                                loot.TempSettings.ModifyItemRaceList = item.RaceList
                                tempValues = {}
                            end
                            if ImGui.IsItemHovered() and ImGui.IsMouseClicked(1) then
                                mq.cmdf('/executelink %s', item.Link)
                            end
                            ImGui.Unindent(2)
                            ImGui.TableNextColumn()
                            -- sell_value
                            if item.Value ~= '0 pp 0 gp 0 sp 0 cp' then
                                loot.SafeText(item.Value)
                            end
                            ImGui.TableNextColumn()
                            loot.SafeText(item.Tribute)     -- tribute_value
                            ImGui.TableNextColumn()
                            loot.SafeText(item.Stackable)   -- stackable
                            ImGui.TableNextColumn()
                            loot.SafeText(item.StackSize)   -- stack_size
                            ImGui.TableNextColumn()
                            loot.SafeText(item.NoDrop)      -- nodrop
                            ImGui.TableNextColumn()
                            loot.SafeText(item.NoTrade)     -- notrade
                            ImGui.TableNextColumn()
                            loot.SafeText(item.Tradeskills) -- tradeskill
                            ImGui.TableNextColumn()
                            loot.SafeText(item.Quest)       -- quest
                            ImGui.TableNextColumn()
                            loot.SafeText(item.Lore)        -- lore
                            ImGui.TableNextColumn()
                            loot.SafeText(item.Collectible) -- collectible
                            ImGui.TableNextColumn()
                            loot.SafeText(item.Augment)     -- augment
                            ImGui.TableNextColumn()
                            loot.SafeText(item.AugType)     -- augtype
                            ImGui.TableNextColumn()
                            loot.SafeText(item.Clicky)      -- clickable
                            ImGui.TableNextColumn()
                            local tmpWeight = item.Weight ~= nil and item.Weight or 0
                            loot.SafeText(tmpWeight)      -- weight
                            ImGui.TableNextColumn()
                            loot.SafeText(item.AC)        -- ac
                            ImGui.TableNextColumn()
                            loot.SafeText(item.Damage)    -- damage
                            ImGui.TableNextColumn()
                            loot.SafeText(item.STR)       -- strength
                            ImGui.TableNextColumn()
                            loot.SafeText(item.DEX)       -- dexterity
                            ImGui.TableNextColumn()
                            loot.SafeText(item.AGI)       -- agility
                            ImGui.TableNextColumn()
                            loot.SafeText(item.STA)       -- stamina
                            ImGui.TableNextColumn()
                            loot.SafeText(item.INT)       -- intelligence
                            ImGui.TableNextColumn()
                            loot.SafeText(item.WIS)       -- wisdom
                            ImGui.TableNextColumn()
                            loot.SafeText(item.CHA)       -- charisma
                            ImGui.TableNextColumn()
                            loot.SafeText(item.HP)        -- hp
                            ImGui.TableNextColumn()
                            loot.SafeText(item.HPRegen)   -- regen_hp
                            ImGui.TableNextColumn()
                            loot.SafeText(item.Mana)      -- mana
                            ImGui.TableNextColumn()
                            loot.SafeText(item.ManaRegen) -- regen_mana
                            ImGui.TableNextColumn()
                            loot.SafeText(item.Haste)     -- haste
                            ImGui.TableNextColumn()
                            loot.SafeText(item.Classes)   -- classes
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
                            loot.SafeText(item.svFire)          -- svfire
                            ImGui.TableNextColumn()
                            loot.SafeText(item.svCold)          -- svcold
                            ImGui.TableNextColumn()
                            loot.SafeText(item.svDisease)       -- svdisease
                            ImGui.TableNextColumn()
                            loot.SafeText(item.svPoison)        -- svpoison
                            ImGui.TableNextColumn()
                            loot.SafeText(item.svCorruption)    -- svcorruption
                            ImGui.TableNextColumn()
                            loot.SafeText(item.svMagic)         -- svmagic
                            ImGui.TableNextColumn()
                            loot.SafeText(item.SpellDamage)     -- spelldamage
                            ImGui.TableNextColumn()
                            loot.SafeText(item.SpellShield)     -- spellshield
                            ImGui.TableNextColumn()
                            loot.SafeText(item.Size)            -- item_size
                            ImGui.TableNextColumn()
                            loot.SafeText(item.WeightReduction) -- weightreduction
                            ImGui.TableNextColumn()
                            loot.SafeText(item.Races)           -- races
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

                            loot.SafeText(item.Range)              -- item_range
                            ImGui.TableNextColumn()
                            loot.SafeText(item.Attack)             -- attack
                            ImGui.TableNextColumn()
                            loot.SafeText(item.StrikeThrough)      -- strikethrough
                            ImGui.TableNextColumn()
                            loot.SafeText(item.HeroicAGI)          -- heroicagi
                            ImGui.TableNextColumn()
                            loot.SafeText(item.HeroicCHA)          -- heroiccha
                            ImGui.TableNextColumn()
                            loot.SafeText(item.HeroicDEX)          -- heroicdex
                            ImGui.TableNextColumn()
                            loot.SafeText(item.HeroicINT)          -- heroicint
                            ImGui.TableNextColumn()
                            loot.SafeText(item.HeroicSTA)          -- heroicsta
                            ImGui.TableNextColumn()
                            loot.SafeText(item.HeroicSTR)          -- heroicstr
                            ImGui.TableNextColumn()
                            loot.SafeText(item.HeroicSvCold)       -- heroicsvcold
                            ImGui.TableNextColumn()
                            loot.SafeText(item.HeroicSvCorruption) -- heroicsvcorruption
                            ImGui.TableNextColumn()
                            loot.SafeText(item.HeroicSvDisease)    -- heroicsvdisease
                            ImGui.TableNextColumn()
                            loot.SafeText(item.HeroicSvFire)       -- heroicsvfire
                            ImGui.TableNextColumn()
                            loot.SafeText(item.HeroicSvMagic)      -- heroicsvmagic
                            ImGui.TableNextColumn()
                            loot.SafeText(item.HeroicSvPoison)     -- heroicsvpoison
                            ImGui.TableNextColumn()
                            loot.SafeText(item.HeroicWIS)          -- heroicwis

                            ImGui.PopID()
                        end
                        ImGui.EndTable()
                    end
                    ImGui.EndTabItem()
                end
            end
        end

        if loot.NewItems ~= nil and loot.NewItemsCount > 0 then
            if ImGui.BeginTabItem("New Items") then
                loot.drawNewItemsTable()
                ImGui.EndTabItem()
            end
        end
        ImGui.EndTabBar()
    end
end

function loot.DrawRuleToolTip(name, setting, classes)
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

function loot.drawSettingIcon(setting)
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

function loot.drawSwitch(settingName, who)
    if who == MyName then
        if loot.Settings[settingName] then
            ImGui.TextColored(0.3, 1.0, 0.3, 0.9, Icons.FA_TOGGLE_ON)
        else
            ImGui.TextColored(1.0, 0.3, 0.3, 0.8, Icons.FA_TOGGLE_OFF)
        end
        if ImGui.IsItemHovered() then
            ImGui.SetTooltip("%s %s", settingName, loot.Settings[settingName] and "Enabled" or "Disabled")
        end
        if ImGui.IsItemHovered() and ImGui.IsMouseClicked(0) then
            loot.Settings[settingName] = not loot.Settings[settingName]
            loot.TempSettings.NeedSave = true
        end
    else
        if loot.Boxes[who] ~= nil then
            if loot.Boxes[who][settingName] then
                ImGui.TextColored(0.3, 1.0, 0.3, 0.9, Icons.FA_TOGGLE_ON)
            else
                ImGui.TextColored(1.0, 0.3, 0.3, 0.8, Icons.FA_TOGGLE_OFF)
            end
            if ImGui.IsItemHovered() then
                ImGui.SetTooltip("%s %s", settingName, loot.Boxes[who][settingName] and "Enabled" or "Disabled")
            end
            if ImGui.IsItemHovered() and ImGui.IsMouseClicked(0) then
                loot.Boxes[who][settingName] = not loot.Boxes[who][settingName]
            end
        end
    end
end

loot.TempSettings.Edit = {}
function loot.renderSettingsSection(who)
    if who == nil then who = MyName end
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
    ImGui.SameLine()
    if ImGui.SmallButton("Send Settings##LootnScoot") then
        if who == MyName then
            for k, v in pairs(loot.Boxes[MyName]) do
                if type(v) == 'table' then
                    for k2, v2 in pairs(v) do
                        loot.Settings[k][k2] = v2
                    end
                else
                    loot.Settings[k] = v
                end
            end
            loot.writeSettings()
            loot.sendMySettings()
        else
            local tmpSet = {}
            for k, v in pairs(loot.Boxes[who]) do
                if type(v) == 'table' then
                    tmpSet[k] = {}
                    for k2, v2 in pairs(v) do
                        tmpSet[k][k2] = v2
                    end
                else
                    tmpSet[k] = v
                end
            end
            loot.lootActor:send({ mailbox = 'lootnscoot', }, {
                action = 'updatesettings',
                who = who,
                settings = tmpSet,
            })
        end
    end
    ImGui.SeparatorText("Clone Settings")
    ImGui.SetNextItemWidth(120)
    if ImGui.BeginCombo('Who to Clone', loot.TempSettings.CloneWho) then
        for k, v in pairs(loot.Boxes) do
            if ImGui.Selectable(k, loot.TempSettings.CloneWho == k) then
                loot.TempSettings.CloneWho = k
            end
        end
        ImGui.EndCombo()
    end
    ImGui.SameLine()
    ImGui.SetNextItemWidth(120)
    if ImGui.BeginCombo('Clone To', loot.TempSettings.CloneTo) then
        for k, v in pairs(loot.Boxes) do
            if ImGui.Selectable(k, loot.TempSettings.CloneTo == k) then
                loot.TempSettings.CloneTo = k
            end
        end
        ImGui.EndCombo()
    end
    ImGui.SameLine()
    if ImGui.SmallButton("Clone Settings") then
        loot.Boxes[loot.TempSettings.CloneTo] = {}
        for k, v in pairs(loot.Boxes[loot.TempSettings.CloneWho]) do
            if type(v) == 'table' then
                loot.Boxes[loot.TempSettings.CloneTo][k] = {}
                for k2, v2 in pairs(v) do
                    loot.Boxes[loot.TempSettings.CloneTo][k][k2] = v2
                end
            else
                loot.Boxes[loot.TempSettings.CloneTo][k] = v
            end
        end
        local tmpSet = {}
        for k, v in pairs(loot.Boxes[loot.TempSettings.CloneTo]) do
            if type(v) == 'table' then
                tmpSet[k] = {}
                for k2, v2 in pairs(v) do
                    tmpSet[k][k2] = v2
                end
            else
                tmpSet[k] = v
            end
        end
        loot.lootActor:send({ mailbox = 'lootnscoot', }, {
            action = 'updatesettings',
            who = loot.TempSettings.CloneTo,
            settings = tmpSet,
        })
        loot.TempSettings.CloneTo = nil
    end

    local sorted_names = loot.SortTableColums(loot.Boxes[who], loot.TempSettings.SortedSettingsKeys, colCount / 2)

    if ImGui.BeginTable("Settings##1", colCount, bit32.bor(ImGuiTableFlags.Borders, ImGuiTableFlags.Resizable, ImGuiTableFlags.ScrollY)) then
        ImGui.TableSetupScrollFreeze(colCount, 1)
        for i = 1, colCount / 2 do
            ImGui.TableSetupColumn("Setting", ImGuiTableColumnFlags.WidthStretch)
            ImGui.TableSetupColumn("Value", ImGuiTableColumnFlags.WidthFixed, 80)
        end
        ImGui.TableHeadersRow()

        for i, settingName in ipairs(sorted_names) do
            if settingsNoDraw[settingName] == nil or settingsNoDraw[settingName] == false then
                ImGui.TableNextColumn()
                ImGui.Indent(2)
                if ImGui.Selectable(settingName) then
                    if type(loot.Boxes[who][settingName]) == "boolean" then
                        loot.Boxes[who][settingName] = not loot.Boxes[who][settingName]
                        if who == MyName then
                            loot.Settings[settingName] = loot.Boxes[who][settingName]
                            loot.TempSettings.NeedSave = true
                        end
                    end
                end
                ImGui.Unindent(2)
                ImGui.TableNextColumn()

                if type(loot.Boxes[who][settingName]) == "boolean" then
                    local posX, posY = ImGui.GetCursorPos()
                    ImGui.SetCursorPosX(posX + (ImGui.GetColumnWidth(-1) / 2) - 5)
                    loot.drawSwitch(settingName, who)
                elseif type(loot.Boxes[who][settingName]) == "number" then
                    ImGui.SetNextItemWidth(ImGui.GetColumnWidth(-1))
                    loot.Boxes[who][settingName] = ImGui.InputInt("##" .. settingName, loot.Boxes[who][settingName])
                elseif type(loot.Boxes[who][settingName]) == "string" then
                    ImGui.SetNextItemWidth(ImGui.GetColumnWidth(-1))
                    loot.Boxes[who][settingName] = ImGui.InputText("##" .. settingName, loot.Boxes[who][settingName])
                end
            end
        end
        ImGui.EndTable()
    end
end

function loot.renderNewItem()
    if (loot.Settings.AutoShowNewItem and loot.NewItemsCount > 0) and showNewItem then
        local colCount, styCount = loot.guiLoot.DrawTheme()

        ImGui.SetNextWindowSize(600, 400, ImGuiCond.FirstUseEver)
        local open, show = ImGui.Begin('New Items', true)
        if not open then
            show = false
            showNewItem = false
        end
        if show then
            loot.drawNewItemsTable()
        end
        if colCount > 0 then ImGui.PopStyleColor(colCount) end
        if styCount > 0 then ImGui.PopStyleVar(styCount) end
        ImGui.End()
    end
end

local animMini       = mq.FindTextureAnimation("A_DragItem")
local EQ_ICON_OFFSET = 500


local function renderBtn()
    -- apply_style()
    local colCount, styCount = loot.guiLoot.DrawTheme()

    ImGui.PushStyleVar(ImGuiStyleVar.WindowPadding, ImVec2(9, 9))
    local openBtn, showBtn = ImGui.Begin(string.format("LootNScoot##Mini"), true,
        bit32.bor(ImGuiWindowFlags.AlwaysAutoResize, ImGuiWindowFlags.NoTitleBar, ImGuiWindowFlags.NoCollapse))
    if not openBtn then
        showBtn = false
    end

    if showBtn then
        animMini:SetTextureCell(644 - EQ_ICON_OFFSET)
        ImGui.DrawTextureAnimation(animMini, 34, 34, true)

        if ImGui.IsItemHovered() then
            ImGui.SetTooltip("Toggle LNS Window")
            if ImGui.IsMouseReleased(0) then
                loot.ShowUI = not loot.ShowUI
            end
        end
    end
    ImGui.PopStyleVar()
    if colCount > 0 then ImGui.PopStyleColor(colCount) end
    if styCount > 0 then ImGui.PopStyleVar(styCount) end
    ImGui.End()
end

function loot.RenderUIs()
    if loot.NewItemDecisions ~= nil then
        loot.enterNewItemRuleInfo(loot.NewItemDecisions)
        loot.NewItemDecisions = nil
    end
    if loot.TempSettings.ModifyItemRule then loot.RenderModifyItemWindow() end
    loot.renderNewItem()
    if loot.pendingItemData ~= nil then
        loot.processPendingItem()
    end
    loot.renderMainUI()
    renderBtn()
end

function loot.enterNewItemRuleInfo(data_table)
    if data_table == nil then
        if loot.NewItemDecisions == nil then return end
        data_table = loot.NewItemDecisions
    end

    if data_table.ID == nil then
        Logger.Error("loot.enterNewItemRuleInfo \arInvalid item \atID \axfor new item rule.")
        return
    end
    Logger.Debug(
        "\aoloot.enterNewItemRuleInfo() \axSending \agNewItem Data\ax message \aoMailbox\ax \atlootnscoot actor\ax: item\at %s \ax, ID\at %s \ax, rule\at %s\ax, classes\at %s\ax, link\at %s\ax, corpseID\at %s\ax",
        data_table.ItemName, data_table.ItemID, data_table.Rule, data_table.Classes, data_table.Link, data_table.CorpseID)

    local itemID     = data_table.ID
    local item       = data_table.ItemName
    local rule       = data_table.Rule
    local classes    = data_table.Classes
    local link       = data_table.Link
    local corpse     = data_table.CorpseID
    local modMessage = {
        who      = MyName,
        action   = 'modifyitem',
        section  = "NormalItems",
        item     = item,
        itemID   = itemID,
        rule     = rule,
        link     = link,
        classes  = classes,
        entered  = true,
        corpse   = corpse,
        noChange = false,
        Server   = eqServer,
    }
    if (classes == loot.NormalItemsClasses[itemID] and rule == loot.NormalItemsRules[itemID]) then
        modMessage.noChange = true

        Logger.Debug("\ayNo Changes Made to Item: \at%s \ax(ID:\ag %s\ax) with rule: \at%s\ax, classes: \at%s\ax",
            link, itemID, rule, classes)
    else
        Logger.Debug(
            "\aoloot.enterNewItemRuleInfo() \axSending \agENTERED ITEM\ax message \aoMailbox\ax \atlootnscoot actor\ax: item\at %s \ax, ID\at %s \ax, rule\at %s\ax, classes\at %s\ax, link\at %s\ax, corpseID\at %s\ax",
            item, itemID, rule, classes, link, corpse)
    end
    loot.lootActor:send({ mailbox = 'lootnscoot', }, modMessage)
end

local showSettings = false

function loot.renderMainUI()
    if loot.ShowUI then
        local colCount, styCount = loot.guiLoot.DrawTheme()
        ImGui.SetNextWindowSize(800, 600, ImGuiCond.FirstUseEver)
        local open, show = ImGui.Begin('LootnScoot', true)
        if not open then
            show = false
            loot.ShowUI = false
        end
        if show then
            ImGui.PushStyleColor(ImGuiCol.PopupBg, ImVec4(0.002, 0.009, 0.082, 0.991))
            if ImGui.SmallButton(string.format("%s Report", Icons.MD_INSERT_CHART)) then
                loot.guiLoot.GetSettings(loot.Settings.HideNames, loot.Settings.LookupLinks, loot.Settings.RecordData, true, loot.Settings.UseActors, 'lootnscoot', true)
            end
            if ImGui.IsItemHovered() then ImGui.SetTooltip("Show/Hide Report Window") end

            ImGui.SameLine()

            if ImGui.SmallButton(string.format("%s Console", Icons.FA_TERMINAL)) then
                loot.guiLoot.openGUI = not loot.guiLoot.openGUI
            end
            if ImGui.IsItemHovered() then ImGui.SetTooltip("Show/Hide Console Window") end

            ImGui.SameLine()

            local labelBtn = not showSettings and
                string.format("%s Settings", Icons.FA_COG) or string.format("%s   Items  ", Icons.FA_SHOPPING_BASKET)

            if ImGui.SmallButton(labelBtn) then
                showSettings = not showSettings
            end

            -- Settings Section
            if showSettings then
                if loot.TempSettings.SelectedActor == nil then
                    loot.TempSettings.SelectedActor = MyName
                end
                ImGui.Indent(2)
                ImGui.TextWrapped("You can change any setting by issuing `/lootutils set settingname value` use [on|off] for true false values.")
                ImGui.TextWrapped("You can also change settings for other characters by selecting them from the dropdown.")
                ImGui.Unindent(2)
                ImGui.Spacing()

                ImGui.Separator()
                ImGui.Spacing()
                ImGui.SetNextItemWidth(180)
                if ImGui.BeginCombo("Select Actor", loot.TempSettings.SelectedActor) then
                    for k, v in pairs(loot.Boxes) do
                        if ImGui.Selectable(k, loot.TempSettings.SelectedActor == k) then
                            loot.TempSettings.SelectedActor = k
                        end
                    end
                    ImGui.EndCombo()
                end
                loot.renderSettingsSection(loot.TempSettings.SelectedActor)
            else
                -- Items and Rules Section
                loot.drawItemsTables()
            end
            ImGui.PopStyleColor()
        end
        if colCount > 0 then
            ImGui.PopStyleColor(colCount)
        end
        if styCount > 0 then
            ImGui.PopStyleVar(styCount)
        end
        ImGui.End()
    end
end

function loot.processArgs(args)
    loot.Terminate = true
    local mercsRunnig = mq.TLO.Lua.Script('rgmercs').Status() == 'RUNNING' or false

    if #args == 1 then
        if args[1] == 'sellstuff' then
            if mercsRunnig then mq.cmd('/rgl pause') end
            loot.processItems('Sell')
            if mercsRunnig then mq.cmd('/rgl unpause') end
        elseif args[1] == 'tributestuff' then
            if mercsRunnig then mq.cmd('/rgl pause') end
            loot.processItems('Tribute')
            if mercsRunnig then mq.cmd('/rgl unpause') end
        elseif args[1] == 'cleanup' then
            if mercsRunnig then mq.cmd('/rgl pause') end
            loot.processItems('Cleanup')
            if mercsRunnig then mq.cmd('/rgl unpause') end
        elseif args[1] == 'once' then
            loot.lootMobs()
        elseif args[1] == 'standalone' then
            if loot.guiLoot ~= nil then
                loot.guiLoot.GetSettings(loot.Settings.HideNames, loot.Settings.LookupLinks, loot.Settings.RecordData, true, loot.Settings.UseActors, 'lootnscoot', false)
            end
            loot.Terminate = false
            loot.lootActor:send({ mailbox = 'lootnscoot', }, { action = 'Hello', Server = eqServer, who = MyName, })
        end
    end
end

function loot.init(args)
    local needsSave = false

    needsSave = loot.loadSettings(true)
    loot.SortItemTables()
    loot.RegisterActors()
    loot.CheckBags()
    loot.setupEvents()
    loot.setupBinds()
    zoneID = mq.TLO.Zone.ID()
    Logger.Debug("Loot::init() \aoSaveRequired: \at%s", needsSave and "TRUE" or "FALSE")
    loot.processArgs(args)
    loot.sendMySettings()
    mq.imgui.init('LootnScoot', loot.RenderUIs)
    if needsSave then loot.writeSettings() end
    return needsSave
end

if loot.guiLoot ~= nil then
    loot.guiLoot.GetSettings(loot.Settings.HideNames, loot.Settings.LookupLinks, loot.Settings.RecordData, true, loot.Settings.UseActors, 'lootnscoot', false)
    loot.guiLoot.init(true, true, 'lootnscoot')
    loot.guiExport()
end

loot.init({ ..., })

while not loot.Terminate do
    if mq.TLO.MacroQuest.GameState() ~= "INGAME" then loot.Terminate = true end -- exit sctipt if at char select.
    if loot.Settings.DoLoot then loot.lootMobs() end
    if doSell then
        loot.processItems('Sell')
        doSell = false
    end
    if doBuy then
        loot.processItems('Buy')
        doBuy = false
    end
    if doTribute then
        loot.processItems('Tribute')
        doTribute = false
    end

    mq.doevents()

    if loot.TempSettings.NeedSave then
        loot.writeSettings()
        loot.TempSettings.NeedSave = false
        loot.loadSettings()
        loot.sendMySettings()
        loot.SortItemTables()
    end

    if loot.TempSettings.LookUpItem then
        if loot.TempSettings.SearchItems ~= nil and loot.TempSettings.SearchItems ~= "" then
            loot.GetItemFromDB(loot.TempSettings.SearchItems, 0)
        end
        loot.TempSettings.LookUpItem = false
    end

    loot.NewItemsCount = loot.NewItemsCount <= 0 and 0 or loot.NewItemsCount

    if loot.NewItemsCount == 0 then
        showNewItem = false
    end

    if loot.TempSettings.NeedsDestroy ~= nil then
        local item = loot.TempSettings.NeedsDestroy.item
        local bag = loot.TempSettings.NeedsDestroy.bag
        local slot = loot.TempSettings.NeedsDestroy.slot
        loot.DestroyItem(item, bag, slot)
        loot.TempSettings.NeedsDestroy = nil
    end

    if loot.MyClass:lower() == 'brd' and loot.Settings.DoDestroy then
        loot.Settings.DoDestroy = false
        Logger.Warn("\aoBard \aoDetected\ax, \arDisabling\ax [\atDoDestroy\ax].")
    end
    mq.delay(1)
end

if loot.Terminate then
    mq.unbind("/lootutils")
    mq.unbind("/lns")
    mq.unbind("/looted")
end
return loot
