--!strict

export type Disconnect = () -> ()

local create
local __extend
local __children
export type ItemGroup<T = any> = {
	add: (ItemGroup<T>, item: T) -> Disconnect,
	add_many: (ItemGroup<T>, items: {T}) -> Disconnect,
	free: (ItemGroup<T>) -> (),
	extend: typeof(__extend),
	
	items: {T},
	cleanup_handler: (T) -> (),
	children: typeof(__children),
}

__children = {(nil::any)::ItemGroup<any>}
function __extend<T>(self: any, new_cleanup_handler: (T) -> (), items: {T}?): ItemGroup<T> return nil::any end

local function group_add(self: ItemGroup, item: any)
	local items = self.items
	table.insert(items, item)

	return function()
		local idx = table.find(items, item)
		if idx then table.remove(items, idx) end
	end
end

local function group_add_many(self: ItemGroup, src: any)
	local items = self.items

	table.move(src, 1, #src, #items + 1, items)
	local clone = table.clone(src)
	return function()
		for _, item in clone do
			local idx = table.find(items, item)
			if idx then table.remove(items, idx) end
		end
	end
end

local function group_free(self: ItemGroup)
	local items = self.items
	local cleanup_handler = self.cleanup_handler
	local children = self.children
	
	for _, child: any in children do
		child:free()
	end
	for _, item in items do
		cleanup_handler(item)
	end
	table.clear(items)
end

local function group_extend<A>(self: ItemGroup, new_cleanup_handler: any, items)
	local new = create(new_cleanup_handler, items)
	table.insert(self.children, new)
	return new
end

function create<T>(cleanup_handler: (T) -> (), items: {T}?): ItemGroup<T>
	local items: {T} = if items ~= nil then table.clone(items) else {}
	
	return ({
		items = items,
		children = {},
		cleanup_handler = cleanup_handler,
		
		free = group_free,
		add = group_add,
		add_many = group_add_many,
		extend = group_extend,
	}::ItemGroup)::any
end

return {
	create = create,
	cleanup = {
		disconnect = function(c: RBXScriptConnection)
			c:Disconnect()
		end,
		destroy = game.Destroy,
		call = function(f: () -> ())
			f()
		end,
	}
}