-- Contact loader configuration.
--
-- Every table entry describes one supported Roblox experience. The loader
-- compares both identifiers because several places can belong to one game,
-- while a place identifier alone does not document that relationship as
-- clearly. Add another entry to this array whenever another script needs to be
-- routed without changing any of the loading logic below.
local GameScriptConfigurations = {
	{
		RequiredGameIdentifier = 7326934954,
		RequiredPlaceIdentifier = 79546208627805,
		ScriptUniformResourceLocator = "https://api.luarmor.net/files/v4/loaders/b0085b50bef7e49153fda15f755894d9.lua",
	},
}

-- Executor compatibility helpers are resolved once at startup. Roblox methods
-- are cloned when the executor provides native cloning primitives, while plain
-- Luau environments keep the original references as a compatibility fallback.
local CloneFunction
local CloneReference

-- Only trust a native cloning primitive. A Lua wrapper with the same global
-- name could alter arguments or results before the loader reaches Roblox.
local RawCloneFunction = clonefunc or clonefunction
local CloneFunctionIsNative = false
if type(RawCloneFunction) == "function" and debug and type(debug.info) == "function" then
	local DebugInformationReadSucceeded, FunctionSource = pcall(debug.info, RawCloneFunction, "s")
	if DebugInformationReadSucceeded and FunctionSource == "[C]" then
		CloneFunctionIsNative = true
	end
end

if CloneFunctionIsNative then
	CloneFunction = RawCloneFunction
else
	-- Returning the supplied function preserves normal behavior when cloning is
	-- unavailable, which also keeps this loader usable in development runtimes.
	CloneFunction = function(TargetFunction)
		return TargetFunction
	end
end

-- Instance references receive the same native-only treatment. The cloned data
-- model reference is then reused by every operation in this file.
local RawCloneReference = cloneref or clone_ref or clonereference
local CloneReferenceIsNative = false
if type(RawCloneReference) == "function" and debug and type(debug.info) == "function" then
	local DebugInformationReadSucceeded, FunctionSource = pcall(debug.info, RawCloneReference, "s")
	if DebugInformationReadSucceeded and FunctionSource == "[C]" then
		CloneReferenceIsNative = true
	end
end

if CloneReferenceIsNative then
	CloneReference = RawCloneReference
else
	-- A regular Instance reference remains valid when the executor does not
	-- expose a native reference-cloning implementation.
	CloneReference = function(TargetReference)
		return TargetReference
	end
end

local DataModel = CloneReference(game)
local HttpGet = CloneFunction(DataModel.HttpGet)
local IsDataModelLoaded = CloneFunction(DataModel.IsLoaded)
local DataModelLoadedSignal = DataModel.Loaded
local WaitForDataModelLoaded = CloneFunction(DataModelLoadedSignal.Wait)

-- Roblox exposes a one-shot Loaded signal specifically for initialization.
-- Check IsLoaded first because waiting after the signal has already fired would
-- suspend the current thread permanently.
if not IsDataModelLoaded(DataModel) then
	WaitForDataModelLoaded(DataModelLoadedSignal)
end

-- FetchLink first uses the executor request API because it exposes status
-- metadata, then falls back to the cloned DataModel.HttpGet method for older
-- environments. A failed request returns nil and never executes partial data.
local RequestFunction = request or http_request or (syn and syn.request)
local function FetchLink(UniformResourceLocatorString)
	if type(UniformResourceLocatorString) ~= "string" or UniformResourceLocatorString == "" then
		return nil
	end

	if type(RequestFunction) == "function" then
		local RequestSucceeded, RequestResult = pcall(RequestFunction, {
			Url = UniformResourceLocatorString,
			Method = "GET",
		})

		if RequestSucceeded
			and type(RequestResult) == "table"
			and (RequestResult.StatusCode == 200 or RequestResult.Status == 200)
			and type(RequestResult.Body) == "string"
		then
			return RequestResult.Body
		end
	end

	local HttpGetSucceeded, ResponseBody = pcall(
		HttpGet,
		DataModel,
		UniformResourceLocatorString
	)
	if HttpGetSucceeded and type(ResponseBody) == "string" then
		return ResponseBody
	end

	return nil
end

-- Find the first route whose game and place identifiers both match the active
-- experience. Unknown games intentionally produce no output and no network
-- request, so this file can safely be used as one shared entry point.
local function FindMatchingScriptConfiguration(CurrentGameIdentifier, CurrentPlaceIdentifier)
	for ConfigurationIndex = 1, #GameScriptConfigurations do
		local ScriptConfiguration = GameScriptConfigurations[ConfigurationIndex]
		local ConfigurationIsValid = type(ScriptConfiguration) == "table"
		local GameIdentifierMatches = ConfigurationIsValid
			and ScriptConfiguration.RequiredGameIdentifier == CurrentGameIdentifier
		local PlaceIdentifierMatches = ConfigurationIsValid
			and ScriptConfiguration.RequiredPlaceIdentifier == CurrentPlaceIdentifier

		if GameIdentifierMatches and PlaceIdentifierMatches then
			return ScriptConfiguration
		end
	end

	return nil
end

local CurrentGameIdentifier = DataModel.GameId
local CurrentPlaceIdentifier = DataModel.PlaceId
local MatchingScriptConfiguration = FindMatchingScriptConfiguration(
	CurrentGameIdentifier,
	CurrentPlaceIdentifier
)

-- A missing route means that Contact does not support the current experience.
-- Exit silently before downloading or compiling any remote source.
if not MatchingScriptConfiguration then
	return
end

local ScriptSource = FetchLink(MatchingScriptConfiguration.ScriptUniformResourceLocator)
if type(ScriptSource) ~= "string" or ScriptSource == "" or type(loadstring) ~= "function" then
	return
end

-- Compilation and execution are isolated independently. This prevents a bad
-- response or a runtime error inside one routed script from breaking the loader
-- itself or accidentally falling through to another configuration entry.
local ScriptCompilationSucceeded, CompiledScript = pcall(loadstring, ScriptSource)
if not ScriptCompilationSucceeded or type(CompiledScript) ~= "function" then
	return
end

local ScriptExecutionSucceeded, ScriptExecutionResult = pcall(CompiledScript)
if not ScriptExecutionSucceeded then
	return
end
