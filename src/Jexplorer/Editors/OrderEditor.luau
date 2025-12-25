--!strict
--!optimize 2

local plugin = script:FindFirstAncestorOfClass("Plugin")

local RunService = game:GetService("RunService")

local main = script.Parent.Parent

local shared = main.Shared

local UITemplates = require(shared.UITemplates)
local Types = require(main.Types)

local JDF = require(shared.UDF)
local PluginUI = require(shared.PluginUI)
local ClassIcon = require(shared.Small.ClassIcon)
local ItemGroup = require(shared.Vendor.ItemGroup)
local cleanup = ItemGroup.cleanup

local getId = PluginUI.getId

local init = false

local OrderEditor = {
	DefaultPriority = 999,
	PriorityVersion = 0,
	ClassPriorities = {}, -- Initialized by JState.load()
} :: Types.OrderEditor

function OrderEditor.init(Manager)
	init = true
	local state = Manager.WidgetState
	local components = Manager.Components

	local jexplorerUi = state.JExplorerUI
	local topbar = jexplorerUi.Topbar

	local connections = state.Connections
	local instances = connections:extend(cleanup.destroy)
	
	local widget, mainframe = PluginUI.createEditorWidget(UITemplates.EditorFrame(), "OrderEditor", "Order Editor")
	OrderEditor.Widget = widget
	Manager.Style:Link(widget)
	
	local list = PluginUI.createItemListFromExisting(mainframe, mainframe.Items.Content, mainframe.Items)
	
	local box; box = PluginUI.createAttributeBox(list, "Default Priority", 999, function(newValue)
		local num = JDF.from(newValue)
		if typeof(num) ~= "number" then
			box:Set(999)
			return
		end
		
		OrderEditor.DefaultPriority = num
	end)
	
	local dropdown = PluginUI.createDropDownItemList({
		Name = "InstSortingPriorities",
		Visible = true
	}, "Instance Sorting Priorities (descending)")
	dropdown:Parent(list)
	
	local currentDrag: {
		frame: Frame & any,
		moveConn: RBXScriptConnection,
		class: string,
		button: Frame
	}?
	local buttons = {}
	local buttonToClass = {}
	
	local function createClassPriorityBox(className: string, priority: number)
		local icon = ClassIcon.getIcon(className)
		if not icon then return end
		
		local buttonItem = PluginUI.createButtonWithIcon(
			dropdown, className, 
			icon.Image, 
			icon.ImageRectOffset, 
			icon.ImageRectSize
		)
		
		local button = buttonItem.Instance
		
		buttonToClass[button] = className
		button.LayoutOrder = priority
		table.insert(buttons, priority, button)
		
		local click: TextButton = button.Click
		click.InputBegan:Connect(function(input)
			if currentDrag then return end
			if input.UserInputState ~= Enum.UserInputState.Begin then return end
			if input.UserInputType ~= Enum.UserInputType.MouseButton1 then return end
			
			local clone = button:Clone()
			clone.ZIndex = 1000
			clone.Parent = mainframe
			
			local con = RunService.RenderStepped:Connect(function()
				local pos = widget:GetRelativeMousePosition()
				clone.Position = UDim2.fromOffset(pos.X, pos.Y)
			end)
			currentDrag = {
				frame = clone,
				moveConn = con,
				class = className,
				button = button
			}
		end)
		click.InputEnded:Connect(function(input)
			if not currentDrag then return end
			if input.UserInputState ~= Enum.UserInputState.End then return end
			if input.UserInputType ~= Enum.UserInputType.MouseButton1 then return end
			
			local drag = currentDrag
			currentDrag.frame:Destroy()
			currentDrag.moveConn:Disconnect()
			currentDrag = nil
			
			local pos = widget:GetRelativeMousePosition()
			local objects = PluginUI.getGuiObjectsAtPosition(mainframe, pos.X, pos.Y)
			local targetButton
			for _, v in objects do
				if v.Name == "ButtonWithIconItem" and v ~= drag.button then
					targetButton = v :: Frame
					break
				end
			end
			if not targetButton then return end
			local targetClass = buttonToClass[targetButton]
			local targetPriority = table.find(OrderEditor.ClassPriorities, targetClass)
			if not targetPriority then return end

			local dragPriority = table.find(OrderEditor.ClassPriorities, drag.class)
			if not dragPriority then return end
			
			table.remove(OrderEditor.ClassPriorities, dragPriority)
			
			local newTargetPriority = table.find(OrderEditor.ClassPriorities, targetClass)
			if not newTargetPriority then return end
			local insertPos
			if dragPriority < targetPriority then
				insertPos = newTargetPriority + 1
			else
				insertPos = newTargetPriority
			end

			table.insert(OrderEditor.ClassPriorities, insertPos, drag.class)

			for i, class in OrderEditor.ClassPriorities do
				for button, buttonClass in buttonToClass do
					if buttonClass == class then
						button.LayoutOrder = i
						break
					end
				end
			end
			
			OrderEditor.PriorityVersion += 1
			Manager.VirtualScroller.rebuildAndUpdate(Manager, false)
		end)
		
		PluginUI.createDeleteButton(button, function()
			local idx = table.find(buttons, button)
			if idx then
				table.remove(buttons, idx)
			end
			
			local currentPriority = table.find(OrderEditor.ClassPriorities, className)
			if currentPriority then
				table.remove(OrderEditor.ClassPriorities, currentPriority)
				for i = currentPriority, #buttons do
					buttons[i].LayoutOrder = i
				end
			end
			
			button:Destroy()
		end)
	end
	
	local insertClassPriority do
		insertClassPriority = PluginUI.createItemList({
			Name = "InsertClassPriority"
		})
		insertClassPriority.Backdrop.Parent = jexplorerUi
		
		local nameBox = PluginUI.createAttributeBox(insertClassPriority, "Class Name", nil)
		PluginUI.createButton(insertClassPriority, "Create", function()
			insertClassPriority:Hide()
			local name = nameBox:Get()
			
			table.insert(OrderEditor.ClassPriorities, 1, name)
			for i, class in OrderEditor.ClassPriorities do
				for button, buttonClass in buttonToClass do
					if buttonClass == class then
						button.LayoutOrder = i
						break
					end
				end
			end
			createClassPriorityBox(name, 1)
		end)
	end
	
	local header = dropdown.Backdrop:WaitForChild("DropDownHeader")
	PluginUI.createInsertButton(header, function()
		insertClassPriority:Show()
	end)
	
	for i, v in OrderEditor.ClassPriorities do
		createClassPriorityBox(v, i)
	end
end

return OrderEditor