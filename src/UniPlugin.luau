--!strict
--!optimize 2
--version 0.0.0

--[[
	UniPlugin: Plugins, unified.
	
	Author: athar_adv
]]
	--[=[
	@type Api {[string]: any}
	@within UniPlugin
	A publicly exported interface for the UniPlugin.
]=]
--[=[
	@class UniPluginConnection
	A connection that can be closed.
]=]
--[=[
	@prop isClosed boolean
	@within UniPluginConnection
	Indicates wether or not `UniPluginConnection:close()` has been called or not.
]=]
--[=[
	@method close
	@within UniPluginConnection
	Closes this `UniPluginConnection`. Sets `UniPluginConnection.isClosed` to true.
]=]

--[=[
	Wraps a Roblox `Plugin` instance to provide a shared
	export/import system between plugins.

	@class UniPlugin
]=]
--[=[
	@prop plugin Plugin
	@within UniPlugin
	The Plugin this UniPlugin is associated with.
]=]
--[=[
	@prop apis {[string]: Api}
	@within UniPlugin
	All registered public apis.
]=]
--[=[
	@prop isClosed boolean
	@within UniPlugin
	If `UniPlugin:close()` has been called. If this is true, calling any method will throw an error.
]=]

export type Api = {[string]: any}
export type UniPluginConnection = {
	close: (UniPluginConnection) -> (),
	isClosed: boolean
}

local exports: {[string]: UniPlugin} = shared

local MAIN_API_ALIAS = "main"

if not shared.__UniPluginExportOpened then
	shared.__UniPluginExportOpened = Instance.new("BindableEvent")
end
local ExportOpened: BindableEvent = shared.__UniPluginExportOpened

local UniPlugin = {}

type Impl = {
	plugin: Plugin,
	apis: {[string]: Api},
	onCloseListeners: {() -> ()},
	connectionsToClose: {UniPluginConnection},
	isClosed: boolean,
	closerConnections: {RBXScriptConnection}
}
export type UniPlugin = typeof(UniPlugin) & Impl
export type ImportedUniPlugins = () -> ...UniPlugin

local function findAndRemove<V>(tbl: {[any]: V}, v: V)
	local idx = table.find(tbl, v)
	if idx then table.remove(tbl, idx) end
end

local function checkIsClosed(self: UniPlugin, methodName: string)
	if self.isClosed then
		error(`UniPlugin '{self.plugin.Name}' is closed, cannot call UniPlugin:{methodName}(...)`, 0)
	end
end

--[=[
	Registers this UniPlugin under `alias` in the shared exports table, making
	it discoverable by other plugins calling `withImports`. Fires the global
	ExportOpened event so any waiting `withImports` listeners are unblocked.

	The returned listener's `close` removes the export and can be called
	manually; it is also called automatically when the plugin unloads or is
	destroyed.

	@within UniPlugin
	@param alias string -- The name to register this plugin under
	@return UniPluginConnection -- A connection that can be closed to unregister the export
	@error "UniPlugin '{self.plugin.Name}' is closed, cannot call UniPlugin:exportAs(...)" -- Occurs if UniPlugin.isClosed is true.

	**Example Usage:**
	```lua
	local UniPlugin = require(path.to.module)(plugin)

	UniPlugin:setApi("output", {
		print = print,
		warn = warn,
		error = error
	})
	UniPlugin:setApi("requireInMyContext", {
		execute = function(module) return require(module) end
	})
	UniPlugin:exportAs("athar-adv/MyPlugin")
]=]
function UniPlugin.exportAs(self: UniPlugin, alias: string): UniPluginConnection
	checkIsClosed(self, "exportAs")
	
	exports[alias] = self
	ExportOpened:Fire(alias)

	local onClose
	local conn = {
		close = function(conn: UniPluginConnection)
			if conn.isClosed then return end
			conn.isClosed = true

			findAndRemove(self.connectionsToClose, conn)
			onClose:close()
			exports[alias] = nil
		end,
		isClosed = false
	}
	onClose = self:onClose(function()
		conn:close()
	end)
	table.insert(self.connectionsToClose, conn)
	return conn
end

--[=[
	Waits for all plugins in `aliases` to be exported, then calls `handler`
	with two arguments:
	- `plugins()` — returns all resolved UniPlugins in the same order as `aliases` via multiple returns.
	- `bindOnImportClosed(fn)` — registers a single callback (overwriting any previous one) that fires whenever this import group is torn down, whether because one of the imported plugins closed naturally or because the returned listener was closed manually.

	The handler re-runs automatically each time all aliases become available
	again after a close. Duplicate aliases are silently deduplicated. Passing
	an empty `aliases` table is a no-op and returns an inert connection.

	Close the returned connection to stop listening entirely and tear down the
	current import group.

	@within UniPlugin
	@param aliases {string} -- List of plugin export aliases to wait for
	@param handler (plugins: () -> ...UniPlugin, bindOnImportClosed: (fn: () -> ()) -> ()) -> () -- Called once all aliases are available; re-runs if the group is torn down and re-established
	@return UniPluginConnection -- A connection that can be closed to stop tracking imports
	@error "UniPlugin '{self.plugin.Name}' is closed, cannot call UniPlugin:withImports(...)" -- Occurs if UniPlugin.isClosed is true.

	**Example Usage:**
	```lua
	local UniPlugin = require(path.to.module)(plugin)

	UniPlugin:withImports({"athar-adv/Jexplorer", "athar-adv/SimpleComplete"}, function(plugins, onImportClosed)
		local jexplorer, simpleComplete = plugins()

		local items = {}
		do
			local manager = jexplorer:getApi("manager")
			manager.setSetting("VirtualScrollFrameBuffer", 20)
			
			table.insert(items, manager.ExplorerFrame.ClassIconStyleRuleCreated:Connect(function(rule)
				rule:SetProperty("Image", "rbxassetid://1234")
			end))
		end
		do
			local selectionImports = simpleComplete:getApi("selectionImports")

			selectionImports.triggerAtCurrentPosition()
		end
		onImportClosed(function()
			for _, v in items do
				v:Disconnect()
			end
		end)
	end)
]=]
function UniPlugin.withImports(self: UniPlugin, aliases: {string}, handler: (plugins: ImportedUniPlugins, bindOnImportClosed: (fn: () -> ()) -> ()) -> ()): UniPluginConnection
	checkIsClosed(self, "withImports")
	
	if #aliases == 0 then
		return {
			close = function(conn) conn.isClosed = true end,
			isClosed = false
		}
	end

	local seen: {[string]: boolean} = {}
	local dedupedAliases: {string} = {}
	for _, alias in aliases do
		if not seen[alias] then
			seen[alias] = true
			table.insert(dedupedAliases, alias)
		end
	end

	local onCloses: {UniPluginConnection} = {}
	local generation = 0
	local onImportClosed: (() -> ())?

	local conn
	local function onPlugins(unips: {[string]: UniPlugin})
		local currentGen = generation
		local function unipClosed()
			if generation ~= currentGen then return end
			generation += 1
			for _, oc in onCloses do oc:close() end
			table.clear(onCloses)
			local cb = onImportClosed
			onImportClosed = nil
			if cb then cb() end
			conn:close()
			self:withImports(aliases, handler)
		end
		for _, unip in unips do
			local onClose = unip:onClose(unipClosed)
			table.insert(onCloses, onClose)
		end
		local ordered: {UniPlugin} = {}
		for _, alias in dedupedAliases do
			table.insert(ordered, unips[alias])
		end
		handler(
			function()
				return table.unpack(ordered)
			end,
			function(fn)
				onImportClosed = fn
			end
		)
	end

	local listenerConn: RBXScriptConnection
	local t = task.spawn(function()
		local resolved: {[string]: UniPlugin} = {}
		local unresolved: {[string]: boolean} = {}

		for _, alias in dedupedAliases do
			if exports[alias] then
				resolved[alias] = exports[alias]
			else
				unresolved[alias] = true
			end
		end

		if next(unresolved) then
			listenerConn = ExportOpened.Event:Connect(function(alias: string)
				if not unresolved[alias] then return end
				resolved[alias] = exports[alias]
				unresolved[alias] = nil
				if next(unresolved) == nil then
					listenerConn:Disconnect()
					onPlugins(resolved)
				end
			end)

			for alias in unresolved do
				if exports[alias] then
					resolved[alias] = exports[alias]
					unresolved[alias] = nil
				end
			end
			if next(unresolved) == nil then
				listenerConn:Disconnect()
				onPlugins(resolved)
			end
		else
			onPlugins(resolved)
		end
	end)

	conn = {
		close = function(conn: UniPluginConnection)
			if conn.isClosed then return end
			conn.isClosed = true
			findAndRemove(self.connectionsToClose, conn)

			generation += 1
			if listenerConn then listenerConn:Disconnect() end
			for _, oc in onCloses do oc:close() end
			table.clear(onCloses)
			local cb = onImportClosed
			onImportClosed = nil
			if cb then cb() end
			if coroutine.status(t) ~= "dead" then
				task.cancel(t)
			end
		end,
		isClosed = false
	}
	table.insert(self.connectionsToClose, conn)

	return conn
end

--[=[
	Registers `fn` to be called when this plugin is torn down (i.e. when the
	plugin unloads or is destroyed). Multiple listeners can be registered and
	all will fire on close.

	The returned listener's `close` unregisters `fn` and can be used to cancel
	the subscription before the plugin closes.

	@within UniPlugin
	@param fn () -> () -- Callback to invoke on plugin teardown
	@return UniPluginConnection -- A connection that can be closed to cancel the subscription
	@error "UniPlugin '{self.plugin.Name}' is closed, cannot call UniPlugin:onClose(...)" -- Occurs if UniPlugin.isClosed is true.

	**Example Usage:**
	```lua
	local UniPlugin = require(path.to.module)(plugin)

	UniPlugin:onClose(function()
		print("Whyd you close my plugin :(")
	end)
]=]
function UniPlugin.onClose(self: UniPlugin, fn: () -> ()): UniPluginConnection
	checkIsClosed(self, "onClose")
	
	table.insert(self.onCloseListeners, fn)
	local conn = {
		close = function(conn: UniPluginConnection)
			if conn.isClosed then return end
			conn.isClosed = true
			findAndRemove(self.onCloseListeners, fn)
			findAndRemove(self.connectionsToClose, conn)
		end,
		isClosed = false
	}
	table.insert(self.connectionsToClose, conn)
	return conn
end

--[=[
	Stores `api` under `alias` (defaults to `"main"`) on this UniPlugin.
	Retrieve it from another plugin via `getApi`.

	@within UniPlugin
	@param alias string? -- The alias to store the API under. Defaults to `"main"`
	@param api Api -- The API table to store
	@error "UniPlugin '{self.plugin.Name}' is closed, cannot call UniPlugin:setApi(...)" -- Occurs if UniPlugin.isClosed is true.

	**Example Usage:**
	```lua
	local UniPlugin = require(path.to.module)(plugin)

	UniPlugin:setApi("output", {
		print = print,
		warn = warn,
		error = error
	})
	UniPlugin:setApi("requireInMyContext", {
		execute = function(module) return require(module) end
	})
	UniPlugin:exportAs("athar-adv/MyPlugin")
]=]
function UniPlugin.setApi(self: UniPlugin, alias: string?, api: Api): ()
	checkIsClosed(self, "setApi")
	
	local alias = alias or MAIN_API_ALIAS
	self.apis[alias] = api
end

--[=[
	Returns the Api stored under `alias` (defaults to `"main"`).
	Errors if no Api has been set for that alias.

	@within UniPlugin
	@param alias string? -- The alias to look up. Defaults to `"main"`
	@return Api -- The stored API table
	@error "UniPlugin '{self.plugin.Name}' is closed, cannot call UniPlugin:getApi(...)" -- Occurs if UniPlugin.isClosed is true.

	**Example Usage:**
	```lua
	local UniPlugin = require(path.to.module)(plugin)

	UniPlugin:withImports({"athar-adv/Jexplorer", "athar-adv/SimpleComplete"}, function(plugins, onImportClosed)
		local jexplorer, simpleComplete = plugins()

		local items = {}
		do
			local manager = jexplorer:getApi("manager")
			print(manager.executeJqlQuery("#?player"))

			local dependencies = jexplorer:getApi("dependencies")
			print(dependencies.GitApi)
		end
		do
			local editor = simpleComplete:getApi("editor")
			print(editor.getOpenDocValue().currentImportedModules)
		end
	end)
]=]
function UniPlugin.getApi(self: UniPlugin, alias: string?): Api
	checkIsClosed(self, "getApi")
	
	local alias = alias or MAIN_API_ALIAS
	return assert(self.apis[alias], `Could not find Api '{alias}' inside UniPlugin '{self.plugin.Name}'`)
end

--[=[
	Closes this UniPlugin. Cleans up any connections, fires `onClose` handlers,
	and makes all methods error on subsequent calls.

	@within UniPlugin

	**Example Usage:**
	```lua
	local UniPlugin = require(path.to.module)(plugin)

	--[[snip!]]

	closePluginButton.Activated:Connect(function()
		UniPlugin:close()
	end)

	UniPlugin:onClose(function()
		for _, v in connections do v:Disconnect() end
	end)
]=]
function UniPlugin.close(self: UniPlugin)
	if self.isClosed then return end
	self.isClosed = true
	for _, v in self.closerConnections do
		v:Disconnect()
	end
	for _, v in table.clone(self.onCloseListeners) do
		v()
	end
	for _, v in table.clone(self.connectionsToClose) do
		v:close()
	end
	table.clear(self.closerConnections)
	table.clear(self.onCloseListeners)
	table.clear(self.connectionsToClose)
end

local created = {}

--[=[
	Returns the UniPlugin instance for the given `plugin`, creating it if one
	doesn't already exist. Only one UniPlugin is ever created per Plugin
	instance for the lifetime of the studio session.

	Automatically connects to `plugin.Unloading` and `plugin.Destroying` to
	fire all `onClose` listeners and close all active `withImports` and
	`exportAs` listeners when the plugin is torn down.

	@within UniPlugin
	@param plugin Plugin -- The Roblox Plugin instance to wrap
	@return UniPlugin
]=]
local function openUniPlugin(plugin: Plugin): UniPlugin
	local existing = created[plugin]
	if existing then return existing end

	local uniPlugin = {
		plugin = plugin,
		apis = {},
		onCloseListeners = {},
		connectionsToClose = {},
		isClosed = false,
		
		exportAs = UniPlugin.exportAs,
		withImports = UniPlugin.withImports,
		onClose = UniPlugin.onClose,
		close = UniPlugin.close,

		setApi = UniPlugin.setApi,
		getApi = UniPlugin.getApi
	} :: UniPlugin
	created[plugin] = uniPlugin
	
	uniPlugin.closerConnections = {
		plugin.Destroying:Connect(function()
			uniPlugin:close()
		end),
		plugin.Unloading:Connect(function()
			uniPlugin:close()
		end)
	}

	return uniPlugin
end

return openUniPlugin