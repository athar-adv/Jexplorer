local Props = require(script.ClassProps)

type Create<Name, PropsType, Type> = (Name) -> (PropsType) -> (Type)
type Create_Overloaded = 
	& Create<"Frame", Props.Frame, Frame>
	& Create<"ScrollingFrame", Props.ScrollingFrame, ScrollingFrame>
	& Create<"TextLabel", Props.TextLabel, TextLabel>
	& Create<"TextButton", Props.TextButton, TextButton>
	& Create<"TextBox", Props.TextBox, TextBox>
	& Create<"ImageLabel", Props.ImageLabel, ImageLabel>
	& Create<"ImageButton", Props.ImageButton, ImageButton>
	& Create<"VideoFrame", Props.VideoFrame, VideoFrame>
	& Create<"ViewportFrame", Props.ViewportFrame, ViewportFrame>
	& Create<"CanvasGroup", Props.CanvasGroup, CanvasGroup>
	& Create<"UIListLayout", Props.UIListLayout, UIListLayout>
	& Create<"UIGridLayout", Props.UIGridLayout, UIGridLayout>
	& Create<"UITableLayout", Props.UITableLayout, UITableLayout>
	& Create<"UIPageLayout", Props.UIPageLayout, UIPageLayout>
	& Create<"UIAspectRatioConstraint", Props.UIAspectRatioConstraint, UIAspectRatioConstraint>
	& Create<"UISizeConstraint", Props.UISizeConstraint, UISizeConstraint>
	& Create<"UITextSizeConstraint", Props.UITextSizeConstraint, UITextSizeConstraint>
	& Create<"UICorner", Props.UICorner, UICorner>
	& Create<"UIStroke", Props.UIStroke, UIStroke>
	& Create<"UIGradient", Props.UIGradient, UIGradient>
	& Create<"UIPadding", Props.UIPadding, UIPadding>
	& Create<"UIScale", Props.UIScale, UIScale>
	& Create<"ScreenGui", Props.ScreenGui, ScreenGui>
	& Create<"BillboardGui", Props.BillboardGui, BillboardGui>
	& Create<"SurfaceGui", Props.SurfaceGui, SurfaceGui>
	& Create<string, {[string | number]: any}, Instance>
	
type Template<Name, PropsType, Type> = (Name) -> (PropsType) -> (override: PropsType?) -> (Type)
type Template_Overloaded = 
	& Template<"Frame", Props.Frame, Frame>
	& Template<"ScrollingFrame", Props.ScrollingFrame, ScrollingFrame>
	& Template<"TextLabel", Props.TextLabel, TextLabel>
	& Template<"TextButton", Props.TextButton, TextButton>
	& Template<"TextBox", Props.TextBox, TextBox>
	& Template<"ImageLabel", Props.ImageLabel, ImageLabel>
	& Template<"ImageButton", Props.ImageButton, ImageButton>
	& Template<"VideoFrame", Props.VideoFrame, VideoFrame>
	& Template<"ViewportFrame", Props.ViewportFrame, ViewportFrame>
	& Template<"CanvasGroup", Props.CanvasGroup, CanvasGroup>
	& Template<"UIListLayout", Props.UIListLayout, UIListLayout>
	& Template<"UIGridLayout", Props.UIGridLayout, UIGridLayout>
	& Template<"UITableLayout", Props.UITableLayout, UITableLayout>
	& Template<"UIPageLayout", Props.UIPageLayout, UIPageLayout>
	& Template<"UIAspectRatioConstraint", Props.UIAspectRatioConstraint, UIAspectRatioConstraint>
	& Template<"UISizeConstraint", Props.UISizeConstraint, UISizeConstraint>
	& Template<"UITextSizeConstraint", Props.UITextSizeConstraint, UITextSizeConstraint>
	& Template<"UICorner", Props.UICorner, UICorner>
	& Template<"UIStroke", Props.UIStroke, UIStroke>
	& Template<"UIGradient", Props.UIGradient, UIGradient>
	& Template<"UIPadding", Props.UIPadding, UIPadding>
	& Template<"UIScale", Props.UIScale, UIScale>
	& Template<"ScreenGui", Props.ScreenGui, ScreenGui>
	& Template<"BillboardGui", Props.BillboardGui, BillboardGui>
	& Template<"SurfaceGui", Props.SurfaceGui, SurfaceGui>
	& Template<string, {[string | number]: any}, Instance>

local function remove(tbl: {[string | number]: any}, k: string): any
	local v = tbl[k]
	tbl[k] = nil
	return v
end

type ConnHandler = (self: RBXScriptConnection, self_instance: Instance, ...any) -> ()
local function createConnection(name: string, type: string, fn: ConnHandler)
	local p = newproxy(true)
	local mt = getmetatable(p)
	mt.type = type
	mt.fn = fn
	mt.name = name
	return p
end

local function parsePropertiesTable(inst: Instance, tbl: {[any]: any})
	local parent = remove(tbl, "Parent")

	local children = {}
	local eventListenersProxies = {}
	local eventListenersFn = {}
	for k, v in tbl do
		if type(k) == "number" then
			if type(v) == "userdata" and type(getmetatable(v)) == "table" then
				table.insert(eventListenersProxies, v)
			elseif type(v) == "string" then
				inst:AddTag(v)
			elseif type(v) == "function" then
				table.insert(children, v())
			elseif typeof(v) == "Instance" then
				table.insert(children, v)
			end
			continue
		end
		if type(v) == "function" then
			eventListenersFn[k] = v
			continue
		end
		inst[k] = v
	end
	
	local class = inst.ClassName
	for _, v in eventListenersProxies do
		local mt = getmetatable(v)
		local fn = mt.fn
		local ty = mt.type
		local k = mt.name

		local signal = inst[k]
		assert(typeof(signal) == "RBXScriptSignal", `RBXScriptSignal '{k}' does not exist on Instance '{class}'`)

		local c;c = signal[ty](signal, function(...)
			fn(c, inst, ...)
		end)
	end
	for k, v in eventListenersFn do
		local signal = inst[k]
		assert(typeof(signal) == "RBXScriptSignal", `RBXScriptSignal '{k}' does not exist on Instance '{class}'`)

		local c;c = signal:Connect(function(...)
			v(c, inst, ...)
		end)
	end
	
	for _, v in children do
		v.Parent = inst
	end

	if parent then
		inst.Parent = parent
	end
end

local function createInstFromArgs(tbl: {[any]: any}, className: string)
	local inst = Instance.new(className)
	parsePropertiesTable(inst, tbl)

	return inst
end

local create: Create_Overloaded = function(className: string)
	return function(tbl: {[string | number]: any})
		return createInstFromArgs(tbl, className)
	end
end

local template: Template_Overloaded = function(className: string)
	return function(tbl: {[string | number]: any})
		return function(override)
			if override then
				local newTbl = table.clone(tbl)
				for k, v in override do
					if type(k) == "number" then
						table.insert(newTbl, v)
						continue
					end
					newTbl[k] = v
				end
				return createInstFromArgs(newTbl, className)
			else
				return createInstFromArgs(tbl, className)
			end
		end
	end
end

return {
	create = create,
	template = template,
	
	connect = function(name: string, fn: ConnHandler)
		return createConnection(name, "Connect", fn)
	end,
	connectParallel = function(name: string, fn: ConnHandler)
		return createConnection(name, "ConnectParallel", fn)
	end,
	connectOnce = function(name: string, fn: ConnHandler)
		return createConnection(name, "Once", fn)
	end,
}