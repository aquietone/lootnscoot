# Remove Normal_Rules - Merge into Global_Rules

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Eliminate the Normal_Rules table by migrating its data into Global_Rules, then removing all Normal_Rules references - leaving only Global and Personal rule tiers.

**Architecture:** Add a one-time SQL migration that copies Normal_Rules entries into Global_Rules (skipping duplicates where Global already has a rule for that item_id). Then systematically replace every `NormalItems`/`Normal_Rules`/`Normal` reference to use `GlobalItems`/`Global_Rules`/`Global` instead. Remove the `AlwaysGlobal` setting (now meaningless - everything IS global). Remove `setNormalItem()` function. Remove the Normal tab from the UI.

**Tech Stack:** Lua, SQLite3 (lsqlite3), MacroQuest ImGui

**No tests exist** - this project has no automated test system. Validation is manual in-game testing. Each task includes verification steps where applicable.

---

## File Map

| File                   | Action | Responsibility                                                                                                                                                                                                                                                                                                                                                   |
| ---------------------- | ------ | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `modules/db.lua`       | Modify | Add migration function, remove Normal prepared statements/table creation, update LoadRuleDB, update UpsertItemRule/GetItemLink/UpdateRuleLink/BulkSet/ImportOldRulesDB                                                                                                                                                                                           |
| `modules/settings.lua` | Modify | Remove `Normal_Rules` from TableListRules, remove `AlwaysGlobal` setting/tooltip/enum                                                                                                                                                                                                                                                                            |
| `init.lua`             | Modify | Remove NormalItems\* tables/variables, change all `'NormalItems'` to `'GlobalItems'`, change all `'Normal_Rules'` to `'Global_Rules'`, remove `setNormalItem()`, remove AlwaysGlobal conditionals, update lookupLootRule/addRule/modifyItemRule/addNewItem/EnterNegIDRule/enterNewItemRuleInfo/commandHandler/processItems/markTradeSkillAsBank/lootItem/getRule |
| `modules/ui.lua`       | Modify | Remove Normal tab, remove Normal missing items table, remove "Global Rule" checkbox from new item dialog, remove Normal_Items radio button from modify dialog, update bulk set default, update all Normal fallback references                                                                                                                                    |
| `modules/actor.lua`    | Modify | Remove NormalItems handler branch in actor callback                                                                                                                                                                                                                                                                                                              |
| `docs/*.md`            | Modify | Update diagrams referencing Normal_Rules                                                                                                                                                                                                                                                                                                                         |

---

### Task 1: DB Migration - Merge Normal_Rules into Global_Rules

**Files:**

- Modify: `modules/db.lua` - add `MigrateNormalToGlobal()` function, call from `LoadRuleDB()`

This is the critical data-preservation step. We INSERT all Normal_Rules rows into Global_Rules, but only where Global doesn't already have that item_id (since Global was higher priority, its rules win on conflicts).

- [ ] **Step 1: Add migration function to db.lua**

In `modules/db.lua`, add this function after `LoadRuleDB()` (after line 700):

```lua
function LNS_DB.MigrateNormalToGlobal()
    if rules_db == nil then rules_db = LNS_DB.OpenDB(LNS_DB.RulesDB) end

    -- Check if Normal_Rules table exists
    local check = rules_db:prepare("SELECT name FROM sqlite_master WHERE type='table' AND name='Normal_Rules'")
    if not check then return false end
    local exists = false
    for row in check:nrows() do
        exists = true
    end
    check:finalize()
    if not exists then return false end

    -- Count Normal_Rules entries for logging
    local countStmt = rules_db:prepare("SELECT COUNT(*) as cnt FROM Normal_Rules")
    local normalCount = 0
    for row in countStmt:nrows() do
        normalCount = row.cnt
    end
    countStmt:finalize()

    if normalCount == 0 then
        -- No data to migrate, just drop the table
        rules_db:exec("DROP TABLE IF EXISTS Normal_Rules;")
        rules_db:exec("PRAGMA wal_checkpoint;")
        Logger.Info(guiLoot.console, "\agMigration complete\ax: Normal_Rules was empty, table removed.")
        return true
    end

    -- Migrate: insert Normal_Rules entries that don't exist in Global_Rules
    rules_db:exec("BEGIN TRANSACTION;")
    local migrated = 0
    local skipped = 0

    local stmt = rules_db:prepare([[
        INSERT INTO Global_Rules (item_id, item_name, item_rule, item_rule_classes, item_link)
        SELECT item_id, item_name, item_rule, item_rule_classes, item_link
        FROM Normal_Rules
        WHERE item_id NOT IN (SELECT item_id FROM Global_Rules)
    ]])

    if stmt then
        stmt:step()
        migrated = rules_db:changes()
        stmt:finalize()
    end

    skipped = normalCount - migrated

    -- Drop the Normal_Rules table
    rules_db:exec("DROP TABLE IF EXISTS Normal_Rules;")
    rules_db:exec("COMMIT;")
    rules_db:exec("PRAGMA wal_checkpoint;")

    Logger.Info(guiLoot.console,
        "\agMigration complete\ax: \ay%d\ax Normal rules merged into Global, \at%d\ax skipped (already in Global). Normal_Rules table removed.",
        migrated, skipped)
    return true
end
```

- [ ] **Step 2: Call migration from LoadRuleDB before table creation**

In `modules/db.lua`, inside `LoadRuleDB()` (currently line 621), add the migration call **before** the CREATE TABLE block. The migration must run while Normal_Rules still exists, before we stop creating it:

Replace the opening of `LoadRuleDB()`:

```lua
function LNS_DB.LoadRuleDB()
    if rules_db == nil then LNS_DB.OpenDB(LNS_DB.RulesDB) end
    -- Creating tables
    rules_db:exec(string.format([[
```

With:

```lua
function LNS_DB.LoadRuleDB()
    if rules_db == nil then rules_db = LNS_DB.OpenDB(LNS_DB.RulesDB) end

    -- One-time migration: merge Normal_Rules into Global_Rules
    LNS_DB.MigrateNormalToGlobal()

    -- Creating tables
    rules_db:exec(string.format([[
```

- [ ] **Step 3: Remove Normal_Rules from table creation SQL**

In `LoadRuleDB()`, remove the Normal_Rules CREATE TABLE block from the SQL string. Change the SQL from:

```sql
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
```

To:

```sql
CREATE TABLE IF NOT EXISTS Global_Rules (
item_id INTEGER PRIMARY KEY NOT NULL UNIQUE,
item_name TEXT NOT NULL,
item_rule TEXT NOT NULL,
item_rule_classes TEXT,
item_link TEXT
);
CREATE TABLE IF NOT EXISTS %s (
```

- [ ] **Step 4: Remove Normal_Rules from the processRules loop**

In `LoadRuleDB()` around line 677, change the table iteration from:

```lua
    for _, tbl in ipairs({ "Global_Rules", "Normal_Rules", settings.PersonalTableName, }) do
```

To:

```lua
    for _, tbl in ipairs({ "Global_Rules", settings.PersonalTableName, }) do
```

- [ ] **Step 5: Remove Normal prepared statements**

In `PrepareStatements()`, remove these four lines (around lines 148-157, 179, 181, 184):

```lua
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
```

And:

```lua
    initPreparedStatement('CHECK_DB_NORMAL', rules_db, "SELECT item_rule, item_rule_classes, item_link FROM Normal_Rules WHERE item_id = ?")
```

And:

```lua
    initPreparedStatement('GET_ITEM_LINK_NORMAL', rules_db, "SELECT item_link FROM Normal_Rules WHERE item_id = ?")
```

And:

```lua
    initPreparedStatement('UPDATE_RULE_LINK_NORMAL', rules_db, "UPDATE Normal_Rules SET item_link = ? WHERE item_id = ?")
```

- [ ] **Step 6: Update UpsertItemRule - remove Normal branch**

In `UpsertItemRule()` (line 895-923), change:

```lua
    if tableName == 'Normal_Rules' then
        stmt = LNS_DB.PreparedStatements.INSERT_RULE_NORMAL
    elseif tableName == 'Global_Rules' then
```

To:

```lua
    if tableName == 'Global_Rules' then
```

- [ ] **Step 7: Update GetItemLink - remove Normal branch**

In `GetItemLink()` (line 792-817), change:

```lua
    local stmt = LNS_DB.PreparedStatements.GET_ITEM_LINK_NORMAL
    if which_table == 'Global_Rules' then
        stmt = LNS_DB.PreparedStatements.GET_ITEM_LINK_GLOBAL
    elseif which_table == settings.PersonalTableName then
```

To:

```lua
    local stmt = LNS_DB.PreparedStatements.GET_ITEM_LINK_GLOBAL
    if which_table == settings.PersonalTableName then
```

- [ ] **Step 8: Update UpdateRuleLink - remove Normal branch**

In `UpdateRuleLink()` (line 820-839), change:

```lua
    local stmt = LNS_DB.PreparedStatements.UPDATE_RULE_LINK_NORMAL
    if which_table == 'Global_Rules' then
        stmt = LNS_DB.PreparedStatements.UPDATE_RULE_LINK_GLOBAL
    elseif which_table == settings.PersonalTableName then
```

To:

```lua
    local stmt = LNS_DB.PreparedStatements.UPDATE_RULE_LINK_GLOBAL
    if which_table == settings.PersonalTableName then
```

- [ ] **Step 9: Update BulkSet - remove Normal mapping**

In `BulkSet()` (line 724-790), change:

```lua
    local localName = which_table == 'Normal_Rules' and 'NormalItems' or 'GlobalItems'
```

To:

```lua
    local localName = 'GlobalItems'
```

- [ ] **Step 10: Update ExportDB loop - remove Normal_Rules**

In the export loop (line 677 area), if there's a separate export function iterating over tables, change:

```lua
    for _, tbl in ipairs({ "Global_Rules", "Normal_Rules", settings.PersonalTableName, }) do
```

To:

```lua
    for _, tbl in ipairs({ "Global_Rules", settings.PersonalTableName, }) do
```

- [ ] **Step 11: Update ImportOldRulesDB - merge old Normal into Global**

In `ImportOldRulesDB()` (around line 1075-1230), the function imports from an old database. Change it so old Normal_Rules entries get imported into Global_Rules instead. Replace the entire Normal import section (lines 1105-1229 area) - remove the separate `tmpNormalDB` processing and merge it into the Global import:

After loading `tmpGlobalDB` from old Global_Rules (lines 1090-1103), change the Normal loading (lines 1105-1119) to merge into Global instead:

```lua
    query = "SELECT * From Normal_Rules;"
    stmt = db:prepare(query)
    if stmt then
        cntr = 1
        for row in stmt:nrows() do
            local itemID = cntr * -1
            -- Only add to global if not already there by name
            if not tmpNamesGlobal[row.item_name] then
                tmpGlobalDB[itemID] = {
                    item_id      = itemID,
                    item_name    = row.item_name,
                    item_rule    = row.item_rule,
                    item_classes = row.item_classes or 'All',
                }
                tmpNamesGlobal[row.item_name] = itemID
            end
            cntr = cntr + 1
        end
        stmt:finalize()
    end
```

Then remove the entire `tmpNormalDB` variable, `newNormal` processing block, and the second INSERT INTO Normal_Rules SQL block (lines 1148-1229). The `nameSet` building should only use `tmpGlobalDB`:

```lua
    local nameSet = {}
    for _, v in pairs(tmpGlobalDB) do nameSet[v.item_name] = true end
```

Remove the `tmpNormalDB` references from `nameSet`, `newNormal`, and the second INSERT block entirely.

---

### Task 2: Settings Cleanup - Remove AlwaysGlobal and Normal_Rules references

**Files:**

- Modify: `modules/settings.lua` lines 8-10, 62, 132, 190

- [ ] **Step 1: Remove Normal_Rules from TableListRules**

In `modules/settings.lua` line 8-10, change:

```lua
LNS_SETTINGS.TableListRules    = {
    "Global_Rules", "Normal_Rules", LNS_SETTINGS.PersonalTableName,
}
```

To:

```lua
LNS_SETTINGS.TableListRules    = {
    "Global_Rules", LNS_SETTINGS.PersonalTableName,
}
```

- [ ] **Step 2: Remove AlwaysGlobal from SettingsEnum**

In `modules/settings.lua` line 62, remove:

```lua
    alwaysglobal = 'AlwaysGlobal',
```

- [ ] **Step 3: Remove AlwaysGlobal from default Settings**

In `modules/settings.lua` line 132, remove:

```lua
    AlwaysGlobal        = false, -- Always assign new rules to global as well as normal rules.
```

- [ ] **Step 4: Remove AlwaysGlobal from Tooltips**

In `modules/settings.lua` line 190, remove:

```lua
    AlwaysGlobal        = "Always assign new rules to global as well as normal rules.",
```

---

### Task 3: init.lua - Remove Normal state variables and setNormalItem

**Files:**

- Modify: `init.lua` lines 118-124, 363-399, 451-466, 2887-2901

- [ ] **Step 1: Remove Normal state variable declarations**

At lines 118-124, remove these declarations:

```lua
LNS.NormalItemsRules       = {}
LNS.NormalItemsClasses     = {}
```

```lua
LNS.NormalItemsMissing     = {}
```

```lua
LNS.NormalMissingNames     = {}
```

Keep `GlobalItemsRules`, `GlobalItemsClasses`, `GlobalItemsMissing`, `GlobalMissingNames`.

- [ ] **Step 2: Remove Normal sorting from SortTables**

In `SortTables()` (lines 360-399), remove:

```lua
    settings.TempSettings.SortedNormalItemKeys     = {}
```

```lua
    settings.TempSettings.SortedMissingNormalNames = {}
```

```lua
    for k in pairs(LNS.NormalItemsRules) do
        table.insert(settings.TempSettings.SortedNormalItemKeys, k)
    end
    table.sort(settings.TempSettings.SortedNormalItemKeys, function(a, b) return a < b end)
```

And remove the NormalMissingNames sorting block:

```lua
    tmpTbl = {}
    for name, id in pairs(LNS.NormalMissingNames) do
        table.insert(tmpTbl, { name = name, id = id, })
    end
    table.sort(tmpTbl, function(a, b)
        return a.name < b.name
    end)
    settings.TempSettings.SortedMissingNormalNames = tmpTbl
```

- [ ] **Step 3: Remove Normal resets from loadSettings**

In `loadSettings()` (lines 451-466), remove:

```lua
        LNS.NormalItemsRules     = {}
```

```lua
        LNS.NormalItemsClasses   = {}
```

- [ ] **Step 4: Remove setNormalItem function**

Delete the entire `setNormalItem` function (lines 2887-2901):

```lua
-- Sets a Normal Item rule
function LNS.setNormalItem(itemID, val, classes, link)
    ...
end
```

---

### Task 4: init.lua - Reroute all NormalItems references to GlobalItems

**Files:**

- Modify: `init.lua` - many locations

- [ ] **Step 1: Update lookupLootRule - remove Normal lookup**

In `lookupLootRule()` (lines 1725-1729), remove the Normal in-memory check:

```lua
        if LNS.NormalItemsRules[itemID] then
            if link ~= 'NULL' or (item_link and link ~= item_link) then
                LNS.UpdateRuleLink(itemID, LNS.ItemLinks[itemID], 'Normal_Rules')
            end
            return LNS.NormalItemsRules[itemID], LNS.NormalItemsClasses[itemID], LNS.ItemLinks[itemID], 'Normal'
        end
```

In the DB fallback section (lines 1770-1773), remove the Normal DB check:

```lua
        if not found then
            found, rule, classes, lookupLink = db.CheckRulesDB(itemID, db.PreparedStatements.CHECK_DB_NORMAL)
            which_table = 'Normal'
            tablename = 'Normal_Rules'
        end
```

Change the default `which_table` at line 1692 from `'Normal'` to `'Global'`:

```lua
    local which_table = 'Global'
```

In the wildcard handler (line 1783), change:

```lua
                    which_table   = 'Normal'
```

To:

```lua
                    which_table   = 'Global'
```

- [ ] **Step 2: Update addNewItem - change NormalItems to GlobalItems**

At line 2064, change:

```lua
        LNS.addRule(itemID, 'NormalItems', itemRule, LNS.TempItemClasses, itemLink, true)
```

To:

```lua
        LNS.addRule(itemID, 'GlobalItems', itemRule, LNS.TempItemClasses, itemLink, true)
```

At line 2066-2069, remove the AlwaysGlobal conditional and just set GlobalItems:

```lua
    local sections = { NormalItems = 1, }
    if settings.Settings.AlwaysGlobal then
        sections['GlobalItems'] = 1
    end
```

To:

```lua
    local sections = { GlobalItems = 1, }
```

- [ ] **Step 3: Update modifyItemRule - remove Normal/AlwaysGlobal logic**

At line 2089, change:

```lua
    local section = tableName == "Normal_Rules" and "NormalItems" or "GlobalItems"
```

To:

```lua
    local section = "GlobalItems"
    if tableName == settings.PersonalTableName then
        section = 'PersonalItems'
    end
```

And remove line 2090 since it's now handled above:

```lua
    section = tableName == settings.PersonalTableName and 'PersonalItems' or section
```

Remove the AlwaysGlobal conditionals at lines 2118-2125:

```lua
        if settings.Settings.AlwaysGlobal and section == 'NormalItems' then
            success = db.DeleteItemRule(action, 'Global_Rules', itemName, itemID)
        end
```

And:

```lua
        if settings.Settings.AlwaysGlobal and section == 'NormalItems' then
            success = db.UpsertItemRule(action, 'Global_Rules', itemName, itemID, classes, link)
        end
```

Remove the AlwaysGlobal actor section conditional at lines 2130-2132:

```lua
        if settings.Settings.AlwaysGlobal and section == 'NormalItems' then
            sections['GlobalItems'] = 1
        end
```

- [ ] **Step 4: Update addRule - remove Normal mapping and AlwaysGlobal**

At line 2181-2188, the dynamic key `LNS[section .. "Rules"]` will now always resolve to `GlobalItemsRules` or `PersonalItemsRules` - this is fine, no change needed there.

Remove the AlwaysGlobal block at lines 2185-2188:

```lua
    if settings.Settings.AlwaysGlobal and section == 'NormalItems' then
        LNS["GlobalItemsRules"][itemID]   = rule
        LNS["GlobalItemsClasses"][itemID] = classes
    end
```

At line 2190, change:

```lua
    local tblName = section == 'GlobalItems' and 'Global_Rules' or 'Normal_Rules'
```

To:

```lua
    local tblName = 'Global_Rules'
```

(The PersonalItems check on the next line already handles the personal case.)

- [ ] **Step 5: Update command handler - change NormalItems to GlobalItems**

In the command handler function, change all `addRule` calls that use `'NormalItems'` to `'GlobalItems'`. These are at approximately lines 866, 880, 964, 969, 993:

Replace all occurrences of:

```lua
LNS.addRule(itemID, 'NormalItems',
```

With:

```lua
LNS.addRule(itemID, 'GlobalItems',
```

And at line 871, change:

```lua
                    LNS.EnterNegIDRule(args[3], rule, 'All', 'NULL', 'Normal_Rules')
```

To:

```lua
                    LNS.EnterNegIDRule(args[3], rule, 'All', 'NULL', 'Global_Rules')
```

- [ ] **Step 6: Update EnterNegIDRule - remove Normal branch**

In `EnterNegIDRule()` (lines 1172-1209), remove the `elseif tableName == 'Normal_Rules'` branch (lines 1187-1196):

```lua
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
```

- [ ] **Step 7: Update enterNewItemRuleInfo - remove Normal references**

At line 1129, change:

```lua
        section    = "NormalItems",
```

To:

```lua
        section    = "GlobalItems",
```

At line 1140, change:

```lua
    if (classes ~= (LNS.NormalItemsClasses[itemID] or 'new') or rule ~= (LNS.NormalItemsRules[itemID] or 'new')) and rule ~= 'Ignore' and rule ~= 'Ask' then
```

To:

```lua
    if (classes ~= (LNS.GlobalItemsClasses[itemID] or 'new') or rule ~= (LNS.GlobalItemsRules[itemID] or 'new')) and rule ~= 'Ignore' and rule ~= 'Ask' then
```

Remove the AlwaysGlobal conditional at lines 1166-1168:

```lua
    if settings.Settings.AlwaysGlobal then
        modMessage.section = "GlobalItems"
    end
```

(The section is already "GlobalItems" from the change above.)

- [ ] **Step 8: Update getRule - change ruletype 'Normal' to 'Global'**

At line 2602, change:

```lua
    if settings.Settings.AlwaysEval and ruletype == 'Normal' then
```

To:

```lua
    if settings.Settings.AlwaysEval and ruletype == 'Global' then
```

At line 2616, change:

```lua
        ruletype = 'Normal'
```

To:

```lua
        ruletype = 'Global'
```

At line 2414, change:

```lua
        if nodrop and settings.Settings.CanWear and ruletype == 'Normal' and not isAug then
```

To:

```lua
        if nodrop and settings.Settings.CanWear and ruletype == 'Global' and not isAug then
```

At line 2769, change:

```lua
    if ((lootRule == 'Sell' or lootRule == 'Tribute') and ruletype == 'Normal') then
```

To:

```lua
    if ((lootRule == 'Sell' or lootRule == 'Tribute') and ruletype == 'Global') then
```

At line 2791, change:

```lua
    if settings.Settings.LootAugments and isAug and ruletype == 'Normal' and not settings.Settings.MasterLooting then
```

To:

```lua
    if settings.Settings.LootAugments and isAug and ruletype == 'Global' and not settings.Settings.MasterLooting then
```

At line 2805, change:

```lua
    if settings.Settings.KeepSpells and LNS.checkSpells(itemName) and ruletype == 'Normal' and not settings.Settings.MasterLooting then
```

To:

```lua
    if settings.Settings.KeepSpells and LNS.checkSpells(itemName) and ruletype == 'Global' and not settings.Settings.MasterLooting then
```

- [ ] **Step 9: Update missing item resolution in getRule**

At lines 2580-2593, change all Normal references to Global:

```lua
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
```

To:

```lua
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
```

- [ ] **Step 10: Update processItems - remove Normal fallback**

At line 3916, change:

```lua
        local rule       = LNS.NormalItemsRules[itemID] or "Ignore"
```

To:

```lua
        local rule       = LNS.GlobalItemsRules[itemID] or "Ignore"
```

- [ ] **Step 11: Update lootItem - remove Normal from rule lookup**

At line 2963-2964, change:

```lua
    local rule           = isGlobalItem and LNS.GlobalItemsRules[cItemID] or
        (isPersonalItem and LNS.PersonalItemsRules[cItemID] or (LNS.NormalItemsRules[cItemID] or nil))
```

To:

```lua
    local rule           = isPersonalItem and LNS.PersonalItemsRules[cItemID] or
        (isGlobalItem and LNS.GlobalItemsRules[cItemID] or nil)
```

- [ ] **Step 12: Update markTradeSkillAsBank - change to GlobalItems**

At lines 3714-3715, change:

```lua
            LNS.NormalItemsRules[bagSlot.ID()] = 'Bank'
            LNS.addRule(bagSlot.ID(), 'NormalItems', 'Bank', 'All', bagSlot.ItemLink('CLICKABLE')())
```

To:

```lua
            LNS.GlobalItemsRules[bagSlot.ID()] = 'Bank'
            LNS.addRule(bagSlot.ID(), 'GlobalItems', 'Bank', 'All', bagSlot.ItemLink('CLICKABLE')())
```

- [ ] **Step 13: Update eventSell and eventTribute - change to GlobalItems**

At line 3643, change:

```lua
        LNS.addRule(itemID, "NormalItems", "Sell", "All", 'NULL')
```

To:

```lua
        LNS.addRule(itemID, "GlobalItems", "Sell", "All", 'NULL')
```

At line 3814, change:

```lua
        LNS.addRule(itemID, "NormalItems", "Tribute", "All", link)
```

To:

```lua
        LNS.addRule(itemID, "GlobalItems", "Tribute", "All", link)
```

- [ ] **Step 14: Clean up commented-out code referencing Normal**

Remove the commented-out SECTIONS table (lines 55-59):

```lua
-- local SECTIONS = {
--     ['NormalItems']='Normal_Rules',
--     ['GlobalItems']='Global_Rules',
--     ['PersonalItems']=settings.PersonalTableName,
-- }
```

Remove the commented-out lookupLootRule branches (lines 1731-1752).

Remove the commented-out `addRule` AlwaysGlobal line (lines 2195-2197).

---

### Task 5: UI - Remove Normal tab and update dialogs

**Files:**

- Modify: `modules/ui.lua`

- [ ] **Step 1: Remove the Normal Items tab**

At line 1870-1871, remove:

```lua
        -- Normal Items
        LNS_UI.drawTabbedTable("Normal")
```

- [ ] **Step 2: Remove Normal missing items table from renderMissingItemsTables**

At lines 712-746, remove the entire "Imported Normal Rules" section:

```lua
    ImGui.Separator()
    ImGui.Text("Imported Normal Rules")
    if ImGui.BeginTable("ImportedData##Normal", 4, ...) then
        ...
        ImGui.EndTable()
    end
```

- [ ] **Step 3: Remove "Global Rule" checkbox from new item dialog**

At lines 1309-1314, remove the `tempGlobalRule` checkbox and its initialization:

```lua
                    if LNS.tempGlobalRule[itemID] == nil then
                        LNS.tempGlobalRule[itemID] = settings.Settings.AlwaysGlobal
                    end
                    ImGui.Indent(10)
                    LNS.tempGlobalRule[itemID] = ImGui.Checkbox('Global Rule', LNS.tempGlobalRule[itemID])
                    ImGui.Unindent(10)
```

At line 1320, change:

```lua
                        local ruleTable = LNS.tempGlobalRule[itemID] and "GlobalItems" or "NormalItems"
```

To:

```lua
                        local ruleTable = "GlobalItems"
```

- [ ] **Step 4: Remove Normal_Items radio button from modify dialog**

At lines 3187-3190, remove:

```lua
        ImGui.SameLine()
        if ImGui.RadioButton("Normal Items", settings.TempSettings.ModifyItemTable == "Normal_Items") then
            settings.TempSettings.ModifyItemTable = "Normal_Items"
        end
```

- [ ] **Step 5: Update modify dialog "else" branch - route to Global**

At lines 3241-3243, the `else` branch that used to call `setNormalItem` should now call `setGlobalItem`:

```lua
            else
                LNS.NormalItemsRules[settings.TempSettings.ModifyItemID] = newRule
                LNS.setNormalItem(settings.TempSettings.ModifyItemID, newRule, tempValues.Classes, item.Link)
```

To:

```lua
            else
                LNS.GlobalItemsRules[settings.TempSettings.ModifyItemID] = newRule
                LNS.setGlobalItem(settings.TempSettings.ModifyItemID, newRule, tempValues.Classes, item.Link)
```

At lines 3268-3269 (delete button else branch):

```lua
            else
                LNS.setNormalItem(settings.TempSettings.ModifyItemID, 'delete', 'All', 'NULL')
```

To:

```lua
            else
                LNS.setGlobalItem(settings.TempSettings.ModifyItemID, 'delete', 'All', 'NULL')
```

At lines 3342-3347 (matches else branch):

```lua
                        else
                            LNS.setNormalItem(id, newRule, tempValues.Classes, LNS.ItemLinks[id])
                            LNS.NormalItemsMissing[oldID] = nil
                            LNS.NormalItemsRules[oldID] = nil
                            LNS.NormalItemsClasses[oldID] = nil
                            LNS.setNormalItem(oldID, 'delete', 'All', 'NULL')
```

To:

```lua
                        else
                            LNS.setGlobalItem(id, newRule, tempValues.Classes, LNS.ItemLinks[id])
                            LNS.GlobalItemsMissing[oldID] = nil
                            LNS.GlobalItemsRules[oldID] = nil
                            LNS.GlobalItemsClasses[oldID] = nil
                            LNS.setGlobalItem(oldID, 'delete', 'All', 'NULL')
```

- [ ] **Step 6: Update default ModifyItemTable fallback**

At line 3141, change:

```lua
        settings.TempSettings.ModifyItemTable = settings.TempSettings.LastModTable or 'Normal_Items'
```

To:

```lua
        settings.TempSettings.ModifyItemTable = settings.TempSettings.LastModTable or 'Global_Items'
```

- [ ] **Step 7: Update BulkSet default table**

At line 2095, change:

```lua
                        settings.TempSettings.BulkSetTable = "Normal_Rules"
```

To:

```lua
                        settings.TempSettings.BulkSetTable = "Global_Rules"
```

---

### Task 6: Actor - Remove NormalItems handler

**Files:**

- Modify: `modules/actor.lua` lines 368-381

- [ ] **Step 1: Remove NormalItems branch from actor callback**

At lines 368-381, remove the entire `elseif` block:

```lua
        elseif (section == 'NormalItems' or (sections and sections['NormalItems'])) and who ~= settings.MyName then
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
```

---

### Task 7: Documentation Updates

**Files:**

- Modify: `docs/actor-messaging-diagram.md`
- Modify: `docs/looting-sequence-diagram.md`
- Modify: `docs/database-updates-diagram.md`
- Modify: `README.md`

- [ ] **Step 1: Update docs to remove Normal_Rules references**

In each docs file, replace references to "Normal_Rules" / "Normal rules" with "Global_Rules" / "Global rules". Remove any mention of the three-tier system and describe the two-tier system (Personal > Global). Remove AlwaysGlobal references.

In `README.md` line 108, remove:

```
- AlwaysGlobal: (default off)
```

---

### Task 8: Final Verification Grep

- [ ] **Step 1: Verify no Normal references remain**

Run a grep across the entire lootnscoot directory for remaining "Normal" references in code context. Ignore comments, docs, and changelog:

```bash
cd /d/MQ_Redguides_EMU/lua/lootnscoot
grep -rn "Normal" --include="*.lua" | grep -v "^--" | grep -v CHANGELOG
```

Any remaining hits should be investigated and resolved.

- [ ] **Step 2: Verify no AlwaysGlobal references remain**

```bash
grep -rn "AlwaysGlobal" --include="*.lua" /d/MQ_Redguides_EMU/lua/lootnscoot/
```

Should return zero results.

---

## Migration Safety Notes

- The SQL migration uses `INSERT ... WHERE item_id NOT IN (SELECT item_id FROM Global_Rules)` - Global rules always win on conflicts since they were higher priority.
- The migration runs once at startup. After it drops Normal_Rules, subsequent startups skip the migration (table doesn't exist).
- No data is lost - all Normal rules that don't conflict with Global rules are preserved in Global_Rules.
- Users who had `AlwaysGlobal = true` already had all their rules in both tables, so the migration is a no-op for them.
- The `AlwaysGlobal` setting removal from settings.lua won't break existing config files - Lua's `dofile` will just load the old value and it'll be ignored since nothing reads it.
