local mq                = require('mq')
local Files             = require('mq.Utils')
local SQLite3           = require 'lsqlite3'
local actors            = require('modules.actor')
local settings          = require('modules.settings')
local guiLoot           = require('modules.loot_hist')
local success, Logger   = pcall(require, 'lib.Write')
if not success then
    printf('\arERROR: Write.lua could not be loaded\n%s\ax', Logger)
    return
end

local LNS_DB = {_version = '0.1', PreparedStatements = {}}

-- paths
local resourceDir                       = mq.TLO.MacroQuest.Path('resources')() .. "/"
LNS_DB.RulesDB                          = string.format('%s/LootNScoot/%s/AdvLootRules.db', resourceDir, settings.EqServer)
LNS_DB.ItemsDB                          = string.format('%s/LootNScoot/%s/Items.db', resourceDir, settings.EqServer)
LNS_DB.HistoryDB                        = string.format('%s/LootNScoot/%s/LootHistory.db', resourceDir, settings.EqServer)

local LNS

function LNS_DB.SetLNS(_LNS)
    LNS = _LNS
end

function LNS_DB.OpenDB(db_name)
    local db = SQLite3.open(db_name)
    if not db then
        printf('Error: Failed to open %s database.', db_name)
        return
    end
    db:exec("PRAGMA journal_mode=WAL;")
    return db
end
local items_db = LNS_DB.OpenDB(LNS_DB.ItemsDB)
local history_db = LNS_DB.OpenDB(LNS_DB.HistoryDB)
local rules_db = LNS_DB.OpenDB(LNS_DB.RulesDB)

function LNS_DB.PrepareStatements()
    local function initPreparedStatement(key, db, sql)
        LNS_DB.PreparedStatements[key] = db:prepare(sql)
        if not LNS_DB.PreparedStatements[key] then
            Logger.Error(guiLoot.console, "\arFailed to prepare %s statement: \at%s", key, db:errmsg())
        end
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
    initPreparedStatement('ADD_ITEM_TO_DB', items_db, sql)
    initPreparedStatement('CHECK_HISTORY', history_db, [[
SELECT Date, TimeStamp FROM LootHistory
WHERE Item = ? AND CorpseName = ? AND Action = ? AND Date = ?
ORDER BY Date DESC, TimeStamp DESC LIMIT 1
]])
    initPreparedStatement('INSERT_HISTORY', history_db, [[
INSERT INTO LootHistory (Item, CorpseName, Action, Date, TimeStamp, Link, Looter, Zone)
VALUES (?, ?, ?, ?, ?, ?, ?, ?)
]])
    initPreparedStatement('INSERT_RULE_NORMAL', rules_db, [[
INSERT INTO Normal_Rules
(item_id, item_name, item_rule, item_rule_classes, item_link)
VALUES (?, ?, ?, ?, ?)
ON CONFLICT(item_id) DO UPDATE SET
item_name                                    = excluded.item_name,
item_rule                                    = excluded.item_rule,
item_rule_classes                                    = excluded.item_rule_classes,
item_link                                    = excluded.item_link
]])
    initPreparedStatement('INSERT_RULE_GLOBAL', rules_db, [[
INSERT INTO Global_Rules
(item_id, item_name, item_rule, item_rule_classes, item_link)
VALUES (?, ?, ?, ?, ?)
ON CONFLICT(item_id) DO UPDATE SET
item_name                                    = excluded.item_name,
item_rule                                    = excluded.item_rule,
item_rule_classes                                    = excluded.item_rule_classes,
item_link                                    = excluded.item_link
]])
    initPreparedStatement('INSERT_RULE_PERSONAL', rules_db, string.format([[
INSERT INTO %s
(item_id, item_name, item_rule, item_rule_classes, item_link)
VALUES (?, ?, ?, ?, ?)
ON CONFLICT(item_id) DO UPDATE SET
item_name                                    = excluded.item_name,
item_rule                                    = excluded.item_rule,
item_rule_classes                                    = excluded.item_rule_classes,
item_link                                    = excluded.item_link
]], settings.PersonalTableName))
    initPreparedStatement('CHECK_DB_PERSONAL', rules_db, string.format("SELECT item_rule, item_rule_classes, item_link FROM %s WHERE item_id = ?", settings.PersonalTableName))
    initPreparedStatement('CHECK_DB_NORMAL', rules_db, "SELECT item_rule, item_rule_classes, item_link FROM Normal_Rules WHERE item_id = ?")
    initPreparedStatement('CHECK_DB_GLOBAL', rules_db, "SELECT item_rule, item_rule_classes, item_link FROM Global_Rules WHERE item_id = ?")
end

--- HISTORY DB

function LNS_DB.LoadHistoricalData()
    local historicalDates = {}
    history_db:exec([[
BEGIN TRANSACTION;
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
COMMIT;
]])

    local stmt = history_db:prepare("SELECT DISTINCT Date FROM LootHistory ORDER BY Date DESC")

    for row in stmt:nrows() do
        table.insert(historicalDates, row.Date)
    end

    stmt:finalize()
    return historicalDates
end

function LNS_DB.LoadDateHistory(lookup_Date)
    local historyDataDate = {}
    local stmt = history_db:prepare("SELECT * FROM LootHistory WHERE Date = ?")
    if not stmt then
        printf("Error preparing statement for date history: %s", history_db:errmsg())
        return
    end
    stmt:bind_values(lookup_Date)
    for row in stmt:nrows() do
        table.insert(historyDataDate, row)
    end

    stmt:finalize()
    return historyDataDate
end

function LNS_DB.LoadItemHistory(lookup_name)
    local historyItemData = {}
    local stmt = history_db:prepare("SELECT * FROM LootHistory WHERE Item LIKE ?")
    if not stmt then
        printf("Error preparing statement for item history: %s", history_db:errmsg())
        return
    end
    stmt:bind_values(string.format("%%%s%%", lookup_name))

    for row in stmt:nrows() do
        table.insert(historyItemData, row)
    end

    stmt:finalize()
    return historyItemData
end

local function convertTimestamp(timeStr)
    local h, mi, s = timeStr:match("(%d+):(%d+):(%d+)")
    local hour = tonumber(h)
    local min = tonumber(mi)
    local sec = tonumber(s)
    local timeSeconds = (hour * 3600) + (min * 60) + sec
    return timeSeconds
end

function LNS_DB.CheckHistory(itemName, corpseName, action, date, timestamp)
    local tooSoon = false
    -- Convert current date+time to epoch
    local currentTime = convertTimestamp(timestamp)

    LNS_DB.PreparedStatements.CHECK_HISTORY:bind_values(itemName, corpseName, action, date)
    local res = LNS_DB.PreparedStatements.CHECK_HISTORY:step()
    if res == SQLite3.ROW then
        local lastTimestamp = LNS_DB.PreparedStatements.CHECK_HISTORY:get_value(1)
        local recoredTime = convertTimestamp(lastTimestamp)
        if (currentTime - recoredTime) <= 60 then
            tooSoon = true
        end
    end
    LNS_DB.PreparedStatements.CHECK_HISTORY:reset()
    return tooSoon
end

function LNS_DB.InsertHistory(itemName, corpseName, action, date, timestamp, link, looter, zone)
    LNS_DB.PreparedStatements.INSERT_HISTORY:bind_values(itemName, corpseName, action, date, timestamp, link, looter, zone)
    local res, err = LNS_DB.PreparedStatements.INSERT_HISTORY:step()
    if res ~= SQLite3.DONE then
        printf("Error inserting data: %s ", err)
    end
    LNS_DB.PreparedStatements.INSERT_HISTORY:reset()
end

--- ITEMS DB

function LNS_DB.SetupItemsTable()
    items_db:exec("BEGIN TRANSACTION")
    items_db:exec([[
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
    items_db:exec("CREATE INDEX IF NOT EXISTS idx_item_name ON Items (name);")
    items_db:exec("CREATE INDEX IF NOT EXISTS idx_item_id ON Items (item_id);")

    items_db:exec("COMMIT")
    items_db:exec("PRAGMA wal_checkpoint;")
end

function LNS_DB.LoadIcons()
    local itemIcons = {}
    local stmt = items_db:prepare("SELECT item_id, icon FROM Items")

    for row in stmt:nrows() do
        itemIcons[row.item_id] = row.icon
    end

    stmt:finalize()
    return itemIcons
end

function LNS_DB.GetItemFromDB(itemName, itemID, query)
    stmt = items_db:prepare(query)
    if not stmt then
        Logger.Error(guiLoot.console, "Failed to prepare SQL statement: %s", items_db:errmsg())
        return 0
    end
    Logger.Debug(guiLoot.console, "SQL Query: \ay%s\ax ", query)

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
            if settings.TempSettings.SearchResults == nil then
                settings.TempSettings.SearchResults = {}
            end
            table.insert(settings.TempSettings.SearchResults, { id = id, data = itemData, })
        end
    end
    Logger.Info(guiLoot.console, "loot.GetItemFromDB() \agFound \ay%d\ax items matching the query: \ay%s\ax", rowsFetched, query)
    stmt:finalize()
    return rowsFetched
end

function LNS_DB.AddItemToDB(itemID, itemName, value, itemIcon)
    items_db:exec("BEGIN TRANSACTION")
    local success, errmsg = pcall(function()
        LNS_DB.PreparedStatements.ADD_ITEM_TO_DB:bind_values(
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
        LNS_DB.PreparedStatements.ADD_ITEM_TO_DB:step()
    end)

    if not success then
        Logger.Error(guiLoot.console, "Error executing SQL statement: %s", errmsg)
    end

    LNS_DB.PreparedStatements.ADD_ITEM_TO_DB:reset()
    items_db:exec("COMMIT")
end

--- Resolve a set of item names to IDs, ignoring not unique matches.
--- @param namesTable table A set of item names as keys (e.g., {["Sword"]=true})
--- @return table A map of item names to item_id (only if exactly one match)
function LNS_DB.ResolveItemIDs(namesTable)
    local resolved = {}
    local seenCount = {}

    local stmt = items_db:prepare("SELECT item_id, name FROM Items")
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

    return resolved
end

function LNS_DB.FindItemInDB(query, param, maxResults)
    local counter = 0
    local retTable = {}
    if not items_db then return counter, retTable end

    local stmt = items_db:prepare(query)
    if not stmt then
        Logger.Error(guiLoot.console, "Failed to prepare SQL statement: %s", items_db:errmsg())
        return 0, {}
    end

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
    return counter, retTable
end

--- RULES DB

function LNS_DB.LoadRuleDB()
    -- Creating tables
    rules_db:exec(string.format([[
BEGIN TRANSACTION;
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
COMMIT;
PRAGMA wal_checkpoint;
]], settings.PersonalTableName))

    local function processRules(stmt, ruleTable, classTable, linkTable, missingItemTable, missingNames)
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

    for _, tbl in ipairs({ "Global_Rules", "Normal_Rules", settings.PersonalTableName, }) do
        local stmt = rules_db:prepare("SELECT * FROM " .. tbl)
        local lbl = tbl:gsub("_Rules", "")
        if tbl == settings.PersonalTableName then lbl = 'Personal' end
        if stmt then
            processRules(stmt, LNS[lbl .. "ItemsRules"], LNS[lbl .. "ItemsClasses"],
                LNS.ItemLinks, LNS[lbl .. 'ItemsMissing'], LNS[lbl .. 'MissingNames'])
            stmt:finalize()
        end
    end

    LNS.SafeZones = {}
    local sz_stmt = rules_db:prepare("SELECT * FROM SafeZones")
    for row in sz_stmt:nrows() do
        local zone = row.zone
        if zone then
            LNS.SafeZones[zone] = true
        end
    end
    sz_stmt:finalize()
end

---comment
---@param item_table table Index of ItemId's to set
---@param setting any Setting to set all items to
---@param classes any Classes to set all items to
---@param which_table string Which Rules table
---@param delete_items boolean Delete items from the table
function LNS_DB.BulkSet(item_table, setting, classes, which_table, delete_items)
    if item_table == nil or type(item_table) ~= "table" then return end
    if which_table == 'Personal_Rules' then which_table = settings.PersonalTableName end
    local localName = which_table == 'Normal_Rules' and 'NormalItems' or 'GlobalItems'
    localName = which_table == settings.PersonalTableName and 'PersonalItems' or localName

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
    local stmt = rules_db:prepare(qry)
    if not stmt then
        return
    end

    rules_db:exec("BEGIN TRANSACTION;")

    for itemID, data in pairs(item_table) do
        local itemName = LNS.ItemNames[itemID] or nil
        local itemLink = data.Link
        Logger.Debug(guiLoot.console, "\nQuery: %s\ayValues\ax: itemID (\at%s\ax) itemName (\ay%s\ax), setting (\at%s)", qry, itemID, itemName, item_table[itemID].Rule)

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

    stmt:finalize()
    rules_db:exec("COMMIT;")
    rules_db:exec("PRAGMA wal_checkpoint;")
    if localName ~= 'PersonalItems' then
        settings.TempSettings.NeedSave = true
        actors.Send({
            action = 'reloadrules',
            who = settings.MyName,
            Server = settings.EqServer,
            bulkLabel = localName,
            bulkRules = LNS[localName .. 'Rules'],
            bulkClasses = LNS[localName .. 'Classes'],
            bulkLink = LNS.ItemLinks,
        })
    end
    settings.TempSettings.BulkSet = {}
end

function LNS_DB.GetItemLink(itemID, link, which_table)
    local alreadyMatched = false
    local qry = string.format("SELECT item_link FROM %s WHERE item_id = ?", which_table)

    -- local qry = string.format([[UPDATE %s SET item_link = ? WHERE item_id = ?;]], which_table)
    local stmt = rules_db:prepare(qry)
    if not stmt then
        Logger.Error(guiLoot.console, "\arFailed to prepare SQL statement: %s", rules_db:errmsg())
        return false
    end
    stmt:bind_values(itemID)

    for row in stmt:nrows() do
        if row.item_link and row.item_link == link then
            alreadyMatched = true
        end
    end
    stmt:finalize()
    return alreadyMatched
end

function LNS_DB.UpdateRuleLink(itemID, link, which_table)
    local qry = string.format([[UPDATE %s SET item_link = ? WHERE item_id = ?;]], which_table)
    local stmt = rules_db:prepare(qry)
    if not stmt then
        return
    end
    stmt:bind_values(link, itemID)
    stmt:step()
    stmt:reset()
    stmt:finalize()

    LNS.ItemLinks[itemID] = link
    Logger.Debug(guiLoot.console, "\aoUpdated link for\ax\at %d\ax to %s", itemID, link)
end

function LNS_DB.CheckRulesDB(id, stmt)
    local found = false
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
    -- Reset the prepared statement
    stmt:reset()
    return found, rule, classes, returnLink
end

function LNS_DB.DeleteItemRule(action, tableName, itemName, itemID)
    local sql = string.format("DELETE FROM %s WHERE item_id = ?", tableName)
    local stmt = rules_db:prepare(sql)
    if not stmt then
        Logger.Warn(guiLoot.console, "Failed to prepare SQL statement for table: %s, item: %s (%s), rule: %s", tableName, itemName, itemID, action)
        return
    end
    stmt:bind_values(itemID)

    -- Execute the statement
    rules_db:exec("BEGIN TRANSACTION")
    local success, errmsg = pcall(function() stmt:step() end)
    if not success then
        Logger.Warn(guiLoot.console, "Failed to execute SQL statement for table %s. Error: %s", tableName, errmsg)
    else
        Logger.Debug(guiLoot.console, "SQL statement executed successfully for item %s in table %s.", itemName, tableName)
    end

    -- Finalize and close the database
    stmt:finalize()
    rules_db:exec("COMMIT")
    rules_db:exec("PRAGMA wal_checkpoint;")
    return success
end

function LNS_DB.UpsertItemRule(action, tableName, itemName, itemID, classes, link)
    local stmt
    -- UPSERT operation
    if tableName == 'Normal_Rules' then
        stmt = LNS_DB.PreparedStatements.INSERT_RULE_NORMAL
    elseif tableName == 'Global_Rules' then
        stmt = LNS_DB.PreparedStatements.INSERT_RULE_GLOBAL
    else
        stmt = LNS_DB.PreparedStatements.INSERT_RULE_PERSONAL
    end
    stmt:bind_values(itemID, itemName, action, classes, link)

    -- Execute the statement
    rules_db:exec("BEGIN TRANSACTION")
    local success, errmsg = pcall(function() stmt:step() end)
    if not success then
        Logger.Warn(guiLoot.console, "Failed to execute SQL statement for table %s. Error: %s", tableName, errmsg)
    else
        Logger.Debug(guiLoot.console, "SQL statement executed successfully for item %s in table %s.", itemName, tableName)
    end

    -- Finalize and close the database
    stmt:reset()
    rules_db:exec("COMMIT")
    rules_db:exec("PRAGMA wal_checkpoint;")
    return success
end

function LNS_DB.AddSafeZone(zoneName)
    local stmt = rules_db:prepare("INSERT OR IGNORE INTO SafeZones (zone) VALUES (?)")
    if not stmt then
        printf("Error preparing statement for safe zone: %s", rules_db:errmsg())
        return
    end
    stmt:bind_values(zoneName)
    rules_db:exec("BEGIN TRANSACTION")
    local res, err = stmt:step()
    if res ~= SQLite3.DONE then
        printf("Error inserting safe zone: %s ", err)
    end
    stmt:finalize()

    rules_db:exec("COMMIT")
    rules_db:exec("PRAGMA wal_checkpoint;")
    return true
end

function LNS_DB.RemoveSafeZone(zoneName)
    local stmt = rules_db:prepare("DELETE FROM SafeZones WHERE zone = ?")
    if not stmt then
        printf("Error preparing statement for safe zone: %s", rules_db:errmsg())
        return
    end
    stmt:bind_values(zoneName)
    rules_db:exec("BEGIN TRANSACTION")
    local res, err = stmt:step()
    if res ~= SQLite3.DONE then
        printf("Error deleting safe zone: %s ", err)
    end
    stmt:finalize()

    rules_db:exec("COMMIT")
    rules_db:exec("PRAGMA wal_checkpoint;")
    return true
end

function LNS_DB.GetLowestID(tableName)
    local query = string.format("SELECT MIN(item_id) as min_id FROM %s;", tableName)
    local stmt = rules_db:prepare(query)
    if not stmt then
        return -1
    end

    local result = 0
    for row in stmt:nrows() do
        result = tonumber(row.min_id or -1)
    end

    stmt:finalize()
    
    -- If the lowest ID is positive, we want to start assigning from -1
    if result > 0 then
        return -1
    end

    -- Otherwise, go one lower than the current lowest
    return result - 1
end

function LNS_DB.EnterNegIDRule(itemName, rule, classes, link, tableName)
    Logger.Info(guiLoot.console, "Entering rule for missing item \ay%s\ax", itemName)
    local newID = LNS_DB.GetLowestID(tableName) or -1
    Logger.Debug(guiLoot.console, "Assigned temporary ID \at%s\ax for missing item \ay%s\ax", newID, itemName)
    local qry = string.format([[
INSERT INTO %s (item_id, item_name, item_rule, item_rule_classes, item_link)
VALUES (?, ?, ?, ?, ?)
ON CONFLICT(item_id) DO UPDATE SET
item_name = excluded.item_name,
item_rule = excluded.item_rule,
item_rule_classes = excluded.item_rule_classes,
item_link = excluded.item_link
]], tableName)
    Logger.Info(guiLoot.console, "Query: %s", qry)
    local stmt = rules_db:prepare(qry)
    if not stmt then
        return nil
    end

    stmt:bind_values(newID, itemName, rule, classes, link)
    local result = stmt:step()
    stmt:finalize()

    return result == SQLite3.DONE
end

--- DB IMPORT


function LNS_DB.ImportOldRulesDB(path)
    if not Files.File.Exists(path) then
        Logger.Error(guiLoot.console, "loot.ImportOldRulesDB() \arFile not found: \at%s\ax", path)
        return
    end

    local db = SQLite3.open(path)
    if not db then
        Logger.Error(guiLoot.console, "loot.ImportOldRulesDB() \arFailed to open database: \at%s\ax", db)
        return
    end

    local tmpGlobalDB = {}
    local tmpNormalDB = {}
    local tmpNamesGlobal = {}
    local tmpNamesNormal = {}

    db:exec("PRAGMA journal_mode=WAL;")
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

    db:close()


    local nameSet = {}
    for _, v in pairs(tmpGlobalDB) do nameSet[v.item_name] = true end
    for _, v in pairs(tmpNormalDB) do nameSet[v.item_name] = true end

    -- Resolve IDs in one DB pass
    local resolvedNames = LNS_DB.ResolveItemIDs(nameSet)

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
    local qry = string.format([[
INSERT INTO Global_Rules (item_id, item_name, item_rule, item_rule_classes, item_link)
VALUES (?, ?, ?, ?, ?)
ON CONFLICT(item_id) DO UPDATE SET
item_name = excluded.item_name,
item_rule = excluded.item_rule,
item_rule_classes = excluded.item_rule_classes,
item_link = excluded.item_link
]])

    stmt = rules_db:prepare(qry)
    if not stmt then
        return
    end

    rules_db:exec("BEGIN TRANSACTION;")

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

    stmt = rules_db:prepare(qry)
    if not stmt then
        rules_db:exec("COMMIT;")
        rules_db:exec("PRAGMA wal_checkpoint;")
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
    rules_db:exec("COMMIT;")
    rules_db:exec("PRAGMA wal_checkpoint;")

    Logger.Info(guiLoot.console, "loot.ImportOldRulesDB() \agSuccessfully imported old rules from \at%s\ax", path)

    -- update our missing tables
    LNS.GlobalItemsMissing = tmpGlobalDB or {}
    LNS.NormalItemsMissing = tmpNormalDB or {}
    LNS.GlobalMissingNames = tmpNamesGlobal or {}
    LNS.NormalMissingNames = tmpNamesNormal or {}
end

return LNS_DB