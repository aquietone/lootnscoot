local mq = require('mq')

local LNS_SETTINGS = {_version = '0.1'}

LNS_SETTINGS.MyName             = mq.TLO.Me.DisplayName()
LNS_SETTINGS.EqServer           = string.gsub(mq.TLO.EverQuest.Server(), ' ', '_')
LNS_SETTINGS.PersonalTableName  = string.format("%s_Rules", LNS_SETTINGS.MyName)

-- tables
LNS_SETTINGS.SettingsEnum   = {
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
    useautorules = 'UseAutoRules',
    trackhistory = 'TrackHistory',

}

LNS_SETTINGS.SettingsNoDraw = {
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

LNS_SETTINGS.Settings       = {
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
    TrackHistory        = true,  -- Enable inserting loot results into history table
    -- ProcessingEval   = true, -- Re evaluate when processing items for sell\tribute? this will re check our settings and not sell or tribute items outside the new parameters
    UseAutoRules        = false, -- let LNS decide loot rules on new items
    BuyItemsTable       = {
        ['Iron Ration'] = 20,
        ['Water Flask'] = 20,
    },
}

LNS_SETTINGS.Tooltips       = {
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
    TrackHistory        = "Enable inserting loot results into history table",
}

LNS_SETTINGS.TempSettings   = {
    Edit               = {},
    ImportDBFileName   = '',
    ImportDBFilePath   = '',
    ItemsToLoot        = {},
    UpdatedBuyItems    = {},
    DeletedBuyKeys     = {},
    RemoveMLItemInfo   = {},
    RemoveMLCorpseInfo = {},
    SortedSettingsKeys = {},
    SortedToggleKeys   = {},
    ModifyItemMatches  = nil,
    ShowHelp           = false,
    ShowImportDB       = false,
    UpdateSettings     = false,
    SendSettings       = false,
    LastModID          = 0,
    LastZone           = nil,
    LastInstance       = nil,
    SafeZoneWarned     = false,
    Popped             = {},
    NewItemData        = {},
    NewBuyItem         = ""
}
return LNS_SETTINGS