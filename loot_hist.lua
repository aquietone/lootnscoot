--[[
	Title: Looted
	Author: Grimmier
	Description:

	Simple output console for looted items and links. 
	can be run standalone or imported into other scripts. 

	Standalone Mode
	/lua run looted start 		-- start in standalone mode
	/lua run looted hidenames 	-- will start with player names hidden and class names used instead.

	Standalone Commands
	/looted show 				-- toggles show hide on window.
	/looted stop 				-- exit sctipt.
	/looted reported			-- prints out a report of items looted by who and qty. 
	/looted hidenames 			-- Toggles showing names or class names. default is class.

	Or you can Import into another Lua.

	Import Mode

	1. place in your scripts folder name it looted.Lua.
	2. local guiLoot = require('looted')
	3. guiLoot.imported = true
	4. guiLoot.openGUI = true|false to show or hide window.
	5. guiLoot.hideNames = true|false toggle masking character names default is true (class).

	* You can export menu items from your lua into the console. 
	* Do this by passing your menu into guiLoot.importGUIElements table. 

	Follow this example export.

	local function guiExport()
		-- Define a new menu element function
		local function myCustomMenuElement()
			if ImGui.BeginMenu('My Custom Menu') then
				-- Add menu items here
				_, guiLoot.console.autoScroll = ImGui.MenuItem('Auto-scroll', nil, guiLoot.console.autoScroll)
				local activated = false
				activated, guiLoot.hideNames = ImGui.MenuItem('Hide Names', activated, guiLoot.hideNames)
				if activated then
					if guiLoot.hideNames then
						guiLoot.console:AppendText("\ay[Looted]\ax Hiding Names\ax")
					else
						guiLoot.console:AppendText("\ay[Looted]\ax Showing Names\ax")
					end
				end
				local act = false
				act, guiLoot.showLinks = ImGui.MenuItem('Show Links', act, guiLoot.showLinks)
				if act then
					guiLoot.linkdb = mq.TLO.Plugin('mq2linkdb').IsLoaded()
					if guiLoot.showLinks then
						if not guiLoot.linkdb then guiLoot.loadLDB() end
						guiLoot.console:AppendText("\ay[Looted]\ax Link Lookup Enabled\ax")
					else
						guiLoot.console:AppendText("\ay[Looted]\ax Link Lookup Disabled\ax")
					end
				end
				ImGui.EndMenu()
			end
		end
		-- Add the custom menu element function to the importGUIElements table
		table.insert(guiLoot.importGUIElements, myCustomMenuElement)
	end

]]
local mq = require('mq')
local imgui = require('ImGui')
local actor = require('actors')

local guiLoot = {
	SHOW = false,
	openGUI = false,
	shouldDrawGUI = false,
	imported = false,
	hideNames = true,
	showLinks = false,
	linkdb = false,

	importGUIElements = {},

	---@type ConsoleWidget
	console = nil,
	localEcho = false,
	resetPosition = false,
	recordData = true,
	UseActors = true,
	winFlags = bit32.bor(ImGuiWindowFlags.MenuBar)
}
local lootTable = {}

---@param names boolean
---@param links boolean
---@param record boolean
function guiLoot.GetSettings(names,links,record)
	if guiLoot.imported then
		guiLoot.hideNames = names
		guiLoot.showLinks = links
		guiLoot.recordData = record
	end
end

function guiLoot.loadLDB()
	if guiLoot.linkdb then return end
	local sWarn = "MQ2LinkDB not loaded, Can't lookup links.\n Attempting to Load MQ2LinkDB"
	guiLoot.console:AppendText(sWarn)
	print(sWarn)
	mq.cmdf("/plugin mq2linkdb noauto")
	guiLoot.linkdb = mq.TLO.Plugin('mq2linkdb').IsLoaded()
end
-- draw any imported exported menus from outside this script.
function drawImportedMenu()
	for _, menuElement in ipairs(guiLoot.importGUIElements) do
		menuElement()
	end
end

function guiLoot.ReportLoot()
	if guiLoot.recordData then
		guiLoot.console:AppendText("\ay[Looted]\at[Loot Report]")
		for looter, lootData in pairs(lootTable) do
			guiLoot.console:AppendText("\at[%s] \ax: ", looter)
			for item, data in pairs(lootData) do
				local itemName = item
				local itemLink = data["Link"]
				local itemCount = data["Count"]
				guiLoot.console:AppendText("\ao\t%s \ax: \ax(%d)", itemLink, itemCount)
			end
		end
	else
		guiLoot.recordData = true
		guiLoot.console:AppendText("\ay[Looted]\ag[Recording Data Enabled]\ax Check back later for Data.")
	end
end

function guiLoot.GUI()
	if not guiLoot.openGUI then return end

	local windowName = 'Looted Items##'..mq.TLO.Me.DisplayName()

	ImGui.SetNextWindowSize(260, 300, ImGuiCond.FirstUseEver)
	--imgui.PushStyleVar(ImGuiStyleVar.WindowPadding, ImVec2(1, 0));

	if guiLoot.imported then windowName = 'Looted Items Local##Imported_'..mq.TLO.Me.DisplayName() end
	guiLoot.openGUI, guiLoot.shouldDrawGUI = ImGui.Begin(windowName, guiLoot.openGUI, guiLoot.winFlags)
	if not guiLoot.openGUI then
		imgui.End()
		--imgui.PopStyleVar()
		guiLoot.shouldDrawGUI = false
		return
	end

	-- Main menu bar
	if imgui.BeginMenuBar() then
		if imgui.BeginMenu('Options') then
			_, guiLoot.console.autoScroll = imgui.MenuItem('Auto-scroll', nil, guiLoot.console.autoScroll)

			local activated = false
			activated, guiLoot.hideNames = imgui.MenuItem('Hide Names', activated, guiLoot.hideNames)
			if activated then
				if guiLoot.hideNames then
					guiLoot.console:AppendText("\ay[Looted]\ax Hiding Names\ax")
				else
					guiLoot.console:AppendText("\ay[Looted]\ax Showing Names\ax")
				end
			end

			local act = false
			act, guiLoot.showLinks = imgui.MenuItem('Show Links', act, guiLoot.showLinks)
			if act then
				guiLoot.linkdb = mq.TLO.Plugin('mq2linkdb').IsLoaded()
				if guiLoot.showLinks then
					if not guiLoot.linkdb then guiLoot.loadLDB() end
					guiLoot.console:AppendText("\ay[Looted]\ax Link Lookup Enabled\ax")
				else
					guiLoot.console:AppendText("\ay[Looted]\ax Link Lookup Disabled\ax")
				end
			end

			local active = false
			active, guiLoot.recordData = imgui.MenuItem('Record Data', active, guiLoot.recordData)
			if active then
				if guiLoot.recordData then
					guiLoot.console:AppendText("\ay[Looted]\ax Recording Data\ax")
				else
					lootTable = {}
					guiLoot.console:AppendText("\ay[Looted]\ax Data Cleared\ax")
				end
			end

			if imgui.MenuItem('View Report') then
				guiLoot.ReportLoot()
			end

			imgui.Separator()

			if imgui.MenuItem('Reset Position') then
				guiLoot.resetPosition = true
			end

			if imgui.MenuItem('Clear Console') then
				guiLoot.console:Clear()
			end

			imgui.Separator()

			if imgui.MenuItem('Close Console') then
				guiLoot.openGUI = false
			end

			if imgui.MenuItem('Exit') then
				if not guiLoot.imported then
					guiLoot.SHOW = false
				else
					guiLoot.openGUI = false
					guiLoot.console:AppendText("\ay[Looted]\ax Can Not Exit in Imported Mode.\ar Closing Window instead.\ax")
				end
			end

			imgui.Separator()

			imgui.Spacing()

			imgui.EndMenu()
		end
		-- inside main menu bar draw section
		if guiLoot.imported and #guiLoot.importGUIElements > 0 then
			drawImportedMenu()
		end
		imgui.EndMenuBar()
	end
	-- End of menu bar

	local footerHeight = imgui.GetStyle().ItemSpacing.y + imgui.GetFrameHeightWithSpacing()

	if imgui.BeginPopupContextWindow() then
		if imgui.Selectable('Clear') then
			guiLoot.console:Clear()
		end
		imgui.EndPopup()
	end

	-- Reduce spacing so everything fits snugly together
	imgui.PushStyleVar(ImGuiStyleVar.ItemSpacing, ImVec2(0, 0))
	local contentSizeX, contentSizeY = imgui.GetContentRegionAvail()
	contentSizeY = contentSizeY - footerHeight

	guiLoot.console:Render(ImVec2(contentSizeX,0))
	imgui.PopStyleVar(1)

	ImGui.End()
end

local function addRule(who, what, link)
	if not lootTable[who] then
		lootTable[who] = {}
	end
	if not lootTable[who][what] then
		lootTable[who][what] = {Count = 0}
	end
	lootTable[who][what]["Link"] = link
	lootTable[who][what]["Count"] = (lootTable[who][what]["Count"] or 0) + 1
end

function guiLoot.RegisterActor()
	guiLoot.actor = actor.register('looted', function(message)
		local lootEntry = message()
		for _,item in ipairs(lootEntry.Items) do
			local link = item.Link
			local what = item.Name
			local who = lootEntry.LootedBy
			if guiLoot.hideNames then
				if who ~= mq.TLO.Me() then who = mq.TLO.Spawn(string.format("%s", who)).Class.ShortName() else who = mq.TLO.Me.Class.ShortName() end
			end

			local text = string.format('\ao[%s] \at%s \ax%s %s', lootEntry.LootedAt, who, item.Action, link)
			guiLoot.console:AppendText(text)
			-- do we want to record loot data?
			if guiLoot.recordData then
				addRule(who, what, link)
			end
		end
	end)
end

function guiLoot.EventLoot(line, who, what)
	local link = ''
	if guiLoot.console ~= nil then
		link = mq.TLO.FindItem(what).ItemLink('CLICKABLE')() or what
		if guiLoot.linkdb and guiLoot.showLinks then
			link = mq.TLO.LinkDB(string.format("=%s",what))() or link
		elseif not guiLoot.linkdb and guiLoot.showLinks then
			guiLoot.loadLDB()
			link = mq.TLO.LinkDB(string.format("=%s",what))() or link
		end
		if guiLoot.hideNames then
			if who ~= 'You' then who = mq.TLO.Spawn(string.format("%s",who)).Class.ShortName() else who = mq.TLO.Me.Class.ShortName() end
		end
		local text = string.format('\ao[%s] \at%s \axLooted %s', mq.TLO.Time(), who, link)
		guiLoot.console:AppendText(text)
		-- do we want to record loot data?
		if not guiLoot.recordData then return end
		addRule(who, what, link)
	end
end

local function bind(...)
	local args = {...}
	if args[1] == 'show' then
		guiLoot.openGUI = not guiLoot.openGUI
		guiLoot.shouldDrawGUI = not guiLoot.shouldDrawGUI
	elseif args[1] == 'stop' then
		guiLoot.SHOW = false
	elseif args[1] == 'clear' then
		lootTable = {}
	elseif args[1] == 'report' then
		guiLoot.openGUI = true
		guiLoot.shouldDrawGUI = true
		guiLoot.ReportLoot()
	elseif args[1] == 'hidenames' then
		guiLoot.hideNames = not guiLoot.hideNames
		if guiLoot.hideNames then
			guiLoot.console:AppendText("\ay[Looted]\ax Hiding Names\ax")
		else
			guiLoot.console:AppendText("\ay[Looted]\ax Showing Names\ax")
		end
	end
end

local function init()
	guiLoot.linkdb = mq.TLO.Plugin('mq2linkdb').IsLoaded()

	-- if imported set show to true.
	if guiLoot.imported then
		guiLoot.SHOW = true
		mq.imgui.init('importedLootItemsGUI', guiLoot.GUI)
	else
		mq.imgui.init('lootItemsGUI', guiLoot.GUI)
	end

	-- setup events
	if guiLoot.UseActors then
		guiLoot.RegisterActor()
	else
		mq.event('echo_Loot', '--#1# ha#*# looted a #2#.#*#', guiLoot.EventLoot)
	end

	-- initialize the console
	if guiLoot.console == nil then
		if guiLoot.imported then
			guiLoot.console = imgui.ConsoleWidget.new("Loot_imported##Imported_Console")
		else
			guiLoot.console = imgui.ConsoleWidget.new("Loot##Console")
		end
	end
end

local args = {...}
local function checkArgs(args)
	init()
	if args[1] == 'start' then
		mq.bind('/looted', bind)
		guiLoot.SHOW = true
		guiLoot.openGUI = true
	elseif args[1] == 'hidenames' then
		mq.bind('/looted', bind)
		guiLoot.SHOW = true
		guiLoot.openGUI = true
		guiLoot.hideNames = true
	else
		return
	end
	local echo = "\ay[Looted]\ax Commands:\n"
	echo = echo .. "\ay[Looted]\ax /looted show   \t\t\atToggles the Gui.\n\ax"
	echo = echo .. "\ay[Looted]\ax /looted report \t\t\atReports loot Data or Enables recording of data if not already.\n\ax"
	echo = echo .. "\ay[Looted]\ax /looted clear  \t\t\atClears Recorded Data.\n\ax"
	echo = echo .. "\ay[Looted]\ax /looted hidenames  \t\atHides names and shows Class instead.\n\ax"
	echo = echo .. "\ay[Looted]\ax /looted stop   \t\t\atExits script.\n\ax"
	print(echo)
	guiLoot.console:AppendText(echo)
end

local function loop()
	while guiLoot.SHOW do
		mq.delay(100)
		mq.doevents()
	end
end
checkArgs(args)
loop()

return guiLoot