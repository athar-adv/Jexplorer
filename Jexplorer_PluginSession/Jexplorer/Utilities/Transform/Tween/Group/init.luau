--!strict
--!optimize 2

type GroupImpl = {
	Items: {any},
	FreeMethod: string | (self: any) -> (),
	Children: {Group},
	IsFreed: boolean,
}

local Group = {}
export type Group = typeof(Group) & GroupImpl

function Group.Free(self: Group)
	if self.IsFreed then return end
	self.IsFreed = false
	
	local freeMethod = self.FreeMethod
	for _, v in self.Items do
		if type(v) == "function" then
			task.defer(v)
			continue
		end
		if type(freeMethod) == "string" then
			(v::any)[freeMethod](v)
			continue
		end
		freeMethod(v)
	end
	
	table.clear(self.Items)
	for _, v in self.Children do
		v:Free()
	end
end

function Group.Insert(self: Group, items: {any})
	for _, v in items do
		if type(v) == "table" or type(v) == "userdata" and typeof(self.FreeMethod) == "string" and type(v[self.FreeMethod]) ~= "function" then
			error(`'{typeof(v)}' doesn't have '{self.FreeMethod}' as a method.`, 0)
		end
		table.insert(self.Items, v)
	end
end

function Group.Remove(self: Group, items: {any})
	for _, v in items do
		local idx = table.find(self.Items, v)
		if not idx then continue end
		
		local l = #self.Items
		self.Items[idx], self.Items[l] = self.Items[l], nil
	end
end

function Group.Has(self: Group, item: any)
	return table.find(self.Items, item) ~= nil
end

function Group.Extend(self: Group, freeMethod: string | (any) -> (), items: {any}?): Group
	local group = new(freeMethod, items)
	table.insert(self.Children, group::any)
	return group
end

function new<T>(freeMethod: string | (T) -> (), items: {T}?)
	return {
		Items = items or {},
		FreeMethod = freeMethod,
		Children = {},
		IsFreed = false,
		
		Free = Group.Free,
		Insert = Group.Insert,
		Remove = Group.Remove,
		Has = Group.Has,
		Extend = Group.Extend
	} :: Group
end

return {
	new = new,
}