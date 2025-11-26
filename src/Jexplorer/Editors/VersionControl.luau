--!strict
--!optimize 2

local plugin = script:FindFirstAncestorOfClass("Plugin")

local LocalizationService = game:GetService("LocalizationService")
local ScriptEditorService = game:GetService("ScriptEditorService")
local ReflectionService = game:GetService("ReflectionService")
local Selection = game:GetService('Selection')

local studioSettings = settings().Studio

local main = script.Parent.Parent

local utilities = main.Utilities

local UITemplates = require(utilities.UITemplates)
local PluginUI = require(utilities.PluginUI)
local GitAPI = require(utilities.GitAPI)
local InstanceUtility = require(utilities.Small.InstanceUtility)
local parse = require(utilities.Luaup.parse)
local visit = require(utilities.Luaup.visit)

local rawindex = InstanceUtility.rawindex

local Types = require(main.Types)

local init = false
local VersionControl = {
	Versions = {},
	PendingChanges = {}
} :: Types.VersionControl
local Manager: Types.Manager

local labels: {any} = {}
local lineLabels: {any} = {}

local KEYWORD_COLOR = Color3.fromRGB(239, 105, 121)
local STRING_COLOR = Color3.fromRGB(173, 241, 149)
local NUMBER_COLOR = Color3.fromRGB(255, 211, 78)
local NIL_COLOR = Color3.fromRGB(255, 192, 34)
local BOOL_COLOR = Color3.fromRGB(255, 192, 34)
local CALL_COLOR = Color3.fromRGB(247, 236, 150)

local function str_replace(str: string, slice: string, startIndex: number, endIndex: number)
	return string.sub(str, 1, startIndex) .. slice .. string.sub(str, endIndex, -1)
end

local function syntaxHighlight(src: string): string
	local originalSrc = src

	local cstResult = parse(src)
	--if not cstResult.success then
	--	error(cstResult.cst)
	--end
	local cst = cstResult.cst
	local visitor = visit.visitor()
	local all_replacements = {}

	local function onNode(word: string, span: vector, color: Color3, x_offset: number, y_offset: number, x_offset2: number, y_offset2: number)
		if span.x == -1 and span.y == -1 then return end
		if word == "%" then 
			word = string.sub(src, span.x + x_offset, span.y + y_offset)
		end

		table.insert(all_replacements, {
			span = span,
			word = word,
			color = color,
			x_offset = x_offset2,
			y_offset = y_offset2
		})
	end

	local function create_visitor(name: string, color: Color3, keywords: {string}, x_offset: number, y_offset: number, x_offset2: number, y_offset2: number, getSpan: (node: any) -> {vector | {vector}})
		visitor[name] = function(_, node)
			local spans = getSpan(node)
			if not spans then return end

			for i, span in spans do
				local word = keywords[math.min(i, #keywords)]
				if typeof(span) == "table" then
					for _, v in span do
						onNode(word, v, color, x_offset, y_offset, x_offset2, y_offset2)
					end
					continue
				end
				onNode(word, span, color, x_offset, y_offset, x_offset2, y_offset2)
			end
		end
	end
	
	create_visitor("visit_stat_local_variable", KEYWORD_COLOR, {"local"}, 0, 0, 0, 1, function(node)
		return {node.local_tok.span}
	end)
	create_visitor("visit_stat_do", KEYWORD_COLOR, {"do", "end"}, 0, 0, 0, 1, function(node)
		return {node.while_tok.span, node.end_tok.span}
	end)
	create_visitor("visit_stat_for_in", KEYWORD_COLOR, {"for", "in", "do", "end"}, 0, 0, 0, 1, function(node)
		return {node.for_tok.span, node.in_tok.span, node.do_tok.span, node.end_tok.span}
	end)
	create_visitor("visit_stat_numeric_for", KEYWORD_COLOR, {"for", "do", "end"}, 0, 0, 0, 1, function(node)
		return {node.for_tok.span, node.do_tok.span, node.end_tok.span}
	end)
	create_visitor("visit_stat_function", KEYWORD_COLOR, {"function", "end"}, 0, 0, 0, 1, function(node)
		return {node.function_tok.span, node.body.end_tok.span}
	end)
	create_visitor("visit_stat_local_function", KEYWORD_COLOR, {"local", "function", "end"}, 0, 0, 0, 1, function(node)
		return {node.local_tok.span, node.function_tok.span, node.body.end_tok.span}
	end)
	create_visitor("visit_stat_type", KEYWORD_COLOR, {"export", "type"}, 0, 0, 0, 1, function(node)
		return {node.export_tok and node.export_tok.span or vector.create(-1, -1), node.type_tok.span}
	end)
	create_visitor("visit_stat_if", KEYWORD_COLOR, {"if", "else", "end", "elseif", "then"}, 0, 0, 0, 1, function(node)
		local elseifSpans: {vector} = {}
		local thenSpans: {vector} = {}
		for _, v in node.branches do
			if v.sep then
				table.insert(elseifSpans, v.sep.span)
			end
			table.insert(thenSpans, v.node.then_tok.span)
		end

		if node.else_branch then
			return {node.if_tok.span, node.else_branch.else_tok.span, node.end_tok.span, elseifSpans, thenSpans}
		end
		return {node.if_tok.span, vector.create(-1, -1), node.end_tok.span, elseifSpans, thenSpans}
	end)
	create_visitor("visit_stat_repeat", KEYWORD_COLOR, {"repeat", "until"}, 0, 0, 0, 1, function(node)
		return {node.repeat_tok.span, node.until_tok.span}
	end)
	create_visitor("visit_last_stat_return", KEYWORD_COLOR, {"return"}, 0, 0, 0, 1, function(node)
		return {node.return_tok.span}
	end)
	create_visitor("visit_last_stat_break", KEYWORD_COLOR, {"break"}, 0, 0, 0, 1, function(node)
		return {node.tok.span}
	end)
	create_visitor("visit_last_stat_continue", KEYWORD_COLOR, {"continue"}, 0, 0, 0, 1, function(node)
		return {node.tok.span}
	end)
	create_visitor("visit_expr_binary", KEYWORD_COLOR, {"and", "or"}, 0, 0, 0, 1, function(node)
		local andNode, orNode = vector.create(-1, -1), vector.create(-1, -1)
		
		if node.operator.kind == "and" then
			andNode = node.operator.span
		end
		if node.operator.kind == "or" then
			orNode = node.operator.span
		end

		return {andNode, orNode}
	end)
	create_visitor("visit_expr_unary", KEYWORD_COLOR, {"not"}, 0, 0, 0, 1, function(node)
		if node.operator.kind == "not" then
			return {node.operator.span}
		end
		return {vector.create(-1, -1)}
	end)
	create_visitor("visit_expr_function", KEYWORD_COLOR, {"function", "end"}, 0, 0, 0, 1, function(node)
		return {node.function_tok.span, node.body.end_tok.span}
	end)
	create_visitor("visit_var", CALL_COLOR, {"%"}, 1, 0, 0, 1, function(node)
		local spans = {}

		local root = node.root
		if root.kind == "name" and node.suffixes[1] and node.suffixes[1].kind == "call" and not node.suffixes[1].method then
			table.insert(spans, root.tok.span)
		end

		for i, suffix in node.suffixes do
			if suffix.kind ~= "call" then continue end

			if suffix.method then
				table.insert(spans, suffix.method.name.span)
				continue
			end

			local prev = node.suffixes[i - 1]
			if prev and prev.kind == "nameindex" then
				table.insert(spans, prev.name.span)
			end
		end

		return spans
	end)
	create_visitor("visit_istring_complex", STRING_COLOR, {"%"}, 1, 0, 0, 1, function(node)
		local first, last = node.first.span, node.last.span
		local arr = {first, last}
		for _, pair in node.middle do
			if not pair.sep then continue end
			table.insert(arr, pair.sep.span)
		end

		return arr
	end)
	create_visitor("visit_istring_simple", STRING_COLOR, {"%"}, 1, 0, 0, 1, function(node)
		return {node.tok.span}
	end)
	create_visitor("visit_expr_string", STRING_COLOR, {"%"}, 1, 0, 0, 1, function(node)
		return {node.tok.span}
	end)
	create_visitor("visit_expr_number", NUMBER_COLOR, {"%"}, 0, 0, 0, 1, function(node)
		return {node.tok.span}
	end)
	create_visitor("visit_expr_boolean", BOOL_COLOR, {"%"}, 0, 0, 0, 1, function(node)
		return {node.tok.span}
	end)
	create_visitor("visit_expr_nil", NIL_COLOR, {"%"}, 0, 0, 0, 1, function(node)
		return {node.tok.span}
	end)

	visit.visit(visitor, nil, cst)

	table.sort(all_replacements, function(a, b)
		return a.span.x > b.span.x
	end)
	
	local LT = "\30"
	local GT = "\31"
	for _, replacement in all_replacements do
		local fmt = `{LT}font color='rgb({math.round(replacement.color.R * 255)}, {math.round(replacement.color.G * 255)}, {math.round(replacement.color.B * 255)})'{GT}%s{LT}/font{GT}`
		src = str_replace(src, fmt:format(replacement.word), replacement.span.x + replacement.x_offset, replacement.span.y + replacement.y_offset)
	end
	
	return src:gsub(`([<>\1\2{GT}{LT}])`, {
		["<"] = "&lt;",
		[">"] = "&gt;",
		["&"] = "&amp;",
		[GT] = ">",
		[LT] = "<"
	})
end

function VersionControl.openSourceViewer(src)
	if not init then return end
	local highlighted = syntaxHighlight(src)
	
	local mainframe = VersionControl.SourceViewerMainframe
	for _, v in labels do
		v:Destroy()
	end
	for _, v in lineLabels do
		v:Destroy()
	end
	
	local box = Instance.new("TextBox")
	box.LineHeight = 1.38
	box.TextSize = 12
	box.Size = UDim2.new(1, 0, 0, 0)
	box.Text = src
	box.TextColor3 = mainframe.Items:FindFirstChild("ItemFrame"):GetStyled("BackgroundColor3")
	box.TextWrapped = false
	box.AutomaticSize = Enum.AutomaticSize.Y
	box.BackgroundTransparency = 1
	box.TextXAlignment = Enum.TextXAlignment.Left
	box.Font = Enum.Font.SourceSans
	box.ClearTextOnFocus = false
	box.TextEditable = false
	box.ZIndex = 2
	box.Position = UDim2.fromOffset(4, 0)
	box.Parent = mainframe.Items:FindFirstChild("ItemFrame")
	
	local label = Instance.new("TextLabel")
	label.TextColor3 = Color3.fromRGB(186, 185, 179)
	label.LineHeight = 1.38
	label.TextSize = 12
	label.RichText = true
	label.Size = UDim2.new(1, 0, 0, 0)
	label.Text = highlighted
	label.TextWrapped = false
	label.AutomaticSize = Enum.AutomaticSize.Y
	label.BackgroundTransparency = 1
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.Font = Enum.Font.SourceSans
	label.Parent = box
	
	local numLines = #string.split(src, "\n")
	for i = 1, numLines do
		local line = Instance.new("TextLabel")
		line:AddTag("JEXP_Text")
		line.TextSize = 12
		line.Text = tostring(i)
		line.Size = UDim2.new(0, 12, 0, 12)
		line.Font = Enum.Font.SourceSans
		line.TextXAlignment = Enum.TextXAlignment.Left
		line.AutomaticSize = Enum.AutomaticSize.X
		line.BackgroundTransparency = 1
		
		line.Parent = mainframe.Items:FindFirstChild("LineFrame")
		
		table.insert(lineLabels, line)
	end
	
	table.insert(labels, box)
	table.insert(labels, label)
	
	VersionControl.SourceViewerWidget.Enabled = true
end

function VersionControl.showInstanceHistoryWidget(inst)
	if not init then return false end
	local list = VersionControl.InstanceHistoryUIList
	list:Clear()
	
	VersionControl.InstanceHistoryWidget.Enabled = true
	
	local versions = VersionControl.Versions[inst:GetDebugId()]
	if not versions then return end
	for verIndex, vinfo in versions do
		local verString = vinfo.timestamp:FormatLocalTime("HH:mm/MM/DD/YY", LocalizationService.SystemLocaleId)
		PluginUI.createButtonWithIcon(list, `version '{tostring(verIndex)}'	[{verString}]`, "rbxassetid://4869184613", Vector2.zero, Vector2.zero, function()
			if inst:IsA("LuaSourceContainer") then
				VersionControl.openSourceViewer(vinfo.props.Source)
			else
				VersionControl.VersionViewerWidget.Enabled = true
			end
		end)
	end
end

function VersionControl.createInstanceVersion(inst, changedProp, newValue)
	if not init then return false end
	local currentTime = os.time()
	
	local id = inst:GetDebugId()
	local versions = VersionControl.Versions[id]
	if not versions then
		versions = {}
		VersionControl.Versions[id] = versions
	end
	
	local props = {}
	for _, v in ReflectionService:GetPropertiesOfClass(inst.ClassName) do
		if not v.Permits.Read then continue end
		if not v.Permits.Read:Contains(SecurityCapabilities.fromCurrent()) then continue end
		props[v.Name] = rawindex(inst, v.Name)
	end
	props[changedProp] = newValue

	local newVersion = {
		timestamp = DateTime.fromUnixTimestamp(currentTime),
		props = props
	}
	table.insert(versions, newVersion)
	return true
end

function VersionControl.addPendingChange(inst, changedProp, newValue)
	if not init then return end
	local id = inst:GetDebugId()
	local changes = VersionControl.PendingChanges[id]
	if not changes then
		changes = {}
		VersionControl.PendingChanges[id] = changes
	end
	
	changes[changedProp] = newValue
	
	if Manager.getSetting("AutosaveInstChanged") then
		local currentHour = os.time() // 3600
		local versions = VersionControl.Versions[id]
		local latestVersion = versions[#versions]
		
		if latestVersion and latestVersion.timestamp.UnixTimestamp // 3600 == currentHour then
			VersionControl.appendPendingChanges(inst)
		else
			VersionControl.createPendingChanges(inst)
		end
		return
	end
	
	local entity = Manager.InstanceToEntity[inst]
	if not entity then return end
	
	local world = Manager.WidgetState.World
	local components = Manager.Components
	
	world:add(entity, components.PendingChanges)
	
	local frame = world:get(entity, components.Frame)
	if not frame then return end
	
	frame.Instance.Main.PendingChanges.Visible = true
end

function VersionControl.appendPendingChanges(inst)
	if not init then return false end
	local id = inst:GetDebugId()
	local changes = VersionControl.PendingChanges[id]
	
	if not changes then return false end
	
	local versions = VersionControl.Versions[id]
	if not versions then return false end
	if #versions == 0 then return false end
	
	for k, v in changes do
		VersionControl.appendInstanceVersion(inst, k, v)
	end
	VersionControl.PendingChanges[id] = nil
	
	local entity = Manager.InstanceToEntity[inst]
	if entity then
		local world = Manager.WidgetState.World
		local components = Manager.Components

		world:remove(entity, components.PendingChanges)
		
		local frame = world:get(entity, components.Frame)
		if frame then
			frame.Instance.Main.PendingChanges.Visible = false
		end
	end
	
	return true
end

function VersionControl.createPendingChanges(inst)
	if not init then return false end
	local id = inst:GetDebugId()
	local changes = VersionControl.PendingChanges[id]
	
	if not changes then return false end
	local first = true
	for k, v in changes do
		if first then
			first = false
			VersionControl.createInstanceVersion(inst, k, v)
			continue
		end
		VersionControl.appendInstanceVersion(inst, k, v)
	end
	
	local entity = Manager.InstanceToEntity[inst]
	if entity then
		local world = Manager.WidgetState.World
		local components = Manager.Components

		world:remove(entity, components.PendingChanges)
		
		local frame = world:get(entity, components.Frame)
		if frame then
			frame.Instance.Main.PendingChanges.Visible = false
		end
	end
	
	return true
end

function VersionControl.appendInstanceVersion(inst, changedProp, newValue)
	if not init then return false end
	local currentTime = os.time()
	
	local id = inst:GetDebugId()
	local versions = VersionControl.Versions[id]
	if not versions then
		versions = {}
		VersionControl.Versions[id] = versions
	end
	
	local latestVersion = versions[#versions]
	if latestVersion then
		latestVersion.props[changedProp] = newValue
		latestVersion.timestamp = DateTime.fromUnixTimestamp(currentTime)
		return true
	else
		return false
	end
end

local FINISH_TIME = 5

local repoList: PluginUI.ItemList
local loadingFrame: Frame
local finishedFrame: Frame
local finishedText: TextLabel
local textFrame: Frame
local textText: TextLabel
function VersionControl.createRepoProxy(display_name, repo_id, root, register_into_proxies_array)
	local repoDropdown = PluginUI.createDropDownItemList({
		Visible = true,
		Parent = repoList.Container
	}, display_name, true)
	
	local objectValue = Instance.new("ObjectValue")
	objectValue.Name = "__repo_root"
	objectValue.Parent = Manager.Storage
	
	local rootNameChangedConn
	local proxy: Types.RepoProxy = {
		DisplayName = display_name,
		RepoId = repo_id,
		Root = root,
		
		Remove = function()
			repoDropdown:Destroy()
			objectValue:Destroy()
			if rootNameChangedConn then
				rootNameChangedConn:Disconnect()
			end
		end,
	}
	PluginUI.createDeleteButton(repoDropdown.Backdrop:WaitForChild("DropDownHeader"), proxy.Remove)
	
	local rootBox = PluginUI.createAttributeBox(repoDropdown, "Root", root.Name)
	local valueBox = rootBox.Instance.ValueBox
	
	valueBox.PlaceholderText = "Click, hold & drop to assign..."

	local button = Instance.new("TextButton")
	button.BorderSizePixel = 0
	button.Transparency = 1
	button.Size = UDim2.fromScale(1, 1)
	button.ZIndex = 10
	button.Parent = valueBox
	
	rootNameChangedConn = root:GetPropertyChangedSignal("Name"):Connect(function()
		valueBox.Text = root.Name
	end)
	
	objectValue.Changed:Connect(function(value)
		root = value
		proxy.Root = value
		valueBox.Text = value.Name
		
		if rootNameChangedConn then
			rootNameChangedConn:Disconnect()
		end
		
		rootNameChangedConn = root:GetPropertyChangedSignal("Name"):Connect(function()
			valueBox.Text = root.Name
		end)
	end)
	
	button.InputBegan:Connect(function(input)
		if input.UserInputState ~= Enum.UserInputState.Begin then return end
		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			plugin:StartDrag(Manager.getDragInfo(objectValue, "Value"))
		end
	end)

	local repoIdBox = PluginUI.createAttributeBox(repoDropdown, "Repo Id (my-name/repo_name)", repo_id)
	local branchBox = PluginUI.createAttributeBox(repoDropdown, "Branch", "main")
	local pathBox = PluginUI.createAttributeBox(repoDropdown, "Path", "src")

	do
		local pushDropdown = PluginUI.createDropDownItemList({
			Visible = true,
			Parent = repoDropdown.Container
		}, "Push")

		local commitMsgBox = PluginUI.createAttributeBox(pushDropdown, "Commit Msg", "")
		PluginUI.createButton(pushDropdown, "Push (Overwrite)", function()
			if finishedFrame.Visible or loadingFrame.Visible then return end
			local commitMsg = commitMsgBox:Get()
			local repoId = repoIdBox:Get()
			local path = pathBox:Get()
			local branch = branchBox:Get()

			assert(VersionControl.Token)
			loadingFrame.Visible = true
			local succ, result = pcall(GitAPI.batchOverwrite, VersionControl.Token, repoId, branch, path, GitAPI.getFileOpsForInstances(root), commitMsg)
			loadingFrame.Visible = false

			finishedFrame.Visible = true
			if succ then
				if result.Success then
					finishedText.Text = `Successfully pushed to repo '{repoId}'`
				else
					finishedText.Text = `Failed to push to repo '{repoId}'; error_code({result.Code}) "{result.Message}"`
				end
			else
				finishedText.Text = `API Call Errored: '{result}'`
			end
			task.wait(FINISH_TIME)
			finishedFrame.Visible = false
		end)
		PluginUI.createButton(pushDropdown, "Push (Update)", function()
			if finishedFrame.Visible or loadingFrame.Visible then return end
			local commitMsg = commitMsgBox:Get()
			local repoId = repoIdBox:Get()
			local path = pathBox:Get()
			local branch = branchBox:Get()

			assert(VersionControl.Token)
			loadingFrame.Visible = true
			local succ, result = pcall(GitAPI.batchCreateOrUpdate, VersionControl.Token, repoId, branch, GitAPI.getFileOpsForInstances(root), commitMsg)
			loadingFrame.Visible = false

			finishedFrame.Visible = true
			if succ then
				if result.Success then
					finishedText.Text = `Successfully pushed to repo '{repoId}'`
				else
					finishedText.Text = `Failed to push to repo '{repoId}': error_code({result.Code}) "{result.Message}"`
				end
			else
				finishedText.Text = `API Call Errored: '{result}'`
			end
			task.wait(FINISH_TIME)
			finishedFrame.Visible = false
		end)
		PluginUI.createButton(repoDropdown, "Revert Last Commit", function()
			if loadingFrame.Visible then return end
			local commitMsg = commitMsgBox:Get()
			local repoId = repoIdBox:Get()
			local path = pathBox:Get()
			local branch = branchBox:Get()

			assert(VersionControl.Token)
			local succ, result = pcall(GitAPI.revertLastCommit, VersionControl.Token, repoId, branch, commitMsg)
			
			finishedFrame.Visible = true
			if succ then
				if result.Success then
					local r = result:Unwrap()
					if not r then return end
					finishedText.Text = `Successfully reverted commit '{r.commit.committer.date}' by '{r.commit.committer.name}'`
				else
					finishedText.Text = `Failed to push to repo '{repoId}': error_code({result.Code}) "{result.Message}"`
				end
			else
				finishedText.Text = `API Call Errored: '{result}'`
			end
			task.wait(FINISH_TIME)
			finishedFrame.Visible = false
		end)
	end
	PluginUI.createButton(repoDropdown, "Pull", function()
		if loadingFrame.Visible then return end
		local repoId = repoIdBox:Get()
		local path = pathBox:Get()
		local branch = branchBox:Get()

		assert(VersionControl.Token)
		loadingFrame.Visible = true
		root:ClearAllChildren()
		local succ, result = (pcall::any)(GitAPI.reconstructInstances, VersionControl.Token, repoId, branch, path, root)
		loadingFrame.Visible = false
		
		finishedFrame.Visible = true
		if succ then
			finishedText.Text = "Successfully pulled"
		else
			finishedText.Text = `Pull failed: '{result}'`
		end
		task.wait(FINISH_TIME)
		finishedFrame.Visible = false
	end)
	return proxy
end

function VersionControl.init(_m)
	init = true
	Manager = _m
	
	local state = Manager.WidgetState
	local components = Manager.Components
	
	local jexplorerUi = state.JExplorerUI
	local topbar = jexplorerUi.Topbar
	
	local connections = state.Connections
	local instances = connections:Extend("Destroy")
	
	local widget, mainframe = PluginUI.createEditorWidget(UITemplates.EditorFrame(), "VersionControl", "Version Control")
	VersionControl.Widget = widget
	Manager.Style:Link(widget)
	
	do
		local widget, mainframe = PluginUI.createEditorWidget(UITemplates.EditorFrame(), "VersionHistory", "Instance Version History")
		VersionControl.InstanceHistoryWidget = widget
		Manager.Style:Link(widget)
		
		local list = PluginUI.createItemListFromExisting(main, mainframe.Items)
		VersionControl.InstanceHistoryUIList = list
	end
	do
		local widget, mainframe = PluginUI.createEditorWidget(UITemplates.EditorFrame(), "VersionViewer", "Instance Version Viewer")
		VersionControl.VersionViewerWidget = widget
		Manager.Style:Link(widget)

		local list = PluginUI.createItemListFromExisting(main, mainframe.Items)
		VersionControl.VersionViewerUIList = list
	end
	do
		local widget, mainframe = PluginUI.createEditorWidget(UITemplates.EditorFrame(), "SourceViewer", "Source Viewer", 
			DockWidgetPluginGuiInfo.new(
				Enum.InitialDockState.Float,
				false,
				false,
				500,
				300
			)
		)
		VersionControl.SourceViewerWidget = widget
		VersionControl.SourceViewerMainframe = mainframe
		Manager.Style:Link(widget)
		
		local listFrame = Instance.new("Frame")
		listFrame.Size = UDim2.fromScale(0, 0)
		listFrame.Name = "LineFrame"
		listFrame.BackgroundTransparency = 1
		listFrame.AutomaticSize = Enum.AutomaticSize.XY
		listFrame.Parent = mainframe.Items
		
		local list = Instance.new("UIListLayout")
		list.Padding = UDim.new(0, 4)
		list.SortOrder = Enum.SortOrder.LayoutOrder
		list.Parent = listFrame
		
		local innerFrame = Instance.new("Frame")
		innerFrame.Size = UDim2.new(0, 2000, 1, 0)
		innerFrame.Position = UDim2.fromOffset(listFrame.AbsoluteSize.X, 0)
		innerFrame.Name = "ItemFrame"
		innerFrame:AddTag("JEXP_DarkBackground")
		innerFrame.BorderSizePixel = 0
		innerFrame.AutomaticSize = Enum.AutomaticSize.Y
		
		mainframe.Items.UIListLayout:Destroy()
		innerFrame.Parent = mainframe.Items
		
		listFrame:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
			innerFrame.Position = UDim2.fromOffset(listFrame.AbsoluteSize.X, 0)
		end)
	end
	
	local list = PluginUI.createItemListFromExisting(mainframe, mainframe.Items)
	PluginUI.createHeader(list, "WARNING: The github sync functionality is still early in functionality, be careful using this in production!")
	
	do
		loadingFrame = Instance.new("Frame")
		loadingFrame.Size = UDim2.new(1, 0, 1, 0)
		loadingFrame.ZIndex = 100
		loadingFrame.Visible = false
		loadingFrame:AddTag("JEXP_DarkBackground")
		loadingFrame.Parent = mainframe

		local loadingText = Instance.new("TextLabel")
		loadingText.Position = UDim2.new(0.5, 0, 0.5, 0)
		loadingText.AnchorPoint = Vector2.new(0.5, 0.5)
		loadingText.Size = UDim2.new(0.3, 0, 0, 40)
		loadingText.Font = Enum.Font.SourceSans
		loadingText:AddTag("JEXP_Text")
		loadingText.TextSize = 14
		loadingText.BackgroundTransparency = 1
		Manager.WidgetState.Connections:Extend(task.cancel, {
			task.spawn(function()
				while true do
					loadingText.Text = "Loading, please wait."
					task.wait(1)
					loadingText.Text = "Loading, please wait.."
					task.wait(1)
					loadingText.Text = "Loading, please wait..."
					task.wait(1)
				end
			end)
		})
		loadingText.Parent = loadingFrame
	end
	
	do
		finishedFrame = Instance.new("Frame")
		finishedFrame.Size = UDim2.new(1, 0, 1, 0)
		finishedFrame.ZIndex = 1000
		finishedFrame.Visible = false
		finishedFrame:AddTag("JEXP_DarkBackground")
		finishedFrame.Parent = mainframe

		finishedText = Instance.new("TextLabel")
		finishedText.Position = UDim2.new(0.5, 0, 0.5, 0)
		finishedText.AnchorPoint = Vector2.new(0.5, 0.5)
		finishedText.Size = UDim2.new(0, 0, 0, 40)
		finishedText.AutomaticSize = Enum.AutomaticSize.X
		finishedText.Font = Enum.Font.SourceSans
		finishedText.TextSize = 14
		finishedText:AddTag("JEXP_Text")
		finishedText.BackgroundTransparency = 1
		finishedText.Parent = finishedFrame
		
		local timer = Instance.new("TextLabel")
		timer.Position = UDim2.new(0.5, 0, 0.8, 0)
		timer.AnchorPoint = Vector2.new(0.5, 0.5)
		timer.Size = UDim2.new(0, 0, 0, 40)
		timer.AutomaticSize = Enum.AutomaticSize.X
		timer.Font = Enum.Font.SourceSans
		timer.TextSize = 14
		timer:AddTag("JEXP_Text")
		timer.BackgroundTransparency = 1
		timer.Parent = finishedFrame
		finishedFrame:GetPropertyChangedSignal("Visible"):Connect(function()
			if finishedFrame.Visible then
				for i = FINISH_TIME, 1, -1 do
					timer.Text = `Back in {i}`
					task.wait(1)
				end
			end
		end)
	end
	
	do
		textFrame = Instance.new("Frame")
		textFrame.Size = UDim2.new(1, 0, 1, 0)
		textFrame.ZIndex = 1000
		textFrame.Visible = false
		textFrame:AddTag("JEXP_DarkBackground")
		textFrame.Parent = mainframe

		textText = Instance.new("TextLabel")
		textText.Position = UDim2.new(0.5, 0, 0.5, 0)
		textText.AnchorPoint = Vector2.new(0.5, 0.5)
		textText.Size = UDim2.new(0, 0, 0, 40)
		textText.AutomaticSize = Enum.AutomaticSize.X
		textText.Font = Enum.Font.SourceSans
		textText.TextSize = 14
		textText:AddTag("JEXP_Text")
		textText.BackgroundTransparency = 1
		textText.Parent = textFrame
	end
	
	repoList = PluginUI.createDropDownItemList({
		Visible = true,
		Parent = list.Container
	}, "Repo Proxies")
	
	local tokenList = PluginUI.createDropDownItemList({
		Visible = true,
		Parent = list.Container
	}, "Auth Tokens (hidden)")
	
	local current_tokens = plugin:GetSetting("Tokens") or {}
	local currentSelectedSideButton: any
	
	local function create_token_box(name: string, token: string, _token_info: any)
		local tokenFrame = PluginUI.createAttributeBox(tokenList, name, string.rep("*", #token), nil, true)
		local selectToken = PluginUI.createSideButtonImage("rbxassetid://93307505425754", Vector2.zero, Vector2.zero, tokenFrame.Instance.ValueBox)
		local deleteButton = PluginUI.createSideButtonText("-", tokenFrame.Instance.ValueBox, 1)
		deleteButton:AddTag("JEXP_Text")
		deleteButton.TextScaled = true
		
		local tokenInfo = _token_info or {
			token = token,
			display_name = name
		}
		deleteButton.Activated:Connect(function()
			local idx = table.find(current_tokens, tokenInfo)
			if idx then table.remove(current_tokens, idx) end

			tokenFrame:Destroy()

			plugin:SetSetting("Tokens", current_tokens)
		end)
		
		local token_str = token
		tokenFrame:OnChange(function(t)
			token_str = t
			tokenFrame:Set(string.rep("*", #t))
			tokenInfo.token = t
			plugin:SetSetting("Tokens", current_tokens)
			
			if currentSelectedSideButton == selectToken then
				local token = GitAPI.AuthToken.new(token_str, "fine_grained")
				VersionControl.Token = token
			end
		end)
		
		selectToken.Activated:Connect(function()
			if currentSelectedSideButton == selectToken then
				currentSelectedSideButton = nil
				selectToken:RemoveTag("JEXP_SelectedColor")
				
				VersionControl.Token = nil
			elseif not currentSelectedSideButton then
				currentSelectedSideButton = selectToken
				selectToken:AddTag("JEXP_SelectedColor")
				
				local token = GitAPI.AuthToken.new(token_str, "fine_grained")
				VersionControl.Token = token
			elseif currentSelectedSideButton then
				currentSelectedSideButton:RemoveTag("JEXP_SelectedColor")
				currentSelectedSideButton = selectToken
				selectToken:AddTag("JEXP_SelectedColor")
				
				local token = GitAPI.AuthToken.new(token_str, "fine_grained")
				VersionControl.Token = token
			end
		end)

		local inst: any = tokenFrame.Instance
		inst.NameLabel:GetPropertyChangedSignal("Text"):Connect(function()
			tokenInfo.display_name = inst.NameLabel.Text
			plugin:SetSetting("Tokens", current_tokens)
		end)
		
		return tokenInfo
	end
	
	for _, v in current_tokens do
		create_token_box(v.display_name, v.token, v)
	end
	PluginUI.createInsertButton(tokenList.Backdrop:WaitForChild("DropDownHeader"), function()
		local info = create_token_box("MyToken", "")
		table.insert(current_tokens, info)
		plugin:SetSetting("Tokens", current_tokens)
	end)
	
	PluginUI.createInsertButton(repoList.Backdrop:WaitForChild("DropDownHeader"), function()
		if textFrame.Visible then return end
		textText.Text = "Select an Instance"
		textFrame.Visible = true
		
		Selection:Set({})
		
		repeat
			task.wait()
		until #Selection:Get() > 0
		
		local inst = Selection:Get()[1]
		Selection:Set({})
		
		textFrame.Visible = false
		VersionControl.createRepoProxy("Repo", "", inst, true)
	end)
end

return VersionControl