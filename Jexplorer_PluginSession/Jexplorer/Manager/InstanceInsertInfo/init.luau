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
}


return INSTANCE_INSERT_INFO
