--!strict
--!optimize 2

local plugin = script:FindFirstAncestorOfClass("Plugin")

local LocalizationService = game:GetService("LocalizationService")
local ScriptEditorService = game:GetService("ScriptEditorService")

local studioSettings = settings().Studio

local main = script.Parent.Parent

local utilities = main.Utilities
local ui = main.UI

local PluginUI = require(utilities.PluginUI)
local GitAPI = require(utilities.GitAPI)
local InstanceUtility = require(utilities.InstanceUtility)
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
	
	local LT = "\32"
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
	for k, v in Manager.APIMap[inst.ClassName] do
		if not v.Readable then continue end
		props[k] = rawindex(inst, k)
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

function VersionControl.init(_m)
	init = true
	Manager = _m
	
	local state = Manager.WidgetState
	local components = Manager.Components
	
	local jexplorerUi = state.JExplorerUI
	local topbar = jexplorerUi.Topbar
	
	local connections = state.Connections
	local instances = connections:Extend("Destroy")
	
	local widget, mainframe = PluginUI.createEditorWidget(ui.EditorFrame, "VersionControl", "Version Control")
	VersionControl.Widget = widget
	Manager.Style:Link(widget)
	
	do
		local widget, mainframe = PluginUI.createEditorWidget(ui.EditorFrame, "VersionHistory", "Instance Version History")
		VersionControl.InstanceHistoryWidget = widget
		Manager.Style:Link(widget)
		
		local list = PluginUI.createItemListFromExisting(main, mainframe.Items)
		VersionControl.InstanceHistoryUIList = list
	end
	do
		local widget, mainframe = PluginUI.createEditorWidget(ui.EditorFrame, "VersionViewer", "Instance Version Viewer")
		VersionControl.VersionViewerWidget = widget
		Manager.Style:Link(widget)

		local list = PluginUI.createItemListFromExisting(main, mainframe.Items)
		VersionControl.VersionViewerUIList = list
	end
	do
		local widget, mainframe = PluginUI.createEditorWidget(ui.EditorFrame, "SourceViewer", "Source Viewer", 
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
	PluginUI.createHeader(list, "WARNING: The github sync functionality is still very early, do not use it for anything except testing!")
	
	local tokenInput
	local existingToken = plugin:GetSetting("GithubAuthToken")
	if existingToken then
		local token = GitAPI.AuthToken.new(existingToken, "fine_grained")
		VersionControl.Token = token
	end
	tokenInput = PluginUI.createAttributeBox(list, "GitHub Token Key (fine-grained) (hidden)", existingToken and string.rep("*", #existingToken) or "", function(tokenKey)
		local token = GitAPI.AuthToken.new(tokenKey, "fine_grained")
		VersionControl.Token = token
		tokenInput.Instance.ValueBox.Text = string.rep("*", #tokenInput.Instance.ValueBox.Text)
		plugin:SetSetting("GithubAuthToken", tokenKey)
	end)
	local repoInput = PluginUI.createAttributeBox(list, "Github Repo Id ('authorName/repoName')", "", function(repoId)
		VersionControl.RepoId = repoId
	end)
	
	PluginUI.createSeparator(list)
	
	local branchInput = PluginUI.createAttributeBox(list, "Target Branch", "")
	branchInput.Instance.ValueBox.PlaceholderText = "main"
	local msgInput = PluginUI.createAttributeBox(list, "Commit Message", "")
	
	local function getFilePath(inst: Instance)
		local path = {}
		local current = inst.Parent
		while current do
			table.insert(path, current.Name)
			if current:HasTag("Jexp_Root") then break end
			current = current.Parent
		end

		local reversedPath = {}
		for i = #path, 1, -1 do
			table.insert(reversedPath, path[i])
		end
		
		table.insert(reversedPath, inst.Name)
		return table.concat(reversedPath, "/") .. "/init.luau"
	end
	local function getAllFilesFromRoot(rootInst: Instance)
		local operations: {GitAPI.FileOperation} = {}
		local newFiles = {}
		for _, inst in rootInst:GetDescendants() do
			if not inst:IsA("LuaSourceContainer") then continue end
			local id = Manager.getInstId(inst)
			local versions = VersionControl.Versions[id]
			if not versions then continue end

			local latest = versions[#versions]
			if not latest then continue end

			local path = getFilePath(inst)
			table.insert(newFiles, {
				path = path,
				content = latest.props.Source
			})
		end
		for _, file in newFiles do
			table.insert(operations, file)
		end
		return operations
	end
	
	local commitDb = false
	PluginUI.createButton(list, "Commit Selected", function()
		widget.Enabled = false
		
		local branch = branchInput:Get()
		if branch == "" then branch = "main" end
		
		local token = VersionControl.Token
		assert(token, "authentication token not provided")
		
		local repo = VersionControl.RepoId
		local commitMsg = msgInput:Get()
		if commitMsg == "" then commitMsg = "Updated" end
		
		local state = Manager.WidgetState
		local world = state.World
		local components = Manager.Components
		
		local files: {GitAPI.FileOperation} = {}
		for _, ent in state.CurrentSelection do
			local inst = world:get(ent, components.Instance)
			if not inst then continue end
			
			local id = Manager.getInstId(inst)
			local versions = VersionControl.Versions[id]
			if not versions then continue end
			
			local latest = versions[#versions]
			if not latest then continue end
			
			if inst:IsA("LuaSourceContainer") then
				local filename = getFilePath(inst)
				
				table.insert(files, {
					path = filename,
					content = latest.props.Source
				})
			else
				error("cannot commit anything other than LuaSourceContainers at this time")
			end
		end
		
		GitAPI.batchCreateOrUpdate(token, repo, branch, files, commitMsg)
	end)
	PluginUI.createButton(list, "Commit Selected Src", function()
		widget.Enabled = false
		
		local branch = branchInput:Get()
		if branch == "" then branch = "main" end

		local token = VersionControl.Token
		assert(token, "authentication token not provided")

		local repo = VersionControl.RepoId
		local commitMsg = msgInput:Get()
		if commitMsg == "" then commitMsg = "Overwrite src directory" end

		local state = Manager.WidgetState
		local world = state.World
		local components = Manager.Components
		
		local selectedRoots = {}
		for _, ent in state.CurrentSelection do
			local inst = world:get(ent, components.Instance)
			if inst and inst:HasTag("Jexp_Root") then
				table.insert(selectedRoots, inst)
			end
		end
		
		assert(#selectedRoots == 1, "Exactly one root instance must be selected for overwrite operation")
		local rootInst = selectedRoots[1]
		
		local operations = getAllFilesFromRoot(rootInst)
		local result = GitAPI.batchCreateOrUpdate(token, repo, branch, operations, commitMsg)
		if result.Success then
			print("src directory successfully overwritten!")
		else
			warn("Failed to overwrite src directory:", result.Message)
		end
	end)
end

return VersionControl