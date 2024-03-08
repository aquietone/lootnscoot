local mq = require('mq')
local imgui = require('ImGui')


local guiLoot = {
	SHOW = false,
	openGUI = true,
	shouldDrawGUI = false,
	imported = false,

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
	if guiLoot.console == nil then
		guiLoot.console = imgui.ConsoleWidget.new("##Console")
	end
	if not guiLoot.shouldDrawGUI then return end
	local flags = ImGuiWindowFlags.MenuBar
	imgui.SetNextWindowSize(ImVec2(640, 240), guiLoot.resetPosition and ImGuiCond.Always or ImGuiCond.Once)
	imgui.PushStyleVar(ImGuiStyleVar.WindowPadding, ImVec2(1, 0));

	guiLoot.openGUI, guiLoot.shouldDrawGUI = ImGui.Begin('Looted Items##'..mq.TLO.Me.DisplayName(), guiLoot.openGUI, flags)
	imgui.PopStyleVar()
	if not guiLoot.shouldDrawGUI then
		imgui.End()
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
	imgui.PopStyleVar()

	ImGui.End()
end

function StringTrim(s)
	return s:gsub("^%s*(.-)%s*$", "%1")
end

function guiLoot.EventLoot(line,who,what)
	print(who.." : "..what)
	if guiLoot.console ~= nil then
		local item = mq.TLO.FindItem(what).ItemLink('CLICKABLE')() or what
		if mq.TLO.Plugin('mq2linkdb').IsLoaded() then 
			item = mq.TLO.FindItem(what).ItemLink('CLICKABLE')() or mq.TLO.LinkDB(string.format("=%s",what))()
		end
		local text = string.format('\at%s \axLooted %s',who, item)
		guiLoot.console:AppendText(text)
	end
end

local function bind(...)
	local args = {...}
	if args[1] == 'show' then
		guiLoot.shouldDrawGUI = not guiLoot.shouldDrawGUI
	elseif args[1] == 'stop' then
		guiLoot.SHOW = false
	end
end

local args = {...}
if args[1] == 'start' then
	mq.bind('/looted', bind)
	guiLoot.SHOW = true
	local echo = "\ay[Looted]\ax Commands:\n"
	echo = echo .. "\ay[Looted]\ax /looted show \t\atToggles the Gui\n\ax"
	echo = echo .. "\ay[Looted]\ax /looted stop \t\atExits script\n\ax"
	print(echo)
end

if not mq.TLO.Plugin('mq2linkdb').IsLoaded() then
	mq.cmd('/plugin linkdb load')
end

if guiLoot.imported then
	guiLoot.SHOW = true
end
mq.imgui.init('lootItemsGUI', guiLoot.GUI)
mq.event('echo_Loot', '--#1# have looted a #2#.#*#', guiLoot.EventLoot)
mq.event('echo_Loot2', '--#1# has looted a #2#.#*#', guiLoot.EventLoot)

while guiLoot.SHOW do
	mq.delay(100)
	mq.doevents()
end

return guiLoot