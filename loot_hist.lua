local mq = require('mq')
local imgui = require('ImGui')


local mq = require('mq')
local imgui = require('ImGui')

local guiLoot = {
	SHOW = false,
	openGUI = true,
	shouldDrawGUI = false,
	imported = false,
	hideNames = false,

	---@type ConsoleWidget
	console = nil,
	localEcho = false,
	resetPosition = false,
}

function MakeColorGradient(freq1, freq2, freq3, phase1, phase2, phase3, center, width, length)
	local text = ''

	for i = 1, length do
		local color = IM_COL32(
			math.floor(math.sin(freq1 * i + phase1) * width + center),
			math.floor(math.sin(freq2 * i + phase2) * width + center),
			math.floor(math.sin(freq3 * i + phase3) * width + center)
		)

		text = text .. string.format("\a#%06xx", bit32.band(color, 0xffffff))

		if i % 50 == 0 then
			guiLoot.console:AppendText(text)
			text = ''
		end
	end

	guiLoot.console:AppendText(text)
end

function guiLoot.GUI()
	if not guiLoot.openGUI then return end
	local flags = ImGuiWindowFlags.MenuBar
	ImGui.SetNextWindowSize(260, 300, ImGuiCond.FirstUseEver)
	imgui.PushStyleVar(ImGuiStyleVar.WindowPadding, ImVec2(1, 0));

	guiLoot.openGUI, guiLoot.shouldDrawGUI = ImGui.Begin('Looted Items##'..mq.TLO.Me.DisplayName(), guiLoot.openGUI, flags)
	if not guiLoot.shouldDrawGUI then
		imgui.End()
		imgui.PopStyleVar()
		guiLoot.openGUI = false
		return
	end

	-- Main menu bar
	if imgui.BeginMenuBar() then
		if imgui.BeginMenu('Options') then
			_, guiLoot.console.autoScroll = imgui.MenuItem('Auto-scroll', nil, guiLoot.console.autoScroll)

			imgui.Separator()

			if imgui.MenuItem('Reset Position') then
				guiLoot.resetPosition = true
			end

			imgui.Separator()

			if imgui.MenuItem('Clear Console') then
				guiLoot.console:Clear()
			end

			imgui.Separator()

			if imgui.MenuItem('Close Console') then
				guiLoot.shouldDrawGUI = false
				guiLoot.SHOW = false
			end

			imgui.EndMenu()
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

	guiLoot.console:Render(ImVec2(contentSizeX, contentSizeY))
	imgui.PopStyleVar(2)

	ImGui.End()
end

function StringTrim(s)
	return s:gsub("^%s*(.-)%s*$", "%1")
end

function guiLoot.EventLoot(line,who,what)
	if guiLoot.console ~= nil then
		local item = mq.TLO.FindItem(what).ItemLink('CLICKABLE')() or what
		if mq.TLO.Plugin('mq2linkdb').IsLoaded() then 
			item = mq.TLO.FindItem(what).ItemLink('CLICKABLE')() or mq.TLO.LinkDB(string.format("=%s",what))()
		end
		if guiLoot.hideNames then
			if who ~= 'You' then who = mq.TLO.Spawn(string.format("%s",who)).Class.ShortName() end
		end
		local text = string.format('\ao[%s] \at%s \axLooted %s',mq.TLO.Time() ,who, item)
		guiLoot.console:AppendText(text)
	end
end

local function bind(...)
	local args = {...}
	if args[1] == 'show' then
		guiLoot.openGUI = not guiLoot.openGUI
		guiLoot.shouldDrawGUI = not guiLoot.shouldDrawGUI
	elseif args[1] == 'stop' then
		guiLoot.SHOW = false
	elseif args[1] == 'hidenames' then
		guiLoot.hideNames = not guiLoot.hideNames
	end
end

local args = {...}
local function checkArgs(args)
	if args[1] == 'start' then
		mq.bind('/looted', bind)
		guiLoot.SHOW = true

	elseif args[1] == 'hidenames' then
		mq.bind('/looted', bind)
		guiLoot.SHOW = true
		guiLoot.hideNames = true
	else
		return
	end

	local echo = "\ay[Looted]\ax Commands:\n"
	echo = echo .. "\ay[Looted]\ax /looted show \t\t\atToggles the Gui.\n\ax"
	echo = echo .. "\ay[Looted]\ax /looted stop \t\t\atExits script.\n\ax"
	echo = echo .. "\ay[Looted]\ax /looted hidenames \t\atHides names and shows Class instead.\n\ax"
	print(echo)
end

local function init()
	checkArgs(args)
	if not mq.TLO.Plugin('mq2linkdb').IsLoaded() then
		mq.cmd('/plugin linkdb load')
	end

	-- if imported set show to true.
	if guiLoot.imported then
		guiLoot.SHOW = true
	end

	-- initialize the gui
	mq.imgui.init('lootItemsGUI', guiLoot.GUI)

	-- setup events
	mq.event('echo_Loot', '--#1# have looted a #2#.#*#', guiLoot.EventLoot)
	mq.event('echo_Loot2', '--#1# has looted a #2#.#*#', guiLoot.EventLoot)

	-- initialize the console
	if guiLoot.console == nil then
		guiLoot.console = imgui.ConsoleWidget.new("Loot##Console")
	end
end

local function loop()
	while guiLoot.SHOW do
		mq.delay(100)
		mq.doevents()
	end
end

init()
loop()

return guiLoot