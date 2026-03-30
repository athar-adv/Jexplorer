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

local function parsePropertiesTable(inst: Instance, tbl: {[any]: any})
	local parent = tbl.Parent
	tbl.Parent = nil

	for k, v in tbl do
		if type(k) == "number" then
			if type(v) == "string" then
				inst:AddTag(v)
			elseif type(v) == "function" then
				v().Parent = inst
			elseif typeof(v) == "Instance" then
				v.Parent = inst
			end
		else
			inst[k] = v
		end
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

return create