return function(containerWidth: number, frameX: number, offset: number)
	local padding = 20

	return UDim2.new(
		0,
		containerWidth - frameX - padding + offset,
		0.5,
		0
	)
end