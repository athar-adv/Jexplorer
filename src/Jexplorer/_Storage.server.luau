--[[
-- Goes up expanded parents to update their expanded heights
local function cascadeUpdateExpandedHeights(world: World, entity: ExplorerEntity): number
	profilebegin("Manager::getExpandedEntityHeight")
	local components = Manager.Components
	local childrenMap = hierarchyCache.childrenMap

	local accumulatedHeight = 0
	local currentParent = parent_of(entity)

	while currentParent and world:has(currentParent, components.Expanded) do
		local parentDirectHeight = calculateDirectHeight(world, components.Expanded, childrenMap, currentParent)
		local totalParentHeight = parentDirectHeight + accumulatedHeight
		accumulatedHeight = totalParentHeight
		hierarchyCache.expandedHeights[currentParent] = accumulatedHeight

		currentParent = parent_of(currentParent)
	end

	profileend()
	return accumulatedHeight
end

ScriptEditorService:RegisterScriptAnalysisCallback("JEXP_diagnostics_listener", 0, function(request, response: any)
	local response = response or {diagnostics = {}}

	local inst: LuaSourceContainer? = request.script
	if not inst then return response end

	local scriptEntity = instanceToEntity[inst]
	if not scriptEntity then return response end

	local fn, err = 

	-- Errors take display priority over warns
	local errors, warns = {}, {}

	world:set(scriptEntity, components.ScriptWarns, warns)
	world:set(scriptEntity, components.ScriptErrors, errors)

	local frame = world:get(scriptEntity, components.Frame)
	if not frame then return response end

	if #errors == 0 and #warns == 0 then
		frame.Instance:RemoveTag("JEXP_ScriptError")
		frame.Instance:RemoveTag("JEXP_ScriptWarn")
		return response
	end

	if #errors > 0 then
		local last = table.remove(errors)
		if not table.find(frame.TagsToRemove, "JEXP_ScriptError") then
			frame.Instance:AddTag("JEXP_ScriptError")
			table.insert(frame.TagsToRemove, "JEXP_ScriptError")
		end
		return response
	end
	local last = table.remove(warns)
	if not table.find(frame.TagsToRemove, "JEXP_ScriptWarn") then
		frame.Instance:AddTag("JEXP_ScriptWarn")
		table.insert(frame.TagsToRemove, "JEXP_ScriptWarn")
	end

	return response
end)
]]