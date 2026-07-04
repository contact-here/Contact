-- Executor compatibility helpers are declared up front so later code can use
-- stable names without caring which exploit runtime provided the original
-- application programming interface.
local CloneFunction, CloneReference, NewCClosure, SetClipboard, GetClipboard

-- Stores the last copied value as a local fallback for runtimes that cannot
-- read the system clipboard back after writing to it.
local LastCopiedText = ""

do
	-- Prefer native clonefunc/clonefunction only when debug.info confirms that
	-- the implementation is C-backed. Lua replacements are treated as unsafe
	-- wrappers and intentionally ignored.
	local RawCloneFunction = clonefunc or clonefunction or clone_function
	local CloneIsNative = false
	if RawCloneFunction then
		local Success, Source = pcall(debug.info, RawCloneFunction, "s")
		if Success and Source == "[C]" then
			CloneIsNative = true
		end
	end

	if RawCloneFunction and CloneIsNative then
		CloneFunction = RawCloneFunction
	else
		-- Identity fallback keeps call sites simple when no native clone exists.
		CloneFunction = function(TargetFunction)
			return TargetFunction
		end
	end

	-- cloneref prevents some environments from returning hooked Instance
	-- references. The identity fallback is still valid in standard Luau.
	local RawCloneReference = cloneref or clone_ref or clonereference
	local CloneReferenceIsNative = false
	if RawCloneReference then
		local Success, Source = pcall(debug.info, RawCloneReference, "s")
		if Success and Source == "[C]" then
			CloneReferenceIsNative = true
		end
	end

	if RawCloneReference and CloneReferenceIsNative then
		CloneReference = RawCloneReference
	else
		-- Identity fallback lets the library run outside executor-specific APIs.
		CloneReference = function(TargetReference)
			return TargetReference
		end
	end

	-- newcclosure is useful for callbacks that should look native to hooks, but
	-- a plain Lua closure is enough when the runtime does not expose it.
	local RawNewCClosure = newcclosure
	local NewCClosureIsNative = false
	if RawNewCClosure then
		local Success, Source = pcall(debug.info, RawNewCClosure, "s")
		if Success and Source == "[C]" then
			NewCClosureIsNative = true
		end
	end

	if RawNewCClosure and NewCClosureIsNative then
		NewCClosure = RawNewCClosure
	else
		-- Keep the same call signature whether or not newcclosure exists.
		NewCClosure = function(TargetFunction)
			return TargetFunction
		end
	end

	-- Clipboard application programming interfaces have several names across
	-- executors. The wrapper validates the input and records the text locally
	-- before attempting the native call.
	local RawSetClipboard = setclipboard or toclipboard or set_clipboard

	SetClipboard = RawSetClipboard and function(Text)
		-- Non-string clipboard writes are ignored to avoid executor-specific
		-- coercion surprises.
		if typeof(Text) ~= "string" then
			return
		end

		LastCopiedText = Text
		local Success, ClonedText = pcall(RawSetClipboard, Text)

		if Success then
			return ClonedText
		end

		return Text
	end or function(Text)
		-- Fallback mode cannot touch the OS clipboard, but preserving the text
		-- still makes copy and read flows deterministic inside the interface.
		LastCopiedText = Text
		return Text
	end

	-- Reading the clipboard is optional; if the runtime cannot provide it, the
	-- last text copied through this library is returned instead.
	local RawGetClipboard = getclipboard or get_clipboard

	GetClipboard = RawGetClipboard and function()
		local Success, ClipboardText = pcall(RawGetClipboard)

		if Success and ClipboardText and #ClipboardText > 0 then
			return ClipboardText
		end

		return LastCopiedText
	end or function()
		return LastCopiedText
	end
end

local UserInputService, RunService, ContextActionService, Workspace
local Drawing = Drawing
local DataModel = CloneReference(game)
local GetService = CloneFunction(DataModel.GetService)

do
	-- Cache services through cloned methods/references so the rest of the
	-- library avoids repeated service lookups and reduces exposure to hooks.
	UserInputService     = CloneReference(GetService(DataModel, "UserInputService"))
	RunService           = CloneReference(GetService(DataModel, "RunService"))
	ContextActionService = CloneReference(GetService(DataModel, "ContextActionService"))
	Workspace            = CloneReference(GetService(DataModel, "Workspace"))
end

local GetMouseLocation, IsMouseButtonPressed, IsKeyDown
local GetStringForKeyCode, GetKeysPressed, GetMouseButtonsPressed
local GetDeviceType
local HeartbeatSignalConnect
local BindCoreActionAtPriority, UnbindCoreAction
local InputBeganSignalConnect, InputChangedSignalConnect, InputEndedSignalConnect
local WindowFocusReleasedConnect, WindowFocusedConnect

do
	-- Method references are copied once and called with explicit self later.
	-- This keeps hot input/render paths shorter and more predictable.
	GetMouseLocation     = CloneFunction(UserInputService.GetMouseLocation)
	IsMouseButtonPressed = CloneFunction(UserInputService.IsMouseButtonPressed)
	IsKeyDown            = CloneFunction(UserInputService.IsKeyDown)
	GetStringForKeyCode  = typeof(UserInputService.GetStringForKeyCode) == "function"
		and CloneFunction(UserInputService.GetStringForKeyCode)
		or function() return "" end

	GetKeysPressed           = typeof(UserInputService.GetKeysPressed) == "function"
		and CloneFunction(UserInputService.GetKeysPressed)
		or function() return {} end

	GetMouseButtonsPressed   = typeof(UserInputService.GetMouseButtonsPressed) == "function"
		and CloneFunction(UserInputService.GetMouseButtonsPressed)
		or function() return {} end
	GetDeviceType            = typeof(UserInputService.GetDeviceType) == "function"
		and CloneFunction(UserInputService.GetDeviceType)
		or function() return "Unknown" end

	HeartbeatSignalConnect = CloneFunction(RunService.Heartbeat.Connect)

	BindCoreActionAtPriority = CloneFunction(ContextActionService.BindCoreActionAtPriority)
	UnbindCoreAction         = CloneFunction(ContextActionService.UnbindCoreAction)

	InputBeganSignalConnect   = CloneFunction(UserInputService.InputBegan.Connect)
	InputChangedSignalConnect = CloneFunction(UserInputService.InputChanged.Connect)
	InputEndedSignalConnect   = CloneFunction(UserInputService.InputEnded.Connect)

	WindowFocusReleasedConnect = CloneFunction(UserInputService.WindowFocusReleased.Connect)
	WindowFocusedConnect       = CloneFunction(UserInputService.WindowFocused.Connect)
end

local SetRenderProperty, GetRenderProperty, IsRenderObject, ClearDrawCache

do
	-- Some Drawing implementations expose setrenderproperty/getrenderproperty;
	-- others are simple Lua tables. These wrappers normalize both models.
	local RawSetRenderProperty = typeof(setrenderproperty) == "function"
		and CloneFunction(setrenderproperty)

	SetRenderProperty = function(TargetObject, PropertyName, PropertyValue)
		-- Native property writes are protected because Drawing objects may be
		-- invalidated asynchronously by the host environment.
		if RawSetRenderProperty then
			pcall(RawSetRenderProperty, TargetObject, PropertyName, PropertyValue)
		else
			local TargetType = type(TargetObject)
			if TargetType == "table" or TargetType == "userdata" then
				TargetObject[PropertyName] = PropertyValue
			end
		end
	end

	local RawGetRenderProperty = typeof(getrenderproperty) == "function"
		and CloneFunction(getrenderproperty)

	GetRenderProperty = function(TargetObject, PropertyName)
		-- Returning nil is safer than surfacing render-backend errors to callers.
		if RawGetRenderProperty then
			local Success, Value = pcall(RawGetRenderProperty, TargetObject, PropertyName)
			if Success then
				return Value
			end
		else
			local TargetType = type(TargetObject)
			if TargetType == "table" or TargetType == "userdata" then
				return TargetObject[PropertyName]
			end
		end
		return nil
	end

	-- Optional backend maintenance hooks. Missing support should never block
	-- User Interface rendering, so each one has a no operation fallback.
	IsRenderObject = typeof(isrenderobj) == "function"
		and CloneFunction(isrenderobj) or function()
		return false
	end

	ClearDrawCache = typeof(cleardrawcache) == "function"
		and CloneFunction(cleardrawcache) or function() end
end

local SelectedBackend = 0

local UseImmediateMode        = false
local DrawingBackendAvailable = false

local DrawingIsNative = false

-- Native Drawing.new is preferred. When it is absent or Lua-backed, the library
-- attempts to load a replacement Drawing implementation before falling back.
if typeof(Drawing) == "table" and typeof(Drawing.new) == "function" then
	local NativeCheckSuccess, NativeCheckSource = pcall(debug.info, Drawing.new, "s")
	if NativeCheckSuccess and NativeCheckSource == "[C]" then
		DrawingIsNative = true
	end
end

if not DrawingIsNative then
	-- Placeholder link is intentionally isolated here so a real custom backend
	-- can be dropped in without changing rendering code below.
	local CustomDrawingLibraryLink = "https://raw.githubusercontent.com/placeholder-link-here/Drawing.lua"
	local RawHttpGet = CloneFunction(DataModel.HttpGet)
	local RawRequestFunction = request or http_request or (syn and syn.request)
	local FetchedContent

	if RawRequestFunction then
		-- request/http_request usually provides status codes and response bodies.
		local RequestSuccess, RequestResult = pcall(RawRequestFunction, { Url = CustomDrawingLibraryLink, Method = "GET" })
		if RequestSuccess and RequestResult and (RequestResult.StatusCode == 200 or RequestResult.Status == 200) then
			FetchedContent = RequestResult.Body
		end
	end

	if not FetchedContent and RawHttpGet then
		-- HttpGet fallback keeps compatibility with older executors.
		local HttpGetSuccess, HttpGetResult = pcall(RawHttpGet, DataModel, CustomDrawingLibraryLink)
		if HttpGetSuccess then
			FetchedContent = HttpGetResult
		end
	end

	if FetchedContent then
		-- Loaded code must return a Drawing-like table before it replaces the
		-- current backend reference.
		local LoadedFunction = loadstring(FetchedContent)
		if LoadedFunction then
			local ExecutionSuccess, ExecutionResult = pcall(LoadedFunction)
			if ExecutionSuccess and typeof(ExecutionResult) == "table" and typeof(ExecutionResult.new) == "function" then
				Drawing = ExecutionResult

				SetRenderProperty = ExecutionResult.SetRenderProperty
				GetRenderProperty = ExecutionResult.GetRenderProperty
				IsRenderObject    = ExecutionResult.IsRenderObject
				ClearDrawCache    = ExecutionResult.ClearDrawingCache or ExecutionResult.ClearDrawCache
			end
		end
	end
end

local DrawingImmediateLine            = nil
local DrawingImmediateCircle          = nil
local DrawingImmediateFilledCircle    = nil
local DrawingImmediateTriangle        = nil
local DrawingImmediateFilledTriangle  = nil
local DrawingImmediateRectangle       = nil
local DrawingImmediateFilledRectangle = nil
local DrawingImmediateText            = nil
local DrawingImmediateGetPaint        = nil

if (SelectedBackend == 0 or SelectedBackend == 1) and typeof(DrawingImmediate) == "table" then
	DrawingImmediateLine            = typeof(DrawingImmediate.Line)            == "function" and CloneFunction(DrawingImmediate.Line)
	DrawingImmediateCircle          = typeof(DrawingImmediate.Circle)          == "function" and CloneFunction(DrawingImmediate.Circle)
	DrawingImmediateFilledCircle    = typeof(DrawingImmediate.FilledCircle)    == "function" and CloneFunction(DrawingImmediate.FilledCircle)
	DrawingImmediateTriangle        = typeof(DrawingImmediate.Triangle)        == "function" and CloneFunction(DrawingImmediate.Triangle)
	DrawingImmediateFilledTriangle  = typeof(DrawingImmediate.FilledTriangle)  == "function" and CloneFunction(DrawingImmediate.FilledTriangle)
	DrawingImmediateRectangle       = typeof(DrawingImmediate.Rectangle)       == "function" and CloneFunction(DrawingImmediate.Rectangle)
	DrawingImmediateFilledRectangle = typeof(DrawingImmediate.FilledRectangle) == "function" and CloneFunction(DrawingImmediate.FilledRectangle)
	DrawingImmediateText            = typeof(DrawingImmediate.Text)            == "function" and CloneFunction(DrawingImmediate.Text)
	DrawingImmediateGetPaint        = typeof(DrawingImmediate.GetPaint)        == "function" and CloneFunction(DrawingImmediate.GetPaint)

	if DrawingImmediateLine then
		UseImmediateMode        = true
		DrawingBackendAvailable = true
	end
end

if not DrawingBackendAvailable then
	if typeof(Drawing) == "table" and typeof(Drawing.new) == "function" then
		UseImmediateMode        = false
		DrawingBackendAvailable = true
	end
end


-- Linear interpolation helper used by hover, focus, and active animations.
local function LerpValue(StartValue, EndValue, Factor)
	return StartValue + (EndValue - StartValue) * Factor
end

-- Moves an animation factor toward either zero or one at a fixed speed. The
-- exponential step makes transitions frame-rate independent.
local function UpdateAnimationFactor(CurrentFactor, TargetState, DeltaTime, Speed)
	Speed = Speed or 12
	local TargetFactor = TargetState and 1 or 0
	if CurrentFactor == TargetFactor then
		return CurrentFactor
	end
	local Difference = TargetFactor - CurrentFactor
	local Step = Difference * (1 - math.exp(-Speed * DeltaTime))
	if math.abs(Step) < 0.001 then
		return TargetFactor
	end
	return CurrentFactor + Step
end

-- Rectangle hit testing for mouse input, dropdown items, scrollbars, and popup
-- controls. Inclusive edges keep one-pixel borders clickable.
local function IsPointInsideRectangle(TestPoint, RectangleOrigin, RectangleSize)
	return TestPoint.X >= RectangleOrigin.X
		and TestPoint.X <= RectangleOrigin.X + RectangleSize.X
		and TestPoint.Y >= RectangleOrigin.Y
		and TestPoint.Y <= RectangleOrigin.Y + RectangleSize.Y
end

local function InvokeCallback(CallbackFunction, ...)
	-- User callbacks should never be able to tear down the renderer or input
	-- loop. A single protected invocation helper keeps callback isolation
	-- consistent across labels, buttons, toggles, sliders, dropdowns, and color
	-- pickers, and gives future diagnostics one central hook point.
	if typeof(CallbackFunction) ~= "function" then
		return false
	end

	return pcall(CallbackFunction, ...)
end

-- Generates short internal identifiers for bookkeeping where a human-readable
-- name is unnecessary.
local function RandomString(Length)
	local Characters = "abcdefghijklmnopqrstuvwxyz0123456789"
	local Result = {}

	for Index = 1, Length do
		local RandomIndex = math.random(1, #Characters)
		Result[Index] = string.sub(Characters, RandomIndex, RandomIndex)
	end

	return table.concat(Result)
end

-- Lightweight word wrapping for Drawing text. Drawing has no automatic layout
-- boxes, so line length is estimated from font size and theme character ratio.
local function WrapText(Text, MaxPixelWidth, FontSize)
	local CharWidth = FontSize * ((Theme and Theme.FontCharWidthRatio or 0.52) * 1.15)
	local MaxChars  = math.max(1, math.floor(MaxPixelWidth / CharWidth))
	local Lines       = {}
	local CurrentLine = ""

	for Word in Text:gmatch("%S+") do
		if #Word > MaxChars then
			if CurrentLine ~= "" then
				table.insert(Lines, CurrentLine)
				CurrentLine = ""
			end

			local Position = 1

			while Position <= #Word do
				local Chunk = string.sub(Word, Position, Position + MaxChars - 1)

				if Position + MaxChars <= #Word then
					table.insert(Lines, Chunk)
				else
					CurrentLine = Chunk
				end

				Position = Position + MaxChars
			end
		else
			local TestLine = CurrentLine == "" and Word or string.format("%s %s", CurrentLine, Word)

			if #TestLine <= MaxChars then
				CurrentLine = TestLine
			else
				if CurrentLine ~= "" then
					table.insert(Lines, CurrentLine)
				end
				CurrentLine = Word
			end
		end
	end

	if CurrentLine ~= "" then
		table.insert(Lines, CurrentLine)
	end

	if #Lines == 0 then
		table.insert(Lines, "")
	end

	return Lines
end

-- Visual design tokens. Color and size values are centralized so the launcher
-- can expose them through the theme editor without touching rendering logic.
local Theme = {

	-- Deep neutral base with layered surface colors. The interface uses calm
	-- graphite, teal, and warm text instead of the flat neon look common in
	-- throwaway script panels.
	WindowBackground       = Color3.fromRGB(9, 12, 16),
	WindowSurfaceHighlight = Color3.fromRGB(18, 24, 30),
	WindowSurfaceShade     = Color3.fromRGB(5, 7, 10),
	WindowBorder           = Color3.fromRGB(52, 64, 76),
	WindowBorderHover      = Color3.fromRGB(112, 158, 176),

	-- The title bar gets a cooler tint than the body to make dragging and
	-- window ownership visually obvious.
	TitleBarBackground     = Color3.fromRGB(12, 18, 23),
	TitleBarBackgroundHover= Color3.fromRGB(19, 29, 36),
	TitleBarHighlight      = Color3.fromRGB(31, 45, 54),
	TitleBarAccentWash     = Color3.fromRGB(14, 42, 46),
	TitleBarSeparator      = Color3.fromRGB(98, 211, 190),
	TitleBarText           = Color3.fromRGB(239, 245, 242),
	TitleBarTextHover      = Color3.fromRGB(255, 255, 255),

	-- Sections are slightly warmer than the window background, giving stacked
	-- groups enough depth without relying on heavy borders.
	SectionBodyBackground  = Color3.fromRGB(12, 15, 19),
	SectionBackground      = Color3.fromRGB(18, 23, 28),
	SectionBackgroundHover = Color3.fromRGB(27, 35, 42),
	SectionText            = Color3.fromRGB(143, 224, 207),
	SectionTextHover       = Color3.fromRGB(214, 245, 236),

	LabelText      = Color3.fromRGB(202, 210, 214),
	LabelTextHover = Color3.fromRGB(241, 247, 245),

	ButtonBackground      = Color3.fromRGB(22, 29, 35),
	ButtonBackgroundHover = Color3.fromRGB(33, 45, 53),
	ButtonText            = Color3.fromRGB(236, 242, 239),
	ButtonBorder          = Color3.fromRGB(65, 80, 88),
	TabBackground         = Color3.fromRGB(16, 22, 27),
	TabBackgroundHover    = Color3.fromRGB(25, 35, 42),
	TabBackgroundActive   = Color3.fromRGB(31, 50, 54),
	ToggleInactive        = Color3.fromRGB(67, 73, 79),
	ToggleActive          = Color3.fromRGB(98, 211, 145),

	TextBoxBackground      = Color3.fromRGB(13, 17, 21),
	TextBoxBackgroundHover = Color3.fromRGB(21, 27, 33),
	TextBoxBorder          = Color3.fromRGB(55, 70, 78),
	TextBoxBorderFocused   = Color3.fromRGB(98, 211, 190),
	TextBoxText            = Color3.fromRGB(226, 234, 232),
	TextBoxPlaceholder     = Color3.fromRGB(116, 128, 132),
	TextBoxCursor          = Color3.fromRGB(143, 224, 207),
	TextBoxSelection       = Color3.fromRGB(58, 120, 132),

	DropdownBackground    = Color3.fromRGB(16, 22, 27),
	DropdownHover         = Color3.fromRGB(25, 35, 42),
	DropdownItemBackground= Color3.fromRGB(13, 18, 23),
	DropdownItemHover     = Color3.fromRGB(35, 54, 60),
	DropdownText          = Color3.fromRGB(221, 231, 229),
	DropdownBorder        = Color3.fromRGB(57, 73, 82),
	DropdownBorderHover   = Color3.fromRGB(98, 211, 190),
	DropdownArrow         = Color3.fromRGB(154, 180, 181),

	SliderTrackBackground = Color3.fromRGB(18, 24, 29),
	SliderTrackFill       = Color3.fromRGB(98, 211, 190),
	SliderTrackFillHover  = Color3.fromRGB(136, 236, 214),
	SliderThumb           = Color3.fromRGB(234, 244, 240),
	SliderThumbHover      = Color3.fromRGB(255, 255, 255),
	SliderText            = Color3.fromRGB(221, 231, 229),
	SliderBorder          = Color3.fromRGB(55, 72, 80),

	ColorPickerBorder      = Color3.fromRGB(55, 72, 80),
	ColorPickerSelectedBorder = Color3.fromRGB(98, 211, 190),
	ColorPickerSwatchHover = Color3.fromRGB(214, 245, 236),

	ScrollbarBackground  = Color3.fromRGB(15, 20, 24),
	ScrollbarHandle      = Color3.fromRGB(75, 98, 105),
	ScrollbarHandleHover = Color3.fromRGB(115, 156, 164),

	NotificationBackground = Color3.fromRGB(12, 17, 21),
	NotificationBorder     = Color3.fromRGB(73, 112, 119),
	NotificationText       = Color3.fromRGB(237, 245, 242),
	NotificationAccent     = Color3.fromRGB(98, 211, 190),

	SaveButtonBackground = Color3.fromRGB(29, 96, 78),
	SaveButtonHover      = Color3.fromRGB(44, 132, 106),
	ExitButtonBackground = Color3.fromRGB(91, 59, 53),
	ExitButtonHover      = Color3.fromRGB(128, 77, 65),
	CloseButtonBackground = Color3.fromRGB(37, 42, 47),
	CloseButtonBorder     = Color3.fromRGB(74, 83, 90),
	CloseButtonHover      = Color3.fromRGB(197, 82, 88),

	SectionHover = Color3.fromRGB(27, 35, 42),

	-- Font metrics are intentionally ratio based. Roblox Drawing fonts do not
	-- provide full text measurement everywhere, so the library uses predictable
	-- estimates that scale together.
	Font            = 2,
	TitleFontSize   = 18,
	SectionFontSize = 15,
	ElementFontSize = 14,

	FontCharWidthRatio = 0.52,

	FontLineHeightRatio = 1.35,

	FontVerticalPaddingRatio = 0.5,

	FontHorizontalInsetRatio = 0.65,

	-- Layout tokens are kept together so adaptive scaling can resize the whole
	-- interface proportionally when the viewport changes.
	WindowWidth         = 620,
	TitleBarHeight      = 48,
	WindowVisibleHeight = 640,
	ElementHeight       = 34,
	ElementPadding      = 9,
	SectionPadding      = 14,
	InnerMargin         = 16,
	ScrollbarWidth      = 6,

	-- Color picker grid dimensions.
	ColorSwatchSize = 24,
	ColorSwatchGap  = 4,

	-- Notification stack dimensions and lifetime.
	NotificationWidth    = 280,
	NotificationHeight   = 38,
	NotificationDuration = 5,
	NotificationMargin   = 12,
}

-- The following helpers derive all text measurements from Theme ratios. That
-- keeps labels, text boxes, and wrapped paragraphs aligned after scaling.
local function FontLineHeight(FontSize)
	return math.ceil(FontSize * Theme.FontLineHeightRatio)
end

local function FontVerticalPadding(FontSize)
	return math.ceil(FontSize * Theme.FontVerticalPaddingRatio)
end

local function LabelVerticalPadding(FontSize)
	return math.max(2, math.floor(FontSize * 0.15))
end

local function FontHorizontalInset(FontSize)
	return math.ceil(FontSize * Theme.FontHorizontalInsetRatio)
end

local function TextBlockHeight(LineCount, FontSize)
	return FontLineHeight(FontSize) * LineCount + LabelVerticalPadding(FontSize) * 2
end

local function TextAvailableWidth(ElementWidth, FontSize)
	return ElementWidth - FontHorizontalInset(FontSize) * 2
end

local AsciiEllipsis = string.char(46, 46, 46)

local function TruncateTextWithAsciiEllipsis(DisplayText, MaximumCharacters)
	-- Drawing text has no reliable clipping primitive across every backend, so
	-- long strings are shortened before they reach the renderer. ASCII dots are
	-- used instead of a single Unicode ellipsis to keep the file and output
	-- friendly to executors with weaker string handling.
	if #DisplayText <= MaximumCharacters then
		return DisplayText
	end

	local PreservedCharacterCount = math.max(1, MaximumCharacters - #AsciiEllipsis)
	return string.format("%s%s", string.sub(DisplayText, 1, PreservedCharacterCount), AsciiEllipsis)
end

local function ClipEditableTextForWidth(DisplayText, MaximumCharacters, IsFocused)
	-- Focused text boxes keep the end of the string visible because that is
	-- where new input appears. Unfocused text uses a front slice with ellipsis
	-- so labels and saved values are easier to scan.
	if #DisplayText <= MaximumCharacters then
		return DisplayText
	end

	if IsFocused then
		return string.sub(DisplayText, #DisplayText - MaximumCharacters + 1)
	end

	return TruncateTextWithAsciiEllipsis(DisplayText, MaximumCharacters)
end

local function GetScrollbarScrollPercent(MousePositionY, TrackPositionY, TrackHeight, HandleHeight)
	local TravelDistance = TrackHeight - HandleHeight
	if TrackHeight <= 0 or TravelDistance <= 0 then
		return 0
	end

	local RelativeY = math.clamp(MousePositionY - TrackPositionY - (HandleHeight / 2), 0, TravelDistance)
	return RelativeY / TravelDistance
end

local function GetScrollbarClickPercent(MousePositionY, TrackPositionY, TrackHeight)
	if TrackHeight <= 0 then
		return 0
	end

	return math.clamp(MousePositionY - TrackPositionY, 0, TrackHeight) / TrackHeight
end

local function GetWindowContentViewportYRange(Window, WindowPositionY)
	-- The title bar belongs to the frame, and the tab bar belongs to navigation.
	-- Scrollable content starts below both, but it must stop at the bottom of
	-- the body. Keeping this calculation centralized prevents resized windows
	-- from letting sections draw below the visual frame.
	local ViewportStart = WindowPositionY + Theme.TitleBarHeight + (Window._TabBarHeight or 0)
	local ViewportEnd = WindowPositionY + Theme.TitleBarHeight + Window._VisibleHeight
	return ViewportStart, math.max(ViewportStart, ViewportEnd)
end

local function GetWindowContentViewportHeight(Window)
	local ViewportStart, ViewportEnd = GetWindowContentViewportYRange(Window, 0)
	return math.max(Theme.ElementHeight, ViewportEnd - ViewportStart)
end

local function GetMainScrollbarGeometry(Window, WindowPosition)
	if Window._MaxScroll <= 0 then
		return nil
	end

	local ViewportStart, ViewportEnd = GetWindowContentViewportYRange(Window, WindowPosition.Y)
	local ContentViewportHeight = math.max(0, ViewportEnd - ViewportStart)
	local TrackHeight = math.max(0, ContentViewportHeight - 4)
	if TrackHeight <= 0 then
		return nil
	end

	local CanvasHeight = math.max(Window._CanvasHeight or Window._VisibleHeight, 1)
	local RawHandleHeight = (ContentViewportHeight / CanvasHeight) * TrackHeight
	local HandleHeight = math.clamp(RawHandleHeight, math.min(20, TrackHeight), TrackHeight)
	local ScrollProgress = Window._MaxScroll > 0 and (Window._ScrollOffset / Window._MaxScroll) or 0
	local TrackPosition = Vector2.new(WindowPosition.X + Theme.WindowWidth - Theme.ScrollbarWidth - 2, ViewportStart + 2)
	local HandlePositionY = TrackPosition.Y + (TrackHeight - HandleHeight) * math.clamp(ScrollProgress, 0, 1)

	return {
		TrackPosition = TrackPosition,
		TrackSize = Vector2.new(Theme.ScrollbarWidth, TrackHeight),
		HitPosition = Vector2.new(TrackPosition.X - 2, TrackPosition.Y),
		HitSize = Vector2.new(Theme.ScrollbarWidth + 4, TrackHeight),
		HandlePosition = Vector2.new(TrackPosition.X, HandlePositionY),
		HandleSize = Vector2.new(Theme.ScrollbarWidth, HandleHeight),
		TrackHeight = TrackHeight,
		HandleHeight = HandleHeight,
	}
end

local function GetSectionScrollbarGeometry(Section, Window)
	if not Section._MaxHeight or Section._SectionMaxScroll <= 0 then
		return nil
	end

	local SectionAbsolutePosition = Window._Position + Vector2.new(Section._PositionX, Section._PositionY - Window._ScrollOffset)
	local VisibleSectionHeight = Section._ClippedHeight or Section._ContentHeight or 0
	local TrackHeight = math.max(0, VisibleSectionHeight - Theme.ElementHeight - 4)
	if TrackHeight <= 0 then
		return nil
	end

	local CanvasHeight = math.max((Section._FullContentHeight or Section._ContentHeight or 0) - Theme.ElementHeight, 1)
	local VisibleCanvasHeight = math.max(VisibleSectionHeight - Theme.ElementHeight, 1)
	local RawHandleHeight = (VisibleCanvasHeight / CanvasHeight) * TrackHeight
	local HandleHeight = math.clamp(RawHandleHeight, math.min(12, TrackHeight), TrackHeight)
	local ScrollProgress = Section._SectionMaxScroll > 0 and (Section._SectionScrollOffset / Section._SectionMaxScroll) or 0
	local TrackPosition = Vector2.new(SectionAbsolutePosition.X + Section._Width - Theme.ScrollbarWidth - 2, SectionAbsolutePosition.Y + Theme.ElementHeight + 2)
	local HandlePositionY = TrackPosition.Y + (TrackHeight - HandleHeight) * math.clamp(ScrollProgress, 0, 1)

	return {
		TrackPosition = TrackPosition,
		TrackSize = Vector2.new(Theme.ScrollbarWidth, TrackHeight),
		HitPosition = Vector2.new(TrackPosition.X - 2, TrackPosition.Y),
		HitSize = Vector2.new(Theme.ScrollbarWidth + 4, TrackHeight),
		HandlePosition = Vector2.new(TrackPosition.X, HandlePositionY),
		HandleSize = Vector2.new(Theme.ScrollbarWidth, HandleHeight),
		TrackHeight = TrackHeight,
		HandleHeight = HandleHeight,
	}
end

local function GetCurrentCamera()
	local Camera = Workspace and Workspace.CurrentCamera
	return Camera and CloneReference(Camera) or nil
end

local function GetViewportSize()
	local Camera = GetCurrentCamera()
	return Camera and Camera.ViewportSize or Vector2.new(1920, 1080)
end

local function GetNotificationStackPosition(TargetPosition, StackIndex)
	local ViewportSize = GetViewportSize()
	local StackOffsetY = StackIndex * (Theme.NotificationHeight + Theme.NotificationMargin)
	local RightSideX = TargetPosition.X + Theme.WindowWidth + Theme.NotificationMargin
	local LeftSideX = TargetPosition.X - Theme.NotificationWidth - Theme.NotificationMargin
	local PositionX = RightSideX

	if RightSideX + Theme.NotificationWidth > ViewportSize.X - Theme.NotificationMargin then
		PositionX = math.max(Theme.NotificationMargin, LeftSideX)
	end

	local MaximumY = math.max(Theme.NotificationMargin, ViewportSize.Y - Theme.NotificationHeight - Theme.NotificationMargin)
	local PositionY = math.clamp(TargetPosition.Y + StackOffsetY, Theme.NotificationMargin, MaximumY)
	return Vector2.new(PositionX, PositionY)
end

-- Clip a rectangle to the visible vertical viewport. A nil result means the
-- rectangle is fully outside the viewport and should not be drawn.
local function ClipRectangleToYRange(Position, Size, MinY, MaxY)
	local Y1 = Position.Y
	local Y2 = Y1 + Size.Y
	local NewY1 = math.max(Y1, MinY)
	local NewY2 = math.min(Y2, MaxY)

	if NewY1 >= NewY2 then
		return nil, nil
	end

	return Vector2.new(Position.X, NewY1), Vector2.new(Size.X, NewY2 - NewY1)
end

-- Clip a vertical line to the visible vertical range while preserving its
-- horizontal position.
local function ClipVerticalLineToYRange(From, To, MinY, MaxY)
	local Y1 = math.min(From.Y, To.Y)
	local Y2 = math.max(From.Y, To.Y)
	local NewY1 = math.max(Y1, MinY)
	local NewY2 = math.min(Y2, MaxY)

	if NewY1 >= NewY2 then
		return nil, nil
	end

	return Vector2.new(From.X, NewY1), Vector2.new(To.X, NewY2)
end

-- Clip a horizontal line to the visible vertical range. Horizontal lines do not
-- need x adjustment, only y visibility checks.
local function ClipHorizontalLineToYRange(From, To, MinY, MaxY)
	local Y = From.Y
	if Y >= MinY and Y <= MaxY then
		return From, To
	else
		return nil, nil
	end
end

-- Sections can scroll independently inside the main window. This helper returns
-- the allowed y range for either the window viewport or a clipped section body.
local function GetSectionAllowedYRange(Section, Window, WindowPositionY)
	local ViewportStart, ViewportEnd = GetWindowContentViewportYRange(Window, WindowPositionY)
	local AllowedMinY = ViewportStart
	local AllowedMaxY = ViewportEnd

	if Section._MaxHeight then
		local ClippedHeight = Section._ClippedHeight or Section._ContentHeight or 0
		if ClippedHeight > 0 then
			local SectionAbsoluteTop = WindowPositionY + Section._PositionY - Window._ScrollOffset + Theme.ElementHeight + Theme.ElementPadding
			local SectionAbsoluteBottom = WindowPositionY + Section._PositionY - Window._ScrollOffset + ClippedHeight
			AllowedMinY = math.max(AllowedMinY, SectionAbsoluteTop)
			AllowedMaxY = math.min(AllowedMaxY, SectionAbsoluteBottom)
		end
	end

	return AllowedMinY, AllowedMaxY
end

-- Visibility check used before drawing and hit testing elements. It handles the
-- main window viewport and the optional inner scroll viewport of a section.
local function IsElementVisibleInViewport(ElementAbsolutePositionY, ElementHeight, Section, Window, WindowPositionY)
	if not Window._Visible then
		return false
	end

	local ViewportStart, ViewportEnd = GetWindowContentViewportYRange(Window, WindowPositionY)
	local InViewport = (ElementAbsolutePositionY + ElementHeight > ViewportStart) and (ElementAbsolutePositionY < ViewportEnd)
	if not InViewport then
		return false
	end

	if Section._MaxHeight then
		local ClippedHeight = Section._ClippedHeight or Section._ContentHeight or 0
		if ClippedHeight > 0 then
			local SectionAbsoluteTop = WindowPositionY + Section._PositionY - Window._ScrollOffset + Theme.ElementHeight + Theme.ElementPadding
			local SectionAbsoluteBottom = WindowPositionY + Section._PositionY - Window._ScrollOffset + ClippedHeight
			return (ElementAbsolutePositionY + ElementHeight > SectionAbsoluteTop) and (ElementAbsolutePositionY < SectionAbsoluteBottom)
		end
	end

	return true
end

-- Apply a batch of Drawing properties through the backend abstraction. Central
-- batching makes retained-mode object updates easier to read and safer.
local function ApplyDrawingProperties(DrawingObject, Properties)
	if not DrawingObject then 
		return 
	end

	for PropertyName, PropertyValue in pairs(Properties) do
		SetRenderProperty(DrawingObject, PropertyName, PropertyValue)
	end
end

-- Destroy every Drawing object stored in a tracking table, then clear the table
-- so later cleanup calls are harmless.
local function DestroyTrackedDrawingTable(DrawingTable)
	for ObjectIndex = #DrawingTable, 1, -1 do
		local DrawingObject = DrawingTable[ObjectIndex]
		if DrawingObject then
			pcall(DrawingObject.Destroy, DrawingObject)
		end
		DrawingTable[ObjectIndex] = nil
	end
end

-- Remove one Drawing object from a tracking list after it has been destroyed.
local function RemoveTrackedDrawing(TrackedDrawingsTable, DrawingObject)
	if not DrawingObject then 
		return 
	end

	for DrawingIndex = #TrackedDrawingsTable, 1, -1 do
		if TrackedDrawingsTable[DrawingIndex] == DrawingObject then
			table.remove(TrackedDrawingsTable, DrawingIndex)

			break
		end
	end
end

-- Destroy a single Drawing object and unregister it from its owner list.
local function DestroyDrawing(DrawingObject, TrackedDrawingsTable)
	if DrawingObject then
		if TrackedDrawingsTable then
			RemoveTrackedDrawing(TrackedDrawingsTable, DrawingObject)
		end
		pcall(DrawingObject.Destroy, DrawingObject)
	end
end

-- Factory for retained-mode Drawing objects. Each created object is tracked so
-- windows and notifications can destroy every render resource cleanly.
local function MakeDrawingFactory(TrackedDrawingsTable)
	local function CreateTrackedDrawingObject(ObjectType)
		-- Immediate mode draws directly every frame, so no persistent Drawing
		-- object should be created in that backend.
		if not DrawingBackendAvailable or UseImmediateMode then 
			return nil 
		end

		local DrawingObject = Drawing.new(ObjectType)
		table.insert(TrackedDrawingsTable, DrawingObject)

		return DrawingObject
	end

	local function CreateRectangleDrawing(FillColor, IsFilled, ZIndexValue, TransparencyValue)
		-- Square is the Drawing class used for filled and outlined rectangles.
		local RectangleObject = CreateTrackedDrawingObject("Square")
		ApplyDrawingProperties(RectangleObject, {
			Color        = FillColor,
			Filled       = IsFilled,
			Transparency = TransparencyValue or 0.95,
			ZIndex       = ZIndexValue or 1,
			Visible      = true,
		})
		if not IsFilled and RectangleObject then
			SetRenderProperty(RectangleObject, "Thickness", 1)
		end
		return RectangleObject
	end

	local function CreateTextDrawing(DisplayText, FontSizeValue, TextColor, ZIndexValue)
		-- Text defaults match the theme so callers only override the values that
		-- are specific to a control.
		local TextObject = CreateTrackedDrawingObject("Text")
		ApplyDrawingProperties(TextObject, {
			Text         = DisplayText,
			Size         = FontSizeValue or Theme.ElementFontSize,
			Color        = TextColor or Theme.LabelText,
			Font         = Theme.Font,
			ZIndex       = ZIndexValue or 10,
			Outline      = false,
			Transparency = 1,
			Visible      = true,
		})
		return TextObject
	end

	return CreateTrackedDrawingObject, CreateRectangleDrawing, CreateTextDrawing
end

-- Global notification drawings are tracked separately from window drawings so
-- they can survive or clean up independently.
local NotificationTrackedDrawings = {}
local CreateNotificationDrawingObject, CreateNotificationRectangleDrawing, CreateNotificationTextDrawing = MakeDrawingFactory(NotificationTrackedDrawings)

-- Built-in color palette for the color picker popup. The order starts with
-- grayscale, then saturated hues, then darker and softer variants.
local ColorPalette = {

	Color3.fromRGB(0, 0, 0),
	Color3.fromRGB(30, 30, 30),
	Color3.fromRGB(60, 60, 60),
	Color3.fromRGB(90, 90, 90),
	Color3.fromRGB(120, 120, 120),
	Color3.fromRGB(150, 150, 150),
	Color3.fromRGB(180, 180, 180),
	Color3.fromRGB(210, 210, 210),
	Color3.fromRGB(240, 240, 240),
	Color3.fromRGB(255, 255, 255),

	Color3.fromRGB(255, 0, 0),
	Color3.fromRGB(255, 127, 0),
	Color3.fromRGB(255, 255, 0),
	Color3.fromRGB(127, 255, 0),
	Color3.fromRGB(0, 255, 0),
	Color3.fromRGB(0, 255, 127),
	Color3.fromRGB(0, 255, 255),
	Color3.fromRGB(0, 127, 255),
	Color3.fromRGB(0, 0, 255),
	Color3.fromRGB(127, 0, 255),

	Color3.fromRGB(139, 0, 0),
	Color3.fromRGB(178, 34, 34),
	Color3.fromRGB(153, 76, 0),
	Color3.fromRGB(128, 128, 0),
	Color3.fromRGB(0, 100, 0),
	Color3.fromRGB(0, 128, 128),
	Color3.fromRGB(0, 0, 139),
	Color3.fromRGB(75, 0, 130),
	Color3.fromRGB(128, 0, 128),
	Color3.fromRGB(139, 69, 19),

	Color3.fromRGB(255, 182, 193),
	Color3.fromRGB(255, 218, 185),
	Color3.fromRGB(255, 255, 200),
	Color3.fromRGB(200, 255, 200),
	Color3.fromRGB(200, 255, 255),
	Color3.fromRGB(200, 200, 255),
	Color3.fromRGB(230, 200, 255),
	Color3.fromRGB(255, 200, 230),
	Color3.fromRGB(245, 222, 179),
	Color3.fromRGB(210, 180, 140),

	Color3.fromRGB(255, 0, 128),
	Color3.fromRGB(255, 65, 54),
	Color3.fromRGB(255, 165, 0),
	Color3.fromRGB(50, 205, 50),
	Color3.fromRGB(0, 206, 209),
	Color3.fromRGB(30, 144, 255),
	Color3.fromRGB(138, 43, 226),
	Color3.fromRGB(255, 20, 147),
	Color3.fromRGB(255, 215, 0),
	Color3.fromRGB(0, 250, 154),
}

local function SetDrawingObjectsVisibility(DrawingObjects, IsVisible)
	for DrawingObjectIndex, DrawingObject in ipairs(DrawingObjects) do
		if DrawingObject then
			SetRenderProperty(DrawingObject, "Visible", IsVisible)
		end
	end
end

local Library = {}

Library._Windows = {}

Library._ActiveSinks = {}
Library._ActiveSinkStates = {}
Library._InputBlockingRequests = {}

Library._Visible = true

Library.ToggleKey = Enum.KeyCode.RightControl

Library.Connections = {}

Library.Theme = Theme

local _CachedPreferredInput = nil

table.insert(Library.Connections, InputChangedSignalConnect(UserInputService.InputChanged, NewCClosure(function()
	local CurrentPreferredInput = UserInputService.PreferredInput
	if CurrentPreferredInput ~= _CachedPreferredInput then
		_CachedPreferredInput = CurrentPreferredInput
		if Library.OnInputTypeChanged then
			pcall(Library.OnInputTypeChanged, CurrentPreferredInput)
		end
	end
end)))

table.insert(Library.Connections, InputChangedSignalConnect(UserInputService.InputChanged, NewCClosure(function(Input)
	if not Library._Visible then 
		return 
	end

	if Input.UserInputType == Enum.UserInputType.MouseWheel then
		local CurrentMousePosition = GetMouseLocation(UserInputService)

		for Index, Window in ipairs(Library._Windows) do
			if Window._Visible and not Window._Destroyed then
				local TabBarPosition = Window._Position + Vector2.new(0, Theme.TitleBarHeight)
				local TabBarSize = Vector2.new(Theme.WindowWidth, Window._TabBarHeight)
				if Window._TabBarHeight > 0 and IsPointInsideRectangle(CurrentMousePosition, TabBarPosition, TabBarSize) then
					local TabCount = #Window._Pages
					local TabBarPadding = 10
					local TabGap = 6
					local TabWidth = math.max(92, (Theme.WindowWidth - (TabBarPadding * 2) - (TabGap * (math.min(TabCount, 5) - 1))) / math.min(TabCount, 5))
					local MaxTabScroll = math.max(0, (TabCount * (TabWidth + TabGap)) - TabGap - (Theme.WindowWidth - TabBarPadding * 2))
					local Delta = Input.Position.Z * 30
					Window._TabScrollOffset = math.clamp((Window._TabScrollOffset or 0) - Delta, 0, MaxTabScroll)
					Window:RecalculateLayout()
					break
				else
					local BodyPosition = Vector2.new(Window._Position.X, Window._Position.Y + Theme.TitleBarHeight)
					local BodySize = Vector2.new(Theme.WindowWidth, Window._VisibleHeight)

					if IsPointInsideRectangle(CurrentMousePosition, BodyPosition, BodySize) then
						local Delta = Input.Position.Z * 45
						local HandledBySection = false

						for SectionIndex, ScrollableSection in ipairs(Window:GetActiveSections()) do
							if ScrollableSection._MaxHeight and ScrollableSection._SectionMaxScroll > 0 then
								local SectionAbsolutePosition = Window._Position + Vector2.new(ScrollableSection._PositionX, ScrollableSection._PositionY - Window._ScrollOffset)
								local SectionVisibleSize = Vector2.new(ScrollableSection._Width, ScrollableSection._ClippedHeight or ScrollableSection._ContentHeight or 0)
								if IsPointInsideRectangle(CurrentMousePosition, SectionAbsolutePosition, SectionVisibleSize) then
									ScrollableSection._SectionScrollOffset = math.clamp(ScrollableSection._SectionScrollOffset - Delta, 0, ScrollableSection._SectionMaxScroll)
									Window:RecalculateLayout()
									HandledBySection = true
									break
								end
							end
						end

						if not HandledBySection then
							Window._ScrollOffset = math.clamp(Window._ScrollOffset - Delta, 0, Window._MaxScroll)
							Window:RecalculateLayout()
						end

						break
					end
				end
			end
		end
	end
end)))

table.insert(Library.Connections, InputBeganSignalConnect(UserInputService.InputBegan, NewCClosure(function(Input, Processed)
	if Input.KeyCode == Library.ToggleKey then
		Library._Visible = not Library._Visible

		for Index, ActiveWindow in ipairs(Library._Windows) do
			if not ActiveWindow._Destroyed then
				ActiveWindow:SetVisible(Library._Visible)
			end
		end

		return
	end

	if not Library._Visible then 
		return 
	end

	for Index, Window in ipairs(Library._Windows) do
		if Window._Visible and not Window._Destroyed then
			local FocusedBox = nil

			if Window._SearchActive and Window._SearchTextBox._IsFocused then
				FocusedBox = Window._SearchTextBox
			else
				for DiscardSectionIndex, Section in ipairs(Window:GetActiveSections()) do
					for DiscardElementIndex, Element in ipairs(Section._Elements) do
						if Element._Type == "TextBox" and Element._IsFocused then
							FocusedBox = Element
							
							break
						end
					end

					if FocusedBox then 
						break 
					end
				end
			end

			if FocusedBox then

				local function PerformTypingAction()
					if not FocusedBox._IsFocused or not Window._Visible or Window._Destroyed then 
						return false 
					end

					local HeldKeys = GetKeysPressed(UserInputService)
					local CtrlHeld = false
					local ShiftHeld = false

					for Index, HeldKey in ipairs(HeldKeys) do
						local CurrentKeyCode = HeldKey.KeyCode
						if CurrentKeyCode == Enum.KeyCode.LeftControl or CurrentKeyCode == Enum.KeyCode.RightControl then
							CtrlHeld = true
						end
						if CurrentKeyCode == Enum.KeyCode.LeftShift or CurrentKeyCode == Enum.KeyCode.RightShift then
							ShiftHeld = true
						end
					end

					if Input.KeyCode == Enum.KeyCode.Backspace then
						if FocusedBox._IsSelected then
							FocusedBox:SetValue("")
							FocusedBox._IsSelected = false
						else
							FocusedBox:SetValue(string.sub(FocusedBox._Value, 1, -2))
						end
						return true
					elseif Input.KeyCode == Enum.KeyCode.Delete then
						FocusedBox:SetValue("")
						FocusedBox._IsSelected = false
						return true
					elseif Input.KeyCode == Enum.KeyCode.Return or Input.KeyCode == Enum.KeyCode.Escape then
						FocusedBox._IsFocused = false
						FocusedBox._IsSelected = false
						FocusedBox._CursorVisible = false
						Window:SetInputBlocking("Typing", false)
						return false
					elseif Input.KeyCode == Enum.KeyCode.Space then
						if FocusedBox._IsSelected then
							FocusedBox:SetValue(" ")
							FocusedBox._IsSelected = false
						else
							FocusedBox:SetValue(string.format("%s ", FocusedBox._Value))
						end
						return true
					elseif CtrlHeld and Input.KeyCode == Enum.KeyCode.V then
						local ClipboardText = GetClipboard()

						if ClipboardText and #ClipboardText > 0 then
							if FocusedBox._IsSelected then
								FocusedBox:SetValue(ClipboardText)
								FocusedBox._IsSelected = false
							else
								FocusedBox:SetValue(string.format("%s%s", FocusedBox._Value, ClipboardText))
							end
						end
						return false
					elseif CtrlHeld and Input.KeyCode == Enum.KeyCode.C then
						SetClipboard(FocusedBox._Value)
						return false
					elseif CtrlHeld and Input.KeyCode == Enum.KeyCode.A then

						FocusedBox._IsSelected = true
						return false
					elseif not CtrlHeld then
						local Character = GetStringForKeyCode(UserInputService, Input.KeyCode)
						if Character and #Character == 1 then
							if ShiftHeld then
								local ShiftMap = {
									["1"] = "!", ["2"] = "@", ["3"] = "#", ["4"] = "$", ["5"] = "%",
									["6"] = "^", ["7"] = "&", ["8"] = "*", ["9"] = "(", ["0"] = ")",
									["-"] = "_", ["="] = "+", ["["] = "{", ["]"] = "}", ["\\"] = "|",
									[";"] = ":", ["'"] = "\"", [","] = "<", ["."] = ">", ["/"] = "?",
									["`"] = "~",
								}
								Character = ShiftMap[Character] or string.upper(Character)
							else
								Character = string.lower(Character)
							end

							if FocusedBox._IsSelected then
								FocusedBox:SetValue(Character)
								FocusedBox._IsSelected = false
							else
								FocusedBox:SetValue(string.format("%s%s", FocusedBox._Value, Character))
							end

							return true
						end
					end

					return false
				end

				if PerformTypingAction() then
					local StartTime = tick()
					local LastRepeat = tick()
					local RepeatDelay = 0.45
					local RepeatInterval = 0.04

					local RepeatConnection

					RepeatConnection = HeartbeatSignalConnect(RunService.Heartbeat, NewCClosure(function()
						if not FocusedBox._IsFocused or not IsKeyDown(UserInputService, Input.KeyCode) or not Library._Visible or not Window._Visible or Window._Destroyed then
							RepeatConnection:Disconnect()
							
							return
						end

						local Now = tick()
						if Now - StartTime > RepeatDelay then
							if Now - LastRepeat > RepeatInterval then
								PerformTypingAction()
								LastRepeat = Now
							end
						end
					end))
				end
				return
			end
		end
	end
end)))

Library.Fonts = (typeof(Drawing) == "table" and Drawing.Fonts) or {
	UI = 0,
	System = 1,
	Plex = 2,
	Monospace = 3,
}

Library.ActiveNotifications = {}

-- Destroy every connection, window, and global notification owned by the
-- library. This is the top-level cleanup entry point for the whole interface.
function Library:Destroy()
	for ConnectionIndex, Connection in ipairs(Library.Connections) do
		if Connection then
			pcall(Connection.Disconnect, Connection)
		end
	end
	Library.Connections = {}

	for WindowIndex = #Library._Windows, 1, -1 do
		local Window = Library._Windows[WindowIndex]
		if Window and not Window._Destroyed then
			pcall(Window.Destroy, Window)
		end
	end
	Library._Windows = {}
	Library._InputBlockingRequests = {}

	local SinkTypesToDisable = {}
	for Type in pairs(Library._ActiveSinks) do
		table.insert(SinkTypesToDisable, Type)
	end
	for DisableIndex, Type in ipairs(SinkTypesToDisable) do
		Library:SetInputBlocking(Type, false)
	end

	DestroyTrackedDrawingTable(NotificationTrackedDrawings)
end

-- Show a transient notification next to a window or at a fixed screen position.
-- Window-specific notifications move with the window's notification stack.
function Library:ShowNotification(NotificationText, WindowOrPosition)
	if not DrawingBackendAvailable then
		return
	end

	local TargetWindow = nil
	local TargetPosition = nil

	if typeof(WindowOrPosition) == "table" and WindowOrPosition._Position then
		TargetWindow = WindowOrPosition
		TargetPosition = WindowOrPosition._Position
	elseif typeof(WindowOrPosition) == "Vector2" then
		TargetPosition = WindowOrPosition
	else
		TargetPosition = Vector2.new(100, 100)
	end

	local ActiveNotificationsList = TargetWindow and TargetWindow._ActiveNotifications or Library.ActiveNotifications
	local NotificationPosition = GetNotificationStackPosition(TargetPosition, #ActiveNotificationsList)

	local NotificationEntry = {
		Text = NotificationText,
		Position = NotificationPosition,
		CreatedAt = tick(),
		Window = TargetWindow,
	}

	if not UseImmediateMode then
		-- Retained mode creates Drawing objects once and removes them after the
		-- notification duration expires.

		local NotificationBackground = CreateNotificationRectangleDrawing(Theme.NotificationBackground, true, 100, 0.95)
		ApplyDrawingProperties(NotificationBackground, {
			Position = NotificationPosition,
			Size = Vector2.new(Theme.NotificationWidth, Theme.NotificationHeight),
		})

		local NotificationBorder = CreateNotificationRectangleDrawing(Theme.NotificationBorder, false, 101, 0.8)
		ApplyDrawingProperties(NotificationBorder, {
			Position = NotificationPosition,
			Size = Vector2.new(Theme.NotificationWidth, Theme.NotificationHeight),
		})

		local NotificationAccentLine = CreateNotificationDrawingObject("Line")
		ApplyDrawingProperties(NotificationAccentLine, {
			From = Vector2.new(NotificationPosition.X + 3, NotificationPosition.Y + 4),
			To = Vector2.new(NotificationPosition.X + 3, NotificationPosition.Y + Theme.NotificationHeight - 4),
			Thickness = 2,
			Transparency = 1,
			Color = Theme.NotificationAccent,
			ZIndex = 103,
			Visible = true,
		})

		local NotificationTextLabel = CreateNotificationTextDrawing(
			NotificationText,
			Theme.ElementFontSize,
			Theme.NotificationText,
			102
		)
		ApplyDrawingProperties(NotificationTextLabel, {
			Position = Vector2.new(
				NotificationPosition.X + 12,
				NotificationPosition.Y + (Theme.NotificationHeight - Theme.ElementFontSize) / 2
			),
			Transparency = 0.95,
		})

		NotificationEntry.Background = NotificationBackground
		NotificationEntry.Border = NotificationBorder
		NotificationEntry.AccentLine = NotificationAccentLine
		NotificationEntry.TextLabel = NotificationTextLabel

		task.delay(Theme.NotificationDuration, function()
			DestroyDrawing(NotificationBackground, NotificationTrackedDrawings)
			DestroyDrawing(NotificationBorder, NotificationTrackedDrawings)
			DestroyDrawing(NotificationAccentLine, NotificationTrackedDrawings)
			DestroyDrawing(NotificationTextLabel, NotificationTrackedDrawings)
		end)
	end

	task.delay(Theme.NotificationDuration, function()
		-- Collapse the notification stack after this entry expires.
		for EntryIndex, Entry in ipairs(ActiveNotificationsList) do
			if Entry == NotificationEntry then
				table.remove(ActiveNotificationsList, EntryIndex)

				for RemainingIndex, RemainingEntry in ipairs(ActiveNotificationsList) do
					RemainingEntry.Position = GetNotificationStackPosition(TargetPosition, RemainingIndex - 1)
					
					if RemainingEntry.Background then
						SetRenderProperty(RemainingEntry.Background, "Position", RemainingEntry.Position)
					end

					if RemainingEntry.Border then
						SetRenderProperty(RemainingEntry.Border, "Position", RemainingEntry.Position)
					end

					if RemainingEntry.TextLabel then
						SetRenderProperty(RemainingEntry.TextLabel, "Position", Vector2.new(
							RemainingEntry.Position.X + 8,
							RemainingEntry.Position.Y + (Theme.NotificationHeight - Theme.ElementFontSize) / 2
						))
					end
				end

				break
			end
		end
	end)

	table.insert(ActiveNotificationsList, NotificationEntry)
end

-- Create a draggable window with pages, sections, elements, search, scrolling,
-- notifications, and adaptive viewport scaling.
function Library:CreateWindow(WindowConfig)
	WindowConfig = WindowConfig or {}
	WindowConfig.Title = WindowConfig.Title or "Window"
	WindowConfig.Position = WindowConfig.Position or Vector2.new(100, 100)

	local WindowTrackedDrawings = {}
	local GetTextBounds

	local DestroyAllTrackedDrawings = function()
		DestroyTrackedDrawingTable(WindowTrackedDrawings)
	end

	local CreateTrackedDrawingObject, CreateRectangleDrawing, CreateTextDrawing = MakeDrawingFactory(WindowTrackedDrawings)

	local DeviceType = GetDeviceType(UserInputService)
	local IsMobileDevice = (DeviceType == Enum.DeviceType.Phone)

	if IsMobileDevice then
		local MobileTheme = {}
		for Key, Value in pairs(Theme) do
			MobileTheme[Key] = Value
		end
		MobileTheme.WindowWidth = 340
		MobileTheme.ElementHeight = 36
		MobileTheme.TitleBarHeight = 40
		Theme = MobileTheme
		Library.Theme = Theme
	end

	if not Theme.Base then
		Theme.Base = {
			TitleFontSize = Theme.TitleFontSize,
			SectionFontSize = Theme.SectionFontSize,
			ElementFontSize = Theme.ElementFontSize,
			WindowWidth = Theme.WindowWidth,
			TitleBarHeight = Theme.TitleBarHeight,
			WindowVisibleHeight = Theme.WindowVisibleHeight,
			ElementHeight = Theme.ElementHeight,
			ElementPadding = Theme.ElementPadding,
			SectionPadding = Theme.SectionPadding,
			InnerMargin = Theme.InnerMargin,
			ScrollbarWidth = Theme.ScrollbarWidth,
			ColorSwatchSize = Theme.ColorSwatchSize,
			ColorSwatchGap = Theme.ColorSwatchGap,
		}
	end

	local Window = {}
	Window._Connections = {}
	Window._ActiveNotifications = {}

	Window._Position = WindowConfig.Position

	Window._Title = WindowConfig.Title

	Window._Sections = {}

	Window._TotalHeight = Theme.TitleBarHeight

	Window._Dragging = false
	Window._Resizing = false
	Window._TitleTextHovered = false
	Window._DragOffset = Vector2.new(0, 0)
	Window._ResizeStartMousePosition = Vector2.new(0, 0)
	Window._ResizeStartSize = Vector2.new(Theme.WindowWidth, Theme.WindowVisibleHeight)
	Window._ResizeGripRegion = {
		Position = Vector2.new(0, 0),
		Size = Vector2.new(20, 20)
	}
	Window._ResizeGripHovered = false

	Window._CloseButtonRegion = {
		Position = Vector2.new(0, 0),
		Size = Vector2.new(20, 20)
	}

	Window._Visible = true

	Window._ScrollOffset = 0
	Window._MaxScroll = 0
	Window._CanvasHeight = 0
	Window._VisibleHeight = Theme.WindowVisibleHeight
	Window._DraggingScrollbar = false

	Window._ScrollSinkActive = nil
	Window._CameraSinkActive = nil
	Window._InterfaceSinkActive = nil

	Window._DrawingObjects = {}

	Window._ActiveDropdown = nil
	Window._ActiveSlider = nil

	Window._Pages = {}
	Window._ActivePageIndex = 1
	Window._TabBarHeight = 34
	Window._TabDrawings = {}
	Window._TabScrollOffset = 0

	function Window:SetInputBlocking(Type, Enabled)
		Library:SetInputBlockingForWindow(Window, Type, Enabled)
	end

	function Window:GetActiveSections()
		local ActivePage = Window._Pages[Window._ActivePageIndex]
		if ActivePage then
			return ActivePage.Sections
		end
		return Window._Sections
	end

	Window.OnSave = function() end
	Window.OnExit = function() end

	local TitleBarBackgroundDrawing = nil
	local TitleBarHighlightDrawing = nil
	local TitleBarAccentWashDrawing = nil
	local TitleBarBorderDrawing = nil
	local TitleBarTextDrawing = nil
	local WindowBodyBackgroundDrawing = nil
	local WindowBodyTopSheenDrawing = nil
	local WindowBodyBottomShadeDrawing = nil
	local WindowBodyBorderDrawing = nil
	local WindowBottomBorderDrawing = nil
	local TitleAccentCircleDrawing = nil
	local TitleAccentOuterGlowCircleDrawing = nil
	local WindowTopAccentDrawing = nil
	local SaveButtonBackgroundDrawing = nil
	local SaveButtonTextDrawing = nil
	local ExitButtonBackgroundDrawing = nil
	local ExitButtonTextDrawing = nil
	local TitleBarSeparatorDrawing = nil
	local CloseButtonBackgroundDrawing = nil
	local CloseButtonBorderDrawing = nil
	local CloseButtonTextDrawing = nil

	local ActionButtonWidth = 40
	local ActionButtonHeight = 18
	local ActionButtonMarginGap = 5

	if not UseImmediateMode and DrawingBackendAvailable then

		WindowBodyBackgroundDrawing = CreateRectangleDrawing(Theme.WindowBackground, true, 1, 0.97)
		ApplyDrawingProperties(WindowBodyBackgroundDrawing, {
			Position = Vector2.new(WindowConfig.Position.X, WindowConfig.Position.Y + Theme.TitleBarHeight),
			Size = Vector2.new(Theme.WindowWidth, 10),
		})

		WindowBodyTopSheenDrawing = CreateRectangleDrawing(Theme.WindowSurfaceHighlight, true, 2, 0.26)
		ApplyDrawingProperties(WindowBodyTopSheenDrawing, {
			Position = Vector2.new(WindowConfig.Position.X, WindowConfig.Position.Y + Theme.TitleBarHeight),
			Size = Vector2.new(Theme.WindowWidth, 44),
		})

		WindowBodyBottomShadeDrawing = CreateRectangleDrawing(Theme.WindowSurfaceShade, true, 2, 0.22)
		ApplyDrawingProperties(WindowBodyBottomShadeDrawing, {
			Position = Vector2.new(WindowConfig.Position.X, WindowConfig.Position.Y + Theme.TitleBarHeight),
			Size = Vector2.new(Theme.WindowWidth, 44),
		})

		WindowBodyBorderDrawing = CreateRectangleDrawing(Theme.WindowBorder, false, 2, 0.8)
		ApplyDrawingProperties(WindowBodyBorderDrawing, {
			Position = GetRenderProperty(WindowBodyBackgroundDrawing, "Position"),
			Size = GetRenderProperty(WindowBodyBackgroundDrawing, "Size"),
		})

		TitleBarBackgroundDrawing = CreateRectangleDrawing(Theme.TitleBarBackground, true, 3, 0.97)
		ApplyDrawingProperties(TitleBarBackgroundDrawing, {
			Position = WindowConfig.Position,
			Size = Vector2.new(Theme.WindowWidth, Theme.TitleBarHeight),
		})

		TitleBarHighlightDrawing = CreateRectangleDrawing(Theme.TitleBarHighlight, true, 4, 0.32)
		ApplyDrawingProperties(TitleBarHighlightDrawing, {
			Position = WindowConfig.Position,
			Size = Vector2.new(Theme.WindowWidth, math.max(6, Theme.TitleBarHeight * 0.45)),
		})

		TitleBarAccentWashDrawing = CreateRectangleDrawing(Theme.TitleBarAccentWash, true, 4, 0.34)
		ApplyDrawingProperties(TitleBarAccentWashDrawing, {
			Position = WindowConfig.Position,
			Size = Vector2.new(Theme.WindowWidth * 0.55, Theme.TitleBarHeight),
		})

		TitleBarBorderDrawing = CreateRectangleDrawing(Theme.WindowBorder, false, 4, 0.8)
		ApplyDrawingProperties(TitleBarBorderDrawing, {
			Position = WindowConfig.Position,
			Size = Vector2.new(Theme.WindowWidth, Theme.TitleBarHeight),
		})

		TitleBarSeparatorDrawing = CreateTrackedDrawingObject("Line")
		ApplyDrawingProperties(TitleBarSeparatorDrawing, {
			Thickness = 2,
			Transparency = 0.85,
			Color = Theme.TitleBarSeparator,
			Visible = true,
			ZIndex = 4,
		})

		TitleAccentCircleDrawing = CreateTrackedDrawingObject("Circle")
		ApplyDrawingProperties(TitleAccentCircleDrawing, {
			Filled = true,
			Radius = 3,
			NumSides = 12,
			Transparency = 1,
			Color = Theme.TitleBarSeparator,
			ZIndex = 6,
			Visible = true,
		})

		TitleAccentOuterGlowCircleDrawing = CreateTrackedDrawingObject("Circle")
		ApplyDrawingProperties(TitleAccentOuterGlowCircleDrawing, {
			Filled = false,
			Radius = 5,
			NumSides = 12,
			Transparency = 0.4,
			Color = Theme.TitleBarSeparator,
			Thickness = 1,
			ZIndex = 5,
			Visible = true,
		})

		TitleBarTextDrawing = CreateTextDrawing(WindowConfig.Title, Theme.TitleFontSize, Theme.TitleBarText, 5)

		CloseButtonBackgroundDrawing = CreateRectangleDrawing(Theme.CloseButtonBackground, true, 5, 0.9)
		CloseButtonBorderDrawing = CreateRectangleDrawing(Theme.CloseButtonBorder, false, 6, 0.9)
		CloseButtonTextDrawing = CreateTextDrawing("X", 13, Theme.TitleBarText, 7)
		ApplyDrawingProperties(CloseButtonTextDrawing, { Visible = true })

		WindowBottomBorderDrawing = CreateTrackedDrawingObject("Line")
		ApplyDrawingProperties(WindowBottomBorderDrawing, {
			Thickness = 1,
			Transparency = 0.35,
			Color = Theme.TitleBarSeparator,
			ZIndex = 4,
			Visible = false,
		})

		WindowTopAccentDrawing = CreateTrackedDrawingObject("Line")
		ApplyDrawingProperties(WindowTopAccentDrawing, {
			Thickness = 1.5,
			Transparency = 0.95,
			Color = Theme.TitleBarSeparator,
			ZIndex = 5,
			Visible = true,
		})


		Window._GlowDrawings = {}
		for GlowIndex = 1, 3 do
			Window._GlowDrawings[GlowIndex] = CreateRectangleDrawing(Theme.TitleBarSeparator, false, 0, 0.08 / GlowIndex)
		end

		Window._CornerBrackets = {}

		for BracketIndex = 1, 8 do
			Window._CornerBrackets[BracketIndex] = CreateTrackedDrawingObject("Line")
			ApplyDrawingProperties(Window._CornerBrackets[BracketIndex], {
				Thickness = 1.25,
				Color = Theme.TitleBarSeparator,
				Transparency = 0.55,
				ZIndex = 4,
				Visible = true,
			})
		end

		Window._SideTicks = {}
		for TickIndex = 1, 4 do
			Window._SideTicks[TickIndex] = CreateTrackedDrawingObject("Line")
			ApplyDrawingProperties(Window._SideTicks[TickIndex], {
				Thickness = 1,
				Color = Theme.TitleBarSeparator,
				Transparency = 0.35,
				ZIndex = 4,
				Visible = true,
			})
		end

		Window._ResizeGripLines = {}
		for ResizeGripLineIndex = 1, 3 do
			Window._ResizeGripLines[ResizeGripLineIndex] = CreateTrackedDrawingObject("Line")
			ApplyDrawingProperties(Window._ResizeGripLines[ResizeGripLineIndex], {
				Thickness = 1.35,
				Color = Theme.TitleBarSeparator,
				Transparency = 0.45,
				ZIndex = 7,
				Visible = true,
			})
		end

		Window._SearchIconCircle = CreateTrackedDrawingObject("Circle")
		ApplyDrawingProperties(Window._SearchIconCircle, {
			Radius = 4.5,
			Filled = false,
			Thickness = 1.5,
			NumSides = 12,
			Color = Theme.TitleBarText,
			ZIndex = 6,
			Visible = true,
		})

		Window._SearchIconLine = CreateTrackedDrawingObject("Line")
		ApplyDrawingProperties(Window._SearchIconLine, {
			Thickness = 1.5,
			Color = Theme.TitleBarText,
			ZIndex = 6,
			Visible = true,
		})

		Window._SearchBackgroundDrawing = CreateRectangleDrawing(Theme.TextBoxBackground, true, 16, 0.95)
		Window._SearchBorderDrawing = CreateRectangleDrawing(Theme.TextBoxBorder, false, 17, 0.7)
		Window._SearchTextDrawing = CreateTextDrawing("", Theme.ElementFontSize, Theme.TextBoxText, 18)

		Window._SearchIconCircleDrawing = CreateTrackedDrawingObject("Circle")
		ApplyDrawingProperties(Window._SearchIconCircleDrawing, {
			Radius = 3.5,
			Filled = false,
			Thickness = 1.5,
			NumSides = 10,
			Color = Theme.TextBoxPlaceholder,
			ZIndex = 18,
			Visible = false,
		})

		Window._SearchIconLineDrawing = CreateTrackedDrawingObject("Line")
		ApplyDrawingProperties(Window._SearchIconLineDrawing, {
			Thickness = 1.5,
			Color = Theme.TextBoxPlaceholder,
			ZIndex = 18,
			Visible = false,
		})

		Window._SearchDropdownBackgroundDrawing = CreateRectangleDrawing(Theme.DropdownBackground, true, 16, 0.98)
		Window._SearchDropdownBorderDrawing = CreateRectangleDrawing(Theme.DropdownBorder, false, 17, 0.8)
		Window._SearchDropdownHoverDrawing = CreateRectangleDrawing(Theme.DropdownItemHover, true, 17, 0.6)

		Window._SearchDropdownTextDrawings = {}
		for TextIndex = 1, 5 do
			Window._SearchDropdownTextDrawings[TextIndex] = CreateTextDrawing("", Theme.ElementFontSize, Theme.DropdownText, 18)
		end

		Window._ElementHighlightDrawing = CreateRectangleDrawing(Theme.TitleBarSeparator, false, 15, 0)
		ApplyDrawingProperties(Window._ElementHighlightDrawing, { Visible = false })

		Window._DrawingObjects = {
			WindowBodyBackgroundDrawing, WindowBodyTopSheenDrawing, WindowBodyBottomShadeDrawing, WindowBodyBorderDrawing,
			TitleBarBackgroundDrawing, TitleBarHighlightDrawing, TitleBarAccentWashDrawing, TitleBarBorderDrawing, TitleBarTextDrawing,
			TitleAccentCircleDrawing, TitleAccentOuterGlowCircleDrawing, TitleBarSeparatorDrawing,
			CloseButtonBackgroundDrawing, CloseButtonBorderDrawing, CloseButtonTextDrawing,
			WindowBottomBorderDrawing, WindowTopAccentDrawing,
		}
		for DiscardGlowIndex, GlowObject in ipairs(Window._GlowDrawings) do
			table.insert(Window._DrawingObjects, GlowObject)
		end
		for DiscardBracketIndex, LineObject in ipairs(Window._CornerBrackets) do
			table.insert(Window._DrawingObjects, LineObject)
		end
		for DiscardTickIndex, TickObject in ipairs(Window._SideTicks) do
			table.insert(Window._DrawingObjects, TickObject)
		end
		for DiscardResizeGripLineIndex, ResizeGripLineObject in ipairs(Window._ResizeGripLines) do
			table.insert(Window._DrawingObjects, ResizeGripLineObject)
		end
		table.insert(Window._DrawingObjects, Window._SearchIconCircle)
		table.insert(Window._DrawingObjects, Window._SearchIconLine)
		table.insert(Window._DrawingObjects, Window._SearchBackgroundDrawing)
		table.insert(Window._DrawingObjects, Window._SearchBorderDrawing)
		table.insert(Window._DrawingObjects, Window._SearchTextDrawing)
		table.insert(Window._DrawingObjects, Window._SearchIconCircleDrawing)
		table.insert(Window._DrawingObjects, Window._SearchIconLineDrawing)
		table.insert(Window._DrawingObjects, Window._SearchDropdownBackgroundDrawing)
		table.insert(Window._DrawingObjects, Window._SearchDropdownBorderDrawing)
		table.insert(Window._DrawingObjects, Window._SearchDropdownHoverDrawing)
		table.insert(Window._DrawingObjects, Window._ElementHighlightDrawing)
		
		for DiscardTextIndex, TextDrawingObject in ipairs(Window._SearchDropdownTextDrawings) do
			table.insert(Window._DrawingObjects, TextDrawingObject)
		end
	end

	Window._SearchActive = false
	Window._SearchResults = {}
	Window._HoveredSearchResultIndex = nil
	Window._HighlightedElement = nil
	Window._SearchTextBox = {
		_Type = "TextBox",
		_IsSearch = true,
		_Value = "",
		_IsFocused = false,
		_IsSelected = false,
		_CursorVisible = false,
		_CursorBlinkTime = 0,
		_Placeholder = string.format("Search elements%s", AsciiEllipsis),
		SetValue = NewCClosure(function(Self, NewValue)
			Self._Value = NewValue
			Window:PerformSearch()
		end)
	}

	function Window:PerformSearch()
		local SearchQuery = string.lower(Window._SearchTextBox._Value)
		Window._SearchResults = {}

		if SearchQuery == "" then
			Window:RecalculateLayout()
			return
		end

		for SectionIndex, Section in ipairs(Window._Sections) do
			for ElementIndex, Element in ipairs(Section._Elements) do
				local IsMatch = false
				local MatchText = ""

				if Element._Type == "TextLabel" then
					IsMatch = string.find(string.lower(Element._Text), SearchQuery, 1, true) ~= nil
					MatchText = Element._Text
				elseif Element._Type == "TextButton" or Element._Type == "Toggle" or Element._Type == "TextBox" or Element._Type == "Dropdown" or Element._Type == "Slider" then
					IsMatch = string.find(string.lower(Element._Text), SearchQuery, 1, true) ~= nil
					MatchText = Element._Text
				end

				if IsMatch then
					table.insert(Window._SearchResults, {
						Section = Section,
						Element = Element,
						Text = string.format("[%s] > %s", Section._Title, MatchText)
					})
					if #Window._SearchResults >= 5 then
						break
					end
				end
			end
			if #Window._SearchResults >= 5 then
				break
			end
		end

		Window:RecalculateLayout()
	end

	function Window:RecalculateLayout()
		if not DrawingBackendAvailable then return end

		local WindowPosition = Window._Position
		local ViewportStart, ViewportEnd = GetWindowContentViewportYRange(Window, WindowPosition.Y)

		local SearchBarHeightOffset = 0
		if Window._SearchActive then
			SearchBarHeightOffset = 32
		end

		local ColumnWidth = (Theme.WindowWidth - (Theme.InnerMargin * 3)) / 2
		local ColumnOnePositionY = Theme.SectionPadding + SearchBarHeightOffset
		local ColumnTwoPositionY = Theme.SectionPadding + SearchBarHeightOffset

		
		if not UseImmediateMode and #Window._Pages > 0 then
			for DiscardSectionIndex, SectionObject in ipairs(Window._Sections) do
				if SectionObject._PageIndex and SectionObject._PageIndex ~= Window._ActivePageIndex then
					local VisibilityObjects = { SectionObject._FullBackground, SectionObject._Background, SectionObject._Border, SectionObject._TextLabel, SectionObject._AccentLine, SectionObject._LeftAccentLine }
					SetDrawingObjectsVisibility(VisibilityObjects, false)
					if SectionObject._TopRightTechLine then SetRenderProperty(SectionObject._TopRightTechLine, "Visible", false) end
					if SectionObject._CornerBrackets then
						for DiscardCornerBracketIndex, LineObject in ipairs(SectionObject._CornerBrackets) do
							SetRenderProperty(LineObject, "Visible", false)
						end
					end
					for DiscardElementIndex, Element in ipairs(SectionObject._Elements) do
						if Element._Type == "TextLabel" then
							SetDrawingObjectsVisibility({ Element._AccentLineDrawing }, false)
							for DiscardLineDrawingIndex, LineDrawingObject in ipairs(Element._LineDrawings or {}) do
								SetRenderProperty(LineDrawingObject, "Visible", false)
							end
						elseif Element._Type == "TextButton" then
							SetDrawingObjectsVisibility({ Element._BackgroundDrawing, Element._BorderDrawing, Element._TextDrawing }, false)
							if Element._AccentLineDrawing then SetRenderProperty(Element._AccentLineDrawing, "Visible", false) end
						elseif Element._Type == "Toggle" then
							SetDrawingObjectsVisibility({ Element._BackgroundDrawing, Element._BorderDrawing, Element._TextDrawing, Element._IndicatorDrawing }, false)
							if Element._AccentLineDrawing then SetRenderProperty(Element._AccentLineDrawing, "Visible", false) end
						elseif Element._Type == "TextBox" then
							SetDrawingObjectsVisibility({ Element._BackgroundDrawing, Element._BorderDrawing, Element._LabelDrawing, Element._TextDrawing }, false)
							if Element._AccentLineDrawing then SetRenderProperty(Element._AccentLineDrawing, "Visible", false) end
							if Element._SelectionDrawing then SetRenderProperty(Element._SelectionDrawing, "Visible", false) end
							if Element._CursorDrawing then SetRenderProperty(Element._CursorDrawing, "Visible", false) end
						elseif Element._Type == "Dropdown" then
							SetDrawingObjectsVisibility({ Element._BackgroundDrawing, Element._BorderDrawing, Element._TextDrawing, Element._ArrowDrawing }, false)
							if Element._AccentLineDrawing then SetRenderProperty(Element._AccentLineDrawing, "Visible", false) end
							for DiscardItemDataIndex, ItemData in ipairs(Element._ItemDrawingObjects) do
								SetDrawingObjectsVisibility({ ItemData.BackgroundDrawing, ItemData.TextDrawing, ItemData.SeparatorDrawing }, false)
							end
						elseif Element._Type == "Slider" then
							SetDrawingObjectsVisibility({
								Element._LabelDrawing, Element._ValueTextDrawing,
								Element._TrackBackgroundDrawing, Element._TrackBorderDrawing,
								Element._TrackFillDrawing, Element._ThumbDrawing, Element._ThumbInnerDrawing,
							}, false)
						elseif Element._Type == "ColorPicker" then
							SetDrawingObjectsVisibility({ Element._LabelDrawing, Element._SwatchDrawing, Element._SwatchBorderDrawing }, false)
							if Element._HoverBackgroundDrawing then SetRenderProperty(Element._HoverBackgroundDrawing, "Visible", false) end
							if Element._AccentLineDrawing then SetRenderProperty(Element._AccentLineDrawing, "Visible", false) end
							if Element._ChevronDrawing then SetRenderProperty(Element._ChevronDrawing, "Visible", false) end
						end
					end
				end
			end
		end

		for SectionIndex, Section in ipairs(Window:GetActiveSections()) do

			local IsColumnOne = (ColumnOnePositionY <= ColumnTwoPositionY)
			local CurrentX = (IsColumnOne and Theme.InnerMargin or (Theme.InnerMargin * 2 + ColumnWidth))
			local CurrentY = Theme.TitleBarHeight + Window._TabBarHeight + (IsColumnOne and ColumnOnePositionY or ColumnTwoPositionY)

			Section._PositionX = CurrentX
			Section._PositionY = CurrentY
			Section._Width = ColumnWidth

			local SectionScrollOffset = Section._SectionScrollOffset or 0
			local SectionContentHeight = Theme.ElementHeight + Theme.ElementPadding

			-- Estimate the effective section limit before laying out elements so
			-- element widths can reserve room for a section-local scrollbar on the
			-- first pass after a resize.
			local EstimatedEffectiveMaxHeight = Section._MaxHeight
			if EstimatedEffectiveMaxHeight then
				local EstimatedAvailableSectionHeight = Theme.TitleBarHeight + Window._VisibleHeight - CurrentY - Theme.SectionPadding
				EstimatedEffectiveMaxHeight = math.min(EstimatedEffectiveMaxHeight, math.max(Theme.ElementHeight + Theme.ElementPadding, EstimatedAvailableSectionHeight))
			end

			local HasScrollbar = EstimatedEffectiveMaxHeight and Section._FullContentHeight and Section._FullContentHeight > EstimatedEffectiveMaxHeight
			for ElementIndex, Element in ipairs(Section._Elements) do
				Element._PositionX = CurrentX + 5
				Element._PositionY = CurrentY + SectionContentHeight - SectionScrollOffset
				Element._Width = ColumnWidth - 10 - (HasScrollbar and (Theme.ScrollbarWidth + 4) or 0)

				if Element._Type == "TextLabel" then
					local AvailWidth = TextAvailableWidth(Element._Width, Theme.ElementFontSize)
					if not Element._WrappedLines or Element._LastText ~= Element._Text or Element._LastWidth ~= Element._Width or Element._LastFontSize ~= Theme.ElementFontSize then
						Element._LastText = Element._Text
						Element._LastWidth = Element._Width
						Element._LastFontSize = Theme.ElementFontSize
						Element._WrappedLines = WrapText(Element._Text, AvailWidth, Theme.ElementFontSize)
					end
					Element._Height = TextBlockHeight(#Element._WrappedLines, Theme.ElementFontSize)
				end
				if Element._Type == "Slider" then
					local ActualWidth = Element._Width - (Window._MaxScroll > 0 and Theme.ScrollbarWidth + 4 or 0)
					Element._TrackPositionX = Element._PositionX
					Element._TrackPositionY = Element._PositionY + Theme.ElementFontSize + 4
					Element._TrackTotalWidth = ActualWidth
					Element._TrackTotalHeight = 6
				elseif Element._Type == "ColorPicker" then
					local ActualWidth = Element._Width - (Window._MaxScroll > 0 and Theme.ScrollbarWidth + 4 or 0)
					Element._SwatchSize = Theme.ColorSwatchSize
					Element._SwatchPositionX = Element._PositionX + ActualWidth - Element._SwatchSize - 5
					Element._SwatchPositionY = Element._PositionY + (Element._Height - Element._SwatchSize) / 2
				elseif Element._Type == "Dropdown" then
					local ItemVerticalOffset = Element._PositionY + Element._Height
					for ItemIndex, ItemData in ipairs(Element._ItemDrawingObjects) do
						ItemData._PositionX = Element._PositionX
						ItemData._PositionY = ItemVerticalOffset
						ItemData._Width = Element._Width
						ItemVerticalOffset = ItemVerticalOffset + Theme.ElementHeight
					end
				end

				local CurrentPadding = Theme.ElementPadding
				local NextElement = Section._Elements[ElementIndex + 1]
				if Element._Type == "TextLabel" and NextElement and NextElement._Type == "TextLabel" then
					CurrentPadding = 2
				end

				SectionContentHeight = SectionContentHeight + Element._Height + CurrentPadding

				if Element._Type == "Dropdown" and Element._Expanded then
					SectionContentHeight = SectionContentHeight + (#Element._Options * Theme.ElementHeight)
				end

				if not UseImmediateMode then
					local ElementAbsolutePosition = WindowPosition + Vector2.new(Element._PositionX, Element._PositionY - Window._ScrollOffset)
					local ElementAbsoluteSize = Vector2.new(Element._Width - (Window._MaxScroll > 0 and Theme.ScrollbarWidth + 4 or 0), Element._Height)

					local IsElementVisible = IsElementVisibleInViewport(ElementAbsolutePosition.Y, Element._Height, Section, Window, WindowPosition.Y)

					if Element._Type == "TextLabel" then

						if not Element._WrappedLines or #Element._WrappedLines == 0 then
							local AvailWidth = TextAvailableWidth(Element._Width, Theme.ElementFontSize)
							Element._WrappedLines = WrapText(Element._Text, AvailWidth, Theme.ElementFontSize)
							Element._Height = TextBlockHeight(#Element._WrappedLines, Theme.ElementFontSize)
							Element:_RebuildLineDrawings(Element._WrappedLines)
						end

						if #Element._LineDrawings ~= #(Element._WrappedLines or {}) then
							Element:_RebuildLineDrawings(Element._WrappedLines or { Element._Text })
						end

						local AllowedMinY, AllowedMaxY = GetSectionAllowedYRange(Section, Window, WindowPosition.Y)

						if Element._AccentLineDrawing then
							local Alpha = LerpValue(0.4, 0.85, Element._HoverFactor or 0)
							local FromPos = Vector2.new(ElementAbsolutePosition.X, ElementAbsolutePosition.Y + 4)
							local ToPos = Vector2.new(ElementAbsolutePosition.X, ElementAbsolutePosition.Y + Element._Height - 4)
							local ClippedFrom, ClippedTo = ClipVerticalLineToYRange(FromPos, ToPos, AllowedMinY, AllowedMaxY)
							if ClippedFrom and ClippedTo then
								ApplyDrawingProperties(Element._AccentLineDrawing, {
									From = ClippedFrom,
									To = ClippedTo,
									Thickness = LerpValue(1, 2, Element._HoverFactor or 0),
									Transparency = Alpha,
									Visible = IsElementVisible,
								})
							else
								ApplyDrawingProperties(Element._AccentLineDrawing, { Visible = false })
							end
						end

						local VerticalPadding   = LabelVerticalPadding(Theme.ElementFontSize)
						local LineHeight = FontLineHeight(Theme.ElementFontSize)
						local HorizontalInset  = FontHorizontalInset(Theme.ElementFontSize)
						local TextColor = Theme.LabelText:Lerp(Theme.LabelTextHover, Element._HoverFactor or 0)
						for LineIndex, LineDrawingObject in ipairs(Element._LineDrawings) do
							local LineY = ElementAbsolutePosition.Y + VerticalPadding + (LineIndex - 1) * LineHeight
							local IsLineVisible = IsElementVisible and (LineY >= AllowedMinY) and (LineY + LineHeight <= AllowedMaxY)
							ApplyDrawingProperties(LineDrawingObject, {
								Position = Vector2.new(
									ElementAbsolutePosition.X + HorizontalInset,
									LineY
								),
								Color = TextColor,
								Size = Theme.ElementFontSize,
								Visible = IsLineVisible,
							})
						end
					elseif Element._Type == "TextButton" then
						local ButtonBackgroundColor = Theme.ButtonBackground:Lerp(Theme.ButtonBackgroundHover, Element._HoverFactor or 0)
						if Element._BackgroundDrawing then
							ApplyDrawingProperties(Element._BackgroundDrawing, { Position = ElementAbsolutePosition, Size = ElementAbsoluteSize, Color = ButtonBackgroundColor, Visible = IsElementVisible })
						end
						if Element._BorderDrawing then
							ApplyDrawingProperties(Element._BorderDrawing, { Position = ElementAbsolutePosition, Size = ElementAbsoluteSize, Color = Theme.ButtonBorder, Visible = IsElementVisible })
						end
						if Element._TextDrawing then
							ApplyDrawingProperties(Element._TextDrawing, {
								Text = Element._Text,
								Position = ElementAbsolutePosition + Vector2.new(10, (Element._Height - Theme.ElementFontSize) / 2),
								Size = Theme.ElementFontSize,
								Color = Theme.ButtonText,
								Visible = IsElementVisible,
							})
						end

						if Element._AccentLineDrawing then
							local AccentFrom = Vector2.new(ElementAbsolutePosition.X, ElementAbsolutePosition.Y + 3)
							local AccentTo = Vector2.new(ElementAbsolutePosition.X, ElementAbsolutePosition.Y + Element._Height - 3)
							local AllowedMinY, AllowedMaxY = GetSectionAllowedYRange(Section, Window, WindowPosition.Y)
							local ClippedFrom, ClippedTo = ClipVerticalLineToYRange(AccentFrom, AccentTo, AllowedMinY, AllowedMaxY)
							if ClippedFrom and ClippedTo and (Element._HoverFactor or 0) > 0.01 then
								ApplyDrawingProperties(Element._AccentLineDrawing, {
									From = ClippedFrom,
									To = ClippedTo,
									Transparency = Element._HoverFactor or 0,
									Visible = IsElementVisible,
								})
							else
								ApplyDrawingProperties(Element._AccentLineDrawing, { Visible = false })
							end
						end
					elseif Element._Type == "Toggle" then
						local ToggleBackgroundColor = Theme.ButtonBackground:Lerp(Theme.ButtonBackgroundHover, Element._HoverFactor or 0)
						if Element._BackgroundDrawing then
							ApplyDrawingProperties(Element._BackgroundDrawing, { Position = ElementAbsolutePosition, Size = ElementAbsoluteSize, Color = ToggleBackgroundColor, Visible = IsElementVisible })
						end
						if Element._BorderDrawing then
							ApplyDrawingProperties(Element._BorderDrawing, { Position = ElementAbsolutePosition, Size = ElementAbsoluteSize, Color = Theme.ButtonBorder, Visible = IsElementVisible })
						end
						if Element._TextDrawing then
							ApplyDrawingProperties(Element._TextDrawing, {
								Position = ElementAbsolutePosition + Vector2.new(10, (Element._Height - Theme.ElementFontSize) / 2),
								Size = Theme.ElementFontSize,
								Color = Theme.ButtonText,
								Visible = IsElementVisible,
							})
						end
						if Element._IndicatorDrawing then
							local PipX = ElementAbsolutePosition.X + ElementAbsoluteSize.X - 14
							local PipY = ElementAbsolutePosition.Y + Element._Height / 2
							local PipColor = Theme.ToggleInactive:Lerp(Theme.ToggleActive, Element._ActiveFactor or 0)
							ApplyDrawingProperties(Element._IndicatorDrawing, { Position = Vector2.new(PipX, PipY), Color = PipColor, Visible = IsElementVisible })
						end

						if Element._AccentLineDrawing then
							local AccentFrom = Vector2.new(ElementAbsolutePosition.X, ElementAbsolutePosition.Y + 3)
							local AccentTo = Vector2.new(ElementAbsolutePosition.X, ElementAbsolutePosition.Y + Element._Height - 3)
							local AllowedMinY, AllowedMaxY = GetSectionAllowedYRange(Section, Window, WindowPosition.Y)
							local ClippedFrom, ClippedTo = ClipVerticalLineToYRange(AccentFrom, AccentTo, AllowedMinY, AllowedMaxY)
							if ClippedFrom and ClippedTo and (Element._ActiveFactor or 0) > 0.01 then
								ApplyDrawingProperties(Element._AccentLineDrawing, {
									From = ClippedFrom,
									To = ClippedTo,
									Transparency = Element._ActiveFactor or 0,
									Visible = IsElementVisible,
								})
							else
								ApplyDrawingProperties(Element._AccentLineDrawing, { Visible = false })
							end
						end
					elseif Element._Type == "TextBox" then

						if Element._IsFocused then
							local Now = tick()
							if Now - Element._CursorBlinkTime >= 0.53 then
								Element._CursorBlinkTime = Now
								Element._CursorVisible = not Element._CursorVisible
							end
						else
							Element._CursorVisible = false
							Element._CursorBlinkTime = 0
						end

						local TextBoxBackgroundColor = Theme.TextBoxBackground:Lerp(Theme.TextBoxBackgroundHover, Element._HoverFactor or 0)
						local TextBoxBorderColor = Theme.TextBoxBorder:Lerp(Theme.TextBoxBorderFocused, Element._FocusFactor or 0)
						local TextBoxBorderThickness = LerpValue(1, 2, Element._FocusFactor or 0)

						if Element._BackgroundDrawing then
							ApplyDrawingProperties(Element._BackgroundDrawing, { Position = ElementAbsolutePosition, Size = ElementAbsoluteSize, Color = TextBoxBackgroundColor, Visible = IsElementVisible })
						end
						if Element._BorderDrawing then
							ApplyDrawingProperties(Element._BorderDrawing, { Position = ElementAbsolutePosition, Size = ElementAbsoluteSize, Color = TextBoxBorderColor, Thickness = TextBoxBorderThickness, Visible = IsElementVisible })
						end

						if Element._AccentLineDrawing then
							local AccentFrom = Vector2.new(ElementAbsolutePosition.X, ElementAbsolutePosition.Y + 3)
							local AccentTo = Vector2.new(ElementAbsolutePosition.X, ElementAbsolutePosition.Y + Element._Height - 3)
							local AllowedMinY, AllowedMaxY = GetSectionAllowedYRange(Section, Window, WindowPosition.Y)
							local ClippedFrom, ClippedTo = ClipVerticalLineToYRange(AccentFrom, AccentTo, AllowedMinY, AllowedMaxY)
							if ClippedFrom and ClippedTo and (Element._FocusFactor or 0) > 0.01 then
								ApplyDrawingProperties(Element._AccentLineDrawing, {
									From = ClippedFrom,
									To = ClippedTo,
									Transparency = Element._FocusFactor or 0,
									Visible = IsElementVisible,
								})
							else
								ApplyDrawingProperties(Element._AccentLineDrawing, { Visible = false })
							end
						end

						if Element._LabelDrawing then
							ApplyDrawingProperties(Element._LabelDrawing, {
								Position = ElementAbsolutePosition + Vector2.new(8, (Element._Height - Theme.ElementFontSize) / 2),
								Size = Theme.ElementFontSize,
								Color = Theme.TextBoxText,
								Visible = IsElementVisible,
							})
						end

						if Element._TextDrawing then
							local LabelWidth = Element._Text ~= "" and math.floor(#Element._Text * Theme.ElementFontSize * Theme.FontCharWidthRatio * 1.2) + 18 or 8
							local InputStartX = ElementAbsolutePosition.X + LabelWidth + 4
							local HasValue = Element._Value ~= ""
							local DisplayText = HasValue and Element._Value or Element._Placeholder

							local ElementRightEdge = ElementAbsolutePosition.X + ElementAbsoluteSize.X
							local AvailableInputWidth = ElementRightEdge - InputStartX - 8
							local CharacterWidth = Theme.ElementFontSize * Theme.FontCharWidthRatio * 1.25
							local MaxChars = math.max(1, math.floor(AvailableInputWidth / CharacterWidth))
							local ClippedText = ClipEditableTextForWidth(DisplayText, MaxChars, Element._IsFocused)
							ApplyDrawingProperties(Element._TextDrawing, {
								Position = Vector2.new(InputStartX, ElementAbsolutePosition.Y + (Element._Height - Theme.ElementFontSize) / 2),
								Text = ClippedText,
								Size = Theme.ElementFontSize,
								Color = HasValue and Theme.TextBoxText or Theme.TextBoxPlaceholder,
								Visible = IsElementVisible,
							})

							if Element._CursorDrawing then
								local CursorX = InputStartX + math.min(#ClippedText * CharacterWidth, AvailableInputWidth)
								local CursorTopY = ElementAbsolutePosition.Y + (Element._Height - Theme.ElementFontSize) / 2
								local CursorBotY = CursorTopY + Theme.ElementFontSize
								ApplyDrawingProperties(Element._CursorDrawing, {
									From = Vector2.new(CursorX, CursorTopY + 1),
									To = Vector2.new(CursorX, CursorBotY - 1),
									Color = Theme.TextBoxCursor,
									Visible = IsElementVisible and Element._IsFocused and Element._CursorVisible,
								})
							end
						end

						if Element._SelectionDrawing then
							local ShowSelection = IsElementVisible and Element._IsFocused and Element._IsSelected and Element._Value ~= ""
							if ShowSelection then
								local LabelWidth = Element._Text ~= "" and math.floor(#Element._Text * Theme.ElementFontSize * Theme.FontCharWidthRatio) + 18 or 8
								local InputStartX = ElementAbsolutePosition.X + LabelWidth + 4
								local CharacterWidth = Theme.ElementFontSize * Theme.FontCharWidthRatio
								local SelectionWidth = math.min(#Element._Value * CharacterWidth, ElementAbsoluteSize.X - LabelWidth - 12)
								ApplyDrawingProperties(Element._SelectionDrawing, {
									Position = Vector2.new(InputStartX - 2, ElementAbsolutePosition.Y + (Element._Height - Theme.ElementFontSize) / 2 - 2),
									Size = Vector2.new(SelectionWidth + 4, Theme.ElementFontSize + 4),
									Visible = true,
								})
							else
								SetRenderProperty(Element._SelectionDrawing, "Visible", false)
							end
						end
					elseif Element._Type == "Dropdown" then
						local DropdownBackgroundColor = Theme.DropdownBackground:Lerp(Theme.DropdownHover, Element._HoverFactor or 0)
						local DropdownBorderColor = Theme.DropdownBorder:Lerp(Theme.DropdownBorderHover, Element._HoverFactor or 0):Lerp(Theme.SectionText, Element._ExpandFactor or 0)
						local DropdownBorderThickness = LerpValue(1, 2, math.max(Element._HoverFactor or 0, Element._ExpandFactor or 0))
						if Element._BackgroundDrawing then
							ApplyDrawingProperties(Element._BackgroundDrawing, { Position = ElementAbsolutePosition, Size = ElementAbsoluteSize, Color = DropdownBackgroundColor, Visible = IsElementVisible })
						end
						if Element._BorderDrawing then
							ApplyDrawingProperties(Element._BorderDrawing, { Position = ElementAbsolutePosition, Size = ElementAbsoluteSize, Color = DropdownBorderColor, Thickness = DropdownBorderThickness, Visible = IsElementVisible })
						end
						if Element._TextDrawing then
							ApplyDrawingProperties(Element._TextDrawing, {
								Position = ElementAbsolutePosition + Vector2.new(8, (Element._Height - Theme.ElementFontSize) / 2),
								Size = Theme.ElementFontSize,
								Color = Theme.DropdownText,
								Visible = IsElementVisible,
							})
						end
						if Element._ArrowDrawing then
							ApplyDrawingProperties(Element._ArrowDrawing, {
								Position = ElementAbsolutePosition + Vector2.new(ElementAbsoluteSize.X - 18, (Element._Height - Theme.ElementFontSize) / 2),
								Size = Theme.ElementFontSize,
								Color = Theme.DropdownArrow,
								Visible = IsElementVisible,
							})
						end

						if Element._AccentLineDrawing then
							local AccentFrom = Vector2.new(ElementAbsolutePosition.X, ElementAbsolutePosition.Y + 3)
							local AccentTo = Vector2.new(ElementAbsolutePosition.X, ElementAbsolutePosition.Y + Element._Height - 3)
							local AllowedMinY, AllowedMaxY = GetSectionAllowedYRange(Section, Window, WindowPosition.Y)
							local ClippedFrom, ClippedTo = ClipVerticalLineToYRange(AccentFrom, AccentTo, AllowedMinY, AllowedMaxY)
							local AccentAlpha = (Element._HoverFactor or 0) * (1 - (Element._ExpandFactor or 0))
							if ClippedFrom and ClippedTo and AccentAlpha > 0.01 then
								ApplyDrawingProperties(Element._AccentLineDrawing, {
									From = ClippedFrom,
									To = ClippedTo,
									Transparency = AccentAlpha,
									Visible = IsElementVisible,
								})
							else
								ApplyDrawingProperties(Element._AccentLineDrawing, { Visible = false })
							end
						end

						if Element._Expanded then
							for ItemIndex, ItemData in ipairs(Element._ItemDrawingObjects) do
								local ItemAbsolutePosition = WindowPosition + Vector2.new(ItemData._PositionX, ItemData._PositionY - Window._ScrollOffset)
								local IsItemVisible = IsElementVisibleInViewport(ItemAbsolutePosition.Y, Theme.ElementHeight, Section, Window, WindowPosition.Y)
								local IsItemHovered = IsPointInsideRectangle(GetMouseLocation(UserInputService), ItemAbsolutePosition, Vector2.new(ItemData._Width, Theme.ElementHeight))

								if ItemData.BackgroundDrawing then
									ApplyDrawingProperties(ItemData.BackgroundDrawing, {
										Position = ItemAbsolutePosition,
										Size = Vector2.new(ElementAbsoluteSize.X, Theme.ElementHeight),
										Color = IsItemHovered and Theme.DropdownItemHover or Theme.DropdownItemBackground,
										Visible = IsItemVisible,
									})
								end
								if ItemData.TextDrawing then
									ApplyDrawingProperties(ItemData.TextDrawing, {
										Position = ItemAbsolutePosition + Vector2.new(12, (Theme.ElementHeight - Theme.ElementFontSize) / 2),
										Size = Theme.ElementFontSize,
										Color = IsItemHovered and Theme.TitleBarText or Theme.DropdownText,
										Visible = IsItemVisible,
									})
								end
								if ItemData.SeparatorDrawing then
									ApplyDrawingProperties(ItemData.SeparatorDrawing, {
										From = Vector2.new(ItemAbsolutePosition.X + 6, ItemAbsolutePosition.Y + Theme.ElementHeight - 1),
										To = Vector2.new(ItemAbsolutePosition.X + ElementAbsoluteSize.X - 6, ItemAbsolutePosition.Y + Theme.ElementHeight - 1),
										Color = Theme.DropdownBorder,
										Visible = IsItemVisible,
									})
								end
							end
						end
					elseif Element._Type == "Slider" then
						local SliderLabelColor = Theme.SliderText:Lerp(Theme.TitleBarText, Element._HoverFactor or 0)
						local ValueColor = Theme.SectionText:Lerp(Theme.SectionTextHover, Element._ActiveFactor or 0)
						if Element._LabelDrawing then
							ApplyDrawingProperties(Element._LabelDrawing, { Position = ElementAbsolutePosition, Color = SliderLabelColor, Size = Theme.ElementFontSize, Visible = IsElementVisible })
						end
						if Element._ValueTextDrawing then
							ApplyDrawingProperties(Element._ValueTextDrawing, {
								Position = ElementAbsolutePosition + Vector2.new(Element._TrackTotalWidth - 48, 0),
								Color = ValueColor,
								Size = Theme.ElementFontSize,
								Visible = IsElementVisible,
							})
						end

						local TrackHeight = LerpValue(8, 10, Element._HoverFactor or 0)
						local TrackAbsolutePosition = ElementAbsolutePosition + Vector2.new(0, Theme.ElementFontSize + 5)
						local TrackAbsoluteSize = Vector2.new(Element._TrackTotalWidth, TrackHeight)

						if Element._TrackBackgroundDrawing then
							ApplyDrawingProperties(Element._TrackBackgroundDrawing, { Position = TrackAbsolutePosition, Size = TrackAbsoluteSize, Color = Theme.SliderTrackBackground, Visible = IsElementVisible })
						end
						if Element._TrackBorderDrawing then
							ApplyDrawingProperties(Element._TrackBorderDrawing, { Position = TrackAbsolutePosition, Size = TrackAbsoluteSize, Color = Theme.SliderBorder, Visible = IsElementVisible })
						end

						local Range = Element._MaxValue - Element._MinValue
						if Range == 0 then Range = 1 end
						local NormalizedValue = math.clamp((Element._Value - Element._MinValue) / Range, 0, 1)
						local FillWidth = math.floor(Element._TrackTotalWidth * NormalizedValue)
						local FillColor = Theme.SliderTrackFill:Lerp(Theme.SliderTrackFillHover, Element._HoverFactor or 0)

						if Element._TrackFillDrawing then
							ApplyDrawingProperties(Element._TrackFillDrawing, {
								Position = TrackAbsolutePosition,
								Size = Vector2.new(FillWidth, TrackHeight),
								Color = FillColor,
								Visible = IsElementVisible,
							})
						end
						local ThumbRadius = LerpValue(7, 9, Element._ThumbHoverFactor or 0)
						local ThumbColor = Theme.SliderThumb:Lerp(Theme.SliderThumbHover, Element._ThumbHoverFactor or 0)
						local ThumbCenter = TrackAbsolutePosition + Vector2.new(FillWidth, TrackHeight / 2)
						if Element._ThumbDrawing then
							ApplyDrawingProperties(Element._ThumbDrawing, {
								Position = ThumbCenter,
								Radius = ThumbRadius,
								Color = ThumbColor,
								Visible = IsElementVisible,
							})
						end

						if Element._ThumbInnerDrawing then
							ApplyDrawingProperties(Element._ThumbInnerDrawing, {
								Position = ThumbCenter,
								Color = FillColor,
								Visible = IsElementVisible,
							})
						end
					elseif Element._Type == "ColorPicker" then
						if Element._HoverBackgroundDrawing then
							ApplyDrawingProperties(Element._HoverBackgroundDrawing, {
								Position = ElementAbsolutePosition,
								Size = ElementAbsoluteSize,
								Transparency = (Element._HoverFactor or 0) * 0.55,
								Visible = IsElementVisible and (Element._HoverFactor or 0) > 0.01,
							})
						end

						if Element._AccentLineDrawing then
							local AccentFrom = Vector2.new(ElementAbsolutePosition.X, ElementAbsolutePosition.Y + 3)
							local AccentTo = Vector2.new(ElementAbsolutePosition.X, ElementAbsolutePosition.Y + Element._Height - 3)
							local AllowedMinY, AllowedMaxY = GetSectionAllowedYRange(Section, Window, WindowPosition.Y)
							local ClippedFrom, ClippedTo = ClipVerticalLineToYRange(AccentFrom, AccentTo, AllowedMinY, AllowedMaxY)
							if ClippedFrom and ClippedTo and (Element._HoverFactor or 0) > 0.01 then
								ApplyDrawingProperties(Element._AccentLineDrawing, {
									From = ClippedFrom,
									To = ClippedTo,
									Transparency = Element._HoverFactor or 0,
									Visible = IsElementVisible,
								})
							else
								ApplyDrawingProperties(Element._AccentLineDrawing, { Visible = false })
							end
						end
						if Element._LabelDrawing then
							local ColorPickerTextColor = Theme.LabelText:Lerp(Theme.LabelTextHover, Element._HoverFactor or 0)
							ApplyDrawingProperties(Element._LabelDrawing, {
								Position = ElementAbsolutePosition + Vector2.new(6, (Element._Height - Theme.ElementFontSize) / 2),
								Color = ColorPickerTextColor,
								Size = Theme.ElementFontSize,
								Visible = IsElementVisible,
							})
						end
						if Element._SwatchDrawing then
							local SwatchSize = Theme.ColorSwatchSize
							local SwatchAbsolutePosition = WindowPosition + Vector2.new(Element._SwatchPositionX, Element._SwatchPositionY - Window._ScrollOffset)
							ApplyDrawingProperties(Element._SwatchDrawing, {
								Position = SwatchAbsolutePosition,
								Size = Vector2.new(SwatchSize, SwatchSize),
								Visible = IsElementVisible,
							})

							if Element._ChevronDrawing then
								ApplyDrawingProperties(Element._ChevronDrawing, {
									Position = Vector2.new(SwatchAbsolutePosition.X - 14, SwatchAbsolutePosition.Y + (SwatchSize - Theme.ElementFontSize) / 2),
									Transparency = (Element._HoverFactor or 0) * 0.85,
									Color = Theme.DropdownArrow,
									Size = Theme.ElementFontSize,
									Visible = IsElementVisible and (Element._HoverFactor or 0) > 0.01,
								})
							end
						end
						if Element._SwatchBorderDrawing then
							local SwatchSize = Theme.ColorSwatchSize
							local SwatchAbsolutePosition = WindowPosition + Vector2.new(Element._SwatchPositionX, Element._SwatchPositionY - Window._ScrollOffset)
							local SwatchBorderColor = Theme.ColorPickerBorder:Lerp(Theme.ColorPickerSwatchHover, Element._HoverFactor or 0)
							local SwatchBorderThick = LerpValue(1, 2, Element._HoverFactor or 0)
							ApplyDrawingProperties(Element._SwatchBorderDrawing, {
								Position = SwatchAbsolutePosition,
								Size = Vector2.new(SwatchSize, SwatchSize),
								Color = SwatchBorderColor,
								Thickness = SwatchBorderThick,
								Visible = IsElementVisible,
							})
						end
					end
				end
			end

			Section._FullContentHeight = SectionContentHeight

			-- Section maximum height values are authored in design space, but the
			-- real window can shrink after viewport scaling. Clamp each section to
			-- the remaining body area so tall panels stay inside the window frame.
			local EffectiveMaxHeight = Section._MaxHeight
			if EffectiveMaxHeight then
				local AvailableSectionHeight = Theme.TitleBarHeight + Window._VisibleHeight - Section._PositionY - Theme.SectionPadding
				local MinimumSectionHeight = Theme.ElementHeight + Theme.ElementPadding
				EffectiveMaxHeight = math.min(EffectiveMaxHeight, math.max(MinimumSectionHeight, AvailableSectionHeight))
			end

			if EffectiveMaxHeight and SectionContentHeight > EffectiveMaxHeight then
				-- Store both the full canvas height and the clipped viewport height.
				-- The renderer uses the clipped height for the border, while input
				-- and scrollbar math keep using the full content height for scrolling.
				Section._ClippedHeight = EffectiveMaxHeight
				Section._SectionMaxScroll = SectionContentHeight - EffectiveMaxHeight + Theme.ElementHeight + Theme.ElementPadding
				Section._SectionScrollOffset = math.clamp(Section._SectionScrollOffset or 0, 0, Section._SectionMaxScroll)
				Section._ContentHeight = EffectiveMaxHeight
			else
				Section._ClippedHeight = nil
				Section._SectionMaxScroll = 0
				Section._SectionScrollOffset = 0
				Section._ContentHeight = SectionContentHeight
			end

			if not UseImmediateMode then
				local SectionAbsolutePosition = WindowPosition + Vector2.new(Section._PositionX, Section._PositionY - Window._ScrollOffset)
				local SectionFullSize = Vector2.new(Section._Width, Section._ContentHeight)
				local SectionHeaderSize = Vector2.new(Section._Width, Theme.ElementHeight)

				local IsSectionVisible = (SectionAbsolutePosition.Y + Section._ContentHeight > ViewportStart) and (SectionAbsolutePosition.Y < ViewportEnd) and Window._Visible

				local CurrentMousePos = GetMouseLocation(UserInputService)
				Section._IsHovered = IsPointInsideRectangle(CurrentMousePos, SectionAbsolutePosition, SectionHeaderSize)

				if Section._FullBackground then
					local ClippedPos, ClippedSize = ClipRectangleToYRange(SectionAbsolutePosition, SectionFullSize, ViewportStart, ViewportEnd)
					if ClippedPos and ClippedSize then
						ApplyDrawingProperties(Section._FullBackground, { Position = ClippedPos, Size = ClippedSize, Color = Theme.SectionBodyBackground, Visible = IsSectionVisible })
					else
						ApplyDrawingProperties(Section._FullBackground, { Visible = false })
					end
				end

				if Section._Border then
					local BorderColor = Theme.WindowBorder:Lerp(Theme.WindowBorderHover, Section._HoverFactor or 0)
					local ClippedPos, ClippedSize = ClipRectangleToYRange(SectionAbsolutePosition, SectionFullSize, ViewportStart, ViewportEnd)
					if ClippedPos and ClippedSize then
						ApplyDrawingProperties(Section._Border, { Position = ClippedPos, Size = ClippedSize, Color = BorderColor, Visible = IsSectionVisible })
					else
						ApplyDrawingProperties(Section._Border, { Visible = false })
					end
				end

				if Section._Background then
					local HeaderBg = Theme.SectionBackground:Lerp(Theme.SectionBackgroundHover, Section._HoverFactor or 0)
					local ClippedPos, ClippedSize = ClipRectangleToYRange(SectionAbsolutePosition, SectionHeaderSize, ViewportStart, ViewportEnd)
					if ClippedPos and ClippedSize then
						ApplyDrawingProperties(Section._Background, { Position = ClippedPos, Size = ClippedSize, Color = HeaderBg, Visible = IsSectionVisible })
					else
						ApplyDrawingProperties(Section._Background, { Visible = false })
					end
				end

				if Section._AccentLine then
					local AccentAlpha = LerpValue(0.7, 1, Section._HoverFactor or 0)
					local FromPos = Vector2.new(SectionAbsolutePosition.X, SectionAbsolutePosition.Y + Theme.ElementHeight)
					local ToPos = Vector2.new(SectionAbsolutePosition.X + Section._Width, SectionAbsolutePosition.Y + Theme.ElementHeight)
					local ClippedFrom, ClippedTo = ClipHorizontalLineToYRange(FromPos, ToPos, ViewportStart, ViewportEnd)
					if ClippedFrom and ClippedTo then
						ApplyDrawingProperties(Section._AccentLine, {
							From = ClippedFrom,
							To = ClippedTo,
							Thickness = LerpValue(1, 2, Section._HoverFactor or 0),
							Transparency = AccentAlpha,
							Color = Theme.TitleBarSeparator,
							Visible = IsSectionVisible,
						})
					else
						ApplyDrawingProperties(Section._AccentLine, { Visible = false })
					end
				end

				if Section._LeftAccentLine then
					local LeftAccentColor = Theme.TitleBarSeparator:Lerp(Theme.SectionTextHover, Section._HoverFactor or 0)
					local FromPos = Vector2.new(SectionAbsolutePosition.X, SectionAbsolutePosition.Y)
					local ToPos = Vector2.new(SectionAbsolutePosition.X, SectionAbsolutePosition.Y + Section._ContentHeight)
					local ClippedFrom, ClippedTo = ClipVerticalLineToYRange(FromPos, ToPos, ViewportStart, ViewportEnd)
					if ClippedFrom and ClippedTo then
						ApplyDrawingProperties(Section._LeftAccentLine, {
							From = ClippedFrom,
							To = ClippedTo,
							Color = LeftAccentColor,
							Transparency = LerpValue(0.35, 0.7, Section._HoverFactor or 0),
							Thickness = 1,
							Visible = IsSectionVisible,
						})
					else
						ApplyDrawingProperties(Section._LeftAccentLine, { Visible = false })
					end
				end

				local SectionScrollbarGeometry = GetSectionScrollbarGeometry(Section, Window)
				if SectionScrollbarGeometry then
					local ScrollHandleColor = Theme.ScrollbarHandle:Lerp(Theme.ScrollbarHandleHover, Section._ScrollbarHoverFactor or 0)

					if Section._ScrollbarTrack then
						local TrackPos, TrackSize = ClipRectangleToYRange(
							SectionScrollbarGeometry.TrackPosition,
							SectionScrollbarGeometry.TrackSize,
							ViewportStart, ViewportEnd
						)
						if TrackPos and TrackSize then
							ApplyDrawingProperties(Section._ScrollbarTrack, {
								Position = TrackPos,
								Size = TrackSize,
								Color = Theme.ScrollbarBackground,
								Visible = IsSectionVisible,
							})
						else
							ApplyDrawingProperties(Section._ScrollbarTrack, { Visible = false })
						end
					end

					if Section._ScrollbarHandle then
						local HandlePos, HandleSize = ClipRectangleToYRange(
							SectionScrollbarGeometry.HandlePosition,
							SectionScrollbarGeometry.HandleSize,
							ViewportStart, ViewportEnd
						)
						if HandlePos and HandleSize then
							ApplyDrawingProperties(Section._ScrollbarHandle, {
								Position = HandlePos,
								Size = HandleSize,
								Color = ScrollHandleColor,
								Visible = IsSectionVisible,
							})
						else
							ApplyDrawingProperties(Section._ScrollbarHandle, { Visible = false })
						end
					end
				else
					if Section._ScrollbarTrack then
						ApplyDrawingProperties(Section._ScrollbarTrack, { Visible = false })
					end
					if Section._ScrollbarHandle then
						ApplyDrawingProperties(Section._ScrollbarHandle, { Visible = false })
					end
				end

				if Section._CornerBrackets then
					for BracketIndex = 1, #Section._CornerBrackets do
						ApplyDrawingProperties(Section._CornerBrackets[BracketIndex], { Visible = false })
					end
				end

				if Section._TopRightTechLine then
					ApplyDrawingProperties(Section._TopRightTechLine, { Visible = false })
				end

				if Section._TextLabel then
					local TitleColor = Theme.SectionText:Lerp(Theme.SectionTextHover, Section._HoverFactor or 0)
					local TitleY = SectionAbsolutePosition.Y + (Theme.ElementHeight - Theme.SectionFontSize) / 2
					local IsTitleVisible = IsSectionVisible and (TitleY >= ViewportStart) and (TitleY + Theme.SectionFontSize <= ViewportEnd)
					ApplyDrawingProperties(Section._TextLabel, {
						Position = Vector2.new(SectionAbsolutePosition.X + 10, TitleY),
						Color = TitleColor,
						Visible = IsTitleVisible,
					})
				end
			end

			local SectionLayoutHeight = Section._ContentHeight or SectionContentHeight
			if IsColumnOne then
				ColumnOnePositionY = ColumnOnePositionY + SectionLayoutHeight + Theme.SectionPadding
			else
				ColumnTwoPositionY = ColumnTwoPositionY + SectionLayoutHeight + Theme.SectionPadding
			end
		end

		local ContentHeight = math.max(ColumnOnePositionY, ColumnTwoPositionY)
		Window._CanvasHeight = ContentHeight
		local AvailableContentViewportHeight = GetWindowContentViewportHeight(Window)
		Window._MaxScroll = math.max(0, ContentHeight - AvailableContentViewportHeight)
		Window._ScrollOffset = math.clamp(Window._ScrollOffset, 0, Window._MaxScroll)

		Window._TotalHeight = Theme.TitleBarHeight + Window._VisibleHeight

		local BodyPosition = Vector2.new(WindowPosition.X, WindowPosition.Y + Theme.TitleBarHeight)

		local BodySize = Vector2.new(Theme.WindowWidth, Window._VisibleHeight)

		if not UseImmediateMode then
			ApplyDrawingProperties(WindowBodyBackgroundDrawing, { Position = BodyPosition, Size = BodySize, Color = Theme.WindowBackground })
			ApplyDrawingProperties(WindowBodyTopSheenDrawing, {
				Position = BodyPosition,
				Size = Vector2.new(Theme.WindowWidth, math.min(58, Window._VisibleHeight * 0.24)),
				Color = Theme.WindowSurfaceHighlight,
				Visible = Window._Visible,
			})
			ApplyDrawingProperties(WindowBodyBottomShadeDrawing, {
				Position = BodyPosition + Vector2.new(0, math.max(0, Window._VisibleHeight - 72)),
				Size = Vector2.new(Theme.WindowWidth, math.min(72, Window._VisibleHeight)),
				Color = Theme.WindowSurfaceShade,
				Visible = Window._Visible,
			})
			ApplyDrawingProperties(WindowBodyBorderDrawing, { Position = BodyPosition, Size = BodySize, Color = Theme.WindowBorder })

			if Window._TabBarHeight > 0 then
				if Window._TabBarBackgroundDrawing then
					ApplyDrawingProperties(Window._TabBarBackgroundDrawing, {
						Position = WindowPosition + Vector2.new(0, Theme.TitleBarHeight),
						Size = Vector2.new(Theme.WindowWidth, Window._TabBarHeight),
						Color = Theme.WindowBackground,
						Visible = Window._Visible,
					})
				end
				if Window._TabBarSeparatorDrawing then
					ApplyDrawingProperties(Window._TabBarSeparatorDrawing, {
						From = WindowPosition + Vector2.new(0, Theme.TitleBarHeight + Window._TabBarHeight),
						To = WindowPosition + Vector2.new(Theme.WindowWidth, Theme.TitleBarHeight + Window._TabBarHeight),
						Transparency = 0.22,
						Visible = Window._Visible,
					})
				end

				local TabCount = #Window._Pages
				local TabBarPadding = 10
				local TabGap = 6
				local TabWidth = math.max(92, (Theme.WindowWidth - (TabBarPadding * 2) - (TabGap * (math.min(TabCount, 5) - 1))) / math.min(TabCount, 5))
				local MaxTabScroll = math.max(0, (TabCount * (TabWidth + TabGap)) - TabGap - (Theme.WindowWidth - TabBarPadding * 2))
				Window._TabScrollOffset = math.clamp(Window._TabScrollOffset or 0, 0, MaxTabScroll)

				for PageIndex, Page in ipairs(Window._Pages) do
					local TabDrawings = Window._TabDrawings[PageIndex]
					if TabDrawings then
						local TabX = WindowPosition.X + TabBarPadding + (PageIndex - 1) * (TabWidth + TabGap) - Window._TabScrollOffset
						local TabY = WindowPosition.Y + Theme.TitleBarHeight + 5
						local TabHeight = Window._TabBarHeight - 10
						
						local TabVisible = Window._Visible
						if TabX < WindowPosition.X - TabWidth or TabX > WindowPosition.X + Theme.WindowWidth then
							TabVisible = false
						end

						local TextSize = GetTextBounds(Page.Title, Theme.ElementFontSize)
						local TextX = TabX + (TabWidth - TextSize.X) / 2
						local TextY = TabY + (TabHeight - TextSize.Y) / 2

						local IsActive = (PageIndex == Window._ActivePageIndex)
						local HoverFactor = Page._HoverFactor or 0
						local ActiveFactor = IsActive and 1 or 0
						local TabBackgroundColor = Theme.TabBackground:Lerp(Theme.TabBackgroundHover, HoverFactor):Lerp(Theme.TabBackgroundActive, ActiveFactor)
						local TabBorderColor = Theme.WindowBorder:Lerp(Theme.TitleBarSeparator, math.max(HoverFactor, ActiveFactor) * 0.75)
						
						local BaseColor = IsActive and Theme.TitleBarText or Theme.LabelText
						local TargetColor = IsActive and Theme.TitleBarTextHover or Theme.LabelTextHover
						local TabColor = BaseColor:Lerp(TargetColor, HoverFactor)

						if TabDrawings.BackgroundDrawing then
							ApplyDrawingProperties(TabDrawings.BackgroundDrawing, {
								Position = Vector2.new(TabX, TabY),
								Size = Vector2.new(TabWidth, TabHeight),
								Color = TabBackgroundColor,
								Transparency = IsActive and 0.98 or 0.68 + HoverFactor * 0.18,
								Visible = TabVisible,
							})
						end

						ApplyDrawingProperties(TabDrawings.TextDrawing, {
							Text = Page.Title,
							Position = Vector2.new(TextX, TextY),
							Color = TabColor,
							Visible = TabVisible,
						})

						if TabVisible and (IsActive or HoverFactor > 0.01) then
							local UnderlineY = TabY + TabHeight - 2
							local UnderlineWidth = math.min(TabWidth - 18, TextSize.X + 18)
							local UnderlineX = TabX + (TabWidth - UnderlineWidth) / 2
							local UnderlineAlpha = IsActive and 1 or HoverFactor
							local UnderlineColor = Theme.TitleBarSeparator:Lerp(TabBorderColor, HoverFactor)

							ApplyDrawingProperties(TabDrawings.UnderlineDrawing, {
								From = Vector2.new(UnderlineX, UnderlineY),
								To = Vector2.new(UnderlineX + UnderlineWidth, UnderlineY),
								Color = UnderlineColor,
								Transparency = UnderlineAlpha,
								Visible = TabVisible,
							})
						else
							ApplyDrawingProperties(TabDrawings.UnderlineDrawing, { Visible = false })
						end
					end
				end
				if MaxTabScroll > 0 and Window._TabScrollbarDrawing then
					local ScrollProgress = Window._TabScrollOffset / MaxTabScroll
					local AvailableTabWidth = Theme.WindowWidth - TabBarPadding * 2
					local HandleWidth = math.clamp((AvailableTabWidth / (TabCount * (TabWidth + TabGap))) * AvailableTabWidth, 30, AvailableTabWidth)
					local HandleX = WindowPosition.X + TabBarPadding + (AvailableTabWidth - HandleWidth) * ScrollProgress
					local HandleY = WindowPosition.Y + Theme.TitleBarHeight + Window._TabBarHeight - 1.5

					ApplyDrawingProperties(Window._TabScrollbarDrawing, {
						From = Vector2.new(HandleX, HandleY),
						To = Vector2.new(HandleX + HandleWidth, HandleY),
						Color = Theme.TitleBarSeparator,
						Transparency = 1,
						Visible = Window._Visible,
					})
				elseif Window._TabScrollbarDrawing then
					ApplyDrawingProperties(Window._TabScrollbarDrawing, { Visible = false })
				end
			end

			if WindowBottomBorderDrawing then
				ApplyDrawingProperties(WindowBottomBorderDrawing, {
					Visible = false
				})
			end

			if WindowTopAccentDrawing then
				ApplyDrawingProperties(WindowTopAccentDrawing, {
					From = WindowPosition,
					To = Vector2.new(WindowPosition.X + Theme.WindowWidth, WindowPosition.Y),
					Color = Theme.TitleBarSeparator,
					Transparency = 0.55,
					Thickness = 1.25,
					Visible = Window._Visible
				})
			end


			ApplyDrawingProperties(TitleBarBackgroundDrawing, { Position = WindowPosition, Color = Theme.TitleBarBackground })
			ApplyDrawingProperties(TitleBarHighlightDrawing, {
				Position = WindowPosition,
				Size = Vector2.new(Theme.WindowWidth, math.max(6, Theme.TitleBarHeight * 0.45)),
				Color = Theme.TitleBarHighlight,
				Visible = Window._Visible,
			})
			ApplyDrawingProperties(TitleBarAccentWashDrawing, {
				Position = WindowPosition,
				Size = Vector2.new(Theme.WindowWidth * 0.58, Theme.TitleBarHeight),
				Color = Theme.TitleBarAccentWash,
				Visible = Window._Visible,
			})
			ApplyDrawingProperties(TitleBarBorderDrawing, { Position = WindowPosition, Color = Theme.WindowBorder })

			if TitleBarTextDrawing then
				SetRenderProperty(TitleBarTextDrawing, "Size", Theme.TitleFontSize)
				SetRenderProperty(TitleBarTextDrawing, "Position", Vector2.new(
					WindowPosition.X + Theme.InnerMargin + 12,
					WindowPosition.Y + (Theme.TitleBarHeight - Theme.TitleFontSize) / 2 + 2
				))
				SetRenderProperty(TitleBarTextDrawing, "Color", Window._TitleTextHovered and Theme.TitleBarTextHover or Theme.TitleBarText)
			end

			if TitleAccentCircleDrawing then
				SetRenderProperty(TitleAccentCircleDrawing, "Position", Vector2.new(
					WindowPosition.X + Theme.InnerMargin + 4,
					WindowPosition.Y + Theme.TitleBarHeight / 2
				))
				SetRenderProperty(TitleAccentCircleDrawing, "Color", Theme.TitleBarSeparator)
			end

			if TitleAccentOuterGlowCircleDrawing then
				SetRenderProperty(TitleAccentOuterGlowCircleDrawing, "Position", Vector2.new(
					WindowPosition.X + Theme.InnerMargin + 4,
					WindowPosition.Y + Theme.TitleBarHeight / 2
				))
				SetRenderProperty(TitleAccentOuterGlowCircleDrawing, "Color", Theme.TitleBarSeparator)
			end

			if TitleBarSeparatorDrawing then
				ApplyDrawingProperties(TitleBarSeparatorDrawing, {
					From = Vector2.new(WindowPosition.X, WindowPosition.Y + Theme.TitleBarHeight),
					To = Vector2.new(WindowPosition.X + Theme.WindowWidth, WindowPosition.Y + Theme.TitleBarHeight),
				})
			end

			if Window._GlowDrawings then
				local FullWindowSize = Vector2.new(Theme.WindowWidth, Theme.TitleBarHeight + Window._VisibleHeight)
				for GlowIndex = 1, #Window._GlowDrawings do
					ApplyDrawingProperties(Window._GlowDrawings[GlowIndex], {
						Position = WindowPosition - Vector2.new(GlowIndex, GlowIndex),
						Size = FullWindowSize + Vector2.new(GlowIndex * 2, GlowIndex * 2),
						Visible = Window._Visible,
					})
				end
			end

			if Window._CornerBrackets then
				local BracketDrawings = Window._CornerBrackets
				for BracketIndex = 1, #BracketDrawings do
					ApplyDrawingProperties(BracketDrawings[BracketIndex], { Visible = false })
				end
			end

			if Window._SideTicks then
				for TickIndex = 1, #Window._SideTicks do
					ApplyDrawingProperties(Window._SideTicks[TickIndex], { Visible = false })
				end
			end

			if Window._ResizeGripLines then
				local ResizeGripBasePosition = Vector2.new(
					WindowPosition.X + Theme.WindowWidth - 18,
					WindowPosition.Y + Theme.TitleBarHeight + Window._VisibleHeight - 18
				)
				local ResizeGripColor = Window._ResizeGripHovered and Theme.TitleBarTextHover or Theme.TitleBarSeparator
				for ResizeGripLineIndex, ResizeGripLineObject in ipairs(Window._ResizeGripLines) do
					local ResizeGripOffset = ResizeGripLineIndex * 4
					ApplyDrawingProperties(ResizeGripLineObject, {
						From = ResizeGripBasePosition + Vector2.new(18 - ResizeGripOffset, 18),
						To = ResizeGripBasePosition + Vector2.new(18, 18 - ResizeGripOffset),
						Color = ResizeGripColor,
						Transparency = Window._ResizeGripHovered and 0.9 or 0.42,
						Visible = Window._Visible,
					})
				end
			end
		end

		local CloseButtonSize = 24
		local CloseButtonPosX = WindowPosition.X + Theme.WindowWidth - CloseButtonSize - 10
		local CloseButtonPosY = WindowPosition.Y + (Theme.TitleBarHeight - CloseButtonSize) / 2
		Window._CloseButtonRegion = {
			Position = Vector2.new(CloseButtonPosX, CloseButtonPosY),
			Size = Vector2.new(CloseButtonSize, CloseButtonSize)
		}

		local SearchButtonSize = 24
		local SearchButtonPosX = CloseButtonPosX - SearchButtonSize - 8
		local SearchButtonPosY = CloseButtonPosY
		Window._SearchButtonRegion = {
			Position = Vector2.new(SearchButtonPosX, SearchButtonPosY),
			Size = Vector2.new(SearchButtonSize, SearchButtonSize)
		}

		if not UseImmediateMode then
			if Window._SearchIconCircle and Window._SearchIconLine then
				local CenterPoint = Window._SearchButtonRegion.Position + Vector2.new(11, 11)
				local MouseIsOverSearch = IsPointInsideRectangle(GetMouseLocation(UserInputService), Window._SearchButtonRegion.Position, Window._SearchButtonRegion.Size)
				local SearchIconColor = Window._SearchActive and Theme.TitleBarSeparator or (MouseIsOverSearch and Theme.TitleBarTextHover or Theme.TitleBarText)

				ApplyDrawingProperties(Window._SearchIconCircle, {
					Position = CenterPoint,
					Color = SearchIconColor,
					Visible = Window._Visible,
				})
				ApplyDrawingProperties(Window._SearchIconLine, {
					From = CenterPoint + Vector2.new(3, 3),
					To = CenterPoint + Vector2.new(8, 8),
					Color = SearchIconColor,
					Visible = Window._Visible,
				})
			end

			if Window._SearchActive then
				local SearchBarPosition = WindowPosition + Vector2.new(Theme.InnerMargin, Theme.TitleBarHeight + Window._TabBarHeight + 6)
				local SearchBarSize = Vector2.new(Theme.WindowWidth - Theme.InnerMargin * 2, 20)
				Window._SearchTextBoxRegion = { Position = SearchBarPosition, Size = SearchBarSize }

				local SearchTextBorderColor = Window._SearchTextBox._IsFocused and Theme.TextBoxBorderFocused or Theme.TextBoxBorder
				ApplyDrawingProperties(Window._SearchBackgroundDrawing, { Position = SearchBarPosition, Size = SearchBarSize, Color = Theme.TextBoxBackground, Visible = Window._Visible })
				ApplyDrawingProperties(Window._SearchBorderDrawing, { Position = SearchBarPosition, Size = SearchBarSize, Color = SearchTextBorderColor, Visible = Window._Visible })

				local TextboxIconCenter = SearchBarPosition + Vector2.new(12, 10)
				ApplyDrawingProperties(Window._SearchIconCircleDrawing, { Position = TextboxIconCenter, Visible = Window._Visible })
				ApplyDrawingProperties(Window._SearchIconLineDrawing, { From = TextboxIconCenter + Vector2.new(2.5, 2.5), To = TextboxIconCenter + Vector2.new(5.5, 5.5), Visible = Window._Visible })

				local HasSearchValue = Window._SearchTextBox._Value ~= ""
				local SearchDisplayText = HasSearchValue and Window._SearchTextBox._Value or Window._SearchTextBox._Placeholder

				local AvailableQueryWidth = SearchBarSize.X - 32
				local CharacterWidth = Theme.ElementFontSize * Theme.FontCharWidthRatio * 1.25
				local MaxQueryChars = math.max(1, math.floor(AvailableQueryWidth / CharacterWidth))
				SearchDisplayText = ClipEditableTextForWidth(SearchDisplayText, MaxQueryChars, Window._SearchTextBox._IsFocused)

				if Window._SearchTextBox._IsFocused and Window._SearchTextBox._CursorVisible then
					SearchDisplayText = string.format("%s|", SearchDisplayText)
				end

				ApplyDrawingProperties(Window._SearchTextDrawing, {
					Text = SearchDisplayText,
					Position = SearchBarPosition + Vector2.new(24, (20 - Theme.ElementFontSize) / 2),
					Color = HasSearchValue and Theme.TextBoxText or Theme.TextBoxPlaceholder,
					Size = Theme.ElementFontSize,
					Visible = Window._Visible
				})

				local SearchResultsCount = #Window._SearchResults
				if SearchResultsCount > 0 then
					local DropdownPosition = SearchBarPosition + Vector2.new(0, 20)
					local DropdownHeight = 24 * SearchResultsCount
					local DropdownSize = Vector2.new(SearchBarSize.X, DropdownHeight)
					Window._SearchDropdownRegion = { Position = DropdownPosition, Size = DropdownSize }

					ApplyDrawingProperties(Window._SearchDropdownBackgroundDrawing, { Position = DropdownPosition, Size = DropdownSize, Color = Theme.DropdownBackground, Visible = Window._Visible })
					ApplyDrawingProperties(Window._SearchDropdownBorderDrawing, { Position = DropdownPosition, Size = DropdownSize, Color = Theme.DropdownBorder, Visible = Window._Visible })

					if Window._HoveredSearchResultIndex then
						local HoverPositionY = DropdownPosition.Y + (Window._HoveredSearchResultIndex - 1) * 24
						ApplyDrawingProperties(Window._SearchDropdownHoverDrawing, {
							Position = Vector2.new(DropdownPosition.X, HoverPositionY),
							Size = Vector2.new(SearchBarSize.X, 24),
							Visible = Window._Visible
						})
					else
						ApplyDrawingProperties(Window._SearchDropdownHoverDrawing, { Visible = false })
					end

					for TextIndex = 1, 5 do
						local TextDrawingObject = Window._SearchDropdownTextDrawings[TextIndex]
						if TextIndex <= SearchResultsCount then
							local ResultItem = Window._SearchResults[TextIndex]
							local TextPosition = DropdownPosition + Vector2.new(10, (TextIndex - 1) * 24 + (24 - Theme.ElementFontSize) / 2)

							local DisplayResultText = ResultItem.Text
							local AvailableTextWidth = SearchBarSize.X - 20
							local MaxChars = math.max(1, math.floor(AvailableTextWidth / CharacterWidth))
							DisplayResultText = TruncateTextWithAsciiEllipsis(DisplayResultText, MaxChars)

							ApplyDrawingProperties(TextDrawingObject, {
								Text = DisplayResultText,
								Position = TextPosition,
								Size = Theme.ElementFontSize,
								Color = Theme.DropdownText,
								Visible = Window._Visible
							})
						else
							ApplyDrawingProperties(TextDrawingObject, { Visible = false })
						end
					end
				else
					Window._SearchDropdownRegion = nil
					ApplyDrawingProperties(Window._SearchDropdownBackgroundDrawing, { Visible = false })
					ApplyDrawingProperties(Window._SearchDropdownBorderDrawing, { Visible = false })
					ApplyDrawingProperties(Window._SearchDropdownHoverDrawing, { Visible = false })
					for TextIndex = 1, 5 do
						ApplyDrawingProperties(Window._SearchDropdownTextDrawings[TextIndex], { Visible = false })
					end
				end
			else
				Window._SearchTextBoxRegion = nil
				Window._SearchDropdownRegion = nil
				ApplyDrawingProperties(Window._SearchBackgroundDrawing, { Visible = false })
				ApplyDrawingProperties(Window._SearchBorderDrawing, { Visible = false })
				ApplyDrawingProperties(Window._SearchTextDrawing, { Visible = false })
				ApplyDrawingProperties(Window._SearchIconCircleDrawing, { Visible = false })
				ApplyDrawingProperties(Window._SearchIconLineDrawing, { Visible = false })
				ApplyDrawingProperties(Window._SearchDropdownBackgroundDrawing, { Visible = false })
				ApplyDrawingProperties(Window._SearchDropdownBorderDrawing, { Visible = false })
				ApplyDrawingProperties(Window._SearchDropdownHoverDrawing, { Visible = false })
				for TextIndex = 1, 5 do
					ApplyDrawingProperties(Window._SearchDropdownTextDrawings[TextIndex], { Visible = false })
				end
			end

			if Window._HighlightedElement then
				local HighlightElement = Window._HighlightedElement
				local ElapsedTime = tick() - HighlightElement._HighlightTime
				if ElapsedTime >= 2.0 then
					Window._HighlightedElement = nil
					ApplyDrawingProperties(Window._ElementHighlightDrawing, { Visible = false })
				else
					local HighlightAlpha = math.clamp(1 - (ElapsedTime / 2.0), 0, 1)
					local HighlightAbsolutePosition = WindowPosition + Vector2.new(HighlightElement._PositionX, HighlightElement._PositionY - Window._ScrollOffset)
					local HighlightAbsoluteSize = Vector2.new(HighlightElement._Width - (Window._MaxScroll > 0 and Theme.ScrollbarWidth + 4 or 0), HighlightElement._Height)

					ApplyDrawingProperties(Window._ElementHighlightDrawing, {
						Position = HighlightAbsolutePosition,
						Size = HighlightAbsoluteSize,
						Thickness = 2,
						Color = Theme.TitleBarSeparator,
						Transparency = HighlightAlpha,
						Visible = (HighlightAbsolutePosition.Y + HighlightElement._Height > ViewportStart) and (HighlightAbsolutePosition.Y < ViewportEnd) and Window._Visible
					})
				end
			end
		end

		if CloseButtonBackgroundDrawing then
			local CloseRegion = Window._CloseButtonRegion
			local CloseHoverFactor = Window._CloseButtonHoverFactor or 0
			local CloseColor = Theme.CloseButtonBackground:Lerp(Theme.CloseButtonHover, CloseHoverFactor)
			local BorderColor = Theme.CloseButtonBorder:Lerp(Theme.CloseButtonHover, CloseHoverFactor)

			ApplyDrawingProperties(CloseButtonBackgroundDrawing, {
				Position = CloseRegion.Position,
				Size = CloseRegion.Size,
				Color = CloseColor,
			})
			ApplyDrawingProperties(CloseButtonBorderDrawing, {
				Position = CloseRegion.Position,
				Size = CloseRegion.Size,
				Color = BorderColor,
			})
			
			local ButtonScale = Theme.TitleFontSize / 14
			local TextSize = math.floor(13 * ButtonScale)
			local TextBounds = GetTextBounds("X", TextSize)
			ApplyDrawingProperties(CloseButtonTextDrawing, {
				Position = CloseRegion.Position + (CloseRegion.Size - TextBounds) / 2,
				Color = Theme.TitleBarText:Lerp(Theme.TitleBarTextHover, CloseHoverFactor),
				Size = TextSize,
			})
		end

		if Window._ActiveColorPicker and Window._ActiveColorPicker._PopupPos then
			Window._ActiveColorPicker:_BuildPopupDrawings()
		end
	end

	local function UpdateElementsVisibility()
		if UseImmediateMode then return end
		local IsVisible = Window._Visible

		for DiscardIndex, Section in ipairs(Window._Sections) do
			local IsSectionVisible = IsVisible
			if IsVisible and Section._PageIndex and Section._PageIndex ~= Window._ActivePageIndex then
				IsSectionVisible = false
			end

			local VisibilityObjects = { Section._FullBackground, Section._Background, Section._Border, Section._TextLabel, Section._AccentLine, Section._LeftAccentLine }
			SetDrawingObjectsVisibility(VisibilityObjects, IsSectionVisible)
			if Section._TopRightTechLine then SetRenderProperty(Section._TopRightTechLine, "Visible", false) end
			if Section._CornerBrackets then
				for DiscardLineIndex, LineObject in ipairs(Section._CornerBrackets) do
					SetRenderProperty(LineObject, "Visible", false)
				end
			end

			for ElementIndex, Element in ipairs(Section._Elements) do
				if Element._Type == "TextLabel" then
					SetDrawingObjectsVisibility({ Element._AccentLineDrawing }, IsSectionVisible)
					for LineIndex, LineDrawingObject in ipairs(Element._LineDrawings or {}) do
						SetRenderProperty(LineDrawingObject, "Visible", IsSectionVisible)
					end

				elseif Element._Type == "TextButton" then
					SetDrawingObjectsVisibility({ Element._BackgroundDrawing, Element._BorderDrawing, Element._TextDrawing }, IsSectionVisible)
					if Element._AccentLineDrawing then SetRenderProperty(Element._AccentLineDrawing, "Visible", false) end

				elseif Element._Type == "Toggle" then
					SetDrawingObjectsVisibility({ Element._BackgroundDrawing, Element._BorderDrawing, Element._TextDrawing, Element._IndicatorDrawing }, IsSectionVisible)
					if Element._AccentLineDrawing then SetRenderProperty(Element._AccentLineDrawing, "Visible", IsSectionVisible and Element._Value == true) end

				elseif Element._Type == "TextBox" then
					SetDrawingObjectsVisibility({ Element._BackgroundDrawing, Element._BorderDrawing, Element._LabelDrawing, Element._TextDrawing }, IsSectionVisible)
					if Element._AccentLineDrawing then SetRenderProperty(Element._AccentLineDrawing, "Visible", false) end
					if Element._SelectionDrawing then SetRenderProperty(Element._SelectionDrawing, "Visible", false) end
					if Element._CursorDrawing then SetRenderProperty(Element._CursorDrawing, "Visible", false) end

				elseif Element._Type == "Dropdown" then
					SetDrawingObjectsVisibility({ Element._BackgroundDrawing, Element._BorderDrawing, Element._TextDrawing, Element._ArrowDrawing }, IsSectionVisible)
					if Element._AccentLineDrawing then SetRenderProperty(Element._AccentLineDrawing, "Visible", false) end

					local ItemsAreVisible = IsSectionVisible and Element._Expanded
					for ItemIndex, ItemData in ipairs(Element._ItemDrawingObjects) do
						SetDrawingObjectsVisibility({ ItemData.BackgroundDrawing, ItemData.TextDrawing, ItemData.SeparatorDrawing }, ItemsAreVisible)
					end

				elseif Element._Type == "Slider" then
					SetDrawingObjectsVisibility({
						Element._LabelDrawing, Element._ValueTextDrawing,
						Element._TrackBackgroundDrawing, Element._TrackBorderDrawing,
						Element._TrackFillDrawing, Element._ThumbDrawing, Element._ThumbInnerDrawing,
					}, IsSectionVisible)

				elseif Element._Type == "ColorPicker" then
					SetDrawingObjectsVisibility({ Element._LabelDrawing, Element._SwatchDrawing, Element._SwatchBorderDrawing }, IsSectionVisible)
					if Element._HoverBackgroundDrawing then SetRenderProperty(Element._HoverBackgroundDrawing, "Visible", false) end
					if Element._AccentLineDrawing then SetRenderProperty(Element._AccentLineDrawing, "Visible", false) end
					if Element._ChevronDrawing then SetRenderProperty(Element._ChevronDrawing, "Visible", false) end

					if not IsSectionVisible and Window._ActiveColorPicker == Element then
						Element:ClosePopup()
					end
				end
			end
		end
	end

	local function SetEntireWindowVisibility(IsVisible)
		if UseImmediateMode then
			Window._Visible = IsVisible
			return
		end

		Window._Visible = IsVisible
		SetDrawingObjectsVisibility(Window._DrawingObjects, IsVisible)
		if Window._CornerBrackets then
			for BracketIndex = 1, #Window._CornerBrackets do
				SetRenderProperty(Window._CornerBrackets[BracketIndex], "Visible", false)
			end
		end
		if Window._SideTicks then
			for TickIndex = 1, #Window._SideTicks do
				SetRenderProperty(Window._SideTicks[TickIndex], "Visible", false)
			end
		end
		UpdateElementsVisibility()
	end

	function Window:SetVisible(IsVisible)
		SetEntireWindowVisibility(IsVisible)
	end

	function Window:GetGeometry()
		-- Configuration code should not read private window fields directly.
		-- This method returns only the stable values that are safe to persist
		-- between launches: screen position and the current resizable dimensions.
		return {
			PositionX = Window._Position.X,
			PositionY = Window._Position.Y,
			WindowWidth = Theme.WindowWidth,
			WindowVisibleHeight = Window._VisibleHeight,
		}
	end

	function GetTextBounds(Text, FontSize)
		-- Drawing does not expose reliable text bounds in every backend, so this
		-- estimate is used consistently by layout and centering code.
		local Ratio = Theme.FontCharWidthRatio or 0.52
		local CharWidth = FontSize * (Ratio * 1.15)
		return Vector2.new(#Text * CharWidth, FontLineHeight(FontSize))
	end

	local function GetCenteredTextPosition(Text, FontSize, RectanglePosition, RectangleSize)
		-- Single source for centering Drawing text inside rectangular controls.
		-- This prevents every button from carrying its own width estimate.
		local TextBounds = GetTextBounds(Text, FontSize)
		return RectanglePosition + Vector2.new(
			(RectangleSize.X - TextBounds.X) / 2,
			(RectangleSize.Y - TextBounds.Y) / 2
		)
	end

	local function ApplyCenteredTextDrawing(TextDrawing, Text, FontSize, RectanglePosition, RectangleSize)
		ApplyDrawingProperties(TextDrawing, {
			Text = Text,
			Size = FontSize,
			Position = GetCenteredTextPosition(Text, FontSize, RectanglePosition, RectangleSize),
			Visible = true,
		})
	end

	local function DrawImmediateCenteredText(RectanglePosition, RectangleSize, FontSize, TextColor, Transparency, Text)
		DrawingImmediateText(
			GetCenteredTextPosition(Text, FontSize, RectanglePosition, RectangleSize),
			Theme.Font,
			FontSize,
			TextColor,
			Transparency or 1,
			Text,
			false
		)
	end

	function Window:CreatePage(PageConfig)
		-- Pages become tabs. Sections created through a page are scoped to that
		-- page and hidden when another page is active.
		PageConfig = PageConfig or {}
		PageConfig.Title = PageConfig.Title or "Page"

		local PageIndex = #Window._Pages + 1
		local Page = {
			Title = PageConfig.Title,
			Sections = {},
			_Index = PageIndex,
			_HoverFactor = 0,
		}

		Window._TabBarHeight = 34

		if #Window._Pages == 0 then
			Window._ActivePageIndex = 1
		end

		table.insert(Window._Pages, Page)

		if #Window._Pages == 1 then
			for DiscardSectionIndex, SectionObject in ipairs(Window._Sections) do
				if not SectionObject._PageIndex then
					SectionObject._PageIndex = 1
					table.insert(Page.Sections, SectionObject)
				end
			end
		end

		if not UseImmediateMode and DrawingBackendAvailable then
			if not Window._TabBarBackgroundDrawing then
				Window._TabBarBackgroundDrawing = CreateRectangleDrawing(Theme.TitleBarBackground, true, 4, 0.97)
				Window._TabBarSeparatorDrawing = CreateTrackedDrawingObject("Line")
				ApplyDrawingProperties(Window._TabBarSeparatorDrawing, {
					Thickness = 2,
					Transparency = 0.85,
					Color = Theme.TitleBarSeparator,
					ZIndex = 4,
					Visible = false,
				})
				Window._TabScrollbarDrawing = CreateTrackedDrawingObject("Line")
				ApplyDrawingProperties(Window._TabScrollbarDrawing, {
					Thickness = 3,
					Color = Theme.TitleBarSeparator,
					ZIndex = 6,
					Visible = false,
				})
				table.insert(Window._DrawingObjects, Window._TabBarBackgroundDrawing)
				table.insert(Window._DrawingObjects, Window._TabBarSeparatorDrawing)
				table.insert(Window._DrawingObjects, Window._TabScrollbarDrawing)
			end

			local TabBackground = CreateRectangleDrawing(Theme.TabBackground, true, 5, 0.75)
			ApplyDrawingProperties(TabBackground, { Visible = Window._Visible })

			local TabText = CreateTextDrawing(Page.Title, Theme.ElementFontSize, Theme.LabelText, 6)
			ApplyDrawingProperties(TabText, { Visible = Window._Visible })

			local TabUnderline = CreateTrackedDrawingObject("Line")
			ApplyDrawingProperties(TabUnderline, {
				Thickness = 2.5,
				Color = Theme.TitleBarSeparator,
				ZIndex = 7,
				Visible = false,
			})

			Window._TabDrawings[PageIndex] = {
				BackgroundDrawing = TabBackground,
				TextDrawing = TabText,
				UnderlineDrawing = TabUnderline,
			}

			table.insert(Window._DrawingObjects, TabBackground)
			table.insert(Window._DrawingObjects, TabText)
			table.insert(Window._DrawingObjects, TabUnderline)
		end

		function Page:CreateSection(SectionConfig)
			SectionConfig = SectionConfig or {}
			SectionConfig._PageIndex = PageIndex
			return Window:CreateSection(SectionConfig)
		end

		Window:RecalculateLayout()
		UpdateElementsVisibility()

		return Page
	end

	function Window:CreateSection(SectionConfig)
		-- Sections are vertical groups. A MaxHeight turns the section into an
		-- independently scrollable panel inside the window.
		SectionConfig = SectionConfig or {}
		SectionConfig.Title = SectionConfig.Title or "Section"

		local Section = {}
		Section._Title = SectionConfig.Title
		Section._Elements = {}
		Section._PositionY = 0
		Section._Width = 0
		Section._IsHovered = false
		Section._MaxHeight = SectionConfig.MaxHeight or nil
		Section._SectionScrollOffset = 0
		Section._SectionMaxScroll = 0
		Section._DraggingScrollbar = false
		Section._ScrollbarHovered = false

		local PageIndex = SectionConfig._PageIndex
		if not PageIndex and #Window._Pages > 0 then
			PageIndex = 1
		end

		if PageIndex then
			Section._PageIndex = PageIndex
			table.insert(Window._Pages[PageIndex].Sections, Section)
		end

		if not UseImmediateMode and DrawingBackendAvailable then
			Section._FullBackground = CreateRectangleDrawing(Theme.SectionBodyBackground, true, 4, 1)
			Section._Background = CreateRectangleDrawing(Theme.SectionBackground, true, 5, 0.95)
			Section._Border = CreateRectangleDrawing(Theme.WindowBorder, false, 6, 0.6)
			Section._TextLabel = CreateTextDrawing(SectionConfig.Title, Theme.SectionFontSize, Theme.SectionText, 7)
			Section._AccentLine = CreateTrackedDrawingObject("Line")
			ApplyDrawingProperties(Section._AccentLine, {
				Thickness = 1,
				Transparency = 0.7,
				Color = Theme.TitleBarSeparator,
				ZIndex = 8,
				Visible = true,
			})
			Section._LeftAccentLine = CreateTrackedDrawingObject("Line")
			ApplyDrawingProperties(Section._LeftAccentLine, {
				Thickness = 2,
				Transparency = 0.8,
				Color = Theme.TitleBarSeparator,
				ZIndex = 8,
				Visible = true,
			})
			Section._CornerBrackets = {}
			for BracketIndex = 1, 4 do
				Section._CornerBrackets[BracketIndex] = CreateTrackedDrawingObject("Line")
				ApplyDrawingProperties(Section._CornerBrackets[BracketIndex], {
					Thickness = 1.25,
					Color = Theme.TitleBarSeparator,
					Transparency = 0.5,
					ZIndex = 8,
					Visible = true,
				})
			end

			Section._TopRightTechLine = CreateTrackedDrawingObject("Line")
			ApplyDrawingProperties(Section._TopRightTechLine, {
				Thickness = 1,
				Transparency = 0.35,
				Color = Theme.TitleBarSeparator,
				ZIndex = 8,
				Visible = true,
			})

			if Section._MaxHeight then
				Section._ScrollbarTrack = CreateRectangleDrawing(Theme.ScrollbarBackground, true, 8, 1)
				Section._ScrollbarHandle = CreateRectangleDrawing(Theme.ScrollbarHandle, true, 9, 1)
			end
		end

		function Section:CreateTextLabel(LabelConfig)
			-- Text labels can wrap across multiple Drawing text objects and can be
			-- clicked for copy-style callbacks.
			LabelConfig = LabelConfig or {}
			LabelConfig.Text = LabelConfig.Text or "Label"
			LabelConfig.Callback = LabelConfig.Callback or function() end

			local Element = {}
			Element._Type = "TextLabel"
			Element._Height = TextBlockHeight(1, Theme.ElementFontSize)
			Element._Text = LabelConfig.Text
			Element._Callback = LabelConfig.Callback
			Element._PositionX = 0
			Element._PositionY = 0
			Element._Width = 0
			Element._IsHovered = false

			Element._LineDrawings = {}

			if not UseImmediateMode and DrawingBackendAvailable then

				Element._TextDrawing = nil
				Element._AccentLineDrawing = CreateTrackedDrawingObject("Line")
				ApplyDrawingProperties(Element._AccentLineDrawing, {
					Thickness = 1,
					Transparency = 0.4,
					Color = Theme.SectionText,
					ZIndex = 10,
					Visible = true,
				})
			end

			local function DestroyLineDrawings()
				-- Wrapped text is rebuilt when width or text changes, so stale line
				-- objects must be removed before creating new ones.
				for LineIndex, LineDrawingObject in ipairs(Element._LineDrawings) do
					DestroyDrawing(LineDrawingObject, WindowTrackedDrawings)
				end
				Element._LineDrawings = {}
			end

			function Element:_RebuildLineDrawings(WrappedLines)
				DestroyLineDrawings()
				if UseImmediateMode or not DrawingBackendAvailable then return end
				for LineIndex, LineText in ipairs(WrappedLines) do
					local LineDrawingObject = CreateTextDrawing(LineText, Theme.ElementFontSize, Theme.LabelText, 10)
					table.insert(Element._LineDrawings, LineDrawingObject)
				end
			end

			function Element:SetText(NewText)
				Element._Text = NewText

				if Element._Width > 0 then
					local AvailWidth   = TextAvailableWidth(Element._Width, Theme.ElementFontSize)
					local WrappedLines = WrapText(NewText, AvailWidth, Theme.ElementFontSize)
					Element._WrappedLines = WrappedLines
					Element._Height = TextBlockHeight(#WrappedLines, Theme.ElementFontSize)
					Element:_RebuildLineDrawings(WrappedLines)
				end
				Window:RecalculateLayout()
			end

			table.insert(Section._Elements, Element)
			Window:RecalculateLayout()
			return Element
		end

		function Section:CreateTextBox(TextBoxConfig)
			-- Text boxes support focus, selection, clipboard paste, cursor blink,
			-- and callback updates when their value changes.
			TextBoxConfig = TextBoxConfig or {}
			TextBoxConfig.Text = TextBoxConfig.Text or "TextBox"
			TextBoxConfig.Default = TextBoxConfig.Default or ""
			TextBoxConfig.Placeholder = TextBoxConfig.Placeholder or string.format("Type here%s", AsciiEllipsis)
			TextBoxConfig.Callback = TextBoxConfig.Callback or function() end

			local Element = {}
			Element._Type = "TextBox"
			Element._Height = Theme.ElementHeight
			Element._Text = TextBoxConfig.Text
			Element._Value = TextBoxConfig.Default
			Element._Placeholder = TextBoxConfig.Placeholder
			Element._Callback = TextBoxConfig.Callback
			Element._IsFocused = false
			Element._IsSelected = false
			Element._PositionX = 0
			Element._PositionY = 0
			Element._Width = 0

			Element._CursorVisible = false
			Element._CursorBlinkTime = 0
			Element._IsHovered = false

			if not UseImmediateMode and DrawingBackendAvailable then
				Element._BackgroundDrawing = CreateRectangleDrawing(Theme.TextBoxBackground, true, 10, 0.95)
				Element._BorderDrawing = CreateRectangleDrawing(Theme.TextBoxBorder, false, 11, 0.7)
				Element._LabelDrawing = CreateTextDrawing(string.format("%s: ", TextBoxConfig.Text), Theme.ElementFontSize, Theme.LabelText, 12)
				Element._TextDrawing = CreateTextDrawing(TextBoxConfig.Default ~= "" and TextBoxConfig.Default or TextBoxConfig.Placeholder, Theme.ElementFontSize, TextBoxConfig.Default ~= "" and Theme.TextBoxText or Theme.TextBoxPlaceholder, 12)
				Element._AccentLineDrawing = CreateTrackedDrawingObject("Line")
				ApplyDrawingProperties(Element._AccentLineDrawing, {
					Thickness = 2,
					Transparency = 0,
					Color = Theme.TextBoxBorderFocused,
					ZIndex = 12,
					Visible = false,
				})

				Element._CursorDrawing = CreateTrackedDrawingObject("Line")
				ApplyDrawingProperties(Element._CursorDrawing, {
					Thickness = 1,
					Transparency = 1,
					Color = Theme.TextBoxCursor,
					ZIndex = 13,
					Visible = false,
				})
				Element._SelectionDrawing = CreateRectangleDrawing(Theme.TextBoxSelection, true, 11, 0.5)
				ApplyDrawingProperties(Element._SelectionDrawing, { Visible = false })
			end

			function Element:SetValue(NewValue)
				Element._Value = NewValue
				if Element._TextDrawing then
					local HasValue = NewValue ~= ""
					SetRenderProperty(Element._TextDrawing, "Text", HasValue and NewValue or Element._Placeholder)
					SetRenderProperty(Element._TextDrawing, "Color", HasValue and Theme.TextBoxText or Theme.TextBoxPlaceholder)
				end
				InvokeCallback(Element._Callback, NewValue)
			end

			function Element:GetValue()
				return Element._Value
			end

			table.insert(Section._Elements, Element)
			Window:RecalculateLayout()
			return Element
		end

		function Section:CreateTextButton(ButtonConfig)
			-- Buttons are simple clickable commands with hover animation and an
			-- optional accent line.
			ButtonConfig = ButtonConfig or {}
			ButtonConfig.Text = ButtonConfig.Text or "Button"
			ButtonConfig.Callback = ButtonConfig.Callback or function() end

			local Element = {}
			Element._Type = "TextButton"
			Element._Height = Theme.ElementHeight
			Element._Text = ButtonConfig.Text
			Element._Callback = ButtonConfig.Callback
			Element._IsHovered = false
			Element._PositionX = 0
			Element._PositionY = 0
			Element._Width = 0

			if not UseImmediateMode and DrawingBackendAvailable then
				Element._BackgroundDrawing = CreateRectangleDrawing(Theme.ButtonBackground, true, 10, 0.95)
				Element._BorderDrawing = CreateRectangleDrawing(Theme.ButtonBorder, false, 11, 0.7)
				Element._TextDrawing = CreateTextDrawing(ButtonConfig.Text, Theme.ElementFontSize, Theme.ButtonText, 12)
				Element._AccentLineDrawing = CreateTrackedDrawingObject("Line")
				ApplyDrawingProperties(Element._AccentLineDrawing, {
					Thickness = 2,
					Transparency = 0,
					Color = Theme.SectionText,
					ZIndex = 13,
					Visible = false,
				})
			end

			function Element:SetText(NewText)
				Element._Text = NewText
				if Element._TextDrawing then
					SetRenderProperty(Element._TextDrawing, "Text", NewText)
				end
				Window:RecalculateLayout()
			end

			table.insert(Section._Elements, Element)
			Window:RecalculateLayout()
			return Element
		end

		function Section:CreateToggle(ToggleConfig)
			-- Toggles store a boolean value and expose SetValue/GetValue helpers so
			-- external configuration code can synchronize them.
			ToggleConfig = ToggleConfig or {}
			ToggleConfig.Text = ToggleConfig.Text or "Toggle"
			ToggleConfig.Default = ToggleConfig.Default ~= nil and ToggleConfig.Default or false
			ToggleConfig.Callback = ToggleConfig.Callback or function() end

			local Element = {}
			Element._Type = "Toggle"
			Element._Height = Theme.ElementHeight
			Element._Text = ToggleConfig.Text
			Element._Value = ToggleConfig.Default
			Element._Callback = ToggleConfig.Callback
			Element._IsHovered = false
			Element._PositionX = 0
			Element._PositionY = 0
			Element._Width = 0

			if not UseImmediateMode and DrawingBackendAvailable then
				Element._BackgroundDrawing = CreateRectangleDrawing(Theme.ButtonBackground, true, 10, 0.95)
				Element._BorderDrawing = CreateRectangleDrawing(Theme.ButtonBorder, false, 11, 0.7)
				Element._TextDrawing = CreateTextDrawing(ToggleConfig.Text, Theme.ElementFontSize, Theme.ButtonText, 12)

				Element._IndicatorDrawing = CreateTrackedDrawingObject("Circle")
				ApplyDrawingProperties(Element._IndicatorDrawing, {
					Filled = true,
					Radius = 5,
					NumSides = 20,
					Transparency = 1,
					ZIndex = 13,
					Visible = true,
					Color = ToggleConfig.Default and Theme.ToggleActive or Theme.ToggleInactive,
				})
				Element._AccentLineDrawing = CreateTrackedDrawingObject("Line")
				ApplyDrawingProperties(Element._AccentLineDrawing, {
					Thickness = 2,
					Transparency = 0,
					Color = Theme.ToggleActive,
					ZIndex = 14,
					Visible = ToggleConfig.Default == true,
				})
			end

			function Element:SetValue(NewValue, SuppressCallback)
				Element._Value = NewValue
				if Element._IndicatorDrawing then
					SetRenderProperty(Element._IndicatorDrawing, "Color",
						NewValue and Theme.ToggleActive or Theme.ToggleInactive)
				end
				if Element._AccentLineDrawing then
					SetRenderProperty(Element._AccentLineDrawing, "Visible", NewValue == true)
				end
				if not SuppressCallback then
					InvokeCallback(Element._Callback, NewValue)
				end
			end

			function Element:GetValue()
				return Element._Value
			end

			function Element:Toggle()
				Element:SetValue(not Element._Value)
			end

			table.insert(Section._Elements, Element)
			Window:RecalculateLayout()
			return Element
		end

		function Section:CreateDropdown(DropdownConfig)
			-- Dropdowns render their options below the main element and temporarily
			-- increase layout height while expanded.
			DropdownConfig = DropdownConfig or {}
			DropdownConfig.Text = DropdownConfig.Text or "Select"
			DropdownConfig.Options = DropdownConfig.Options or {}
			DropdownConfig.Default = DropdownConfig.Default or (DropdownConfig.Options[1] or "")
			DropdownConfig.Callback = DropdownConfig.Callback or function() end

			local Element = {}
			Element._Type = "Dropdown"
			Element._Height = Theme.ElementHeight
			Element._Text = DropdownConfig.Text
			Element._Options = DropdownConfig.Options
			Element._Value = DropdownConfig.Default
			Element._Callback = DropdownConfig.Callback
			Element._Expanded = false
			Element._IsHovered = false
			Element._ItemDrawingObjects = {}
			Element._PositionX = 0
			Element._PositionY = 0
			Element._Width = 0

			if not UseImmediateMode and DrawingBackendAvailable then
				Element._BackgroundDrawing = CreateRectangleDrawing(Theme.DropdownBackground, true, 10, 0.95)
				Element._BorderDrawing = CreateRectangleDrawing(Theme.DropdownBorder, false, 11, 0.7)
				Element._TextDrawing = CreateTextDrawing(string.format("%s: %s", DropdownConfig.Text, DropdownConfig.Default), Theme.ElementFontSize, Theme.DropdownText, 12)
				Element._ArrowDrawing = CreateTextDrawing("v", Theme.ElementFontSize, Theme.DropdownArrow, 12)
				Element._AccentLineDrawing = CreateTrackedDrawingObject("Line")
				ApplyDrawingProperties(Element._AccentLineDrawing, {
					Thickness = 2,
					Transparency = 0,
					Color = Theme.SectionText,
					ZIndex = 13,
					Visible = false,
				})
			end

			for OptionIndex, OptionText in ipairs(DropdownConfig.Options) do
				local ItemData = {
					Value = OptionText,
					_PositionX = 0,
					_PositionY = 0,
					_Width = 0,
				}

				if not UseImmediateMode and DrawingBackendAvailable then
					local ItemBackground = CreateRectangleDrawing(Theme.DropdownItemBackground, true, 20, 0.95)
					ApplyDrawingProperties(ItemBackground, { Visible = false })

					local ItemText = CreateTextDrawing(OptionText, Theme.ElementFontSize, Theme.DropdownText, 21)
					ApplyDrawingProperties(ItemText, { Visible = false })

					local ItemSeparator = CreateTrackedDrawingObject("Line")
					ApplyDrawingProperties(ItemSeparator, {
						Thickness = 1,
						Transparency = 0.5,
						Color = Theme.WindowBorder,
						ZIndex = 22,
						Visible = false,
					})

					ItemData.BackgroundDrawing = ItemBackground
					ItemData.TextDrawing = ItemText
					ItemData.SeparatorDrawing = ItemSeparator
				end

				table.insert(Element._ItemDrawingObjects, ItemData)
			end

			function Element:Toggle()
				-- Only one dropdown should be open at a time, which prevents option
				-- lists from overlapping each other.
				Element._Expanded = not Element._Expanded

				if Element._Expanded then
					if Window._ActiveDropdown and Window._ActiveDropdown ~= Element then
						Window._ActiveDropdown:Toggle()
					end
					Window._ActiveDropdown = Element
				else
					if Window._ActiveDropdown == Element then
						Window._ActiveDropdown = nil
					end
				end

				if Element._ArrowDrawing then
					SetRenderProperty(Element._ArrowDrawing, "Text", Element._Expanded and "^" or "v")
				end

				for ItemIndex, ItemData in ipairs(Element._ItemDrawingObjects) do
					local ShouldBeVisible = Element._Expanded and Window._Visible
					SetDrawingObjectsVisibility({ ItemData.BackgroundDrawing, ItemData.TextDrawing }, ShouldBeVisible)
				end

				Window:RecalculateLayout()
			end

			function Element:SetValue(NewValue)
				Element._Value = NewValue
				if Element._TextDrawing then
					SetRenderProperty(Element._TextDrawing, "Text", string.format("%s: %s", DropdownConfig.Text, NewValue))
				end
				InvokeCallback(Element._Callback, NewValue)
			end

			function Element:GetValue()
				return Element._Value
			end

			table.insert(Section._Elements, Element)
			Window:RecalculateLayout()
			return Element
		end

		function Section:CreateSlider(SliderConfig)
			-- Sliders map horizontal mouse position to a snapped numeric value.
			SliderConfig = SliderConfig or {}
			SliderConfig.Text = SliderConfig.Text or "Slider"
			SliderConfig.Min = SliderConfig.Min or 0
			SliderConfig.Max = SliderConfig.Max or 100
			SliderConfig.Default = SliderConfig.Default or SliderConfig.Min
			SliderConfig.Increment = SliderConfig.Increment or 1
			SliderConfig.Callback = SliderConfig.Callback or function() end

			local Element = {}
			Element._Type = "Slider"
			Element._Height = Theme.ElementHeight + 10
			Element._Text = SliderConfig.Text
			Element._MinValue = SliderConfig.Min
			Element._MaxValue = SliderConfig.Max
			Element._Value = SliderConfig.Default
			Element._IncrementStep = SliderConfig.Increment
			Element._Callback = SliderConfig.Callback
			Element._TrackPositionX = 0
			Element._TrackPositionY = 0
			Element._TrackTotalWidth = 0
			Element._TrackTotalHeight = 6
			Element._PositionX = 0
			Element._PositionY = 0
			Element._Width = 0
			Element._IsHovered = false
			Element._IsThumbHovered = false

			local function SnapToIncrement(RawValue)
				-- Snapping happens before clamping so increments behave predictably
				-- near both ends of the range.
				local SnappedValue = math.floor((RawValue - Element._MinValue) / Element._IncrementStep + 0.5) * Element._IncrementStep + Element._MinValue
				return math.clamp(SnappedValue, Element._MinValue, Element._MaxValue)
			end

			if not UseImmediateMode and DrawingBackendAvailable then
				Element._LabelDrawing = CreateTextDrawing(SliderConfig.Text, Theme.ElementFontSize, Theme.SliderText, 10)
				Element._ValueTextDrawing = CreateTextDrawing(tostring(SliderConfig.Default), Theme.ElementFontSize, Theme.SectionText, 10)
				Element._TrackBackgroundDrawing = CreateRectangleDrawing(Theme.SliderTrackBackground, true, 10, 0.95)
				Element._TrackBorderDrawing = CreateRectangleDrawing(Theme.SliderBorder, false, 11, 0.6)
				Element._TrackFillDrawing = CreateRectangleDrawing(Theme.SliderTrackFill, true, 12, 0.95)

				Element._ThumbDrawing = CreateTrackedDrawingObject("Circle")
				ApplyDrawingProperties(Element._ThumbDrawing, {
					Color = Theme.SliderThumb,
					Filled = true,
					Radius = 7,
					NumSides = 24,
					Transparency = 1,
					ZIndex = 13,
					Visible = true,
				})

				Element._ThumbInnerDrawing = CreateTrackedDrawingObject("Circle")
				ApplyDrawingProperties(Element._ThumbInnerDrawing, {
					Color = Theme.SliderTrackFill,
					Filled = true,
					Radius = 3,
					NumSides = 16,
					Transparency = 1,
					ZIndex = 14,
					Visible = true,
				})
			end

			function Element:SetValue(NewValue)
				NewValue = SnapToIncrement(NewValue)
				Element._Value = NewValue

				if Element._ValueTextDrawing then
					SetRenderProperty(Element._ValueTextDrawing, "Text", tostring(NewValue))
				end

				if not UseImmediateMode and DrawingBackendAvailable then
					Window:RecalculateLayout()
				end

				InvokeCallback(Element._Callback, NewValue)
			end

			function Element:GetValue()
				return Element._Value
			end

			function Element:_UpdateValueFromMousePosition(MousePositionX)
				local AbsoluteTrackPositionX = Window._Position.X + Element._TrackPositionX
				local TrackWidth = math.max(1, Element._TrackTotalWidth or 1)
				local NormalizedFactor = math.clamp(
					(MousePositionX - AbsoluteTrackPositionX) / TrackWidth, 0, 1
				)
				local InterpolatedValue = LerpValue(Element._MinValue, Element._MaxValue, NormalizedFactor)
				Element:SetValue(InterpolatedValue)
			end

			table.insert(Section._Elements, Element)
			Window:RecalculateLayout()
			return Element
		end

		function Section:CreateColorPicker(PickerConfig)
			-- Color pickers keep a compact swatch in the section and open a
			-- larger popup palette when the user wants to choose a new value.
			PickerConfig = PickerConfig or {}
			PickerConfig.Text = PickerConfig.Text or "Color"
			PickerConfig.Default = PickerConfig.Default or Color3.fromRGB(255, 255, 255)
			PickerConfig.Callback = PickerConfig.Callback or function() end

			local Element = {}
			Element._Type = "ColorPicker"
			Element._Height = Theme.ElementHeight
			Element._Text = PickerConfig.Text
			Element._Value = PickerConfig.Default
			Element._Callback = PickerConfig.Callback
			Element._SwatchDrawingObjects = {}
			Element._SelectedSwatchIndex = nil
			Element._PositionX = 0
			Element._PositionY = 0
			Element._Width = 0
			Element._IsHovered = false
			Element._HoveredSwatchIndex = nil

			for PaletteIndex, PaletteColor in ipairs(ColorPalette) do
				if PaletteColor == PickerConfig.Default then
					Element._SelectedSwatchIndex = PaletteIndex
					break
				end
			end

			if not UseImmediateMode and DrawingBackendAvailable then
				Element._LabelDrawing = CreateTextDrawing(PickerConfig.Text, Theme.ElementFontSize, Theme.LabelText, 10)
				Element._SwatchDrawing = CreateRectangleDrawing(Element._Value, true, 11, 1)
				Element._SwatchBorderDrawing = CreateRectangleDrawing(Theme.ColorPickerBorder, false, 12, 1)
				Element._HoverBackgroundDrawing = CreateRectangleDrawing(Theme.ButtonBackground, true, 9, 0.55)
				ApplyDrawingProperties(Element._HoverBackgroundDrawing, { Visible = false })
				Element._AccentLineDrawing = CreateTrackedDrawingObject("Line")
				ApplyDrawingProperties(Element._AccentLineDrawing, {
					Thickness = 2,
					Transparency = 0,
					Color = Theme.SectionText,
					ZIndex = 13,
					Visible = false,
				})
				Element._ChevronDrawing = CreateTextDrawing(">", Theme.ElementFontSize - 1, Theme.DropdownArrow, 13)
				ApplyDrawingProperties(Element._ChevronDrawing, { Transparency = 0.85, Visible = false })
			end

			for SwatchIndex, SwatchColor in ipairs(ColorPalette) do
				table.insert(Element._SwatchDrawingObjects, {
					Color = SwatchColor,
					Index = SwatchIndex,
				})
			end

			function Element:OpenPopup()
				-- Popup selection starts from the current committed color. Applying
				-- writes the value; cancelling simply closes the temporary picker.
				Window._ActiveColorPicker = Element
				Element._TempSelectedSwatchIndex = Element._SelectedSwatchIndex or 1
				Element._TempSelectedColor = Element._Value

				if not UseImmediateMode and DrawingBackendAvailable then
					Element:_BuildPopupDrawings()
				end
			end

			function Element:ClosePopup()
				Window._ActiveColorPicker = nil
				Element._TempSelectedColor = nil

				if not UseImmediateMode then
					Element:_DestroyPopupDrawings()
				end
			end

			function Element:_BuildPopupDrawings()
				Element:_DestroyPopupDrawings()

				local Camera = GetCurrentCamera()
				local ViewportSize = Camera and Camera.ViewportSize or Vector2.new(1920, 1080)
				local Scale = math.clamp(math.min(ViewportSize.X / 1920, ViewportSize.Y / 1080), 0.82, 1.35)

				local SwatchSize    = 22 * Scale
				local SwatchGap     = 4 * Scale
				local Margin        = 10 * Scale
				local Columns       = 10
				local RowCount          = math.ceil(#ColorPalette / Columns)
				local GridWidth     = Columns * SwatchSize + (Columns - 1) * SwatchGap
				local PopupWidth    = Margin + GridWidth + Margin
				local HeaderHeight  = 24 * Scale
				local GridHeight    = RowCount * SwatchSize + (RowCount - 1) * SwatchGap
				local ButtonHeight       = 24 * Scale
				local PopupHeight   = HeaderHeight + Margin + GridHeight + 10 * Scale + ButtonHeight + 10 * Scale

				local WindowPos = Window._Position
				local PopupX = WindowPos.X + Theme.WindowWidth + 10
				if PopupX + PopupWidth > ViewportSize.X - 8 then PopupX = WindowPos.X - PopupWidth - 10 end
				local PopupY = WindowPos.Y
				if PopupY + PopupHeight > ViewportSize.Y - 8 then PopupY = ViewportSize.Y - PopupHeight - 8 end
				PopupY = math.max(8, PopupY)

				local PopupPosition = Vector2.new(PopupX, PopupY)
				Element._PopupPos    = PopupPosition
				Element._PopupWidth  = PopupWidth
				Element._PopupHeight = PopupHeight
				Element._PopupColumns   = Columns
				Element._PopupSwatchCellSize = SwatchSize
				Element._PopupSwatchCellGap  = SwatchGap
				Element._PopupMarginSize     = Margin
				Element._PopupGridStartY = PopupPosition.Y + HeaderHeight + Margin
				Element._PopupGridHeight = GridHeight
				Element._PopupHeaderHeight = HeaderHeight

				Element._PopupBgDrawing = CreateRectangleDrawing(Theme.WindowBackground, true, 50, 1)
				ApplyDrawingProperties(Element._PopupBgDrawing, { Position = PopupPosition, Size = Vector2.new(PopupWidth, PopupHeight), Visible = true })
				Element._PopupBorderDrawing = CreateRectangleDrawing(Theme.WindowBorder, false, 51, 1)
				ApplyDrawingProperties(Element._PopupBorderDrawing, { Position = PopupPosition, Size = Vector2.new(PopupWidth, PopupHeight), Visible = true })

				Element._PopupHeaderDrawing = CreateRectangleDrawing(Theme.TitleBarBackground, true, 51, 1)
				ApplyDrawingProperties(Element._PopupHeaderDrawing, { Position = PopupPosition, Size = Vector2.new(PopupWidth, HeaderHeight), Visible = true })
				Element._PopupTitleDrawing = CreateTextDrawing("Select color", 12 * Scale, Theme.TitleBarText, 52)
				ApplyDrawingProperties(Element._PopupTitleDrawing, {
					Position = Vector2.new(
						PopupPosition.X + Margin,
						GetCenteredTextPosition("Select color", 12 * Scale, PopupPosition, Vector2.new(PopupWidth, HeaderHeight)).Y
					),
					Visible = true,
				})

				local PreviewPosition = Vector2.new(PopupPosition.X + PopupWidth - Margin - 42 * Scale, PopupPosition.Y + 6 * Scale)
				local PreviewSize = Vector2.new(42 * Scale, HeaderHeight - 12 * Scale)
				Element._PopupPreviewDrawing = CreateRectangleDrawing(Element._TempSelectedColor or Element._Value, true, 52, 1)
				ApplyDrawingProperties(Element._PopupPreviewDrawing, { Position = PreviewPosition, Size = PreviewSize, Visible = true })
				Element._PopupPreviewBorderDrawing = CreateRectangleDrawing(Theme.ColorPickerSelectedBorder, false, 53, 0.9)
				ApplyDrawingProperties(Element._PopupPreviewBorderDrawing, { Position = PreviewPosition, Size = PreviewSize, Visible = true })

				Element._PopupSwatchDrawings = {}
				local GridStartY = PopupPosition.Y + HeaderHeight + Margin
				for SwatchIndex = 1, #ColorPalette do
					local ColumnIndex = (SwatchIndex - 1) % Columns
					local RowIndex = math.floor((SwatchIndex - 1) / Columns)
					local SwatchX = PopupPosition.X + Margin + ColumnIndex * (SwatchSize + SwatchGap)
					local SwatchY = GridStartY + RowIndex * (SwatchSize + SwatchGap)
					local SwatchPos = Vector2.new(SwatchX, SwatchY)
					local SwatchSizeVector  = Vector2.new(SwatchSize, SwatchSize)
					local IsSelected = (SwatchIndex == Element._TempSelectedSwatchIndex)

					local FillDrawing = CreateRectangleDrawing(ColorPalette[SwatchIndex], true, 52, 1)
					ApplyDrawingProperties(FillDrawing, { Position = SwatchPos, Size = SwatchSizeVector, Visible = true })
					local BorderDrawing = CreateRectangleDrawing(IsSelected and Theme.ColorPickerSelectedBorder or Theme.ColorPickerBorder, false, 53, 1)
					ApplyDrawingProperties(BorderDrawing, { Position = SwatchPos, Size = SwatchSizeVector, Thickness = IsSelected and 2 or 1, Visible = true })

					table.insert(Element._PopupSwatchDrawings, { Fill = FillDrawing, Border = BorderDrawing })
				end

				local ButtonY   = GridStartY + GridHeight + 10 * Scale
				local ButtonWidth   = (PopupWidth - Margin * 3) / 2
				local SavePos   = Vector2.new(PopupPosition.X + Margin, ButtonY)
				local ExitPos   = Vector2.new(PopupPosition.X + Margin * 2 + ButtonWidth, ButtonY)
				local ButtonSize  = Vector2.new(ButtonWidth, ButtonHeight)
				Element._PopupSavePos  = SavePos
				Element._PopupExitPos  = ExitPos
				Element._PopupButtonSize = ButtonSize

				Element._PopupSaveBackground  = CreateRectangleDrawing(Theme.SaveButtonBackground, true, 52, 1)
				ApplyDrawingProperties(Element._PopupSaveBackground, { Position = SavePos, Size = ButtonSize, Visible = true })
				Element._PopupSaveText = CreateTextDrawing("Apply", 12 * Scale, Theme.ButtonText, 53)
				ApplyCenteredTextDrawing(Element._PopupSaveText, "Apply", 12 * Scale, SavePos, ButtonSize)

				Element._PopupExitBackground  = CreateRectangleDrawing(Theme.ExitButtonBackground, true, 52, 1)
				ApplyDrawingProperties(Element._PopupExitBackground, { Position = ExitPos, Size = ButtonSize, Visible = true })
				Element._PopupExitText = CreateTextDrawing("Cancel", 12 * Scale, Theme.ButtonText, 53)
				ApplyCenteredTextDrawing(Element._PopupExitText, "Cancel", 12 * Scale, ExitPos, ButtonSize)
			end

			function Element:_DestroyPopupDrawings()
				DestroyDrawing(Element._PopupBgDrawing, WindowTrackedDrawings)
				DestroyDrawing(Element._PopupBorderDrawing, WindowTrackedDrawings)
				DestroyDrawing(Element._PopupHeaderDrawing, WindowTrackedDrawings)
				DestroyDrawing(Element._PopupTitleDrawing, WindowTrackedDrawings)
				DestroyDrawing(Element._PopupPreviewDrawing, WindowTrackedDrawings)
				DestroyDrawing(Element._PopupPreviewBorderDrawing, WindowTrackedDrawings)
				DestroyDrawing(Element._PopupSaveBackground, WindowTrackedDrawings)
				DestroyDrawing(Element._PopupSaveText, WindowTrackedDrawings)
				DestroyDrawing(Element._PopupExitBackground, WindowTrackedDrawings)
				DestroyDrawing(Element._PopupExitText, WindowTrackedDrawings)
				for SwatchIndex, SwatchPair in ipairs(Element._PopupSwatchDrawings or {}) do
					DestroyDrawing(SwatchPair.Fill, WindowTrackedDrawings)
					DestroyDrawing(SwatchPair.Border, WindowTrackedDrawings)
				end
				Element._PopupBgDrawing      = nil
				Element._PopupBorderDrawing  = nil
				Element._PopupHeaderDrawing  = nil
				Element._PopupTitleDrawing   = nil
				Element._PopupPreviewDrawing = nil
				Element._PopupPreviewBorderDrawing = nil
				Element._PopupSaveBackground        = nil
				Element._PopupSaveText       = nil
				Element._PopupExitBackground        = nil
				Element._PopupExitText       = nil
				Element._PopupSwatchDrawings = {}
				Element._PopupPos            = nil
			end

			function Element:SelectSwatch(TargetSwatchIndex)
				-- Commit a palette color and update the compact section swatch.
				if not TargetSwatchIndex or not ColorPalette[TargetSwatchIndex] then
					return
				end

				if Element._SelectedSwatchIndex and Element._SwatchDrawingObjects[Element._SelectedSwatchIndex] then
					local PreviousSwatch = Element._SwatchDrawingObjects[Element._SelectedSwatchIndex]
					if PreviousSwatch.BorderDrawing then
						ApplyDrawingProperties(PreviousSwatch.BorderDrawing, {
							Color = Theme.ColorPickerBorder,
							Thickness = 1,
						})
					end
				end

				Element._SelectedSwatchIndex = TargetSwatchIndex
				Element._Value = ColorPalette[TargetSwatchIndex]
				Element._TempSelectedColor = Element._Value

				if Element._SwatchDrawingObjects[TargetSwatchIndex] then
					local NewlySelectedSwatch = Element._SwatchDrawingObjects[TargetSwatchIndex]
					if NewlySelectedSwatch.BorderDrawing then
						ApplyDrawingProperties(NewlySelectedSwatch.BorderDrawing, {
							Color = Theme.ColorPickerSelectedBorder,
							Thickness = 2,
						})
					end
				end

				if Element._SwatchDrawing then
					SetRenderProperty(Element._SwatchDrawing, "Color", Element._Value)
				end

				InvokeCallback(Element._Callback, Element._Value)
			end

			function Element:SetValue(NewColor, SuppressCallback)
				-- External setters can pass any Color3. The closest palette
				-- swatch is highlighted while the exact Color3 is preserved.
				if typeof(NewColor) ~= "Color3" then
					return false
				end

				local ClosestMatchIndex = 1
				local SmallestDistance = math.huge

				for PaletteIndex, PaletteColor in ipairs(ColorPalette) do
					local RedDelta = PaletteColor.R - NewColor.R
					local GreenDelta = PaletteColor.G - NewColor.G
					local BlueDelta = PaletteColor.B - NewColor.B
					local ColorDistance = RedDelta * RedDelta + GreenDelta * GreenDelta + BlueDelta * BlueDelta

					if ColorDistance < SmallestDistance then
						SmallestDistance = ColorDistance
						ClosestMatchIndex = PaletteIndex
					end
				end

				if Element._SelectedSwatchIndex and Element._SwatchDrawingObjects[Element._SelectedSwatchIndex] then
					local PreviousSwatch = Element._SwatchDrawingObjects[Element._SelectedSwatchIndex]
					if PreviousSwatch.BorderDrawing then
						ApplyDrawingProperties(PreviousSwatch.BorderDrawing, {
							Color = Theme.ColorPickerBorder,
							Thickness = 1,
						})
					end
				end

				Element._SelectedSwatchIndex = ClosestMatchIndex
				Element._Value = NewColor

				if Element._SwatchDrawingObjects[ClosestMatchIndex] then
					local NewlySelectedSwatch = Element._SwatchDrawingObjects[ClosestMatchIndex]
					if NewlySelectedSwatch.BorderDrawing then
						ApplyDrawingProperties(NewlySelectedSwatch.BorderDrawing, {
							Color = Theme.ColorPickerSelectedBorder,
							Thickness = 2,
						})
					end
				end

				if Element._SwatchDrawing then
					SetRenderProperty(Element._SwatchDrawing, "Color", Element._Value)
				end

				if not SuppressCallback then
					InvokeCallback(Element._Callback, Element._Value)
				end

				return true
			end

			function Element:GetValue()
				return Element._Value
			end

			table.insert(Section._Elements, Element)
			Window:RecalculateLayout()
			return Element
		end

		table.insert(Window._Sections, Section)
		Window:RecalculateLayout()
		return Section
	end

	function Window:Destroy()
		if Window._Destroyed then
			return
		end

		-- Close temporary panels before destroying drawing objects. Their close
		-- methods clear active state and remove popup-specific drawings through
		-- the same code path used during normal interaction.
		if Window._ActiveDropdown then
			Window._ActiveDropdown:Toggle()
		end
		if Window._ActiveColorPicker then
			Window._ActiveColorPicker:ClosePopup()
		end

		DestroyAllTrackedDrawings()

		for EntryIndex = #Window._ActiveNotifications, 1, -1 do
			local Entry = Window._ActiveNotifications[EntryIndex]
			DestroyDrawing(Entry.Background, NotificationTrackedDrawings)
			DestroyDrawing(Entry.Border, NotificationTrackedDrawings)
			DestroyDrawing(Entry.AccentLine, NotificationTrackedDrawings)
			DestroyDrawing(Entry.TextLabel, NotificationTrackedDrawings)
			table.remove(Window._ActiveNotifications, EntryIndex)
		end

		Window:SetInputBlocking("Scroll", false)
		Window:SetInputBlocking("Camera", false)
		Window:SetInputBlocking("Interface", false)
		Window:SetInputBlocking("Typing", false)
		Library:ClearInputBlockingForWindow(Window)

		for ConnectionIndex, Connection in ipairs(Window._Connections) do
			if Connection then
				pcall(Connection.Disconnect, Connection)
			end
		end
		Window._Connections = {}

		for WindowIndex, ActiveWindow in ipairs(Library._Windows) do
			if ActiveWindow == Window then
				table.remove(Library._Windows, WindowIndex)
				break
			end
		end

		Window._Visible = false
		Window._Destroyed = true
	end

	local PreviousMouseButtonState = false
	local PreviousSecondaryMouseButtonState = false
	local QueuedPrimaryClick = false
	local PrimaryMouseButtonHeld = false

	local WindowHasFocus = true
	local UpdateHoverState

	local function GetWindowResizeLimits()
		local Camera = GetCurrentCamera()
		local ViewportSize = Camera and Camera.ViewportSize or Vector2.new(1920, 1080)
		return {
			MinimumWidth = 460,
			MinimumVisibleHeight = 380,
			MaximumWidth = math.max(460, ViewportSize.X - 16),
			MaximumVisibleHeight = math.max(380, ViewportSize.Y - Theme.TitleBarHeight - 16),
		}
	end

	local function ApplyWindowSize(NewWindowWidth, NewVisibleHeight)
		local ResizeLimits = GetWindowResizeLimits()
		local ClampedWindowWidth = math.clamp(NewWindowWidth, ResizeLimits.MinimumWidth, ResizeLimits.MaximumWidth)
		local ClampedVisibleHeight = math.clamp(NewVisibleHeight, ResizeLimits.MinimumVisibleHeight, ResizeLimits.MaximumVisibleHeight)
		local BaseWindowWidth = Theme.Base and Theme.Base.WindowWidth or Theme.WindowWidth
		local CurrentScale = BaseWindowWidth ~= 0 and (Theme.WindowWidth / BaseWindowWidth) or 1
		if CurrentScale == 0 then
			CurrentScale = 1
		end

		Theme.WindowWidth = ClampedWindowWidth
		Theme.WindowVisibleHeight = ClampedVisibleHeight

		if Theme.Base then
			Theme.Base.WindowWidth = ClampedWindowWidth / CurrentScale
			Theme.Base.WindowVisibleHeight = ClampedVisibleHeight / CurrentScale
		end

		Window._VisibleHeight = ClampedVisibleHeight
		Window._TotalHeight = Theme.TitleBarHeight + ClampedVisibleHeight
	end

	local function ClampWindowPosition(TargetPosition)
		local Camera = GetCurrentCamera()
		local ViewportSize = Camera and Camera.ViewportSize or Vector2.new(1920, 1080)
		local MaximumPositionX = math.max(8, ViewportSize.X - Theme.WindowWidth - 8)
		local MaximumPositionY = math.max(8, ViewportSize.Y - (Theme.TitleBarHeight + Window._VisibleHeight) - 8)

		return Vector2.new(
			math.clamp(TargetPosition.X, 8, MaximumPositionX),
			math.clamp(TargetPosition.Y, 8, MaximumPositionY)
		)
	end

	function Window:SetGeometry(Geometry)
		-- Saved geometry is treated as untrusted input because the file can be
		-- edited, corrupted, or copied from a different screen size. Every value
		-- is converted, clamped, and then applied through the same resize helpers
		-- used by pointer resizing.
		if typeof(Geometry) ~= "table" then
			return false
		end

		local NewWindowWidth = tonumber(Geometry.WindowWidth)
		local NewVisibleHeight = tonumber(Geometry.WindowVisibleHeight)
		if NewWindowWidth and NewVisibleHeight then
			ApplyWindowSize(NewWindowWidth, NewVisibleHeight)
		end

		local NewPositionX = tonumber(Geometry.PositionX)
		local NewPositionY = tonumber(Geometry.PositionY)
		if NewPositionX and NewPositionY then
			Window._Position = ClampWindowPosition(Vector2.new(NewPositionX, NewPositionY))
		else
			Window._Position = ClampWindowPosition(Window._Position)
		end

		Window:RecalculateLayout()
		return true
	end

	local function RefreshInterfaceCaptureState()
		local SectionScrollbarIsBeingDragged = false
		for SectionIndex, ScrollableSection in ipairs(Window._Sections) do
			if ScrollableSection._DraggingScrollbar then
				SectionScrollbarIsBeingDragged = true
				break
			end
		end

		local ShouldCaptureInterface = Window._MouseInWindow
			or PrimaryMouseButtonHeld
			or Window._Dragging
			or Window._Resizing
			or Window._ActiveSlider ~= nil
			or Window._DraggingScrollbar
			or SectionScrollbarIsBeingDragged

		if ShouldCaptureInterface ~= Window._InterfaceSinkActive then
			Window._InterfaceSinkActive = ShouldCaptureInterface
			Window:SetInputBlocking("Interface", ShouldCaptureInterface)
		end
	end

	local function ReleasePrimaryPointerCapture()
		PrimaryMouseButtonHeld = false
		PreviousMouseButtonState = false
		PreviousSecondaryMouseButtonState = false
		Window._Dragging = false
		Window._Resizing = false
		Window._ActiveSlider = nil
		Window._DraggingScrollbar = false

		for SectionIndex, ScrollableSection in ipairs(Window._Sections) do
			ScrollableSection._DraggingScrollbar = false
		end

		RefreshInterfaceCaptureState()
	end

	local function ClearFocusedTextBoxes()
		-- Focus cleanup is shared by buttons, toggles, dropdowns, sliders, and
		-- background clicks. Keeping it as a window-level helper prevents each
		-- click path from carrying its own text focus logic.
		for FocusSectionIndex, FocusSection in ipairs(Window:GetActiveSections()) do
			for FocusElementIndex, FocusElement in ipairs(FocusSection._Elements) do
				if FocusElement._Type == "TextBox" then
					FocusElement._IsFocused = false
					FocusElement._CursorVisible = false
				end
			end
		end
		Window:SetInputBlocking("Typing", false)
	end

	local function SetSearchTextBoxFocus(IsFocused)
		-- Search uses the same typing sink as normal text boxes, but it is not
		-- stored inside a section. This helper keeps the focus flag, cursor, and
		-- input blocking synchronized for every search interaction path.
		Window._SearchTextBox._IsFocused = IsFocused == true
		if not Window._SearchTextBox._IsFocused then
			Window._SearchTextBox._CursorVisible = false
			Window._SearchTextBox._CursorBlinkTime = 0
		end
		Window:SetInputBlocking("Typing", Window._SearchTextBox._IsFocused)
	end

	local function SetSearchActive(IsActive, ShouldResetQuery)
		-- Opening search starts with a clean query by default. Closing search
		-- also clears hover state so stale dropdown rows cannot be selected by a
		-- later click after the search field is hidden.
		Window._SearchActive = IsActive == true
		SetSearchTextBoxFocus(Window._SearchActive)

		if ShouldResetQuery then
			Window._SearchTextBox._Value = ""
			Window._SearchResults = {}
		end

		if not Window._SearchActive then
			Window._HoveredSearchResultIndex = nil
			Window._SearchDropdownRegion = nil
		end
	end

	local function CloseFloatingOverlays()
		-- Dropdowns and color pickers are both temporary floating panels. Treat
		-- secondary clicks as a shared dismissal command so the two systems do
		-- not each need their own input polling branch.
		local DidCloseOverlay = false
		if Window._ActiveDropdown then
			Window._ActiveDropdown:Toggle()
			DidCloseOverlay = true
		end
		if Window._ActiveColorPicker then
			Window._ActiveColorPicker:ClosePopup()
			DidCloseOverlay = true
		end
		return DidCloseOverlay
	end

	table.insert(Window._Connections, WindowFocusReleasedConnect(UserInputService.WindowFocusReleased, NewCClosure(function()
		WindowHasFocus = false
		PreviousSecondaryMouseButtonState = false
	end)))
	table.insert(Window._Connections, WindowFocusedConnect(UserInputService.WindowFocused, NewCClosure(function()
		WindowHasFocus = true
	end)))

	table.insert(Window._Connections, InputBeganSignalConnect(UserInputService.InputBegan, NewCClosure(function(Input, Processed)
		if Window._Destroyed or not Window._Visible or not Library._Visible then
			return
		end

		if Input.UserInputType ~= Enum.UserInputType.MouseButton1 then
			return
		end

		local CurrentMousePosition = GetMouseLocation(UserInputService)
		if not UpdateHoverState then
			return
		end
		UpdateHoverState(CurrentMousePosition)

		if Window._MouseInWindow then
			QueuedPrimaryClick = true
			PrimaryMouseButtonHeld = true
			PreviousMouseButtonState = true
			RefreshInterfaceCaptureState()
		end
	end)))

	table.insert(Window._Connections, InputEndedSignalConnect(UserInputService.InputEnded, NewCClosure(function(Input, Processed)
		if Input.UserInputType ~= Enum.UserInputType.MouseButton1 then
			return
		end

		ReleasePrimaryPointerCapture()
	end)))

	UpdateHoverState = function(CurrentMousePosition)
		for SectionIndex, Section in ipairs(Window._Sections) do
			local IsActivePage = (not Section._PageIndex) or (Section._PageIndex == Window._ActivePageIndex)
			if not IsActivePage then
				Section._IsHovered = false
				Section._ScrollbarHovered = false
				for DiscardElementIndex, Element in ipairs(Section._Elements) do
					Element._IsHovered = false
					if Element._Type == "Slider" then
						Element._IsThumbHovered = false
					elseif Element._Type == "ColorPicker" then
						Element._IsSwatchHovered = false
					end
				end
			end
		end

		for PageIndex, Page in ipairs(Window._Pages) do
			Page._IsHovered = false
			if Window._TabBarHeight > 0 then
				local TabCount = #Window._Pages
				local TabBarPadding = 10
				local TabGap = 6
				local TabWidth = math.max(92, (Theme.WindowWidth - (TabBarPadding * 2) - (TabGap * (math.min(TabCount, 5) - 1))) / math.min(TabCount, 5))
				local TabX = Window._Position.X + TabBarPadding + (PageIndex - 1) * (TabWidth + TabGap) - (Window._TabScrollOffset or 0)
				local TabY = Window._Position.Y + Theme.TitleBarHeight + 5
				Page._IsHovered = IsPointInsideRectangle(CurrentMousePosition, Vector2.new(TabX, TabY), Vector2.new(TabWidth, Window._TabBarHeight - 10))
			end
		end

		if Window._SearchButtonRegion then
			Window._SearchButtonHovered = IsPointInsideRectangle(CurrentMousePosition, Window._SearchButtonRegion.Position, Window._SearchButtonRegion.Size)
		else
			Window._SearchButtonHovered = false
		end

		if Window._SearchActive and Window._SearchTextBox then
			Window._SearchTextBox._IsHovered = Window._SearchTextBoxRegion and IsPointInsideRectangle(CurrentMousePosition, Window._SearchTextBoxRegion.Position, Window._SearchTextBoxRegion.Size) or false
			Window._HoveredSearchResultIndex = nil
			if Window._SearchDropdownRegion and #Window._SearchResults > 0 and IsPointInsideRectangle(CurrentMousePosition, Window._SearchDropdownRegion.Position, Window._SearchDropdownRegion.Size) then
				local RelativeSearchResultY = CurrentMousePosition.Y - Window._SearchDropdownRegion.Position.Y
				local SearchResultIndex = math.floor(RelativeSearchResultY / 24) + 1
				if SearchResultIndex >= 1 and SearchResultIndex <= #Window._SearchResults then
					Window._HoveredSearchResultIndex = SearchResultIndex
				end
			end
		else
			Window._HoveredSearchResultIndex = nil
			if Window._SearchTextBox then
				Window._SearchTextBox._IsHovered = false
			end
		end

		for SectionIndex, Section in ipairs(Window:GetActiveSections()) do
			local SectionYPosition = Window._Position.Y + Section._PositionY - Window._ScrollOffset
			local SectionHeaderPosition = Vector2.new(Window._Position.X + Section._PositionX, SectionYPosition)
			local SectionHeaderSize = Vector2.new(Section._Width, Theme.ElementHeight)
			local ViewportStart, ViewportEnd = GetWindowContentViewportYRange(Window, Window._Position.Y)
			local SectionVisible = (SectionYPosition + (Section._ContentHeight or 0) > ViewportStart)
				and (SectionYPosition < ViewportEnd)
			Section._IsHovered = SectionVisible and IsPointInsideRectangle(CurrentMousePosition, SectionHeaderPosition, SectionHeaderSize)

			for ElementIndex, Element in ipairs(Section._Elements) do
				local ElementYPosition = Window._Position.Y + Element._PositionY - Window._ScrollOffset
				local ElementRegionPosition = Vector2.new(Window._Position.X + Element._PositionX, ElementYPosition)
				local ElementWidth = Element._Width - (Window._MaxScroll > 0 and Theme.ScrollbarWidth + 4 or 0)
				local ElementRegionSize = Vector2.new(ElementWidth, Element._Height)
				local IsElementVisible = IsElementVisibleInViewport(ElementYPosition, Element._Height, Section, Window, Window._Position.Y)
				local IsCurrentlyHovered = IsElementVisible and IsPointInsideRectangle(CurrentMousePosition, ElementRegionPosition, ElementRegionSize)

				if Element._Type == "Slider" then
					local TrackAbsolutePositionX = Window._Position.X + (Element._TrackPositionX or Element._PositionX)
					local TrackAbsolutePositionY = ElementYPosition + Theme.ElementFontSize + 5
					local TrackPos = Vector2.new(TrackAbsolutePositionX, TrackAbsolutePositionY)
					local TrackSize = Vector2.new(Element._TrackTotalWidth or ElementWidth, 16)
					Element._IsHovered = IsElementVisible and IsPointInsideRectangle(CurrentMousePosition, TrackPos, TrackSize)

					local Value = Element._Value or 0
					local Range = (Element._MaxValue or 100) - (Element._MinValue or 0)
					if Range == 0 then Range = 1 end
					local NormalizedValue = math.clamp((Value - (Element._MinValue or 0)) / Range, 0, 1)
					local ThumbX = TrackAbsolutePositionX + math.floor((Element._TrackTotalWidth or Element._Width) * NormalizedValue)
					local ThumbY = TrackAbsolutePositionY + 4
					local ThumbHitSize = 14
					Element._IsThumbHovered = IsElementVisible and math.abs(CurrentMousePosition.X - ThumbX) < ThumbHitSize and math.abs(CurrentMousePosition.Y - ThumbY) < ThumbHitSize
					Element._IsHovered = Element._IsHovered or Element._IsThumbHovered
				elseif Element._Type == "ColorPicker" then
					local SwatchAbsolutePosition = Window._Position + Vector2.new(Element._SwatchPositionX, Element._SwatchPositionY - Window._ScrollOffset)
					local SwatchSizeVector = Vector2.new(Element._SwatchSize, Element._SwatchSize)
					Element._IsSwatchHovered = IsElementVisible and IsPointInsideRectangle(CurrentMousePosition, SwatchAbsolutePosition, SwatchSizeVector)
					Element._IsHovered = Element._IsSwatchHovered
				else
					Element._IsHovered = IsCurrentlyHovered
				end
			end
		end

		local MainScrollbarGeometry = GetMainScrollbarGeometry(Window, Window._Position)
		Window._ScrollbarHovered = MainScrollbarGeometry
			and IsPointInsideRectangle(CurrentMousePosition, MainScrollbarGeometry.HitPosition, MainScrollbarGeometry.HitSize)
			or false

		for SectionIndex, ScrollableSection in ipairs(Window:GetActiveSections()) do
			local SectionScrollbarGeometry = GetSectionScrollbarGeometry(ScrollableSection, Window)
			ScrollableSection._ScrollbarHovered = SectionScrollbarGeometry
				and IsPointInsideRectangle(CurrentMousePosition, SectionScrollbarGeometry.HitPosition, SectionScrollbarGeometry.HitSize)
				or false
		end

		local SinkBodyPosition = Vector2.new(Window._Position.X, Window._Position.Y + Theme.TitleBarHeight)
		local SinkBodySize = Vector2.new(Theme.WindowWidth, Window._VisibleHeight)
		local SinkTitlePosition = Vector2.new(Window._Position.X, Window._Position.Y)
		local SinkTitleSize = Vector2.new(Theme.WindowWidth, Theme.TitleBarHeight)
		local MouseInWindow = IsPointInsideRectangle(CurrentMousePosition, SinkBodyPosition, SinkBodySize)
			or IsPointInsideRectangle(CurrentMousePosition, SinkTitlePosition, SinkTitleSize)
		Window._MouseInWindow = MouseInWindow
		if MouseInWindow ~= Window._ScrollSinkActive then
			Window._ScrollSinkActive = MouseInWindow
			Window:SetInputBlocking("Scroll", MouseInWindow)
		end
		if MouseInWindow ~= Window._CameraSinkActive then
			Window._CameraSinkActive = MouseInWindow
			Window:SetInputBlocking("Camera", MouseInWindow)
		end
		RefreshInterfaceCaptureState()
		Window._TitleBarHovered = IsPointInsideRectangle(CurrentMousePosition, SinkTitlePosition, SinkTitleSize)

		local ResizeGripSize = math.max(18, Theme.InnerMargin)
		local ResizeGripPosition = Vector2.new(
			Window._Position.X + Theme.WindowWidth - ResizeGripSize,
			Window._Position.Y + Theme.TitleBarHeight + Window._VisibleHeight - ResizeGripSize
		)
		Window._ResizeGripRegion = {
			Position = ResizeGripPosition,
			Size = Vector2.new(ResizeGripSize, ResizeGripSize)
		}
		Window._ResizeGripHovered = IsPointInsideRectangle(CurrentMousePosition, Window._ResizeGripRegion.Position, Window._ResizeGripRegion.Size)

		local TitleHitboxPosition = Vector2.new(Window._Position.X + Theme.InnerMargin, Window._Position.Y)
		local TitleHitboxSize = Vector2.new(math.min(180, Theme.WindowWidth / 2), Theme.TitleBarHeight)
		Window._TitleTextHovered = IsPointInsideRectangle(CurrentMousePosition, TitleHitboxPosition, TitleHitboxSize)

		if Window._CloseButtonRegion then
			Window._CloseButtonHovered = IsPointInsideRectangle(CurrentMousePosition, Window._CloseButtonRegion.Position, Window._CloseButtonRegion.Size)
		else
			Window._CloseButtonHovered = false
		end

		if Window._ActiveDropdown then
			for ItemIndex, ItemData in ipairs(Window._ActiveDropdown._ItemDrawingObjects) do
				local ItemRegionPosition = Vector2.new(Window._Position.X + ItemData._PositionX, Window._Position.Y + ItemData._PositionY - Window._ScrollOffset)
				local ItemRegionSize = Vector2.new(ItemData._Width, Theme.ElementHeight)
				ItemData._IsHovered = IsPointInsideRectangle(CurrentMousePosition, ItemRegionPosition, ItemRegionSize)
				if ItemData.BackgroundDrawing then
					ApplyDrawingProperties(ItemData.BackgroundDrawing, {
						Color = ItemData._IsHovered and Theme.DropdownItemHover or Theme.DropdownItemBackground,
					})
				end
			end
		end

		if Window._ActiveColorPicker then
			local ColorPicker = Window._ActiveColorPicker
			local PopupGeometry = UseImmediateMode and ColorPicker._PopupGeometry or nil
			local PopupPosition = PopupGeometry and PopupGeometry.Position or ColorPicker._PopupPos
			local PopupWidth = PopupGeometry and PopupGeometry.Width or ColorPicker._PopupWidth
			local PopupHeight = PopupGeometry and PopupGeometry.Height or ColorPicker._PopupHeight
			local Columns = PopupGeometry and PopupGeometry.Columns or ColorPicker._PopupColumns
			local SwatchSize = PopupGeometry and PopupGeometry.SwatchSize or ColorPicker._PopupSwatchCellSize
			local SwatchGap = PopupGeometry and PopupGeometry.SwatchGap or ColorPicker._PopupSwatchCellGap
			local Margin = PopupGeometry and PopupGeometry.Margin or ColorPicker._PopupMarginSize
			local GridStartY = PopupGeometry and PopupGeometry.GridStartY or ColorPicker._PopupGridStartY
			local SavePosition = PopupGeometry and PopupGeometry.SavePos or ColorPicker._PopupSavePos
			local ExitPosition = PopupGeometry and PopupGeometry.ExitPos or ColorPicker._PopupExitPos
			local ButtonSize = PopupGeometry and PopupGeometry.ButtonSize or ColorPicker._PopupButtonSize

			ColorPicker._PopupHovered = PopupPosition and PopupWidth and PopupHeight and IsPointInsideRectangle(CurrentMousePosition, PopupPosition, Vector2.new(PopupWidth, PopupHeight)) or false
			ColorPicker._SaveButtonHovered = SavePosition and ButtonSize and IsPointInsideRectangle(CurrentMousePosition, SavePosition, ButtonSize) or false
			ColorPicker._ExitButtonHovered = ExitPosition and ButtonSize and IsPointInsideRectangle(CurrentMousePosition, ExitPosition, ButtonSize) or false
			ColorPicker._HoveredSwatchIndex = nil

			if ColorPicker._PopupHovered and PopupPosition and Columns and SwatchSize and SwatchGap and Margin and GridStartY then
				for SwatchIndex = 1, #ColorPalette do
					local ColumnIndex = (SwatchIndex - 1) % Columns
					local RowIndex = math.floor((SwatchIndex - 1) / Columns)
					local SwatchX = PopupPosition.X + Margin + ColumnIndex * (SwatchSize + SwatchGap)
					local SwatchY = GridStartY + RowIndex * (SwatchSize + SwatchGap)
					if IsPointInsideRectangle(CurrentMousePosition, Vector2.new(SwatchX, SwatchY), Vector2.new(SwatchSize, SwatchSize)) then
						ColorPicker._HoveredSwatchIndex = SwatchIndex
						break
					end
				end
			end
		end
	end

	local HeartbeatConnection = HeartbeatSignalConnect(RunService.Heartbeat, NewCClosure(function(DeltaTime)
		if Window._Destroyed then return end

		local DeltaSeconds = DeltaTime or 0.0167
		local CurrentMousePosition = GetMouseLocation(UserInputService)
		UpdateHoverState(CurrentMousePosition)

		local AnimationChanged = false
		local function UpdateAnimationState(CurrentFactor, TargetState, DeltaSecondsValue, Speed)
			local NewFactor = UpdateAnimationFactor(CurrentFactor, TargetState, DeltaSecondsValue, Speed)
			if NewFactor ~= CurrentFactor then
				AnimationChanged = true
			end
			return NewFactor
		end

		Window._CloseButtonHoverFactor = UpdateAnimationState(Window._CloseButtonHoverFactor or 0, Window._CloseButtonHovered, DeltaSeconds, 12)
		Window._TitleTextHoverFactor = UpdateAnimationState(Window._TitleTextHoverFactor or 0, Window._TitleTextHovered, DeltaSeconds, 12)

		for PageIndex, Page in ipairs(Window._Pages) do
			Page._HoverFactor = UpdateAnimationState(Page._HoverFactor or 0, Page._IsHovered, DeltaSeconds, 12)
		end

		if Window._SearchActive then
			local SearchBox = Window._SearchTextBox
			SearchBox._HoverFactor = UpdateAnimationState(SearchBox._HoverFactor or 0, SearchBox._IsHovered, DeltaSeconds, 12)
			SearchBox._FocusFactor = UpdateAnimationState(SearchBox._FocusFactor or 0, SearchBox._IsFocused, DeltaSeconds, 12)
		end

		for SectionIndex, Section in ipairs(Window._Sections) do
			Section._HoverFactor = UpdateAnimationState(Section._HoverFactor or 0, Section._IsHovered, DeltaSeconds, 12)
			Section._ScrollbarHoverFactor = UpdateAnimationState(Section._ScrollbarHoverFactor or 0, Section._ScrollbarHovered or Section._DraggingScrollbar, DeltaSeconds, 12)

			for ElementIndex, Element in ipairs(Section._Elements) do
				Element._HoverFactor = UpdateAnimationState(Element._HoverFactor or 0, Element._IsHovered, DeltaSeconds, 12)
				Element._FocusFactor = UpdateAnimationState(Element._FocusFactor or 0, Element._IsFocused, DeltaSeconds, 12)
				Element._ExpandFactor = UpdateAnimationState(Element._ExpandFactor or 0, Element._Expanded, DeltaSeconds, 12)
				Element._ActiveFactor = UpdateAnimationState(Element._ActiveFactor or 0, (Element._Type == "Slider" and Window._ActiveSlider == Element) or (Element._Type == "Toggle" and Element._Value) or false, DeltaSeconds, 12)
				if Element._Type == "Slider" then
					Element._ThumbHoverFactor = UpdateAnimationState(Element._ThumbHoverFactor or 0, Element._IsThumbHovered or (Window._ActiveSlider == Element), DeltaSeconds, 12)
				end
			end
		end

		if Window._SearchActive and Window._SearchTextBox._IsFocused then
			local CurrentTime = tick()
			if CurrentTime - Window._SearchTextBox._CursorBlinkTime >= 0.53 then
				Window._SearchTextBox._CursorBlinkTime = CurrentTime
				Window._SearchTextBox._CursorVisible = not Window._SearchTextBox._CursorVisible
				Window:RecalculateLayout()
			end
		else
			Window._SearchTextBox._CursorVisible = false
			Window._SearchTextBox._CursorBlinkTime = 0
		end

		local SectionScrollbarHasActivePointerCapture = false
		for SectionIndex, ScrollableSection in ipairs(Window._Sections) do
			if ScrollableSection._DraggingScrollbar then
				SectionScrollbarHasActivePointerCapture = true
				break
			end
		end

		local HasActivePointerCapture = PrimaryMouseButtonHeld
			or Window._Dragging
			or Window._Resizing
			or Window._ActiveSlider ~= nil
			or Window._DraggingScrollbar
			or SectionScrollbarHasActivePointerCapture

		if not WindowHasFocus and not Window._MouseInWindow and not QueuedPrimaryClick and not HasActivePointerCapture then return end

		local RawMouseButtonDown = IsMouseButtonPressed(UserInputService, Enum.UserInputType.MouseButton1)
		local IsPrimaryMouseButtonDown = PrimaryMouseButtonHeld or RawMouseButtonDown

		local MouseButtonJustPressed = RawMouseButtonDown and not PreviousMouseButtonState
		local MouseButtonJustReleased = not IsPrimaryMouseButtonDown and PreviousMouseButtonState
		local ShouldProcessPrimaryClick = QueuedPrimaryClick or MouseButtonJustPressed
		QueuedPrimaryClick = false

		local SecondaryMouseButtonDown = false
		local PressedButtons = GetMouseButtonsPressed(UserInputService)
		for ButtonIndex, PressedButton in ipairs(PressedButtons) do
			if PressedButton.UserInputType == Enum.UserInputType.MouseButton2 then
				SecondaryMouseButtonDown = true
				break
			end
		end
		if SecondaryMouseButtonDown and not PreviousSecondaryMouseButtonState then
			CloseFloatingOverlays()
		end
		PreviousSecondaryMouseButtonState = SecondaryMouseButtonDown

		PreviousMouseButtonState = IsPrimaryMouseButtonDown

		if not Window._Visible then return end

		if Window._ActiveSlider and IsPrimaryMouseButtonDown then
			Window._ActiveSlider:_UpdateValueFromMousePosition(CurrentMousePosition.X)
		end

		if MouseButtonJustReleased then
			ReleasePrimaryPointerCapture()
		end

		if Window._Resizing and IsPrimaryMouseButtonDown and Window._ResizeStartSize then
			local ResizeDelta = CurrentMousePosition - Window._ResizeStartMousePosition
			ApplyWindowSize(Window._ResizeStartSize.X + ResizeDelta.X, Window._ResizeStartSize.Y + ResizeDelta.Y)
			Window:RecalculateLayout()
		end

		if Window._Dragging and IsPrimaryMouseButtonDown and Window._DragOffset then
			Window._Position = CurrentMousePosition - Window._DragOffset
			Window:RecalculateLayout()
		end

		if Window._DraggingScrollbar and IsPrimaryMouseButtonDown then
			local MainScrollbarGeometry = GetMainScrollbarGeometry(Window, Window._Position)
			if MainScrollbarGeometry then
				local ScrollPercent = GetScrollbarScrollPercent(CurrentMousePosition.Y, MainScrollbarGeometry.TrackPosition.Y, MainScrollbarGeometry.TrackHeight, MainScrollbarGeometry.HandleHeight)
				Window._ScrollOffset = ScrollPercent * Window._MaxScroll
				Window:RecalculateLayout()
			end
		end

		for SectionIndex, ScrollableSection in ipairs(Window:GetActiveSections()) do
			if ScrollableSection._DraggingScrollbar and IsPrimaryMouseButtonDown and ScrollableSection._MaxHeight and ScrollableSection._SectionMaxScroll > 0 then
				local SectionScrollbarGeometry = GetSectionScrollbarGeometry(ScrollableSection, Window)
				if SectionScrollbarGeometry then
					local ScrollPercent = GetScrollbarScrollPercent(CurrentMousePosition.Y, SectionScrollbarGeometry.TrackPosition.Y, SectionScrollbarGeometry.TrackHeight, SectionScrollbarGeometry.HandleHeight)
					ScrollableSection._SectionScrollOffset = ScrollPercent * ScrollableSection._SectionMaxScroll
					Window:RecalculateLayout()
				end
			end
		end

		if ShouldProcessPrimaryClick then
			if Window._SearchButtonHovered then
				SetSearchActive(not Window._SearchActive, true)
				Window:RecalculateLayout()
				return
			end

			if Window._SearchActive then
				if Window._HoveredSearchResultIndex then
					local ResultIndex = Window._HoveredSearchResultIndex
					local MatchedItem = Window._SearchResults[ResultIndex]
					if MatchedItem then
						local TargetSection = MatchedItem.Section
						local TargetElement = MatchedItem.Element

						if TargetSection._PageIndex and TargetSection._PageIndex ~= Window._ActivePageIndex then
							Window._ActivePageIndex = TargetSection._PageIndex
							Window._ScrollOffset = 0
							UpdateElementsVisibility()
						end

						local TargetScroll = TargetSection._PositionY - Theme.TitleBarHeight - 10
						Window._ScrollOffset = math.clamp(TargetScroll, 0, Window._MaxScroll)

						Window._HighlightedElement = TargetElement
						TargetElement._HighlightTime = tick()

						SetSearchActive(false, true)

						Window:RecalculateLayout()
						return
					end
				elseif Window._SearchTextBox._IsHovered then
					SetSearchTextBoxFocus(true)
					Window:RecalculateLayout()
					return
				else
					SetSearchTextBoxFocus(false)
					Window:RecalculateLayout()
				end
			end

			if Window._CloseButtonHovered then
				InvokeCallback(Window.OnExit)
				Window:Destroy()
				return
			end

			if Window._ResizeGripHovered then
				Window._Resizing = true
				Window._ResizeStartMousePosition = CurrentMousePosition
				Window._ResizeStartSize = Vector2.new(Theme.WindowWidth, Window._VisibleHeight)
				RefreshInterfaceCaptureState()
				return
			end

			if Window._MaxScroll > 0 and Window._ScrollbarHovered then
				local MainScrollbarGeometry = GetMainScrollbarGeometry(Window, Window._Position)
				if MainScrollbarGeometry then
					Window._ScrollOffset = GetScrollbarClickPercent(CurrentMousePosition.Y, MainScrollbarGeometry.TrackPosition.Y, MainScrollbarGeometry.TrackHeight) * Window._MaxScroll
					Window._DraggingScrollbar = true
					RefreshInterfaceCaptureState()
					return
				end
			end

			for SectionIndex, ScrollableSection in ipairs(Window:GetActiveSections()) do
				if ScrollableSection._MaxHeight and ScrollableSection._SectionMaxScroll > 0 and ScrollableSection._ScrollbarHovered then
					local SectionScrollbarGeometry = GetSectionScrollbarGeometry(ScrollableSection, Window)
					if SectionScrollbarGeometry then
						ScrollableSection._SectionScrollOffset = GetScrollbarClickPercent(CurrentMousePosition.Y, SectionScrollbarGeometry.TrackPosition.Y, SectionScrollbarGeometry.TrackHeight) * ScrollableSection._SectionMaxScroll
						ScrollableSection._DraggingScrollbar = true
						RefreshInterfaceCaptureState()
						return
					end
				end
			end

			if Window._TabBarHeight > 0 then
				for PageIndex, Page in ipairs(Window._Pages) do
					if Page._IsHovered then
						if PageIndex ~= Window._ActivePageIndex then
							Window._ActivePageIndex = PageIndex
							Window._ScrollOffset = 0
							UpdateElementsVisibility()
							Window:RecalculateLayout()
						end
						return
					end
				end
			end

			if Window._TitleBarHovered then
				Window._Dragging = true
				Window._DragOffset = CurrentMousePosition - Window._Position
				RefreshInterfaceCaptureState()
				return
			end

			if Window._ActiveDropdown then
				local ExpandedDropdown = Window._ActiveDropdown

				for ItemIndex, ItemData in ipairs(ExpandedDropdown._ItemDrawingObjects) do
					if ItemData._IsHovered then
						ExpandedDropdown:SetValue(ItemData.Value)
						ExpandedDropdown:Toggle()
						return
					end
				end
			end

			if Window._ActiveColorPicker then
				local ColorPicker = Window._ActiveColorPicker
				if not ColorPicker._PopupHovered then
					ColorPicker:ClosePopup()

				else
					if ColorPicker._SaveButtonHovered then
						ColorPicker:SelectSwatch(ColorPicker._TempSelectedSwatchIndex)
						ColorPicker:ClosePopup()
						return
					end
					if ColorPicker._ExitButtonHovered then
						ColorPicker:ClosePopup()
						return
					end
					if ColorPicker._HoveredSwatchIndex then
						local SwatchIndex = ColorPicker._HoveredSwatchIndex
						ColorPicker._TempSelectedSwatchIndex = SwatchIndex
						ColorPicker._TempSelectedColor = ColorPalette[SwatchIndex]

						if not UseImmediateMode then
							if ColorPicker._PopupPreviewDrawing then
								SetRenderProperty(ColorPicker._PopupPreviewDrawing, "Color", ColorPicker._TempSelectedColor)
							end
							for SwatchPairIndex, SwatchPair in ipairs(ColorPicker._PopupSwatchDrawings or {}) do
								if SwatchPair.Border then
									local IsSwatchSelected = SwatchPairIndex == SwatchIndex
									ApplyDrawingProperties(SwatchPair.Border, { Color = IsSwatchSelected and Theme.ColorPickerSelectedBorder or Theme.ColorPickerBorder, Thickness = IsSwatchSelected and 2 or 1 })
								end
							end
						end
						return
					end
					return
				end
			end

			for SectionIndex, Section in ipairs(Window:GetActiveSections()) do
				for ElementIndex, Element in ipairs(Section._Elements) do
					if Element._IsHovered then
						if Element._Type == "TextButton" then
							ClearFocusedTextBoxes()
							InvokeCallback(Element._Callback)
							return

						elseif Element._Type == "TextLabel" then
							ClearFocusedTextBoxes()
							InvokeCallback(Element._Callback)
							return

						elseif Element._Type == "Toggle" then
							ClearFocusedTextBoxes()
							Element:Toggle()
							return

						elseif Element._Type == "Dropdown" then
							ClearFocusedTextBoxes()
							Element:Toggle()
							return

						elseif Element._Type == "Slider" then
							ClearFocusedTextBoxes()
							Window._ActiveSlider = Element
							Element:_UpdateValueFromMousePosition(CurrentMousePosition.X)
							RefreshInterfaceCaptureState()
							return

						elseif Element._Type == "TextBox" then
							Element._IsFocused = true

							Element._CursorVisible = true
							Element._CursorBlinkTime = tick()
							Window:SetInputBlocking("Typing", true)
							return

						elseif Element._Type == "ColorPicker" then
							ClearFocusedTextBoxes()
							if Element._IsSwatchHovered then
								if Window._ActiveColorPicker == Element then
									Element:ClosePopup()
								else
									if Window._ActiveColorPicker then Window._ActiveColorPicker:ClosePopup() end
									Element:OpenPopup()
								end
								return
							end
						end
					end
				end
			end

			ClearFocusedTextBoxes()

		end

		if not UseImmediateMode and AnimationChanged then
			Window:RecalculateLayout()
		end
	end))

	table.insert(Window._Connections, InputChangedSignalConnect(UserInputService.InputChanged, NewCClosure(function()
		if not Window._Visible or Window._Destroyed then return end
		if not UserInputService.OnScreenKeyboardVisible then return end

		local KeyboardSize = UserInputService.OnScreenKeyboardSize
		if KeyboardSize.Y <= 0 then return end

		local Camera = GetCurrentCamera()
		local ViewportHeight = Camera and Camera.ViewportSize.Y or 600

		local MaxAllowedY = ViewportHeight - KeyboardSize.Y - Window._TotalHeight - 8
		if Window._Position.Y > MaxAllowedY then
			Window._Position = Vector2.new(Window._Position.X, math.max(8, MaxAllowedY))
			Window:RecalculateLayout()
		end
	end)))

	table.insert(Window._Connections, HeartbeatConnection)
	table.insert(Library._Windows, Window)

	if UseImmediateMode and DrawingImmediateGetPaint then
		local PaintConnection = DrawingImmediateGetPaint(1):Connect(NewCClosure(function()
			if Window._Destroyed or not Library._Visible or not Window._Visible then return end

			local WindowPosition = Window._Position
			local ViewportStart, ViewportEnd = GetWindowContentViewportYRange(Window, WindowPosition.Y)
			local WindowWidth = Theme.WindowWidth

			local ContentHeight = Window._VisibleHeight

			local BodyPosition = Vector2.new(WindowPosition.X, WindowPosition.Y + Theme.TitleBarHeight)
			local BodySize = Vector2.new(WindowWidth, ContentHeight)

			local FullWindowSize = Vector2.new(WindowWidth, Theme.TitleBarHeight + ContentHeight)
			for GlowIndex = 1, 3 do
				DrawingImmediateRectangle(WindowPosition - Vector2.new(GlowIndex, GlowIndex), FullWindowSize + Vector2.new(GlowIndex * 2, GlowIndex * 2), Theme.TitleBarSeparator, 0.08 / GlowIndex, 0, 1)
			end

			DrawingImmediateFilledRectangle(BodyPosition, BodySize, Theme.WindowBackground, 1, 0)
			DrawingImmediateFilledRectangle(BodyPosition, Vector2.new(WindowWidth, math.min(58, ContentHeight * 0.24)), Theme.WindowSurfaceHighlight, 0.26, 0)
			DrawingImmediateFilledRectangle(BodyPosition + Vector2.new(0, math.max(0, ContentHeight - 72)), Vector2.new(WindowWidth, math.min(72, ContentHeight)), Theme.WindowSurfaceShade, 0.22, 0)
			DrawingImmediateRectangle(BodyPosition, BodySize, Theme.WindowBorder, 0.8, 0, 1)

			DrawingImmediateLine(
				WindowPosition,
				Vector2.new(WindowPosition.X + WindowWidth, WindowPosition.Y),
				Theme.TitleBarSeparator,
				0.55,
				1.25
			)

			local CurrentMousePosition = GetMouseLocation(UserInputService)
			local MouseInsideBody = IsPointInsideRectangle(CurrentMousePosition, BodyPosition, BodySize)

			local TitleBarCheckPos = Vector2.new(WindowPosition.X, WindowPosition.Y)
			local TitleBarCheckSize = Vector2.new(WindowWidth, Theme.TitleBarHeight)
			local MouseInsideWindow = MouseInsideBody or IsPointInsideRectangle(CurrentMousePosition, TitleBarCheckPos, TitleBarCheckSize)
			Window._MouseInWindow = MouseInsideWindow
			if MouseInsideWindow ~= Window._ScrollSinkActive then
				Window._ScrollSinkActive = MouseInsideWindow
				Window:SetInputBlocking("Scroll", MouseInsideWindow)
			end

			if MouseInsideWindow ~= Window._CameraSinkActive then
				Window._CameraSinkActive = MouseInsideWindow
				Window:SetInputBlocking("Camera", MouseInsideWindow)
			end
			RefreshInterfaceCaptureState()

			local TitleBarSize = Vector2.new(WindowWidth, Theme.TitleBarHeight)
			DrawingImmediateFilledRectangle(WindowPosition, TitleBarSize, Theme.TitleBarBackground, 1, 0)
			DrawingImmediateFilledRectangle(WindowPosition, Vector2.new(WindowWidth, math.max(6, Theme.TitleBarHeight * 0.45)), Theme.TitleBarHighlight, 0.32, 0)
			DrawingImmediateFilledRectangle(WindowPosition, Vector2.new(WindowWidth * 0.58, Theme.TitleBarHeight), Theme.TitleBarAccentWash, 0.34, 0)
			Window._TitleBarHovered = IsPointInsideRectangle(CurrentMousePosition, WindowPosition, TitleBarSize)
			local ResizeGripSize = math.max(18, Theme.InnerMargin)
			Window._ResizeGripRegion = {
				Position = Vector2.new(WindowPosition.X + WindowWidth - ResizeGripSize, WindowPosition.Y + Theme.TitleBarHeight + ContentHeight - ResizeGripSize),
				Size = Vector2.new(ResizeGripSize, ResizeGripSize)
			}
			Window._ResizeGripHovered = IsPointInsideRectangle(CurrentMousePosition, Window._ResizeGripRegion.Position, Window._ResizeGripRegion.Size)

			local SeparatorStart = Vector2.new(WindowPosition.X, WindowPosition.Y + Theme.TitleBarHeight)
			local SeparatorEnd = Vector2.new(WindowPosition.X + WindowWidth, WindowPosition.Y + Theme.TitleBarHeight)
			DrawingImmediateLine(SeparatorStart, SeparatorEnd, Theme.TitleBarSeparator, 0.85, 2)

			if Window._TabBarHeight > 0 then
				local TabBarPos = WindowPosition + Vector2.new(0, Theme.TitleBarHeight)
				local TabBarSize = Vector2.new(WindowWidth, Window._TabBarHeight)
				DrawingImmediateFilledRectangle(TabBarPos, TabBarSize, Theme.WindowBackground, 1, 0)
				DrawingImmediateLine(
					TabBarPos + Vector2.new(0, Window._TabBarHeight),
					TabBarPos + Vector2.new(WindowWidth, Window._TabBarHeight),
					Theme.TitleBarSeparator,
					0.22,
					1
				)

				local TabCount = #Window._Pages
				local TabBarPadding = 10
				local TabGap = 6
				local TabWidth = math.max(92, (WindowWidth - (TabBarPadding * 2) - (TabGap * (math.min(TabCount, 5) - 1))) / math.min(TabCount, 5))
				local MaxTabScroll = math.max(0, (TabCount * (TabWidth + TabGap)) - TabGap - (WindowWidth - TabBarPadding * 2))
				Window._TabScrollOffset = math.clamp(Window._TabScrollOffset or 0, 0, MaxTabScroll)
				for PageIndex, Page in ipairs(Window._Pages) do
					local TabX = WindowPosition.X + TabBarPadding + (PageIndex - 1) * (TabWidth + TabGap) - Window._TabScrollOffset
					local TabY = WindowPosition.Y + Theme.TitleBarHeight + 5
					local TabHeight = Window._TabBarHeight - 10
					
					if TabX >= WindowPosition.X - 10 and TabX + TabWidth <= WindowPosition.X + WindowWidth + 10 then
						local TextSize = GetTextBounds(Page.Title, Theme.ElementFontSize)
						local TextX = TabX + (TabWidth - TextSize.X) / 2
						local TextY = TabY + (TabHeight - TextSize.Y) / 2

						local IsActive = (PageIndex == Window._ActivePageIndex)
						local HoverFactor = Page._HoverFactor or 0
						local ActiveFactor = IsActive and 1 or 0
						local TabBackgroundColor = Theme.TabBackground:Lerp(Theme.TabBackgroundHover, HoverFactor):Lerp(Theme.TabBackgroundActive, ActiveFactor)
						DrawingImmediateFilledRectangle(Vector2.new(TabX, TabY), Vector2.new(TabWidth, TabHeight), TabBackgroundColor, IsActive and 0.98 or 0.68 + HoverFactor * 0.18, 0)
						
						local BaseColor = IsActive and Theme.TitleBarText or Theme.LabelText
						local TargetColor = IsActive and Theme.TitleBarTextHover or Theme.LabelTextHover
						local TabColor = BaseColor:Lerp(TargetColor, HoverFactor)

						DrawingImmediateText(
							Vector2.new(TextX, TextY),
							Theme.Font, Theme.ElementFontSize, TabColor, 1, Page.Title, false
						)

						if IsActive or HoverFactor > 0.01 then
							local UnderlineY = TabY + TabHeight - 2
							local UnderlineWidth = math.min(TabWidth - 18, TextSize.X + 18)
							local UnderlineX = TabX + (TabWidth - UnderlineWidth) / 2
							local UnderlineAlpha = IsActive and 1 or HoverFactor
							local UnderlineColor = Theme.TitleBarSeparator:Lerp(Theme.TitleBarTextHover, HoverFactor)

							DrawingImmediateLine(
								Vector2.new(UnderlineX, UnderlineY),
								Vector2.new(UnderlineX + UnderlineWidth, UnderlineY),
								UnderlineColor,
								UnderlineAlpha,
								2
							)
						end
					end
				end
				if MaxTabScroll > 0 then
					local ScrollProgress = Window._TabScrollOffset / MaxTabScroll
					local AvailableTabWidth = WindowWidth - TabBarPadding * 2
					local HandleWidth = math.clamp((AvailableTabWidth / (TabCount * (TabWidth + TabGap))) * AvailableTabWidth, 30, AvailableTabWidth)
					local HandleX = WindowPosition.X + TabBarPadding + (AvailableTabWidth - HandleWidth) * ScrollProgress
					local HandleY = WindowPosition.Y + Theme.TitleBarHeight + Window._TabBarHeight - 1.5

					DrawingImmediateLine(
						Vector2.new(HandleX, HandleY),
						Vector2.new(HandleX + HandleWidth, HandleY),
						Theme.TitleBarSeparator,
						1.0,
						3
					)
				end
			end

			local TitleTextX   = WindowPosition.X + Theme.InnerMargin + 12
			local TitleTextY   = WindowPosition.Y + (Theme.TitleBarHeight - Theme.TitleFontSize) / 2 + 2
			local TitleTextColor   = Theme.TitleBarText:Lerp(Theme.TitleBarTextHover, Window._TitleTextHoverFactor or 0)

			local TitleDotCenter = Vector2.new(WindowPosition.X + Theme.InnerMargin + 4, WindowPosition.Y + Theme.TitleBarHeight / 2)
			DrawingImmediateCircle(TitleDotCenter, 5, Theme.TitleBarSeparator, 0.4, 12, 1)
			DrawingImmediateFilledCircle(TitleDotCenter, 2.5, Theme.TitleBarSeparator, 12, 1)
			DrawingImmediateText(
				Vector2.new(TitleTextX, TitleTextY),
				Theme.Font, Theme.TitleFontSize, TitleTextColor, 1, Window._Title, false
			)

			if Window._CloseButtonRegion then
				local CloseRegion = Window._CloseButtonRegion
				local CloseColor = Theme.CloseButtonBackground:Lerp(Theme.CloseButtonHover, Window._CloseButtonHoverFactor or 0)
				DrawingImmediateFilledRectangle(CloseRegion.Position, CloseRegion.Size, CloseColor, 0.9, 0)

				DrawingImmediateRectangle(CloseRegion.Position, CloseRegion.Size,
					Theme.CloseButtonBorder:Lerp(Theme.CloseButtonHover, Window._CloseButtonHoverFactor or 0),
					0.9, 0, 1)

				DrawingImmediateText(
					GetCenteredTextPosition("X", 14, CloseRegion.Position, CloseRegion.Size),
					Theme.Font, 14, Theme.TitleBarText:Lerp(Theme.TitleBarTextHover, Window._CloseButtonHoverFactor or 0), 1, "X", false
				)
			end

			if Window._SearchButtonRegion then
				local MouseIsOverSearch = IsPointInsideRectangle(CurrentMousePosition, Window._SearchButtonRegion.Position, Window._SearchButtonRegion.Size)
				local SearchIconColor = Window._SearchActive and Theme.TitleBarSeparator or (MouseIsOverSearch and Theme.TitleBarTextHover or Theme.TitleBarText)
				local SearchIconCenter = Window._SearchButtonRegion.Position + Vector2.new(11, 11)

				DrawingImmediateCircle(SearchIconCenter, 4.5, SearchIconColor, 1, 12, 1)
				DrawingImmediateLine(SearchIconCenter + Vector2.new(3, 3), SearchIconCenter + Vector2.new(8, 8), SearchIconColor, 1, 1.5)
			end

			for SectionIndex, Section in ipairs(Window:GetActiveSections()) do
				local SectionYPosition = WindowPosition.Y + Section._PositionY - Window._ScrollOffset

				local SectionFullHeight = Section._ContentHeight or Theme.ElementHeight
				if SectionYPosition + SectionFullHeight > ViewportStart and SectionYPosition < ViewportEnd then
					local SectionHeaderPosition = Vector2.new(WindowPosition.X + Section._PositionX, SectionYPosition)
					local SectionHeaderSize = Vector2.new(Section._Width, Theme.ElementHeight)
					local SectionFullSize = Vector2.new(Section._Width, SectionFullHeight)

					Section._IsHovered = IsPointInsideRectangle(CurrentMousePosition, SectionHeaderPosition, SectionHeaderSize)

					local ClippedBgPos, ClippedBgSize = ClipRectangleToYRange(SectionHeaderPosition, SectionFullSize, ViewportStart, ViewportEnd)
					if ClippedBgPos and ClippedBgSize then
						DrawingImmediateFilledRectangle(ClippedBgPos, ClippedBgSize, Theme.SectionBodyBackground, 1, 0)
						local SectionBorderColor = Theme.WindowBorder:Lerp(Theme.WindowBorderHover, Section._HoverFactor or 0)
						DrawingImmediateRectangle(ClippedBgPos, ClippedBgSize, SectionBorderColor, 0.6, 0, 1)
					end

					local LeftAccentColor = Theme.TitleBarSeparator:Lerp(Theme.SectionTextHover, Section._HoverFactor or 0)
					local LeftAccentFrom, LeftAccentTo = ClipVerticalLineToYRange(SectionHeaderPosition, Vector2.new(SectionHeaderPosition.X, SectionHeaderPosition.Y + SectionFullHeight), ViewportStart, ViewportEnd)
					if LeftAccentFrom and LeftAccentTo then
						DrawingImmediateLine(LeftAccentFrom, LeftAccentTo, LeftAccentColor, LerpValue(0.35, 0.7, Section._HoverFactor or 0), 1)
					end

					local SectionHeaderBg = Theme.SectionBackground:Lerp(Theme.SectionBackgroundHover, Section._HoverFactor or 0)
					local ClippedHeaderPos, ClippedHeaderSize = ClipRectangleToYRange(SectionHeaderPosition, SectionHeaderSize, ViewportStart, ViewportEnd)
					if ClippedHeaderPos and ClippedHeaderSize then
						DrawingImmediateFilledRectangle(ClippedHeaderPos, ClippedHeaderSize, SectionHeaderBg, 1, 0)
					end

					local SectionAccentAlpha = LerpValue(0.7, 1, Section._HoverFactor or 0)
					local SectionAccentStart, SectionAccentEnd = ClipHorizontalLineToYRange(
						Vector2.new(SectionHeaderPosition.X, SectionHeaderPosition.Y + Theme.ElementHeight),
						Vector2.new(SectionHeaderPosition.X + Section._Width, SectionHeaderPosition.Y + Theme.ElementHeight),
						ViewportStart, ViewportEnd
					)
					if SectionAccentStart and SectionAccentEnd then
						DrawingImmediateLine(SectionAccentStart, SectionAccentEnd, Theme.TitleBarSeparator, SectionAccentAlpha, LerpValue(1, 2, Section._HoverFactor or 0))
					end

					local SectionTitleColor = Theme.SectionText:Lerp(Theme.SectionTextHover, Section._HoverFactor or 0)
					local TitleY = SectionYPosition + (Theme.ElementHeight - Theme.SectionFontSize) / 2
					if TitleY >= ViewportStart and TitleY + Theme.SectionFontSize <= ViewportEnd then
						DrawingImmediateText(
							Vector2.new(WindowPosition.X + Section._PositionX + 10, TitleY),
							Theme.Font, Theme.SectionFontSize, SectionTitleColor, 1, Section._Title, false
						)
					end

					local SectionScrollbarGeometry = GetSectionScrollbarGeometry(Section, Window)
					if SectionScrollbarGeometry then
						local ScrollHandleColor = Theme.ScrollbarHandle:Lerp(Theme.ScrollbarHandleHover, Section._ScrollbarHoverFactor or 0)

						local TrackPos, TrackSize = ClipRectangleToYRange(
							SectionScrollbarGeometry.TrackPosition,
							SectionScrollbarGeometry.TrackSize,
							ViewportStart, ViewportEnd
						)
						if TrackPos and TrackSize then
							DrawingImmediateFilledRectangle(TrackPos, TrackSize, Theme.ScrollbarBackground, 1, 0)
						end

						local HandlePos, HandleSize = ClipRectangleToYRange(
							SectionScrollbarGeometry.HandlePosition,
							SectionScrollbarGeometry.HandleSize,
							ViewportStart, ViewportEnd
						)
						if HandlePos and HandleSize then
							DrawingImmediateFilledRectangle(HandlePos, HandleSize, ScrollHandleColor, 1, 0)
						end
					end
				end

				for ElementIndex, Element in ipairs(Section._Elements) do
					local ElementYPosition = WindowPosition.Y + Element._PositionY - Window._ScrollOffset

					local IsElementVisible = IsElementVisibleInViewport(ElementYPosition, Element._Height, Section, Window, WindowPosition.Y)

					if IsElementVisible then
						local ElementPosition = Vector2.new(WindowPosition.X + Element._PositionX, ElementYPosition)
						local ElementSize = Vector2.new(Element._Width - (Window._MaxScroll > 0 and Theme.ScrollbarWidth + 4 or 0), Element._Height)

						local AllowedMinY, AllowedMaxY = GetSectionAllowedYRange(Section, Window, WindowPosition.Y)

						if Element._Type == "TextLabel" then
							local LabelAccentAlpha = LerpValue(0.4, 0.85, Element._HoverFactor or 0)
							local LabelTextColor   = Theme.LabelText:Lerp(Theme.LabelTextHover, Element._HoverFactor or 0)
							local AccentFrom, AccentTo = ClipVerticalLineToYRange(
								Vector2.new(ElementPosition.X, ElementYPosition + 4),
								Vector2.new(ElementPosition.X, ElementYPosition + Element._Height - 4),
								AllowedMinY, AllowedMaxY
							)
							if AccentFrom and AccentTo then
								DrawingImmediateLine(AccentFrom, AccentTo, Theme.SectionText, LabelAccentAlpha, LerpValue(1, 2, Element._HoverFactor or 0))
							end

							local VerticalPadding     = LabelVerticalPadding(Theme.ElementFontSize)
							local LineHeight  = FontLineHeight(Theme.ElementFontSize)
							local HorizontalInset   = FontHorizontalInset(Theme.ElementFontSize)
							local Lines    = Element._WrappedLines or { Element._Text }
							for LineIndex, LineText in ipairs(Lines) do
								local LineY = ElementYPosition + VerticalPadding + (LineIndex - 1) * LineHeight
								if LineY >= AllowedMinY and LineY + LineHeight <= AllowedMaxY then
									DrawingImmediateText(
										Vector2.new(
											WindowPosition.X + Element._PositionX + HorizontalInset,
											LineY
										),
										Theme.Font, Theme.ElementFontSize, LabelTextColor, 1, LineText, false
									)
								end
							end
						elseif Element._Type == "TextButton" then
							local ButtonColor = Theme.ButtonBackground:Lerp(Theme.ButtonBackgroundHover, Element._HoverFactor or 0)
							local ClippedPos, ClippedSize = ClipRectangleToYRange(ElementPosition, ElementSize, AllowedMinY, AllowedMaxY)
							if ClippedPos and ClippedSize then
								DrawingImmediateFilledRectangle(ClippedPos, ClippedSize, ButtonColor, 1, 0)
								DrawingImmediateRectangle(ClippedPos, ClippedSize, Theme.ButtonBorder, 0.8, 0, 1)
							end

							if (Element._HoverFactor or 0) > 0.01 then
								local AccentFrom, AccentTo = ClipVerticalLineToYRange(
									Vector2.new(ElementPosition.X, ElementYPosition + 3),
									Vector2.new(ElementPosition.X, ElementYPosition + Element._Height - 3),
									AllowedMinY, AllowedMaxY
								)
								if AccentFrom and AccentTo then
									DrawingImmediateLine(AccentFrom, AccentTo, Theme.SectionText, Element._HoverFactor or 0, 2)
								end
							end

							local TextY = ElementYPosition + (Element._Height - Theme.ElementFontSize) / 2
							if TextY >= AllowedMinY and TextY + Theme.ElementFontSize <= AllowedMaxY then
								DrawingImmediateText(
									Vector2.new(WindowPosition.X + Element._PositionX + 10, TextY),
									Theme.Font, Theme.ElementFontSize, Theme.ButtonText, 1, Element._Text, false
								)
							end
						elseif Element._Type == "Toggle" then
							local ToggleBg = Theme.ButtonBackground:Lerp(Theme.ButtonBackgroundHover, Element._HoverFactor or 0)
							local ClippedPos, ClippedSize = ClipRectangleToYRange(ElementPosition, ElementSize, AllowedMinY, AllowedMaxY)
							if ClippedPos and ClippedSize then
								DrawingImmediateFilledRectangle(ClippedPos, ClippedSize, ToggleBg, 1, 0)
								DrawingImmediateRectangle(ClippedPos, ClippedSize, Theme.ButtonBorder, 0.8, 0, 1)
							end

							if (Element._ActiveFactor or 0) > 0.01 then
								local AccentFrom, AccentTo = ClipVerticalLineToYRange(
									Vector2.new(ElementPosition.X, ElementYPosition + 3),
									Vector2.new(ElementPosition.X, ElementYPosition + Element._Height - 3),
									AllowedMinY, AllowedMaxY
								)
								if AccentFrom and AccentTo then
									DrawingImmediateLine(AccentFrom, AccentTo, Theme.ToggleActive, Element._ActiveFactor or 0, 2)
								end
							end

							local TextY = ElementYPosition + (Element._Height - Theme.ElementFontSize) / 2
							if TextY >= AllowedMinY and TextY + Theme.ElementFontSize <= AllowedMaxY then
								DrawingImmediateText(
									Vector2.new(WindowPosition.X + Element._PositionX + 10, TextY),
									Theme.Font, Theme.ElementFontSize, Theme.ButtonText, 1, Element._Text, false
								)
							end

							local PipX = WindowPosition.X + Element._PositionX + ElementSize.X - 14
							local PipY = ElementYPosition + Element._Height / 2
							local PipColor = Theme.ToggleInactive:Lerp(Theme.ToggleActive, Element._ActiveFactor or 0)
							if PipY - 5 >= AllowedMinY and PipY + 5 <= AllowedMaxY then
								DrawingImmediateFilledCircle(Vector2.new(PipX, PipY), 5, PipColor, 20, 1)
							end
						elseif Element._Type == "TextBox" then
							if Element._IsFocused then
								local Now = tick()
								if Now - Element._CursorBlinkTime >= 0.53 then
									Element._CursorBlinkTime = Now
									Element._CursorVisible = not Element._CursorVisible
								end
							else
								Element._CursorVisible = false
								Element._CursorBlinkTime = 0
							end

							local TextBoxBackgroundColor = Theme.TextBoxBackground:Lerp(Theme.TextBoxBackgroundHover, Element._HoverFactor or 0)
							local TextBoxBorderColor = Theme.TextBoxBorder:Lerp(Theme.TextBoxBorderFocused, Element._FocusFactor or 0)
							local TextBoxBorderThickness = LerpValue(1, 2, Element._FocusFactor or 0)

							local ClippedPos, ClippedSize = ClipRectangleToYRange(ElementPosition, ElementSize, AllowedMinY, AllowedMaxY)
							if ClippedPos and ClippedSize then
								DrawingImmediateFilledRectangle(ClippedPos, ClippedSize, TextBoxBackgroundColor, 1, 0)
								DrawingImmediateRectangle(ClippedPos, ClippedSize, TextBoxBorderColor, 1, 0, TextBoxBorderThickness)
							end

							if (Element._FocusFactor or 0) > 0.01 then
								local AccentFrom, AccentTo = ClipVerticalLineToYRange(
									Vector2.new(ElementPosition.X, ElementYPosition + 3),
									Vector2.new(ElementPosition.X, ElementYPosition + Element._Height - 3),
									AllowedMinY, AllowedMaxY
								)
								if AccentFrom and AccentTo then
									DrawingImmediateLine(AccentFrom, AccentTo, Theme.TextBoxBorderFocused, Element._FocusFactor or 0, 2)
								end
							end

							local TextY = ElementYPosition + (Element._Height - Theme.ElementFontSize) / 2
							if TextY >= AllowedMinY and TextY + Theme.ElementFontSize <= AllowedMaxY then
								if Element._Text and Element._Text ~= "" then
									DrawingImmediateText(
										Vector2.new(WindowPosition.X + Element._PositionX + 8, TextY),
										Theme.Font, Theme.ElementFontSize, Theme.LabelText, 1, string.format("%s: ", Element._Text), false
									)
								end
							end

							local LabelWidth = Element._Text ~= "" and math.floor(#Element._Text * Theme.ElementFontSize * Theme.FontCharWidthRatio * 1.2) + 18 or 8
							local InputStartX = WindowPosition.X + Element._PositionX + LabelWidth + 4

							local HasValue = Element._Value ~= ""
							local DisplayText = HasValue and Element._Value or Element._Placeholder
							local DisplayColor = HasValue and Theme.TextBoxText or Theme.TextBoxPlaceholder
							local CursorSuffix = (Element._IsFocused and Element._CursorVisible) and "|" or (Element._IsFocused and " " or "")

							local ElementRightEdge = WindowPosition.X + Element._PositionX + ElementSize.X
							local AvailableInputWidth = ElementRightEdge - InputStartX - 8
							local CharacterWidth = Theme.ElementFontSize * Theme.FontCharWidthRatio * 1.25
							local MaxChars = math.max(1, math.floor(AvailableInputWidth / CharacterWidth))
							local ClippedText = ClipEditableTextForWidth(DisplayText, MaxChars, Element._IsFocused)

							if Element._IsSelected and HasValue then
								local SelectionWidth = math.min(#ClippedText * CharacterWidth, AvailableInputWidth)
								local SelPos = Vector2.new(InputStartX - 2, ElementYPosition + (Element._Height - Theme.ElementFontSize) / 2 - 2)
								local SelSize = Vector2.new(SelectionWidth + 4, Theme.ElementFontSize + 4)
								local ClippedSelPos, ClippedSelSize = ClipRectangleToYRange(SelPos, SelSize, AllowedMinY, AllowedMaxY)
								if ClippedSelPos and ClippedSelSize then
									DrawingImmediateFilledRectangle(ClippedSelPos, ClippedSelSize, Theme.TextBoxSelection, 0.5, 0)
								end
							end

							if TextY >= AllowedMinY and TextY + Theme.ElementFontSize <= AllowedMaxY then
								DrawingImmediateText(
									Vector2.new(InputStartX, TextY),
									Theme.Font, Theme.ElementFontSize, DisplayColor, 1, string.format("%s%s", ClippedText, CursorSuffix), false
								)
							end
						elseif Element._Type == "Dropdown" then
							local DropdownBackgroundColor = Theme.DropdownBackground:Lerp(Theme.DropdownHover, Element._HoverFactor or 0)
							local DropdownBorderColor = Theme.DropdownBorder:Lerp(Theme.DropdownBorderHover, Element._HoverFactor or 0):Lerp(Theme.SectionText, Element._ExpandFactor or 0)
							local DropdownBorderThickness = LerpValue(1, 2, math.max(Element._HoverFactor or 0, Element._ExpandFactor or 0))
							local ClippedPos, ClippedSize = ClipRectangleToYRange(ElementPosition, ElementSize, AllowedMinY, AllowedMaxY)
							if ClippedPos and ClippedSize then
								DrawingImmediateFilledRectangle(ClippedPos, ClippedSize, DropdownBackgroundColor, 1, 0)
								DrawingImmediateRectangle(ClippedPos, ClippedSize, DropdownBorderColor, 0.8, 0, DropdownBorderThickness)
							end

							local AccentAlpha = (Element._HoverFactor or 0) * (1 - (Element._ExpandFactor or 0))
							if AccentAlpha > 0.01 then
								local AccentFrom, AccentTo = ClipVerticalLineToYRange(
									Vector2.new(ElementPosition.X, ElementYPosition + 3),
									Vector2.new(ElementPosition.X, ElementYPosition + Element._Height - 3),
									AllowedMinY, AllowedMaxY
								)
								if AccentFrom and AccentTo then
									DrawingImmediateLine(AccentFrom, AccentTo, Theme.SectionText, AccentAlpha, 2)
								end
							end

							local TextY = ElementYPosition + (Element._Height - Theme.ElementFontSize) / 2
							if TextY >= AllowedMinY and TextY + Theme.ElementFontSize <= AllowedMaxY then
								DrawingImmediateText(
									Vector2.new(WindowPosition.X + Element._PositionX + 8, TextY),
									Theme.Font, Theme.ElementFontSize, Theme.DropdownText, 1, string.format("%s: %s", Element._Text, Element._Value), false
								)
								DrawingImmediateText(
									Vector2.new(WindowPosition.X + Element._PositionX + ElementSize.X - 18, TextY),
									Theme.Font, Theme.ElementFontSize, Theme.DropdownArrow, 1, Element._Expanded and "^" or "v", false
								)
							end

							if Element._Expanded then
								for ItemIndex, ItemData in ipairs(Element._ItemDrawingObjects) do
									local ItemYPosition = WindowPosition.Y + ItemData._PositionY - Window._ScrollOffset
									local ItemSize = Vector2.new(ElementSize.X, Theme.ElementHeight)
									local ItemPosition = Vector2.new(WindowPosition.X + ItemData._PositionX, ItemYPosition)
									local ClippedItemPos, ClippedItemSize = ClipRectangleToYRange(ItemPosition, ItemSize, AllowedMinY, AllowedMaxY)
									if ClippedItemPos and ClippedItemSize then
										local IsHovered = IsPointInsideRectangle(CurrentMousePosition, ItemPosition, ItemSize)
										DrawingImmediateFilledRectangle(ClippedItemPos, ClippedItemSize, IsHovered and Theme.DropdownItemHover or Theme.DropdownItemBackground, 1, 0)

										local ItemSeparatorY = ItemYPosition + Theme.ElementHeight - 1
										local SepFrom, SepTo = ClipHorizontalLineToYRange(
											Vector2.new(ItemPosition.X + 6, ItemSeparatorY),
											Vector2.new(ItemPosition.X + ItemSize.X - 6, ItemSeparatorY),
											AllowedMinY, AllowedMaxY
										)
										if SepFrom and SepTo then
											DrawingImmediateLine(SepFrom, SepTo, Theme.WindowBorder, 0.5, 1)
										end

										local ItemTextY = ItemYPosition + (Theme.ElementHeight - Theme.ElementFontSize) / 2
										if ItemTextY >= AllowedMinY and ItemTextY + Theme.ElementFontSize <= AllowedMaxY then
											DrawingImmediateText(
												Vector2.new(WindowPosition.X + ItemData._PositionX + 12, ItemTextY),
												Theme.Font, Theme.ElementFontSize, IsHovered and Theme.TitleBarText or Theme.DropdownText, 1, ItemData.Value, false
											)
										end
									end
								end
							end
						elseif Element._Type == "Slider" then
							local Value = Element._Value or 0
							local Minimum = Element._MinValue or 0
							local Maximum = Element._MaxValue or 100
							local Range = Maximum - Minimum
							if Range == 0 then Range = 1 end

							local SliderLabelColor = Theme.SliderText:Lerp(Theme.TitleBarText, Element._HoverFactor or 0)
							local TextY = ElementYPosition
							if TextY >= AllowedMinY and TextY + Theme.ElementFontSize <= AllowedMaxY then
								DrawingImmediateText(
									Vector2.new(WindowPosition.X + Element._PositionX, TextY),
									Theme.Font, Theme.ElementFontSize, SliderLabelColor, 1, Element._Text, false
								)
								local ValueColor = Theme.SectionText:Lerp(Theme.SectionTextHover, Element._ActiveFactor or 0)
								DrawingImmediateText(
									Vector2.new(WindowPosition.X + Element._PositionX + Element._TrackTotalWidth - 48, TextY),
									Theme.Font, Theme.ElementFontSize, ValueColor, 1, tostring(Value), false
								)
							end

							local TrackPosition = Vector2.new(WindowPosition.X + (Element._TrackPositionX or Element._PositionX), ElementYPosition + Theme.ElementFontSize + 5)
							local TrackHeight = LerpValue(8, 10, Element._HoverFactor or 0)
							local TrackSize = Vector2.new(Element._TrackTotalWidth, TrackHeight)
							local NormalizedValue = math.clamp((Value - Minimum) / Range, 0, 1)
							local FillWidth = math.floor(Element._TrackTotalWidth * NormalizedValue)
							local FillColor = Theme.SliderTrackFill:Lerp(Theme.SliderTrackFillHover, Element._HoverFactor or 0)

							local ClippedTrackPos, ClippedTrackSize = ClipRectangleToYRange(TrackPosition, TrackSize, AllowedMinY, AllowedMaxY)
							if ClippedTrackPos and ClippedTrackSize then
								DrawingImmediateFilledRectangle(ClippedTrackPos, ClippedTrackSize, Theme.SliderTrackBackground, 1, 0)
								DrawingImmediateRectangle(ClippedTrackPos, ClippedTrackSize, Theme.SliderBorder, 0.7, 0, 1)
							end

							if FillWidth > 0 then
								local ClippedFillPos, ClippedFillSize = ClipRectangleToYRange(TrackPosition, Vector2.new(FillWidth, TrackHeight), AllowedMinY, AllowedMaxY)
								if ClippedFillPos and ClippedFillSize then
									DrawingImmediateFilledRectangle(ClippedFillPos, ClippedFillSize, FillColor, 1, 0)
								end
							end

							local ThumbRadius = LerpValue(7, 9, Element._ThumbHoverFactor or 0)
							local ThumbColor = Theme.SliderThumb:Lerp(Theme.SliderThumbHover, Element._ThumbHoverFactor or 0)
							local ThumbY = TrackPosition.Y + TrackHeight / 2
							if ThumbY - ThumbRadius >= AllowedMinY and ThumbY + ThumbRadius <= AllowedMaxY then
								DrawingImmediateFilledCircle(Vector2.new(TrackPosition.X + FillWidth, ThumbY), ThumbRadius, ThumbColor, 24, 1)
								DrawingImmediateFilledCircle(Vector2.new(TrackPosition.X + FillWidth, ThumbY), 3, FillColor, 16, 1)
							end
						elseif Element._Type == "ColorPicker" then
							local HoverFactor = Element._HoverFactor or 0

							if HoverFactor > 0.01 then
								local ClippedPos, ClippedSize = ClipRectangleToYRange(ElementPosition, ElementSize, AllowedMinY, AllowedMaxY)
								if ClippedPos and ClippedSize then
									DrawingImmediateFilledRectangle(ClippedPos, ClippedSize, Theme.ButtonBackground, HoverFactor * 0.55, 0)
								end
								local AccentFrom, AccentTo = ClipVerticalLineToYRange(
									Vector2.new(ElementPosition.X, ElementYPosition + 3),
									Vector2.new(ElementPosition.X, ElementYPosition + Element._Height - 3),
									AllowedMinY, AllowedMaxY
								)
								if AccentFrom and AccentTo then
									DrawingImmediateLine(AccentFrom, AccentTo, Theme.SectionText, HoverFactor, 2)
								end
							end

							local TextY = ElementYPosition + (Element._Height - Theme.ElementFontSize) / 2
							if TextY >= AllowedMinY and TextY + Theme.ElementFontSize <= AllowedMaxY then
								local ColorPickerTextColor = Theme.LabelText:Lerp(Theme.LabelTextHover, HoverFactor)
								DrawingImmediateText(
									Vector2.new(WindowPosition.X + Element._PositionX + 6, TextY),
									Theme.Font, Theme.ElementFontSize, ColorPickerTextColor, 1, Element._Text, false
								)
							end

							local SwatchSizeValue = Element._SwatchSize or 24
							local SwatchPosition = WindowPosition + Vector2.new(Element._SwatchPositionX, Element._SwatchPositionY - Window._ScrollOffset)
							local SwatchSizeVector = Vector2.new(SwatchSizeValue, SwatchSizeValue)

							local ClippedSwatchPos, ClippedSwatchSize = ClipRectangleToYRange(SwatchPosition, SwatchSizeVector, AllowedMinY, AllowedMaxY)
							if ClippedSwatchPos and ClippedSwatchSize then
								DrawingImmediateFilledRectangle(ClippedSwatchPos, ClippedSwatchSize, Element._Value or Color3.new(1, 1, 1), 1, 0)
								local SwatchBorderColor = Theme.ColorPickerBorder:Lerp(Theme.ColorPickerSwatchHover, HoverFactor)
								local SwatchBorderThick = LerpValue(1, 2, HoverFactor)
								DrawingImmediateRectangle(ClippedSwatchPos, ClippedSwatchSize, SwatchBorderColor, 1, 0, SwatchBorderThick)
							end

							if HoverFactor > 0.01 then
								local ChevronY = SwatchPosition.Y + (SwatchSizeValue - Theme.ElementFontSize) / 2
								if ChevronY >= AllowedMinY and ChevronY + Theme.ElementFontSize - 1 <= AllowedMaxY then
									DrawingImmediateText(
										Vector2.new(SwatchPosition.X - 14, ChevronY),
										Theme.Font, Theme.ElementFontSize - 1, Theme.DropdownArrow, HoverFactor * 0.85, ">", false
									)
								end
							end
						end
					end
				end
			end

			local MainScrollbarGeometry = GetMainScrollbarGeometry(Window, WindowPosition)
			if MainScrollbarGeometry then
				local IsScrollActive = Window._ScrollbarHovered or Window._DraggingScrollbar
				local ScrollHandleColor = IsScrollActive and Theme.ScrollbarHandleHover or Theme.ScrollbarHandle

				DrawingImmediateFilledRectangle(
					MainScrollbarGeometry.TrackPosition,
					MainScrollbarGeometry.TrackSize,
					Theme.ScrollbarBackground, 1, 0
				)

				DrawingImmediateFilledRectangle(
					MainScrollbarGeometry.HandlePosition,
					MainScrollbarGeometry.HandleSize,
					ScrollHandleColor, 1, 0
				)

				if IsScrollActive then
					DrawingImmediateLine(
						MainScrollbarGeometry.HandlePosition + Vector2.new(math.floor(Theme.ScrollbarWidth / 2), 3),
						MainScrollbarGeometry.HandlePosition + Vector2.new(math.floor(Theme.ScrollbarWidth / 2), MainScrollbarGeometry.HandleSize.Y - 3),
						Theme.TitleBarSeparator, 0.7, 1
					)
				end
			end

			local ResizeGripBasePosition = Vector2.new(
				WindowPosition.X + WindowWidth - 18,
				WindowPosition.Y + Theme.TitleBarHeight + ContentHeight - 18
			)
			local ResizeGripColor = Window._ResizeGripHovered and Theme.TitleBarTextHover or Theme.TitleBarSeparator
			for ResizeGripLineIndex = 1, 3 do
				local ResizeGripOffset = ResizeGripLineIndex * 4
				DrawingImmediateLine(
					ResizeGripBasePosition + Vector2.new(18 - ResizeGripOffset, 18),
					ResizeGripBasePosition + Vector2.new(18, 18 - ResizeGripOffset),
					ResizeGripColor,
					Window._ResizeGripHovered and 0.9 or 0.42,
					1.35
				)
			end


			if Window._SearchActive then
				local SearchBarPosition = WindowPosition + Vector2.new(Theme.InnerMargin, Theme.TitleBarHeight + Window._TabBarHeight + 6)
				local SearchBarSize = Vector2.new(Theme.WindowWidth - Theme.InnerMargin * 2, 20)
				Window._SearchTextBoxRegion = { Position = SearchBarPosition, Size = SearchBarSize }

				local SearchTextBorderColor = Window._SearchTextBox._IsFocused and Theme.TextBoxBorderFocused or Theme.TextBoxBorder

				DrawingImmediateFilledRectangle(SearchBarPosition, SearchBarSize, Theme.TextBoxBackground, 1, 0)
				DrawingImmediateRectangle(
					SearchBarPosition,
					SearchBarSize,
					SearchTextBorderColor,
					1,
					0,
					SearchTextBorderColor == Theme.TextBoxBorderFocused and 2 or 1
				)

				local TextboxIconCenter = SearchBarPosition + Vector2.new(12, 10)
				DrawingImmediateCircle(TextboxIconCenter, 3.5, Theme.TextBoxPlaceholder, 1, 12, 1)
				DrawingImmediateLine(
					TextboxIconCenter + Vector2.new(2.5, 2.5),
					TextboxIconCenter + Vector2.new(5.5, 5.5),
					Theme.TextBoxPlaceholder,
					1,
					1.5
				)

				local HasSearchValue = Window._SearchTextBox._Value ~= ""
				local SearchDisplayText = HasSearchValue and Window._SearchTextBox._Value or Window._SearchTextBox._Placeholder

				local AvailableQueryWidth = SearchBarSize.X - 32
				local CharacterWidth = Theme.ElementFontSize * Theme.FontCharWidthRatio * 1.25
				local MaxQueryChars = math.max(1, math.floor(AvailableQueryWidth / CharacterWidth))
				SearchDisplayText = ClipEditableTextForWidth(SearchDisplayText, MaxQueryChars, Window._SearchTextBox._IsFocused)

				if Window._SearchTextBox._IsFocused and Window._SearchTextBox._CursorVisible then
					SearchDisplayText = string.format("%s|", SearchDisplayText)
				end

				local SearchTextColor = HasSearchValue and Theme.TextBoxText or Theme.TextBoxPlaceholder
				DrawingImmediateText(
					SearchBarPosition + Vector2.new(24, (20 - Theme.ElementFontSize) / 2),
					Theme.Font,
					Theme.ElementFontSize,
					SearchTextColor,
					1,
					SearchDisplayText,
					false
				)

				local SearchResultsCount = #Window._SearchResults
				if SearchResultsCount > 0 then
					local DropdownPosition = SearchBarPosition + Vector2.new(0, 20)
					local DropdownHeight = 24 * SearchResultsCount
					local DropdownSize = Vector2.new(SearchBarSize.X, DropdownHeight)
					Window._SearchDropdownRegion = { Position = DropdownPosition, Size = DropdownSize }

					DrawingImmediateFilledRectangle(DropdownPosition, DropdownSize, Theme.DropdownBackground, 1, 0)
					DrawingImmediateRectangle(DropdownPosition, DropdownSize, Theme.DropdownBorder, 0.8, 0, 1)

					if Window._HoveredSearchResultIndex then
						local HoverPositionY = DropdownPosition.Y + (Window._HoveredSearchResultIndex - 1) * 24
						DrawingImmediateFilledRectangle(
							Vector2.new(DropdownPosition.X, HoverPositionY),
							Vector2.new(SearchBarSize.X, 24),
							Theme.DropdownItemHover,
							1,
							0
						)
					end

					for TextIndex = 1, math.min(SearchResultsCount, 5) do
						local ResultItem = Window._SearchResults[TextIndex]
						local TextPosition = DropdownPosition + Vector2.new(10, (TextIndex - 1) * 24 + (24 - Theme.ElementFontSize) / 2)
						local ItemTextColor = (Window._HoveredSearchResultIndex == TextIndex) and Theme.TitleBarTextHover or Theme.DropdownText

						local DisplayResultText = ResultItem.Text
						local AvailableTextWidth = SearchBarSize.X - 20
						local MaxChars = math.max(1, math.floor(AvailableTextWidth / CharacterWidth))
						DisplayResultText = TruncateTextWithAsciiEllipsis(DisplayResultText, MaxChars)

						DrawingImmediateText(
							TextPosition,
							Theme.Font,
							Theme.ElementFontSize,
							ItemTextColor,
							1,
							DisplayResultText,
							false
						)
					end
				else
					Window._SearchDropdownRegion = nil
				end
			else
				Window._SearchTextBoxRegion = nil
				Window._SearchDropdownRegion = nil
			end

			if Window._HighlightedElement then
				local HighlightElement = Window._HighlightedElement
				local ElapsedTime = tick() - HighlightElement._HighlightTime
				if ElapsedTime >= 2.0 then
					Window._HighlightedElement = nil
				else
					local HighlightAlpha = math.clamp(1 - (ElapsedTime / 2.0), 0, 1)
					local HighlightAbsolutePosition = WindowPosition + Vector2.new(HighlightElement._PositionX, HighlightElement._PositionY - Window._ScrollOffset)
					local HighlightAbsoluteSize = Vector2.new(HighlightElement._Width - (Window._MaxScroll > 0 and Theme.ScrollbarWidth + 4 or 0), HighlightElement._Height)

					if (HighlightAbsolutePosition.Y + HighlightElement._Height > ViewportStart) and (HighlightAbsolutePosition.Y < ViewportEnd) then
						DrawingImmediateRectangle(HighlightAbsolutePosition, HighlightAbsoluteSize, Theme.TitleBarSeparator, HighlightAlpha, 0, 2)
					end
				end
			end

			if Window._ActiveColorPicker then
				local ColorPicker = Window._ActiveColorPicker
				local SwatchSize = 22
				local SwatchGap = 4
				local Margin = 10
				local Columns = 10
				local RowCount = math.ceil(#ColorPalette / Columns)
				local GridWidth = Columns * SwatchSize + (Columns - 1) * SwatchGap
				local PopupWidth = Margin + GridWidth + Margin
				local HeaderHeight = 24

				local GridHeight = RowCount * SwatchSize + (RowCount - 1) * SwatchGap
				local ButtonAreaHeight = 10 + 24 + 10
				local PopupHeight = HeaderHeight + Margin + GridHeight + ButtonAreaHeight

				local Camera = GetCurrentCamera()
				local ViewportSize = Camera and Camera.ViewportSize or Vector2.new(1920, 1080)
				local PopupX = WindowPosition.X + WindowWidth + 10
				if PopupX + PopupWidth > ViewportSize.X - 8 then

					PopupX = WindowPosition.X - PopupWidth - 10
				end
				local PopupY = WindowPosition.Y
				if PopupY + PopupHeight > ViewportSize.Y - 8 then
					PopupY = ViewportSize.Y - PopupHeight - 8
				end
				PopupY = math.max(8, PopupY)
				local PopupPosition = Vector2.new(PopupX, PopupY)

				DrawingImmediateFilledRectangle(PopupPosition, Vector2.new(PopupWidth, PopupHeight), Theme.WindowBackground, 1, 0)
				DrawingImmediateRectangle(PopupPosition, Vector2.new(PopupWidth, PopupHeight), Theme.WindowBorder, 1, 0, 1)

				DrawingImmediateFilledRectangle(PopupPosition, Vector2.new(PopupWidth, HeaderHeight), Theme.TitleBarBackground, 1, 0)
				DrawingImmediateText(
					Vector2.new(
						PopupPosition.X + Margin,
						GetCenteredTextPosition("Select color", 12, PopupPosition, Vector2.new(PopupWidth, HeaderHeight)).Y
					),
					Theme.Font,
					12,
					Theme.TitleBarText,
					1,
					"Select color",
					false
				)

				local ActivePreviewColor = ColorPicker._TempSelectedColor or ColorPicker._Value or Color3.new(1, 1, 1)
				DrawingImmediateFilledRectangle(
					Vector2.new(PopupPosition.X + PopupWidth - Margin - 42, PopupPosition.Y + 6),
					Vector2.new(42, HeaderHeight - 12),
					ActivePreviewColor,
					1,
					0
				)
				DrawingImmediateRectangle(
					Vector2.new(PopupPosition.X + PopupWidth - Margin - 42, PopupPosition.Y + 6),
					Vector2.new(42, HeaderHeight - 12),
					Theme.ColorPickerSelectedBorder,
					0.9,
					0,
					1
				)

				local GridStartY = PopupPosition.Y + HeaderHeight + Margin
				local CurrentMousePosition = GetMouseLocation(UserInputService)
				for SwatchIndex = 1, #ColorPalette do
					local ColumnIndex = (SwatchIndex - 1) % Columns
					local RowIndex    = math.floor((SwatchIndex - 1) / Columns)
					local SwatchX = PopupPosition.X + Margin + ColumnIndex * (SwatchSize + SwatchGap)
					local SwatchY = GridStartY + RowIndex * (SwatchSize + SwatchGap)
					local SwatchPos  = Vector2.new(SwatchX, SwatchY)
					local SwatchSizeVector  = Vector2.new(SwatchSize, SwatchSize)
					local IsSelected = (SwatchIndex == ColorPicker._TempSelectedSwatchIndex)
					local IsHovered = IsPointInsideRectangle(CurrentMousePosition, SwatchPos, SwatchSizeVector)
					DrawingImmediateFilledRectangle(SwatchPos, SwatchSizeVector, ColorPalette[SwatchIndex], 1, 0)
					DrawingImmediateRectangle(
						SwatchPos,
						SwatchSizeVector,
						IsSelected and Theme.ColorPickerSelectedBorder or (IsHovered and Theme.ColorPickerSwatchHover or Theme.ColorPickerBorder),
						1,
						0,
						(IsSelected or IsHovered) and 2 or 1
					)

					if IsSelected then
						local CheckStart = SwatchPos + Vector2.new(6, SwatchSize - 8)
						local CheckMiddle = SwatchPos + Vector2.new(10, SwatchSize - 4)
						local CheckEnd = SwatchPos + Vector2.new(SwatchSize - 5, 5)
						DrawingImmediateLine(CheckStart, CheckMiddle, Color3.fromRGB(255, 255, 255), 1, 2)
						DrawingImmediateLine(CheckMiddle, CheckEnd, Color3.fromRGB(255, 255, 255), 1, 2)
					end
				end

				local SaveButtonY    = GridStartY + GridHeight + 10
				local SaveButtonSize = Vector2.new((PopupWidth - Margin * 3) / 2, 24)
				local SaveButtonPos  = Vector2.new(PopupPosition.X + Margin, SaveButtonY)
				local ExitButtonPos  = Vector2.new(SaveButtonPos.X + SaveButtonSize.X + Margin, SaveButtonY)
				local IsSaveHovered = IsPointInsideRectangle(CurrentMousePosition, SaveButtonPos, SaveButtonSize)
				local IsExitHovered = IsPointInsideRectangle(CurrentMousePosition, ExitButtonPos, SaveButtonSize)

				DrawingImmediateFilledRectangle(SaveButtonPos, SaveButtonSize, IsSaveHovered and Theme.SaveButtonHover or Theme.SaveButtonBackground, 1, 0)
				DrawImmediateCenteredText(SaveButtonPos, SaveButtonSize, 12, Theme.ButtonText, 1, "Apply")
				DrawingImmediateFilledRectangle(ExitButtonPos, SaveButtonSize, IsExitHovered and Theme.ExitButtonHover or Theme.ExitButtonBackground, 1, 0)
				DrawImmediateCenteredText(ExitButtonPos, SaveButtonSize, 12, Theme.ButtonText, 1, "Cancel")

				ColorPicker._PopupGeometry = {
					Position    = PopupPosition,
					Width       = PopupWidth,
					Height      = PopupHeight,
					HeaderHeight = HeaderHeight,
					Margin      = Margin,
					SwatchSize  = SwatchSize,
					SwatchGap   = SwatchGap,
					Columns     = Columns,
					GridStartY  = GridStartY,
					GridHeight  = GridHeight,
					SavePos     = SaveButtonPos,
					ExitPos     = ExitButtonPos,
					ButtonSize  = SaveButtonSize,
				}
			end

			local PaintNotificationsList = {}
			for NotificationIndex, Entry in ipairs(Library.ActiveNotifications) do
				table.insert(PaintNotificationsList, Entry)
			end
			for NotificationIndex, Entry in ipairs(Window._ActiveNotifications) do
				table.insert(PaintNotificationsList, Entry)
			end

			for NotificationIndex, Entry in ipairs(PaintNotificationsList) do
				DrawingImmediateFilledRectangle(Entry.Position, Vector2.new(Theme.NotificationWidth, Theme.NotificationHeight), Theme.NotificationBackground, 1, 0)
				DrawingImmediateRectangle(Entry.Position, Vector2.new(Theme.NotificationWidth, Theme.NotificationHeight), Theme.NotificationBorder, 0.8, 0, 1)

				DrawingImmediateLine(
					Vector2.new(Entry.Position.X + 3, Entry.Position.Y + 4),
					Vector2.new(Entry.Position.X + 3, Entry.Position.Y + Theme.NotificationHeight - 4),
					Theme.NotificationAccent, 1, 2
				)
				DrawingImmediateText(
					Vector2.new(Entry.Position.X + 12, Entry.Position.Y + (Theme.NotificationHeight - Theme.ElementFontSize) / 2),
					Theme.Font, Theme.ElementFontSize, Theme.NotificationText, 1, Entry.Text, false
				)
			end
		end))
		table.insert(Window._Connections, PaintConnection)
	end

	local function UpdateViewportScale()
		local Camera = GetCurrentCamera()
		local Viewport = Camera and Camera.ViewportSize or Vector2.new(1920, 1080)

		-- Scale from both axes so the window can shrink on small screens instead
		-- of stretching past the viewport. The upper clamp prevents oversized
		-- monitors from making text and controls feel inflated.
		local RawScale = math.min(Viewport.X / 1920, Viewport.Y / 1080)
		local Scale = math.clamp(RawScale, IsMobileDevice and 0.92 or 0.82, 1.35)

		for ParameterKey, BaseValue in pairs(Theme.Base) do
			Theme[ParameterKey] = BaseValue * Scale
		end

		Window._TabBarHeight = 34 * Scale
		Window._VisibleHeight = Theme.WindowVisibleHeight

		-- Keep the window inside the visible camera area after a resize, display
		-- mode change, or mobile rotation.
		local MaximumPositionX = math.max(8, Viewport.X - Theme.WindowWidth - 8)
		local MaximumPositionY = math.max(8, Viewport.Y - (Theme.TitleBarHeight + Window._VisibleHeight) - 8)
		Window._Position = Vector2.new(
			math.clamp(Window._Position.X, 8, MaximumPositionX),
			math.clamp(Window._Position.Y, 8, MaximumPositionY)
		)
	end

	local ViewportConnection
	local function ConnectViewport()
		if ViewportConnection then
			ViewportConnection:Disconnect()
			ViewportConnection = nil
		end
		local Camera = GetCurrentCamera()
		if Camera then
			ViewportConnection = Camera:GetPropertyChangedSignal("ViewportSize"):Connect(NewCClosure(function()
				UpdateViewportScale()
				Window:RecalculateLayout()
			end))
			table.insert(Window._Connections, ViewportConnection)
		end
	end

	local CameraConnection = Workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(NewCClosure(function()
		ConnectViewport()
		UpdateViewportScale()
		Window:RecalculateLayout()
	end))
	table.insert(Window._Connections, CameraConnection)

	ConnectViewport()
	UpdateViewportScale()

	Window:RecalculateLayout()

	return Window
end

function Library:_ReconcileInputBlocking(Type)
	local ShouldBlock = false

	for Window, RequestTable in pairs(Library._InputBlockingRequests) do
		if Window and not Window._Destroyed and RequestTable[Type] then
			ShouldBlock = true
			break
		end
	end

	Library:SetInputBlocking(Type, ShouldBlock)
end

function Library:SetInputBlockingForWindow(Window, Type, Enabled)
	if not Window then
		return
	end

	local RequestTable = Library._InputBlockingRequests[Window]
	if not RequestTable and Enabled ~= true then
		return
	end

	if not RequestTable then
		RequestTable = {}
		Library._InputBlockingRequests[Window] = RequestTable
	end

	RequestTable[Type] = Enabled == true or nil

	if not next(RequestTable) then
		Library._InputBlockingRequests[Window] = nil
	end

	Library:_ReconcileInputBlocking(Type)
end

function Library:ClearInputBlockingForWindow(Window)
	local RequestTable = Library._InputBlockingRequests[Window]
	if not RequestTable then
		return
	end

	Library._InputBlockingRequests[Window] = nil

	for Type in pairs(RequestTable) do
		Library:_ReconcileInputBlocking(Type)
	end
end

function Library:SetInputBlocking(Type, Enabled)
	local ShouldEnable = Enabled == true
	if Library._ActiveSinkStates[Type] == ShouldEnable then
		return
	end

	Library._ActiveSinkStates[Type] = ShouldEnable

	local Priority = 10000000
	if Enum.ContextActionPriority and Enum.ContextActionPriority.High and typeof(Enum.ContextActionPriority.High.Value) == "number" then
		Priority = math.max(Priority, Enum.ContextActionPriority.High.Value)
	end
	local ExistingName = Library._ActiveSinks[Type]

	if ExistingName then
		UnbindCoreAction(ContextActionService, ExistingName)
		Library._ActiveSinks[Type] = nil
	end

	if ShouldEnable then

		local NewName = RandomString(16)
		Library._ActiveSinks[Type] = NewName

		if Type == "Scroll" then
			BindCoreActionAtPriority(ContextActionService, NewName, function(ActionName, InputState, InputObject)
				return Enum.ContextActionResult.Sink
			end, false, Priority, Enum.UserInputType.MouseWheel)
		elseif Type == "Interface" then
			BindCoreActionAtPriority(ContextActionService, NewName, function(ActionName, InputState, InputObject)
				return Enum.ContextActionResult.Sink
			end, false, Priority,
				Enum.UserInputType.MouseButton1,
				Enum.UserInputType.MouseButton2,
				Enum.UserInputType.MouseButton3,
				Enum.UserInputType.MouseMovement,
				Enum.UserInputType.MouseWheel,
				Enum.UserInputType.Touch
			)
		elseif Type == "Camera" then
			BindCoreActionAtPriority(ContextActionService, NewName, function(ActionName, InputState, InputObject)
				return Enum.ContextActionResult.Sink
			end, false, Priority,
				Enum.UserInputType.MouseMovement,
				Enum.UserInputType.MouseButton2,
				Enum.UserInputType.MouseWheel
			)
		elseif Type == "Typing" then
			local function TypingSink(ActionName, InputState, InputObject)
				return Enum.ContextActionResult.Sink
			end

			BindCoreActionAtPriority(ContextActionService, NewName, TypingSink, false, Priority,
				Enum.UserInputType.MouseButton1, Enum.UserInputType.MouseWheel,
				Enum.KeyCode.W, Enum.KeyCode.A, Enum.KeyCode.S, Enum.KeyCode.D, Enum.KeyCode.Space,
				Enum.KeyCode.Up, Enum.KeyCode.Down, Enum.KeyCode.Left, Enum.KeyCode.Right,
				Enum.KeyCode.I, Enum.KeyCode.O
			)
		end
	end
end

return Library
