local ChangeHistoryService = game:GetService("ChangeHistoryService")

return {
	beginRecording = function(name: string)
		local id = ChangeHistoryService:TryBeginRecording(name, name)
		if not id then
			ChangeHistoryService:SetWaypoint(name)
		end
		return id
	end,
	finishRecording = function(id: string?, operation: Enum.FinishRecordingOperation?)
		if id then
			ChangeHistoryService:FinishRecording(id, operation or Enum.FinishRecordingOperation.Commit)
		end
	end,
}