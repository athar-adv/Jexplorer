--!strict
--!optimize 2

local HttpService = game:GetService('HttpService')

local LuaSecret = require(script.LuaSecret)
local Base64 = require(script.Base64)
local APIResult = require(script.APIResult)

export type LuaSecret = LuaSecret.LuaSecret
type APIResult<T... = ()> = APIResult.APIResult<T...>
type AuthType = "classic" | "fine_grained" 

type GitRepoItem = {
	_links: {
		git: string,
		html: string,
		self: string,
	},
	download_url: string,
	git_url: string,
	html_url: string,
	name: string,
	path: string,
	sha: string,
	size: number,
	type: string,
	url: string
}

export type FileOperation = {
	path: string,
	content: string?,  -- nil for delete operations
	mode: "100644" | "100755" | "040000" | "160000" | "120000"?, -- optional, defaults to 100644
	type: "blob" | "tree" | "commit"? -- optional, defaults to blob
}

export type GitRepoFolder = {GitRepoItem}
export type GitBranchInfo = {
	_links: {
		html: string,
		self: string
	},
	name: string,
	protected: boolean,
	protection: {
		enabled: boolean,
		required_status_checks: {
			checks: {any},
			contexts: {any},
			enforcement_level: "off" | "on"
		}
	},
	protection_url: string,
	commit: {
		commit: {
			author: {
				date: string,
				email: string,
				name: string
			},
			comment_count: number,
			committer: {
				date: string,
				email: string,
				name: string
			},
			message: string,
			tree: {
				sha: string,
				url: string
			},
			url: string,
			verification: {
				payload: string,
				reason: string,
				signature: string,
				verified: boolean,
				verified_at: string
			}
		},
		committer: {
			avatar_url: string,
			events_url: string,
			followers_url: string,
			following_url: string,
			gists_url: string,
			gravatar_id: string,
			html_url: string,
			id: number,
			login: string,
			node_id: string,
			organizations_url: string,
			recieved_events_url: string,
			repos_url: string,
			site_admin: boolean,
			starred_url: string,
			subscriptions_url: string,
			type: string,
			url: string,
			user_view_type: "public" | "private"
		},
		html_url: string,
		node_id: string,
		parents: {
			{
				html_url: string,
				sha: string,
				url: string
			}
		},
		sha: string,
		url: string
	}
}

local AUTH_TYPE_TO_PREFIX = {
	classic = "token ",
	fine_grained = "Bearer "
}

local EXPECTED_FILE = "'%s' requires that 'path' point to a file, not a folder."
local EXPECTED_FOLDER = "'%s' requires that 'path' point to a folder, not a file/other item."
local EXPECTED_FG = "authToken.AuthType must be 'fine_grained' for '%s'"

local ROOT_ENV = debug.info(1, "f")

local function token(auth: LuaSecret, authType: AuthType)
	return LuaSecret.get(
		auth:AddPrefix(AUTH_TYPE_TO_PREFIX[authType]),
		2
	)
end

local AuthToken = {}

function AuthToken.new(auth: Secret | string, authType: AuthType)
	assert(authType == "classic" or authType == "fine_grained", `Expected ' 'classic' | 'fine_grained' ' for 'authType', got '{typeof(authType)}'`)
	assert(typeof(auth) == "Secret" or typeof(auth) == "string", `Expected 'Secret | string' for 'auth', got '{typeof(auth)}'`)
	
	local secret = LuaSecret.new(auth, ROOT_ENV)
	secret:SetProperty("AuthType", authType, 2)
	
	return secret
end

function AuthToken.fromSecret(key: string, authType: AuthType)
	local auth = AuthToken.new(HttpService:GetSecret(key), authType)
	auth:SetProperty("SecretKey", key, 2)
	
	return auth
end

function AuthToken.serialize(authToken: LuaSecret): string
	LuaSecret.assert_is(authToken)
	
	local authType = authToken:GetProperty("AuthType")
	local value = LuaSecret.get(authToken, 2)
	
	if typeof(value) == "Secret" then
		return Base64.to(`1:{authType}:{authToken:GetProperty("SecretKey")}`)
	end
	return Base64.to(`2:{authType}:{value}`)
end

function AuthToken.deserialize(serialized: string): LuaSecret
	local deencoded = Base64.from(serialized)
	local valueType, authType: any, auth = string.match(deencoded, "(%d):(.*):(.*)")
	assert(valueType and authType and auth, `'{serialized}' does not fit serialization format.`)
	
	if valueType == "1" then
		-- Secret
		return AuthToken.fromSecret(auth, authType)
	elseif valueType == "2" then
		-- String
		return AuthToken.new(auth, authType)
	else
		error("unknown value type")
	end
end

local GitAPI = {
	AuthToken = AuthToken
}

function GitAPI.getRepoContent(authToken: LuaSecret, repoId: string, branch: string, path: string): APIResult<{type: "Folder", value: GitRepoFolder} | {type: "Item", value: GitRepoItem}>
	LuaSecret.assert_is(authToken)
	
	local authType = authToken:GetProperty("AuthType")
	
	local url = `https://api.github.com/repos/{repoId}/contents/{path}?ref={branch}`
	
	local success, response = pcall(function()
		return HttpService:RequestAsync({
			Url = url,
			Method = "GET",
			Headers = {
				["Authorization"] = token(authToken, authType),
				["Accept"] = "application/vnd.github.v3+json"
			}
		})
	end)
	
	local apiResult
	if response.Success then
		apiResult = HttpService:JSONDecode(response.Body)
	end
	
	return APIResult.new(
		response.Success,
		response.StatusCode,
		response.StatusMessage,
		apiResult and {
			type = #apiResult > 0 and "Folder" or "Item",
			value = apiResult
		} or nil :: any
	)
end

function GitAPI.getFileContentsInFolder(authToken: LuaSecret, repoId: string, branch: string, path: string, nocache: boolean?): {APIResult<GitRepoItem & {content: string}>}
	LuaSecret.assert_is(authToken)
	
	local authType = authToken:GetProperty("AuthType")
	
	local contents = GitAPI.getRepoContent(authToken, repoId, branch, path):Unwrap()
	assert(contents.type == "Folder", EXPECTED_FOLDER:format("GitAPI.getFileContentsInFolder"))
	
	local n = #contents.value
	local finished = 0
	
	local finalContents = {}
	for _, child: any in contents.value do
		task.spawn(function()
			local success, response: any = pcall(function()
				return HttpService:GetAsync(child.git_url, nocache, {
					["Authorization"] = token(authToken, authType),
					["Accept"] = "application/vnd.github.v3+json"
				})
			end)
			finished += 1
			
			if not success then return end
			
			local apiResult = HttpService:JSONDecode(response)
			child.content = Base64.from(apiResult.content)
			
			table.insert(finalContents,
				APIResult.new(
					success,
					200,
					"OK",
					child
				)
			)
		end)
	end
	
	repeat task.wait() until finished == n
	return finalContents
end

function GitAPI.getLatestBranchInfo(authToken: LuaSecret, repoId: string, branch: string): APIResult<GitBranchInfo>
	LuaSecret.assert_is(authToken)
	
	local authType = authToken:GetProperty("AuthType")
	
	local url = `https://api.github.com/repos/{repoId}/branches/{branch}`
	
	local success, response = pcall(function()
		return HttpService:RequestAsync({
			Url = url,
			Method = "GET",
			Headers = {
				["Authorization"] = token(authToken, authType),
				["Accept"] = "application/vnd.github.v3+json"
			}
		})
	end)
	
	local apiResult
	if response.Success then
		apiResult = HttpService:JSONDecode(response.Body)
	end
	
	return APIResult.new(
		response.Success,
		response.StatusCode,
		response.StatusMessage,
		apiResult
	)
end

function GitAPI.createOrUpdateFile(authToken: LuaSecret, repoId: string, branch: string, path: string, source: string, commitMessage: string?): APIResult
	LuaSecret.assert_is(authToken)
	
	local authType = authToken:GetProperty("AuthType")
	assert(authType == "fine_grained", EXPECTED_FG:format("GitAPI.createOrUpdateFile"))
	
	local repoInfo = GitAPI.getRepoContent(authToken, repoId, branch, path)
	local sha
	if repoInfo.Success then
		local result = repoInfo:Unwrap()
		assert(result.type == "Item", EXPECTED_FILE:format("GitAPI.createOrUpdateFile"))
		
		sha = result.value.sha
	else
		sha = GitAPI.getLatestBranchInfo(authToken, repoId, branch):Unwrap().commit.sha
	end
	
	local url = `https://api.github.com/repos/{repoId}/contents/{path}`
	local requestBody = {
		message = commitMessage or `Updated '{path}'`,
		content = Base64.to(source),
		branch = branch,
		sha = sha
	}
	
	local success, response = pcall(function()
		return HttpService:RequestAsync({
			Url = url,
			Method = "PUT",
			Headers = {
				["Authorization"] = token(authToken, authType),
				["Accept"] = "application/vnd.github.v3+json",
			},
			Body = HttpService:JSONEncode(requestBody)
		})
	end)
	
	return APIResult.new(
		response.Success,
		response.StatusCode,
		response.StatusMessage
	)
end

function GitAPI.deleteFile(authToken: LuaSecret, repoId: string, branch: string, path: string, commitMessage: string?): APIResult
	LuaSecret.assert_is(authToken)

	local authType = authToken:GetProperty("AuthType")
	assert(authType == "fine_grained", EXPECTED_FG:format("GitAPI.deleteFile"))
	
	local repoInfo = GitAPI.getRepoContent(authToken, repoId, branch, path):Unwrap()
	assert(repoInfo.type == "Item", EXPECTED_FILE:format("GitAPI.deleteFile"))
	
	local url = `https://api.github.com/repos/{repoId}/contents/{path}`
	
	local success, response = pcall(function()
		return HttpService:RequestAsync({
			Url = url,
			Method = "DELETE",
			Headers = {
				["Authorization"] = token(authToken, authType),
				["Accept"] = "application/vnd.github.v3+json",
			},
			Body = HttpService:JSONEncode({
				message = commitMessage or `Deleted '{path}'`,
				branch = branch,
				sha = repoInfo.value.sha
			})
		})
	end)
	
	return APIResult.new(
		response.Success,
		response.StatusCode,
		response.StatusMessage
	)
end

function GitAPI.createBranch(authToken: LuaSecret, repoId: string, branchName: string, baseSha: string?): APIResult
	LuaSecret.assert_is(authToken)
	
	local authType = authToken:GetProperty("AuthType")
	assert(authType == "fine_grained", EXPECTED_FG:format("GitAPI.deleteFile"))
	
	local url = `https://api.github.com/repos/{repoId}/git/refs`
	
	local success, response = pcall(function()
		return HttpService:RequestAsync({
			Url = url,
			Method = "POST",
			Headers = {
				["Authorization"] = token(authToken, authType),
				["Accept"] = "application/vnd.github.v3+json"
			},
			Body = HttpService:JSONEncode({
				ref = `refs/heads/{branchName}`,
				sha = baseSha or GitAPI.getLatestBranchInfo(authToken, repoId, "main"):Unwrap().commit.sha
			})
		})
	end)
	
	return APIResult.new(
		response.Success,
		response.StatusCode,
		response.StatusMessage
	)
end

function GitAPI.batchCreateOrUpdate(
	authToken: LuaSecret, 
	repoId: string, 
	branch: string, 
	files: {FileOperation}, 
	commitMessage: string?
): APIResult
	LuaSecret.assert_is(authToken)

	local authType = authToken:GetProperty("AuthType")
	assert(authType == "fine_grained", EXPECTED_FG:format("GitAPI.batchCreateOrUpdate"))

	if #files == 0 then
		return APIResult.new(false, 400, "No files to process")
	end
	
	local branchInfo = GitAPI.getLatestBranchInfo(authToken, repoId, branch):Unwrap()
	local latestCommitSha = branchInfo.commit.sha
	local baseTreeSha = branchInfo.commit.commit.tree.sha
	
	local treeItems = {}
	for _, file in files do
		if not file.path or file.path == "" then
			continue
		end
		
		local cleanPath = string.gsub(file.path, "^/+", "")
		cleanPath = string.gsub(cleanPath, "/+$", "")

		if cleanPath == "" then continue end

		local item = {
			path = cleanPath,
			mode = file.mode or "100644",
			type = file.type or "blob"
		}

		if file.content then
			item.content = file.content
		end
		table.insert(treeItems, item)
	end

	if #treeItems == 0 then
		return APIResult.new(false, 400, "No valid files to process after filtering")
	end
	
	local createTreeUrl = `https://api.github.com/repos/{repoId}/git/trees`
	local requestBody = {
		base_tree = baseTreeSha,
		tree = treeItems
	}

	local treeSuccess, treeResponse = pcall(function()
		return HttpService:RequestAsync({
			Url = createTreeUrl,
			Method = "POST",
			Headers = {
				["Authorization"] = token(authToken, authType),
				["Accept"] = "application/vnd.github.v3+json",
				["Content-Type"] = "application/json"
			},
			Body = HttpService:JSONEncode(requestBody)
		})
	end)

	if not treeSuccess or not treeResponse.Success then
		local errorMsg = "Tree creation failed"
		if treeResponse and treeResponse.Body then
			local success, errorData = pcall(function() 
				return HttpService:JSONDecode(treeResponse.Body) 
			end)
			if success and errorData.message then
				errorMsg = errorData.message
			end
		end
		return APIResult.new(
			false,
			treeResponse and treeResponse.StatusCode or 500,
			errorMsg
		)
	end

	local treeData = HttpService:JSONDecode(treeResponse.Body)
	local newTreeSha = treeData.sha
	
	local createCommitUrl = `https://api.github.com/repos/{repoId}/git/commits`
	local commitSuccess, commitResponse = pcall(function()
		return HttpService:RequestAsync({
			Url = createCommitUrl,
			Method = "POST",
			Headers = {
				["Authorization"] = token(authToken, authType),
				["Accept"] = "application/vnd.github.v3+json",
				["Content-Type"] = "application/json"
			},
			Body = HttpService:JSONEncode({
				message = commitMessage or "Batch file operations",
				tree = newTreeSha,
				parents = {latestCommitSha}
			})
		})
	end)

	if not commitSuccess or not commitResponse.Success then
		local errorMsg = "Commit creation failed"
		if commitResponse and commitResponse.Body then
			local success, errorData = pcall(function() 
				return HttpService:JSONDecode(commitResponse.Body) 
			end)
			if success and errorData.message then
				errorMsg = errorData.message
			end
		end
		return APIResult.new(
			false,
			commitResponse and commitResponse.StatusCode or 500,
			errorMsg
		)
	end

	local commitData = HttpService:JSONDecode(commitResponse.Body)
	local newCommitSha = commitData.sha
	
	local updateRefUrl = `https://api.github.com/repos/{repoId}/git/refs/heads/{branch}`
	local refSuccess, refResponse = pcall(function()
		return HttpService:RequestAsync({
			Url = updateRefUrl,
			Method = "PATCH",
			Headers = {
				["Authorization"] = token(authToken, authType),
				["Accept"] = "application/vnd.github.v3+json",
				["Content-Type"] = "application/json"
			},
			Body = HttpService:JSONEncode({
				sha = newCommitSha
			})
		})
	end)

	return APIResult.new(
		refResponse.Success,
		refResponse.StatusCode,
		refResponse.StatusMessage,
		refResponse.Success and {
			commitSha = newCommitSha,
			treeSha = newTreeSha
		} or nil
	)
end

-- Convenience function for creating multiple files
function GitAPI.createMultipleFiles(
	authToken: LuaSecret,
	repoId: string,
	branch: string,
	files: {{path: string, content: string}},
	commitMessage: string?
): APIResult
	local operations: {FileOperation} = {}
	for _, file in files do
		table.insert(operations, {
			path = file.path,
			content = file.content,
			mode = "100644",
			type = "blob"
		})
	end

	return GitAPI.batchCreateOrUpdate(authToken, repoId, branch, operations, commitMessage)
end

-- Convenience function for deleting multiple files
function GitAPI.deleteMultipleFiles(
	authToken: LuaSecret,
	repoId: string,
	branch: string,
	paths: {string},
	commitMessage: string?
): APIResult
	local operations = {}
	for _, path in paths do
		table.insert(operations, {
			path = path,
			content = nil -- nil content means delete
		})
	end

	return GitAPI.batchCreateOrUpdate(authToken, repoId, branch, operations, commitMessage)
end

return GitAPI