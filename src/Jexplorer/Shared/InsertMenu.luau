--!strict

local StudioService = game:GetService("StudioService")
local ChangeHistoryService = game:GetService("ChangeHistoryService")

local Types = require("../Types")

local RawInst = require("./Small/RawInst")

local getClampedXY = require("./Small/GetClampedXY")
local rawnewindex = RawInst.rawnewindex

local PluginUI = require("./PluginUI")

local function calculateMatchScore(text: string, search: string)
	if search == "" then return 1 end

	local lowerText = text:lower()
	local lowerSearch = search:lower()
	if lowerText == lowerSearch then
		return 1000
	end

	if lowerText:sub(1, #lowerSearch) == lowerSearch then
		return 100
	end

	if lowerText:find(lowerSearch, 1, true) then
		return 50
	end

	local textIndex = 1
	local searchIndex = 1
	local matches = 0

	while textIndex <= #lowerText and searchIndex <= #lowerSearch do
		if lowerText:sub(textIndex, textIndex) == lowerSearch:sub(searchIndex, searchIndex) then
			matches = matches + 1
			searchIndex = searchIndex + 1
		end
		textIndex = textIndex + 1
	end

	if matches == #lowerSearch then
		return 10 + matches
	end

	return 0
end

local menuInfo
local InsertMenu = {} :: Types.InsertMenu

function InsertMenu.init(Manager)
	local components = Manager.Components
	local state = Manager.WidgetState
	local world = state.World
	local connections = state.Connections
	local jexplorerUi = state.JExplorerUI
	local topbar = jexplorerUi.Topbar

	local insertInstanceList do
		insertInstanceList = PluginUI.createItemList {
			Name = "InsertInstanceList"
		}
		local allButtons: {
			{
				button: Frame,
				className: string,
				category: string
			}
		} = {}
		local categories: {[string]: Frame} = {}
		local originalOrders: {
			buttons: {[string]: number},
			headers: {[string]: number}
		} = {
			buttons = {},
			headers = {}
		}
		local currentVisibleButtons: {
			{
				button: Frame,
				className: string,
				category: string
			}
		} = {}

		local topFrame = Instance.new("Frame")
		topFrame:AddTag("JEXP_Border")
		topFrame:AddTag("JEXP_Background")

		topFrame.Name = "TopFrame"
		topFrame.AnchorPoint = Vector2.new(0, 1)
		topFrame.BorderSizePixel = 0
		topFrame.Size = UDim2.new(1, 0, 0, 28)
		topFrame.Parent = insertInstanceList.Backdrop

		local searchbar = Instance.new("TextBox")
		searchbar:AddTag("JEXP_Border")
		searchbar:AddTag("JEXP_DarkBackground")
		searchbar:AddTag("JEXP_Text")

		searchbar.Name = "SearchBar"
		searchbar.AnchorPoint = Vector2.new(0, 0.5)
		searchbar.BorderSizePixel = 0
		searchbar.Position = UDim2.new(0.025, 0, 0.5, 0)
		searchbar.Size = UDim2.fromScale(0.8, 0.6)
		searchbar.Text = ""
		searchbar.TextSize = 8
		searchbar.PlaceholderText = "Search object..."
		searchbar.TextXAlignment = Enum.TextXAlignment.Left
		searchbar.TextYAlignment = Enum.TextYAlignment.Center
		searchbar.Parent = topFrame

		local highlightFrame = Instance.new("Frame")
		highlightFrame.Size = UDim2.fromScale(1, 1)
		highlightFrame.BackgroundColor3 = Color3.new(100, 100, 100)
		highlightFrame.BackgroundTransparency = 0.8

		searchbar:GetPropertyChangedSignal("Text"):Connect(function()
			local searchText = searchbar.Text
			local matches = {}
			for _, buttonData in allButtons do
				local score = calculateMatchScore(buttonData.className, searchText)
				if score > 0 then
					table.insert(matches, {
						button = buttonData.button,
						score = score,
						className = buttonData.className,
						category = buttonData.category
					})
				end
			end

			table.sort(matches, function(a, b)
				return a.score > b.score
			end)
			for _, buttonData in allButtons do
				buttonData.button.Visible = false
			end
			for _, header in categories do
				header.Visible = false
			end
			if searchText == "" then
				-- Reset to show all buttons
				currentVisibleButtons = {}
				for _, buttonData in allButtons do
					buttonData.button.Visible = true
					buttonData.button.LayoutOrder = originalOrders.buttons[buttonData.className]
					table.insert(currentVisibleButtons, buttonData)
				end
				for category, header in categories do
					header.Visible = true
					header.LayoutOrder = originalOrders.headers[category]
				end
				return
			end

			-- Clear and rebuild visible buttons list
			currentVisibleButtons = {}
			local layoutOrder = 1
			local visibleCategories = {}
			local categoryOrder = {}
			for _, match in matches do
				if not visibleCategories[match.category] then
					visibleCategories[match.category] = true
					table.insert(categoryOrder, match.category)
				end
			end
			for _, category in categoryOrder do
				if categories[category] then
					categories[category].Visible = true
					categories[category].LayoutOrder = layoutOrder
					layoutOrder = layoutOrder + 1
				end
				for _, match in matches do
					if match.category == category then
						match.button.Visible = true
						match.button.LayoutOrder = layoutOrder
						layoutOrder = layoutOrder + 1
						-- Add to visible buttons in display order
						table.insert(currentVisibleButtons, match)
					end
				end
			end
		end)

		local function insert(class: string)
			insertInstanceList:Hide()

			local entity = state.ContextTarget
			if not entity then return end

			local id = ChangeHistoryService:TryBeginRecording("CreateInstance", "Create Instance")

			local entityInst = world:get(entity, components.Instance)
			if not entityInst then
				if id then
					ChangeHistoryService:FinishRecording(id, Enum.FinishRecordingOperation.Cancel)
				end
				return 
			end

			local success, inst = pcall(Instance.new, class)
			if not success then warn(inst) return end

			local infos = {}
			for k, v in require("./Info/InstanceInsertInfo") do
				if inst:IsA(k) then table.insert(infos, v) end
			end
			for _, info in infos do
				for k, v in info.Props do
					pcall(rawnewindex, inst, k, v)
				end
				if info.SideEffect then
					info.SideEffect(inst)
				end
			end

			inst.Parent = entityInst
			--if not Manager.isExplorerEntityExpanded(entity) then
			--	--toggleExpand(world, entity, true, true)
			--	world:add(entity, components.Expanded)
			--	Manager.HierarchyState.invalidateEntityStateCache(entity)
			--	Manager.DeferredTaskScheduler.HierarchyChildrenMapNeedsUpdate = true
			--end

			--local childEntity = assert(Manager.HierarchyState.createInstanceEntity(Manager, inst, entity))
			--Manager.HierarchyState.queueForOnChildAdded(entity, childEntity)
			
			game.Selection:Set({inst})

			if id then
				ChangeHistoryService:FinishRecording(id, Enum.FinishRecordingOperation.Commit)
			end
		end

		local layoutOrder = 0
		for category, tbl in require("./Info/InstanceCategories") do
			local header = PluginUI.createHeader(insertInstanceList, category)
			layoutOrder += 1
			header.LayoutOrder = layoutOrder

			categories[category] = header
			originalOrders.headers[category] = layoutOrder

			for _, class in tbl do
				local success, icon: Types.StudioIconResult = xpcall(
					StudioService.GetClassIcon, function()end, StudioService, class
				)
				if not success then return end

				local buttonItem = PluginUI.createButtonWithIcon(
					insertInstanceList, class, icon.Image, icon.ImageRectOffset, icon.ImageRectSize, 
					function()
						insert(class)
					end
				)

				layoutOrder += 1

				local button = buttonItem.Instance
				button.LayoutOrder = layoutOrder

				button:RemoveTag("JEXP_DarkBackground")
				button:AddTag("JEXP_Background")
				originalOrders.buttons[class] = layoutOrder
				table.insert(allButtons, {
					button = button,
					className = class,
					category = category
				})
			end
		end
		currentVisibleButtons = {}
		for _, buttonData in allButtons do
			table.insert(currentVisibleButtons, buttonData)
		end

		--local currentInsertTarget: number
		menuInfo = {
			currentInsertTarget = 1,
			insertInstanceList = insertInstanceList,
			currentVisibleButtons = currentVisibleButtons,
			searchbar = searchbar,
			highlightFrame = highlightFrame
		}

		local function onInputBegan(input)
			if not insertInstanceList.Backdrop.Visible then return end
			if input.UserInputState ~= Enum.UserInputState.Begin then return end
			if input.KeyCode == Enum.KeyCode.Return then
				insertInstanceList:Hide()
				if menuInfo.currentInsertTarget > 0 and menuInfo.currentInsertTarget <= #currentVisibleButtons then
					insert(currentVisibleButtons[menuInfo.currentInsertTarget].className)
				end
			elseif input.KeyCode == Enum.KeyCode.Up then
				if #currentVisibleButtons > 0 then
					menuInfo.currentInsertTarget = math.max(1, menuInfo.currentInsertTarget - 1)
					highlightFrame.Parent = currentVisibleButtons[menuInfo.currentInsertTarget].button
				end
			elseif input.KeyCode == Enum.KeyCode.Down then
				if #currentVisibleButtons > 0 then
					menuInfo.currentInsertTarget = math.min(#currentVisibleButtons, menuInfo.currentInsertTarget + 1)
					highlightFrame.Parent = currentVisibleButtons[menuInfo.currentInsertTarget].button
				end
			end
		end

		connections:add_many({
			Manager.connectInputBegan(onInputBegan),
			searchbar.FocusLost:Connect(function(_, input)
				onInputBegan(input)
			end),
			searchbar.InputBegan:Connect(onInputBegan)
		})
		insertInstanceList.Backdrop.Parent = jexplorerUi
	end

	Manager.ItemLists = {
		InsertInstance = insertInstanceList
	}
end

function InsertMenu.show(Manager, pos, size)
	assert(menuInfo, "InsertMenu not initialized yet")
	
	local state = Manager.WidgetState
	local jexplorerUi = state.JExplorerUI
	
	local insertInstanceList = menuInfo.insertInstanceList
	local frameSize = insertInstanceList.Backdrop.AbsoluteSize
	local searchbar = menuInfo.searchbar
	
	insertInstanceList:SetAnchor(
		Vector2.new(0, 0), 
		UDim2.fromOffset(
			getClampedXY(
				frameSize,
				pos, 
				size,
				jexplorerUi.AbsolutePosition,
				jexplorerUi.AbsoluteSize
			)
		)
	)

	insertInstanceList:Show()
	searchbar:CaptureFocus()
	searchbar.Text = ""
	menuInfo.currentInsertTarget = 1
	-- Set initial highlight
	if #menuInfo.currentVisibleButtons > 0 then
		menuInfo.highlightFrame.Parent = menuInfo.currentVisibleButtons[1].button
	end
end

return InsertMenu