local ChangeHistoryService = game:GetService("ChangeHistoryService")

return {
	beginRecording = function(name: string): string?
		return ChangeHistoryService:TryBeginRecording(name, name)
	end,
	finishRecording = function(id: string?, operation: Enum.FinishRecordingOperation?)
		if not id then return end
		ChangeHistoryService:FinishRecording(id, operation or Enum.FinishRecordingOperation.Commit)
	end,
}