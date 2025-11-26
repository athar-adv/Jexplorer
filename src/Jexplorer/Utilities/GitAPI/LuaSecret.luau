local secretToData = setmetatable({}::{[any]: {value: Secret | string, authorizedEnv: any, metadata: {[string]: any}}}, {__mode = "k"})

local function checkToRootEnv(secret: LuaSecret, levelToRootEnv: number)
	if not levelToRootEnv then
		error("levelToRootEnv is a required parameter.")
	end
	local data = secretToData[secret]
	--if debug.info(levelToRootEnv, "f") ~= data.authorizedEnv then
	--	error("attempt to access 'LuaSecret' from an unauthorized env")
	--end
end

local secretIndex = {}
secretIndex.__index = secretIndex

local newSecret

export type LuaSecret = typeof(setmetatable({}, secretIndex))

-- Returns a new <code>LuaSecret</code> with <code>prefix</code> at the start of the original value.
function secretIndex:AddPrefix(prefix: string): LuaSecret
	local value = secretToData[self].value
	if typeof(value) == "Secret" then
		return newSecret(value:AddPrefix(prefix))
	elseif typeof(value) == "string" then
		return newSecret(prefix .. value)
	else
		error(`Value of 'LuaSecret' is not a 'Secret' nor a 'string'.`)
	end
end

-- Returns a new <code>LuaSecret</code> with <code>suffix</code> at the end of the original value.
function secretIndex:AddSuffix(suffix: string): LuaSecret
	local data = secretToData[self]
	local value = data.value
	
	if typeof(value) == "Secret" then
		local new = newSecret(value:AddSuffix(suffix))
		secretToData[new].metadata = table.clone(data.metadata)
		return new
	elseif typeof(value) == "string" then
		local new = newSecret(value .. suffix)
		secretToData[new].metadata = table.clone(data.metadata)
		return new
	else
		error(`Value of 'LuaSecret' is not a 'Secret' nor a 'string'.`)
	end
end

-- Used to associate additional metadata with the <code>LuaSecret</code>.
function secretIndex:SetProperty(key: string, value: any, levelToRootEnv: number): ()
	checkToRootEnv(self, levelToRootEnv)
	secretToData[self].metadata[key] = value
end

-- Used to get additional metadata assigned by <code>LuaSecret.SetProperty</code>.
function secretIndex:GetProperty(key: string): any
	return secretToData[self].metadata[key]
end

local function getSecretValue(secret: LuaSecret, levelToRootEnv: number): Secret | string
	checkToRootEnv(secret, levelToRootEnv)
	
	local value = secretToData[secret].value
	
	if not value then error(`LuaSecret '{secret}' does not exist.`) end
	return value
end

local function assert_auth(secret: LuaSecret)
	if not secretToData[secret].value then
		error(`Expected 'LuaSecret', got '{typeof(secret)}'`)
	end
end

function newSecret(value: string | Secret, authorizedEnv: (...any) -> ...any): LuaSecret
	local proxy = newproxy(true)
	local mt = getmetatable(proxy)

	mt.__metatable = "Metatable is locked"
	mt.__index = secretIndex
	function mt:__tostring()
		return "LuaSecret"
	end
	function mt:__newindex(name, value)
		error(`'{name}' is not a valid member of 'LuaSecret'`)
	end

	secretToData[proxy] = {
		value = value,
		authorizedEnv = authorizedEnv,
		metadata = {}
	}
	
	return proxy
end

return {
	new = newSecret,
	get = getSecretValue,
	assert_is = assert_auth
}