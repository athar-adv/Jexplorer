local ChangeHistoryService = game:GetService("ChangeHistoryService")

type fn = () -> ()

local lastRecordingId: string?
local lastRecordingState: Enum.FinishRecordingOperation?
local function onEnd(id, operationObject, ...)
	if id and lastRecordingId == id then
		ChangeHistoryService:FinishRecording(id, operationObject.v)
	end
	lastRecordingState = operationObject.v
	return ...
end

return function<T...>(name: string, fn: (cancel: fn, append: fn, commit: fn) -> T...): T...
	local id = ChangeHistoryService:TryBeginRecording(name, name)
	if not id then
		if lastRecordingId then
			ChangeHistoryService:FinishRecording(lastRecordingId, lastRecordingState or Enum.FinishRecordingOperation.Cancel)
			id = ChangeHistoryService:TryBeginRecording(name, name)
			if not id then
				-- Final fallback
				ChangeHistoryService:SetWaypoint(name)
			else
				lastRecordingId = id
			end
		else
			ChangeHistoryService:SetWaypoint(name)
		end
	else
		lastRecordingId = id
	end
	local operationObject = {v = Enum.FinishRecordingOperation.Commit}
	
	return onEnd(id, operationObject, fn(function()
		operationObject.v = Enum.FinishRecordingOperation.Cancel
	end, function()
		operationObject.v = Enum.FinishRecordingOperation.Append
	end, function()
		operationObject.v = Enum.FinishRecordingOperation.Commit
	end))
end