--!optimize 2
--!strict
--!native

--[[ SimpleSignal ]]

-- Author: athar_adv

local Types = require(script.Types)

export type SignalConnection = Types.SignalConnection
export type SimpleSignal<T...=(any)> = Types.SimpleSignal<T...>

export type RBXScriptConnection = SignalConnection
export type RBXScriptSignal<T...=(any)> = SimpleSignal<T...>

-- Key for accessing the private field of connections
local CONNECTION_PRIVATE = {}

local T_ASSERT_FORMAT = "Expected '%s' for '%s', got '%s'"
local DESTROYED_MSG = "Cannot use a destroyed signal."
local SUSPENDED = "suspended"

-- ConnectParallel will error if not called from an Actor context
local IS_PARALLEL_CONTEXT = pcall(function()
	local c = game.Destroying:ConnectParallel(function()end)
	c:Disconnect()
end)

local function call(c: SignalConnection, ...)
	local private = c[CONNECTION_PRIVATE]
	
	local parallel = private.IsParallel
	local old = private.MainThread
	private.MainThread = nil
	
	if parallel then task.desynchronize() end
	private.Fn(...)
	if parallel then task.synchronize() end
	
	if c.Connected then
		private.MainThread = old
	end
end

local function mainThreadWorker(c: SignalConnection, a, ...)
	-- Initial call if arguments are provided (so coroutine.resume doesn't have to be called twice)
	if a then
		call(c, a, ...)
	end
	
	while c.Connected do
		call(c, coroutine.yield())
	end
end

local function connection_disconnect(self: SignalConnection): ()
	if not self.Connected then return end
	self.Connected = false
	local private = self[CONNECTION_PRIVATE]
	
	local t = private.MainThread
	if t then
		task.cancel(t)
	end
	private.MainThread = nil

	local connections = private.Connections
	local l = #connections
	local pos = private.Index

	if l == pos then
		connections[l] = nil
		return
	end
	local last = connections[l]
	last[CONNECTION_PRIVATE].Index = pos

	connections[pos], connections[l] = last, nil
end

local function signal_connect<T...>(self: SimpleSignal<T...>, fn: (T...) -> ()): SignalConnection
	assert(not self.Destroyed, DESTROYED_MSG)
	assert(type(fn) == "function", T_ASSERT_FORMAT:format("function", "fn", tostring(fn)))
	
	local connections = self.Connections
	local index = #connections + 1

	local connection: SignalConnection = {
		Connected = true,
		Disconnect = connection_disconnect,
		
		[CONNECTION_PRIVATE] = {
			Fn = fn,
			Connections = connections,
			Index = index,
			IsParallel = false
		}
	}
	-- Ensure the thread has a reference to the connection
	local t = task.defer(mainThreadWorker, connection)

	connection[CONNECTION_PRIVATE].MainThread = t
	table.insert(connections, connection)
	
	return connection
end
-- Essentially the same as connect, just setting the isParallel flag and asserting if inside an Actor context
local function signal_connectParallel<T...>(self: SimpleSignal<T...>, fn: (T...) -> ()): SignalConnection
	assert(not self.Destroyed, DESTROYED_MSG)
	assert(type(fn) == "function", T_ASSERT_FORMAT:format("function", "fn", tostring(fn)))
	assert(IS_PARALLEL_CONTEXT, "Scripts that connect in parallel must be rooted under an Actor.")
	
	local c = self:Connect(fn)
	c[CONNECTION_PRIVATE].IsParallel = true
	
	return c
end

local function signal_once<T...>(self: SimpleSignal<T...>, fn: (T...) -> ()): SignalConnection
	assert(not self.Destroyed, DESTROYED_MSG)
	assert(type(fn) == "function", `Function expected, got {fn}`)

	local connection
	connection = self:Connect(function(...)
		connection:Disconnect()
		fn(...)
	end)

	return connection
end

local function signal_disconnectAll<T...>(self: SimpleSignal<T...>): ()
	assert(not self.Destroyed, DESTROYED_MSG)
	
	local connections = self.Connections
	local l = #connections

	for _, connection in connections do
		local priv = connection[CONNECTION_PRIVATE]
		connection.Connected = false
		
		local t = priv.MainThread
		if not t then continue end

		task.cancel(t)
		priv.MainThread = nil
	end
	table.clear(connections)
end

local function signal_fire<T...>(self: SimpleSignal<T...>, ...: T...): ()
	assert(not self.Destroyed, DESTROYED_MSG)
	
	local connections = self.Connections
	local l = #connections
	if l == 0 then return end
	
	for i = l, 1, -1 do
		local connection = connections[i]
		local priv = connection[CONNECTION_PRIVATE]
		
		local t = priv.MainThread
		-- If the main thread is done being used, it can simply be reused (fast path)
		if t ~= nil then
			task.spawn(t, ...)
			continue
		end
		-- If the main thread is still being used (aka yielding), 
		-- create a new one and set it as the new main thread (slow path)
		local t = task.spawn(mainThreadWorker, connection, ...)
		priv.MainThread = t
	end
end

local function signal_wait<T...>(self: SimpleSignal<T...>): T...
	assert(not self.Destroyed, DESTROYED_MSG)
	
	local running = coroutine.running()

	local connection
	connection = self:Connect(function(...)
		connection:Disconnect()
		task.spawn(running, ...)
	end)

	return coroutine.yield()
end

local function signal_destroy<T...>(self: SimpleSignal<T...>): ()
	assert(not self.Destroyed, DESTROYED_MSG)
	
	self:DisconnectAll()
	self.Destroyed = true
end

--[[
	Create a new <code>SimpleSignal</code> object.
]]
local function signal_new<T...>(): SimpleSignal<T...>
	return {
		Connections = {},
		Destroyed = false,

		Destroy = signal_destroy,
		Connect = signal_connect,
		ConnectParallel = signal_connectParallel,

		Fire = signal_fire,
		Once = signal_once,
		Wait = signal_wait,
		DisconnectAll = signal_disconnectAll
	}
end

return {
	new = signal_new
}