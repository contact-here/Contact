-- Every table entry describes one supported Roblox experience. The loader
-- compares both identifiers because several places can belong to one game,
-- while a place identifier alone does not document that relationship as
-- clearly. Add another entry to this array whenever another script needs to be
-- routed without changing any of the loading logic below.
local GameScriptConfigurations = {
	{
		RequiredGameIdentifier = 7326934954,
		RequiredPlaceIdentifier = 126509999114328,
		ScriptIdentifier = "b97820e6e01f226d0008bb53b38a37b3",
		KeySystem = true,
	},
	{
		RequiredGameIdentifier = 66654135,
		RequiredPlaceIdentifier = 142823291,
		ScriptIdentifier = "b1d9c28e83468d6e0aba05732cf9a9ce",
		KeySystem = false,
	}
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

local function ShowLoaderNotification(NotificationMessage)
	pcall(function()
		local StarterGui = CloneReference(DataModel:GetService("StarterGui"))
		StarterGui:SetCore("SendNotification", {
			Title = "Contact",
			Text = tostring(NotificationMessage),
			Duration = 8,
		})
	end)
end
-- Cached keys are always verified by Luarmor before protected scripts execute.
if MatchingScriptConfiguration.KeySystem == true then
	local function LoadRemoteModule(ModuleUniformResourceLocator)
		local ModuleSource = FetchLink(ModuleUniformResourceLocator)
		if type(ModuleSource) ~= "string"
			or ModuleSource == ""
			or type(loadstring) ~= "function"
		then
			return nil
		end

		local ModuleCompilationSucceeded, CompiledModule = pcall(loadstring, ModuleSource)
		if not ModuleCompilationSucceeded or type(CompiledModule) ~= "function" then
			return nil
		end

		local ModuleExecutionSucceeded, ModuleResult = pcall(CompiledModule)
		if ModuleExecutionSucceeded then
			return ModuleResult
		end

		return nil
	end

	local KeyVerificationMessages = {
		KEY_EXPIRED = "Your key has expired. Get a new key from a provider.",
		KEY_BANNED = "Your key is blocked. Contact @contactbyfron in https://discord.gg/contactinghere or contact@contactinghere.lol email for help.",
		KEY_HWID_LOCKED = "This key belongs to another device. Reset your HWID using the bot or key page.",
		KEY_INCORRECT = "This key does not exist or was deleted. Check it or get a new key.",
		KEY_INVALID = "Invalid key format. Paste the complete key without extra characters.",
		SCRIPT_ID_INCORRECT = "This script is unavailable. Contact the script owner.",
		SCRIPT_ID_INVALID = "The script identifier is misconfigured. Contact the script owner.",
		INVALID_EXECUTOR = "Unsupported executor or invalid device information. Update your executor or try another.",
		SECURITY_ERROR = "Luarmor could not verify this request. Please retry later.",
		TIME_ERROR = "Check your device date and time, then retry. The request may have timed out.",
		UNKNOWN_ERROR = "Luarmor is temporarily unavailable. Please retry later.",
	}
	local KeyVerificationLibrary

	local function ValidateScriptKey(ScriptKeyText)
		if not KeyVerificationLibrary then
			KeyVerificationLibrary = LoadRemoteModule("https://sdkapi-public.luarmor.net/library.lua")
			if type(KeyVerificationLibrary) ~= "table"
				or type(KeyVerificationLibrary.check_key) ~= "function"
			then
				KeyVerificationLibrary = nil
				return false, "Cannot reach Luarmor. Please retry."
			end

			-- These lowercase fields belong to the external Luarmor SDK contract.
			KeyVerificationLibrary.script_id = MatchingScriptConfiguration.ScriptIdentifier
		end

		local KeyVerificationSucceeded, KeyVerificationResponse = pcall(
			KeyVerificationLibrary.check_key,
			ScriptKeyText
		)
		if not KeyVerificationSucceeded or type(KeyVerificationResponse) ~= "table" then
			return false, "Network error. Please retry."
		end

		if KeyVerificationResponse.code == "KEY_VALID" then
			return true
		end

		local VerificationStatusCode = tostring(KeyVerificationResponse.code or "UNKNOWN_ERROR")
		local VerificationStatusMessage = KeyVerificationMessages[VerificationStatusCode]
			or "Unexpected verification error. Please retry or contact support."
		return false, VerificationStatusMessage
	end

	local SavedKeyFolderPath = "Contact"
	local SavedKeyFilePath = SavedKeyFolderPath .. "/Key"
	-- Separate from configuration encryption. Local reversible protection cannot
	-- hide the key from someone who controls this device and this loader.
	local KeyStorageEncryptionSecret = "Contact|ProjectAccess|StorageV1|7B29D4E18C63A05F"

	local function TransformKeyStorageByte(InputByte, SecretByte)
		local TransformedByte = 0
		local CurrentBitValue = 1
		for BitIndex = 1, 8 do
			if InputByte % 2 ~= SecretByte % 2 then
				TransformedByte = TransformedByte + CurrentBitValue
			end
			InputByte = math.floor(InputByte / 2)
			SecretByte = math.floor(SecretByte / 2)
			CurrentBitValue = CurrentBitValue * 2
		end
		return TransformedByte
	end

	local function EncryptStoredKey(PlainScriptKey)
		local EncodedBytes = {}
		local StoragePayload = "ContactKeyV1:" .. PlainScriptKey
		for ByteIndex = 1, #StoragePayload do
			local SecretByteIndex = (ByteIndex - 1) % #KeyStorageEncryptionSecret + 1
			EncodedBytes[ByteIndex] = string.format("%02x", TransformKeyStorageByte(
				string.byte(StoragePayload, ByteIndex),
				string.byte(KeyStorageEncryptionSecret, SecretByteIndex)
			))
		end
		return table.concat(EncodedBytes)
	end

	local function DecryptStoredKey(EncryptedKeyText)
		if type(EncryptedKeyText) ~= "string" or #EncryptedKeyText > 4096
			or #EncryptedKeyText % 2 ~= 0 or EncryptedKeyText:find("[^%x]")
		then
			return nil
		end

		local DecodedBytes = {}
		for CharacterIndex = 1, #EncryptedKeyText, 2 do
			local ByteIndex = (CharacterIndex + 1) / 2
			local SecretByteIndex = (ByteIndex - 1) % #KeyStorageEncryptionSecret + 1
			DecodedBytes[ByteIndex] = string.char(TransformKeyStorageByte(
				tonumber(EncryptedKeyText:sub(CharacterIndex, CharacterIndex + 1), 16),
				string.byte(KeyStorageEncryptionSecret, SecretByteIndex)
			))
		end

		return table.concat(DecodedBytes):match("^ContactKeyV1:(.+)$")
	end

	local ScriptKeyText = type(script_key) == "string" and script_key or ""
	if ScriptKeyText == "" and type(getgenv) == "function" then
		local EnvironmentReadSucceeded, ExecutorEnvironment = pcall(getgenv)
		if EnvironmentReadSucceeded and type(ExecutorEnvironment) == "table"
			and type(ExecutorEnvironment.script_key) == "string"
		then
			ScriptKeyText = ExecutorEnvironment.script_key
		end
	end
	ScriptKeyText = ScriptKeyText:match("^%s*(.-)%s*$")

	local KeyStorageReadMessage
	if ScriptKeyText == "" and type(readfile) == "function" then
		local SavedKeyReadSucceeded, SavedKeyText = pcall(readfile, SavedKeyFilePath)
		if SavedKeyReadSucceeded then
			local DecryptedScriptKey = DecryptStoredKey(SavedKeyText)
			if DecryptedScriptKey then
				ScriptKeyText = DecryptedScriptKey:match("^%s*(.-)%s*$")
			else
				KeyStorageReadMessage = "The saved key file is damaged. Enter your key again."
			end
		end
	end

	local ScriptKeyIsValid = false
	local KeyVerificationMessage = KeyStorageReadMessage
	if ScriptKeyText ~= "" then
		ScriptKeyIsValid, KeyVerificationMessage = ValidateScriptKey(ScriptKeyText)
	end

	if not ScriptKeyIsValid then
		local InterfaceLibrary = LoadRemoteModule(
			"https://raw.githubusercontent.com/contact-here/Contact/refs/heads/main/Library.lua"
		)
		if type(InterfaceLibrary) ~= "table" then
			ShowLoaderNotification("Could not load the key interface. Check your connection and retry.")
			return
		end

		local KeyPromptSucceeded, AcceptedScriptKey, KeyPromptFailureMessage = pcall(InterfaceLibrary.PromptKey, InterfaceLibrary, {
			ValidateScriptKey = ValidateScriptKey,
			InitialStatusMessage = KeyVerificationMessage,
			KeyProviders = {
				{
					DisplayName = "Work.ink",
					UniformResourceLocator = "https://ads.luarmor.net/get_key?for=Contact-lrOhEEUAtinP",
				},
				{
					DisplayName = "Linkvertise",
					UniformResourceLocator = "https://ads.luarmor.net/get_key?for=Contact-YfrTPtrjfoJO",
				},
				{
					DisplayName = "Lootlabs",
					UniformResourceLocator = "https://ads.luarmor.net/get_key?for=Contact-FdofVyJivbDh",
				},
			},
		})

		pcall(InterfaceLibrary.Destroy, InterfaceLibrary)
		if not KeyPromptSucceeded then
			ShowLoaderNotification("The key interface could not start on this executor. Update it and retry.")
			return
		end
		if KeyPromptFailureMessage then
			ShowLoaderNotification(KeyPromptFailureMessage)
		end
		if type(AcceptedScriptKey) ~= "string" or AcceptedScriptKey == "" then
			return
		end

		ScriptKeyText = AcceptedScriptKey
	end

	-- Luarmor requires this exact global name before its loader executes.
	script_key = ScriptKeyText
	if type(getgenv) == "function" then
		local EnvironmentReadSucceeded, ExecutorEnvironment = pcall(getgenv)
		if EnvironmentReadSucceeded and type(ExecutorEnvironment) == "table" then
			ExecutorEnvironment.script_key = ScriptKeyText
		end
	end

	if type(writefile) == "function" then
		local KeyFolderAvailable = false
		if type(isfolder) == "function" then
			local FolderCheckSucceeded, FolderExists = pcall(isfolder, SavedKeyFolderPath)
			KeyFolderAvailable = FolderCheckSucceeded and FolderExists == true
		end
		if not KeyFolderAvailable and type(makefolder) == "function" then
			pcall(makefolder, SavedKeyFolderPath)
		end

		local KeyWriteSucceeded = pcall(writefile, SavedKeyFilePath, EncryptStoredKey(ScriptKeyText))
		if not KeyWriteSucceeded then
			ShowLoaderNotification("Key accepted, but could not be saved. You may need to enter it next time.")
		end
	end
end
local ScriptUniformResourceLocator = string.format(
	"https://api.luarmor.net/files/v4/loaders/%s.lua",
	MatchingScriptConfiguration.ScriptIdentifier
)
local ScriptSource = FetchLink(ScriptUniformResourceLocator)
if type(ScriptSource) ~= "string" or ScriptSource == "" or type(loadstring) ~= "function" then
	ShowLoaderNotification("Could not download the script, or this executor cannot run it.")
	return
end

-- Compilation and execution are isolated independently. This prevents a bad
-- response or a runtime error inside one routed script from breaking the loader
-- itself or accidentally falling through to another configuration entry.
local ScriptCompilationSucceeded, CompiledScript = pcall(loadstring, ScriptSource)
if not ScriptCompilationSucceeded or type(CompiledScript) ~= "function" then
	ShowLoaderNotification("The script could not be prepared. Please retry later.")
	return
end

local ScriptExecutionSucceeded, ScriptExecutionResult = pcall(CompiledScript)
if not ScriptExecutionSucceeded then
	ShowLoaderNotification("The script could not start. Please retry or contact support.")
	return
end
