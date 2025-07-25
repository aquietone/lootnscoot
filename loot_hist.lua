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
local mq              = require('mq')
local ImGui           = require('ImGui')
local MyClass         = mq.TLO.Me.Class.ShortName()
local Actors          = require("actors")
local Files           = require("mq.Utils")
local success, Logger = pcall(require, 'lib.Write')

if not success then
	printf('\arERROR: Write.lua could not be loaded\n%s\ax', Logger)
	return
end
local Icons                                                  = require('mq.ICONS')
local MyName                                                 = mq.TLO.Me.CleanName()
local theme, settings                                        = {}, {}
local script                                                 = 'Looted'
local ColorCount, ColorCountConf, StyleCount, StyleCountConf = 0, 0, 0, 0
local ColorCountRep, StyleCountRep                           = 0, 0
local openConfigGUI, locked, zoom                            = false, false, false
local themeFile                                              = mq.configDir .. '/MyThemeZ.lua'
local configFile                                             = string.format('%s/Looted/%s/%s_config.lua', mq.configDir, mq.TLO.EverQuest.Server(), MyName)
local eqServer                                               = string.gsub(mq.TLO.EverQuest.Server(), ' ', '_')

local recordFile                                             = string.format("%s/MyUI/Looted/%s/%s_LootRecord.lua", mq.configDir, mq.TLO.EverQuest.Server(), MyName)
local ZoomLvl                                                = 1.0
local fontSize                                               = 16 -- coming soon adding in the var and table now. usage is commented out for now.
local ThemeName                                              = 'None'
local gIcon                                                  = Icons.MD_SETTINGS
local globalNewIcon                                          = Icons.FA_GLOBE
local globeIcon                                              = Icons.FA_GLOBE
local changed                                                = false

local txtBuffer                                              = {}
local defaults                                               = {
	LoadTheme = 'None',
	Scale = 1.0,
	Zoom = false,
	txtAutoScroll = true,
	bottomPosition = 0,
	lastScrollPos = 0,
	fontSize = 16,
}
local pageSizes                                              = {}
local guiLoot                                                = {
	SHOW              = false,
	openGUI           = false,
	shouldDrawGUI     = false,
	imported          = true,
	hideNames         = false,
	showReport        = false,
	showLinks         = false,
	-- linkdb            = false,
	importGUIElements = {},

	---@type ConsoleWidget
	console           = nil,
	localEcho         = false,
	resetPosition     = false,
	recordData        = true,
	UseActors         = true,
	winFlags          = bit32.bor(ImGuiWindowFlags.MenuBar, ImGuiWindowFlags.NoFocusOnAppearing),
}
local oldStyle                                               = ImGui.GetStyle()
local style                                                  = ImGui.GetStyle()
guiLoot.PastHistory                                          = false
guiLoot.pageSize                                             = 25
local lootTable                                              = {}
guiLoot.TempSettings                                         = {}
guiLoot.SessionLootRecord                                    = {}
guiLoot.TempSettings.FilterHistory                           = ''
guiLoot.ReportLeft                                           = false

local fontSizes                                              = {}
for i = 10, 40 do
	if i % 2 == 0 then
		table.insert(fontSizes, i)
		if i == 12 then
			table.insert(fontSizes, 13) -- this is the default font size so keep it in the list
		end
	end
end

--

---@param names boolean -- hide names or not, used for lootnscoot
---@param record boolean -- record data or not, used for lootnscoot
---@param imported boolean -- imported or not, used for lootnscoot
---@param useactors boolean -- use actors or not, used for lootnscoot
---@param caller string -- caller of the function, used for logging and debugging
---@param report boolean|nil -- report if we are showing the report or not
---@param report_left boolean|nil report skipped items
function guiLoot.GetSettings(names, record, imported, useactors, caller, report, report_left)
	local repVal = report and report or false
	guiLoot.imported = imported
	guiLoot.hideNames = names
	guiLoot.recordData = record
	guiLoot.UseActors = useactors
	guiLoot.caller = caller
	guiLoot.showReport = repVal
	guiLoot.ReportLeft = report_left or (guiLoot.ReportLeft or false)
end

-- draw any imported menus from outside this script.
local function drawImportedMenu()
	if guiLoot.importGUIElements[1] ~= nil then
		guiLoot.importGUIElements[1]()
	end
end

function guiLoot.ReportLoot()
	if guiLoot.recordData then
		guiLoot.showReport = true
		guiLoot.console:AppendText("\ay[Looted]\at[Loot Report]")
		for item, data in pairs(lootTable) do
			local itemName = item
			local looter = data['Who']
			local itemLink = data["Link"]
			local itemCount = data["Count"]
			guiLoot.console:AppendText("\ao%s \ax: \ax(%d)", itemLink, itemCount)
			guiLoot.console:AppendText("\at\t[%s] \ax: ", looter)
		end
	else
		guiLoot.recordData = true
		guiLoot.console:AppendText("\ay[Looted]\ag[Recording Data Enabled]\ax Check back later for Data.")
	end
end

local function getSortedKeys(t)
	local keys = {}
	for k in pairs(t) do
		table.insert(keys, k)
	end
	table.sort(keys)
	return keys
end

local function loadTheme()
	if Files.File.Exists(themeFile) then
		theme = dofile(themeFile)
	else
		theme = require('themes')
	end
	ThemeName = theme.LoadTheme or 'notheme'
end

function guiLoot.LoadHistoricalData(table)
	guiLoot.SessionLootRecord = table or {}
end

local function loadSettings()
	local newSetting = false
	local temp = {}
	if not Files.File.Exists(configFile) then
		mq.pickle(configFile, defaults)
		loadSettings()
	else
		-- Load settings from the Lua config file
		temp = {}
		settings = dofile(configFile) or {}
		if settings[script] == nil then
			settings[script] = {}
			settings[script] = defaults
		end
		temp = settings[script]
	end

	-- if not Files.File.Exists(recordFile) then
	-- 	mq.pickle(recordFile, {})
	-- else
	-- 	LootRecord = dofile(recordFile)
	-- end
	loadTheme()

	for k, v in pairs(defaults) do
		if settings[script][k] == nil then
			settings[script][k] = v
			Logger.Info(nil, "\ay[LOOT]: \atSetting: \ay%s\ao not found in settings file, adding default value \aw[\ag%s\aw].", k, v)
		end
	end

	zoom = settings[script].Zoom ~= nil and settings[script].Zoom or false
	locked = settings[script].locked ~= nil and settings[script].locked or false
	ZoomLvl = settings[script].Scale or 1.0
	ThemeName = settings[script].LoadTheme or 'Default'
	fontSize = settings[script].fontSize or fontSize

	mq.pickle(configFile, settings)

	temp = settings[script]
	for i = 1, 200 do
		if i % 25 == 0 then
			table.insert(pageSizes, i)
		end
	end
end
---comment
---@param themeName string|nil -- name of the theme to load form table
---@return integer, integer -- returns the new counter values
function guiLoot.DrawTheme(themeName)
	if themeName == nil then
		themeName = ThemeName
	end
	local StyleCounter = 0
	local ColorCounter = 0
	if themeName == nil or themeName == 'None' or themeName == 'Default' then return 0, 0 end
	for tID, tData in pairs(theme.Theme) do
		if tData.Name == themeName then
			for pID, cData in pairs(theme.Theme[tID].Color) do
				ImGui.PushStyleColor(ImGuiCol[cData.PropertyName], ImVec4(cData.Color[1], cData.Color[2], cData.Color[3], cData.Color[4]))
				ColorCounter = ColorCounter + 1
			end
			if tData['Style'] ~= nil then
				if next(tData['Style']) ~= nil then
					for sID, sData in pairs(theme.Theme[tID].Style) do
						if sData.Size ~= nil then
							if sData.PropertyName == 'FrameRounding' then
								ImGui.PushStyleVar(ImGuiStyleVar.FrameRounding, 10)
							elseif sData.PropertyName == 'ChildRounding' then
								ImGui.PushStyleVar(ImGuiStyleVar.ChildRounding, 10)
							elseif sData.PropertyName == 'PopupRounding' then
								ImGui.PushStyleVar(ImGuiStyleVar.PopupRounding, 10)
							elseif sData.PropertyName == 'ScrollbarRounding' then
								ImGui.PushStyleVar(ImGuiStyleVar.ScrollbarRounding, 12)
							elseif sData.PropertyName == 'WindowRounding' then
								ImGui.PushStyleVar(ImGuiStyleVar.WindowRounding, 12)
							else
								ImGui.PushStyleVar(ImGuiStyleVar[sData.PropertyName], sData.Size)
							end
							StyleCounter = StyleCounter + 1
						elseif sData.X ~= nil then
							ImGui.PushStyleVar(ImGuiStyleVar[sData.PropertyName], sData.X, sData.Y)
							StyleCounter = StyleCounter + 1
						end
					end
				end
			end
		end
	end
	return ColorCounter, StyleCounter
end

function guiLoot.GUI()
	ColorCount, StyleCount = guiLoot.DrawTheme(ThemeName)

	if guiLoot.openGUI then
		local windowName = 'Looted Items##' .. MyName
		ImGui.SetNextWindowSize(260, 300, ImGuiCond.FirstUseEver)

		if guiLoot.imported then windowName = 'Loot Console##' .. MyName end
		local openGui, show = ImGui.Begin(windowName, true, guiLoot.winFlags)

		if not openGui then
			guiLoot.openGUI = false
			show = false
		end

		if show then
			-- Main menu bar

			if ImGui.BeginMenuBar() then
				-- ImGui.PushStyleVar(ImGuiStyleVar.FramePadding, 4,7)

				if ImGui.BeginMenu('Options##Looted') then
					local activated = false
					_, guiLoot.console.autoScroll = ImGui.MenuItem('Auto-scroll', nil, guiLoot.console.autoScroll)
					_, openConfigGUI = ImGui.MenuItem('Config', nil, openConfigGUI)
					_, guiLoot.hideNames = ImGui.MenuItem('Hide Names', nil, guiLoot.hideNames)
					_, zoom = ImGui.MenuItem('Zoom', nil, zoom)
					_, guiLoot.PastHistory = ImGui.MenuItem('Past History', nil, guiLoot.PastHistory)
					-- if not guiLoot.UseActors then
					-- 	_, guiLoot.showLinks = ImGui.MenuItem('Show Links', nil, guiLoot.showLinks)
					-- end
					if ImGui.MenuItem('Record Data', nil, guiLoot.recordData) then
						if guiLoot.recordData then
							guiLoot.console:AppendText("\ay[Looted]\ax Recording Data\ax")
						else
							lootTable = {}
							guiLoot.console:AppendText("\ay[Looted]\ax Data Cleared\ax")
						end
					end

					if ImGui.MenuItem('View Report') then
						guiLoot.ReportLoot()
						guiLoot.showReport = true
					end

					ImGui.Separator()

					if ImGui.MenuItem('Reset Position') then
						guiLoot.resetPosition = true
					end

					if ImGui.MenuItem('Clear Console') then
						guiLoot.console:Clear()
						txtBuffer = {}
					end

					ImGui.Separator()

					if ImGui.MenuItem('Close Console') then
						guiLoot.openGUI = false
					end

					if ImGui.MenuItem('Exit') then
						if not guiLoot.imported then
							guiLoot.SHOW = false
						else
							guiLoot.openGUI = false
							guiLoot.console:AppendText("\ay[Looted]\ax Can Not Exit in Imported Mode.\ar Closing Window instead.\ax")
						end
					end

					ImGui.Separator()

					ImGui.Spacing()

					ImGui.EndMenu()
				end

				if guiLoot.imported and #guiLoot.importGUIElements > 0 then
					drawImportedMenu()
				end

				if ImGui.BeginMenu('Hide Corpse##') then
					if ImGui.MenuItem('alwaysnpc##') then
						mq.cmdf('/hidecorpse alwaysnpc')
					end
					if ImGui.MenuItem('looted##') then
						mq.cmdf('/hidecorpse looted')
					end
					if ImGui.MenuItem('all##') then
						mq.cmdf('/hidecorpse all')
					end
					if ImGui.MenuItem('none##') then
						mq.cmdf('/hidecorpse none')
					end
					ImGui.EndMenu()
				end

				ImGui.EndMenuBar()

				-- ImGui.PushStyleVar(ImGuiStyleVar.FramePadding, 4,3)
			end
			-- End of menu bar
			ImGui.SetWindowFontScale(ZoomLvl)

			local footerHeight = ImGui.GetStyle().ItemSpacing.y + ImGui.GetFrameHeightWithSpacing()

			if ImGui.BeginPopupContextWindow() then
				if ImGui.Selectable('Clear') then
					guiLoot.console:Clear()
					txtBuffer = {}
				end
				ImGui.EndPopup()
			end

			-- Reduce spacing so everything fits snugly together
			-- imgui.PushStyleVar(ImGuiStyleVar.ItemSpacing, ImVec2(0, 0))
			local contentSizeX, contentSizeY = ImGui.GetContentRegionAvail()
			contentSizeY = contentSizeY - footerHeight

			guiLoot.console:Render(ImVec2(contentSizeX, 0))

			ImGui.SetWindowFontScale(1)
		end

		ImGui.End()
	end

	if guiLoot.showReport then
		guiLoot.lootedReport_GUI()
	end

	if openConfigGUI then
		guiLoot.lootedConf_GUI()
	end

	-- if guiLoot.PastHistory then
	-- 	guiLoot.drawRecord()
	-- end

	if ColorCount > 0 then ImGui.PopStyleColor(ColorCount) end
	if StyleCount > 0 then ImGui.PopStyleVar(StyleCount) end
end

local function evalRule(item)
	if string.find(item, 'Destroy') then
		ImGui.TextColored(0.860, 0.104, 0.104, 1.000, Icons.MD_DELETE)
		if ImGui.IsItemHovered() then
			ImGui.BeginTooltip()
			ImGui.Text("Destroy Item")
			ImGui.EndTooltip()
		end
	elseif string.find(item, 'Quest') then
		ImGui.TextColored(1.000, 0.914, 0.200, 1.000, Icons.MD_SEARCH)
		if ImGui.IsItemHovered() then
			ImGui.BeginTooltip()
			ImGui.Text("Quest Item")
			ImGui.EndTooltip()
		end
	elseif string.find(item, "Tribute") then
		ImGui.TextColored(0.991, 0.506, 0.230, 1.000, Icons.FA_GIFT)
		if ImGui.IsItemHovered() then
			ImGui.BeginTooltip()
			ImGui.Text("Tribute Item")
			ImGui.EndTooltip()
		end
	elseif string.find(item, 'Sell') then
		ImGui.TextColored(0, 1, 0, 1, Icons.MD_ATTACH_MONEY)
		if ImGui.IsItemHovered() then
			ImGui.BeginTooltip()
			ImGui.Text("Sell Item")
			ImGui.EndTooltip()
		end
	elseif string.find(item, 'Keep') then
		ImGui.TextColored(0.916, 0.094, 0.736, 1.000, Icons.MD_FAVORITE_BORDER)
		if ImGui.IsItemHovered() then
			ImGui.BeginTooltip()
			ImGui.Text("Keep Item")
			ImGui.EndTooltip()
		end
	elseif string.find(item, 'Unknown') then
		ImGui.TextColored(0.5, 0.5, 0.5, 1.000, Icons.FA_QUESTION)
		if ImGui.IsItemHovered() then
			ImGui.BeginTooltip()
			ImGui.Text("Not Set")
			ImGui.EndTooltip()
		end
	elseif string.find(item, 'Ask') then
		ImGui.TextColored(0.5, 0.5, 0.9, 1.000, Icons.FA_QUESTION)
		if ImGui.IsItemHovered() then
			ImGui.BeginTooltip()
			ImGui.Text("Not Set")
			ImGui.EndTooltip()
		end
	elseif string.find(item, 'CanUse') then
		ImGui.TextColored(0.4, 0.7, 0.2, 1.000, Icons.FA_USER_O)
		if ImGui.IsItemHovered() then
			ImGui.BeginTooltip()
			ImGui.Text("Can Use Item")
			ImGui.EndTooltip()
		end
	elseif string.find(item, 'Ignore') or string.find(item, 'Left') then
		ImGui.TextColored(0.976, 0.218, 0.244, 1.000, Icons.MD_NOT_INTERESTED)
		if ImGui.IsItemHovered() then
			ImGui.BeginTooltip()
			ImGui.Text("Ignore Item")
			ImGui.EndTooltip()
		end
	elseif string.find(item, 'Bank') then
		ImGui.TextColored(0.162, 0.785, 0.877, 1.000, Icons.MD_ACCOUNT_BALANCE)
		if ImGui.IsItemHovered() then
			ImGui.BeginTooltip()
			ImGui.Text("Bank Item")
			ImGui.EndTooltip()
		end
	else
		ImGui.Text(item)
	end
end

function guiLoot.lootedReport_GUI()
	--- Report Window
	ImGui.SetNextWindowSize(300, 200, ImGuiCond.Appearing)
	if changed and mq.TLO.Plugin('mq2dannet').IsLoaded() and guiLoot.caller == 'lootnscoot' then
		mq.cmdf('/dgae /lootutils reload')
		changed = false
	end
	local openRepGUI, showRepGUI = ImGui.Begin("Loot Report##" .. script, true, bit32.bor(
		ImGuiWindowFlags.NoFocusOnAppearing, ImGuiWindowFlags.NoCollapse))
	if showRepGUI then
		ImGui.SetWindowFontScale(ZoomLvl)
		local sizeX, sizeY = ImGui.GetContentRegionAvail()
		ImGui.BeginTable('##LootReport', 4, bit32.bor(ImGuiTableFlags.Borders, ImGuiTableFlags.ScrollY, ImGuiTableFlags.Resizable, ImGuiTableFlags.RowBg), ImVec2(sizeX, sizeY - 10))
		ImGui.TableSetupScrollFreeze(0, 1)

		ImGui.TableSetupColumn("Item", ImGuiTableColumnFlags.WidthFixed, 150)
		ImGui.TableSetupColumn("Looter(s)", ImGuiTableColumnFlags.WidthFixed, 75)
		ImGui.TableSetupColumn("Count", bit32.bor(ImGuiTableColumnFlags.NoResize, ImGuiTableColumnFlags.WidthFixed), 50)
		ImGui.TableSetupColumn("Tagged", bit32.bor(ImGuiTableColumnFlags.NoResize, ImGuiTableColumnFlags.WidthFixed), 75)
		ImGui.TableHeadersRow()
		if ImGui.BeginPopupContextItem() then
			ImGui.SeparatorText("Tags:")
			ImGui.TextColored(0.523, 0.797, 0.944, 1.000, globeIcon)
			ImGui.SameLine()
			ImGui.Text('Global Item')
			ImGui.TextColored(0.898, 0.777, 0.000, 1.000, Icons.MD_STAR)
			ImGui.SameLine()
			ImGui.Text('Changed Rule')
			ImGui.TextColored(0.860, 0.104, 0.104, 1.000, Icons.MD_DELETE)
			ImGui.SameLine()
			ImGui.Text("Destroy")
			ImGui.TextColored(1.000, 0.914, 0.200, 1.000, Icons.MD_SEARCH)
			ImGui.SameLine()
			ImGui.Text("Quest")
			ImGui.TextColored(0.991, 0.506, 0.230, 1.000, Icons.FA_GIFT)
			ImGui.SameLine()
			ImGui.Text("Tribute")
			ImGui.TextColored(0, 1, 0, 1, Icons.MD_ATTACH_MONEY)
			ImGui.SameLine()
			ImGui.Text("Sell")
			ImGui.TextColored(0.916, 0.094, 0.736, 1.000, Icons.MD_FAVORITE_BORDER)
			ImGui.SameLine()
			ImGui.Text("Keep")
			ImGui.TextColored(0.5, 0.5, 0.5, 1.000, Icons.FA_QUESTION)
			ImGui.SameLine()
			ImGui.Text("Unknown")
			ImGui.SameLine()
			ImGui.TextColored(0.5, 0.9, 0.5, 1.000, Icons.FA_QUESTION)
			ImGui.SameLine()
			ImGui.Text("Ask")
			ImGui.SameLine()
			ImGui.TextColored(0.4, 0.7, 0.2, 1.000, Icons.FA_USER_O)
			ImGui.SameLine()
			ImGui.Text("CanUse")
			ImGui.EndPopup()
		end
		local row = 1
		-- for looter, lootData in pairs(lootTable) do

		local sortedKeys = getSortedKeys(lootTable)
		for _, key in ipairs(sortedKeys) do
			local data = lootTable[key]
			local item = key
			local looter = data['Who']
			local itemName = key
			local itemLink = data["Link"]
			local itemCount = data["Count"]
			local itemEval = data.Eval or 'Unknown'
			local itemNewEval = data["NewEval"] or 'NONE'
			local globalItem = false
			local globalNew = false
			globalItem = string.find(itemEval, 'Global') ~= nil
			if globalItem then
				itemName = string.gsub(itemName, 'Global ', '')
			end
			globalNew = string.find(itemNewEval, 'Global') ~= nil
			itemEval = string.find(itemEval, "Quest") and 'Quest' or itemEval
			local rowID = string.format("%s_%d", item, row)
			ImGui.PushID(rowID)

			ImGui.TableNextRow()

			ImGui.TableSetColumnIndex(0)
			-- ImGui.BeginGroup()
			if string.find(itemName, "*") then
				itemName = string.gsub(itemName, "*", "")
			end

			if ImGui.Selectable(itemName .. "##" .. rowID, false, ImGuiSelectableFlags.SpanAllColumns) then
				mq.cmdf('/executelink %s', itemLink)
			end

			if guiLoot.imported then
				if ImGui.BeginPopupContextItem(rowID) then
					if string.find(item, "*") then
						itemName = string.gsub(item, "*", '')
					end
					ImGui.Text(itemName)
					ImGui.Separator()
					ImGui.PushStyleColor(ImGuiCol.Text, ImVec4(1, 1, 0, 0.75))
					if ImGui.BeginMenu('Normal Item Settings##' .. rowID) then
						local tmpName = string.gsub(itemName, "*", "")
						if ImGui.Selectable('Keep##' .. rowID) then
							mq.cmdf('/lootutils keep "%s"', tmpName)
							lootTable[item]["NewEval"] = 'Keep'
							changed = true
						end
						if ImGui.Selectable('Quest##' .. rowID) then
							mq.cmdf('/lootutils quest "%s"', tmpName)
							lootTable[item]["NewEval"] = 'Quest'
							changed = true
						end
						if ImGui.Selectable('Sell##' .. rowID) then
							mq.cmdf('/lootutils sell "%s"', tmpName)
							lootTable[item]["NewEval"] = 'Sell'
							changed = true
						end
						if ImGui.Selectable('Tribute##' .. rowID) then
							mq.cmdf('/lootutils tribute "%s"', tmpName)
							lootTable[item]["NewEval"] = 'Tribute'
							changed = true
						end
						if ImGui.Selectable('Destroy##' .. rowID) then
							mq.cmdf('/lootutils destroy "%s"', tmpName)
							lootTable[item]["NewEval"] = 'Destroy'
							changed = true
						end
						ImGui.EndMenu()
					end
					ImGui.PopStyleColor()
					ImGui.PushStyleColor(ImGuiCol.Text, ImVec4(0.523, 0.797, 0.944, 1.000))
					if ImGui.BeginMenu('Global Item Settings##' .. rowID) then
						local tmpName = string.gsub(itemName, "*", "")
						if ImGui.Selectable('Global Keep##' .. rowID) then
							mq.cmdf('/lootutils globalitem keep "%s"', tmpName)
							lootTable[item]["NewEval"] = 'Global Keep'
							changed = true
						end
						if ImGui.Selectable('Global Quest##' .. rowID) then
							mq.cmdf('/lootutils globalitem quest "%s"', tmpName)
							lootTable[item]["NewEval"] = 'Global Quest'
							changed = true
						end
						if ImGui.Selectable('Global Sell##' .. rowID) then
							mq.cmdf('/lootutils globalitem sell "%s"', tmpName)
							lootTable[item]["NewEval"] = 'Global Sell'
							changed = true
						end
						if ImGui.Selectable('Global Tribute##' .. rowID) then
							mq.cmdf('/lootutils globalitem tribute "%s"', tmpName)
							lootTable[item]["NewEval"] = 'Global Tribute'
							changed = true
						end
						if ImGui.Selectable('Global Destroy##' .. rowID) then
							mq.cmdf('/lootutils globalitem destroy "%s"', tmpName)
							lootTable[item]["NewEval"] = 'Global Destroy'
							changed = true
						end
						ImGui.EndMenu()
					end
					ImGui.PopStyleColor()
					ImGui.EndPopup()
				end
			else
				if ImGui.IsItemHovered() then
					ImGui.BeginTooltip()
					ImGui.Text("Left Click to open item link")
					ImGui.EndTooltip()
				end
			end

			ImGui.TableSetColumnIndex(1)
			ImGui.Text(looter)
			ImGui.TableSetColumnIndex(2)
			ImGui.Text("\t%d", itemCount)
			if ImGui.IsItemHovered() then
				ImGui.BeginTooltip()
				if string.find(itemEval, 'Unknown') then
					ImGui.Text("%s Looted: %d", looter, itemCount)
				else
					ImGui.Text("%s %sing: %d", looter, itemEval, itemCount)
				end
				ImGui.EndTooltip()
			end

			ImGui.TableSetColumnIndex(3)
			if itemEval == itemNewEval then itemNewEval = 'NONE' end
			if itemNewEval ~= 'NONE' then
				ImGui.TextColored(0.898, 0.777, 0.000, 1.000, Icons.MD_STAR)
				if ImGui.IsItemHovered() then
					ImGui.BeginTooltip()
					ImGui.TextColored(0.6, 0.6, 0.6, 1, "Old Rule: %s", itemEval)
					ImGui.TextColored(1.000, 0.914, 0.200, 1.000, "New Rule: %s", itemNewEval)
					ImGui.EndTooltip()
				end
				ImGui.SameLine()
				if globalNew then
					ImGui.TextColored(0.523, 0.797, 0.944, 1.000, globalNewIcon)
					if ImGui.IsItemHovered() then
						ImGui.BeginTooltip()
						ImGui.Text("Global Rule")
						ImGui.EndTooltip()
					end
					ImGui.SameLine()
				end
				ImGui.SameLine()
				evalRule(itemNewEval)
			else
				if globalItem then
					ImGui.TextColored(0.523, 0.797, 0.944, 1.000, globeIcon)
					if ImGui.IsItemHovered() then
						ImGui.BeginTooltip()
						ImGui.Text("Global Item")
						ImGui.EndTooltip()
					end
					ImGui.SameLine()
				end
				evalRule(itemEval)
			end

			-- ImGui.Text(data['Eval'])

			ImGui.PopID()
			row = row + 1
		end
		-- end

		ImGui.EndTable()
	end

	ImGui.SetWindowFontScale(1)
	ImGui.End()

	if not openRepGUI then
		guiLoot.showReport = false
	end
end

function guiLoot.lootedConf_GUI()
	local openWin, showConfigGUI = ImGui.Begin("Looted Conf##" .. script, true, bit32.bor(ImGuiWindowFlags.None, ImGuiWindowFlags.AlwaysAutoResize, ImGuiWindowFlags.NoCollapse))
	ImGui.SetWindowFontScale(ZoomLvl)

	if not openWin then
		openConfigGUI = false
	end

	if showConfigGUI then
		ImGui.SeparatorText('Theme')
		ImGui.Text("Cur Theme: %s", ThemeName)
		-- Combo Box Load Theme

		if ImGui.BeginCombo("Load Theme##" .. script, ThemeName) then
			ImGui.SetWindowFontScale(ZoomLvl)
			for k, data in pairs(theme.Theme) do
				local isSelected = data.Name == ThemeName
				if ImGui.Selectable(data.Name, isSelected) then
					theme.LoadTheme = data.Name
					ThemeName = theme.LoadTheme
					settings[script].LoadTheme = ThemeName
				end
			end
			ImGui.EndCombo()
		end

		if ImGui.Button('Reload Theme File') then
			loadTheme()
		end
		--------------------- Sliders ----------------------
		ImGui.SeparatorText('Scaling')
		-- Slider for adjusting zoom level
		local tmpZoom = ZoomLvl
		if ZoomLvl then
			tmpZoom = ImGui.SliderFloat("Text Scale##" .. script, tmpZoom, 0.5, 2.0)
		end
		if ZoomLvl ~= tmpZoom then
			ZoomLvl = tmpZoom
		end

		ImGui.SeparatorText('Save and Close')

		if ImGui.Button('Save and Close##' .. script) then
			openConfigGUI = false
			settings = dofile(configFile)
			settings[script].Scale = ZoomLvl
			settings[script].LoadTheme = ThemeName

			mq.pickle(configFile, settings)
		end
	end

	ImGui.SetWindowFontScale(1)
	ImGui.End()
end

local function addRule(who, what, link, eval, rule)
	if type(eval) ~= 'string' then eval = 'Unknown' end
	if lootTable[what] == nil then
		lootTable[what] = {}
		lootTable[what] = { Count = 0, Who = who, Link = link, Eval = eval or 'Unknown', Rule = rule or 'Unknown', }
	end
	local looters = lootTable[what]['Who'] or ''
	if not string.find(looters, who) then
		lootTable[what]['Who'] = looters .. ', ' .. who
	end
	lootTable[what]["Link"] = link
	lootTable[what]["Eval"] = eval
	lootTable[what]["Count"] = (lootTable[what]["Count"] or 0) + 1
	lootTable[what]['Rule'] = rule or 'Unknown'
end

---comment -- Checks for the last ID number in the table passed. returns the NextID
---@param table table -- the table we want to look up ID's in
---@return number -- returns the NextID that doesn't exist in the table yet.
local function getNextID(table)
	local maxChannelId = 0
	for channelId, _ in pairs(table) do
		local numericId = tonumber(channelId)
		if numericId and numericId > maxChannelId then
			maxChannelId = numericId
		end
	end
	return maxChannelId + 1
end

local function trimCorpseName(corpseName)
	if corpseName == nil then return 'unknown' end
	return corpseName:gsub("'s corpse$", "")
end

function guiLoot.RegisterActor()
	guiLoot.actor = Actors.register('looted', function(message)
		local lootEntry = message()
		if lootEntry.Server ~= eqServer then return end
		for _, item in ipairs(lootEntry.Items) do
			local link = item.Link
			local what = item.Name
			local eval = item.Eval
			local rule = item.Rule
			local corpseName = trimCorpseName(item.CorpseName) or 'unknown'
			local who = lootEntry.LootedBy
			local cantWear = item.cantWear or false
			local actionLabel = item.Eval
			local consoleAction = item.Eval
			--printf("[\ayLOOTED DEBUG\ax] :: \agRecieved Message\ax: Item (\at%s\ax) Action (\at%s\ax) From (\at%s\ax) Eval (\at%s\ax) Rule (\at%s\ax)", what, item.Action, who,item.Eval,item.Rule)

			if guiLoot.hideNames then
				if who ~= mq.TLO.Me.Name() then who = mq.TLO.Spawn(string.format("%s", who)).Class.ShortName() else who = MyClass end
			end
			if guiLoot.recordData and ((item.Action:find('Looted') or item.Action:find('Destroyed')) and ((not item.Action:find('Left') and not item.Action:find("Ask")) or guiLoot.ReportLeft)) then
				addRule(who, what, link, eval, rule)
			end
			if lootEntry.LootedBy ~= MyName then
				if cantWear then
					consoleAction = consoleAction .. ' \ax(\arCant Wear\ax)'
				end
				local text = string.format('\ao[\at%s\ax] \at%s \ax%s %s Corpse \at%s\ax (\at%s\ax)', lootEntry.LootedAt, who, consoleAction, link, corpseName, lootEntry.ID)
				if item.Action == 'Destroyed' then
					text = string.format('\ao[\at%s\ax] \at%s \ar%s \ax%s \axCorpse \at%s\ax (\at%s\ax)', lootEntry.LootedAt, who, string.upper(item.Action), link, corpseName,
						lootEntry.ID)
				end
				guiLoot.console:AppendText(text)
			end
			local recordDate = os.date("%Y-%m-%d")
			if guiLoot.SessionLootRecord == nil then
				guiLoot.SessionLootRecord = {}
			end
			table.insert(guiLoot.SessionLootRecord, {
				Date = recordDate,
				TimeStamp = lootEntry.LootedAt,
				Zone = lootEntry.Zone,
				CorpseName = corpseName,
				Looter = who,
				Item = item.Name,
				Link = link,
				Action = eval and eval or item.Action,
				Rule = rule,
			})
		end
	end)
end

function guiLoot.EventLoot(line, who, what)
	local link = ''
	if guiLoot.console ~= nil then
		link = mq.TLO.FindItem(what).ItemLink('CLICKABLE')() or what
		-- if guiLoot.linkdb and guiLoot.showLinks then
		-- 	---@diagnostic disable-next-line: undefined-field
		-- 	link = mq.TLO.LinkDB(string.format("=%s", what))() or link
		-- elseif not guiLoot.linkdb and guiLoot.showLinks then
		-- 	guiLoot.loadLDB()
		-- 	---@diagnostic disable-next-line: undefined-field
		-- 	link = mq.TLO.LinkDB(string.format("=%s", what))() or link
		-- end
		if guiLoot.hideNames then
			if who ~= 'You' then who = mq.TLO.Spawn(string.format("%s", who)).Class.ShortName() else who = MyClass end
		end
		local text = string.format('\ao[%s][\ayLootedEvent\ax] \at%s \axLooted %s', mq.TLO.Time(), who, link)
		guiLoot.console:AppendText(text)
		local zLine = string.format('\ao[%s][\ayLootedEvent\ax] %s Looted %s', mq.TLO.Time(), who, what)
		local i = getNextID(txtBuffer)
		-- ZOOM Console hack
		if i > 1 then
			if txtBuffer[i - 1].Text == '' then i = i - 1 end
		end
		-- Add the new line to the buffer
		txtBuffer[i] = {
			Text = zLine,
		}
		-- cleanup zoom buffer
		-- Check if the buffer exceeds 1000 lines
		local bufferLength = #txtBuffer
		if bufferLength > 1000 then
			-- Remove excess lines
			for j = 1, bufferLength - 1000 do
				table.remove(txtBuffer, 1)
			end
		end
		-- do we want to record loot data?
		if not guiLoot.recordData then return end
		addRule(who, what, link, "Keep", 'Keep')
	end
end

function guiLoot.init(use_actors, imported, caller)
	guiLoot.imported = imported
	guiLoot.UseActors = true
	guiLoot.caller = caller

	guiLoot.linkdb = false
	-- if imported set show to true.
	if guiLoot.imported then
		guiLoot.SHOW = true
	end
	mq.imgui.init('lootItemsGUI', guiLoot.GUI)

	-- mq.imgui.init('lootConfigGUI', guiLoot.lootedConf_GUI)
	-- mq.imgui.init('lootReportGui', guiLoot.lootedReport_GUI)
	-- setup events

	guiLoot.RegisterActor()
	guiLoot.linkdb = false

	-- print("Using Events")
	-- mq.event('echo_Loot', '--#1# ha#*# looted a #2#.#*#', guiLoot.EventLoot)


	-- initialize the console
	if guiLoot.console == nil then
		guiLoot.console = ImGui.ConsoleWidget.new("Loot_imported##Imported_Console")
	end

	-- load settings
	loadSettings()
	-- loop()
end

return guiLoot
