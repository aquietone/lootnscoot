--[[
lootnscoot.lua v1.0 - aquietone

This is a port of the RedGuides copy of ninjadvloot.inc with some updates as well.
I may have glossed over some of the events or edge cases so it may have some issues
around things like:
- lore items
- full inventory
- not full inventory but no slot large enough for an item
- ...
Or those things might just work, I just haven't tested it very much using lvl 1 toons
on project lazarus.

This script can be used in two ways:
    1. Included within a larger script using require, for example if you have some KissAssist-like lua script:
        To loot mobs, call lootutils.lootMobs():

            local mq = require 'mq'
            local lootutils = require 'lootnscoot'
            while true do
                lootutils.lootMobs()
                mq.delay(1000)
            end
        
        lootUtils.lootMobs() will run until it has attempted to loot all corpses within the defined radius.

        To sell to a vendor, call lootutils.sellStuff():

            local mq = require 'mq'
            local lootutils = require 'lootnscoot'
            local doSell = false
            local function binds(...)
                local args = {...}
                if args[1] == 'sell' then doSell = true end
            end
            mq.bind('/myscript', binds)
            while true do
                lootutils.lootMobs()
                if doSell then lootutils.sellStuff() doSell = false end
                mq.delay(1000)
            end

        lootutils.sellStuff() will run until it has attempted to sell all items marked as sell to the targeted vendor.

        Note that in the above example, loot.sellStuff() isn't being called directly from the bind callback.
        Selling may take some time and includes delays, so it is best to be called from your main loop.

        Optionally, configure settings using:
            Set the radius within which corpses should be looted (radius from you, not a camp location)
                lootutils.CorpseRadius = number
            Set whether loot.ini should be updated based off of sell item events to add manually sold items.
                lootutils.AddNewSales = boolean
            Set your own instance of Write.lua to configure a different prefix, log level, etc.
                lootutils.logger = Write
            Several other settings can be found in the "loot" table defined in the code.

    2. Run as a standalone script:
        /lua run lootnscoot standalone
            Will keep the script running, checking for corpses once per second.
        /lua run lootnscoot once
            Will run one iteration of loot.lootMobs().
        /lua run lootnscoot sell
            Will run one iteration of loot.sellStuff().

The script will setup a bind for "/lootutils":
    /lootutils <action> "${Cursor.Name}"
        Set the loot rule for an item. "action" may be one of:
            - Keep
            - Bank
            - Sell
            - Tribute (Not Implemented)
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
    /lootutils sell
        Runs lootutils.sellStuff() one time

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

This script depends on having Write.lua in your lua/lib folder.
    https://gitlab.com/Knightly1/knightlinc/-/blob/master/Write.lua 

This does not include the buy routines from ninjadvloot. It does include the sell routines
but lootly sell routines seem more robust than the code that was in ninjadvloot.inc.
The forage event handling also does not handle fishing events like ninjadvloot did.
There is also no flag for combat looting. It will only loot if no mobs are within the radius.

]]

---@type Mq
local mq = require 'mq'
local success, Write = pcall(require, 'lib.Write')
if not success then printf('\arERROR: Write.lua could not be loaded\n%s\ax', Write) return end
local eqServer = string.gsub(mq.TLO.EverQuest.Server(),' ','_')
local eqChar = mq.TLO.Me.Name()
local version = 1.5
-- Public default settings, also read in from Loot.ini [Settings] section
local loot = {
	logger = Write,
	Version = '"'..tostring(version)..'"',
	LootFile = mq.configDir .. '/Loot.ini',
	SettingsFile = mq.configDir.. '/LootNScoot_'..eqServer..'_'..eqChar..'.ini',
	GlobalLootOn = true,        -- Enable Global Loot Items.
	CombatLooting = false,      -- Enables looting during combat. Not recommended on the MT
	CorpseRadius = 100,         -- Radius to activly loot corpses
	MobsTooClose = 40,          -- Don't loot if mobs are in this range.
	SaveBagSlots = 3,           -- Number of bag slots you would like to keep empty at all times. Stop looting if we hit this number
	TributeKeep = false,        -- Keep items flagged Tribute
	MinTributeValue = 100,      -- Minimun Tribute points to keep item if TributeKeep is enabled.
	MinSellPrice = -1,          -- Minimum Sell price to keep item. -1 = any
	StackPlatValue = 0,         -- Minimum sell value for full stack
	StackableOnly = false,      -- Only loot stackable items
	AlwaysEval = false,         -- Re-Evaluate all *Non Quest* items. useful to update loot.ini after changing min sell values.
	BankTradeskills = true,     -- Toggle flagging Tradeskill items as Bank or not.
	DoLoot = true,              -- Enable auto looting in standalone mode
	LootForage = true,          -- Enable Looting of Foraged Items
	LootNoDrop = false,         -- Enable Looting of NoDrop items.
	LootQuest = false,          -- Enable Looting of Items Marked 'Quest', requires LootNoDrop on to loot NoDrop quest items
	DoDestroy = false,          -- Enable Destroy functionality. Otherwise 'Destroy' acts as 'Ignore'
	AlwaysDestroy = false,      -- Always Destroy items to clean corpese Will Destroy Non-Quest items marked 'Ignore' items REQUIRES DoDestroy set to true
	QuestKeep = 10,             -- Default number to keep if item not set using Quest|# format.
	LootChannel = "dgt",        -- Channel we report loot to.
	ReportLoot = true,          -- Report loot items to group or not.
	SpamLootInfo = false,       -- Echo Spam for Looting
	LootForageSpam = false,     -- Echo spam for Foraged Items
	AddNewSales = true,         -- Adds 'Sell' Flag to items automatically if you sell them while the script is running.
	GMLSelect = true,
	ExcludeBag1 = "Extraplanar Trade Satchel", -- Name of Bag to ignore items in when selling
	NoDropDefaults = "Quest|Keep|Ignore",
	LootLagDelay = 0,           -- not implimented yet
	CorpseRotTime = "440s",     -- not implimented yet
	Terminate = true,
}
loot.logger.prefix = 'lootnscoot'

-- Internal settings
local lootData, cantLootList = {}, {}
local doSell, doTribute, areFull = false, false, false
local cantLootID = 0
-- Constants
local spawnSearch = '%s radius %d zradius 50'
-- If you want destroy to actually loot and destroy items, change DoDestroy=false to DoDestroy=true in the Settings Ini.
-- Otherwise, destroy behaves the same as ignore.
local shouldLootActions = {Keep=true, Bank=true, Sell=true, Destroy=false, Ignore=false, Tribute=false}
local validActions = {keep='Keep',bank='Bank',sell='Sell',ignore='Ignore',destroy='Destroy',quest='Quest', tribute='Tribute'}
local saveOptionTypes = {string=1,number=1,boolean=1}

-- FORWARD DECLARATIONS

local eventForage, eventSell, eventCantLoot

-- UTILITIES

local function writeSettings()
	for option,value in pairs(loot) do
		local valueType = type(value)
		if saveOptionTypes[valueType] then
			mq.cmdf('/ini "%s" "%s" "%s" "%s"', loot.SettingsFile, 'Settings', option, value)
		end
	end
end

local function split(input, sep)
	if sep == nil then
		sep = "|"
	end
	local t={}
	for str in string.gmatch(input, "([^"..sep.."]+)") do
		table.insert(t, str)
	end
	return t
end

local function loadSettings()
	local iniSettings = mq.TLO.Ini.File(loot.SettingsFile).Section('Settings')
	local keyCount = iniSettings.Key.Count()
	for i=1,keyCount do
		local key = iniSettings.Key.KeyAtIndex(i)()
		local value = iniSettings.Key(key).Value()
		if key == 'Version' then
			loot[key] = tostring(value)
		elseif value == 'true' or value == 'false' then
			loot[key] = value == 'true' and true or false
		elseif tonumber(value) then
			loot[key] = tonumber(value)
		else
			loot[key] = value
		end
	end
	if tonumber(loot.Version) < tonumber(version) then
		loot.Version = tostring(version)
		print('Updating Settings File to Version '..tostring(version))
		writeSettings()
	end
	shouldLootActions.Destroy = loot.DoDestroy
	shouldLootActions.Tribute = loot.TributeKeep
end

local function checkCursor()
	local currentItem = nil
	while mq.TLO.Cursor() do
		-- can't do anything if there's nowhere to put the item, either due to no free inventory space
		-- or no slot of appropriate size
		if mq.TLO.Me.FreeInventory() == 0 or mq.TLO.Cursor() == currentItem then
			if loot.SpamLootInfo then loot.logger.Debug('Inventory full, item stuck on cursor') end
			mq.cmd('/autoinv')
			return
		end
		currentItem = mq.TLO.Cursor()
		mq.cmd('/autoinv')
		mq.delay(100)
	end
end

local function navToID(spawnID)
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

local function addRule(itemName, section, rule)
	if not lootData[section] then
		lootData[section] = {}
	end
	lootData[section][itemName] = rule
	mq.cmdf('/ini "%s" "%s" "%s" "%s"', loot.LootFile, section, itemName, rule)
end

local function lookupIniLootRule(section, key)
	return mq.TLO.Ini.File(loot.LootFile).Section(section).Key(key).Value()
end
-- moved this function up so we can report Quest Items.
local reportPrefix = '/%s \a-t[\ax\ayLootUtils\ax\a-t]\ax '
local function report(message, ...)
	if loot.ReportLoot then
		local prefixWithChannel = reportPrefix:format(loot.LootChannel)
		mq.cmdf(prefixWithChannel .. message, ...)
	end
end

local function getRule(item)
	local itemName = item.Name()
	local lootDecision = 'Keep'
	local tradeskill = item.Tradeskills()
	local sellPrice = item.Value() and item.Value()/1000 or 0
	local stackable = item.Stackable()
	local tributeValue = item.Tribute()
	local firstLetter = itemName:sub(1,1):upper()
	local stackSize = item.StackSize()
	local countHave = mq.TLO.FindItemCount(string.format("%s",itemName))() + mq.TLO.FindItemBankCount(string.format("%s",itemName))()
	local qKeep = 0
	
	lootData[firstLetter] = lootData[firstLetter] or {}
	lootData[firstLetter][itemName] = lootData[firstLetter][itemName] or lookupIniLootRule(firstLetter, itemName)
	-- Re-Evaluate the settings if AlwaysEval is on.
	if loot.AlwaysEval and not string.find(lootData[firstLetter][itemName],'Quest') then
		local oldDecision = lootData[firstLetter][itemName] -- whats on file
		local resetDecision = 'NULL'
		-- If sell price changed and item doesn't meet the new value re-evalute it otherwise keep it set to sell
		if oldDecision == 'Sell' and not stackable and sellPrice < loot.MinSellPrice then resetDecision = 'NULL' else resetDecision = oldDecision end
		-- Do the same for stackable items.
		if oldDecision == 'Sell' and stackable and (loot.StackPlatValue > 0 and sellPrice*stackSize > loot.StackPlatValue) then resetDecision = 'NULL' else resetDecision = oldDecision end
		-- if tribute minimum settings value changed re-evaluate
		if oldDecision == 'Tribute' and tributeValue < loot.MinTributeValue then resetDecision = 'NULL' else resetDecision = oldDecision end
		-- if banking tradeskills settings changed re-evaluate
		if oldDecision == 'Bank' and not loot.BankTradeskills then resetDecision = 'NULL' else resetDecision = oldDecision end
		if oldDecision == 'Keep' then resetDecision = oldDecision end -- do nothing with items set to keep *May change this later*
		if oldDecision == 'Ignore' then resetDecision = 'NULL' end -- reevaluate ignored items
		if oldDecision == 'Destroy' then resetDecision = 'Destroy' end -- do nothing with items set to destroy
		lootData[firstLetter][itemName] = resetDecision -- pass value on to next check. Items marked 'NULL' will be treated as new and evaluated properly.
	end
	if lootData[firstLetter][itemName] == 'NULL' then
		if tradeskill and loot.BankTradeskills then lootDecision = 'Bank' end
		if sellPrice < loot.MinSellPrice then lootDecision = 'Ignore' end
		if not stackable and loot.StackableOnly then lootDecision = 'Ignore' end
		if loot.StackPlatValue > 0 and sellPrice*stackSize < loot.StackPlatValue then lootDecision = 'Ignore' end
		-- set Tribute flag if tribute value is greater than minTributeValue and the sell price is less than min sell price or has no value
		if tributeValue >= loot.MinTributeValue and (sellPrice < loot.MinSellPrice or sellPrice == 0) then lootDecision = 'Tribute' end
		addRule(itemName, firstLetter, lootDecision)
	end
	-- Check if item marked Quest
	if string.find(lootData[firstLetter][itemName],'Quest') then
		local qVal = 'Ignore'
		-- do we want to loot quest items?
		if loot.LootQuest then
			--look to see if Quantity attached to Quest|qty
			local _, position = string.find(lootData[firstLetter][itemName], '|')
			if position then qKeep = tonumber(string.sub(lootData[firstLetter][itemName], position + 1)) else qKeep = 0 end
			-- if Quantity is tied to the entry then use that otherwise use default Quest Keep Qty.
			if qKeep == 0 then
				qKeep = loot.QuestKeep
			end
			-- If we have less than we want to keep loot it.
			if countHave < tonumber(qKeep) then
				qVal = 'Keep'
			end
			if loot.AlwaysDestroy and qVal == 'Ignore' then qVal = 'Destroy' end
		end
		return qVal,qKeep
	end
	if loot.AlwaysDestroy and lootData[firstLetter][itemName] == 'Ignore' then return 'Destroy',0 end
	return lootData[firstLetter][itemName],0
end

-- EVENTS

local itemNoValue = nil
local function eventNovalue(line, item)
	itemNoValue = item
end

local function setupEvents()
	mq.event("CantLoot", "#*#may not loot this corpse#*#", eventCantLoot)
	mq.event("Sell", "#*#You receive#*# for the #1#(s)#*#", eventSell)
	if loot.LootForage then
		mq.event("ForageExtras", "Your forage mastery has enabled you to find something else!", eventForage)
		mq.event("Forage", "You have scrounged up #*#", eventForage)
	end
	mq.event("Novalue", "#*#give you absolutely nothing for the #1#.#*#", eventNovalue)
end

-- BINDS

local function commandHandler(...)
	local args = {...}
	if #args == 1 then
		if args[1] == 'sell' and not loot.Terminate then
			doSell = true
		elseif args[1] == 'reload' then
			lootData = {}
			loadSettings()
			loot.Terminate = false
			loot.logger.Info("Reloaded Settings And Loot Files")
		elseif args[1] == 'bank' then
			loot.bankStuff()
		elseif args[1] == 'tribute' then
			doTribute = true
		elseif args[1] == 'loot' then
			loot.lootMobs()
		elseif args[1] == 'tsbank' then
			loot.markTradeSkillAsBank()
		elseif validActions[args[1]] and mq.TLO.Cursor() then
			addRule(mq.TLO.Cursor(), mq.TLO.Cursor():sub(1,1), validActions[args[1]])
			loot.logger.Info(string.format("Setting \ay%s\ax to \ay%s\ax", mq.TLO.Cursor(), validActions[args[1]]))
		end
	elseif #args == 2 then
		if args[1] == 'quest' and mq.TLO.Cursor() then
			addRule(mq.TLO.Cursor(),mq.TLO.Cursor():sub(1,1), 'Quest|'..args[2])
			loot.logger.Info(string.format("Setting \ay%s\ax to \ayQuest|%s\ax", mq.TLO.Cursor(), args[2]))
		end
	end
end

local function setupBinds()
	mq.bind('/lootutils', commandHandler)
end

-- LOOTING

local function CheckBags()
	areFull = mq.TLO.Me.FreeInventory() <= loot.SaveBagSlots
end

function eventCantLoot()
	cantLootID = mq.TLO.Target.ID()
end

---@param index number @The current index we are looking at in loot window, 1-based.
---@param doWhat string @The action to take for the item.
---@param button string @The mouse button to use to loot the item. Currently only leftmouseup implemented.
local function lootItem(index, doWhat, button, qKeep)
	loot.logger.Debug('Enter lootItem')
	if not shouldLootActions[doWhat] then return end
	local corpseItem = mq.TLO.Corpse.Item(index)
	local corpseItemID =corpseItem.ID()
	local itemName = corpseItem.Name()
	local itemLink = corpseItem.ItemLink('CLICKABLE')()
	mq.cmdf('/nomodkey /shift /itemnotify loot%s %s', index, button)
	-- Looting of no drop items is currently disabled with no flag to enable anyways
	-- added check to make sure the cursor isn't empty so we can exit the pause early.-- or not mq.TLO.Corpse.Item(index).NoDrop()
	mq.delay(1) -- for good measure.
	mq.delay(5000, function() return mq.TLO.Window('ConfirmationDialogBox').Open() or mq.TLO.Cursor() == nil end)
	if mq.TLO.Window('ConfirmationDialogBox').Open() then mq.cmd('/nomodkey /notify ConfirmationDialogBox Yes_Button leftmouseup') end
	mq.delay(5000, function() return mq.TLO.Cursor() ~= nil or not mq.TLO.Window('LootWnd').Open() end)
	mq.delay(1) -- force next frame
	-- The loot window closes if attempting to loot a lore item you already have, but lore should have already been checked for
	if not mq.TLO.Window('LootWnd').Open() then return end
	if doWhat == 'Destroy' and mq.TLO.Cursor.ID() == corpseItemID then mq.cmd('/destroy') end
	checkCursor()
	if qKeep > 0 and doWhat == 'Keep' then
		local countHave = mq.TLO.FindItemCount(string.format("%s",itemName))() + mq.TLO.FindItemBankCount(string.format("%s",itemName))()
		report("\awQuest Item:\ag %s \awCount:\ao %s \awof\ag %s", itemLink, tostring(countHave), qKeep)
	else
		report('%sing \ay%s\ax', doWhat, itemLink)
	end
	CheckBags()
	if areFull then report('My bags are full, I can\'t loot anymore! Turning OFF Looting until we sell.') end
end

local function lootCorpse(corpseID)
	CheckBags()
	if areFull then return end
	loot.logger.Debug('Enter lootCorpse')
	if mq.TLO.Cursor() then checkCursor() end
	for i=1,3 do
		mq.cmd('/loot')
		mq.delay(1000, function() return mq.TLO.Window('LootWnd').Open() end)
		if mq.TLO.Window('LootWnd').Open() then break end
	end
	mq.doevents('CantLoot')
	mq.delay(3000, function() return cantLootID > 0 or mq.TLO.Window('LootWnd').Open() end)
	if not mq.TLO.Window('LootWnd').Open() then
		if mq.TLO.Target.CleanName() ~= nil then
			loot.logger.Warn(('Can\'t loot %s right now'):format(mq.TLO.Target.CleanName()))
			cantLootList[corpseID] = os.time()
		end
		return
	end
	mq.delay(1000, function() return (mq.TLO.Corpse.Items() or 0) > 0 end)
	local items = mq.TLO.Corpse.Items() or 0
	loot.logger.Debug(('Loot window open. Items: %s'):format(items))
	local corpseName = mq.TLO.Corpse.Name()
	if mq.TLO.Window('LootWnd').Open() and items > 0 then
		if mq.TLO.Corpse.DisplayName() == mq.TLO.Me.DisplayName() then mq.cmd('/lootall') return end -- if its our own corpse just loot it.
		local noDropItems = {}
		local loreItems = {}
		for i=1,items do
			local freeSpace = mq.TLO.Me.FreeInventory()
			local corpseItem = mq.TLO.Corpse.Item(i)
			local itemLink = corpseItem.ItemLink('CLICKABLE')()
			if corpseItem() then
				local itemRule, qKeep = getRule(corpseItem)
				local stackable = corpseItem.Stackable()
				local freeStack = corpseItem.FreeStack()
				if corpseItem.Lore() then
					local haveItem = mq.TLO.FindItem(('=%s'):format(corpseItem.Name()))()
					local haveItemBank = mq.TLO.FindItemBank(('=%s'):format(corpseItem.Name()))()
					if haveItem or haveItemBank or freeSpace <= loot.SaveBagSlots then
						table.insert(loreItems, itemLink)
						lootItem(i,'Ignore','leftmouseup', 0)
					elseif corpseItem.NoDrop() then
						if loot.LootNoDrop then
							lootItem(i, itemRule, 'leftmouseup', qKeep)
						else
							table.insert(noDropItems, itemLink)
							lootItem(i,'Ignore','leftmouseup',0)
						end
					else
						lootItem(i, itemRule, 'leftmouseup', qKeep)
					end
				elseif corpseItem.NoDrop() then
					if loot.LootNoDrop then
						lootItem(i, itemRule, 'leftmouseup', qKeep)
					else
						table.insert(noDropItems, itemLink)
						lootItem(i,'Ignore','leftmouseup',0)
					end
				elseif freeSpace > loot.SaveBagSlots or (stackable and freeStack > 0) then
					lootItem(i, itemRule, 'leftmouseup', qKeep)
				end
			end
			mq.delay(1)
			if mq.TLO.Cursor() then checkCursor() end
			mq.delay(1)
			if not mq.TLO.Window('LootWnd').Open() then break end
		end
		if loot.ReportLoot and (#noDropItems > 0 or #loreItems > 0) then
			local skippedItems = '/%s Skipped loots (%s - %s) '
			for _,noDropItem in ipairs(noDropItems) do
				skippedItems = skippedItems .. ' ' .. noDropItem .. ' (nodrop) '
			end
			for _,loreItem in ipairs(loreItems) do
				skippedItems = skippedItems .. ' ' .. loreItem .. ' (lore) '
			end
			mq.cmdf(skippedItems, loot.LootChannel, corpseName, corpseID)
		end
	end
	if mq.TLO.Cursor() then checkCursor() end
	mq.cmd('/nomodkey /notify LootWnd LW_DoneButton leftmouseup')
	mq.delay(3000, function() return not mq.TLO.Window('LootWnd').Open() end)
	-- if the corpse doesn't poof after looting, there may have been something we weren't able to loot or ignored
	-- mark the corpse as not lootable for a bit so we don't keep trying
	if mq.TLO.Spawn(('corpse id %s'):format(corpseID))() then
		cantLootList[corpseID] = os.time()
	end
end

local function corpseLocked(corpseID)
	if not cantLootList[corpseID] then return false end
	if os.difftime(os.time(), cantLootList[corpseID]) > 60 then
		cantLootList[corpseID] = nil
		return false
	end
	return true
end

function loot.lootMobs(limit)
	loot.logger.Debug('Enter lootMobs')
	local deadCount = mq.TLO.SpawnCount(spawnSearch:format('npccorpse', loot.CorpseRadius))()
	loot.logger.Debug(string.format('There are %s corpses in range.', deadCount))
	local mobsNearby = mq.TLO.SpawnCount(spawnSearch:format('xtarhater', loot.MobsTooClose))()
	-- options for combat looting or looting disabled
	if deadCount == 0 or ((mobsNearby > 0 or mq.TLO.Me.Combat()) and not loot.CombatLooting) then return false end
	local corpseList = {}
	for i=1,math.max(deadCount, limit or 0) do
		local corpse = mq.TLO.NearestSpawn(('%d,'..spawnSearch):format(i, 'npccorpse', loot.CorpseRadius))
		table.insert(corpseList, corpse)
		-- why is there a deity check?
	end
	local didLoot = false
	loot.logger.Debug(string.format('Trying to loot %d corpses.', #corpseList))
	for i=1,#corpseList do
		local corpse = corpseList[i]
		local corpseID = corpse.ID()
		if corpseID and corpseID > 0 and not corpseLocked(corpseID) and (mq.TLO.Navigation.PathLength('spawn id '..tostring(corpseID))() or 100) < 60 then
			loot.logger.Debug('Moving to corpse ID='..tostring(corpseID))
			navToID(corpseID)
			corpse.DoTarget()
			lootCorpse(corpseID)
			didLoot = true
			mq.doevents('InventoryFull')
		end
	end
	loot.logger.Debug('Done with corpse list.')
	return didLoot
end

-- SELLING

function eventSell(line, itemName)
	local firstLetter = itemName:sub(1,1):upper()
	if lootData[firstLetter] and lootData[firstLetter][itemName] == 'Sell' then return end
	if lookupIniLootRule(firstLetter, itemName) == 'Sell' then
		lootData[firstLetter] = lootData[firstLetter] or {}
		lootData[firstLetter][itemName] = 'Sell'
		return
	end
	if loot.AddNewSales then
		loot.logger.Info(string.format('Setting %s to Sell', itemName))
		if not lootData[firstLetter] then lootData[firstLetter] = {} end
		lootData[firstLetter][itemName] = 'Sell'
		mq.cmdf('/ini "%s" "%s" "%s" "%s"', loot.LootFile, firstLetter, itemName, 'Sell')
	end
end

local function goToVendor()
	if not mq.TLO.Target() then
		loot.logger.Warn('Please target a vendor')
		return false
	end
	local vendorName = mq.TLO.Target.CleanName()
	
	loot.logger.Info('Doing business with '..vendorName)
	if mq.TLO.Target.Distance() > 15 then
		navToID(mq.TLO.Target.ID())
	end
	return true
end

local function openVendor()
	loot.logger.Debug('Opening merchant window')
	mq.cmd('/nomodkey /click right target')
	loot.logger.Debug('Waiting for merchant window to populate')
	mq.delay(1000, function() return mq.TLO.Window('MerchantWnd').Open() or mq.TLO.Window('TributeMasterWnd').Open() end)
	if not mq.TLO.Window('MerchantWnd').Open() or mq.TLO.Window('TributeMasterWnd').Open() then return false end
	if mq.TLO.Window('TributeMasterWnd').Open() then return true end
	mq.delay(5000, function() return mq.TLO.Merchant.ItemsReceived() end)
	return mq.TLO.Merchant.ItemsReceived()
end

local NEVER_SELL = {['Diamond Coin']=true, ['Celestial Crest']=true, ['Gold Coin']=true, ['Taelosian Symbols']=true, ['Planar Symbols']=true}
local function sellToVendor(itemToSell)
	if NEVER_SELL[itemToSell] then return end
	while mq.TLO.FindItemCount('='..itemToSell)() > 0 do
		if mq.TLO.Window('MerchantWnd').Open() then
			loot.logger.Info('Selling '..itemToSell)
			mq.cmdf('/nomodkey /itemnotify "%s" leftmouseup', itemToSell)
			mq.delay(1000, function() return mq.TLO.Window('MerchantWnd/MW_SelectedItemLabel').Text() == itemToSell end)
			mq.cmd('/nomodkey /shiftkey /notify merchantwnd MW_Sell_Button leftmouseup')
			mq.doevents('eventNovalue')
			if itemNoValue == itemToSell then
				addRule(itemToSell, itemToSell:sub(1,1), 'Ignore')
				itemNoValue = nil
				break
			end
			-- TODO: handle vendor not wanting item / item can't be sold
			mq.delay(1000, function() return mq.TLO.Window('MerchantWnd/MW_SelectedItemLabel').Text() == '' end)
		end
	end
end

function loot.sellStuff()
	if not mq.TLO.Window('MerchantWnd').Open() then
		if not goToVendor() then return end
		if not openVendor() then return end
	end
	
	local totalPlat = mq.TLO.Me.Platinum()
	-- sell any top level inventory items that are marked as well, which aren't bags
	for i=1,10 do
		local bagSlot = mq.TLO.InvSlot('pack'..i).Item
		if bagSlot.Container() == 0 then
			if bagSlot.ID() then
				local itemToSell = bagSlot.Name()
				local sellRule = getRule(bagSlot)
				if sellRule == 'Sell' then sellToVendor(itemToSell) end
			end
		end
	end
	-- sell any items in bags which are marked as sell
	for i=1,10 do
		local bagSlot = mq.TLO.InvSlot('pack'..i).Item
		local containerSize = bagSlot.Container()
		if containerSize and containerSize > 0 then
			for j=1,containerSize do
				local itemToSell = bagSlot.Item(j).Name()
				if itemToSell then
					local sellRule = getRule(bagSlot.Item(j))
					if sellRule == 'Sell' then
						local sellPrice = bagSlot.Item(j).Value() and bagSlot.Item(j).Value()/1000 or 0
						if sellPrice == 0 then
							loot.logger.Warn(string.format('Item \ay%s\ax is set to Sell but has no sell value!', itemToSell))
							else
							sellToVendor(itemToSell)
						end
					end
				end
			end
		end
	end
	mq.flushevents('Sell')
	if mq.TLO.Window('MerchantWnd').Open() then mq.cmd('/nomodkey /notify MerchantWnd MW_Done_Button leftmouseup') end
	local newTotalPlat = mq.TLO.Me.Platinum() - totalPlat
	report('Total plat value sold: \ag%s\ax', newTotalPlat)
	CheckBags()
end

-- TRIBUTEING

local function tributeToVendor(itemToTrib)
	if NEVER_SELL[itemToTrib.Name()] then return end
	while mq.TLO.FindItemCount('='..itemToTrib.Name())() > 0 do
		if mq.TLO.Window('TributeMasterWnd').Open() then
			loot.logger.Info('Tributeing '..itemToTrib.Name())
			mq.cmdf('/nomodkey /itemnotify "%s" leftmouseup', itemToTrib.Name())
			mq.delay(1000, function() return mq.TLO.Window('TributeMasterWnd').Child('TMW_ValueLabel').Text() == itemToTrib.Value.Tribute() end)
			if mq.TLO.Window('TributeMasterWnd').Child('TMW_DonateButton').Enabled() then mq.TLO.Window('TributeMasterWnd').Child('TMW_DonateButton').LeftMouseUp() end
			mq.delay(1000, function() return not mq.TLO.Window('TributeMasterWnd').Child('TMW_DonateButton').Enabled() end)
		end
	end
end

function loot.tributeStuff()
	if not mq.TLO.Window('TributeMasterWnd').Open() then
		if not goToVendor() then return end
		if not openVendor() then return end
	end
	-- Check top level inventory items that are marked as well, which aren't bags
	for i=1,10 do
		local bagSlot = mq.TLO.InvSlot('pack'..i).Item
		if bagSlot.Container() == 0 then
			if bagSlot.ID() then
				local itemToTrib = bagSlot
				local tribRule = getRule(bagSlot)
				if tribRule == 'Tribute' then tributeToVendor(itemToTrib) end
			end
		end
	end
	-- Check items in bags which are marked as tribute
	for i=1,10 do
		local bagSlot = mq.TLO.InvSlot('pack'..i).Item
		local containerSize = bagSlot.Container()
		if containerSize and containerSize > 0 then
			for j=1,containerSize do
				local itemToTrib = bagSlot.Item(j)
				if itemToTrib.ID() then
					local tribRule = getRule(itemToTrib)
					if tribRule == 'Tribute' then
						tributeToVendor(itemToTrib)
					end
				end
			end
		end
	end
	mq.flushevents('Tribute')
	if mq.TLO.Window('TributeMasterWnd').Open() then mq.TLO.Window('TributeMasterWnd').DoClose() end
	CheckBags()
end

-- BANKING

function loot.markTradeSkillAsBank()
	for i=1,10 do
		local bagSlot = mq.TLO.InvSlot('pack'..i).Item
		if bagSlot.Container() == 0 then
			if bagSlot.ID() then
				if bagSlot.Tradeskills() then
					local itemToMark = bagSlot.Name()
					addRule(itemToMark, itemToMark:sub(1,1), 'Bank')
				end
			end
		end
	end
	-- sell any items in bags which are marked as sell
	for i=1,10 do
		local bagSlot = mq.TLO.InvSlot('pack'..i).Item
		local containerSize = bagSlot.Container()
		if containerSize and containerSize > 0 then
			for j=1,containerSize do
				local item = bagSlot.Item(j)
				if item.ID() and item.Tradeskills() then
					local itemToMark = bagSlot.Item(j).Name()
					addRule(itemToMark, itemToMark:sub(1,1), 'Bank')
				end
			end
		end
	end
end

local function bankItem(itemName)
	mq.cmdf('/nomodkey /shiftkey /itemnotify "%s" leftmouseup', itemName)
	mq.delay(100, function() return mq.TLO.Cursor() end)
	mq.cmd('/notify BigBankWnd BIGB_AutoButton leftmouseup')
	mq.delay(100, function() return not mq.TLO.Cursor() end)
end

function loot.bankStuff()
	if not mq.TLO.Window('BigBankWnd').Open() then
		loot.logger.Warn('Bank window must be open!')
		return
	end
	for i=1,10 do
		local bagSlot = mq.TLO.InvSlot('pack'..i).Item
		if bagSlot.Container() == 0 then
			if bagSlot.ID() then
				local itemToBank = bagSlot.Name()
				local bankRule = getRule(bagSlot)
				if bankRule == 'Bank' then bankItem(itemToBank) end
			end
		end
	end
	-- sell any items in bags which are marked as sell
	for i=1,10 do
		local bagSlot = mq.TLO.InvSlot('pack'..i).Item
		local containerSize = bagSlot.Container()
		if containerSize and containerSize > 0 then
			for j=1,containerSize do
				local itemToBank = bagSlot.Item(j).Name()
				if itemToBank then
					local bankRule = getRule(bagSlot.Item(j))
					if bankRule == 'Bank' then bankItem(itemToBank) end
				end
			end
		end
	end
end

-- FORAGING

function eventForage()
	loot.logger.Debug('Enter eventForage')
	-- allow time for item to be on cursor incase message is faster or something?
	mq.delay(1000, function() return mq.TLO.Cursor() end)
	-- there may be more than one item on cursor so go until its cleared
	while mq.TLO.Cursor() do
		local cursorItem = mq.TLO.Cursor
		local foragedItem = cursorItem.Name()
		local forageRule = split(getRule(cursorItem))
		local ruleAction = forageRule[1] -- what to do with the item
		local ruleAmount = forageRule[2] -- how many of the item should be kept
		local currentItemAmount = mq.TLO.FindItemCount('='..foragedItem)()
		-- >= because .. does finditemcount not count the item on the cursor?
		if not shouldLootActions[ruleAction] or (ruleAction == 'Quest' and currentItemAmount >= ruleAmount) then
			if mq.TLO.Cursor.Name() == foragedItem then
				if loot.LootForageSpam then loot.logger.Info('Destroying foraged item '..foragedItem) end
				mq.cmd('/destroy')
				mq.delay(500)
			end
			-- will a lore item we already have even show up on cursor?
			-- free inventory check won't cover an item too big for any container so may need some extra check related to that?
		elseif (shouldLootActions[ruleAction] or currentItemAmount < ruleAmount) and (not cursorItem.Lore() or currentItemAmount == 0) and (mq.TLO.Me.FreeInventory() or (cursorItem.Stackable() and cursorItem.FreeStack())) then
			if loot.LootForageSpam then loot.logger.Info('Keeping foraged item '..foragedItem) end
			mq.cmd('/autoinv')
		else
			if loot.LootForageSpam then loot.logger.Warn('Unable to process item '..foragedItem) end
			break
		end
		mq.delay(50)
	end
end

--

local function processArgs(args)
	if #args == 1 then
		if args[1] == 'sell' then
			loot.sellStuff()
		elseif args[1] == 'once' then
			loot.lootMobs()
		elseif args[1] == 'standalone' then
			loot.Terminate = false
		end
	end
end

local function init(args)
	local iniFile = mq.TLO.Ini.File(loot.SettingsFile)
	if not (iniFile.Exists() and iniFile.Section('Settings').Exists()) then
		writeSettings()
		else
		loadSettings()
	end
	CheckBags()
	setupEvents()
	setupBinds()
	processArgs(args)
end

init({...})

while not loot.Terminate do
	if loot.DoLoot and not areFull then loot.lootMobs() end
	if doSell then loot.sellStuff() doSell = false end
	if doTribute then loot.tributeStuff() doTribute = false end
	mq.doevents()
	mq.delay(1000)
end

return loot