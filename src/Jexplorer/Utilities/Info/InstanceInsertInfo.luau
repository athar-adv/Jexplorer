local INSTANCE_INSERT_INFO: {
	[string]: {
		SideEffect: ((inst: Instance) -> ())?,
		Props: {[string]: any}
	}
} = {
	["_"] = {
		SideEffect = function()
		end,
		Props = {
		}
	},

	-- BasePart and descendants
	["BasePart"] = {
		SideEffect = function(part: BasePart)
			local camera = workspace.CurrentCamera
			local cameraPosition = camera.CFrame.Position
			local cameraDirection = camera.CFrame.LookVector

			local raycastResult = workspace:Raycast(cameraPosition, cameraDirection * 100)
			if raycastResult then
				part.Position = raycastResult.Position
			else
				part.Position = cameraPosition + (cameraDirection * 10)
			end
		end,
		Props = {
			TopSurface = Enum.SurfaceType.Smooth,
			BottomSurface = Enum.SurfaceType.Smooth,
			LeftSurface = Enum.SurfaceType.Smooth,
			RightSurface = Enum.SurfaceType.Smooth,
			FrontSurface = Enum.SurfaceType.Smooth,
			BackSurface = Enum.SurfaceType.Smooth,
		}
	},

	["Part"] = {
		Props = {
			Size = Vector3.new(4, 1, 2),
			Color = Color3.fromRGB(163, 162, 165),
		}
	},

	["WedgePart"] = {
		Props = {
			Size = Vector3.new(4, 1, 2),
			Color = Color3.fromRGB(163, 162, 165),
		}
	},

	["CornerWedgePart"] = {
		Props = {
			Size = Vector3.new(4, 1, 2),
			Color = Color3.fromRGB(163, 162, 165),
		}
	},

	["TrussPart"] = {
		Props = {
			Size = Vector3.new(2, 2, 2),
		}
	},

	["SpawnLocation"] = {
		Props = {
			Size = Vector3.new(6, 1, 6),
			Color = Color3.fromRGB(13, 105, 172),
			TopSurface = Enum.SurfaceType.Smooth,
			BottomSurface = Enum.SurfaceType.Smooth,
			Transparency = 0.4,
			CanCollide = false,
		}
	},

	["Seat"] = {
		Props = {
			Size = Vector3.new(4, 1, 2),
			Color = Color3.fromRGB(163, 162, 165),
		}
	},

	["VehicleSeat"] = {
		Props = {
			Size = Vector3.new(4, 1, 2),
			Color = Color3.fromRGB(163, 162, 165),
		}
	},

	["MeshPart"] = {
		Props = {
			Size = Vector3.new(4, 1, 2),
			Color = Color3.fromRGB(163, 162, 165),
		}
	},

	-- UI Elements
	["GuiObject"] = {
		Props = {
			BorderSizePixel = 0
		}
	},
	
	["Frame"] = {
		Props = {
			Size = UDim2.new(0, 100, 0, 100),
			BackgroundColor3 = Color3.fromRGB(255, 255, 255),
		}
	},

	["TextLabel"] = {
		Props = {
			Size = UDim2.new(0, 200, 0, 50),
			BackgroundColor3 = Color3.fromRGB(255, 255, 255),
			Text = "Label",
			TextColor3 = Color3.fromRGB(0, 0, 0),
			Font = Enum.Font.Legacy,
			TextSize = 8,
		}
	},

	["TextButton"] = {
		Props = {
			Size = UDim2.new(0, 200, 0, 50),
			BackgroundColor3 = Color3.fromRGB(255, 255, 255),
			Text = "TextButton",
			TextColor3 = Color3.fromRGB(0, 0, 0),
			Font = Enum.Font.Legacy,
			TextSize = 8,
			AutoButtonColor = true,
		}
	},

	["TextBox"] = {
		Props = {
			Size = UDim2.new(0, 200, 0, 50),
			BackgroundColor3 = Color3.fromRGB(255, 255, 255),
			Text = "TextBox",
			TextColor3 = Color3.fromRGB(0, 0, 0),
			Font = Enum.Font.Legacy,
			TextSize = 8,
			ClearTextOnFocus = true,
		}
	},

	["ImageLabel"] = {
		Props = {
			Size = UDim2.new(0, 100, 0, 100),
			BackgroundColor3 = Color3.fromRGB(255, 255, 255),
			Image = "",
		}
	},

	["ImageButton"] = {
		Props = {
			Size = UDim2.new(0, 100, 0, 100),
			BackgroundColor3 = Color3.fromRGB(255, 255, 255),
			Image = "",
			AutoButtonColor = true,
		}
	},

	["ViewportFrame"] = {
		Props = {
			Size = UDim2.new(0, 200, 0, 200),
			BackgroundColor3 = Color3.fromRGB(255, 255, 255),
		}
	},

	["ScrollingFrame"] = {
		Props = {
			Size = UDim2.new(0, 100, 0, 100),
			BackgroundColor3 = Color3.fromRGB(255, 255, 255),
			CanvasSize = UDim2.new(0, 0, 2, 0),
			ScrollBarThickness = 12,
		}
	},

	["VideoFrame"] = {
		Props = {
			Size = UDim2.new(0, 100, 0, 100),
			BackgroundColor3 = Color3.fromRGB(255, 255, 255),
		}
	},

	["CanvasGroup"] = {
		Props = {
			Size = UDim2.new(0, 100, 0, 100),
			BackgroundColor3 = Color3.fromRGB(255, 255, 255),
		}
	},

	-- Screen GUIs
	["ScreenGui"] = {
		Props = {
			ResetOnSpawn = true,
			ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		}
	},

	["BillboardGui"] = {
		Props = {
			Size = UDim2.new(0, 200, 0, 50),
			AlwaysOnTop = false,
		}
	},

	["SurfaceGui"] = {
		Props = {
			CanvasSize = Vector2.new(800, 600),
			AlwaysOnTop = false,
		}
	},

	-- Layout objects
	["UIListLayout"] = {
		Props = {
			Padding = UDim.new(0, 0),
			FillDirection = Enum.FillDirection.Vertical,
			HorizontalAlignment = Enum.HorizontalAlignment.Center,
			VerticalAlignment = Enum.VerticalAlignment.Top,
			SortOrder = Enum.SortOrder.Name,
		}
	},

	["UIGridLayout"] = {
		Props = {
			CellPadding = UDim2.new(0, 5, 0, 5),
			CellSize = UDim2.new(0, 100, 0, 100),
			FillDirection = Enum.FillDirection.Vertical,
			HorizontalAlignment = Enum.HorizontalAlignment.Left,
			VerticalAlignment = Enum.VerticalAlignment.Top,
			SortOrder = Enum.SortOrder.Name,
		}
	},

	["UITableLayout"] = {
		Props = {
			Padding = UDim2.new(0, 0, 0, 0),
			FillDirection = Enum.FillDirection.Vertical,
			HorizontalAlignment = Enum.HorizontalAlignment.Left,
			VerticalAlignment = Enum.VerticalAlignment.Top,
		}
	},

	["UIPageLayout"] = {
		Props = {
			Padding = UDim.new(0, 0),
			FillDirection = Enum.FillDirection.Vertical,
			HorizontalAlignment = Enum.HorizontalAlignment.Center,
			VerticalAlignment = Enum.VerticalAlignment.Center,
			SortOrder = Enum.SortOrder.Name,
			Animated = true,
			Circular = false,
			GamepadInputEnabled = true,
			ScrollWheelInputEnabled = true,
			TouchInputEnabled = true,
		}
	},

	-- Constraints
	["UIPadding"] = {
		Props = {
			PaddingLeft = UDim.new(0, 0),
			PaddingRight = UDim.new(0, 0),
			PaddingTop = UDim.new(0, 0),
			PaddingBottom = UDim.new(0, 0),
		}
	},

	["UICorner"] = {
		Props = {
			CornerRadius = UDim.new(0, 8),
		}
	},

	["UIStroke"] = {
		Props = {
			Color = Color3.fromRGB(0, 0, 0),
			Thickness = 1,
			Transparency = 0,
			ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual,
		}
	},

	["UIGradient"] = {
		Props = {
			Color = ColorSequence.new(Color3.fromRGB(255, 255, 255), Color3.fromRGB(255, 255, 255)),
			Transparency = NumberSequence.new(0),
			Rotation = 0,
		}
	},

	["UIAspectRatioConstraint"] = {
		Props = {
			AspectRatio = 1,
			AspectType = Enum.AspectType.FitWithinMaxSize,
			DominantAxis = Enum.DominantAxis.Width,
		}
	},

	["UISizeConstraint"] = {
		Props = {
			MaxSize = Vector2.new(math.huge, math.huge),
			MinSize = Vector2.new(0, 0),
		}
	},

	["UITextSizeConstraint"] = {
		Props = {
			MaxTextSize = 100,
			MinTextSize = 1,
		}
	},

	["UIScale"] = {
		Props = {
			Scale = 1,
		}
	},

	-- Lights
	["PointLight"] = {
		Props = {
			Brightness = 1,
			Color = Color3.fromRGB(255, 255, 255),
			Range = 60,
			Shadows = false,
		}
	},

	["SpotLight"] = {
		Props = {
			Brightness = 1,
			Color = Color3.fromRGB(255, 255, 255),
			Range = 60,
			Angle = 90,
			Face = Enum.NormalId.Front,
			Shadows = false,
		}
	},

	["SurfaceLight"] = {
		Props = {
			Brightness = 1,
			Color = Color3.fromRGB(255, 255, 255),
			Range = 60,
			Angle = 90,
			Face = Enum.NormalId.Front,
			Shadows = false,
		}
	},

	-- Attachments and Effects
	["Attachment"] = {
		Props = {
			Visible = false,
		}
	},

	["Beam"] = {
		Props = {
			Color = ColorSequence.new(Color3.fromRGB(255, 255, 255)),
			Transparency = NumberSequence.new(0.5),
			Width0 = 1,
			Width1 = 1,
		}
	},

	["Trail"] = {
		Props = {
			Color = ColorSequence.new(Color3.fromRGB(255, 255, 255)),
			Transparency = NumberSequence.new(0.5),
			Lifetime = 2,
			MinLength = 0.1,
			WidthScale = NumberSequence.new(1),
		}
	},

	["ParticleEmitter"] = {
		Props = {
			Color = ColorSequence.new(Color3.fromRGB(255, 255, 255)),
			Transparency = NumberSequence.new(0),
			LightEmission = 0,
			LightInfluence = 0,
			Size = NumberSequence.new(1),
			Texture = "",
			Rate = 5,
			Lifetime = NumberRange.new(1),
			Speed = NumberRange.new(5),
			Rotation = NumberRange.new(0),
			RotSpeed = NumberRange.new(0),
			SpreadAngle = Vector2.new(0, 0),
			Shape = Enum.ParticleEmitterShape.Box,
			ShapeInOut = Enum.ParticleEmitterShapeInOut.Outward,
			ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume,
		}
	},

	["Smoke"] = {
		Props = {
			Color = Color3.fromRGB(255, 255, 255),
			Opacity = 0.5,
			RiseVelocity = 1,
			Size = 1,
			TimeScale = 1,
		}
	},

	["Fire"] = {
		Props = {
			Size = 5,
			Heat = 10,
			SecondaryColor = Color3.fromRGB(255, 128, 0),
			Color = Color3.fromRGB(255, 0, 0),
		}
	},

	["Sparkles"] = {
		Props = {
			SparkleColor = Color3.fromRGB(255, 255, 255),
		}
	},

	-- Decals & Textures
	["Decal"] = {
		Props = {
			Texture = "",
			Transparency = 0,
			Face = Enum.NormalId.Front,
			Color3 = Color3.fromRGB(255, 255, 255),
		}
	},

	["Texture"] = {
		Props = {
			Texture = "",
			StudsPerTileU = 1,
			StudsPerTileV = 1,
			Face = Enum.NormalId.Front,
			Color3 = Color3.fromRGB(255, 255, 255),
			Transparency = 0,
		}
	},

	-- Sounds
	["Sound"] = {
		Props = {
			SoundId = "",
			Volume = 0.5,
			PlaybackSpeed = 1,
			Looped = false,
			Playing = false,
		}
	},

	-- Scripts
	["Script"] = {
		Props = {
			Source = "print('Hello World!')\n",
			Disabled = false,
		}
	},

	["LocalScript"] = {
		Props = {
			Source = "print('Hello World!')\n",
			Disabled = false,
		}
	},

	["ModuleScript"] = {
		Props = {
			Source = "local module = {}\n\nreturn module\n",
		}
	},

	-- Models & Folders
	["Model"] = {
		Props = { },
	},

	["Folder"] = {
		Props = { },
	},

	-- Values
	["StringValue"] = { Props = { Value = "" } },
	["BoolValue"] = { Props = { Value = false } },
	["IntValue"] = { Props = { Value = 0 } },
	["NumberValue"] = { Props = { Value = 0 } },
	["ObjectValue"] = { Props = { Value = nil } },
	["CFrameValue"] = { Props = { Value = CFrame.new() } },
	["Vector3Value"] = { Props = { Value = Vector3.new() } },
	["BrickColorValue"] = { Props = { Value = BrickColor.new("White") } },
	["Color3Value"] = { Props = { Value = Color3.fromRGB(255, 255, 255) } },

	-- Constraints
	["AlignPosition"] = {
		Props = {
			ApplyAtCenterOfMass = true,
			MaxForce = 10000,
			MaxVelocity = math.huge,
			Responsiveness = 200,
		}
	},

	["AlignOrientation"] = {
		Props = {
			PrimaryAxis = Vector3.new(1, 0, 0),
			SecondaryAxis = Vector3.new(0, 1, 0),
			MaxTorque = 10000,
			Responsiveness = 200,
		}
	},

	["HingeConstraint"] = {
		Props = {
			Active = false,
			AngularVelocity = 0,
			CurrentAngle = 0,
			MotorMaxTorque = 0,
			MotorSpeed = 0,
		}
	},

	["BallSocketConstraint"] = {
		Props = {
			LimitsEnabled = false,
			UpperAngle = 45,
		}
	},

	["WeldConstraint"] = {
		Props = {
			Enabled = true,
		}
	},

	["RopeConstraint"] = {
		Props = {
			Length = 2,
			Restitution = 0,
		}
	},

	["RigidConstraint"] = {
		Props = { }
	},

	["SpringConstraint"] = {
		Props = {
			Coils = 1,
			FreeLength = 2,
			Stiffness = 10,
			Damping = 1,
		}
	},

	-- GUI 3D
	["SurfaceSelection"] = {
		Props = {
			TargetSurface = Enum.NormalId.Front,
		}
	},

	["SelectionBox"] = {
		Props = {
			LineThickness = 0.05,
			Color3 = Color3.fromRGB(0, 162, 255),
		}
	},

	["SelectionSphere"] = {
		Props = {
			SurfaceColor3 = Color3.fromRGB(0, 162, 255),
			SurfaceTransparency = 0.5,
			Transparency = 0,
		}
	},

	["Highlight"] = {
		Props = {
			FillColor = Color3.fromRGB(255, 255, 255),
			FillTransparency = 0.5,
			OutlineTransparency = 0,
		}
	},

	-- Tools
	["Tool"] = {
		Props = {
			RequiresHandle = true,
		}
	},

	["HopperBin"] = {
		Props = {},
	},

	-- Meshes (legacy)
	["SpecialMesh"] = {
		Props = {
			MeshType = Enum.MeshType.Head,
			Scale = Vector3.new(1, 1, 1),
		}
	},

	-- Tween service objects
	["Animation"] = {
		Props = {
			AnimationId = "",
		}
	},
}

return INSTANCE_INSERT_INFO