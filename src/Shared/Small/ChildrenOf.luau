--!strict
local Jecs = require(script.Parent.Parent.Parent.Jecs)
local Types = require(script.Parent.Parent.Parent.Types)

type World = Types.World
type ExplorerEntity = Types.ExplorerEntity

local childrenOf = (function(world: World, parent: ExplorerEntity, a, b, c)
	if a and b and c then
		return world:query(a, b, c, Jecs.pair(Jecs.ChildOf, parent))::any
	elseif a and b then
		return world:query(a, b, Jecs.pair(Jecs.ChildOf, parent))::any
	elseif a then
		return world:query(a, Jecs.pair(Jecs.ChildOf, parent))::any
	else
		return world:query(Jecs.pair(Jecs.ChildOf, parent))::any
	end
end::any)::
((World, ExplorerEntity) -> Jecs.Query<>)
&	(<A>(World, ExplorerEntity, Jecs.Id<A>) -> Jecs.Query<A>)
&	(<A, B>(World, ExplorerEntity, Jecs.Id<A>, Jecs.Id<B>) -> Jecs.Query<A, B>)
&	(<A, B, C>(World, ExplorerEntity, Jecs.Id<A>, Jecs.Id<B>, Jecs.Id<C>) -> Jecs.Query<A, B, C>)

return childrenOf