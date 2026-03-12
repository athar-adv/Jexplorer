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

local template: Template_Overloaded = function(className: string)
	return function(tbl: {[string | number]: any})
		local template = createInstFromArgs(tbl, className)
		return function(override)
			if override then
				local clone = template:Clone()
				for k, v in override do
					if type(k) == "number" then
						if typeof(v) ~= "Instance" then
							error(`Array part of template must be instances only, got {typeof(v)} '{v}'`)
						end
						v.Parent = clone
					else
						clone[k] = v
					end
				end
				return clone
			end
			return template:Clone()
		end
	end
end

return {
	create = create,
	template = template,
}