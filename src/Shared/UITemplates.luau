local create = require("./create")

return {
	JexplorerUi = function()
		return create "Frame" {
			Name = "JexplorerUi",
			"JEXP_Background",

			create "Frame" {
				Name = "InstanceTree",
				"JEXP_DarkBackground",

				create "ScrollingFrame" {
					Name = "TreeScroller",
					"JEXP_ScrollingFrame",
				},
				create "Frame" {
					Name = "ScrollContainer"
				},
				create "Frame" {
					Name = "ScrollBackgroundHorizontal",
					ZIndex = 4,

					"JEXP_DarkBackground",
					"JEXP_GrayBorder",
					"JEXP_ScrollBackgroundHorizontal"
				},
				create "Frame" {
					Name = "ScrollBackgroundVertical",
					ZIndex = 4,

					"JEXP_DarkBackground",
					"JEXP_GrayBorder",
					"JEXP_ScrollBackgroundVertical"
				},
			},
			create "Frame" {
				Name = "Topbar",

				"JEXP_Background",
				"JEXP_Border",
				create "Frame" {
					Name = "PathBar",
					"JEXP_Background",
					"JEXP_Border",
					create "ScrollingFrame" {
						Name = "Segments",

						create "TextButton" {
							Name = "PathSegment",
							"JEXP_Text"
						}
					}
				},
				create "Frame" {
					Name = "TabBar",
					"JEXP_Background",

					create "ScrollingFrame" {
						Name = "Tabs",
					}
				},
				create "ImageButton" {
					Name = "Options",
					"JEXP_MonochromeImage"
				},
				create "Frame" {
					Name = "QueryInputFrame",
					"JEXP_Border",
					"JEXP_DarkBackground",

					create "ScrollingFrame" {
						Name = "Scroll",
						CanvasSize = UDim2.fromScale(0, 0),

						create "TextBox" {
							Name = "QueryInput",
							Text = "",

							"JEXP_Text",
							"JEXP_DefaultText",
						},
					},
					create "ImageButton" {
						Name = "SelectQueried",

						"JEXP_Hover",
						"JEXP_MonochromeImage"
					},
					create "TextLabel" {
						Name = "QueryCount",

						"JEXP_Text"
					}
				}
			}
		}
	end,
	InstanceFrame = function()
		return create "Frame" {
			Name = "InstanceFrame",
			"JEXP_Background",
			"JEXP_ExplorerFrame",

			create "Frame" {
				Name = "Buffer",
			},
			--create "Frame" {
			--	Name = "Ruler"
			--},
			create "Frame" {
				Name = "Main",

				create "Frame" {
					Name = "Overlay",

					create "ImageButton" {
						Name = "Select",
					}
				},
				create "ImageLabel" {
					Name = "ClassIcon",
				},
				create "ImageLabel" {
					Name = "PackageLinkIcon",
					Visible = false
				},
				create "ImageLabel" {
					Name = "PendingChanges",
					Visible = false
				},
				create "TextBox" {
					Name = "InstanceName",

					Interactable = false,
					TextEditable = false,
				},
				create "ImageButton" {
					Name = "Arrow",
					"JEXP_Arrow"
				},
				create "ImageButton" {
					Name = "Insert",
					Visible = false,

					"JEXP_MonochromeImage"
				},
				create "ImageButton" {
					Name = "Reclass",
					Visible = false,

					"JEXP_MonochromeImage"
				}
			}
		}
	end,
	EditorFrame = function()
		return create "Frame" {
			Size = UDim2.new(1, 0, 1, 0),

			"JEXP_Background",

			create "ScrollingFrame" {
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

				create "Frame" {
					Name = "Content",
					Size = UDim2.fromScale(0, 0),
					AutomaticSize = Enum.AutomaticSize.XY,
					BackgroundTransparency = 1,

					create "UIListLayout" {
						ItemLineAlignment = Enum.ItemLineAlignment.Start,
						SortOrder = Enum.SortOrder.LayoutOrder,
					}
				},
				create "Frame" {
					Name = "Overlay",
					Size = UDim2.fromScale(1, 1),
					ZIndex = 100,
					BackgroundTransparency = 1
				}
			},
			create "Frame" {
				Name = "ScrollBackgroundHorizontal",
				ZIndex = 4,

				"JEXP_DarkBackground",
				"JEXP_Border",
				"JEXP_ScrollBackgroundHorizontal",
			},
			create "Frame" {
				Name = "ScrollBackgroundVertical",
				ZIndex = 4,

				"JEXP_DarkBackground",
				"JEXP_Border",
				"JEXP_ScrollBackgroundVertical"
			},
		}
	end,
	TabFrame = function()
		return create "Frame" {
			Name = "InstanceTab",
			Size = UDim2.new(0, 70, 1, 0),

			"JEXP_TabFrame",

			create "TextBox" {
				Name = "NameBox",
				Size = UDim2.new(0, 0, 1, 0),
				"JEXP_Text"
			},
			create "TextButton" {
				Name = "Button",
			},
			create "ImageLabel" {
				Name = "Icon"
			}
		}
	end,
}