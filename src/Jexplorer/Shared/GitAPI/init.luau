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

local NULL = "NULL"

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

type contents = {
	{Type: "File", Result: APIResult<GitRepoItem & {content: string}>} |
	{Type: "Folder", Result: APIResult<GitRepoItem>}
}

function GitAPI.getFileContentsInFolder(authToken: LuaSecret, repoId: string, branch: string, path: string, nocache: boolean?, _contents: contents?): contents
	LuaSecret.assert_is(authToken)
	
	local authType = authToken:GetProperty("AuthType")
	
	local contents = GitAPI.getRepoContent(authToken, repoId, branch, path):Unwrap()
	assert(contents.type == "Folder", EXPECTED_FOLDER:format("GitAPI.getFileContentsInFolder"))
	
	local n = #contents.value
	local finished = 0
	
	local finalContents = _contents or {}
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
			--Is a folder
			if not apiResult.content then
				table.insert(finalContents,
					{
						Type = "Folder",
						Result = APIResult.new(
							success,
							200,
							"OK",
							child
						)
					}
				)
				return
			end
			child.content = Base64.from(apiResult.content)
			
			table.insert(finalContents,
				{
					Type = "File",
					Result = APIResult.new(
						success,
						200,
						"OK",
						child
					)
				}
			)
		end)
	end
	
	repeat task.wait() until finished == n
	return finalContents
end

function GitAPI.getFileOpsForInstances(root: Instance): {FileOperation}
	local operations: {FileOperation} = {}
	
	local function getFileExtension(instance: Instance): string
		if instance:IsA("ModuleScript") then
			return "luau"
		elseif instance:IsA("Script") then
			return "server.luau"
		elseif instance:IsA("LocalScript") then
			return "client.luau"
		end
		return "luau"
	end

	local function hasLuaSourceContainerChildren(instance: Instance): boolean
		for _, child in instance:GetChildren() do
			if child:IsA("LuaSourceContainer") or child:IsA("Folder") then
				return true
			end
		end
		return false
	end

	local function countLuaSourceContainers(parent: Instance): number
		local count = 0
		for _, child in parent:GetChildren() do
			if child:IsA("LuaSourceContainer") then
				count += 1
			end
		end
		return count
	end

	local function processInstance(instance: Instance, currentPath: string, isRoot: boolean)
		-- Skip non-LuaSourceContainer and non-Folder instances
		if not (instance:IsA("LuaSourceContainer") or instance:IsA("Folder")) then
			return
		end

		if instance:IsA("LuaSourceContainer") then
			local hasChildren = hasLuaSourceContainerChildren(instance)
			local source = (instance :: any).Source

			if hasChildren then
				-- Create folder with init.luau inside
				local folderPath = currentPath ~= "" 
					and `{currentPath}/{instance.Name}` 
					or instance.Name

				table.insert(operations, {
					path = `{folderPath}/init.{getFileExtension(instance)}`,
					content = source,
					mode = "100644",
					type = "blob"
				})

				-- Process children
				for _, child in instance:GetChildren() do
					processInstance(child, folderPath, false)
				end
			else
				-- Check if this is a direct child of root with no siblings
				if isRoot and countLuaSourceContainers(instance.Parent or root) == 1 then
					-- Name it init.luau
					local filePath = currentPath ~= ""
						and `{currentPath}/init.{getFileExtension(instance)}`
						or `init.{getFileExtension(instance)}`

					table.insert(operations, {
						path = filePath,
						content = source,
						mode = "100644",
						type = "blob"
					})
				else
					-- Regular file
					local filePath = currentPath ~= ""
						and `{currentPath}/{instance.Name}.{getFileExtension(instance)}`
						or `{instance.Name}.{getFileExtension(instance)}`

					table.insert(operations, {
						path = filePath,
						content = source,
						mode = "100644",
						type = "blob"
					})
				end
			end

		elseif instance:IsA("Folder") then
			-- Process folder children
			local folderPath = currentPath ~= ""
				and `{currentPath}/{instance.Name}`
				or instance.Name

			for _, child in instance:GetChildren() do
				processInstance(child, folderPath, false)
			end
		end
	end

	-- Start processing from root's children
	for _, child in root:GetChildren() do
		processInstance(child, "src", true)
	end

	return operations
end

do
	local function getExtension(path: string): string
		return path:match(".-%.([%w_]+)") or ""
	end
	
	local function getBaseName(path: string): string
		return path:match("(.-)%.") or ""
	end

	-- Recursive function to build instance tree
	function GitAPI.reconstructInstances(authToken, repoId: string, branch: string, path: string, parent: Instance?)
		local contents = GitAPI.getFileContentsInFolder(authToken, repoId, branch, path)

		for _, item in contents do
			if item.Type == "File" then
				local result = item.Result:Unwrap()
				local ext = getExtension(result.name)
				local baseName = getBaseName(result.name)
				local instance: any

				-- Create appropriate instance based on file type
				if ext == "lua" or ext == "luau" then
					instance = Instance.new("ModuleScript")
					instance.Name = baseName
					instance.Source = result.content -- Content is already decoded by GitAPI
				elseif ext == "server" then
					instance = Instance.new("Script")
					instance.Name = baseName
					instance.Source = result.content

				elseif ext == "client" then
					instance = Instance.new("LocalScript")
					instance.Name = baseName
					instance.Source = result.content
				end

				if parent then
					instance.Parent = parent
				end

			elseif item.Type == "Folder" then
				local result = item.Result:Unwrap()
				-- Create folder and recurse
				local folder = Instance.new("Folder")
				folder.Name = result.name

				if parent then
					folder.Parent = parent
				end

				-- Recursively process subfolder
				GitAPI.reconstructInstances(authToken, repoId, branch, result.path, folder)
			end
		end
	end
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
	
	local treeItems: {any} = {}
	for _, file in files do
		if not file.path or file.path == "" then
			continue
		end

		local cleanPath = string.gsub(file.path, "^/+", "")
		cleanPath = string.gsub(cleanPath, "/+$", "")

		if cleanPath == "" then continue end

		if file.content == nil then
			table.insert(treeItems, {
				path = cleanPath,
				mode = "100644",
				sha = NULL     -- placeholder
			})
		else
			table.insert(treeItems, {
				path = cleanPath,
				mode = file.mode or "100644",
				type = file.type or "blob",
				content = file.content
			})
		end
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
			Body = HttpService:JSONEncode(requestBody):gsub(`"{NULL}"`, "null")
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

function GitAPI.batchOverwrite(
	authToken: LuaSecret,
	repoId: string,
	branch: string,
	path: string,
	files: {FileOperation},
	commitMessage: string?
): APIResult
	LuaSecret.assert_is(authToken)

	local authType = authToken:GetProperty("AuthType")
	assert(authType == "fine_grained", EXPECTED_FG:format("GitAPI.batchOverwrite"))

	-- Recursive function to get all files in a folder structure
	local function getAllFilesRecursive(folderPath: string, collected: {{Type: any, Result: APIResult<...any>}}?): {any}
		local collected = collected or {}

		local success, contents = pcall(function()
			return GitAPI.getFileContentsInFolder(authToken, repoId, branch, folderPath)
		end)

		if not success then
			warn(`Failed to get contents of folder: {folderPath}`)
			return collected
		end

		for _, item in contents do
			if item.Type == "File" then
				table.insert(collected, item)
			elseif item.Type == "Folder" then
				local folderResult = item.Result
				if folderResult.Success then
					local result = folderResult:Unwrap()
					-- Recursively get all files in this subfolder
					getAllFilesRecursive(result.path, collected)
				end
			end
		end

		return collected
	end

	-- Get all existing files in the folder (recursively)
	local existingFiles = getAllFilesRecursive(path)

	-- Build a set of paths that should exist after the operation
	local targetPaths = {}
	for _, file in files do
		if file.path and file.path ~= "" then
			local cleanPath = string.gsub(file.path, "^/+", "")
			cleanPath = string.gsub(cleanPath, "/+$", "")
			if cleanPath ~= "" then
				-- Store full path
				local fullPath = cleanPath
				targetPaths[fullPath] = true
			end
		end
	end

	-- Prepare operations: updates + deletes
	local operations: {FileOperation} = {}

	-- Add all the files to create/update
	for _, file in files do
		-- Ensure paths are prefixed with the base path if needed
		local cleanPath = string.gsub(file.path, "^/+", "")
		cleanPath = string.gsub(cleanPath, "/+$", "")
		
		if cleanPath ~= "" then
			table.insert(operations, {
				path = cleanPath,
				content = file.content,
				mode = file.mode,
				type = file.type
			})
		end
	end

	-- Add delete operations for files not in the target set
	for _, item in existingFiles do
		if item.Result.Success then
			local result = item.Result:Unwrap()
			if not targetPaths[result.path] then
				-- This file exists remotely but wasn't provided, mark for deletion
				table.insert(operations, {
					path = result.path,
					content = nil -- nil means delete in batchCreateOrUpdate
				})
			end
		end
	end

	-- Execute the batch operation
	return GitAPI.batchCreateOrUpdate(
		authToken,
		repoId,
		branch,
		operations,
		commitMessage or `Overwrite contents of '{path}'`
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

function GitAPI.revertLastCommit(
	authToken: LuaSecret,
	repoId: string,
	branch: string,
	commitMessage: string?
): APIResult<{
	commitSha: string,
	revertedCommitSha: string,
	commit: typeof(((nil :: any) :: GitBranchInfo).commit.commit)
}?>
	LuaSecret.assert_is(authToken)

	local authType = authToken:GetProperty("AuthType")
	assert(authType == "fine_grained", EXPECTED_FG:format("GitAPI.revertLastCommit"))

	-- Get the latest commit
	local branchInfo = GitAPI.getLatestBranchInfo(authToken, repoId, branch):Unwrap()
	local latestCommitSha = branchInfo.commit.sha
	local parentCommits = branchInfo.commit.parents

	if #parentCommits == 0 then
		return APIResult.new(false, 400, "Cannot revert initial commit (no parent)")
	end

	local parentCommitSha = parentCommits[1].sha

	-- Get the tree from the parent commit (the state before the last commit)
	local parentCommitUrl = `https://api.github.com/repos/{repoId}/git/commits/{parentCommitSha}`
	local parentSuccess, parentResponse = pcall(function()
		return HttpService:RequestAsync({
			Url = parentCommitUrl,
			Method = "GET",
			Headers = {
				["Authorization"] = token(authToken, authType),
				["Accept"] = "application/vnd.github.v3+json"
			}
		})
	end)

	if not parentSuccess or not parentResponse.Success then
		return APIResult.new(
			false,
			parentResponse and parentResponse.StatusCode or 500,
			"Failed to fetch parent commit"
		)
	end

	local parentCommitData = HttpService:JSONDecode(parentResponse.Body)
	local parentTreeSha = parentCommitData.tree.sha

	-- Create a new commit with the parent's tree (effectively reverting)
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
				message = commitMessage or `Revert "{branchInfo.commit.commit.message}"`,
				tree = parentTreeSha,
				parents = {latestCommitSha}
			})
		})
	end)

	if not commitSuccess or not commitResponse.Success then
		local errorMsg = "Failed to create revert commit"
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

	-- Update the branch reference to point to the new commit
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
			revertedCommitSha = latestCommitSha,
			commit = branchInfo.commit.commit
		} or nil
	)
end

return GitAPI