local Jecs = require("../../Jecs")

type World = Jecs.World

local cache = {}
return function<T...>(world: World, name: string, ...: Jecs.Id): Jecs.Query<T...>
	local cached = cache[name]
	if cached then return cached end
	
	local cachedq = world:query(...):cached()
	cache[name] = cachedq
	return cachedq
end
:: ((World, string) -> Jecs.Query<>)
&	(<A>(World, string, Jecs.Id<A>) -> Jecs.Query<A>)
&	(<A, B>(World, string, Jecs.Id<A>, Jecs.Id<B>) -> Jecs.Query<A, B>)
&	(<A, B, C>(World, string, Jecs.Id<A>, Jecs.Id<B>, Jecs.Id<C>) -> Jecs.Query<A, B, C>)