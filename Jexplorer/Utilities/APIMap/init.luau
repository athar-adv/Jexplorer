--!optimize 2

--[[

+++++                                                                                               
+++++                                                                                        ++++   
+++++                                                                                        ++++   
+++++   +++++++++++++    +++++   +++++   ++++ ++++++++      ===========      ++++++++++   ++++++++++
+++++   ++++++++++++++    +++++ +++++    +++++++ ++++++    ======  =====   +++++++ ++++++   +++++   
+++++   ++++     +++++     +++++++++     +++++     +++++  =====     =====  ++++      ++++    ++++   
+++++   ++++      ++++      +++++++      ++++      +++++  =============== +++++              ++++   
+++++   ++++      ++++      +++++++      ++++      +++++  =====      ====  ++++              ++++   
+++++   ++++      ++++    +++++ ++++     +++++    ++++++  =====     =====  +++++    +++++    ++++   
+++++   ++++      ++++   +++++   +++++   ++++++++++++++    =============    ++++++++++++     +++++++
+++++   ++++      ++++  +++++     +++++  ++++  ++++++         ===========     ++++++++        ++++++
                                         ++++                        =====                          
                                         ++++                         =====                         
                                         ++++                           =====                       
                                                                         =====                      
                                                                          =====                     
                                                                            =====                   
                                                                             ===                    
v1.4.3

A super easy and efficient API map builder for Roblox,
with plugin support and smart cross-communication.


GitHub:
https://github.com/AlexanderLindholt/Inxpect

DevForum:
https://devforum.roblox.com/t/3799622


--------------------------------------------------------------------------------
MIT License

Copyright (c) 2025 Alexander Lindholt

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
--------------------------------------------------------------------------------

]]--

--[[

What the different cache locations are for:
- Workspace: Current game
- StudioService: Current session (edit mode only)
- Plugin: Current plugin

They are all needed and work together. Very smart :D

]]--

-- Attempt to find the plugin object.
local plugin = script:FindFirstAncestorOfClass("Plugin")

-- Services.
local StudioService = if plugin then game:GetService("StudioService") else nil
local HttpService = game:GetService("HttpService")
local RunService = game:GetService("RunService")

-- API map type.
type APIMap = {
	[string]: {
		[string]: {
			Type: string,
			Writable: boolean
		}
	}
}

-- Tags list for validation.
local readOnlyTags = {
	ReadOnly = true,
	NotScriptable = true,
	NotCreatable = true
}
-- Types map for conversion.
local types = {
	--bool = "boolean",
	--int = "number",
	--float = "number",
	--double = "number",
	--int32 = "number",
	--int64 = "number",
	--int16 = "number",
	--int8 = "number"
}

-- Function for translating the type found in API dump into Luau type.
local function translateType(valueType)
	return if valueType.Category == "Class" then
		"Instance"
		elseif valueType.Category == "Enum" then
		"Enum."..valueType.Name
		else
		types[valueType.Name] or valueType.Name
end

-- Function for creating property data table.
local function createProperty(member)
	local writable = true
	local readable = true
	do -- Detect read-only.
		local security = member.Security
		if security ~= "None" then
			if security.Write and security.Write ~= "None" then
				writable = false
			end
			if security.Read and security.Read ~= "None" then
				readable = false
			end
		end
		if member.Tags then
			for _, tag in member.Tags do
				if readOnlyTags[tag] then writable = false end
			end
		end
	end
	
	return {Type = translateType(member.ValueType), Category = member.Category or "UNKNOWN CATEGORY", Writable = writable, Readable = readable}
end

-- API map builder function.
local function buildMap(): ({[string]: {[string]: {Type: string, Category: string, Writable: boolean, Readable: boolean}}}, string)
	-- Let copies of this library know that we're building the map.
	workspace:SetAttribute("APIMapBuilding", true)
	
	-- Grab the latest Roblox API dump from GitHub.
	local success, apiDump = pcall(HttpService.GetAsync, HttpService,
		"https://raw.githubusercontent.com/MaximumADHD/Roblox-Client-Tracker/refs/heads/roblox/API-Dump.json",
		true -- We disable caching because we only request this data once.
	)
	-- Decode the API dump.
	apiDump = HttpService:JSONDecode(apiDump)
	
	-- Build map.
	local map = {}
	local rawMap = {}
	for _, class in apiDump.Classes do
		rawMap[class.Name] = class
	end
	for _, class in apiDump.Classes do
		-- Skip classes that are not creatable.
		if (class.Tags and class.Tags.NotCreatable) then continue end
		
		-- The current class's properties table.
		local properties = {}
		
		-- Gather superclasses.
		local superClasses = {}
		local superClass = rawMap[class.Superclass]
		while superClass do
			table.insert(superClasses, superClass)
			superClass = rawMap[superClass.Superclass]
		end
		-- Inherit properties from superclasses.
		for index = #superClasses, 1, -1 do
			local superClass = superClasses[index]
			for _, member in superClass.Members do
				if member.MemberType == "Property" then
					properties[member.Name] = createProperty(member)
				end
			end
		end
		
		-- Add local properties.
		for _, member in class.Members do
			if member.MemberType == "Property" then
				properties[member.Name] = createProperty(member)
			end
		end
		
		-- Add to map.
		map[class.Name] = properties
	end
	
	-- Cache map.
	local encodedMap = HttpService:JSONEncode(map)
	-- Let copies of this library know that we're no longer building.
	workspace:SetAttribute("APIMapBuilding", nil)
	
	-- Return map.
	return map, encodedMap
end

return buildMap