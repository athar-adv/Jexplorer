--!optimize 2
--!nonstrict

local RunService = game:GetService('RunService')
local TweenService = game:GetService('TweenService')

local Signal = require(script.SimpleSignal)
local Group = require(script.Group)
local t = require(script.t)

local t_assert = t.t_assert

type SpecialProperties = {
	[string]: {
		Type: string,
		Get: (item: any) -> any,
		Set: (item: any, value: any) -> ()
	}
}
type PropertyTransforms = {
	[string]: (a: any, b: any, t: number) -> any
}

local SPECIAL_PROPERTIES: SpecialProperties = {
	["CFrame"] = {
		Type = "PVInstance",
		Get = function(item: PVInstance)
			return item:GetPivot()
		end,
		Set = function(item: PVInstance, value)
			item:PivotTo(value)
		end,
	},
	["Weight"] = {
		Type = "AnimationTrack",
		Get = function(item: AnimationTrack)
			return item.WeightCurrent
		end,
		Set = function(item: AnimationTrack, value)
			item:AdjustWeight(value)
		end,
	},
}
local PROP_TRANSFORMS: PropertyTransforms = {
	boolean = function(a, b)
		return b
	end,
	number = function(a, b, t)
		return a + (b - a) * t
	end,
	Vector3 = function(a, b, t)
		return a + (b - a) * t
	end,
	CFrame = function(a, b, t)
		return a:Lerp(b, t)
	end,
	Color3 = function(a, b, t)
		return a:Lerp(b, t)
	end,
}

local function getproperty(obj: Instance, propName: string): any
	local special = SPECIAL_PROPERTIES[propName]
	local isSpecial = special ~= nil and obj:IsA(special.Type)
	
	return isSpecial and special.Get(obj) or obj[propName]
end

local function setproperty(obj: Instance, propName: string, value: any): ()
	local special = SPECIAL_PROPERTIES[propName]
	local isSpecial = special ~= nil and obj:IsA(special.Type)
	
	if isSpecial then
		special.Set(obj, value)
	else
		obj[propName] = value
	end
end

local SimpleTween = {}

--[[
	Starts/resumes playback of this <code>SimpleTween</code>.
]]
function SimpleTween.Play(self: SimpleTween): SimpleTween
	local object 			= self.Object
	local properties 		= self.Properties
	local seconds 			= self.Seconds
	local easingStyle 		= self.EasingStyle
	local easingDirection 	= self.EasingDirection
	local trash 			= self.Trash
	local progresses		= self.Progresses
	
	local style 			= self.EasingStyle
	local dir 				= self.EasingDirection
	
	local activeConnections = 0
	
	for name, goal in properties do
		activeConnections += 1
		
		progresses[name] = getproperty(object, name)

		local initial = progresses[name]
		
		local elapsed = 0
		local conn
		conn = RunService.Heartbeat:Connect(function(dt)
			elapsed += dt 
			local alpha = math.clamp(elapsed/seconds, 0, 1)
			
			local easedAlpha = TweenService:GetValue(alpha, style, dir)
			local transform = PROP_TRANSFORMS[typeof(initial)]
			
			local target
			if transform then
				target = transform(initial, goal, easedAlpha)
			else
				alpha = 1
				target = goal
			end
			
			setproperty(object, name, target)
			progresses[name] = getproperty(object, name)
			
			if alpha < 1 then return end
			
			conn:Disconnect()
			activeConnections -= 1
			
			if activeConnections <= 0 then
				self.Completed:Fire(Enum.PlaybackState.Completed)
			end
		end)
		trash:Insert({conn})
	end
	return self
end

--[[
	Cancels playback of this <code>SimpleTween</code> (can't be resumed at the same state)
]]
function SimpleTween.Cancel(self: SimpleTween)
	table.clear(self.Progresses)
	self.Trash:Free()

	self.Completed:Fire(Enum.PlaybackState.Cancelled)
end

--[[
	Paused playback of this <code>SimpleTween</code> (can be resumed at the same state)
]]
function SimpleTween.Pause(self: SimpleTween)
	self.Trash:Free()

	self.Completed:Fire(Enum.PlaybackState.Paused)
end

export type SimpleTweenImpl = {
	Object: Instance,
	Properties: {[string]: any},
	Seconds: number,
	EasingStyle: Enum.EasingStyle,
	EasingDirection: Enum.EasingDirection,
	Progresses: {[string]: any},
	Trash: Group.Group,
	
	Completed: Signal.SimpleSignal<Enum.PlaybackState>
}
export type SimpleTween = typeof(SimpleTween) & SimpleTweenImpl

-- Creates a new <code>SimpleTween</code>.
local function new(object: Instance, properties: {[string]: any}, seconds: number, easingStyle: Enum.EasingStyle?, easingDirection: Enum.EasingDirection?)
	t_assert("object", object, "Instance")
	t_assert("properties", properties, t.map(t.string, t.any), "{[string]: any}")
	t_assert("seconds", seconds, "number")
	t_assert("easingStyle", easingStyle, t.optional(t.enum(Enum.EasingStyle)), "Enum.EasingStyle?")
	t_assert("easinDirection", easingDirection, t.optional(t.enum(Enum.EasingDirection)), "Enum.EasingDirection?")
	
	return {
		Object = object,
		Properties = properties,
		Seconds = seconds,
		EasingStyle = easingStyle or Enum.EasingStyle.Linear,
		EasingDirection = easingDirection or Enum.EasingDirection.Out,
		Progresses = {},
		Trash = Group.new("Disconnect"),
		
		Completed = Signal.new(),
		
		Pause = SimpleTween.Pause,
		Play = SimpleTween.Play,
		Cancel = SimpleTween.Cancel,
	} :: SimpleTween
end

return {
	new = new
}