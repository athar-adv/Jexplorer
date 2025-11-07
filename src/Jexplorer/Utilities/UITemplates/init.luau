--!strict

local Create = require("./Create")
local template = Create.template

return {
	JexplorerUi = template "Frame" {
		Name = "JexplorerUi",
		Size = UDim2.new(1, 0, 1, 0),
		
		"JEXP_Background",
		template "ScrollingFrame" {
			Name = "InstanceTree",
			AnchorPoint = Vector2.new(0.5, 1),
			BackgroundTransparency = 1,
			Position = UDim2.new(0.5, 0, 1, 0),
			ZIndex = 5,
			AutomaticCanvasSize = Enum.AutomaticSize.XY,
			BottomImage = "rbxasset://textures/ui/Scroll/scroll-middle.png",
			TopImage = "rbxasset://textures/ui/Scroll/scroll-middle.png",
			HorizontalScrollBarInset = Enum.ScrollBarInset.Always,
			VerticalScrollBarInset = Enum.ScrollBarInset.Always,
			ScrollingEnabled = false,
			
			"JEXP_DarkBackground",
			"JEXP_ScrollingFrame"
		},
		template "Frame" {
			Name = "ScrollBackgroundHorizontal",
			AnchorPoint = Vector2.new(0, 1),
			BackgroundTransparency = 0.75,
			Position = UDim2.new(0, 0, 1, 0),
			ZIndex = 0,
			
			"JEXP_DarkBackground",
			"JEXP_Border"
		},
		template "Frame" {
			Name = "ScrollBackgroundVertical",
			AnchorPoint = Vector2.new(1, 0),
			BackgroundTransparency = 0.75,
			Position = UDim2.new(1, 0, 0, 0),
			ZIndex = 0,

			"JEXP_DarkBackground",
			"JEXP_Border"
		},
		template "Frame" {
			Name = "Topbar",
			ZIndex = 10,
			
			"JEXP_Background",
			"JEXP_Topbar",
			"JEXP_Border",
			
			template "Frame" {
				Name = "PathBar",
				"JEXP_Background",
				"JEXP_Border",
				"JEXP_PathBar",
				
				template "ScrollingFrame" {
					Name = "Segments",
					BackgroundTransparency = 1,
					Size = UDim2.new(1, 0, 1, 0),
					AutomaticCanvasSize = Enum.AutomaticSize.X,
					BottomImage = "rbxasset://textures/ui/Scroll/scroll-middle.png",
					CanvasSize = UDim2.new(0, 0, 0, 0),
					ElasticBehavior = Enum.ElasticBehavior.Never,
					ScrollBarThickness = 2,
					TopImage = "rbxasset://textures/ui/Scroll/scroll-middle.png",
					MidImage = "rbxasset://textures/ui/Scroll/scroll-middle.png",
					
					template "UIListLayout" {
						FillDirection = Enum.FillDirection.Horizontal,
						SortOrder = Enum.SortOrder.LayoutOrder,
						VerticalAlignment = Enum.VerticalAlignment.Center,
						Padding = UDim.new(0, 4)
					},
					template "TextButton" {
						Name = "PathSegment",
						AutomaticSize = Enum.AutomaticSize.X,
						BackgroundTransparency = 1,
						Size = UDim2.new(0, 0, 1, 0),
						TextSize = 11,
						Text = "",
						FontFace = Font.fromEnum(Enum.Font.SourceSans),
						TextXAlignment = Enum.TextXAlignment.Left,
						
						"JEXP_Text"
					}
				}
			},
			template "Frame" {
				Name = "TabBar",
				"JEXP_Background",
				"JEXP_TabBar",

				template "ScrollingFrame" {
					Name = "Tabs",
					BackgroundTransparency = 1,
					Size = UDim2.new(1, 0, 1, 0),
					AutomaticCanvasSize = Enum.AutomaticSize.X,
					BottomImage = "rbxasset://textures/ui/Scroll/scroll-middle.png",
					CanvasSize = UDim2.new(0, 0, 0, 0),
					ElasticBehavior = Enum.ElasticBehavior.Never,
					ScrollBarThickness = 2,
					TopImage = "rbxasset://textures/ui/Scroll/scroll-middle.png",
					MidImage = "rbxasset://textures/ui/Scroll/scroll-middle.png",

					template "UIListLayout" {
						FillDirection = Enum.FillDirection.Horizontal,
						SortOrder = Enum.SortOrder.LayoutOrder,
						VerticalAlignment = Enum.VerticalAlignment.Center,
						Padding = UDim.new(0, 1)
					},
				}
			},
			template "ImageButton" {
				Name = "Options",
				AnchorPoint = Vector2.new(0, 0.5),
				BackgroundTransparency = 1,
				Position = UDim2.new(0, 2, 0.5, 0),
				"JEXP_Arrow",
				
				template "UIAspectRatioConstraint" {
					AspectRatio = 1
				}
			},
			template "TextBox" {
				Name = "QueryInput",
				AnchorPoint = Vector2.new(0, 0.5),
				ClearTextOnFocus = false,
				Text = "",
				PlaceholderColor3 = Color3.fromRGB(197, 197, 197),
				PlaceholderText = "Query Components...",
				FontFace = Font.fromEnum(Enum.Font.SourceSans),
				TextWrapped = true,
				TextXAlignment = Enum.TextXAlignment.Left,
				
				"JEXP_Border",
				"JEXP_DarkBackground",
				"JEXP_Text",
				
				template "ImageButton" {
					Name = "SelectQueried",
					AnchorPoint = Vector2.new(1, 0.5),
					AutoButtonColor = false,
					BackgroundTransparency = 1,
					Position = UDim2.new(1, -10, 0.5, 0),
					Size = UDim2.new(0, 15, 0, 15),
					Image = "rbxassetid://112780490255100",
					
					"JEXP_Hover",
					"JEXP_MonochromeImage"
				},
				template "TextLabel" {
					Name = "QueryCount",
					Text = "0",
					AnchorPoint = Vector2.new(1, 0.5),
					BackgroundTransparency = 1,
					Position = UDim2.new(1, -29, 0.5, 0),
					Size = UDim2.new(0, 15, 0, 15),
					TextWrapped = true,
					TextXAlignment = Enum.TextXAlignment.Right,
					AutomaticSize = Enum.AutomaticSize.X,
					TextSize = 8,
					
					"JEXP_Text"
				}
			}
		}
	},
	InstanceFrame = template "Frame" {
		Name = "InstanceFrame",
		AutomaticSize = Enum.AutomaticSize.XY,
		SizeConstraint = Enum.SizeConstraint.RelativeXX,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ZIndex = 100,

		"JEXP_Background",
		
		template "Frame" {
			Name = "Buffer",
			AnchorPoint = Vector2.new(1, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			BackgroundTransparency = 1,
			BackgroundColor3 = Color3.fromRGB(255, 255, 255),
			Size = UDim2.new(0.94, 0, 0, 0)
		},
		template "Frame" {
			Name = "Children",
			AutomaticSize = Enum.AutomaticSize.Y,
			BackgroundTransparency = 1,
			Size = UDim2.new(1, 0, 0, 0),
			
			"JEXP_ChildrenContainer",
			
			template "Frame" {
				Name = "List",
				AutomaticSize = Enum.AutomaticSize.Y,
				BackgroundTransparency = 1,
				Size = UDim2.new(1, 0, 1, 0),
			},
			template "Frame" {
				Name = "Ruler"
			}
		},
		template "Frame" {
			Name = "Main",
			
			template "Frame" {
				Name = "Overlay",
				AnchorPoint = Vector2.new(0.5, 0),
				AutomaticSize = Enum.AutomaticSize.Y,
				Size = UDim2.new(20, 0, 1, 0), -- Make it extremely long to reach all the edges
				ZIndex = 2,
				
				template "ImageButton" {
					Name = "Select",
					BackgroundTransparency = 1,
					Size = UDim2.new(1, 0, 1, 0),
					ZIndex = 2,
				}
			},
			template "ImageLabel" {
				Name = "ClassIcon",
				AnchorPoint = Vector2.new(0.5, 0.5),
				BackgroundTransparency = 1,
				Position = UDim2.new(0, 30, 0.5, 0),
				Size = UDim2.new(0, 15, 0, 15),
				ZIndex = 2,

				template "UIAspectRatioConstraint" {
					AspectRatio = 1
				}
			},
			template "ImageLabel" {
				Name = "PackageLinkIcon",
				AnchorPoint = Vector2.new(0, 0.5),
				BackgroundTransparency = 1,
				Position = UDim2.new(0, -6, 0.5, 0),
				Size = UDim2.new(0, 12, 0, 12),
				ZIndex = 3,
				Visible = false,

				template "UIAspectRatioConstraint" {
					AspectRatio = 0.92
				}
			},
			template "ImageLabel" {
				Name = "PendingChanges",
				AnchorPoint = Vector2.new(0, 0.5),
				BackgroundTransparency = 1,
				Position = UDim2.new(0, -4, 0.5, 0),
				Size = UDim2.new(0, 12, 0, 12),
				Image = "rbxassetid://108225148244406",
				ZIndex = 3,
				Visible = false,

				template "UIAspectRatioConstraint" {
					AspectRatio = 0.92
				}
			},
			template "TextBox" {
				Name = "InstanceName",
				Interactable = false,
				TextEditable = false
			},
			template "ImageButton" {
				Name = "Arrow",
				"JEXP_Arrow"
			},
			template "ImageButton" {
				Name = "Insert",
				BackgroundTransparency = 1,
				AnchorPoint = Vector2.new(0, 0.5),
				Size = UDim2.new(0, 16, 0, 16),
				Visible = false,
				ZIndex = 3,
				Image = "rbxassetid://137932446085794",
				
				template "UIAspectRatioConstraint" {
					AspectRatio = 0.92
				}
			}
		}
	},
	DragFrame = template "Frame" {
		Name = "DragFrame",
		AutomaticSize = Enum.AutomaticSize.XY,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ZIndex = 100,
		
		"JEXP_Background",
		
		template "Frame" {
			Name = "Main",
			AutomaticSize = Enum.AutomaticSize.XY,
			Size = UDim2.new(1, 0, 0, 20),
			ZIndex = 2,
			
			"JEXP_SelectedColor",
			
			template "Frame" {
				Name = "Overlay",
				AutomaticSize = Enum.AutomaticSize.XY,
				Size = UDim2.new(1, 0, 0, 20),
				ZIndex = 2,
				
				"JEXP_Selected"
			},
			template "ImageLabel" {
				Name = "ClassIcon",
				AnchorPoint = Vector2.new(0.5, 0.5),
				BackgroundTransparency = 1,
				Position = UDim2.new(0, 30, 0.5, 0),
				Size = UDim2.new(0, 15, 0, 15),
				ZIndex = 2,
				
				template "UIAspectRatioConstraint" {
					AspectRatio = 1
				}
			},
			template "TextLabel" {
				Name = "InstanceName",
				AutomaticSize = Enum.AutomaticSize.XY,
				BackgroundTransparency = 1,
				Position = UDim2.new(0, 40, 0.5, 0),
				FontFace = Font.fromEnum(Enum.Font.SourceSans),
				Size = UDim2.new(1, 0, 0, 15),
				ZIndex = 2,
				Text = "Instance",
				TextSize = 14,
				TextXAlignment = Enum.TextXAlignment.Left,
				
				"JEXP_InstanceName"
			}
		}
	},
	EditorFrame = template "Frame" {
		Size = UDim2.new(1, 0, 1, 0),
		
		"JEXP_Background",
		
		template "ScrollingFrame" {
			Name = "Items",
			AnchorPoint = Vector2.new(0.5, 1),
			BackgroundTransparency = 1,
			Position = UDim2.new(0.5, 0, 1, 0),
			Size = UDim2.new(1, 0, 1, 0),
			ZIndex = 5,
			AutomaticCanvasSize = Enum.AutomaticSize.XY,
			BottomImage = "rbxasset://textures/ui/Scroll/scroll-middle.png",
			TopImage = "rbxasset://textures/ui/Scroll/scroll-middle.png",
			MidImage = "rbxasset://textures/ui/Scroll/scroll-middle.png",
			ElasticBehavior = Enum.ElasticBehavior.Never,
			HorizontalScrollBarInset = Enum.ScrollBarInset.Always,
			VerticalScrollBarInset = Enum.ScrollBarInset.Always,
			
			"JEXP_DarkBackground",
			"JEXP_ScrollingFrame",
			
			template "UIListLayout" {
				ItemLineAlignment = Enum.ItemLineAlignment.Start
			}
		},
		template "Frame" {
			Name = "ScrollBackgroundHorizontal",
			AnchorPoint = Vector2.new(0, 1),
			BackgroundTransparency = 0.75,
			Position = UDim2.new(0, 0, 1, 0),
			ZIndex = 0,

			"JEXP_DarkBackground",
			"JEXP_Border"
		},
		template "Frame" {
			Name = "ScrollBackgroundVertical",
			AnchorPoint = Vector2.new(1, 0),
			BackgroundTransparency = 0.75,
			Position = UDim2.new(1, 0, 0, 0),
			ZIndex = 0,

			"JEXP_DarkBackground",
			"JEXP_Border"
		},
	}
}