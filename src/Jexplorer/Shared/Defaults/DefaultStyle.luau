--!strict

local Style = require(script.Parent.Parent.Style)
local Selector = require(script.Parent.Parent.Small.Selector)
local ClassIcon = require(script.Parent.Parent.Small.ClassIcon)
local Types = require(script.Parent.Parent.Parent.Types)
local InstClasses = require(script.Parent.Parent.Info.InstClasses)

local _rule = Style.rule
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
		["DarkerBackgroundColor"] = var "$DarkBackgroundColor - rgb(10, 10, 10)",

		["TextColor"] = theme:GetColor(Enum.StudioStyleGuideColor.MainText),
		["DefaultTextColor"] = var "$BackgroundColor.R > 0.5 ? $TextColor + rgb(80, 80, 80) : $TextColor - rgb(80, 80, 80)",
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
		["ScrollbarColor"] = var "$BackgroundColor.R > 0.5 ? $DarkerBackgroundColor - rgb(70, 70, 70) : $DarkerBackgroundColor - rgb(210, 210, 210)",
		["QueryInputTextSize"] = 11,
		["Theme"] = var "$BackgroundColor.R > 0.5 ? 'Light' : 'Dark'",
		["DownArrowImage"] = var "'rbxasset://studio_svg_textures/Shared/Navigation/![$Theme]/Standard/DropdownArrow.png'",
		["LegacyDownArrowImage"] = var "'rbxasset://studio_svg_textures/Shared/Navigation/![$Theme]/Standard/ArrowDown.png'",
	}
	
	local rule = function(...)
		local newrule = _rule(...)
		newrule:AddTag("Default")
		return newrule
	end :: typeof(_rule)
		
	local defaultRules = {
		rule("UniversalProps", "GuiObject", 0, {
			BorderSizePixel = 0,
			BorderColor3 = Color3.fromRGB(0, 0, 0),
			Active = true
		}),
		rule("ScrollingFrameStyle", ".JEXP_ScrollingFrame", 0, {
			AnchorPoint = Vector2.new(0.5, 1),
			BackgroundTransparency = 1,
			Position = UDim2.new(0.5, 0, 1, 0),
			ZIndex = 5,
			AutomaticCanvasSize = Enum.AutomaticSize.XY,
			BottomImage = "rbxasset://textures/ui/Scroll/scroll-middle.png",
			TopImage = "rbxasset://textures/ui/Scroll/scroll-middle.png",
			HorizontalScrollBarInset = Enum.ScrollBarInset.Always,
			VerticalScrollBarInset = Enum.ScrollBarInset.Always,
			ScrollBarThickness = "$ScrollbarWidthOffset",
			ScrollBarImageTransparency = 0,
			ScrollBarImageColor3 = "$ScrollbarColor",
		}),
		rule("ScrollBackgroundHorizontalStyle", ".JEXP_ScrollBackgroundHorizontal", 0, {
			AnchorPoint = Vector2.new(0, 1),
			BackgroundTransparency = 0,
			Position = UDim2.new(0, 0, 1, 0),
			Size = var "udim2(1, 0, 0, $ScrollbarWidthOffset)",
		}),
		rule("ScrollBackgroundVerticalStyle", ".JEXP_ScrollBackgroundVertical", 0, {
			AnchorPoint = Vector2.new(1, 0),
			BackgroundTransparency = 0,
			Position = UDim2.new(1, 0, 0, 0),
			Size = var "udim2(0, $ScrollbarWidthOffset, 1, 0)",
		}),
		rule("JExplorerUIStyle", "#JexplorerUi", 0, {
			Size = UDim2.fromScale(1, 1),
			
			rule("InstanceTreeStyle", "> #InstanceTree ScrollingFrame", 2, {
				Size = var "udim2(1, 0, 1, -($TopbarSize.Y.Offset + $PathBarSize.Y.Offset + $TabBarSize.Y.Offset + 10))",
				AutomaticCanvasSize = Enum.AutomaticSize.None
			}),
			rule("TopbarStyle", "> #Topbar", 0, {
				ZIndex = 10,
				Size = "$TopbarSize",
				Position = var "udim2(0, 0, 0, $TabBarSize.Y.Offset)",
				
				rule("QueryBarStyle", "> #QueryInput TextBox", 0, {
					AnchorPoint = Vector2.new(0, 0.5),
					ClearTextOnFocus = false,
					PlaceholderColor3 = "$DefaultTextColor",
					PlaceholderText = "Query Components...",
					FontFace = Font.fromEnum(Enum.Font.SourceSans),
					TextWrapped = true,
					TextXAlignment = Enum.TextXAlignment.Left,
					Position = var "udim2(0, $IconSizeOffset.X.Offset + 5, 0.5, 0)",
					Size = UDim2.fromScale(0.9, 0.8),
					TextSize = "$QueryInputTextSize",
					
					rule("TextPadding", "::UIPadding", 0, {
						PaddingLeft = UDim.new(0, 4)
					}),
					rule("SelectQueriedButtonStyle", "> #SelectQueried ImageButton", 0, {
						AnchorPoint = Vector2.new(1, 0.5),
						AutoButtonColor = false,
						BackgroundTransparency = 1,
						Position = UDim2.new(1, -10, 0.5, 0),
						Size = UDim2.new(0, 15, 0, 15),
						Image = "rbxassetid://103293158278743",
					}),
					rule("QueryCountStyle", "> #QueryCount TextLabel", 0, {
						Text = "0",
						AnchorPoint = Vector2.new(1, 0.5),
						BackgroundTransparency = 1,
						Position = UDim2.new(1, -29, 0.5, 0),
						Size = UDim2.new(0, 15, 0, 15),
						TextWrapped = true,
						TextXAlignment = Enum.TextXAlignment.Right,
						AutomaticSize = Enum.AutomaticSize.X,
						TextSize = 8,
					})
				}),
				rule("OpenOptionsButtonStyle", "> #Options", 0, {
					AnchorPoint = Vector2.new(0, 0.5),
					BackgroundTransparency = 1,
					Position = UDim2.new(0, 2, 0.5, 0),
					Size = UDim2.fromOffset(16, 16),
					Image = "rbxassetid://121156068055943",
					
					rule("AspectRatioConstraint", "::UIAspectRatioConstraint", 0, {
						AspectRatio = 1
					})
				}),
				rule("TabBarStyle", "> #TabBar", 0, {
					Size = "$TabBarSize",
					AnchorPoint = Vector2.new(0, 1),
					Position = UDim2.fromScale(0, 0),
					
					rule("ScrollingFrameStyle", "> #Tabs ScrollingFrame", 0, {
						BackgroundTransparency = 1,
						Size = UDim2.new(1, 0, 1, 0),
						AutomaticCanvasSize = Enum.AutomaticSize.X,
						BottomImage = "rbxasset://textures/ui/Scroll/scroll-middle.png",
						CanvasSize = UDim2.new(0, 0, 0, 0),
						ElasticBehavior = Enum.ElasticBehavior.Never,
						ScrollBarThickness = 2,
						TopImage = "rbxasset://textures/ui/Scroll/scroll-middle.png",
						MidImage = "rbxasset://textures/ui/Scroll/scroll-middle.png",
						
						rule("ListLayout", "::UIListLayout", 0, {
							FillDirection = Enum.FillDirection.Horizontal,
							SortOrder = Enum.SortOrder.LayoutOrder,
							VerticalAlignment = Enum.VerticalAlignment.Center,
							Padding = UDim.new(0, 1)
						})
					})
				}),
				rule("PathBarStyle", "> #PathBar", 0, {
					Size = "$PathBarSize",
					AnchorPoint = Vector2.new(0, 0),
					Position = UDim2.fromScale(0, 1),
					
					rule("ScrollingFrameStyle", "> #Segments ScrollingFrame", 0, {
						BackgroundTransparency = 1,
						Size = UDim2.new(1, 0, 1, 0),
						AutomaticCanvasSize = Enum.AutomaticSize.X,
						BottomImage = "rbxasset://textures/ui/Scroll/scroll-middle.png",
						CanvasSize = UDim2.new(0, 0, 0, 0),
						ElasticBehavior = Enum.ElasticBehavior.Never,
						ScrollBarThickness = 2,
						TopImage = "rbxasset://textures/ui/Scroll/scroll-middle.png",
						MidImage = "rbxasset://textures/ui/Scroll/scroll-middle.png",
						
						rule("ListLayout", "::UIListLayout", 0, {
							FillDirection = Enum.FillDirection.Horizontal,
							SortOrder = Enum.SortOrder.LayoutOrder,
							VerticalAlignment = Enum.VerticalAlignment.Center,
							Padding = UDim.new(0, 4)
						}),
						rule("PathSegmentStyle", "> #PathSegment", 0, {
							AutomaticSize = Enum.AutomaticSize.X,
							BackgroundTransparency = 1,
							Size = UDim2.new(0, 0, 1, 0),
							TextSize = 11,
							Text = "",
							FontFace = Font.fromEnum(Enum.Font.SourceSans),
							TextXAlignment = Enum.TextXAlignment.Left,
						})
					})
				})
			})
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
		rule("SelectedColor",
			getClassTagSlctr(".JEXP_SelectedColor", "GuiObject"), 12, {
				BackgroundColor3 = "$SelectedColor"
			}
		),
		rule("DarkerBackgroundStyle",
			getClassTagSlctr(".JEXP_DarkerBackground", "GuiObject"), 0, {
				BackgroundColor3 = "$DarkerBackgroundColor"
			}
		),
		rule("ArrowStyle",
			getClassTagSlctr(".JEXP_Arrow", "ImageLabel", "ImageButton"), 1, {
				Image = "$LegacyDownArrowImage",
				ImageColor3 = "$MonochromeColor",
				Size = "$IconSizeOffset"
			}
		),
		rule("MonochromeImageStyle",
			getClassTagSlctr(".JEXP_MonochromeImage", "ImageButton", "ImageLabel"), 0, {
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
		rule("DefaultTextStyle",
			getClassTagSlctr(".JEXP_DefaultText", "TextLabel", "TextButton", "TextBox"), 1, {
				PlaceholderTextColor3 = "$DefaultTextColor",
			}
		),
		rule("UIBorder", ".JEXP_Border ::UIStroke", 0, {
			Thickness = 0.4,
			Color = var "$BackgroundColor.R > 0.5 ? rgb(100, 100, 100) : rgb(0, 0, 0)",
			ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
			LineJoinMode = Enum.LineJoinMode.Miter,

			Enabled = true,
			Transparency = 0,
		}),
		rule("GrayUIBorder", ".JEXP_GrayBorder ::UIStroke", 0, {
			Thickness = 0.4,
			Color = Color3.fromRGB(50, 50, 50),
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
		rule("TabFrameStyle", ".JEXP_TabFrame Frame", 0, {
			rule("NameBoxStyle", "> #NameBox TextBox", 0, {
				Position = UDim2.new(0, 2, 0.5, 0),
				AnchorPoint = Vector2.new(0, 0.5),
				TextXAlignment = Enum.TextXAlignment.Left,
				TextYAlignment = Enum.TextYAlignment.Center,
				ClearTextOnFocus = false,
				Interactable = true,
				TextSize = 6,
				Active = false,
				BackgroundTransparency = 1,
			}),
			rule("ButtonStyle", "> #Button TextButton", 0, {
				Transparency = 1,
				Size = UDim2.new(1, 0, 1, 0),
			})
		}),
		rule("SelectedTabStyle", ".JEXP_TabFrame Frame.JEXP_SelectedColor", 10, {
			rule("SelectedNameBox", "> #NameBox TextBox", 10, {
				TextColor3 = "rgb(255, 255, 255)",
			})
		}),
		rule("InstanceFrameStyle", "#InstanceFrame Frame", 0, {
			Size = UDim2.new(1, 0, 0, 0),
			AutomaticSize = Enum.AutomaticSize.XY,
			SizeConstraint = Enum.SizeConstraint.RelativeXX,
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			ZIndex = 100,
			
			rule("BufferStyle", "> #Buffer Frame", 0, {
				AnchorPoint = Vector2.new(1, 0),
				AutomaticSize = Enum.AutomaticSize.Y,
				BackgroundTransparency = 1,
				BackgroundColor3 = Color3.fromRGB(255, 255, 255),
				Size = UDim2.new(0.94, 0, 0, 0)
			}),
			rule("ChildrenStyle", "> #Children Frame", 0, {
				Position = var "udim2(0, $IndentWidth, 0, 20)",
				AutomaticSize = Enum.AutomaticSize.Y,
				BackgroundTransparency = 1,
				Size = UDim2.new(1, 0, 0, 0),

				rule("RulerStyle", "> #Ruler Frame", 0, {
					Visible = true, --ssss
					Size = UDim2.new(0, 1, 1, 0),
					BackgroundColor3 = var "$BackgroundColor.R > 0.5 ? rgb(200, 200, 200) : rgb(70, 70, 70)",
					BackgroundTransparency = 0.5,
					AutomaticSize = Enum.AutomaticSize.Y,
					ZIndex = 0
				}),
				rule("ListStyle", "> #List Frame", 0, {
					AutomaticSize = Enum.AutomaticSize.Y,
					BackgroundTransparency = 1,
					Size = UDim2.new(1, 0, 1, 0),
				})
			}),
			rule("MainFrameStyle", "> #Main", 0, {
				Size = "$InstanceFrameSize",
				BackgroundTransparency = 1,
				ZIndex = 2,
				
				rule("OverlayStyle", "> #Overlay Frame", 0, {
					AnchorPoint = Vector2.new(0.5, 0),
					AutomaticSize = Enum.AutomaticSize.Y,
					Size = UDim2.new(20, 0, 1, 0), -- Make it extremely long to reach all the edges
					ZIndex = 2,
					
					rule("IdleOverlay", ":idle", 0, {
						BackgroundTransparency = 1,
						BackgroundColor3 = "$BackgroundColor",
					}),
					rule("SelectStyle", "> #Select ImageButton", 0, {
						BackgroundTransparency = 1,
						Size = UDim2.new(1, 0, 1, 0),
						ZIndex = 2,
					})
				}),
				rule("InstanceName", getClassTagSlctr("> #InstanceName", "TextLabel", "TextBox"), 0, {
					Active = false,
					AnchorPoint = Vector2.new(0, 0.5),
					AutomaticSize = Enum.AutomaticSize.X,
					TextSize = "$InstanceFrameTextSize",
					TextColor3 = "$InstanceFrameTextColor",
					Position = UDim2.new(0, 41, 0.5, 0),
					
					BackgroundTransparency = 1,
					ClearTextOnFocus = false,
					
					Size = UDim2.new(0, 0, 0, 15),
					ZIndex = 3,
					PlaceholderColor3 = Color3.fromRGB(255, 255, 255),
					RichText = true,
					Text = "Instance",
					TextXAlignment = Enum.TextXAlignment.Left,
					FontFace = Font.fromEnum(Enum.Font.SourceSans)
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
					ZIndex = 3,
					AnchorPoint = Vector2.new(0.5, 0.5),
					BackgroundTransparency = 1,
					Position = UDim2.new(0, 30, 0.5, 0),
					
					rule("AspectRatioConstraint", "::UIAspectRatioConstraint", 0, {
						AspectRatio = 1
					})
				}),
				rule("PackageLinkIconStyle", "> #PackageLinkIcon ImageLabel", 0, {
					AnchorPoint = Vector2.new(1, 0.5),
					BackgroundTransparency = 1,
					Position = UDim2.new(0, 0, 0.5, 0),
					Size = UDim2.new(0, 16, 0, 16),
					Image = var "'rbxasset://studio_svg_textures/Shared/Packages/![$Theme]/Standard/PackageStatus_AutoupdateOff.png'",
					ZIndex = 3,
					
					rule("AspectRatioConstraint", "::UIAspectRatioConstraint", 0, {
						AspectRatio = 0.92
					})
				}),
				rule("PendingChangesIconStyle", "> #PendingChanges ImageLabel", 0, {
					AnchorPoint = Vector2.new(0, 0.5),
					BackgroundTransparency = 1,
					Position = UDim2.new(0, -4, 0.5, 0),
					Size = UDim2.new(0, 16, 0, 16),
					Image = var "'rbxasset://studio_svg_textures/Shared/Packages/![$Theme]/Standard/Modified@3x.png'",
					ZIndex = 3,
					
					rule("AspectRatioConstraint", "::UIAspectRatioConstraint", 0, {
						AspectRatio = 0.92
					})
				}),
				rule("InsertButtonStyle", "> #Insert ImageButton", 0, {
					BackgroundTransparency = 1,
					AnchorPoint = Vector2.new(0, 0.5),
					Size = UDim2.new(0, 10, 0, 10),
					ZIndex = 3,
					Image = "rbxassetid://124663566816110",
					
					rule("AspectRatioConstraint", "::UIAspectRatioConstraint", 0, {
						AspectRatio = 0.92
					})
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
		rule("HoverEffect", ".JEXP_Hover :hover Frame", 10, {
			BackgroundTransparency = 0.6,
			BackgroundColor3 = "$HoverColor"
		}),
		
		rule("LocalScriptIcon", `{Selector.getTaggedPropertySelector("ClassName", "LocalScript")} > #Main > #ClassIcon`, 1, {
			Image = var "'rbxasset://studio_svg_textures/Shared/Scripting/![$Theme]/Standard/LegacyClientRunContext.png'",
			ImageRectOffset = Vector2.zero,
			ImageRectSize = Vector2.zero
		}),
		rule("LegacyRunContextIcon", `{Selector.getTaggedPropertySelector("ClassName", "Script")} {Selector.getTaggedPropertySelector("RunContext", "Legacy")} > #Main > #ClassIcon`, 1, {
			Image = var "'rbxasset://studio_svg_textures/Shared/Scripting/![$Theme]/Standard/LegacyServerRunContext.png'",
			ImageRectOffset = Vector2.zero,
			ImageRectSize = Vector2.zero
		}),
		rule("ServerRunContextIcon", `{Selector.getTaggedPropertySelector("ClassName", "Script")} {Selector.getTaggedPropertySelector("RunContext", "Server")} > #Main > #ClassIcon`, 1, {
			Image = var "'rbxasset://studio_svg_textures/Shared/Scripting/![$Theme]/Standard/ServerRunContext.png'",
			ImageRectOffset = Vector2.zero,
			ImageRectSize = Vector2.zero
		}),
		rule("ClientRunContextIcon", `{Selector.getTaggedPropertySelector("ClassName", "Script")} {Selector.getTaggedPropertySelector("RunContext", "Client")} > #Main > #ClassIcon`, 1, {
			Image = var "'rbxasset://studio_svg_textures/Shared/Scripting/![$Theme]/Standard/ClientRunContext.png'",
			ImageRectOffset = Vector2.zero,
			ImageRectSize = Vector2.zero
		}),
		rule("PluginRunContextIcon", `{Selector.getTaggedPropertySelector("ClassName", "Script")} {Selector.getTaggedPropertySelector("RunContext", "Plugin")} > #Main > #ClassIcon`, 1, {
			Image = var "'rbxasset://studio_svg_textures/Shared/Scripting/![$Theme]/Standard/PluginRunContext.png'",
			ImageRectOffset = Vector2.zero,
			ImageRectSize = Vector2.zero
		}),
	}
	
	return defaultTokens, defaultRules
end