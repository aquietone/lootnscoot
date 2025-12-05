-- Ripped from rgmercs/derple
local mq                  = require('mq')
local ImPlot              = require('ImPlot')
local Set                 = require('mq.Set')
local ScrollingPlotBuffer = require('lib.scrolling_plot_buffer')

local Module              = { _version = '0.1a', _name = "Perf", _author = 'Derple', }
Module.__index            = Module
Module.DefaultConfig      = {}
Module.MaxFrameStep       = 5.0
Module.GoalMaxFrameTime   = 0
Module.CurMaxMaxFrameTime = 0
Module.xAxes              = {}
Module.SettingsLoaded     = false
Module.FrameTimingData    = {}
Module.MaxFrameTime       = 0
Module.LastExtentsCheck   = os.clock()
Module.FAQ                = {}
Module.SaveRequested      = nil
Module.SecondsToStore     = 30
Module.EnablePerfMonitoring = false
Module.PlotFillLines      = true

Module.DefaultConfig      = {
    ['SecondsToStore']                         = {
        DisplayName = "Seconds to Store",
        Group = "General",
        Header = "Misc",
        Category = "Misc",
        Tooltip = "The number of Seconds to keep in history.",
        Default = 30,
        Min = 10,
        Max = 120,
        Step = 5,
    },
    ['EnablePerfMonitoring']                   = {
        DisplayName = "Enable Performance Monitoring",
        Group       = "General",
        Header      = "Misc",
        Category    = "Misc",
        Tooltip     = "Enable the Performance Module for advanced testing.",
        Default     = false,
    },
    ['PlotFillLines']                          = {
        DisplayName = "Enable Fill Lines",
        Group = "General",
        Header = "Misc",
        Category = "Misc",
        Tooltip = "Fill in the Plot Lines",
        Default = true,
    },
}

function Module.New()
    local newModule = setmetatable({}, Module)
    return newModule
end

function Module:Init()
    return { self = self, defaults = self.DefaultConfig, }
end

function Module:ShouldRender()
    return Module.EnablePerfMonitoring
end

function Module:Render()
    local pressed

    if os.clock() - self.LastExtentsCheck > 0.01 then
        self.GoalMaxFrameTime = 0
        self.LastExtentsCheck = os.clock()
        for _, data in pairs(self.FrameTimingData) do
            for idx, time in ipairs(data.frameTimes.DataY) do
                -- is this entry visible?
                local visible = data.frameTimes.DataX[idx] > os.clock() - Module.SecondsToStore and
                    data.frameTimes.DataX[idx] < os.clock()
                if visible and time > self.GoalMaxFrameTime then
                    self.GoalMaxFrameTime = math.ceil(time / self.MaxFrameStep) * self.MaxFrameStep
                end
            end
        end
    end

    -- converge on new max recalc min and maxes
    if self.CurMaxMaxFrameTime < self.GoalMaxFrameTime then self.CurMaxMaxFrameTime = self.CurMaxMaxFrameTime + 1 end
    if self.CurMaxMaxFrameTime > self.GoalMaxFrameTime then self.CurMaxMaxFrameTime = self.CurMaxMaxFrameTime - 1 end

    if ImPlot.BeginPlot("Frame Times for LootNScoot") then
        ImPlot.SetupAxes("Time (s)", "Frame Time (ms)")
        ImPlot.SetupAxisLimits(ImAxis.X1, os.clock() - Module.SecondsToStore, os.clock(), ImGuiCond.Always)
        ImPlot.SetupAxisLimits(ImAxis.Y1, 1, self.CurMaxMaxFrameTime, ImGuiCond.Always)

        for _, module in pairs({'lootitem','history'}) do
            if self.FrameTimingData[module] and not self.FrameTimingData[module].mutexLock then
                local framData = self.FrameTimingData[module]

                if framData then
                    ImPlot.PlotLine(module, framData.frameTimes.DataX, framData.frameTimes.DataY,
                        #framData.frameTimes.DataX,
                        Module.PlotFillLines and ImPlotLineFlags.Shaded or ImPlotLineFlags.None,
                        framData.frameTimes.Offset - 1)
                end
            end
        end

        ImPlot.EndPlot()
    end
end

function Module:GiveTime(combat_state)
end

function Module:OnFrameExec(module, frameTime)
    if not Module.EnablePerfMonitoring then return end

    if not self.FrameTimingData[module] then
        self.FrameTimingData[module] = {
            mutexLock = false,
            lastFrame = os.clock(),
            frameTimes =
                ScrollingPlotBuffer:new(),
        }
    end

    self.FrameTimingData[module].lastFrame = os.clock()
    self.FrameTimingData[module].frameTimes:AddPoint(os.clock(), frameTime)
end

function Module:DoGetState()
    if not Module.EnablePerfMonitoring then return "Disabled" end

    return "Enabled"
end

return Module
