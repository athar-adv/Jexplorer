local JDF = require(script.Parent.JDF)

local evaluateCondition

local JQL = {}

local function splitTopLevel(text, delimiter)
	local parts = {}
	local current = ""
	local depth = 0
	local i = 1

	while i <= #text do
		local char = text:sub(i, i)

		if char == "(" then
			depth += 1
			current = current .. char
		elseif char == ")" then
			depth -= 1
			current = current .. char
		elseif char == delimiter and depth == 0 then
			if current ~= "" then
				table.insert(parts, current)
				current = ""
			end
		else
			current = current .. char
		end

		i += 1
	end

	if current ~= "" then
		table.insert(parts, current)
	end

	return parts
end

local function parseInlinePair(expr)
	local equalPos = nil
	local depth = 0
	for i = 1, #expr do
		local char = expr:sub(i, i)
		if char == "(" then
			depth += 1
		elseif char == ")" then
			depth -= 1
		elseif char == "=" and depth == 0 then
			equalPos = i
			break
		end
	end

	if not equalPos then
		error("Invalid pair syntax, missing '=': " .. expr)
	end

	local component = expr:sub(1, equalPos - 1):gsub("^%s+", ""):gsub("%s+$", "")
	local valueStr = expr:sub(equalPos + 1):gsub("^%s+", ""):gsub("%s+$", "")

	local parsedValue = JDF.from(valueStr)

	return {
		type = "pair",
		component = component,
		value = parsedValue,
		rawValue = valueStr
	}
end

local function parsePair(expr)
	local content = expr:match("^%((.*)%)$")
	if not content then
		error("Invalid pair syntax: " .. expr)
	end

	local equalPos = nil
	local depth = 0
	for i = 1, #content do
		local char = content:sub(i, i)
		if char == "(" then
			depth += 1
		elseif char == ")" then
			depth -= 1
		elseif char == "=" and depth == 0 then
			equalPos = i
			break
		end
	end

	if not equalPos then
		error("Invalid pair syntax, missing '=': " .. expr)
	end

	local component = content:sub(1, equalPos - 1):gsub("^%s+", ""):gsub("%s+$", "")
	local valueStr = content:sub(equalPos + 1):gsub("^%s+", ""):gsub("%s+$", "")

	local parsedValue = JDF.from(valueStr)

	return {
		type = "pair",
		component = component,
		value = parsedValue,
		rawValue = valueStr
	}
end

local function splitArguments(content)
	local args = {}
	local current = ""
	local depth = 0
	local i = 1

	while i <= #content do
		local char = content:sub(i, i)

		if char == "(" then
			depth += 1
			current = current .. char
		elseif char == ")" then
			depth -= 1
			current = current .. char
		elseif char == "," and depth == 0 then
			local s = current:gsub("^%s+", ""):gsub("%s+$", "")
			table.insert(args, s)
			current = ""
		else
			current = current .. char
		end

		i += 1
	end

	if current ~= "" then
		local s = current:gsub("^%s+", ""):gsub("%s+$", "")
		table.insert(args, s)
	end

	return args
end

local function parsePredicate(expr)
	local content = expr:match("^predicate%((.*)%)$")
	if not content then
		error("Invalid predicate syntax: " .. expr)
	end

	local parts = splitArguments(content)
	if #parts ~= 3 then
		error("Predicate requires exactly 3 arguments: " .. expr)
	end

	local propertyPath = parts[1]
	local component = parts[2]
	local valueStr = parts[3]

	local parsedValue = JDF.from(valueStr)

	return {
		type = "predicate",
		propertyPath = propertyPath,
		component = component,
		value = parsedValue,
		rawValue = valueStr
	}
end

local function parseCondition(condition)
	condition = condition:gsub("^%s+", ""):gsub("%s+$", "")

	-- Parse parent operators (< and <*)
	local parentDepth = 0
	local parentWildcard = false
	local remaining = condition

	-- Check for wildcard parent operator (<*)
	if remaining:match("^<%*") then
		parentWildcard = true
		remaining = remaining:sub(3)
		parentDepth = 1
	else
		-- Regular parent operator (<)
		while remaining:match("^<") do
			parentDepth = parentDepth + 1
			remaining = remaining:sub(2)
		end
	end

	if parentDepth > 0 then
		return {
			type = "parent",
			depth = parentDepth,
			wildcard = parentWildcard,
			condition = parseCondition(remaining)
		}
	end

	-- Parse child operators (> and >*)
	local childDepth = 0
	local childWildcard = false
	remaining = condition

	-- Check for wildcard child operator (>*)
	if remaining:match("^>%*") then
		childWildcard = true
		remaining = remaining:sub(3)
		childDepth = 1
	else
		-- Regular child operator (>)
		while remaining:match("^>") do
			childDepth = childDepth + 1
			remaining = remaining:sub(2)
		end
	end

	if childDepth > 0 then
		return {
			type = "child",
			depth = childDepth,
			wildcard = childWildcard,
			condition = parseCondition(remaining)
		}
	end

	if condition:match("^predicate%(") then
		return parsePredicate(condition)
	elseif condition:match("^%(.*=.*%)$") then
		return parsePair(condition)
	elseif condition:match(".*=.*") then
		return parseInlinePair(condition)
	else
		return {
			type = "component",
			name = condition
		}
	end
end

local function parseExpression(text)
	text = text:gsub("^%s+", ""):gsub("%s+$", "")

	local orParts = splitTopLevel(text, "|")
	if #orParts > 1 then
		local orConditions = {}
		for _, part in orParts do
			table.insert(orConditions, parseExpression(part:gsub("^%s+", ""):gsub("%s+$", "")))
		end
		return {
			type = "or",
			conditions = orConditions
		}
	end

	local andParts = splitTopLevel(text, "&")
	if #andParts > 1 then
		local andConditions = {}
		for _, part in andParts do
			table.insert(andConditions, parseExpression(part:gsub("^%s+", ""):gsub("%s+$", "")))
		end
		return {
			type = "and",
			conditions = andConditions
		}
	end

	if text:match("^%(.+%)$") then
		local content = text:match("^%((.+)%)$")
		return parseExpression(content)
	end

	return parseCondition(text)
end

local function getQueryCacheKey(queryTree)
	if queryTree.type == "component" then
		return "comp:" .. queryTree.name
	elseif queryTree.type == "pair" then
		return "pair:" .. queryTree.component .. "=" .. tostring(queryTree.value)
	elseif queryTree.type == "and" then
		local parts = {}
		for _, cond in queryTree.conditions do
			table.insert(parts, getQueryCacheKey(cond))
		end
		return "and(" .. table.concat(parts, ",") .. ")"
	elseif queryTree.type == "or" then
		local parts = {}
		for _, cond in queryTree.conditions do
			table.insert(parts, getQueryCacheKey(cond))
		end
		return "or(" .. table.concat(parts, ",") .. ")"
	elseif queryTree.type == "parent" then
		local wildcardStr = queryTree.wildcard and "*" or ""
		return "parent" .. wildcardStr .. queryTree.depth .. "(" .. getQueryCacheKey(queryTree.condition) .. ")"
	elseif queryTree.type == "child" then
		local wildcardStr = queryTree.wildcard and "*" or ""
		return "child" .. wildcardStr .. queryTree.depth .. "(" .. getQueryCacheKey(queryTree.condition) .. ")"
	else
		return tostring(queryTree.type)
	end
end

local function intersectEntitySetsOptimized(set1, set2)
	if #set1 > #set2 then
		set1, set2 = set2, set1
	end

	local result = {}
	local set2Map = {}

	for _, entity in set2 do
		set2Map[entity] = true
	end

	for _, entity in set1 do
		if set2Map[entity] then
			table.insert(result, entity)
		end
	end

	return result
end

local function estimateConditionCost(condition, world, componentMap, tagMap)
	if condition.type == "component" then
		local component = componentMap[condition.name] or tagMap[condition.name]
		if component then
			-- Try to estimate entity count for this component
			local count = 0
			for entity in world:query(component):iter() do
				count += 1
				if count > 1000 then break end -- Cap the counting for performance
			end
			return count
		end
		return math.huge -- Component not found = very expensive
	elseif condition.type == "pair" then
		local component = componentMap[condition.component]
		if component then
			-- Pairs are generally more selective than plain components
			local count = 0
			for entity in world:query(component):iter() do
				count += 1
				if count > 500 then break end
			end
			return count * 0.1 -- Assume pairs filter out 90% of entities
		end
		return math.huge
	elseif condition.type == "and" then
		-- AND cost is roughly the minimum of subconditions
		local minCost = math.huge
		for _, subcond in condition.conditions do
			local cost = estimateConditionCost(subcond, world, componentMap, tagMap)
			minCost = math.min(minCost, cost)
		end
		return minCost
	elseif condition.type == "or" then
		-- OR cost is roughly the sum of subconditions
		local totalCost = 0
		for _, subcond in condition.conditions do
			local cost = estimateConditionCost(subcond, world, componentMap, tagMap)
			totalCost = totalCost + cost
		end
		return totalCost
	else
		-- Parent/child relationships are generally expensive, wildcards even more so
		local baseCost = 10000
		if condition.wildcard then
			baseCost = baseCost * 5 -- Wildcard operations are much more expensive
		end
		return baseCost
	end
end

local function sortConditionsBySelectivity(conditions, world, componentMap, tagMap)
	local conditionsWithCost = {}

	for i, condition in conditions do
		local cost = estimateConditionCost(condition, world, componentMap, tagMap)
		table.insert(conditionsWithCost, {condition = condition, cost = cost, index = i})
	end

	-- Sort by cost (lower cost = more selective = better)
	table.sort(conditionsWithCost, function(a, b) 
		if a.cost == b.cost then
			return a.index < b.index -- Stable sort
		end
		return a.cost < b.cost 
	end)

	local sorted = {}
	for _, item in conditionsWithCost do
		table.insert(sorted, item.condition)
	end

	return sorted
end

local function getDescendantsAtDepthOptimized(world, entity, depth)
	if depth == 0 then
		return {entity}
	end

	local descendants = {}
	local visited = {} -- Prevent cycles

	local function collectAtDepth(currentEntity, currentDepth)
		if visited[currentEntity] or currentDepth > depth then
			return
		end
		visited[currentEntity] = true

		if currentDepth == depth then
			table.insert(descendants, currentEntity)
			return
		end
		local children = {}
		for child in world:children(currentEntity) do
			table.insert(children, child)
		end

		for _, child in children do
			collectAtDepth(child, currentDepth + 1)
		end
	end

	local rootChildren = {}
	for child in world:children(entity) do
		table.insert(rootChildren, child)
	end

	for _, child in rootChildren do
		collectAtDepth(child, 1)
	end

	return descendants
end

local function getAncestorsAtDepthOptimized(world, entity, depth)
	local current = entity

	for i = 1, depth do
		current = world:parent(current)
		if not current then
			return {} -- No ancestor at this depth
		end
	end

	return {current}
end

local function testConditionMatch(world, queryWorld, components, componentMap, tagMap, entity, condition)
	if condition.type == "component" then
		local component = componentMap[condition.name] or tagMap[condition.name]
		if not component then return false end
		return world:has(entity, component)
	elseif condition.type == "pair" then
		local component = componentMap[condition.component]
		if not component then return false end

		if not world:has(entity, component) then return false end

		local instance = world:get(entity, components.Instance)
		if not instance then return false end

		local value = instance[condition.component]
		return condition.value == value
	else
		-- For complex conditions, evaluate them recursively
		local result = evaluateCondition(world, queryWorld, components, componentMap, tagMap, condition)
		for _, resultEntity in result do
			if resultEntity == entity then
				return true
			end
		end
		return false
	end
end

local function getAllWildcardParents(world, queryWorld, components, componentMap, tagMap, entity, condition)
	local matches = {}
	local current = world:parent(entity)
	local visited = {}

	while current and not visited[current] do
		visited[current] = true

		if testConditionMatch(world, queryWorld, components, componentMap, tagMap, current, condition) then
			table.insert(matches, current)
		end

		current = world:parent(current)
	end

	return matches
end

local function getAllWildcardChildren(world, queryWorld, components, componentMap, tagMap, entity, condition)
	local matches = {}
	local visited = {}

	local function searchChildren(currentEntity)
		if visited[currentEntity] then
			return
		end
		visited[currentEntity] = true

		local children = {}
		for child in world:children(currentEntity) do
			table.insert(children, child)
		end

		for _, child in children do
			if testConditionMatch(world, queryWorld, components, componentMap, tagMap, child, condition) then
				table.insert(matches, child)
			end
			searchChildren(child)
		end
	end

	searchChildren(entity)
	return matches
end

local function checkSingleCondition(world, components, componentMap, entity, condition)
	if condition.type == "component" then
		return true -- Already filtered by the query
	elseif condition.type == "pair" then
		local component = componentMap[condition.component]
		if not component then
			return false
		end

		local instance = world:get(entity, components.Instance)
		if not instance then return false end
		local value = instance[condition.component]

		return condition.value == value
	end

	return false
end

local function evaluateLeafCondition(world, queryWorld, components, componentMap, tagMap, condition)
	local validEntities = {}
	local queriedComponents = {}
	if condition.type == "component" then
		local component = tagMap[condition.name]
		if component then
			table.insert(queriedComponents, component)
		end
	elseif condition.type == "pair" then
		local component = componentMap[condition.component]
		if component then
			table.insert(queriedComponents, component)
		end
	end

	if #queriedComponents == 0 then
		return validEntities
	end

	local query = queryWorld:query(unpack(queriedComponents))
	local entityList = {}

	for entity in query:iter() do
		table.insert(entityList, entity)
	end

	for _, queryEntity in entityList do
		for _, entity in queryWorld:get(queryEntity, components.QueryLinkedEntities) do
			if checkSingleCondition(world, components, componentMap, entity, condition) then
				table.insert(validEntities, entity)
			end
		end
	end

	return validEntities
end

function evaluateCondition(world, queryWorld, components, componentMap, tagMap, condition)
	if condition.type == "and" then
		-- Sort conditions by estimated selectivity (most selective first)
		local sortedConditions = sortConditionsBySelectivity(condition.conditions, world, componentMap, tagMap)

		local result = nil
		for _, subCondition in sortedConditions do
			local subResult = evaluateCondition(world, queryWorld, components, componentMap, tagMap, subCondition)

			if result == nil then
				result = subResult
			else
				result = intersectEntitySetsOptimized(result, subResult)
			end

			-- Early termination if result becomes empty
			if #result == 0 then
				return {}
			end
		end
		return result or {}
	elseif condition.type == "or" then
		local resultSet = {}
		local seen = {}

		for _, subCondition in condition.conditions do
			local subResult = evaluateCondition(world, queryWorld, components, componentMap, tagMap, subCondition)
			for _, entity in subResult do
				if not seen[entity] then
					seen[entity] = true
					table.insert(resultSet, entity)
				end
			end
		end
		return resultSet

	elseif condition.type == "parent" then
		local validEntities = {}

		if condition.wildcard then
			-- Wildcard parent search: find any parent that matches the condition
			local leafEntities = evaluateCondition(world, queryWorld, components, componentMap, tagMap, 
				{type = "component", name = condition.condition.name or condition.condition.component or "Instance"})

			for _, entity in leafEntities do
				local parentMatches = getAllWildcardParents(world, queryWorld, components, componentMap, tagMap, entity, condition.condition)
				for _, parentEntity in parentMatches do
					table.insert(validEntities, entity)
					break -- Only need one match per entity
				end
			end
		else
			-- Regular parent search: exact depth
			local parentMatches = evaluateCondition(world, queryWorld, components, componentMap, tagMap, condition.condition)
			for _, parentEntity in parentMatches do
				local descendants = getDescendantsAtDepthOptimized(world, parentEntity, condition.depth)
				for _, descendant in descendants do
					table.insert(validEntities, descendant)
				end
			end
		end

		return validEntities

	elseif condition.type == "child" then
		local validEntities = {}

		if condition.wildcard then
			-- Wildcard child search: find any child that matches the condition
			local leafEntities = evaluateCondition(world, queryWorld, components, componentMap, tagMap, 
				{type = "component", name = condition.condition.name or condition.condition.component or "Instance"})

			for _, entity in leafEntities do
				local childMatches = getAllWildcardChildren(world, queryWorld, components, componentMap, tagMap, entity, condition.condition)
				for _, childEntity in childMatches do
					table.insert(validEntities, entity)
					break -- Only need one match per entity
				end
			end
		else
			-- Regular child search: exact depth
			local childMatches = evaluateCondition(world, queryWorld, components, componentMap, tagMap, condition.condition)
			for _, childEntity in childMatches do
				local ancestors = getAncestorsAtDepthOptimized(world, childEntity, condition.depth)
				for _, ancestor in ancestors do
					table.insert(validEntities, ancestor)
				end
			end
		end

		return validEntities

	else
		return evaluateLeafCondition(world, queryWorld, components, componentMap, tagMap, condition)
	end
end

function JQL.executeQuery(world, queryWorld, components, componentMap, tagMap, condition)
	return evaluateCondition(world, queryWorld, components, componentMap, tagMap, condition)
end

function JQL.parseQuery(queryText)
	return parseExpression(queryText)
end
-- Cache for parent trees to avoid recomputation
local parentTreeCache = {}
local cacheSize = 0
local MAX_CACHE_SIZE = 1000

-- Optimized parent tree collection with caching and cycle detection
function JQL.collectParentTree(world, entity, visited, useCache)
	useCache = useCache ~= false -- Default to true

	if useCache and parentTreeCache[entity] then
		return parentTreeCache[entity]
	end

	visited = visited or {}
	local tree = {}

	if visited[entity] then
		return tree -- Cycle detected, return empty tree
	end
	visited[entity] = true

	table.insert(tree, entity)

	local parent = world:parent(entity)
	if parent then
		local parentTree = JQL.collectParentTree(world, parent, visited, useCache)
		for _, parentEntity in parentTree do
			table.insert(tree, parentEntity)
		end
	end

	-- Cache the result if using cache and not at max capacity
	if useCache and cacheSize < MAX_CACHE_SIZE then
		parentTreeCache[entity] = tree
		cacheSize = cacheSize + 1
	end

	return tree
end

-- Clear cache when needed (call this periodically or when memory is low)
function JQL.clearParentTreeCache()
	parentTreeCache = {}
	cacheSize = 0
end

-- MUCH more efficient getAllChildren - stops early when possible
function JQL.getAllChildren(world, entity, maxDepth)
	local children = {}
	local visited = {}
	local currentDepth = 0
	maxDepth = maxDepth or 100 -- Default depth limit to prevent infinite loops

	local function collectChildren(currentEntity, depth)
		if visited[currentEntity] or depth > maxDepth then
			return
		end
		visited[currentEntity] = true

		for child in world:children(currentEntity) do
			table.insert(children, child)
			collectChildren(child, depth + 1)
		end
	end

	collectChildren(entity, 0)
	return children
end

-- NEW: Fast ancestor chain check - much more efficient than getAllChildren
function JQL.isAncestorOf(world, potentialAncestor, entity, maxDepth)
	maxDepth = maxDepth or 1000
	local current = entity
	local depth = 0

	while current and depth < maxDepth do
		current = world:parent(current)
		depth = depth + 1

		if current == potentialAncestor then
			return true
		end
	end

	return false
end

-- NEW: Check if entity is on path to any valid entity (much more efficient)
function JQL.isOnPathToValidEntity(world, entity, validEntitySet)
	-- Check if entity itself is valid
	if validEntitySet[entity] then
		return true
	end

	-- Check if any ancestor is valid (entity is descendant of valid entity)
	local current = world:parent(entity)
	local depth = 0
	local maxDepth = 50 -- Reasonable limit for UI hierarchies

	while current and depth < maxDepth do
		if validEntitySet[current] then
			return true
		end
		current = world:parent(current)
		depth = depth + 1
	end

	return false
end

return JQL