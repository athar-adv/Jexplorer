export type APIResult<T... = ()> = {
	Code: number,
	Message: string,
	Success: boolean,
	Unwrap: (APIResult<T...>) -> T...
}

local resultIndex = {}
local resultMt = {
	__index = resultIndex,
	__metatable = "Metatable is locked"
}

function resultMt:__tostring()
	return `APIResult({self.Success})`
end

function resultIndex:Unwrap()
	if not self.Success then
		error(`Attempt to unwrap an unsuccessful result: ({self.Code}) '{self.Message}'`)
	end
	return unpack(self.__v)
end

local function new<T...>(success: boolean, code: number, message: string?, ...: T...): APIResult<T...>
	local msg
	if message then
		msg = message
	elseif success and not message then
		msg = "OK"
	elseif not success and not message then
		msg = "FAIL"
	end
	return setmetatable({
		Code = code,
		Message = msg,
		Success = success,

		__v = table.pack(...)
	}, resultMt) :: any
end

return {
	new = new
}