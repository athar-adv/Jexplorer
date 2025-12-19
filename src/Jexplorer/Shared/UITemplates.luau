--!strict

local Create = require("./Create")
local template = Create.template

return {
	JexplorerUi = template "Frame" {
		Name = "JexplorerUi",
		"JEXP_Background",
		
		template "ScrollingFrame" {
			Name = "InstanceTree",
			
			"JEXP_DarkBackground",
			"JEXP_ScrollingFrame"
		},
		template "Frame" {
			Name = "ScrollBackgroundHorizontal",
			ZIndex = 4,
			
			"JEXP_DarkBackground",
			"JEXP_GrayBorder",
			"JEXP_ScrollBackgroundHorizontal"
		},
		template "Frame" {
			Name = "ScrollBackgroundVertical",
			ZIndex = 4,

			"JEXP_DarkBackground",
			"JEXP_GrayBorder",
			"JEXP_ScrollBackgroundVertical"
		},
		template "Frame" {
			Name = "Topbar",
			
			"JEXP_Background",
			"JEXP_Border",
			template "Frame" {
				Name = "PathBar",
				"JEXP_Background",
				"JEXP_Border",
				template "ScrollingFrame" {
					Name = "Segments",

					template "TextButton" {
						Name = "PathSegment",
						"JEXP_Text"
					}
				}
			},
			template "Frame" {
				Name = "TabBar",
				"JEXP_Background",

				template "ScrollingFrame" {
					Name = "Tabs",
				}
			},
			template "ImageButton" {
				Name = "Options",
				"JEXP_MonochromeImage"
			},
			template "TextBox" {
				Name = "QueryInput",
				Text = "",
				
				"JEXP_Border",
				"JEXP_DarkBackground",
				"JEXP_Text",
				"JEXP_DefaultText",
				
				template "ImageButton" {
					Name = "SelectQueried",
					
					"JEXP_Hover",
					"JEXP_MonochromeImage"
				},
				template "TextLabel" {
					Name = "QueryCount",
					
					"JEXP_Text"
				}
			}
		}
	},
	InstanceFrame = template "Frame" {
		Name = "InstanceFrame",
		"JEXP_Background",
		
		template "Frame" {
			Name = "Buffer",
		},
		template "Frame" {
			Name = "Children",
			"JEXP_ChildrenContainer",
			
			template "Frame" {
				Name = "List",
			},
			template "Frame" {
				Name = "Ruler"
			}
		},
		template "Frame" {
			Name = "Main",
			
			template "Frame" {
				Name = "Overlay",
				
				template "ImageButton" {
					Name = "Select",
				}
			},
			template "ImageLabel" {
				Name = "ClassIcon",
			},
			template "ImageLabel" {
				Name = "PackageLinkIcon",
				Visible = false
			},
			template "ImageLabel" {
				Name = "PendingChanges",
				Visible = false
			},
			template "TextBox" {
				Name = "InstanceName",
				
				Interactable = false,
				TextEditable = false,
			},
			template "ImageButton" {
				Name = "Arrow",
				"JEXP_Arrow"
			},
			template "ImageButton" {
				Name = "Insert",
				Visible = false,
				
				"JEXP_MonochromeImage"
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
			ZIndex = 4,
			
			"JEXP_DarkBackground",
			"JEXP_Border",
			"JEXP_ScrollBackgroundHorizontal",
		},
		template "Frame" {
			Name = "ScrollBackgroundVertical",
			ZIndex = 4,
			
			"JEXP_DarkBackground",
			"JEXP_Border",
			"JEXP_ScrollBackgroundVertical"
		},
	},
	TabFrame = template "Frame" {
		Name = "InstanceTab",
		Size = UDim2.new(0, 70, 1, 0),
		
		"JEXP_LightBackground",
		"JEXP_Border",
		"JEXP_TabFrame",
		
		template "TextBox" {
			Name = "NameBox",
			Size = UDim2.new(0, 0, 1, 0),
			"JEXP_Text"
		},
		template "TextButton" {
			Name = "Button",
		}
	}
}