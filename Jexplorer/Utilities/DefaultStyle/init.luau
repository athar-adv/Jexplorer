local Style = require(script.Parent.Style)
local Selector = require(script.Parent.Selector)
local ClassIcon = require(script.Parent.ClassIcon)
local Types = require(script.Parent.Parent.Types)
local InstClasses = require(script.Parent.InstClasses)

local rule = Style.rule
local var = Style.var
local cloned = Style.cloned

local getClassTagSlctr = Selector.getClassTagSlctr

local studioSettings = settings().Studio

return function(Manager: Types.Manager): ({[string]: any}, {Style.Rule})
	local theme = studioSettings.Theme :: StudioTheme
	
	local defaultTokens = {
		["SelectedColor"] = Color3.fromRGB(25, 148, 255),
		["ScriptErrorColor"] = Color3.fromRGB(255, 44, 44),
		["ScriptWarnColor"] = Color3.fromRGB(255, 211, 53),
		["HoverColor"] = var "$BackgroundColor.R > 0.5 ? $BackgroundColor - rgb(30, 30, 30) : $BackgroundColor + rgb(30, 30, 30)",
		
		["BackgroundColor"] = theme:GetColor(Enum.StudioStyleGuideColor.MainBackground),
		["DarkBackgroundColor"] = var "$BackgroundColor - rgb(6, 6, 6)",
		["LightBackgroundColor"] = var "$BackgroundColor + rgb(10, 10, 10)",

		["TextColor"] = theme:GetColor(Enum.StudioStyleGuideColor.MainText),
		["TextColorDark"] = var "$TextColor - rgb(130, 130, 130)",

		["MonochromeColor"] = var "$BackgroundColor.R > 0.5 ? rgb(0, 0, 0) : rgb(255, 255, 255)",

		["InstanceFrameTextSize"] = 14,
		["InstanceFrameTextColor"] = var "$TextColor",
		["InstanceFrameSize"] = UDim2.new(1, 0, 0, 20),
		
		["IconSizeOffset"] = UDim2.fromOffset(16, 16),
		["TopbarSize"] = UDim2.new(1, 0, 0, 20),
		["PathBarSize"] = UDim2.new(1, 0, 0, 20),
		["TabBarSize"] = UDim2.new(1, 0, 0, 20),
		["ScrollbarWidthOffset"] = 12,
		["IndentWidth"] = 20,
		["QueryInputTextSize"] = 11
	}
	local defaultRules = {
		rule("UniversalProps", "GuiObject", 0, {
			BorderSizePixel = 0,
			BorderColor3 = Color3.fromRGB(0, 0, 0),
			Active = true
		}),
		rule("JExplorerUIStyle", "#JExplorerUi", 0, {
			Size = UDim2.fromScale(1, 1),
		}),
		
		rule("BackgroundStyle", 
			getClassTagSlctr(".JEXP_Background", "GuiObject"), 0, {
				BackgroundColor3 = "$BackgroundColor"
			}
		),
		rule("LightBackgroundStyle",
			getClassTagSlctr(".JEXP_LightBackground", "GuiObject"), 0, {
				BackgroundColor3 = "$LightBackgroundColor"
			}
		),
		rule("DarkBackgroundStyle",
			getClassTagSlctr(".JEXP_DarkBackground", "GuiObject"), 0, {
				BackgroundColor3 = "$DarkBackgroundColor"
			}
		),
		rule("DarkerBackgroundStyle",
			getClassTagSlctr(".JEXP_DarkerBackground", "GuiObject"), 0, {
				BackgroundColor3 = var "$DarkBackgroundColor - rgb(10, 10, 10)"
			}
		),
		rule("ArrowStyle",
			getClassTagSlctr(".JEXP_Arrow", "ImageLabel", "ImageButton"), 1, {
				Image = "rbxassetid://11552476728",
				ImageColor3 = "$MonochromeColor",
				Size = "$IconSizeOffset"
			}
		),
		rule("MonochromeImageStyle",
			getClassTagSlctr(".JEXP_MonochromeImage", "ImageButton"), 0, {
				ImageColor3 = "$MonochromeColor"
			}
		),
		rule("MonochromeBackgroundStyle",
			getClassTagSlctr(".JEXP_MonochromeBackground", "Frame"), 0, {
				ImageColor3 = "$MonochromeColor"
			}
		),
		rule("DarkTextStyle",
			getClassTagSlctr(".JEXP_DarkText", "TextLabel", "TextButton", "TextBox"), 1, {
				TextColor3 = "$TextColorDark"
			}
		),
		rule("TextStyle",
			getClassTagSlctr(".JEXP_Text", "TextLabel", "TextButton", "TextBox"), 1, {
				TextColor3 = "$TextColor",
			}
		),
		rule("QueryInputBarStyle", "#QueryInput", 0, {
			Position = var "udim2(0, $IconSizeOffset.X.Offset + 5, 0.5, 0)",
			Size = UDim2.fromScale(0.9, 0.8),
			TextSize = "$QueryInputTextSize"
		}),
		rule("ScrollingBarStyle",
			getClassTagSlctr(".JEXP_ScrollingFrame", "ScrollingFrame"), 0, {
				ScrollBarImageColor3 = "$DarkBackgroundColor",
				ScrollBarThickness = "$ScrollbarWidthOffset"
			}
		),
		rule("VerticalScrollingBarBackgroundStyle",
			getClassTagSlctr("#ScrollbarBackgroundVertical", "Frame"), 0, {
				Size = var "udim2(0, $ScrollbarWidthOffset, 1, 0)"
			}
		),
		rule("HorizontalScrollingBarBackgroundStyle",
			getClassTagSlctr("#ScrollbarBackgroundHorizontal", "Frame"), 0, {
				Size = var "udim2(1, 0, 0, $ScrollbarWidthOffset)"
			}
		),
		rule("UIBorder", ".JEXP_Border ::UIStroke", 0, {
			Thickness = 0.4,
			Color = Color3.fromRGB(0, 0, 0),
			ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
			LineJoinMode = Enum.LineJoinMode.Miter,

			Enabled = true,
			Transparency = 0,
		}),
		rule("GrayUIBorder", ".JEXP_GrayBorder ::UIStroke", 0, {
			Thickness = 0.2,
			Color = var "$DarkBackgroundColor",
			ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
			LineJoinMode = Enum.LineJoinMode.Miter,
			
			Enabled = true,
			Transparency = 0
		}),
		rule("DropTargetOutline", ".JEXP_DropTarget ::UIStroke", 0, {
			Thickness = 0.5,
			Color = "$MonochromeColor",
			ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
			LineJoinMode = Enum.LineJoinMode.Miter,

			Enabled = true,
			Transparency = 0,
		}),
		rule("CircleCorner", ".JEXP_CircleCorner ::UICorner", 0, {
			CornerRadius = UDim.new(1, 0)
		}),
		rule("InstanceFrameStyle", "#InstanceFrame Frame", 0, {
			Size = UDim2.new(1, 0, 0, 0),
			
			rule("ChildrenStyle", "> #Children Frame", 0, {
				Position = var "udim2(0, $IndentWidth, 0, 20)",

				rule("RulerStyle", "> #Ruler Frame", 0, {
					Visible = true, --ssss
					Size = UDim2.new(0, 1, 1, 0),
					BackgroundColor3 = Color3.fromRGB(70, 70, 70),
					BackgroundTransparency = 0.5,
					AutomaticSize = Enum.AutomaticSize.Y,
					ZIndex = 0
				})
			}),
			rule("MainFrameStyle", "> #Main", 0, {
				Size = "$InstanceFrameSize",
				BackgroundTransparency = 1,
				ZIndex = 2,
				
				rule("IdleOverlay", "> #Overlay :idle Frame", 1, {
					BackgroundTransparency = 1,
					BackgroundColor3 = "$BackgroundColor",
				}),
				rule("InstanceName", getClassTagSlctr("> #InstanceName", "TextLabel", "TextBox"), 0, {
					Active = false,
					AnchorPoint = Vector2.new(0, 0.5),
					AutomaticSize = Enum.AutomaticSize.X,
					TextSize = "$InstanceFrameTextSize",
					TextColor3 = "$InstanceFrameTextColor",
					Position = UDim2.new(0, 43, 0.5, 0),
					
					BackgroundTransparency = 1,
					ClearTextOnFocus = false,
					
					Size = UDim2.new(0, 0, 0, 15),
					ZIndex = 3,
					PlaceholderColor3 = Color3.fromRGB(255, 255, 255),
					RichText = true,
					Text = "Instance",
					TextXAlignment = Enum.TextXAlignment.Left,
				}),
				rule("ArrowStyle", "> #Arrow ImageButton", 0, {
					AnchorPoint = Vector2.new(0.5, 0.5),
					BackgroundTransparency = 1,
					Position = UDim2.new(0, 10, 0.5, 0),
					--Rotation = -90,
					ZIndex = 3,
				}),
				rule("IconStyle", "> #ClassIcon ImageLabel", 0, {
					Size = "$IconSizeOffset",
					ZIndex = 3
				})
			})
		}),
		rule("SelectedInstanceNameStyle",
			".JEXP_Selected Frame > #Main > #InstanceName", 10, {
				TextColor3 = "$TextColor"
			}
		),
		rule("InstanceNameStyleDisabled",
			`{Selector.getTaggedPropertySelector("Enabled", "false")} > #Main > #InstanceName`, 1, {
				TextSize = "$InstanceFrameTextSize",
				TextColor3 = "$TextColorDark"
			}
		),
		rule("SelectedStyle", 
			".JEXP_Selected Frame > #Main > #Overlay", 20, {
				BackgroundTransparency = 0.6,
				BackgroundColor3 = "$SelectedColor",
			}
		),
		rule("ScriptErrorStyle", 
			".JEXP_ScriptError Frame > #Main > #Overlay", 15, {
				BackgroundTransparency = 0.6,
				BackgroundColor3 = "$ScriptErrorColor",
			}
		),
		rule("ScriptWarnStyle", 
			".JEXP_ScriptWarn Frame > #Main > #Overlay", 15, {
				BackgroundTransparency = 0.6,
				BackgroundColor3 = "$ScriptWarnColor",
			}
		),
		rule("SelectedColor",
			".JEXP_SelectedColor Frame", 0, {
				BackgroundColor3 = "$SelectedColor"
			}
		),
		rule("TopbarStyle",
			getClassTagSlctr(".JEXP_Topbar", "Frame"), 0, {
				Size = "$TopbarSize",
				Position = var "udim2(0, 0, 0, $TabBarSize.Y.Offset)"
			}
		),
		rule("PathBarStyle",
			getClassTagSlctr(".JEXP_PathBar", "Frame", "ScrollingFrame"), 0, {
				Size = "$PathBarSize",
				AnchorPoint = Vector2.new(0, 0),
				Position = UDim2.fromScale(0, 1)
			}
		),
		rule("TabBarStyle",
			getClassTagSlctr(".JEXP_TabBar", "Frame"), 0, {
				Size = "$TabBarSize",
				AnchorPoint = Vector2.new(0, 1),
				Position = UDim2.fromScale(0, 0)
			}
		),
		rule("InstanceTreeStyle",
			getClassTagSlctr("#InstanceTree", "ScrollingFrame"), 0, {
				Size = var "udim2(1, 0, 1, -($TopbarSize.Y.Offset + $PathBarSize.Y.Offset + $TabBarSize.Y.Offset + 10))"
			}
		),
		rule("HoverEffect", ".JEXP_Hover :hover Frame", 10, {
			BackgroundTransparency = 0.6,
			BackgroundColor3 = "$HoverColor"
		}),
		
		rule("ClientRunContextIcon", `{Selector.getTaggedPropertySelector("RunContext", "Client")} > #Main > #ClassIcon`, 1, {
			Image = "rbxasset://studio_svg_textures/Shared/InsertableObjects/Dark/Standard/LocalScript.png",
			ImageRectOffset = Vector2.zero,
			ImageRectSize = Vector2.new(16, 16)
		}),
		rule("PluginRunContextIcon", `{Selector.getTaggedPropertySelector("RunContext", "Plugin")} > #Main > #ClassIcon`, 1, {
			Image = "rbxasset://studio_svg_textures/Shared/InsertableObjects/Dark/Standard/Attachment.png",
			ImageRectOffset = Vector2.new(16, 0),
			ImageRectSize = Vector2.new(-16, 16)
		}),
	}
	
	return defaultTokens, defaultRules
end