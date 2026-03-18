--!strict

local Types = require("../Types")

type ExplorerFrame = Types.ExplorerFrame
type Manager = Types.Manager

local RULER_POOL_SIZE = 20
local rulerPool: {GuiObject} = {}

local RulerPool = {}

function RulerPool.fillToLimit(Manager: Manager)
	if #rulerPool >= RULER_POOL_SIZE then return end
	local framesToCreate = RULER_POOL_SIZE - #rulerPool
	for _ = 1, framesToCreate do
		local ruler = Instance.new("Frame")
		ruler.Name = "StickyRuler"
		ruler.BorderSizePixel = 0

		table.insert(rulerPool, ruler)
	end
end

function RulerPool.getRuler(Manager: Manager): Frame
	if #rulerPool == 0 then
		RulerPool.fillToLimit(Manager)
	end
	return table.remove(rulerPool) :: Frame
end

function RulerPool.releaseRuler(Manager: Manager, frame: ExplorerFrame)
	local state = Manager.WidgetState
	local frameWorld = state.FrameWorld
	local components = Manager.Components

	local ruler = frameWorld:get(frame, components.FRAMEWORLD_Ruler)
	if not ruler then return end

	--ruler.Visible = false
	ruler.Size = UDim2.fromOffset(0, 0)
	ruler.Parent = nil
	frameWorld:remove(frame, components.FRAMEWORLD_Ruler)
	table.insert(rulerPool, ruler)
end

function RulerPool.assignRuler(Manager: Manager, frame: ExplorerFrame, frameX: number, stickyY: number, rulerHeight: number, indentWidth: number)
	local state = Manager.WidgetState
	local frameWorld = state.FrameWorld
	local components = Manager.Components

	local ruler = frameWorld:get(frame, components.FRAMEWORLD_Ruler)
	if not ruler then
		local _ruler = RulerPool.getRuler(Manager)
		_ruler.Parent = state.InstanceTree
		frameWorld:set(frame, components.FRAMEWORLD_Ruler, _ruler)
		ruler = _ruler
	end
	local ruler = assert(ruler)

	ruler.Position = UDim2.fromOffset(frameX + indentWidth, stickyY + Manager.getSetting("FrameHeight"))
	ruler.Size = UDim2.fromOffset(1, math.max(0, rulerHeight))
	--ruler.Visible = rulerHeight > 0
end

return RulerPool