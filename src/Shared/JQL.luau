local JDF = require(script.Parent.UDF)

local evaluateCondition

local JQL = {}

local function fuzzyMatch(str, pattern)
	if not str or not pattern then
		return false
	end

	str = string.lower(tostring(str))
	pattern = string.lower(tostring(pattern))

	return string.find(str, pattern, 1, true) ~= nil
end

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

local function parseHasMacro(expr)
	local content = expr:match("^@has%((.*)%)$")
	if not content then
		error("Invalid @has syntax: " .. expr)
	end

	local componentName = content:gsub("^%s+", ""):gsub("%s+$", "")

	return {
		type = "has",
		componentName = componentName
	}
end

local function parseMatchesMacro(expr)
	local content = expr:match("^@matches%((.*)%)$")
	if not content then
		error("Invalid @matches syntax: " .. expr)
	end

	local parts = splitArguments(content)
	if #parts ~= 2 then
		error("@matches requires exactly 2 arguments: property and pattern: " .. expr)
	end

	local property = parts[1]
	local pattern = parts[2]

	return {
		type = "matches",
		property = property,
		pattern = pattern,
	}
end

local function parseIsMacro(expr)
	local content = expr:match("^@is%((.*)%)$")
	if not content then
		error("Invalid @is syntax: " .. expr)
	end

	local parts = splitArguments(content)
	if #parts ~= 2 then
		error("@is requires exactly 2 arguments: property and type: " .. expr)
	end

	return {
		type = "is",
		property = parts[1]:gsub("^%s+", ""):gsub("%s+$", ""),
		expectedType = parts[2]:gsub("^%s+", ""):gsub("%s+$", "")
	}
end

local function parsePatternMacro(expr)
	local content = expr:match("^@pattern%((.*)%)$")
	if not content then
		error("Invalid @pattern syntax: " .. expr)
	end

	local parts = splitArguments(content)
	if #parts ~= 2 then
		error("@pattern requires exactly 2 arguments: property and pattern string: " .. expr)
	end

	local property = parts[1]:gsub("^%s+", ""):gsub("%s+$", "")
	local patternStr = parts[2]:gsub("^%s+", ""):gsub("%s+$", "")

	-- Strip required surrounding quotes
	local stripped = patternStr:match('^"(.*)"$') or patternStr:match("^'(.*)'$")
	if not stripped then
		error("@pattern second argument must be a quoted string: " .. expr)
	end

	return {
		type = "pattern",
		property = property,
		pattern = stripped
	}
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

	-- Parse descendant operator (*<)
	if condition:match("^%*<") then
		local remaining = condition:sub(3)
		return {
			type = "descendant",
			condition = parseCondition(remaining)
		}
	end

	-- Parse ancestor operator (*>)
	if condition:match("^%*>") then
		local remaining = condition:sub(3)
		return {
			type = "ancestor",
			condition = parseCondition(remaining)
		}
	end

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

	-- Parse #NAME prefix (exact name match)
	if condition:match("^#[^?]") then
		local name = condition:sub(2):gsub("^%s+", ""):gsub("%s+$", "")
		return {
			type = "pair",
			component = "Name",
			value = name,
			rawValue = name
		}
	end

	-- Parse #?PARTIAL_NAME prefix (partial name match)
	if condition:match("^#%?") then
		local partialName = condition:sub(3):gsub("^%s+", ""):gsub("%s+$", "")
		return {
			type = "matches",
			property = "Name",
			pattern = partialName,
		}
	end

	-- Parse $ATTRIBUTE = VALUE (attribute query)
	if condition:match("^%$") then
		local equalPos = nil
		local depth = 0
		for i = 1, #condition do
			local char = condition:sub(i, i)
			if char == "(" then
				depth += 1
			elseif char == ")" then
				depth -= 1
			elseif char == "=" and depth == 0 then
				equalPos = i
				break
			end
		end

		if equalPos then
			local attributeName = condition:sub(2, equalPos - 1):gsub("^%s+", ""):gsub("%s+$", "")
			local valueStr = condition:sub(equalPos + 1):gsub("^%s+", ""):gsub("%s+$", "")
			local parsedValue = JDF.from(valueStr)

			return {
				type = "attribute",
				attributeName = attributeName,
				value = parsedValue,
				rawValue = valueStr
			}
		end
	end

	if condition:match("^predicate%(") then
		return parsePredicate(condition)
	elseif condition:match("^%(.*=.*%)$") then
		return parsePair(condition)
	elseif condition:match(".*=.*") then
		return parseInlinePair(condition)
	elseif condition:match("^%.") then
		local tagName = condition:sub(2):gsub("^%s+", ""):gsub("%s+$", "")
		return {
			type = "component",
			name = tagName
		}
	elseif condition:match("^@has%(") then
		return parseHasMacro(condition)
	elseif condition:match("^@matches%(") then
		return parseMatchesMacro(condition)
	elseif condition:match("^@is%(") then
		return parseIsMacro(condition)
	elseif condition:match("^@pattern%(") then
		return parsePatternMacro(condition)
	else
		error(`invalid condition: '{condition}'`)
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
	elseif queryTree.type == "has" then
		return "has:" .. queryTree.componentName
	elseif queryTree.type == "matches" then
		return "matches:" .. queryTree.property .. "~" .. tostring(queryTree.pattern)
	elseif queryTree.type == "is" then
		return "is:" .. queryTree.property .. ":" .. queryTree.expectedType
	elseif queryTree.type == "pattern" then
		return "pattern:" .. queryTree.property .. "~" .. queryTree.pattern
	elseif queryTree.type == "attribute" then
		return "attr:" .. queryTree.attributeName .. "=" .. tostring(queryTree.value)
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
	elseif queryTree.type == "descendant" then
		return "descendant(" .. getQueryCacheKey(queryTree.condition) .. ")"
	elseif queryTree.type == "ancestor" then
		return "ancestor(" .. getQueryCacheKey(queryTree.condition) .. ")"
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

local function estimateConditionCost(condition, world, componentMap, tagMap, attributeMap)
	if condition.type == "component" then
		local component = componentMap[condition.name] or tagMap[condition.name]
		if component then
			local count = 0
			for entity in world:query(component):iter() do
				count += 1
				if count > 1000 then break end
			end
			return count
		end
		return math.huge
	elseif condition.type == "has" then
		local component = componentMap[condition.componentName]
		if component then
			local count = 0
			for entity in world:query(component):iter() do
				count += 1
				if count > 1000 then break end
			end
			return count
		end
		return math.huge
	elseif condition.type == "matches" then
		return 5000
	elseif condition.type == "is" then
		return 5000
	elseif condition.type == "pattern" then
		return 5000
	elseif condition.type == "pair" then
		local component = componentMap[condition.component]
		if component then
			local count = 0
			for entity in world:query(component):iter() do
				count += 1
				if count > 500 then break end
			end
			return count * 0.1
		end
		return math.huge
	elseif condition.type == "attribute" then
		local attribute = attributeMap and attributeMap[condition.attributeName]
		if attribute then
			local count = 0
			for entity in world:query(attribute):iter() do
				count += 1
				if count > 500 then break end
			end
			return count * 0.1
		end
		return math.huge
	elseif condition.type == "and" then
		local minCost = math.huge
		for _, subcond in condition.conditions do
			local cost = estimateConditionCost(subcond, world, componentMap, tagMap, attributeMap)
			minCost = math.min(minCost, cost)
		end
		return minCost
	elseif condition.type == "or" then
		local totalCost = 0
		for _, subcond in condition.conditions do
			local cost = estimateConditionCost(subcond, world, componentMap, tagMap, attributeMap)
			totalCost = totalCost + cost
		end
		return totalCost
	elseif condition.type == "descendant" or condition.type == "ancestor" then
		return 50000
	else
		local baseCost = 10000
		if condition.wildcard then
			baseCost = baseCost * 5
		end
		return baseCost
	end
end

local function sortConditionsBySelectivity(conditions, world, componentMap, tagMap, attributeMap)
	local conditionsWithCost = {}

	for i, condition in conditions do
		local cost = estimateConditionCost(condition, world, componentMap, tagMap, attributeMap)
		table.insert(conditionsWithCost, {condition = condition, cost = cost, index = i})
	end

	table.sort(conditionsWithCost, function(a, b)
		if a.cost == b.cost then
			return a.index < b.index
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
	local visited = {}

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
			return {}
		end
	end

	return {current}
end

local function testConditionMatch(world, queryWorld, components, componentMap, tagMap, attributeMap, entity, condition)
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
	elseif condition.type == "has" then
		local component = componentMap[condition.componentName]
		if not component then return false end
		return world:has(entity, component)
	elseif condition.type == "matches" then
		local instance = world:get(entity, components.Instance)
		if not instance then return false end

		local value = instance[condition.property]
		if not value then return false end

		return fuzzyMatch(value, condition.pattern)
	elseif condition.type == "is" then
		local instance = world:get(entity, components.Instance)
		if not instance then return false end

		local value = instance[condition.property]
		if value == nil then return false end

		local enumType = condition.expectedType:match("^Enum%.(.+)$")
		if enumType then
			return typeof(value) == "EnumItem" and tostring(value.EnumType) == enumType
		end

		return typeof(value) == condition.expectedType
	elseif condition.type == "pattern" then
		local instance = world:get(entity, components.Instance)
		if not instance then return false end

		local value = instance[condition.property]
		if value == nil then return false end

		return tostring(value):match(condition.pattern) ~= nil
	elseif condition.type == "attribute" then
		local instance = world:get(entity, components.Instance)
		if not instance then return false end

		local value = instance:GetAttribute(condition.attributeName)
		return condition.value == value
	else
		local result = evaluateCondition(world, queryWorld, components, componentMap, tagMap, attributeMap, condition)
		for _, resultEntity in result do
			if resultEntity == entity then
				return true
			end
		end
		return false
	end
end

local function getAllWildcardParents(world, queryWorld, components, componentMap, tagMap, attributeMap, entity, condition)
	local matches = {}
	local current = world:parent(entity)
	local visited = {}

	while current and not visited[current] do
		visited[current] = true

		if testConditionMatch(world, queryWorld, components, componentMap, tagMap, attributeMap, current, condition) then
			table.insert(matches, current)
		end

		current = world:parent(current)
	end

	return matches
end

local function getAllWildcardChildren(world, queryWorld, components, componentMap, tagMap, attributeMap, entity, condition)
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
			if testConditionMatch(world, queryWorld, components, componentMap, tagMap, attributeMap, child, condition) then
				table.insert(matches, child)
			end
			searchChildren(child)
		end
	end

	searchChildren(entity)
	return matches
end

local function checkSingleCondition(world, components, componentMap, attributeMap, entity, condition)
	if condition.type == "component" then
		return true -- Already filtered by the query
	elseif condition.type == "has" then
		return true -- Already filtered by the query
	elseif condition.type == "matches" then
		local instance = world:get(entity, components.Instance)
		if not instance then return false end

		local value = instance[condition.property]
		if not value then return false end

		return fuzzyMatch(value, condition.pattern)
	elseif condition.type == "is" then
		local instance = world:get(entity, components.Instance)
		if not instance then return false end

		local value = instance[condition.property]
		if value == nil then return false end

		local enumType = condition.expectedType:match("^Enum%.(.+)$")
		if enumType then
			return typeof(value) == "EnumItem" and tostring(value.EnumType) == enumType
		end

		return typeof(value) == condition.expectedType
	elseif condition.type == "pattern" then
		local instance = world:get(entity, components.Instance)
		if not instance then return false end

		local value = instance[condition.property]
		if value == nil then return false end

		return tostring(value):match(condition.pattern) ~= nil
	elseif condition.type == "pair" then
		local component = componentMap[condition.component]
		if not component then
			return false
		end

		local instance = world:get(entity, components.Instance)
		if not instance then return false end
		local value = instance[condition.component]

		return condition.value == value
	elseif condition.type == "attribute" then
		local instance = world:get(entity, components.Instance)
		if not instance then return false end

		local value = instance:GetAttribute(condition.attributeName)
		return condition.value == value
	end

	return false
end

local function evaluateLeafCondition(world, queryWorld, components, componentMap, tagMap, attributeMap, condition)
	local validEntities = {}

	-- Full instance scan for conditions that can't be indexed
	if condition.type == "matches" or condition.type == "is" or condition.type == "pattern" then
		local instanceComponent = components.Instance
		if not instanceComponent then
			return validEntities
		end

		for entity in world:query(instanceComponent):iter() do
			if checkSingleCondition(world, components, componentMap, attributeMap, entity, condition) then
				table.insert(validEntities, entity)
			end
		end

		return validEntities
	end

	local queriedComponents = {}

	if condition.type == "component" then
		local component = tagMap[condition.name]
		if component then
			table.insert(queriedComponents, component)
		end

	elseif condition.type == "has" then
		local component = componentMap[condition.componentName]
		if component then
			table.insert(queriedComponents, component)
		end

	elseif condition.type == "pair" then
		local component = componentMap[condition.component]
		if component then
			table.insert(queriedComponents, component)
		end

	elseif condition.type == "attribute" then
		local attribute = attributeMap[condition.attributeName]
		if attribute then
			table.insert(queriedComponents, attribute)
		end
	end

	if #queriedComponents == 0 then
		return validEntities
	end

	local query = queryWorld:query(unpack(queriedComponents))
	local entityList = {}

	for queryEntity in query:iter() do
		table.insert(entityList, queryEntity)
	end

	for _, queryEntity in entityList do
		for _, entity in queryWorld:get(queryEntity, components.QueryLinkedEntities) do
			if checkSingleCondition(world, components, componentMap, attributeMap, entity, condition) then
				table.insert(validEntities, entity)
			end
		end
	end

	return validEntities
end

function evaluateCondition(world, queryWorld, components, componentMap, tagMap, attributeMap, condition)
	if condition.type == "and" then
		local sortedConditions = sortConditionsBySelectivity(condition.conditions, world, componentMap, tagMap, attributeMap)

		local result = nil
		for _, subCondition in sortedConditions do
			local subResult = evaluateCondition(world, queryWorld, components, componentMap, tagMap, attributeMap, subCondition)

			if result == nil then
				result = subResult
			else
				result = intersectEntitySetsOptimized(result, subResult)
			end

			if #result == 0 then
				return {}
			end
		end
		return result or {}

	elseif condition.type == "or" then
		local resultSet = {}
		local seen = {}

		for _, subCondition in condition.conditions do
			local subResult = evaluateCondition(world, queryWorld, components, componentMap, tagMap, attributeMap, subCondition)
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
			local leafEntities = evaluateCondition(world, queryWorld, components, componentMap, tagMap, attributeMap,
				{type = "component", name = condition.condition.name or condition.condition.component or "Instance"})

			for _, entity in leafEntities do
				local parentMatches = getAllWildcardParents(world, queryWorld, components, componentMap, tagMap, attributeMap, entity, condition.condition)
				for _, parentEntity in parentMatches do
					table.insert(validEntities, entity)
					break
				end
			end
		else
			local parentMatches = evaluateCondition(world, queryWorld, components, componentMap, tagMap, attributeMap, condition.condition)
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
			local leafEntities = evaluateCondition(world, queryWorld, components, componentMap, tagMap, attributeMap,
				{type = "component", name = condition.condition.name or condition.condition.component or "Instance"})

			for _, entity in leafEntities do
				local childMatches = getAllWildcardChildren(world, queryWorld, components, componentMap, tagMap, attributeMap, entity, condition.condition)
				for _, childEntity in childMatches do
					table.insert(validEntities, entity)
					break
				end
			end
		else
			local childMatches = evaluateCondition(world, queryWorld, components, componentMap, tagMap, attributeMap, condition.condition)
			for _, childEntity in childMatches do
				local ancestors = getAncestorsAtDepthOptimized(world, childEntity, condition.depth)
				for _, ancestor in ancestors do
					table.insert(validEntities, ancestor)
				end
			end
		end

		return validEntities

	elseif condition.type == "descendant" then
		local validEntities = {}
		local ancestorMatches = evaluateCondition(world, queryWorld, components, componentMap, tagMap, attributeMap, condition.condition)

		for _, ancestorEntity in ancestorMatches do
			local descendants = JQL.getAllChildren(world, ancestorEntity)
			for _, descendant in descendants do
				table.insert(validEntities, descendant)
			end
		end

		return validEntities

	elseif condition.type == "ancestor" then
		local validEntities = {}
		local descendantMatches = evaluateCondition(world, queryWorld, components, componentMap, tagMap, attributeMap, condition.condition)
		local addedEntities = {}

		for _, descendantEntity in descendantMatches do
			local current = world:parent(descendantEntity)
			local visited = {}

			while current and not visited[current] do
				visited[current] = true

				if not addedEntities[current] then
					addedEntities[current] = true
					table.insert(validEntities, current)
				end

				current = world:parent(current)
			end
		end

		return validEntities

	else
		return evaluateLeafCondition(world, queryWorld, components, componentMap, tagMap, attributeMap, condition)
	end
end

function JQL.executeQuery(world, queryWorld, components, componentMap, tagMap, attributeMap, condition)
	return evaluateCondition(world, queryWorld, components, componentMap, tagMap, attributeMap or {}, condition)
end

function JQL.parseQuery(queryText)
	return parseExpression(queryText)
end

-- Cache for parent trees to avoid recomputation
local parentTreeCache = {}
local cacheSize = 0
local MAX_CACHE_SIZE = 1000

function JQL.collectParentTree(world, entity, visited, useCache)
	useCache = useCache ~= false

	if useCache and parentTreeCache[entity] then
		return parentTreeCache[entity]
	end

	visited = visited or {}
	local tree = {}

	if visited[entity] then
		return tree
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

	if useCache and cacheSize < MAX_CACHE_SIZE then
		parentTreeCache[entity] = tree
		cacheSize = cacheSize + 1
	end

	return tree
end

function JQL.clearParentTreeCache()
	parentTreeCache = {}
	cacheSize = 0
end

function JQL.getAllChildren(world, entity, maxDepth)
	local children = {}
	local visited = {}
	maxDepth = maxDepth or 100

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

function JQL.isOnPathToValidEntity(world, entity, validEntitySet)
	if validEntitySet[entity] then
		return true
	end

	local current = world:parent(entity)
	local depth = 0
	local maxDepth = 50

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