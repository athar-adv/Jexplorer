return function(frameSize: Vector2, originalPosition: Vector2, size: Vector2, containerPos: Vector2, containerSize: Vector2): (number, number)
	local left = containerPos.X
	local top = containerPos.Y
	local right = containerPos.X + containerSize.X
	local bottom = containerPos.Y + containerSize.Y

	local desiredX = originalPosition.X
	local desiredY = originalPosition.Y + size.Y
	if desiredX + frameSize.X > right then
		desiredX = right - frameSize.X
	end
	if desiredX < left then
		desiredX = left
	end
	if desiredY + frameSize.Y > bottom then
		desiredY = originalPosition.Y - frameSize.Y
		if desiredY < top then
			desiredY = bottom - frameSize.Y
		end
	end
	if desiredY < top then
		desiredY = top
	end
	return 	math.max(left, math.min(desiredX, right - frameSize.X)),
			math.max(top, math.min(desiredY, bottom - frameSize.Y))
end