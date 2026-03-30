--!strict

local Style = require("../Style")
local Selector = require("../Small/Selector")
local ClassIcon = require("../Small/ClassIcon")
local Types = require("../../Types")
local InstClasses = require("../Info/InstClasses")
local Constants = require("../../Constants")

local rule = Style.rule
local var = Style.var
local cloned = Style.cloned

local getClassTagSlctr = Selector.getClassTagSlctr

local studioSettings = settings().Studio

return function(Manager: Types.Manager): ({[string]: any}, {Style.Rule})
	local theme = studioSettings.Theme :: StudioTheme
	
	local defaultTokens = {
		["SelectedColor"] = Color3.fromRGB(15, 91, 153),
		["ScriptErrorColor"] = Color3.fromRGB(255, 44, 44),
		["ScriptWarnColor"] = Color3.fromRGB(255, 211, 53),
		["HoverColor"] = var "brightness($BackgroundColor) > 0.5 ? $BackgroundColor - rgb(30, 30, 30) : $BackgroundColor + rgb(30, 30, 30)",
		
		["BackgroundColor"] = theme:GetColor(Enum.StudioStyleGuideColor.MainBackground),
		["DarkBackgroundColor"] = var "$BackgroundColor - rgb(6, 6, 6)",
		["LightBackgroundColor"] = var "$BackgroundColor + rgb(10, 10, 10)",
		["DarkerBackgroundColor"] = var "$DarkBackgroundColor - rgb(10, 10, 10)",

		["TextColor"] = var "invert($BackgroundColor)",
		["DefaultTextColor"] = var "$TextColor - rgb(80, 80, 80)",
		["TextColorDark"] = var "$TextColor - rgb(130, 130, 130)",

		["MonochromeColor"] = var "invert($BackgroundColor)",

		["InstanceFrameTextSize"] = 14,
		["InstanceFrameTextColor"] = var "$TextColor",
		["InstanceFrameSize"] = UDim2.new(1, 0, 0, 20),
		
		["IconSizeOffset"] = UDim2.fromOffset(16, 16),
		["TopbarSize"] = UDim2.new(1, 0, 0, 20),
		["PathBarSize"] = UDim2.new(1, 0, 0, 20),
		["TabBarSize"] = UDim2.new(1, 0, 0, 20),
		["ScrollbarWidthOffset"] = 12,
		["ScrollbarColor"] = var "brightness($BackgroundColor) > 0.5 ? $DarkerBackgroundColor - rgb(70, 70, 70) : $DarkerBackgroundColor - rgb(210, 210, 210)",
		["QueryInputTextSize"] = 11,
		["Theme"] = var "brightness($BackgroundColor) > 0.5 ? 'Light' : 'Dark'",
		
		["LightArrowImage"] = "rbxasset://studio_svg_textures/Shared/Navigation/Dark/Standard/ArrowDown.png",
		["DarkArrowImage"] = "rbxasset://studio_svg_textures/Shared/Navigation/Light/Standard/ArrowDown.png",
		["InvertedArrowImage"] = var "'rbxasset://studio_svg_textures/Shared/Navigation/![$SelectedTheme]/Standard/ArrowDown.png'",
		["ArrowImage"] = var "$LegacyDownArrowImage",
		
		["LegacyDownArrowImage"] = var "'rbxasset://studio_svg_textures/Shared/Navigation/![$Theme]/Standard/ArrowDown.png'",
		["FadedColor"] = var "brightness($BackgroundColor) > 0.5 ? $BackgroundColor - rgb(100, 100, 100) : $BackgroundColor + rgb(100, 100, 100)",
		["SelectedTheme"] = var "brightness($SelectedColor) > 0.5 ? 'Light' : 'Dark'",
		["SelectedMonochromeColor"] = var "brightness($SelectedColor) > 0.5 ? rgb(0, 0, 0) : rgb(255, 255, 255)",
		["CornerRadius"] = UDim.new(0, 6),
		["TabPickingRootsColor"] = Color3.fromRGB(34, 112, 29),
		["Icon16x16AspectRatio"] = 0.96
	}
	
	--local rule = function(...)
	--	local newrule = _rule(...)
	--	newrule:AddTag("Default")
	--	newrule:AddTag("DontSaveRule")
	--	return newrule
	--end :: typeof(_rule)
		
	local defaultRules = {
		rule("NoRichText", "TextButton, TextLabel, TextBox", 0, {
			RichText = false
		}),
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
		rule("JExplorerUIStyle", "#JexplorerUi", 10, {
			Size = UDim2.fromScale(1, 1),
			
			rule("InstanceTreeStyle", "> #InstanceTree Frame", 2, {
				Size = var "udim2(1, 0, 1, -($TopbarSize.Y.Offset + $PathBarSize.Y.Offset + $TabBarSize.Y.Offset))",
				AutomaticCanvasSize = Enum.AutomaticSize.None,
				ClipDescendants = true,
				AnchorPoint = Vector2.new(0.5, 1),
				BackgroundTransparency = 1,
				Position = UDim2.new(0.5, 0, 1, 0),
				ZIndex = 5,
				
				rule("ScrollContainerStyle", "> #ScrollContainer Frame", 2, {
					Size = UDim2.fromScale(1, 1),
					BackgroundTransparency = 1,
				}),
				rule("TreeScrollerStyle", "> #TreeScroller ScrollingFrame", 3, {
					Size = UDim2.fromScale(1, 1),
					BackgroundTransparency = 1,
				})
			}),
			rule("TopbarStyle", "> #Topbar", 0, {
				ZIndex = 10,
				Size = "$TopbarSize",
				Position = var "udim2(0, 0, 0, $TabBarSize.Y.Offset)",
				
				rule("QueryFrameStyle", "> #QueryInputFrame", 0, {
					AnchorPoint = Vector2.new(0, 0.5),
					Position = var "udim2(0, $IconSizeOffset.X.Offset + 5, 0.5, 0)",
					Size = UDim2.fromScale(0.9, 0.8),
					
					rule("RoundedCorner", "::UICorner", 0, {
						CornerRadius = "$CornerRadius"
					}),
					rule("BorderStyle", "::UIStroke", 10, {
						Thickness = 0.5,
						LineJoinMode = Enum.LineJoinMode.Round
					}),
					rule("ScrollerStyle", "> #Scroll", 0, {
						AutomaticCanvasSize = Enum.AutomaticSize.X,
						BackgroundTransparency = 1,
						ScrollBarThickness = 1,
						Size = UDim2.new(1, -39, 1, 0),
						BottomImage = "rbxasset://textures/ui/Scroll/scroll-middle.png",
						TopImage = "rbxasset://textures/ui/Scroll/scroll-middle.png",
						HorizontalScrollBarInset = Enum.ScrollBarInset.Always,
						VerticalScrollBarInset = Enum.ScrollBarInset.Always,
						ScrollBarImageTransparency = 0,
						ScrollBarImageColor3 = "$ScrollbarColor",
						
						rule("QueryBarStyle", "> #QueryInput TextBox", 0, {
							ClearTextOnFocus = false,
							PlaceholderColor3 = "$DefaultTextColor",
							PlaceholderText = "Query Components...",
							BackgroundTransparency = 1,
							FontFace = Font.fromEnum(Enum.Font.SourceSans),
							TextXAlignment = Enum.TextXAlignment.Left,
							Size = UDim2.fromScale(1, 1),
							AutomaticSize = Enum.AutomaticSize.X,
							TextSize = "$QueryInputTextSize",

							rule("TextPadding", "::UIPadding", 0, {
								PaddingLeft = UDim.new(0, 4)
							}),
						})
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
					Position = UDim2.fromScale(0, 0),
					AnchorPoint = Vector2.new(0, 1),
					
					rule("ScrollingFrameStyle", "> #Tabs ScrollingFrame", 0, {
						BackgroundTransparency = 1,
						Size = UDim2.new(1, 0, 1, 0),
						Position = var "udim2(0, $IconSizeOffset.X.Offset + 2, 0, 0)",
						--AutomaticCanvasSize = Enum.AutomaticSize.X,
						BottomImage = "rbxasset://textures/ui/Scroll/scroll-middle.png",
						CanvasSize = UDim2.new(0, 0, 0, 0),
						ElasticBehavior = Enum.ElasticBehavior.Never,
						ScrollBarThickness = 2,
						TopImage = "rbxasset://textures/ui/Scroll/scroll-middle.png",
						MidImage = "rbxasset://textures/ui/Scroll/scroll-middle.png",
						ScrollBarImageColor3 = "$ScrollbarColor",
						
						rule("InsertTabButtonStyle", "> #InsertTabButton TextButton", 10, {
							LayoutOrder = 999,
							Size = UDim2.new(0, 20, 0, 20)
						}),
						rule("Padding", "::UIPadding", 0, {
							PaddingLeft = UDim.new(0, 4)
						}),
						rule("ListLayout", "::UIListLayout", 0, {
							FillDirection = Enum.FillDirection.Horizontal,
							SortOrder = Enum.SortOrder.LayoutOrder,
							VerticalAlignment = Enum.VerticalAlignment.Center,
							Padding = UDim.new(0, 4)
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
						ScrollBarImageColor3 = "$ScrollbarColor",
						
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
		rule("SelectedTextColor",
			getClassTagSlctr(".JEXP_SelectedColor", "TextButton", "TextBox", "TextLabel"), 20, {
				BackgroundColor3 = "$SelectedColor",
				TextColor3 = Color3.fromRGB(255, 255, 255)
			}
		),
		rule("DarkerBackgroundStyle",
			getClassTagSlctr(".JEXP_DarkerBackground", "GuiObject"), 0, {
				BackgroundColor3 = "$DarkerBackgroundColor"
			}
		),
		rule("ArrowStyle",
			getClassTagSlctr(".JEXP_Arrow", "ImageLabel", "ImageButton"), 1, {
				Image = "$ArrowImage",
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
		rule("FadedTextStyle",
			getClassTagSlctr(".JEXP_FadedText", "TextLabel", "TextButton", "TextBox"), 1, {
				TextColor3 = "$FadedColor"
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
			BackgroundColor3 = var "brightness($BackgroundColor) > 0.5 ? $DarkBackgroundColor : $LightBackgroundColor",
			AnchorPoint = Vector2.new(0, 0.5),
			rule("RoundedCorner", "::UICorner", 0, {
				CornerRadius = "$CornerRadius"
			}),
			rule("BorderStyle", "::UIStroke", 10, {
				Thickness = 0.5,
				LineJoinMode = Enum.LineJoinMode.Round
			}),
			rule("NameBoxStyle", "> #NameBox TextBox", 0, {
				Position = UDim2.new(0, 24, 0.5, 0),  -- shifted right to make room for icon
				AnchorPoint = Vector2.new(0, 0.5),
				TextXAlignment = Enum.TextXAlignment.Left,
				TextYAlignment = Enum.TextYAlignment.Center,
				ClearTextOnFocus = false,
				Interactable = true,
				TextSize = 14,
				Active = false,
				BackgroundTransparency = 1,
				FontFace = Font.fromName("SourceSans", Enum.FontWeight.Heavy)
			}),
			rule("IconStyle", "> #Icon ImageLabel", 0, {
				Size = UDim2.new(0, 16, 0, 16),
				Position = UDim2.new(0, 2, 0.5, 0),
				AnchorPoint = Vector2.new(0, 0.5),
				BackgroundTransparency = 1,
				
				rule("RoundCorner", "::UICorner", 0, {
					CornerRadius = "$CornerRadius"
				})
			}),
			rule("ButtonStyle", "> #Button TextButton", 0, {
				Transparency = 1,
				Size = UDim2.new(1, 0, 1, 0),
			})
		}),
		rule("SelectedTabStyle", ".JEXP_TabFrame Frame.JEXP_SelectedColor", 10, {
			rule("NameBoxStyle", "> #NameBox TextBox", 10, {
				TextColor3 = "$SelectedMonochromeColor"
			}),
		}),
		rule("SelectingTabStyle", ".JEXP_TabFrame Frame.JEXP_SelectingRoots", 10, {
			BackgroundColor3 = "$TabPickingRootsColor",
			rule("NameBoxStyle", "> #NameBox TextBox", 10, {
				TextColor3 = var "brightness($TabPickingRootsColor) > 0.5 ? rgb(0, 0, 0) : rgb(255, 255, 255)"
			}),
		}),
		rule("ExplorerFrameRulerStyle", "#StickyRuler Frame", 0, {
			Position = var "udim2(0, 20, 0, 20)",
			Visible = true,
			--Size = UDim2.new(0, 1, 1, 0),
			BackgroundColor3 = var "$BackgroundColor.R > 0.5 ? rgb(200, 200, 200) : rgb(70, 70, 70)",
			BackgroundTransparency = 0.5,
			--AutomaticSize = Enum.AutomaticSize.Y,
			ZIndex = 12
		}),
		rule("ExplorerFrameStyle", ".JEXP_ExplorerFrame Frame", 0, {
			Size = UDim2.new(1, 0, 0, 0),
			AutomaticSize = Enum.AutomaticSize.XY,
			SizeConstraint = Enum.SizeConstraint.RelativeXX,
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			ZIndex = -2,
			
			rule("BufferStyle", "> #Buffer Frame", 0, {
				AnchorPoint = Vector2.new(1, 0),
				AutomaticSize = Enum.AutomaticSize.Y,
				BackgroundTransparency = 1,
				BackgroundColor3 = Color3.fromRGB(255, 255, 255),
				Size = UDim2.new(0.94, 0, 0, 0)
			}),
			rule("MainFrameStyle", "> #Main", 0, {
				Size = "$InstanceFrameSize",
				BackgroundTransparency = 1,
				ZIndex = 1,
				
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
						AspectRatio = "$Icon16x16AspectRatio"
					})
				}),
				rule("PendingChangesIconStyle", "> #PendingChanges ImageLabel", 0, {
					AnchorPoint = Vector2.new(1, 0.5),
					BackgroundTransparency = 1,
					Position = UDim2.new(0, -4, 0.5, 0),
					Size = UDim2.new(0, 16, 0, 16),
					Image = var "'rbxasset://studio_svg_textures/Shared/Packages/![$Theme]/Standard/Modified@3x.png'",
					ZIndex = 3,
					
					rule("AspectRatioConstraint", "::UIAspectRatioConstraint", 0, {
						AspectRatio = "$Icon16x16AspectRatio"
					})
				}),
				rule("InsertButtonStyle", "> #Insert ImageButton", 0, {
					BackgroundTransparency = 1,
					AnchorPoint = Vector2.new(0, 0.5),
					Size = UDim2.new(0, 10, 0, 10),
					ZIndex = 3,
					Image = "rbxassetid://124663566816110",
					
					rule("AspectRatioConstraint", "::UIAspectRatioConstraint", 0, {
						AspectRatio = "$Icon16x16AspectRatio"
					})
				}),
				rule("ReclassButtonStyle", "> #Reclass ImageButton", 0, {
					BackgroundTransparency = 1,
					AnchorPoint = Vector2.new(1, 0.5),
					Size = UDim2.new(0, 16, 0, 16),
					ZIndex = 3,
					Image = var "'rbxasset://studio_svg_textures/Shared/DraggerTools/![$Theme]/Standard/Scale@2x.png'",
					
					rule("AspectRatioConstraint", "::UIAspectRatioConstraint", 0, {
						AspectRatio = "$Icon16x16AspectRatio"
					})
				})
			})
		}),
		rule("SelectedExplorerFrameStyle", ".JEXP_Selected Frame", 11, {
			rule("InstanceNameStyle", "> #Main > #InstanceName", 1, {
				TextColor3 = Color3.fromRGB(255, 255, 255)
			}),
			rule("IconStyle", "> #Main > #ClassIcon", 1, {
				ImageTransparency = 0
			}),
			rule("OverlayStyle", "> #Main > #Overlay", 1, {
				BackgroundTransparency = 0.2,
				BackgroundColor3 = "$SelectedColor",
			}),
			rule("ArrowStyle", "> #Main > #Arrow", 1, {
				ImageColor3 = "$SelectedMonochromeColor",
				Image = "$InvertedArrowImage"
			}),
			rule("InsertButtonStyle", "> #Main > #Insert ImageButton", 10, {
				ImageColor3 = "$SelectedMonochromeColor"
			}),
			rule("ReclassButtonStyle", "> #Main > #Reclass ImageButton", 10, {
				Image = var "'rbxasset://studio_svg_textures/Shared/DraggerTools/![$SelectedTheme]/Standard/Scale@2x.png'",
				ImageColor3 = "$SelectedMonochromeColor"
			})
		}),
		rule("ExplorerFrameStyleDisabled",
			Selector.getTaggedPropertySelector("Enabled", "false"), 10, {
				rule("InstanceNameStyle", "> #Main > #InstanceName", 1, {
					TextSize = "$InstanceFrameTextSize",
					TextColor3 = "$FadedColor"
				}),
				rule("IconStyle", "> #Main > #ClassIcon", 1, {
					ImageTransparency = 0.5
				}),
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
		
		rule("LocalScriptIcon", Selector.getIconSelector(nil, "LocalScript"), 1, {
			Image = var "'rbxasset://studio_svg_textures/Shared/Scripting/![$Theme]/Standard/LegacyClientRunContext.png'",
			ImageRectOffset = Vector2.zero,
			ImageRectSize = Vector2.zero
		}),
		rule("LegacyRunContextIcon", `#{Constants.ExplorerFrameScriptClassNameFormat:format("Legacy")} > #Main > #ClassIcon`, 1, {
			Image = var "'rbxasset://studio_svg_textures/Shared/Scripting/![$Theme]/Standard/LegacyServerRunContext.png'",
			ImageRectOffset = Vector2.zero,
			ImageRectSize = Vector2.zero
		}),
		rule("ServerRunContextIcon", `#{Constants.ExplorerFrameScriptClassNameFormat:format("Server")} > #Main > #ClassIcon`, 1, {
			Image = var "'rbxasset://studio_svg_textures/Shared/Scripting/![$Theme]/Standard/ServerRunContext.png'",
			ImageRectOffset = Vector2.zero,
			ImageRectSize = Vector2.zero
		}),
		rule("ClientRunContextIcon", `#{Constants.ExplorerFrameScriptClassNameFormat:format("Client")} > #Main > #ClassIcon`, 1, {
			Image = var "'rbxasset://studio_svg_textures/Shared/Scripting/![$Theme]/Standard/ClientRunContext.png'",
			ImageRectOffset = Vector2.zero,
			ImageRectSize = Vector2.zero
		}),
		rule("PluginRunContextIcon", `#{Constants.ExplorerFrameScriptClassNameFormat:format("Plugin")} > #Main > #ClassIcon`, 1, {
			Image = var "'rbxasset://studio_svg_textures/Shared/Scripting/![$Theme]/Standard/PluginRunContext.png'",
			ImageRectOffset = Vector2.zero,
			ImageRectSize = Vector2.zero
		}),
		
		rule("LocalScriptIcon_Selected", `.JEXP_Selected {Selector.getIconSelector(nil, "LocalScript")}`, 100, {
			Image = var "'rbxasset://studio_svg_textures/Shared/Scripting/Dark/Standard/LegacyClientRunContext.png'",
			ImageRectOffset = Vector2.zero,
			ImageRectSize = Vector2.zero
		}),
		rule("LegacyRunContextIcon_Selected", `.JEXP_Selected #{Constants.ExplorerFrameScriptClassNameFormat:format("Legacy")} > #Main > #ClassIcon`, 100, {
			Image = var "'rbxasset://studio_svg_textures/Shared/Scripting/Dark/Standard/LegacyServerRunContext.png'",
			ImageRectOffset = Vector2.zero,
			ImageRectSize = Vector2.zero
		}),
		rule("ServerRunContextIcon_Selected", `.JEXP_Selected #{Constants.ExplorerFrameScriptClassNameFormat:format("Server")} > #Main > #ClassIcon`, 100, {
			Image = var "'rbxasset://studio_svg_textures/Shared/Scripting/Dark/Standard/ServerRunContext.png'",
			ImageRectOffset = Vector2.zero,
			ImageRectSize = Vector2.zero
		}),
		rule("ClientRunContextIcon_Selected", `.JEXP_Selected #{Constants.ExplorerFrameScriptClassNameFormat:format("Client")} > #Main > #ClassIcon`, 100, {
			Image = var "'rbxasset://studio_svg_textures/Shared/Scripting/Dark/Standard/ClientRunContext.png'",
			ImageRectOffset = Vector2.zero,
			ImageRectSize = Vector2.zero
		}),
		rule("PluginRunContextIcon_Selected", `.JEXP_Selected #{Constants.ExplorerFrameScriptClassNameFormat:format("Plugin")} > #Main > #ClassIcon`, 100, {
			Image = var "'rbxasset://studio_svg_textures/Shared/Scripting/Dark/Standard/PluginRunContext.png'",
			ImageRectOffset = Vector2.zero,
			ImageRectSize = Vector2.zero
		}),
	}
	for _, v: Style.Rule in defaultRules do
		v:AddTag("Default")
		v:AddTag("DontSaveRule")
	end
	
	return defaultTokens, defaultRules
end