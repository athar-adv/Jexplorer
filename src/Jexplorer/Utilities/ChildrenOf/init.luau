local Jecs = require(script.Parent.Parent.Jecs)
local Types = require(script.Parent.Parent.Types)

type World = Types.World
type InstanceEntity = Types.InstanceEntity

local childrenOf = (function(world: World, parent: InstanceEntity, a, b, c)
	if a and b and c then
		return world:query(a, b, c, Jecs.pair(Jecs.ChildOf, parent))
	elseif a and b then
		return world:query(a, b, Jecs.pair(Jecs.ChildOf, parent))
	elseif a then
		return world:query(a, Jecs.pair(Jecs.ChildOf, parent))
	else
		return world:query(Jecs.pair(Jecs.ChildOf, parent))
	end
end::any)::
((World, InstanceEntity) -> Jecs.Query<>)
&	(<A>(World, InstanceEntity, Jecs.Id<A>) -> Jecs.Query<A>)
&	(<A, B>(World, InstanceEntity, Jecs.Id<A>, Jecs.Id<B>) -> Jecs.Query<A, B>)
&	(<A, B, C>(World, InstanceEntity, Jecs.Id<A>, Jecs.Id<B>, Jecs.Id<C>) -> Jecs.Query<A, B, C>)

return childrenOf