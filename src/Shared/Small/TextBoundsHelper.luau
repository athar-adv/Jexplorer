local Types = require("../../Types")
local RawInst = require("./RawInst")

local GetStyled = game.GetStyled 
local rawindex = RawInst.rawindex

local textlabel = Instance.new("TextLabel")
textlabel.Visible = false
textlabel.Name = "BoundsCalcProxy"

return {
	SetProxyParent = function(parent: Instance)
		textlabel.Parent = parent
	end,

	GetBounds = function(Manager: Types.Manager, from: TextButton | TextLabel | TextBox): Vector2
		textlabel.Text = rawindex(from, "Text")

		textlabel.TextSize = GetStyled(from, "TextSize")
		textlabel.FontFace = GetStyled(from, "FontFace")

		return rawindex(textlabel, "TextBounds")
	end
}