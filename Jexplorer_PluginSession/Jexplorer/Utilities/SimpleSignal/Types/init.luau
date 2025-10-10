--!strict

export type SignalConnection = {
	Disconnect: typeof(
		--[[
			Disconnects the connection from the event.
		]]
		function(self: SignalConnection)end
	),
	Connected: boolean,
	
	-- Private members
	[{}]: {
		MainThread: thread?,
		Fn: (...any) -> (),
		Connections: {SignalConnection},
		Index: number,
		IsParallel: boolean
	}
}

-- Function types are made using typeof() to preserve doc comments
export type SimpleSignal<T...> = {
	Destroy: typeof(
		--[[
		Destroys this event object.
		]]
		function(self: SimpleSignal<T...>): () end
	),
	Connect: typeof(
		--[[
		Connects the given function to the event and returns an <code>SignalConnection</code> that represents it.
		
		<strong>fn</strong>: The function to connect to the event.
		]]
		function(self: SimpleSignal<T...>, fn: (T...) -> ()): SignalConnection 
			return {}::SignalConnection 
		end
	),
	ConnectParallel: typeof(
		--[[
		Connects the given function to the event (running it in a seperate core) and returns an <code>SignalConnection</code> that represents it.
		
		<strong>fn</strong>: The function to connect to the event.
		]]
		function(self: SimpleSignal<T...>, fn: (T...) -> ()): SignalConnection 
			return {}::SignalConnection 
		end
	),
	Once: typeof(
		--[[
		Connects the given function to the event (for a single invocation) and returns an <code>SignalConnection</code> that represents it.
		
		<strong>fn</strong>: The function to connect to the event.
		]]
		function(self: SimpleSignal<T...>, fn: (T...) -> ()): SignalConnection 
			return {}::SignalConnection 
		end
	),
	Fire: typeof(
		--[[
		Upon firing, all <code>SignalConnections</code> connected to this event will be called.
		
		<strong>T...</strong>: The arguments to pass to connected functions.
		]]
		function(self: SimpleSignal<T...>, ...:T...): () end
	),
	DisconnectAll: typeof(
		--[[
		Disconnects all <code>SignalConnections</code> currently connected to the event.
		]]
		function(self: SimpleSignal<T...>): () end
	),
	Wait: typeof(
		--[[
		Yields the current thread until the signal fires
		and returns the arguments provided by the signal.
		]]
		function(self: SimpleSignal<T...>): T... end
	),
	
	Connections: {SignalConnection},
	Destroyed: boolean
}

return nil