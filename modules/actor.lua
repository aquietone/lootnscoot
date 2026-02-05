local mq              = require('mq')
local Actors          = require('actors')
local settings        = require('modules.settings')
local guiLoot         = require('modules.loot_hist')
local success, Logger = pcall(require, 'lib.Logger')
if not success then
    printf('\arERROR: Write.lua could not be loaded\n%s\ax', Logger)
    return
end

local LNS_ACTORS = { _version = '0.1', }

local LNS

function LNS_ACTORS.SetLNS(_LNS)
    LNS = _LNS
end

------------------------------------
--          ACTORS
------------------------------------

local function callback(message)
    local lootMessage = message()
    local server      = lootMessage.Server and lootMessage.Server or (lootMessage.server or 'NULL')
    if server ~= settings.EqServer and server ~= 'NULL' then return end -- if they sent the server name then only answer if it matches our server

    local who           = lootMessage.who or ''
    local action        = lootMessage.action or ''
    local itemID        = lootMessage.itemID or 0
    local rule          = lootMessage.rule or 'NULL'
    local section       = lootMessage.section or 'NormalItems'
    local sections      = lootMessage.sections
    local itemName      = lootMessage.item or 'NULL'
    local itemLink      = lootMessage.link or 'NULL'
    local itemClasses   = lootMessage.classes or 'All'
    local itemRaces     = lootMessage.races or 'All'
    local boxSettings   = lootMessage.settings or {}
    local directions    = lootMessage.directions or 'NULL'
    local combatLooting = lootMessage.CombatLooting
    local corpseradius  = lootMessage.CorpseRadius or settings.Settings.CorpseRadius
    local lootmycorpse  = lootMessage.LootMyCorpse
    local ignorenearby  = lootMessage.IgnoreNearby
    local itemDetails   = lootMessage.details or {}
    if ignorenearby == nil then
        ignorenearby = settings.Settings.IgnoreMyNearCorpses
    end
    if combatLooting == nil then
        combatLooting = settings.Settings.CombatLooting
    end
    if lootmycorpse == nil then
        lootmycorpse = settings.Settings.LootMyCorpse
    end
    local dbgTbl = {
        Lookup = 'loot.RegisterActors()',
        Event = '\ax\agReceived\ax message',
        Action = action,
        ItemID = itemID,
        Rule = rule,
        Classes = itemClasses,
        Directions = directions,
        Who = who,
        Link = itemLink,
        LNS_Mode = LNS.Mode,
        Secion = section,
    }

    ------- DEBUG MESSAGES PER SECOND ---------
    -- keep a running Average of the Total MPS (Messages Per Second)
    local now    = os.clock()
    if settings.TempSettings.MPS == nil then
        settings.TempSettings.MPS = 0
        settings.TempSettings.MPSStart = now
        settings.TempSettings.MPSCount = 0
        settings.TempSettings.LastMsg = now
    end

    if now - settings.TempSettings.LastMsg >= 10 then
        settings.TempSettings.MPSStart = now
        settings.TempSettings.MPSCount = 0
    end

    settings.TempSettings.MPSCount = settings.TempSettings.MPSCount + 1

    if now - settings.TempSettings.MPSStart >= 1 then
        settings.TempSettings.MPS = settings.TempSettings.MPSCount / (now - settings.TempSettings.MPSStart)
    else
        settings.TempSettings.MPS = settings.TempSettings.MPSCount
    end

    settings.TempSettings.LastMsg = now

    if LNS.debugPrint then
        -- reset after 10 seconds of inactivity
        if settings.TempSettings.MailBox == nil then
            settings.TempSettings.MailBox = {}
        end
        local sub = ''
        if directions ~= nil and directions ~= 'NULL' then
            sub = directions
        elseif action ~= nil and action ~= 'NULL' then
            sub = action
        else
            sub = 'unknown'
        end
        table.insert(settings.TempSettings.MailBox, {
            Time = string.format("%s.%s", os.date('%H:%M:%S'), string.format("%.3f", (os.clock() % 1)):gsub("0%.", '')),
            Subject = sub,
            Sender = who or 'unknown',
        })
        table.sort(settings.TempSettings.MailBox, function(a, b)
            return a.Time > b.Time
        end)
    end
    ------------------------------------------

    if LNS.Mode == 'directed' and who == settings.MyName then
        if directions == 'doloot' and (settings.Settings.DoLoot or settings.Settings.LootMyCorpse) and not LNS.LootNow then
            if os.time() - (settings.TempSettings.DirectedLoot or 0) <= 2 then
                settings.TempSettings.DirectedLoot = os.time()
                Logger.Debug(guiLoot.console, dbgTbl)
            end
            if lootMessage.limit then
                settings.TempSettings.LootLimit = lootMessage.limit
            end
            LNS.LootNow = true
            return
        end
        if directions == 'setsetting_directed' or directions == 'combatlooting' then
            dbgTbl['CombatLooting'] = combatLooting
            dbgTbl['CorpseRadius'] = corpseradius
            dbgTbl['LootMyCorpse'] = lootmycorpse
            dbgTbl['IgnoreNearby'] = ignorenearby
            Logger.Debug(guiLoot.console, dbgTbl)
            settings.Settings.CombatLooting = combatLooting
            settings.Settings.CorpseRadius = corpseradius
            settings.Settings.LootMyCorpse = lootmycorpse
            settings.Settings.IgnoreMyNearCorpses = ignorenearby
            LNS.Boxes[settings.MyName] = settings.Settings
            -- LNS.writeSettings()
            -- LNS_ACTORS.SendMySettings()
            settings.TempSettings[settings.MyName] = nil
            settings.TempSettings.NeedSave = true
            return
        end
        if directions == 'getsettings_directed' or directions == 'getcombatsetting' then
            Logger.Debug(guiLoot.console, dbgTbl)
            LNS_ACTORS.Send({
                Subject = 'mysetting',
                Who = settings.MyName,
                Server = settings.EqServer,
                LNSSettings = settings.Settings,
                CorpsesToIgnore = LNS.lootedCorpses or {},
            }, 'loot_module')
            settings.TempSettings.SentSettings = true
            settings.TempSettings.NeedSave = true
            return
        end
    end
    if itemName == 'NULL' then
        itemName = LNS.ItemNames[itemID] and LNS.ItemNames[itemID] or 'NULL'
    end
    if action == 'Hello' and who ~= settings.MyName then
        settings.TempSettings.SendSettings = true
        settings.TempSettings[who] = {}
        table.insert(LNS.BoxKeys, who)
        table.sort(LNS.BoxKeys)
        return
    end

    if action == 'check_item' and who ~= settings.MyName then
        local corpseID = lootMessage.CorpseID
        LNS.lootedCorpses[corpseID] = true

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

            if LNS.MasterLootList[corpseID].Items[itemName].Members[settings.MyName] == nil then
                LNS.MasterLootList[corpseID].Items[itemName].Members[settings.MyName] = MyCount
                LNS_ACTORS.Send({
                    who = settings.MyName,
                    action = 'check_item',
                    item = itemName,
                    link = itemLink,
                    Count = MyCount,
                    Server = settings.EqServer,
                    CorpseID = corpseID,
                    Value = lootMessage.Value or 0,
                    NoDrop = lootMessage.NoDrop or false,
                    Lore = lootMessage.Lore or false,
                })
            end
        end

        return
    end

    if action == 'recheck_item' and who ~= settings.MyName then
        local MyCount = mq.TLO.FindItemCount(string.format("=%s", itemName))() + mq.TLO.FindItemBankCount(string.format("=%s", itemName))()
        local corpseID = lootMessage.CorpseID
        LNS_ACTORS.Send({
            who = settings.MyName,
            action = 'check_item',
            item = itemName,
            link = itemLink,
            Count = MyCount,
            CorpseID = corpseID,
            Server = settings.EqServer,
        })
        return
    end

    if action == 'item_gone' then
        settings.TempSettings.RemoveMLItemInfo = {
            ['itemName'] = itemName,
            ['corpseID'] = lootMessage.CorpseID,
        }
        settings.TempSettings.RemoveMLItem = true
        return
    end

    if action == 'corpse_gone' and who ~= settings.MyName then
        settings.TempSettings.RemoveMLCorpseInfo = {
            ['corpseID'] = lootMessage.CorpseID,
        }
        settings.TempSettings.RemoveMLCorpse = true
        return
    end

    if action == 'master_looter' and who ~= settings.MyName and settings.Settings.MasterLooting ~= lootMessage.select then
        settings.Settings.MasterLooting          = lootMessage.select
        settings.TempSettings[who].MasterLooting = lootMessage.select
        LNS.Boxes[settings.MyName]               = settings.Settings
        settings.TempSettings[settings.MyName]   = nil
        settings.TempSettings.NeedSave           = true
        settings.TempSettings.UpdateSettings     = true
        Logger.Debug(guiLoot.console, dbgTbl)
        Logger.Info(guiLoot.console, "Setting \ay%s\ax to \ag%s\ax", 'MasterLooting', lootMessage.select)

        return
    end

    if action == 'loot_item' and who == settings.MyName then
        --LNS_ACTORS.Send({ who = member, action = 'loot_item', CorpseID = cID, item = item, })
        Logger.Info(guiLoot.console, "\agLooting Item\ax: \at%s\ax, \ayLink\ax: \at%s\ax, \awFrom\ax: \ag%s\ax", itemName, itemLink, who)
        table.insert(settings.TempSettings.ItemsToLoot, { corpseID = lootMessage.CorpseID, itemName = itemName, })
        return
    end

    if action == 'sendsettings' and who ~= settings.MyName then
        if LNS.Boxes[who] == nil then LNS.Boxes[who] = {} end

        LNS.Boxes[who] = boxSettings
        settings.TempSettings[who] = boxSettings
        return
    end

    if action == 'updatesettings' then
        if LNS.Boxes[who] == nil then LNS.Boxes[who] = {} end
        LNS.Boxes[who] = {}
        LNS.Boxes[who] = boxSettings
        settings.TempSettings[who] = nil
        if who == settings.MyName then
            for k, v in pairs(boxSettings) do
                if type(v) ~= 'table' then
                    settings.Settings[k] = v
                end
            end
            LNS.Boxes[settings.MyName] = settings.Settings
            settings.TempSettings[settings.MyName] = nil
            settings.TempSettings.UpdateSettings = true
        end
        return
    end

    if action == 'addsafezone' then
        if who == settings.MyName then return end
        LNS.SafeZones[lootMessage.zone] = true
        settings.TempSettings[settings.MyName] = nil
        settings.TempSettings.UpdateSettings = true
        Logger.Debug(guiLoot.console, dbgTbl)

        return
    end

    if action == 'removesafezone' then
        if who == settings.MyName then return end
        LNS.SafeZones[lootMessage.zone] = nil
        settings.TempSettings[settings.MyName] = nil
        settings.TempSettings.UpdateSettings = true
        Logger.Debug(guiLoot.console, dbgTbl)

        return
    end

    if action == 'updatewildcard' then
        Logger.Debug(guiLoot.console, dbgTbl)
        settings.TempSettings.NeedReloadWildCards = true
        return
    end

    if server ~= settings.EqServer then return end

    -- Reload loot settings
    if action == 'reloadrules' and who ~= settings.MyName then
        LNS[lootMessage.bulkLabel .. 'Rules']   = {}
        LNS[lootMessage.bulkLabel .. 'Classes'] = {}
        LNS[lootMessage.bulkLabel .. 'Rules']   = lootMessage.bulkRules or {}
        LNS[lootMessage.bulkLabel .. 'Classes'] = lootMessage.bulkClasses or {}
        LNS.ItemLinks                           = lootMessage.bulkLink or {}
        return
    end
    -- -- Handle actions

    if action == 'addrule' or action == 'modifyitem' or (action == 'new' and sections ~= nil) then
        Logger.Debug(guiLoot.console, dbgTbl)

        if (section == 'PersonalItems' or (sections and sections['PersonalItems'])) and who == settings.MyName then
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
        elseif (section == 'GlobalItems' or (sections and sections['GlobalItems'])) and who ~= settings.MyName then
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
        end
        Logger.Info(guiLoot.console, infoMsg)

        if lootMessage.entered and action ~= 'deleteitem' then
            if LNS.lootedCorpses[lootMessage.corpse] and lootMessage.hasChanged and rule ~= 'Ignore' and rule ~= 'Ask' then
                LNS.lootedCorpses[lootMessage.corpse] = nil
            end

            LNS.NewItems[itemID] = nil
            if settings.TempSettings.NewItemIDs ~= nil then
                for idx, id in ipairs(settings.TempSettings.NewItemIDs) do
                    if id == itemID then
                        table.remove(settings.TempSettings.NewItemIDs, idx)
                        break
                    end
                end
            end
            if settings.TempSettings.NewItemIDs ~= nil then
                LNS.NewItemsCount = #settings.TempSettings.NewItemIDs or 0
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
                CorpseLooted = LNS.lootedCorpses[lootMessage.corpse] or false,
            }
            Logger.Info(guiLoot.console, infoMsg)
        end

        if who ~= settings.MyName then
            table.insert(settings.TempSettings.GetItems, { Name = itemName, ID = itemID, ItemLink = itemLink, })
        end

        -- clean bags of items marked as destroy so we don't collect garbage
        if rule:lower() == 'destroy' then
            settings.TempSettings.NeedsCleanup = true
        end
    elseif action == 'deleteitem' and who ~= settings.MyName then
        Logger.Debug(guiLoot.console, dbgTbl)

        LNS[section .. 'Rules'][itemID]   = nil
        LNS[section .. 'Classes'][itemID] = nil
        infoMsg                           = {
            Lookup = 'loot.RegisterActors()',
            Action = action,
            RuleType = section,
            Rule = rule,
            Item = itemName,
        }
        Logger.Info(guiLoot.console, infoMsg)
    end
    if action == 'new' and who ~= settings.MyName and LNS.NewItems[itemID] == nil then
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
            Tribute    = lootMessage.tribute,
            Classes    = itemClasses,
            Races      = itemRaces,
            CorpseID   = lootMessage.corpse,
        }
        if settings.TempSettings.NewItemIDs == nil then
            settings.TempSettings.NewItemIDs = {}
        end
        table.insert(settings.TempSettings.NewItemIDs, itemID)
        infoMsg = {
            Lookup = 'loot.RegisterActors()',
            Action = action,
            RuleType = section,
            Rule = rule,
            Item = itemName,
        }
        Logger.Info(guiLoot.console, infoMsg)
        -- LNS.NewItemsCount = LNS.NewItemsCount + 1
        LNS.NewItemsCount = #settings.TempSettings.NewItemIDs or 0
        if settings.TempSettings.NewItemData[itemID] == nil then
            settings.TempSettings.NewItemData[itemID] = itemDetails
        end
        if settings.Settings.AutoShowNewItem then
            LNS.showNewItem = true
        end
    elseif action == 'ItemsDB_UPDATE' and who ~= settings.MyName then
        -- loot.LoadItemsDB()
    end

    -- Notify modules of loot setting changes
end

function LNS_ACTORS.RegisterActors()
    LNS_ACTORS.lootActor = Actors.register('lootnscoot', function(message)
        local success, result = pcall(callback, message)
        if not success then
            Logger.Info(guiLoot.console, string.format('Actor callback failed: %s', result))
        end
    end)
end

function LNS_ACTORS.Send(message, mailbox)
    message.Server = settings.EqServer
    if mailbox == 'loot_module' then
        LNS_ACTORS.lootActor:send({ mailbox = mailbox, script = LNS.DirectorScript, }, message)
    elseif mailbox == 'looted' then
        LNS_ACTORS.lootActor:send({ mailbox = mailbox, script = LNS.DirectorLNSPath or 'lootnscoot', }, message)
    else
        LNS_ACTORS.lootActor:send({ mailbox = 'lootnscoot', script = LNS.DirectorLNSPath or 'lootnscoot', }, message)
    end
end

function LNS_ACTORS.SendMySettings()
    LNS.Boxes[settings.MyName] = settings.Settings
    LNS_ACTORS.Send({
        who             = settings.MyName,
        action          = 'sendsettings',
        settings        = settings.Settings,
        CorpsesToIgnore = LNS.lootedCorpses or {},
        CombatLooting   = settings.Settings.CombatLooting,
        CorpseRadius    = settings.Settings.CorpseRadius,
        LootMyCorpse    = settings.Settings.LootMyCorpse,
        IgnoreNearby    = settings.Settings.IgnoreMyNearCorpses,
        Server          = settings.EqServer,
    })

    LNS.Boxes[settings.MyName] = settings.Settings

    settings.TempSettings.LastSent = os.time()
end

function LNS_ACTORS.FinishedLooting()
    if LNS.Mode == 'directed' then
        LNS_ACTORS.Send({
            Subject = 'done_looting',
            Who = settings.MyName,
            LNSSettings = settings.Settings,
            CorpsesToIgnore = LNS.lootedCorpses or {},
            CombatLooting = settings.Settings.CombatLooting,
            CorpseRadius = settings.Settings.CorpseRadius,
            LootMyCorpse = settings.Settings.LootMyCorpse,
            IgnoreNearby = settings.Settings.IgnoreMyNearCorpses,
        }, 'loot_module')
    end
    LNS.LootNow = false
    LNS.IsLooting = false
end

function LNS_ACTORS.InformProcessing()
    if LNS.Mode == 'directed' then
        Logger.Info(guiLoot.console, "\ayInforming \ax\aw[\at%s\ax\aw]\ax that I am \agProcessing.", LNS.DirectorScript)
        LNS_ACTORS.Send({
            Subject = "processing",
            Who = settings.MyName,
            LNSSettings = settings.Settings,
            Server = settings.EqServer,
            CorpsesToIgnore = LNS.lootedCorpses or {},
            CombatLooting = settings.Settings.CombatLooting,
            CorpseRadius = settings.Settings.CorpseRadius,
            LootMyCorpse = settings.Settings.LootMyCorpse,
            IgnoreNearby = settings.Settings.IgnoreMyNearCorpses,
        }, 'loot_module')
    end
end

function LNS_ACTORS.DoneProcessing()
    if LNS.Mode == 'directed' then
        Logger.Info(guiLoot.console, "\ayInforming \ax\aw[\at%s\ax\aw]\ax that I am \agDone Processing.", LNS.DirectorScript)
        LNS_ACTORS.Send({
            Subject = "done_processing",
            Who = settings.MyName,
            Server = settings.EqServer,
            LNSSettings = settings.Settings,
            CorpsesToIgnore = LNS.lootedCorpses or {},
            CombatLooting = settings.Settings.CombatLooting,
            CorpseRadius = settings.Settings.CorpseRadius,
            LootMyCorpse = settings.Settings.LootMyCorpse,
            IgnoreNearby = settings.Settings.IgnoreMyNearCorpses,
        }, 'loot_module')
    end
end

return LNS_ACTORS
