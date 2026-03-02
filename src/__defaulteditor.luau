--!strict
--!optimize 2

local plugin = script:FindFirstAncestorOfClass("Plugin")

local main = script.Parent.Parent

local utilities = main.Utilities
local ui = main.UI

local Types = require(main.Types)

local Editor = {} -- :: Types.Editor

function Editor.init(Manager)
	
end

return Editor