--!strict

local ChangeHistoryService = game:GetService("ChangeHistoryService")

local Types = require("../Types")

local ClassIcon = require("./Small/ClassIcon")
local RawInst = require("./Small/RawInst")
local Categories = require("./Info/InstanceCategories")

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

type buttonItem = Types.buttonItem
local menuInfo: Types.ClassSelectionMenuInfo
local ClassSelectionMenu = {} :: Types.ClassSelectionMenu

function ClassSelectionMenu.init(Manager)
	local components = Manager.Components
	local state = Manager.WidgetState
	local world = state.World
	local connections = state.Connections
	local jexplorerUi = state.JExplorerUI
	local topbar = jexplorerUi.Topbar

	-- Frequently used classes per scope: { [scopeName]: { className, ... } }
	local frequentByScope: { [string]: { string } } = {}
	local currentScope: string = "Default"
	local FREQUENT_CATEGORY = "Suggested"

	local classSelectList do
		classSelectList = PluginUI.createItemList {
			Name = "classSelectList"
		}
		local allButtons: {buttonItem} = {}
		local categories: {[string]: Frame} = {}
		local originalOrders: {
			buttons: {[string]: number},
			headers: {[string]: number}
		} = {
			buttons = {},
			headers = {}
		}
		local currentVisibleButtons: {buttonItem} = {}

		-- Holds instances created for the Frequently Used section so we can destroy on rebuild
		local frequentInstances: { Instance } = {}

		local topFrame = Instance.new("Frame")
		topFrame:AddTag("JEXP_Border")
		topFrame:AddTag("JEXP_Background")

		topFrame.Name = "TopFrame"
		topFrame.AnchorPoint = Vector2.new(0, 1)
		topFrame.BorderSizePixel = 0
		topFrame.Size = UDim2.new(1, 0, 0, 28)
		topFrame.Parent = classSelectList.Backdrop

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

		local function rebuildFrequentSection()
			highlightFrame.Parent = nil

			-- Destroy all previously created Frequently Used UI instances
			for _, inst in frequentInstances do
				inst:Destroy()
			end
			table.clear(frequentInstances)

			-- Remove stale allButtons entries for Frequently Used
			for i = #allButtons, 1, -1 do
				if allButtons[i].category == FREQUENT_CATEGORY then
					table.remove(allButtons, i)
				end
			end

			categories[FREQUENT_CATEGORY] = nil
			originalOrders.headers[FREQUENT_CATEGORY] = nil

			local scopeList = frequentByScope[currentScope]
			if not scopeList or #scopeList == 0 then return end

			-- Header at LayoutOrder 0, always sits above real categories (base 10000+)
			local header = PluginUI.createHeader(nil, FREQUENT_CATEGORY)
			header.LayoutOrder = 0
			header.Size = UDim2.new(1, 0, 0, header.Size.Y.Offset)
			header.Parent = classSelectList.Container
			table.insert(classSelectList.Items, header)

			categories[FREQUENT_CATEGORY] = header
			originalOrders.headers[FREQUENT_CATEGORY] = 0
			table.insert(frequentInstances, header)

			-- No limit — use the full list as provided by setScopeInfo
			for order, className in scopeList do
				local icon = ClassIcon.getIcon(className)
				if not icon then continue end

				local capturedClass = className
				local buttonItem = PluginUI.createButtonWithIcon(
					nil,
					capturedClass,
					icon.Image,
					icon.ImageRectOffset,
					icon.ImageRectSize,
					function()
						classSelectList:Hide()
						if menuInfo.currentOnSelectCallback then
							menuInfo.currentOnSelectCallback(capturedClass)
						end
					end
				)

				local button = buttonItem.Instance
				-- LayoutOrder 1..N, all below the real category base of 10000
				button.LayoutOrder = order
				button:RemoveTag("JEXP_DarkBackground")
				button:AddTag("JEXP_Background")

				button.Size = UDim2.new(1, 0, 0, button.Size.Y.Offset)
				button.Parent = classSelectList.Container
				table.insert(classSelectList.Items, button)

				local key = FREQUENT_CATEGORY .. "_" .. capturedClass
				originalOrders.buttons[key] = order
				table.insert(allButtons, {
					button = button,
					className = capturedClass,
					category = FREQUENT_CATEGORY
				})
				table.insert(frequentInstances, button)
			end
		end

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
				currentVisibleButtons = {}
				for _, buttonData in allButtons do
					buttonData.button.Visible = true
					local key = buttonData.category == FREQUENT_CATEGORY
						and (FREQUENT_CATEGORY .. "_" .. buttonData.className)
						or buttonData.className
					buttonData.button.LayoutOrder = originalOrders.buttons[key]
					table.insert(currentVisibleButtons, buttonData)
				end
				table.sort(currentVisibleButtons, function(a, b)
					return a.button.LayoutOrder < b.button.LayoutOrder
				end)
				for category, header in categories do
					header.Visible = true
					header.LayoutOrder = originalOrders.headers[category]
				end
				menuInfo.currentVisibleButtons = currentVisibleButtons
				return
			end

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
						table.insert(currentVisibleButtons, match)
					end
				end
			end
			menuInfo.currentVisibleButtons = currentVisibleButtons
		end)
		
		local REAL_CATEGORY_BASE = 10000
		local layoutOrder = REAL_CATEGORY_BASE
		local buttons = {}
		for category, tbl in Categories do
			local header = PluginUI.createHeader(classSelectList, category)
			layoutOrder += 1
			header.LayoutOrder = layoutOrder

			categories[category] = header
			originalOrders.headers[category] = layoutOrder

			for _, class in tbl do
				local icon = ClassIcon.getIcon(class)
				if not icon then continue end

				local capturedClass = class
				local buttonItem = PluginUI.createButtonWithIcon(
					nil, capturedClass, icon.Image, icon.ImageRectOffset, icon.ImageRectSize,
					function()
						classSelectList:Hide()
						if menuInfo.currentOnSelectCallback then
							menuInfo.currentOnSelectCallback(capturedClass)
						end
					end
				)
				table.insert(buttons, buttonItem.Instance)
				layoutOrder += 1

				local button = buttonItem.Instance
				button.LayoutOrder = layoutOrder
				button:RemoveTag("JEXP_DarkBackground")
				button:AddTag("JEXP_Background")
				originalOrders.buttons[capturedClass] = layoutOrder
				table.insert(allButtons, {
					button = button,
					className = capturedClass,
					category = category
				})
			end
		end
		classSelectList:AddBulkItem(buttons)
		currentVisibleButtons = {}
		for _, buttonData in allButtons do
			table.insert(currentVisibleButtons, buttonData)
		end

		menuInfo = {
			currentOnSelectCallback = nil,
			currentInsertTarget = 1,
			classSelectList = classSelectList,
			currentVisibleButtons = currentVisibleButtons,
			searchbar = searchbar,
			highlightFrame = highlightFrame,
			setScopeInfo = function(scopeName: string, frequentClasses: {string})
				frequentByScope[scopeName or "Default"] = frequentClasses
			end,
			setScope = function(scopeName: string)
				currentScope = scopeName or "Default"
				rebuildFrequentSection()

				currentVisibleButtons = {}
				for _, buttonData in allButtons do
					buttonData.button.Visible = true
					local key = buttonData.category == FREQUENT_CATEGORY
						and (FREQUENT_CATEGORY .. "_" .. buttonData.className)
						or buttonData.className
					buttonData.button.LayoutOrder = originalOrders.buttons[key]
					table.insert(currentVisibleButtons, buttonData)
				end
				table.sort(currentVisibleButtons, function(a, b)
					return a.button.LayoutOrder < b.button.LayoutOrder
				end)

				menuInfo.currentVisibleButtons = currentVisibleButtons
				menuInfo.currentInsertTarget = 1
				if #currentVisibleButtons > 0 then
					highlightFrame.Parent = currentVisibleButtons[1].button
				end

				searchbar.Text = ""
			end
		}
		ClassSelectionMenu.menuInfo = menuInfo
		
		local function onInputBegan(input)
			if not classSelectList.Backdrop.Visible then return end
			if input.UserInputState ~= Enum.UserInputState.Begin then return end
			local visible = menuInfo.currentVisibleButtons
			if input.KeyCode == Enum.KeyCode.Return then
				classSelectList:Hide()
				if menuInfo.currentOnSelectCallback and menuInfo.currentInsertTarget > 0 and menuInfo.currentInsertTarget <= #visible then
					local selected = visible[menuInfo.currentInsertTarget]
					menuInfo.currentOnSelectCallback(selected.className)
				end
			elseif input.KeyCode == Enum.KeyCode.Up then
				if #visible > 0 then
					menuInfo.currentInsertTarget = math.max(1, menuInfo.currentInsertTarget - 1)
					highlightFrame.Parent = visible[menuInfo.currentInsertTarget].button
				end
			elseif input.KeyCode == Enum.KeyCode.Down then
				if #visible > 0 then
					menuInfo.currentInsertTarget = math.min(#visible, menuInfo.currentInsertTarget + 1)
					highlightFrame.Parent = visible[menuInfo.currentInsertTarget].button
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
		classSelectList.Backdrop.Parent = jexplorerUi
	end

	Manager.ItemLists = {
		InsertInstance = classSelectList
	}
end

function ClassSelectionMenu.show(Manager, pos, size, fn)
	assert(menuInfo, "ClassSelectionMenu not initialized yet")

	local state = Manager.WidgetState
	local jexplorerUi = state.JExplorerUI

	local classSelectList = menuInfo.classSelectList
	local frameSize = classSelectList.Backdrop.AbsoluteSize
	local searchbar = menuInfo.searchbar

	menuInfo.currentOnSelectCallback = fn

	classSelectList:SetAnchor(
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
	
	classSelectList:Show()
	searchbar:CaptureFocus()
	searchbar.Text = ""
	menuInfo.currentInsertTarget = 1
	if #menuInfo.currentVisibleButtons > 0 then
		menuInfo.highlightFrame.Parent = menuInfo.currentVisibleButtons[1].button
	end
end

return ClassSelectionMenu