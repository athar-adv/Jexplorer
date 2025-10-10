local TweenService = game:GetService('TweenService')
local Tween = require(script.Tween)

export type Tween = Tween.SimpleTween

local Transform = {
	tween = Tween.new
}

function Transform.bulkLerpTo(objects: {BasePart}, cframes: {CFrame}, alphas: {number})
	local cf = {}
	
	for i = 1, #objects do
		cf[i] = objects[i].CFrame:Lerp(cframes[i], alphas[i])
	end
		
	workspace:BulkMoveTo(objects, cf, Enum.BulkMoveMode.FireCFrameChanged)
end

function Transform.fullRotate(object: PVInstance, targetDegrees: number, seconds: number, Axis: Vector3, easeInfo: EaseInfo)
	local TargetVector = Axis.Unit * Vector3.new(math.rad(targetDegrees), math.rad(targetDegrees), math.rad(targetDegrees))
	local TIncrement = CFrame.Angles(TargetVector.X, TargetVector.Y, TargetVector.Z)
	local targetCFrame = object:GetPivot() * TIncrement

	return Tween.new(object, {CFrame = targetCFrame}, seconds, easeInfo)
end

function Transform.toDegree(object: PVInstance, targetDegrees: number, Axis: Vector3)
	local TargetVector = Axis.Unit * Vector3.new(math.rad(targetDegrees), math.rad(targetDegrees), math.rad(targetDegrees))
	local TIncrement = CFrame.Angles(TargetVector.X, TargetVector.Y, TargetVector.Z)
	local targetCFrame = object:GetPivot() * TIncrement

	object:PivotTo(targetCFrame)
end

function Transform.getMove(parent: Instance)
	local centerAttachment = Instance.new("Attachment")
	centerAttachment.Parent = parent

	local move = Instance.new("AlignPosition")

	move.Name = "Move"
	move.Mode = Enum.PositionAlignmentMode.OneAttachment
	move.Attachment0 = centerAttachment
	move.Parent = parent

	return move
end

function Transform.getGyro(parent: Instance)
	local centerAttachment = Instance.new("Attachment")
	centerAttachment.Parent = parent

	local gyro = Instance.new("AlignOrientation")

	gyro.Name = "Gyro"
	gyro.Mode = Enum.OrientationAlignmentMode.OneAttachment
	gyro.Attachment0 = centerAttachment
	gyro.Parent = parent

	return gyro
end

-- Utility function to generate BodyGyro & BodyPosition-like AlignOrientation and AlignPosition
function Transform.getMovers(parent: Instance)
	local centerAttachment = Instance.new("Attachment")
	centerAttachment.Parent = parent

	local move = Instance.new("AlignPosition")
	local gyro = Instance.new("AlignOrientation")

	move.Name = "Move"
	move.Mode = Enum.PositionAlignmentMode.OneAttachment
	move.Attachment0 = centerAttachment
	move.Parent = parent

	gyro.Name = "Gyro"
	gyro.Mode = Enum.OrientationAlignmentMode.OneAttachment
	gyro.Attachment0 = centerAttachment
	gyro.Parent = parent

	return move, gyro, centerAttachment
end

function Transform.weldModel(model: Model)
	if not model.PrimaryPart then
		model.PrimaryPart = model:FindFirstAncestorOfClass("Part")
		warn("Model primary part automatically set for: ", model)
	end
	for _, part in model:GetDescendants() do
		if part:IsA("BasePart") then
			local weld = Instance.new("WeldConstraint")
			weld.Part0 = model.PrimaryPart
			weld.Part1 = part
			weld.Parent = model.PrimaryPart
		end
	end
end

function Transform.breakWelds(model: Model)
	for _, v in model.PrimaryPart:GetChildren() do
		if v:IsA('WeldConstraint') then
			v:Destroy()
		end
	end
end

function Transform.toggleModelAnchor(model: Model, anchored: boolean)
	for _, part in model:GetDescendants() do
		if part:IsA("BasePart") then
			part.Anchored = anchored
			if anchored then
				part.AssemblyLinearVelocity = Vector3.zero
				part.AssemblyAngularVelocity = Vector3.zero
			end
		end
	end
end

function Transform.setModelNetOwner(model: Model, owner: Player?)
	for _, part in model:GetDescendants() do
		if part:IsA("BasePart") then
			part:SetNetworkOwner(owner)
		end
	end
end

function Transform.setModelCollision(model: Model, newGroup: string)
	for _, part in model:GetDescendants() do
		if part:IsA("BasePart") then
			part.CollisionGroup = newGroup
		end
	end
end

return Transform