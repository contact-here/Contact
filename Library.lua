-- Executor compatibility helpers are declared up front so later code can use
-- stable names without caring which executor runtime provided the original
-- application programming interface.
local CloneFunction, CloneReference, NewCClosure

-- Executor-only controls must distinguish native runtime functions from Lua
-- compatibility shims. debug.info is used directly so the capability contract
-- cannot drift behind a cached alias.
local function IsNativeExecutorFunction(TargetFunction)
	if typeof(TargetFunction) ~= "function" then
		return false
	end

	local InspectionSucceeded, FunctionSource = pcall(
		debug.info,
		TargetFunction,
		"s"
	)

	return InspectionSucceeded and FunctionSource == "[C]"
end

do
	-- Resolve executor compatibility as one contract instead of repeating the
	-- same native-function branching three times.
	local RawCloneFunction, RawCloneReference, RawNewCClosure =
		clonefunc or clonefunction or clone_function,
		cloneref or clone_ref or clonereference,
		newcclosure
	local CloneFunctionIsNative, CloneReferenceIsNative, NewCClosureIsNative =
		IsNativeExecutorFunction(RawCloneFunction),
		IsNativeExecutorFunction(RawCloneReference),
		IsNativeExecutorFunction(RawNewCClosure)

	CloneFunction = CloneFunctionIsNative and RawCloneFunction or function(TargetFunction)
		return TargetFunction
	end

	CloneReference = CloneReferenceIsNative and RawCloneReference or function(TargetReference)
		return TargetReference
	end

	NewCClosure = NewCClosureIsNative and RawNewCClosure or function(TargetFunction)
		return TargetFunction
	end
end

local UserInputService, RunService, ContextActionService,
	GraphicalUserInterfaceService, CoreGui, Workspace
local DrawingLibrary = Drawing
local WriteClipboardText = setclipboard or toclipboard or set_clipboard
local DataModel = CloneReference(game)
local GetService, IsDataModelLoaded, DataModelLoadedSignal, WaitForDataModelLoaded,
	CreateInstance, DestroyInstance, FindFirstChild, GetPropertyChangedSignal, ConnectSignal =
	CloneFunction(DataModel.GetService),
	CloneFunction(DataModel.IsLoaded),
	DataModel.Loaded,
	CloneFunction(DataModel.Loaded.Wait),
	CloneFunction(Instance.new),
	CloneFunction(DataModel.Destroy),
	CloneFunction(DataModel.FindFirstChild),
	CloneFunction(DataModel.GetPropertyChangedSignal),
	nil

-- Roblox exposes a one-shot Loaded signal specifically for initialization.
-- Check IsLoaded first because waiting after the signal has already fired would
-- suspend the current thread permanently.
if not IsDataModelLoaded(DataModel) then
	WaitForDataModelLoaded(DataModelLoadedSignal)
end

do
	-- Cache services through cloned methods/references so the rest of the
	-- library avoids repeated service lookups and reduces exposure to hooks.
	UserInputService, RunService, ContextActionService,
		GraphicalUserInterfaceService, CoreGui, Workspace =
		CloneReference(GetService(DataModel, "UserInputService")),
		CloneReference(GetService(DataModel, "RunService")),
		CloneReference(GetService(DataModel, "ContextActionService")),
		CloneReference(GetService(DataModel, "GuiService")),
		CloneReference(GetService(DataModel, "CoreGui")),
		CloneReference(GetService(DataModel, "Workspace"))
	-- The generic RBXScriptSignal connection method is cached only after the
	-- cloned RunService reference is available.
	ConnectSignal = CloneFunction(RunService.Heartbeat.Connect)
end

local GetMouseLocation, IsMouseButtonPressed, GetMouseButtonsPressed, GetDeviceType,
	GetGraphicalUserInterfaceInset, InterfaceFrameSignal,
	BindCoreActionAtPriority, UnbindCoreAction

do
	-- Cache the complete input/render method set in one assignment so optional
	-- fallbacks and required native methods remain visibly part of one contract.
	GetMouseLocation, IsMouseButtonPressed, GetMouseButtonsPressed, GetDeviceType,
		GetGraphicalUserInterfaceInset, InterfaceFrameSignal,
		BindCoreActionAtPriority, UnbindCoreAction =
		CloneFunction(UserInputService.GetMouseLocation),
		CloneFunction(UserInputService.IsMouseButtonPressed),
		typeof(UserInputService.GetMouseButtonsPressed) == "function"
			and CloneFunction(UserInputService.GetMouseButtonsPressed)
			or function() return {} end,
		typeof(UserInputService.GetDeviceType) == "function"
			and CloneFunction(UserInputService.GetDeviceType)
			or function() return "Unknown" end,
		CloneFunction(GraphicalUserInterfaceService.GetGuiInset),
		RunService.PreRender or RunService.RenderStepped or RunService.Heartbeat,
		CloneFunction(ContextActionService.BindCoreActionAtPriority),
		CloneFunction(ContextActionService.UnbindCoreAction)
end

local SetRenderProperty, GetRenderProperty

do
	-- Some Drawing implementations expose setrenderproperty/getrenderproperty;
	-- others are simple Lua tables. These wrappers normalize both models.
	local RawSetRenderProperty, RawGetRenderProperty =
		typeof(setrenderproperty) == "function" and CloneFunction(setrenderproperty),
		typeof(getrenderproperty) == "function" and CloneFunction(getrenderproperty)

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

	GetRenderProperty = function(TargetObject, PropertyName)
		-- Returning nil is safer than surfacing render-backend errors to callers.
		if RawGetRenderProperty then
			local PropertyReadSucceeded, PropertyValue = pcall(RawGetRenderProperty, TargetObject, PropertyName)
			if PropertyReadSucceeded then
				return PropertyValue
			end
		else
			local TargetType = type(TargetObject)
			if TargetType == "table" or TargetType == "userdata" then
				return TargetObject[PropertyName]
			end
		end
		return nil
	end

end

local SelectedBackend, UseImmediateMode, DrawingBackendAvailable, DrawingIsNative =
	0, false, false, false

-- Native Drawing.new is preferred. When it is absent or Lua-backed, the library
-- attempts to load a replacement Drawing implementation before falling back.
if typeof(DrawingLibrary) == "table" and typeof(DrawingLibrary.new) == "function" then
	if IsNativeExecutorFunction(DrawingLibrary.new) then
		DrawingIsNative = true
	end
end

if not DrawingIsNative then
	local CustomDrawingLibraryLink = "https://raw.githubusercontent.com/contact-here/Contact/refs/heads/main/DrawingLibrary.lua"
	local RawHttpGet = CloneFunction(DataModel.HttpGet)
	local RawRequestFunction = request or http_request or (syn and syn.request)
	local FetchedContent

	if not string.find(CustomDrawingLibraryLink, "placeholder-link-here") then
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
	end

	if FetchedContent then
		-- Loaded code must return a Drawing-like table before it replaces the
		-- current backend reference.
		local LoadedFunction = loadstring(FetchedContent)
		if LoadedFunction then
			local ExecutionSuccess, ExecutionResult = pcall(LoadedFunction)
			if ExecutionSuccess and typeof(ExecutionResult) == "table" and typeof(ExecutionResult.new) == "function" then
				DrawingLibrary = ExecutionResult

				-- Preserve the generic table/userdata property adapters when a
				-- replacement backend implements Drawing.new but omits either
				-- optional optimized property helper.
				if typeof(ExecutionResult.SetRenderProperty) == "function" then
					SetRenderProperty = ExecutionResult.SetRenderProperty
				end
				if typeof(ExecutionResult.GetRenderProperty) == "function" then
					GetRenderProperty = ExecutionResult.GetRenderProperty
				end
			end
		end
	end
end
local DrawingImmediateLine, DrawingImmediateCircle, DrawingImmediateFilledCircle,
	DrawingImmediateRectangle, DrawingImmediateFilledRectangle,
	DrawingImmediateTriangle, DrawingImmediateFilledTriangle,
	DrawingImmediateQuad, DrawingImmediateFilledQuad, DrawingImmediateText,
	DrawingImmediateOutlinedText, DrawingImmediateGetPaint

-- Cache DrawingImmediate primitives whenever the executor exposes them, even
-- when the main interface itself was forced to use retained Drawing. Feature
-- pages can then select either backend independently through GetRenderingBackends.
if typeof(DrawingImmediate) == "table" then
	DrawingImmediateLine, DrawingImmediateCircle, DrawingImmediateFilledCircle,
		DrawingImmediateRectangle, DrawingImmediateFilledRectangle,
		DrawingImmediateTriangle, DrawingImmediateFilledTriangle,
		DrawingImmediateQuad, DrawingImmediateFilledQuad, DrawingImmediateText,
		DrawingImmediateOutlinedText, DrawingImmediateGetPaint =
		typeof(DrawingImmediate.Line) == "function" and CloneFunction(DrawingImmediate.Line),
		typeof(DrawingImmediate.Circle) == "function" and CloneFunction(DrawingImmediate.Circle),
		typeof(DrawingImmediate.FilledCircle) == "function" and CloneFunction(DrawingImmediate.FilledCircle),
		typeof(DrawingImmediate.Rectangle) == "function" and CloneFunction(DrawingImmediate.Rectangle),
		typeof(DrawingImmediate.FilledRectangle) == "function" and CloneFunction(DrawingImmediate.FilledRectangle),
		typeof(DrawingImmediate.Triangle) == "function" and CloneFunction(DrawingImmediate.Triangle),
		typeof(DrawingImmediate.FilledTriangle) == "function" and CloneFunction(DrawingImmediate.FilledTriangle),
		typeof(DrawingImmediate.Quad) == "function" and CloneFunction(DrawingImmediate.Quad),
		typeof(DrawingImmediate.FilledQuad) == "function" and CloneFunction(DrawingImmediate.FilledQuad),
		typeof(DrawingImmediate.Text) == "function" and CloneFunction(DrawingImmediate.Text),
		typeof(DrawingImmediate.OutlinedText) == "function" and CloneFunction(DrawingImmediate.OutlinedText),
		typeof(DrawingImmediate.GetPaint) == "function" and CloneFunction(DrawingImmediate.GetPaint)

	if (SelectedBackend == 0 or SelectedBackend == 1) and DrawingImmediateLine then
		UseImmediateMode        = true
		DrawingBackendAvailable = true
	end
end

-- Render a solid circular marker without relying on FilledCircle. Several
-- DrawingImmediate builds expose that function with incompatible parameter
-- orders, which can turn a requested circle into a three-sided polygon. A
-- maximally rounded square is geometrically circular and its parameter order is
-- stable. The thick outline-circle fallback covers unusually limited runtimes.
-- Dropdown arrows remain the only triangular control indicators.
local function DrawImmediateSolidCircle(Center, Radius, Color, Opacity, NumberOfSides)
	local SafeRadius = math.max(1, tonumber(Radius) or 1)
	local SafeOpacity = math.clamp(tonumber(Opacity) or 1, 0, 1)
	local SafeNumberOfSides = math.clamp(
		math.floor(tonumber(NumberOfSides) or 64),
		16,
		250
	)

	-- A square whose rounding equals half its size has circular geometry and uses
	-- the same FilledRectangle signature in every supported Potassium build.
	if DrawingImmediateFilledRectangle then
		local Diameter = SafeRadius * 2
		DrawingImmediateFilledRectangle(
			Center - Vector2.new(SafeRadius, SafeRadius),
			Vector2.new(Diameter, Diameter),
			Color,
			SafeOpacity,
			SafeRadius
		)
	end

	if DrawingImmediateCircle then
		local OutlineThickness = DrawingImmediateFilledRectangle and 1 or SafeRadius
		DrawingImmediateCircle(Center, SafeRadius, Color, SafeOpacity, SafeNumberOfSides, OutlineThickness)
	end
end

if not DrawingBackendAvailable then
	if typeof(DrawingLibrary) == "table" and typeof(DrawingLibrary.new) == "function" then
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
local function RandomString(CharacterCount)
	local AvailableCharacters = "abcdefghijklmnopqrstuvwxyz0123456789"
	local ResultCharacters = {}

	for CharacterIndex = 1, CharacterCount do
		local RandomCharacterIndex = math.random(1, #AvailableCharacters)
		ResultCharacters[CharacterIndex] = string.sub(AvailableCharacters, RandomCharacterIndex, RandomCharacterIndex)
	end

	return table.concat(ResultCharacters)
end

local Theme

-- Lightweight word wrapping for Drawing text. Drawing has no automatic layout
-- boxes, so line length is estimated from font size and theme character ratio.
local function WrapText(InputText, MaximumPixelWidth, FontSize)
	local CharacterWidth = FontSize * ((Theme and Theme.FontCharWidthRatio or 0.52) * 1.15)
	local MaximumCharactersPerLine = math.max(1, math.floor(MaximumPixelWidth / CharacterWidth))
	local WrappedLines = {}

	-- Explicit newline characters are treated as hard line breaks before word
	-- wrapping. This keeps formatted labels, counters, and copied diagnostic
	-- blocks from being merged into one visual paragraph.
	for ParagraphText in string.gmatch(string.format("%s\n", tostring(InputText)), "([^\n]*)\n") do
		local CurrentLine = ""

		if ParagraphText == "" then
			table.insert(WrappedLines, "")
		else
			for Word in ParagraphText:gmatch("%S+") do
				if #Word > MaximumCharactersPerLine then
					if CurrentLine ~= "" then
						table.insert(WrappedLines, CurrentLine)
						CurrentLine = ""
					end

					local WordCharacterPosition = 1

					while WordCharacterPosition <= #Word do
						local WordChunk = string.sub(Word, WordCharacterPosition, WordCharacterPosition + MaximumCharactersPerLine - 1)

						if WordCharacterPosition + MaximumCharactersPerLine <= #Word then
							table.insert(WrappedLines, WordChunk)
						else
							CurrentLine = WordChunk
						end

						WordCharacterPosition = WordCharacterPosition + MaximumCharactersPerLine
					end
				else
					local TestLine = CurrentLine == "" and Word or string.format("%s %s", CurrentLine, Word)

					if #TestLine <= MaximumCharactersPerLine then
						CurrentLine = TestLine
					else
						if CurrentLine ~= "" then
							table.insert(WrappedLines, CurrentLine)
						end
						CurrentLine = Word
					end
				end
			end

			if CurrentLine ~= "" then
				table.insert(WrappedLines, CurrentLine)
			end
		end
	end

	if #WrappedLines == 0 then
		table.insert(WrappedLines, "")
	end

	return WrappedLines
end

-- Visual design tokens. Color and size values are centralized so the launcher
-- can expose them through the theme editor without touching rendering logic.
Theme = {

	-- contactinghere.lol uses an almost-black canvas, translucent white surfaces,
	-- bright type, and small cyan/red signals. These tokens mirror that visual
	-- hierarchy while keeping every state readable in a Drawing-only renderer.
	AccentPrimary          = Color3.fromRGB(56, 189, 248),
	AccentSecondary        = Color3.fromRGB(248, 113, 113),
	AccentNeutral          = Color3.fromRGB(228, 228, 231),
	WindowBackground       = Color3.fromRGB(3, 3, 5),
	WindowSurfaceHighlight = Color3.fromRGB(18, 18, 26),
	WindowSurfaceShade     = Color3.fromRGB(0, 0, 0),
	WindowBorder           = Color3.fromRGB(39, 39, 42),
	WindowBorderHover      = Color3.fromRGB(161, 161, 170),

	-- The title bar gets a cooler tint than the body to make dragging and
	-- window ownership visually obvious.
	TitleBarBackground     = Color3.fromRGB(7, 7, 10),
	TitleBarBackgroundHover= Color3.fromRGB(12, 12, 18),
	TitleBarHighlight      = Color3.fromRGB(23, 23, 25),
	TitleBarAccentWash     = Color3.fromRGB(12, 12, 18),
	TitleBarSeparator      = Color3.fromRGB(228, 228, 231),
	TitleBarText           = Color3.fromRGB(255, 255, 255),
	TitleBarTextHover      = Color3.fromRGB(255, 255, 255),

	-- Sections are slightly warmer than the window background, giving stacked
	-- groups enough depth without relying on heavy borders.
	SectionBodyBackground  = Color3.fromRGB(7, 7, 10),
	SectionBackground      = Color3.fromRGB(12, 12, 18),
	SectionBackgroundHover = Color3.fromRGB(18, 18, 26),
	SectionText            = Color3.fromRGB(161, 161, 170),
	SectionTextHover       = Color3.fromRGB(255, 255, 255),

	LabelText      = Color3.fromRGB(161, 161, 170),
	LabelTextHover = Color3.fromRGB(255, 255, 255),

	ButtonBackground      = Color3.fromRGB(12, 12, 18),
	ButtonBackgroundHover = Color3.fromRGB(23, 23, 25),
	ButtonText            = Color3.fromRGB(255, 255, 255),
	ButtonBorder          = Color3.fromRGB(39, 39, 42),
	TabBackground         = Color3.fromRGB(7, 7, 10),
	TabBackgroundHover    = Color3.fromRGB(18, 18, 26),
	TabBackgroundActive   = Color3.fromRGB(23, 23, 25),
	ToggleInactive        = Color3.fromRGB(63, 63, 70),
	ToggleActive          = Color3.fromRGB(56, 189, 248),

	TextBoxBackground      = Color3.fromRGB(7, 7, 10),
	TextBoxBackgroundHover = Color3.fromRGB(12, 12, 18),
	TextBoxBorder          = Color3.fromRGB(39, 39, 42),
	TextBoxBorderFocused   = Color3.fromRGB(56, 189, 248),
	TextBoxText            = Color3.fromRGB(255, 255, 255),
	TextBoxPlaceholder     = Color3.fromRGB(113, 113, 122),
	TextBoxCursor          = Color3.fromRGB(255, 255, 255),
	TextBoxSelection       = Color3.fromRGB(56, 189, 248),

	DropdownBackground    = Color3.fromRGB(7, 7, 10),
	DropdownHover         = Color3.fromRGB(12, 12, 18),
	DropdownItemBackground= Color3.fromRGB(3, 3, 5),
	DropdownItemHover     = Color3.fromRGB(18, 18, 26),
	DropdownText          = Color3.fromRGB(228, 228, 231),
	DropdownBorder        = Color3.fromRGB(39, 39, 42),
	DropdownBorderHover   = Color3.fromRGB(161, 161, 170),
	DropdownArrow         = Color3.fromRGB(161, 161, 170),

	SliderTrackBackground = Color3.fromRGB(7, 7, 10),
	SliderTrackFill       = Color3.fromRGB(56, 189, 248),
	SliderTrackFillHover  = Color3.fromRGB(125, 211, 252),
	SliderText            = Color3.fromRGB(228, 228, 231),
	SliderBorder          = Color3.fromRGB(39, 39, 42),
	SliderTrackHeight       = 8,
	SliderTrackHoverHeight  = 10,
	SliderThumbRadius       = 7,
	SliderThumbHoverRadius  = 9,
	ToggleIndicatorRadius   = 5,

	ColorPickerBorder      = Color3.fromRGB(39, 39, 42),
	ColorPickerSelectedBorder = Color3.fromRGB(255, 255, 255),
	ColorPickerSwatchHover = Color3.fromRGB(161, 161, 170),

	ScrollbarBackground  = Color3.fromRGB(7, 7, 10),
	ScrollbarHandle      = Color3.fromRGB(39, 39, 42),
	ScrollbarHandleHover = Color3.fromRGB(82, 82, 91),

	NotificationBackground = Color3.fromRGB(7, 7, 10),
	NotificationBorder     = Color3.fromRGB(39, 39, 42),
	NotificationText       = Color3.fromRGB(255, 255, 255),
	NotificationAccent     = Color3.fromRGB(56, 189, 248),
	TooltipBackground      = Color3.fromRGB(3, 3, 5),
	TooltipBorder          = Color3.fromRGB(39, 39, 42),
	TooltipText            = Color3.fromRGB(228, 228, 231),
	LockedControlBackground= Color3.fromRGB(7, 7, 10),
	LockedControlBorder    = Color3.fromRGB(248, 113, 113),
	LockedControlIcon      = Color3.fromRGB(248, 113, 113),
	LockedControlText      = Color3.fromRGB(255, 255, 255),

	SaveButtonBackground = Color3.fromRGB(3, 105, 161),
	SaveButtonHover      = Color3.fromRGB(14, 165, 233),
	ExitButtonBackground = Color3.fromRGB(69, 10, 10),
	ExitButtonHover      = Color3.fromRGB(248, 113, 113),
	CloseButtonBackground = Color3.fromRGB(12, 12, 18),
	CloseButtonBorder     = Color3.fromRGB(39, 39, 42),
	CloseButtonHover      = Color3.fromRGB(248, 113, 113),
	TouchLauncherBackground = Color3.fromRGB(7, 7, 10),
	TouchLauncherBorder     = Color3.fromRGB(56, 189, 248),
	TouchLauncherText       = Color3.fromRGB(255, 255, 255),

	SectionHover = Color3.fromRGB(18, 18, 26),

	-- Desktop uses Drawing.Fonts.Plex. Potassium maps this identifier to the
	-- balanced proportional typeface used by the earlier Contact interface;
	-- Monospace is intentionally reserved for feature renderers that explicitly
	-- request code-like text rather than for the complete application surface.
	Font            = 2,
	TitleFontSize           = 18,
	HeaderSecondaryFontSize = 10,
	SectionFontSize         = 15,
	SectionMetaFontSize     = 10,
	ElementFontSize         = 14,

	FontCharWidthRatio = 0.5,

	FontLineHeightRatio = 1.35,

	FontVerticalPaddingRatio = 0.5,

	FontHorizontalInsetRatio = 0.65,

	-- Layout tokens are kept together so adaptive scaling can resize the whole
	-- interface proportionally when the viewport changes.
	WindowWidth         = 620,
	TitleBarHeight      = 50,
	WindowVisibleHeight = 680,
	ElementHeight       = 38,
	ElementPadding      = 10,
	SectionPadding      = 16,
	InnerMargin         = 18,
	ScrollbarWidth      = 7,
	WindowCornerRadius  = 12,
	ControlCornerRadius = 8,
	CompactCornerRadius = 6,

	-- Color picker grid dimensions.
	ColorSwatchSize = 24,
	ColorSwatchGap  = 4,

	-- Notification stack dimensions and lifetime.
	NotificationWidth    = 320,
	NotificationMaximumWidth = 520,
	NotificationHeight   = 44,
	NotificationDuration = 5,
	NotificationMargin   = 12,
	NotificationHorizontalPadding = 12,
	NotificationVerticalPadding = 9,
	TooltipDelay         = 3,
	TooltipWidth         = 340,
	TooltipPadding       = 11,
	TooltipMaximumLines  = 8,
}

-- Keep the animation integrator on the already-captured Theme table. The large
-- CreateWindow closure stays within Lua 5.1's strict upvalue budget this way.
Theme.UpdateAnimationFactor = UpdateAnimationFactor

-- Normalize rectangle rounding across retained and immediate renderers. Normal
-- controls inherit the site's compact eight-pixel radius, while explicit values
-- remain available for window geometry and true circles.
do
	local RawDrawingImmediateRectangle = DrawingImmediateRectangle
	local RawDrawingImmediateFilledRectangle = DrawingImmediateFilledRectangle

	local function ResolveImmediateRectangleRounding(RectangleSize, RequestedRounding)
		local MaximumRounding = math.max(0, math.min(RectangleSize.X, RectangleSize.Y) * 0.5)
		local PreferredRounding = tonumber(RequestedRounding) or 0
		if PreferredRounding <= 0 then
			PreferredRounding = Theme.ControlCornerRadius
		end
		return math.min(PreferredRounding, MaximumRounding)
	end

	if RawDrawingImmediateRectangle then
		DrawingImmediateRectangle = function(TopLeftPosition, RectangleSize, RectangleColor, Opacity, Rounding, Thickness)
			return RawDrawingImmediateRectangle(
				TopLeftPosition,
				RectangleSize,
				RectangleColor,
				Opacity,
				ResolveImmediateRectangleRounding(RectangleSize, Rounding),
				Thickness
			)
		end
	end

	if RawDrawingImmediateFilledRectangle then
		DrawingImmediateFilledRectangle = function(TopLeftPosition, RectangleSize, RectangleColor, Opacity, Rounding)
			return RawDrawingImmediateFilledRectangle(
				TopLeftPosition,
				RectangleSize,
				RectangleColor,
				Opacity,
				ResolveImmediateRectangleRounding(RectangleSize, Rounding)
			)
		end
	end
end

local function GetTouchInputCoordinateInset()
	-- InputObject.Position on touch devices is reported in the inset-adjusted
	-- viewport coordinate space, while Drawing and DrawingImmediate render in
	-- full-screen coordinates. GuiService supplies the current top-left offset
	-- between those spaces, including the dynamic Roblox top bar on mobile.
	local InsetReadSucceeded, TopLeftInset = pcall(
		GetGraphicalUserInterfaceInset,
		GraphicalUserInterfaceService
	)
	if InsetReadSucceeded and typeof(TopLeftInset) == "Vector2" then
		return TopLeftInset
	end

	return Vector2.new(0, 0)
end

local function GetTouchInputScreenPosition(InputObject, CoordinateInset)
	-- Keep every touch consumer on one conversion path. This prevents tabs,
	-- ordinary elements, title dragging, and the resize corner from developing
	-- different hitbox offsets when Roblox changes its top-bar geometry.
	local RawInputPosition = InputObject.Position
	local ScreenCoordinateInset = CoordinateInset or GetTouchInputCoordinateInset()
	return Vector2.new(
		RawInputPosition.X + ScreenCoordinateInset.X,
		RawInputPosition.Y + ScreenCoordinateInset.Y
	)
end

-- The following helpers derive all text measurements from Theme ratios. That
-- keeps labels, text boxes, and wrapped paragraphs aligned after scaling.
local function FontLineHeight(FontSize)
	return math.ceil(FontSize * Theme.FontLineHeightRatio)
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

function Theme:GetElementAvailableWidth(Element, Window)
	-- Every layout, renderer, and hit-test path must reserve the same amount of
	-- horizontal space for the main scrollbar. Previously TextBox height was
	-- calculated with the wider pre-scrollbar width and rendered with the narrower
	-- width, which could switch it into stacked mode without allocating a second
	-- line and let its value overlap the following control.
	local ElementWidth = math.max(1, tonumber(Element and Element._Width) or 1)
	local MainScrollbarReservedWidth = Window
		and Window._MaxScroll > 0
		and self.ScrollbarWidth + 4
		or 0
	return math.max(1, ElementWidth - MainScrollbarReservedWidth)
end

GetEditableTextCharacterWidth = function(FontSize)
	-- Editable controls and retained text use one font-specific width estimate.
	-- Keeping this calculation centralized makes Plex cursor placement,
	-- selection, horizontal clipping, and pointer hit testing agree visually.
	return FontSize * Theme.FontCharWidthRatio
end

-- Calculate variable tab widths from their complete titles. Short titles retain
-- a compact minimum width, while descriptive titles receive enough horizontal
-- space to remain readable. Any remaining width is shared evenly; narrow
-- windows keep the existing horizontal tab scrolling behavior.
GetPageTabLayout = function(Window, WindowWidth)
	local TabCount = #Window._Pages
	local TabBarPadding = 12
	local TabGap = 8
	local AvailableTabWidth = math.max(1, WindowWidth - TabBarPadding * 2)
	local TabWidths = {}
	local TabOffsets = {}
	local TotalTabWidth = 0
	local CharacterWidth = GetEditableTextCharacterWidth(Theme.ElementFontSize)

	if TabCount == 0 then
		return {
			Padding = TabBarPadding,
			Gap = TabGap,
			Widths = TabWidths,
			Offsets = TabOffsets,
			ContentWidth = 0,
			AvailableWidth = AvailableTabWidth,
			MaximumScroll = 0,
		}
	end

	for PageIndex, Page in ipairs(Window._Pages) do
		local PreferredTabWidth = math.max(104, #tostring(Page.Title) * CharacterWidth + 34)
		TabWidths[PageIndex] = PreferredTabWidth
		TotalTabWidth = TotalTabWidth + PreferredTabWidth
	end
	TotalTabWidth = TotalTabWidth + TabGap * math.max(0, TabCount - 1)

	if TotalTabWidth < AvailableTabWidth then
		local SharedAdditionalWidth = (AvailableTabWidth - TotalTabWidth) / TabCount
		TotalTabWidth = 0
		for PageIndex = 1, TabCount do
			TabWidths[PageIndex] = TabWidths[PageIndex] + SharedAdditionalWidth
			TotalTabWidth = TotalTabWidth + TabWidths[PageIndex]
		end
		TotalTabWidth = TotalTabWidth + TabGap * math.max(0, TabCount - 1)
	end

	local CurrentTabOffset = 0
	for PageIndex = 1, TabCount do
		TabOffsets[PageIndex] = CurrentTabOffset
		CurrentTabOffset = CurrentTabOffset + TabWidths[PageIndex] + TabGap
	end

	return {
		Padding = TabBarPadding,
		Gap = TabGap,
		Widths = TabWidths,
		Offsets = TabOffsets,
		ContentWidth = TotalTabWidth,
		AvailableWidth = AvailableTabWidth,
		MaximumScroll = math.max(0, TotalTabWidth - AvailableTabWidth),
	}
end

local AsciiEllipsis = string.char(46, 46, 46)

local function TruncateTextWithAsciiEllipsis(DisplayText, MaximumCharacters)
	-- Drawing text has no reliable clipping primitive across every backend, so
	-- long strings are shortened before they reach the renderer. ASCII dots are
	-- used instead of a single Unicode ellipsis to keep the file and output
	-- friendly to executors with weaker string handling.
	local SafeDisplayText = tostring(DisplayText or "")
	local SafeMaximumCharacters = math.max(1, math.floor(tonumber(MaximumCharacters) or 1))
	if #SafeDisplayText <= SafeMaximumCharacters then
		return SafeDisplayText
	end

	-- Extremely narrow controls may not even have room for all three dots. Keep
	-- the result inside the requested character budget instead of returning one
	-- preserved character plus an ellipsis that is wider than the control.
	if SafeMaximumCharacters <= #AsciiEllipsis then
		return string.sub(AsciiEllipsis, 1, SafeMaximumCharacters)
	end

	local PreservedCharacterCount = SafeMaximumCharacters - #AsciiEllipsis
	return string.format(
		"%s%s",
		string.sub(SafeDisplayText, 1, PreservedCharacterCount),
		AsciiEllipsis
	)
end

local function GetTextBoxSuggestionDropdownHeight(Element)
	-- Autocomplete suggestions are part of the text box's layout footprint so
	-- following elements move down instead of being painted underneath them.
	if not Element or not Element._IsFocused or not Element._Suggestions or #Element._Suggestions == 0 then
		return 0
	end

	local SuggestionCount = math.min(#Element._Suggestions, Element._MaximumSuggestions or 5)
	return 2 + SuggestionCount * 22
end

GetDropdownVisibleItemCount = function(Element)
	-- Long dynamic dropdowns, such as class lists, should scroll inside their
	-- own option area instead of stretching the whole section to every item.
	if not Element or not Element._Expanded then
		return 0
	end

	return math.min(#(Element._Options or {}), Element._MaximumVisibleItems or 8)
end

GetDropdownOptionsHeight = function(Element)
	return GetDropdownVisibleItemCount(Element) * Theme.ElementHeight
end

GetDropdownMaximumScroll = function(Element)
	local HiddenItemCount = math.max(0, #(Element._Options or {}) - GetDropdownVisibleItemCount(Element))
	return HiddenItemCount * Theme.ElementHeight
end

ClampDropdownScrollOffset = function(Element)
	if not Element then
		return 0
	end

	Element._OptionsScrollOffset = math.clamp(Element._OptionsScrollOffset or 0, 0, GetDropdownMaximumScroll(Element))
	return Element._OptionsScrollOffset
end

ClampTextBoxCursorIndex = function(Element, CursorIndex)
	-- Cursor indices live between characters, so the valid range is
	-- one through string length plus one.
	local TextLength = #(Element._Value or "")
	return math.clamp(tonumber(CursorIndex) or TextLength + 1, 1, TextLength + 1)
end

SetTextBoxCursorIndex = function(Element, CursorIndex)
	Element._CursorIndex = ClampTextBoxCursorIndex(Element, CursorIndex)
	if not Element._SelectionDragging then
		Element._SelectionAnchorIndex = Element._CursorIndex
	end
end

SetTextBoxSelectionRange = function(Element, StartIndex, EndIndex)
	-- A selection is represented as a half-open range: StartIndex is included
	-- and EndIndex points to the cursor slot after the last selected character.
	local TextLength = #(Element._Value or "")
	local ClampedStartIndex = math.clamp(tonumber(StartIndex) or 1, 1, TextLength + 1)
	local ClampedEndIndex = math.clamp(tonumber(EndIndex) or ClampedStartIndex, 1, TextLength + 1)

	Element._SelectionStartIndex = ClampedStartIndex
	Element._SelectionEndIndex = ClampedEndIndex
	Element._CursorIndex = ClampedEndIndex
	Element._IsSelected = ClampedStartIndex ~= ClampedEndIndex
end

ClearTextBoxSelection = function(Element)
	Element._SelectionStartIndex = nil
	Element._SelectionEndIndex = nil
	Element._SelectionAnchorIndex = Element._CursorIndex or ClampTextBoxCursorIndex(Element)
	Element._IsSelected = false
end

GetTextBoxSelectionBounds = function(Element)
	if not Element._IsSelected or not Element._SelectionStartIndex or not Element._SelectionEndIndex then
		return nil, nil
	end

	local StartIndex = math.min(Element._SelectionStartIndex, Element._SelectionEndIndex)
	local EndIndex = math.max(Element._SelectionStartIndex, Element._SelectionEndIndex)
	if StartIndex == EndIndex then
		return nil, nil
	end

	return StartIndex, EndIndex
end

GetFocusedTextBoxDisplayOffset = function(Element, MaximumCharacters)
	local TextLength = #(Element._Value or "")
	local SafeMaximumCharacters = math.max(1, tonumber(MaximumCharacters) or 1)
	local MaximumDisplayOffset = math.max(1, TextLength - SafeMaximumCharacters + 1)

	-- Keep a stable viewport while the user moves the cursor or drags a
	-- selection. The previous implementation always displayed the end of the
	-- string, which made the caret appear far away from the selected text.
	local DisplayOffset = math.clamp(tonumber(Element._DisplayOffset) or 1, 1, MaximumDisplayOffset)
	if Element._IsFocused then
		local CursorIndex = ClampTextBoxCursorIndex(Element, Element._CursorIndex)
		if CursorIndex < DisplayOffset then
			DisplayOffset = CursorIndex
		elseif CursorIndex > DisplayOffset + SafeMaximumCharacters then
			DisplayOffset = CursorIndex - SafeMaximumCharacters
		end
	else
		-- Unfocused controls are easier to scan when they begin with the first
		-- characters instead of preserving an editing-only horizontal offset.
		DisplayOffset = 1
	end

	Element._DisplayOffset = math.clamp(DisplayOffset, 1, MaximumDisplayOffset)
	return Element._DisplayOffset
end

GetVisibleTextBoxCharacterRange = function(Element, MaximumCharacters)
	local TextLength = #(Element._Value or "")
	local DisplayOffset = GetFocusedTextBoxDisplayOffset(Element, MaximumCharacters)
	local DisplayEndIndex = math.min(TextLength + 1, DisplayOffset + MaximumCharacters)
	return DisplayOffset, DisplayEndIndex
end

GetTextBoxCharacterIndexFromMouseX = function(Element, MousePositionX, InputStartX, CharacterWidth, MaximumCharacters)
	local DisplayOffset = GetFocusedTextBoxDisplayOffset(Element, MaximumCharacters)
	local RelativePositionX = math.max(0, MousePositionX - InputStartX)
	local CharacterOffset = math.floor((RelativePositionX / CharacterWidth) + 0.5)
	return ClampTextBoxCursorIndex(Element, DisplayOffset + CharacterOffset)
end

GetTextBoxVisibleText = function(Element, DisplayText, MaximumCharacters, HasValue)
	-- The rendered value uses the exact viewport that cursor and selection
	-- geometry use. This keeps every backend aligned while still truncating
	-- placeholders and inactive values with a readable ASCII ellipsis.
	local SafeDisplayText = tostring(DisplayText or "")
	local SafeMaximumCharacters = math.max(1, tonumber(MaximumCharacters) or 1)
	if #SafeDisplayText <= SafeMaximumCharacters then
		return SafeDisplayText
	end

	if Element._IsFocused and HasValue then
		local DisplayOffset = GetFocusedTextBoxDisplayOffset(Element, SafeMaximumCharacters)
		return string.sub(SafeDisplayText, DisplayOffset, DisplayOffset + SafeMaximumCharacters - 1)
	end

	return TruncateTextWithAsciiEllipsis(SafeDisplayText, SafeMaximumCharacters)
end

GetTextBoxLayoutMetrics = function(Element, TextBoxPosition, TextBoxWidth)
	-- All text-box rendering and hit testing passes through this function. Long
	-- labels automatically move above the editable value when an inline layout
	-- would leave too little room for useful input.
	local SafeWidth = math.max(1, tonumber(TextBoxWidth) or 1)
	local CharacterWidth = GetEditableTextCharacterWidth(Theme.ElementFontSize)
	local HorizontalInset = math.max(6, FontHorizontalInset(Theme.ElementFontSize))
	local InlineInputGap = math.max(12, HorizontalInset + 4)
	local LabelText = Element._Text and tostring(Element._Text) or ""
	local LabelDisplayText = LabelText ~= "" and string.format("%s:", LabelText) or ""
	-- Plex is slightly wider than the editable cursor grid. Account for that
	-- difference when positioning the value so labels such as "Target jump
	-- velocity:" cannot visually touch or overlap the first entered character.
	local LabelCharacterWidth = CharacterWidth * 1.15
	local EstimatedLabelWidth = #LabelDisplayText * LabelCharacterWidth
	-- Eight editable characters are sufficient for compact numeric controls.
	-- Keeping this threshold modest preserves the familiar single-row layout,
	-- while genuinely long labels still switch to the safer stacked layout.
	local MinimumInputWidth = math.max(CharacterWidth * 8, SafeWidth * 0.24)
	local ForceStackedLayout = Element._TextBoxLayout == "Stacked"
	local ForceInlineLayout = Element._TextBoxLayout == "Inline"
	local UsesStackedLayout = not ForceInlineLayout
		and LabelDisplayText ~= ""
		and (
			ForceStackedLayout
			or EstimatedLabelWidth + MinimumInputWidth + HorizontalInset * 2 + InlineInputGap > SafeWidth
		)

	local BaseHeight = Theme.ElementHeight
	local LabelPosition = TextBoxPosition + Vector2.new(HorizontalInset, (Theme.ElementHeight - Theme.ElementFontSize) / 2)
	local InputTextPositionY = TextBoxPosition.Y + (Theme.ElementHeight - Theme.ElementFontSize) / 2
	local InputStartX

	if UsesStackedLayout then
		BaseHeight = Theme.ElementHeight + FontLineHeight(Theme.ElementFontSize) + 4
		LabelPosition = TextBoxPosition + Vector2.new(HorizontalInset, 6)
		InputStartX = TextBoxPosition.X + HorizontalInset
		InputTextPositionY = TextBoxPosition.Y + BaseHeight - Theme.ElementFontSize - 7
	else
		InputStartX = TextBoxPosition.X + HorizontalInset
		if LabelDisplayText ~= "" then
			InputStartX = InputStartX + EstimatedLabelWidth + InlineInputGap
		end
	end

	local AvailableInputWidth = math.max(CharacterWidth, TextBoxPosition.X + SafeWidth - InputStartX - HorizontalInset)
	local MaximumCharacters = math.max(1, math.floor(AvailableInputWidth / CharacterWidth))
	local MaximumLabelCharacters = math.max(1, math.floor((SafeWidth - HorizontalInset * 2) / LabelCharacterWidth))

	return {
		BaseHeight = BaseHeight,
		UsesStackedLayout = UsesStackedLayout,
		LabelPosition = LabelPosition,
		LabelDisplayText = TruncateTextWithAsciiEllipsis(LabelDisplayText, MaximumLabelCharacters),
		InputStartX = InputStartX,
		InputTextPositionY = InputTextPositionY,
		AvailableInputWidth = AvailableInputWidth,
		CharacterWidth = CharacterWidth,
		MaximumCharacters = MaximumCharacters,
	}
end

ConfigureElementTooltip = function(Element, ElementConfiguration)
	-- Interactive controls opt into delayed explanatory tooltips through one
	-- common field. SetTooltip also lets asynchronous features update their
	-- description after remote data becomes available.
	local ExplicitTooltip = ElementConfiguration and ElementConfiguration.Tooltip
	if ExplicitTooltip == nil or tostring(ExplicitTooltip) == "" then
		local ElementName = tostring(Element._Text or "control")
		local DefaultTooltipByType = {
			TextButton = string.format("Runs the '%s' action.", ElementName),
			Toggle = string.format("Enables or disables '%s'.", ElementName),
			Dropdown = string.format("Selects a value for '%s'.", ElementName),
			TextBox = string.format("Edits the value for '%s'.", ElementName),
			Slider = string.format("Adjusts the numeric value for '%s'.", ElementName),
			ColorPicker = string.format("Selects a color for '%s'.", ElementName),
		}
		ExplicitTooltip = DefaultTooltipByType[Element._Type] or ""
	end

	Element._Tooltip = tostring(ExplicitTooltip or "")
	Element._TooltipHoverStartedAt = nil

	function Element:SetTooltip(NewTooltip)
		Element._Tooltip = tostring(NewTooltip or "")
		Element._TooltipHoverStartedAt = nil
	end
end

GetTooltipGeometry = function(Window, MousePosition)
	local Element = Window and Window._HoveredTooltipElement or nil
	if not Element or not Window._Visible or Element._Tooltip == "" or not Element._TooltipHoverStartedAt then
		return nil
	end

	if tick() - Element._TooltipHoverStartedAt < Theme.TooltipDelay then
		return nil
	end

	local Camera = Workspace and Workspace.CurrentCamera and CloneReference(Workspace.CurrentCamera) or nil
	local ViewportSize = Camera and Camera.ViewportSize or Vector2.new(1920, 1080)
	local TooltipWidth = math.min(Theme.TooltipWidth, math.max(140, ViewportSize.X - 16))
	local AvailableTextWidth = TooltipWidth - Theme.TooltipPadding * 2
	local WrappedLines = WrapText(Element._Tooltip, AvailableTextWidth, Theme.ElementFontSize)
	while #WrappedLines > Theme.TooltipMaximumLines do
		table.remove(WrappedLines)
	end
	if #WrappedLines == Theme.TooltipMaximumLines then
		local LastLineIndex = #WrappedLines
		local MaximumCharacters = math.max(1, math.floor(AvailableTextWidth / GetEditableTextCharacterWidth(Theme.ElementFontSize)))
		WrappedLines[LastLineIndex] = TruncateTextWithAsciiEllipsis(WrappedLines[LastLineIndex], MaximumCharacters)
	end

	local TooltipHeight = Theme.TooltipPadding * 2 + #WrappedLines * FontLineHeight(Theme.ElementFontSize)
	local TooltipPosition = MousePosition + Vector2.new(16, 20)
	TooltipPosition = Vector2.new(
		math.clamp(TooltipPosition.X, 8, math.max(8, ViewportSize.X - TooltipWidth - 8)),
		math.clamp(TooltipPosition.Y, 8, math.max(8, ViewportSize.Y - TooltipHeight - 8))
	)

	return {
		Position = TooltipPosition,
		Size = Vector2.new(TooltipWidth, TooltipHeight),
		Lines = WrappedLines,
	}
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
	local SearchBarHeightOffset = Window._SearchActive and 32 or 0
	local ViewportStart = WindowPositionY
		+ Theme.TitleBarHeight
		+ (Window._TabBarHeight or 0)
		+ SearchBarHeightOffset
	local ViewportEnd = WindowPositionY
		+ Theme.TitleBarHeight
		+ Window._VisibleHeight
	return ViewportStart, math.max(ViewportStart, ViewportEnd)
end

local function GetWindowContentViewportHeight(Window)
	local ViewportStart, ViewportEnd = GetWindowContentViewportYRange(Window, 0)
	return math.max(Theme.ElementHeight, ViewportEnd - ViewportStart)
end

local function GetWindowResizeGripHitSize(Window)
	-- The decorative corner remains intentionally compact, but a finger needs a
	-- substantially larger invisible target than a mouse cursor. Keeping the
	-- target inside the window prevents it from stealing touches from nearby
	-- Roblox controls while still meeting a comfortable mobile touch size.
	if Window and Window._TouchInputAvailable then
		return math.max(48, Theme.ElementHeight * 1.2)
	end

	return math.max(18, Theme.InnerMargin)
end

local function CreateScrollbarGeometry(
	TrackPosition,
	TrackHeight,
	VisibleCanvasHeight,
	CanvasHeight,
	ScrollOffset,
	MaximumScroll,
	MinimumHandleHeight
)
	if TrackHeight <= 0 or VisibleCanvasHeight <= 0 or CanvasHeight <= 0 then
		return nil
	end

	local RawHandleHeight = (VisibleCanvasHeight / CanvasHeight) * TrackHeight
	local HandleHeight = math.clamp(
		RawHandleHeight,
		math.min(MinimumHandleHeight, TrackHeight),
		TrackHeight
	)
	local ScrollProgress = MaximumScroll > 0
		and math.clamp((ScrollOffset or 0) / MaximumScroll, 0, 1)
		or 0
	local HandlePositionY = TrackPosition.Y
		+ (TrackHeight - HandleHeight) * ScrollProgress

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

local function GetMainScrollbarGeometry(Window, WindowPosition)
	if Window._MaxScroll <= 0 then
		return nil
	end

	local ViewportStart, ViewportEnd = GetWindowContentViewportYRange(
		Window,
		WindowPosition.Y
	)
	local ContentViewportHeight = math.max(0, ViewportEnd - ViewportStart)
	local TrackHeight = math.max(0, ContentViewportHeight - 4)
	local TrackPosition = Vector2.new(
		WindowPosition.X + Theme.WindowWidth - Theme.ScrollbarWidth - 2,
		ViewportStart + 2
	)

	return CreateScrollbarGeometry(
		TrackPosition,
		TrackHeight,
		ContentViewportHeight,
		math.max(Window._CanvasHeight or Window._VisibleHeight, 1),
		Window._ScrollOffset,
		Window._MaxScroll,
		20
	)
end

local function GetSectionScrollbarGeometry(Section, Window)
	if not Section._MaxHeight or Section._SectionMaxScroll <= 0 then
		return nil
	end

	local SectionAbsolutePosition = Window._Position + Vector2.new(
		Section._PositionX,
		Section._PositionY - Window._ScrollOffset
	)
	local VisibleSectionHeight = Section._ClippedHeight or Section._ContentHeight or 0
	local VisibleCanvasHeight = math.max(VisibleSectionHeight - Theme.ElementHeight, 1)
	local TrackHeight = math.max(0, VisibleSectionHeight - Theme.ElementHeight - 4)
	local TrackPosition = Vector2.new(
		SectionAbsolutePosition.X + Section._Width - Theme.ScrollbarWidth - 2,
		SectionAbsolutePosition.Y + Theme.ElementHeight + 2
	)

	return CreateScrollbarGeometry(
		TrackPosition,
		TrackHeight,
		VisibleCanvasHeight,
		math.max(
			(Section._FullContentHeight or Section._ContentHeight or 0) - Theme.ElementHeight,
			1
		),
		Section._SectionScrollOffset,
		Section._SectionMaxScroll,
		12
	)
end

local function GetCurrentCamera()
	local Camera = Workspace and Workspace.CurrentCamera
	return Camera and CloneReference(Camera) or nil
end

local function GetViewportSize()
	local Camera = GetCurrentCamera()
	return Camera and Camera.ViewportSize or Vector2.new(1920, 1080)
end

local function GetNotificationEntrySize(NotificationEntry)
	local NotificationSize = NotificationEntry and NotificationEntry.Size
	if typeof(NotificationSize) == "Vector2" then
		return NotificationSize
	end
	return Vector2.new(Theme.NotificationWidth, Theme.NotificationHeight)
end

-- Notification entries can have different dimensions after word wrapping. The
-- complete stack is therefore laid out cumulatively instead of multiplying an
-- index by one fixed height. The stack prefers the right side of the window,
-- moves to the left when necessary, and remains fully inside the viewport.
local function GetNotificationStackPositions(TargetPosition, NotificationEntries)
	local ViewportSize = GetViewportSize()
	local ViewportMargin = Theme.NotificationMargin
	local TotalStackHeight = 0

	for NotificationIndex, NotificationEntry in ipairs(NotificationEntries) do
		TotalStackHeight = TotalStackHeight + GetNotificationEntrySize(NotificationEntry).Y
		if NotificationIndex < #NotificationEntries then
			TotalStackHeight = TotalStackHeight + Theme.NotificationMargin
		end
	end

	local MaximumStackTop = math.max(
		ViewportMargin,
		ViewportSize.Y - TotalStackHeight - ViewportMargin
	)
	local StackTopPositionY
	if TargetPosition.Y + TotalStackHeight <= ViewportSize.Y - ViewportMargin then
		StackTopPositionY = TargetPosition.Y
	elseif TargetPosition.Y - TotalStackHeight >= ViewportMargin then
		StackTopPositionY = TargetPosition.Y - TotalStackHeight
	else
		StackTopPositionY = math.clamp(
			TargetPosition.Y,
			ViewportMargin,
			MaximumStackTop
		)
	end

	local NotificationPositions = {}
	local CurrentPositionY = StackTopPositionY
	for NotificationIndex, NotificationEntry in ipairs(NotificationEntries) do
		local NotificationSize = GetNotificationEntrySize(NotificationEntry)
		local RightSidePositionX = TargetPosition.X
			+ Theme.WindowWidth
			+ Theme.NotificationMargin
		local LeftSidePositionX = TargetPosition.X
			- NotificationSize.X
			- Theme.NotificationMargin
		local MaximumPositionX = math.max(
			ViewportMargin,
			ViewportSize.X - NotificationSize.X - ViewportMargin
		)
		local PositionX = RightSidePositionX
		if RightSidePositionX + NotificationSize.X
			> ViewportSize.X - ViewportMargin
		then
			PositionX = LeftSidePositionX
		end
		PositionX = math.clamp(PositionX, ViewportMargin, MaximumPositionX)

		NotificationPositions[NotificationIndex] = Vector2.new(
			PositionX,
			CurrentPositionY
		)
		CurrentPositionY = CurrentPositionY
			+ NotificationSize.Y
			+ Theme.NotificationMargin
	end

	return NotificationPositions
end

-- Move every retained Drawing object belonging to one notification. Immediate
-- mode reads Entry.Position during paint, so updating the shared position also
-- keeps both rendering backends on the same geometry path.
local function SetNotificationEntryPosition(NotificationEntry, NotificationPosition)
	NotificationEntry.Position = NotificationPosition
	local NotificationSize = GetNotificationEntrySize(NotificationEntry)

	if NotificationEntry.Background then
		SetRenderProperty(NotificationEntry.Background, "Position", NotificationPosition)
		SetRenderProperty(NotificationEntry.Background, "Size", NotificationSize)
	end
	if NotificationEntry.Border then
		SetRenderProperty(NotificationEntry.Border, "Position", NotificationPosition)
		SetRenderProperty(NotificationEntry.Border, "Size", NotificationSize)
	end
	if NotificationEntry.AccentLine then
		SetRenderProperty(NotificationEntry.AccentLine, "From", Vector2.new(
			NotificationPosition.X + 3,
			NotificationPosition.Y + 4
		))
		SetRenderProperty(NotificationEntry.AccentLine, "To", Vector2.new(
			NotificationPosition.X + 3,
			NotificationPosition.Y + NotificationSize.Y - 4
		))
	end
	local TextStartPositionY = NotificationPosition.Y
		+ (NotificationEntry.TextStartOffsetY or Theme.NotificationVerticalPadding)
	for TextLineIndex, TextLabel in ipairs(NotificationEntry.TextLabels or {}) do
		SetRenderProperty(TextLabel, "Position", Vector2.new(
			NotificationPosition.X + Theme.NotificationHorizontalPadding,
			TextStartPositionY
				+ (TextLineIndex - 1) * FontLineHeight(Theme.ElementFontSize)
		))
	end
end

-- Recalculate a complete notification stack from its current window position.
-- This is called during drag, resize, viewport changes, and stack expiration.
local function RepositionNotificationStack(NotificationEntries, TargetPosition)
	local NotificationPositions = GetNotificationStackPositions(
		TargetPosition,
		NotificationEntries
	)
	for NotificationIndex, NotificationEntry in ipairs(NotificationEntries) do
		SetNotificationEntryPosition(
			NotificationEntry,
			NotificationPositions[NotificationIndex]
		)
	end
end

-- Clip a rectangle to the visible vertical viewport. A nil result means the
-- rectangle is fully outside the viewport and should not be drawn.
local function ClipRectangleToYRange(Position, Size, MinimumPositionY, MaximumPositionY)
	local RectangleTopPositionY = Position.Y
	local RectangleBottomPositionY = RectangleTopPositionY + Size.Y
	local ClippedTopPositionY = math.max(RectangleTopPositionY, MinimumPositionY)
	local ClippedBottomPositionY = math.min(RectangleBottomPositionY, MaximumPositionY)

	if ClippedTopPositionY >= ClippedBottomPositionY then
		return nil, nil
	end

	return Vector2.new(Position.X, ClippedTopPositionY), Vector2.new(Size.X, ClippedBottomPositionY - ClippedTopPositionY)
end

-- Clip a vertical line to the visible vertical range while preserving its
-- horizontal position.
local function ClipVerticalLineToYRange(FromPosition, ToPosition, MinimumPositionY, MaximumPositionY)
	local LineTopPositionY = math.min(FromPosition.Y, ToPosition.Y)
	local LineBottomPositionY = math.max(FromPosition.Y, ToPosition.Y)
	local ClippedTopPositionY = math.max(LineTopPositionY, MinimumPositionY)
	local ClippedBottomPositionY = math.min(LineBottomPositionY, MaximumPositionY)

	if ClippedTopPositionY >= ClippedBottomPositionY then
		return nil, nil
	end

	return Vector2.new(FromPosition.X, ClippedTopPositionY), Vector2.new(ToPosition.X, ClippedBottomPositionY)
end

-- Clip a horizontal line to the visible vertical range. Horizontal lines do not
-- need x adjustment, only y visibility checks.
local function ClipHorizontalLineToYRange(FromPosition, ToPosition, MinimumPositionY, MaximumPositionY)
	local LinePositionY = FromPosition.Y
	if LinePositionY >= MinimumPositionY and LinePositionY <= MaximumPositionY then
		return FromPosition, ToPosition
	else
		return nil, nil
	end
end

DrawImmediateTextBoxSelectionAndCursor = function(Element, InputStartX, InputTextPositionY, CharacterWidth, MaximumCharacters, AllowedMinY, AllowedMaxY, HasValue)
	-- Immediate Drawing mode has no retained cursor object, so selection and
	-- cursor geometry are painted directly each frame from the same index model
	-- used by keyboard editing. This helper stays outside the large CreateWindow
	-- closure so Luau's upvalue limit is not exceeded.
	if Element._IsSelected and HasValue then
		local SelectionStartIndex, SelectionEndIndex = GetTextBoxSelectionBounds(Element)
		local DisplayStartIndex, DisplayEndIndex = GetVisibleTextBoxCharacterRange(Element, MaximumCharacters)
		local VisibleSelectionStartIndex = SelectionStartIndex and math.max(SelectionStartIndex, DisplayStartIndex)
		local VisibleSelectionEndIndex = SelectionEndIndex and math.min(SelectionEndIndex, DisplayEndIndex)
		if VisibleSelectionStartIndex and VisibleSelectionEndIndex and VisibleSelectionStartIndex < VisibleSelectionEndIndex then
			local SelectionX = InputStartX + (VisibleSelectionStartIndex - DisplayStartIndex) * CharacterWidth
			local SelectionWidth = (VisibleSelectionEndIndex - VisibleSelectionStartIndex) * CharacterWidth
			local SelectionPosition = Vector2.new(SelectionX - 2, InputTextPositionY - 2)
			local SelectionSize = Vector2.new(SelectionWidth + 4, Theme.ElementFontSize + 4)
			local ClippedSelectionPosition, ClippedSelectionSize = ClipRectangleToYRange(SelectionPosition, SelectionSize, AllowedMinY, AllowedMaxY)
			if ClippedSelectionPosition and ClippedSelectionSize then
				DrawingImmediateFilledRectangle(ClippedSelectionPosition, ClippedSelectionSize, Theme.TextBoxSelection, 0.5, 0)
			end
		end
	end

	if Element._IsFocused and Element._CursorVisible then
		local DisplayStartIndex, DisplayEndIndex = GetVisibleTextBoxCharacterRange(Element, MaximumCharacters)
		local CursorIndex = math.clamp(ClampTextBoxCursorIndex(Element, Element._CursorIndex), DisplayStartIndex, DisplayEndIndex)
		local CursorX = InputStartX + (CursorIndex - DisplayStartIndex) * CharacterWidth
		local CursorTopY = InputTextPositionY
		local CursorBottomY = CursorTopY + Theme.ElementFontSize
		local ClippedCursorFrom, ClippedCursorTo = ClipVerticalLineToYRange(
			Vector2.new(CursorX, CursorTopY + 1),
			Vector2.new(CursorX, CursorBottomY - 1),
			AllowedMinY,
			AllowedMaxY
		)
		if ClippedCursorFrom and ClippedCursorTo then
			DrawingImmediateLine(ClippedCursorFrom, ClippedCursorTo, Theme.TextBoxCursor, 1, 1)
		end
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

local function IsElementFullyVisibleInViewport(ElementAbsolutePositionY, ElementHeight, Section, Window, WindowPositionY)
	-- Retained Drawing rectangles cannot be clipped by a parent object. Controls
	-- are therefore shown only when their complete interactive body fits inside
	-- both the page viewport and an optional section viewport. Multi-line labels
	-- continue using line-level clipping through IsElementVisibleInViewport.
	local AllowedMinimumPositionY, AllowedMaximumPositionY = GetSectionAllowedYRange(
		Section,
		Window,
		WindowPositionY
	)
	return ElementAbsolutePositionY >= AllowedMinimumPositionY
		and ElementAbsolutePositionY + ElementHeight <= AllowedMaximumPositionY
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

		local CreationSucceeded, DrawingObject = pcall(DrawingLibrary.new, ObjectType)
		if not CreationSucceeded or not DrawingObject then
			return nil
		end
		table.insert(TrackedDrawingsTable, DrawingObject)

		return DrawingObject
	end

	local function CreateRectangleDrawing(FillColor, IsFilled, ZIndexValue, TransparencyValue)
		-- Square is the Drawing class used for filled and outlined rectangles.
		local RectangleObject = CreateTrackedDrawingObject("Square")
		local RectangleProperties = {
			Color        = FillColor,
			Filled       = IsFilled,
			Transparency = TransparencyValue or 0.95,
			ZIndex       = ZIndexValue or 1,
			Visible      = true,
		}
		-- Potassium's native Square contract has no Rounding property. The local
		-- ScreenGui emulator intentionally extends Square with it for visual parity.
		if not DrawingIsNative then
			RectangleProperties.Rounding = Theme.ControlCornerRadius
		end
		ApplyDrawingProperties(RectangleObject, RectangleProperties)
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

-- Inline visual tokens let labels mix tiny drawn markers with regular text.
-- The original text stays plain and copyable, while the renderer replaces
-- tokens such as :green_circle: with Drawing-backed shapes.
Theme.InlineVisualTokens = {
	[":green_circle:"] = { Shape = "Circle", Color = Color3.fromRGB(66, 214, 118) },
	[":white_circle:"] = { Shape = "Circle", Color = Color3.fromRGB(231, 236, 238) },
	[":red_circle:"] = { Shape = "Circle", Color = Color3.fromRGB(235, 82, 82) },
	[":yellow_circle:"] = { Shape = "Circle", Color = Color3.fromRGB(240, 204, 82) },
	[":blue_circle:"] = { Shape = "Circle", Color = Color3.fromRGB(86, 154, 244) },
}

function Theme:GetInlineVisualCharacterWidth(FontSizeValue)
	-- Drawing text has no glyph measurement application programming interface,
	-- so marker placement uses the
	-- same fixed-width estimate as the rest of the custom label layout.
	return FontSizeValue * ((Theme and Theme.FontCharWidthRatio or 0.52) * 1.25)
end

function Theme:ParseInlineVisualLine(LineText, FontSizeValue)
	-- Replace known marker tokens with two spaces and remember where the shape
	-- should be painted. Unknown :tokens: are left untouched.
	local OutputParts = {}
	local InlineVisuals = {}
	local SearchPosition = 1
	local VisibleCharacterCount = 0

	while true do
		local TokenStart, TokenEnd, TokenText = string.find(LineText, "(:[%w_]+:)", SearchPosition)
		if not TokenStart then
			local RemainingText = string.sub(LineText, SearchPosition)
			OutputParts[#OutputParts + 1] = RemainingText
			VisibleCharacterCount = VisibleCharacterCount + #RemainingText
			break
		end

		local TokenMetadata = Theme.InlineVisualTokens[TokenText]
		if TokenMetadata then
			local PrefixText = string.sub(LineText, SearchPosition, TokenStart - 1)
			OutputParts[#OutputParts + 1] = PrefixText
			VisibleCharacterCount = VisibleCharacterCount + #PrefixText

			OutputParts[#OutputParts + 1] = "  "
			InlineVisuals[#InlineVisuals + 1] = {
				ColumnIndex = VisibleCharacterCount,
				CharacterWidth = Theme:GetInlineVisualCharacterWidth(FontSizeValue),
				Color = TokenMetadata.Color,
				Shape = TokenMetadata.Shape,
			}
			VisibleCharacterCount = VisibleCharacterCount + 2
		else
			local LiteralText = string.sub(LineText, SearchPosition, TokenEnd)
			OutputParts[#OutputParts + 1] = LiteralText
			VisibleCharacterCount = VisibleCharacterCount + #LiteralText
		end

		SearchPosition = TokenEnd + 1
	end

	return table.concat(OutputParts), InlineVisuals
end

function Theme:HideInlineVisualDrawings(Element)
	for VisualIndex, VisualData in ipairs(Element._InlineVisualDrawings or {}) do
		if VisualData.DrawingObject then
			SetRenderProperty(VisualData.DrawingObject, "Visible", false)
		end
	end
end

local function SetDrawingObjectsVisibility(DrawingObjects, IsVisible)
	for DrawingObjectIndex, DrawingObject in ipairs(DrawingObjects) do
		if DrawingObject then
			SetRenderProperty(DrawingObject, "Visible", IsVisible)
		end
	end
end

local Library = {}
local SupportedInputBlockingTypes = {
	Scroll = true,
	TouchInterface = true,
	Interface = true,
	Camera = true,
}

function Library.CopyTextToClipboard(ClipboardText)
	-- Clipboard access belongs to the executor rather than Roblox. Keep the
	-- original function reference and expose one truthful result contract to all
	-- applications instead of maintaining per-game no-op compatibility shims.
	if typeof(WriteClipboardText) ~= "function" then
		return false, "Clipboard writing is unavailable on this executor"
	end

	local ClipboardWriteSucceeded, ClipboardFailureMessage = pcall(
		WriteClipboardText,
		tostring(ClipboardText or "")
	)
	if not ClipboardWriteSucceeded then
		return false, tostring(ClipboardFailureMessage)
	end
	return true, nil
end

function Library.FindExistingOrAwaitAddedChild(TargetInstance, ChildName, CancellationPredicate)
	-- Consumers frequently need a replicated object that may already exist or
	-- may arrive after startup. This shared implementation prevents each script
	-- from maintaining a subtly different ChildAdded waiting loop. An optional
	-- cancellation predicate lets lifecycle-owned workers stop waiting when their
	-- window, controller, or character generation is no longer current.
	if typeof(TargetInstance) ~= "Instance"
		or typeof(ChildName) ~= "string"
		or ChildName == ""
		or (CancellationPredicate ~= nil and typeof(CancellationPredicate) ~= "function")
	then
		return nil
	end

	local InitialLookupSucceeded, InitialChild = pcall(
		FindFirstChild,
		TargetInstance,
		ChildName
	)
	if InitialLookupSucceeded and InitialChild then
		return CloneReference(InitialChild)
	end

	local ChildAddedSignalReadSucceeded, ChildAddedSignal = pcall(function()
		return TargetInstance.ChildAdded
	end)
	if not ChildAddedSignalReadSucceeded or not ChildAddedSignal then
		return nil
	end

	-- A direct signal wait cannot be cancelled. Keep one temporary connection
	-- instead, then yield cooperatively while checking both the requested child
	-- and the caller's lifecycle predicate.
	local AddedMatchingChild
	local ConnectionSucceeded, ChildAddedConnection = pcall(
		ConnectSignal,
		ChildAddedSignal,
		NewCClosure(function(AddedChild)
			AddedChild = CloneReference(AddedChild)
			if AddedChild and AddedChild.Name == ChildName then
				AddedMatchingChild = AddedChild
			end
		end)
	)
	if not ConnectionSucceeded or not ChildAddedConnection then
		return nil
	end

	local function DisconnectChildAddedConnection()
		if ChildAddedConnection then
			pcall(ChildAddedConnection.Disconnect, ChildAddedConnection)
			ChildAddedConnection = nil
		end
	end

	while not AddedMatchingChild do
		if CancellationPredicate then
			local PredicateSucceeded, ShouldCancel = pcall(CancellationPredicate)
			if not PredicateSucceeded or ShouldCancel == true then
				DisconnectChildAddedConnection()
				return nil
			end
		end

		local RecheckSucceeded, RecheckedChild = pcall(
			FindFirstChild,
			TargetInstance,
			ChildName
		)
		if RecheckSucceeded and RecheckedChild then
			AddedMatchingChild = CloneReference(RecheckedChild)
			break
		end
		task.wait()
	end

	DisconnectChildAddedConnection()
	return AddedMatchingChild
end

function Library.GetSortedDictionaryKeys(Dictionary)
	-- Deterministic dictionary ordering keeps generated information reports and
	-- dropdown options stable between refreshes.
	local SortedKeys = {}
	if typeof(Dictionary) ~= "table" then
		return SortedKeys
	end

	for DictionaryKey in pairs(Dictionary) do
		SortedKeys[#SortedKeys + 1] = DictionaryKey
	end
	table.sort(SortedKeys, function(FirstKey, SecondKey)
		return string.lower(tostring(FirstKey)) < string.lower(tostring(SecondKey))
	end)
	return SortedKeys
end

Library._Windows = {}

Library._ActiveSinks = {}
Library._ActiveSinkStates = {}
Library._InputBlockingRequests = {}

Library._Visible = true

Library.ToggleKey = Enum.KeyCode.RightControl

Library.Connections = {}

Library.Theme = Theme

function Library:IsExecutorFunctionSupported(TargetFunction)
	-- Lua wrappers can imitate an executor application programming interface
	-- while omitting behavior that the control depends on. Only C-backed
	-- implementations are therefore advertised as supported.
	return IsNativeExecutorFunction(TargetFunction)
end

function Library:IsPageTabFullyInsideViewport(TabLayout, WindowPositionX, WindowWidth, TabPositionX, TabWidth)
	-- Drawing backends do not provide a reliable clipping rectangle. A partially
	-- visible tab would therefore paint its background and title beyond the window
	-- border. Use the same strict viewport test for drawing and pointer hit testing
	-- so an off-screen tab is neither rendered nor accidentally interactive.
	local TabViewportLeft = WindowPositionX + TabLayout.Padding
	local TabViewportRight = WindowPositionX + WindowWidth - TabLayout.Padding
	local FloatingPointTolerance = 0.5
	return TabPositionX >= TabViewportLeft - FloatingPointTolerance
		and TabPositionX + TabWidth <= TabViewportRight + FloatingPointTolerance
end

-- A touch-capable desktop can expose TouchEnabled even when the interface is
-- primarily operated with a mouse. DeviceType is therefore the authoritative
-- phone/tablet signal, while the viewport check covers executors that report an
-- unknown device type on a genuinely compact touch screen.
local function IsTouchInterfaceDevice()
	local DetectedDeviceType = GetDeviceType(UserInputService)
	if DetectedDeviceType == Enum.DeviceType.Phone or DetectedDeviceType == Enum.DeviceType.Tablet then
		return true
	end
	if DetectedDeviceType ~= Enum.DeviceType.Unknown and tostring(DetectedDeviceType) ~= "Unknown" then
		return false
	end

	if UserInputService.TouchEnabled ~= true then
		return false
	end
	if UserInputService.KeyboardEnabled == true or UserInputService.MouseEnabled == true then
		-- Some executors report DeviceType.Unknown and TouchEnabled on ordinary
		-- personal computers. Physical keyboard or mouse availability is a stronger
		-- desktop signal than the touch capability bit and prevents the permanent
		-- TouchInterface sink from disabling camera and mouse window controls.
		return false
	end

	local ViewportSize = GetViewportSize()
	return math.min(ViewportSize.X, ViewportSize.Y) <= 1400
end

-- Application scripts use this capability query to expose controls that only
-- make sense when no physical keyboard shortcut is guaranteed to be present.
function Library:IsTouchInputAvailable()
	return IsTouchInterfaceDevice()
end

function Library:GetTouchInputScreenPosition(InputObject, CoordinateInset)
	-- Application-level touch controls must use the exact coordinate conversion
	-- used by the library window. Returning nil for an invalid object lets callers
	-- pass the input through without manufacturing an unreliable position.
	if not InputObject or typeof(InputObject.Position) ~= "Vector3" then
		return nil
	end

	return GetTouchInputScreenPosition(InputObject, CoordinateInset)
end

local CachedPreferredInput = nil

table.insert(Library.Connections, ConnectSignal(UserInputService.InputChanged, NewCClosure(function()
	local CurrentPreferredInput = UserInputService.PreferredInput
	if CurrentPreferredInput ~= CachedPreferredInput then
		CachedPreferredInput = CurrentPreferredInput
		if Library.OnInputTypeChanged then
			pcall(Library.OnInputTypeChanged, CurrentPreferredInput)
		end
	end
end)))

function Library:ProcessMouseWheel(Input)
	if not Library._Visible then 
		return false
	end

	if Input.UserInputType == Enum.UserInputType.MouseWheel then
		local CurrentClock = os.clock()
		local DeltaSignature = tostring(Input.Position.Z)
		if Library._LastMouseWheelClock and CurrentClock - Library._LastMouseWheelClock < 0.01 and Library._LastMouseWheelSignature == DeltaSignature then
			return true
		end

		Library._LastMouseWheelClock = CurrentClock
		Library._LastMouseWheelSignature = DeltaSignature
		local CurrentMousePosition = GetMouseLocation(UserInputService)

		for Index, Window in ipairs(Library._Windows) do
			if Window._Visible and not Window._Destroyed then
				local TabBarPosition = Window._Position + Vector2.new(0, Theme.TitleBarHeight)
				local TabBarSize = Vector2.new(Theme.WindowWidth, Window._TabBarHeight)
				if Window._TabBarHeight > 0 and IsPointInsideRectangle(CurrentMousePosition, TabBarPosition, TabBarSize) then
					local TabLayout = GetPageTabLayout(Window, Theme.WindowWidth)
					local Delta = Input.Position.Z * 30
					Window._TabScrollOffset = math.clamp(
						(Window._TabScrollOffset or 0) - Delta,
						0,
						TabLayout.MaximumScroll
					)
					Window:RecalculateLayout()
					return true
				else
					local BodyPosition = Vector2.new(Window._Position.X, Window._Position.Y + Theme.TitleBarHeight)
					local BodySize = Vector2.new(Theme.WindowWidth, Window._VisibleHeight)

					if IsPointInsideRectangle(CurrentMousePosition, BodyPosition, BodySize) then
						local Delta = Input.Position.Z * 45
						local ActiveDropdown = Window._ActiveDropdown
						if ActiveDropdown and ActiveDropdown._Expanded and ActiveDropdown._OptionsRegion then
							if IsPointInsideRectangle(CurrentMousePosition, ActiveDropdown._OptionsRegion.Position, ActiveDropdown._OptionsRegion.Size) then
								ActiveDropdown._OptionsScrollOffset = math.clamp(
									(ActiveDropdown._OptionsScrollOffset or 0) - Delta,
									0,
									GetDropdownMaximumScroll(ActiveDropdown)
								)
								Window:RecalculateLayout()
								return true
							end
						end

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

						return true
					end
				end
			end
		end
	end

	return false
end

table.insert(Library.Connections, ConnectSignal(UserInputService.InputChanged, NewCClosure(function(Input)
	Library:ProcessMouseWheel(Input)
end)))

table.insert(Library.Connections, ConnectSignal(UserInputService.InputBegan, NewCClosure(function(Input, Processed)
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
				-- The hidden native Roblox TextBox is the sole text editor on every
				-- platform. Roblox owns keyboard layouts, Unicode composition,
				-- clipboard shortcuts, cursor movement, and the on-screen keyboard.
				local NativeTextInputState = Window._NativeTextInputState
				if NativeTextInputState
					and NativeTextInputState.Available
					and NativeTextInputState.TargetElement == FocusedBox then
					-- Single-line native TextBoxes do not use Up and Down for text
					-- editing, so those two keys remain available for navigating the
					-- library's suggestion list.
					if (Input.KeyCode == Enum.KeyCode.Up or Input.KeyCode == Enum.KeyCode.Down)
						and FocusedBox._Suggestions
						and #FocusedBox._Suggestions > 0 then
						local SuggestionCount = math.min(
							#FocusedBox._Suggestions,
							FocusedBox._MaximumSuggestions or #FocusedBox._Suggestions
						)
						local CurrentSuggestionIndex = FocusedBox._KeyboardSuggestionIndex or 0
						if Input.KeyCode == Enum.KeyCode.Down then
							CurrentSuggestionIndex = CurrentSuggestionIndex % SuggestionCount + 1
						else
							CurrentSuggestionIndex = (CurrentSuggestionIndex - 2) % SuggestionCount + 1
						end
						FocusedBox._KeyboardSuggestionIndex = CurrentSuggestionIndex
						Window:RecalculateLayout()
					end
				end
				return
			end
		end
	end
end)))

-- Normalize the external Drawing font table before exposing it through the
-- library. Drawing calls its first font "UI"; the public library name is
-- expanded to "User Interface" to keep displayed option names descriptive.
local DrawingFontIdentifiers = (typeof(DrawingLibrary) == "table" and DrawingLibrary.Fonts) or {
	UserInterface = 0,
	System = 1,
	Plex = 2,
	Monospace = 3,
}
Library.Fonts = {}
for OriginalFontName, FontIdentifier in pairs(DrawingFontIdentifiers) do
	local PublicFontName = OriginalFontName == "UI" and "User Interface" or OriginalFontName
	Library.Fonts[PublicFontName] = FontIdentifier
end

-- Expose the rendering implementations through one small adapter instead of
-- making feature modules rediscover, download, and normalize the same Drawing
-- libraries. The retained adapter includes the replacement Drawing library
-- loaded above, so callers automatically receive the remote fallback whenever
-- the executor does not provide a native Drawing.new implementation.
function Library:GetRenderingBackends()
	local RetainedDrawingAvailable = typeof(DrawingLibrary) == "table" and typeof(DrawingLibrary.new) == "function"
	local ImmediateDrawingAvailable = DrawingImmediateGetPaint ~= nil
		and (DrawingImmediateText ~= nil or DrawingImmediateOutlinedText ~= nil)

	local function CreateRetainedDrawingObject(ObjectType)
		if not RetainedDrawingAvailable then
			return nil, "Drawing.new is unavailable"
		end

		local CreationSucceeded, DrawingObject = pcall(DrawingLibrary.new, ObjectType)
		if not CreationSucceeded then
			return nil, tostring(DrawingObject)
		end
		return DrawingObject, nil
	end

	local function DestroyRetainedDrawingObject(DrawingObject)
		if not DrawingObject then
			return
		end

		local MethodReadSucceeded, DestructionMethod = pcall(function()
			return DrawingObject.Destroy or DrawingObject.Remove
		end)
		if MethodReadSucceeded and typeof(DestructionMethod) == "function" then
			pcall(DestructionMethod, DrawingObject)
		end
	end

	return {
		DrawingImmediate = {
			Available = ImmediateDrawingAvailable,
			GetPaint = DrawingImmediateGetPaint,
			Line = DrawingImmediateLine,
			Circle = DrawingImmediateCircle,
			SolidCircle = DrawImmediateSolidCircle,
			FilledCircle = DrawingImmediateFilledCircle,
			Rectangle = DrawingImmediateRectangle,
			FilledRectangle = DrawingImmediateFilledRectangle,
			Triangle = DrawingImmediateTriangle,
			FilledTriangle = DrawingImmediateFilledTriangle,
			Quad = DrawingImmediateQuad,
			FilledQuad = DrawingImmediateFilledQuad,
			Text = DrawingImmediateText,
			OutlinedText = DrawingImmediateOutlinedText,
		},
		Drawing = {
			Available = RetainedDrawingAvailable,
			CreateObject = CreateRetainedDrawingObject,
			SetProperty = SetRenderProperty,
			GetProperty = GetRenderProperty,
			DestroyObject = DestroyRetainedDrawingObject,
		},
	}
end

function Theme:GetSliderTextLayoutMetrics(Element, SliderPosition, SliderWidth)
	-- Slider captions and values share one line, so the value receives a bounded
	-- right-aligned region and the caption uses only the remaining width. This
	-- prevents long labels from painting through numeric values or outside the
	-- section while preserving the complete value whenever practical.
	local SafeSliderWidth = math.max(1, tonumber(SliderWidth) or 1)
	local CharacterWidth = GetEditableTextCharacterWidth(self.ElementFontSize)
	local HorizontalGap = math.max(8, CharacterWidth)
	local RawValueText = tostring(Element._Value or 0)
	local MaximumValueCharacters = math.max(
		1,
		math.floor((SafeSliderWidth * 0.4) / CharacterWidth)
	)
	local ValueDisplayText = TruncateTextWithAsciiEllipsis(
		RawValueText,
		MaximumValueCharacters
	)
	local ValueTextWidth = math.min(
		SafeSliderWidth,
		#ValueDisplayText * CharacterWidth
	)
	local ValuePositionX = SliderPosition.X + SafeSliderWidth - ValueTextWidth
	local LabelAvailableWidth = math.max(
		CharacterWidth,
		ValuePositionX - SliderPosition.X - HorizontalGap
	)
	local MaximumLabelCharacters = math.max(
		1,
		math.floor(LabelAvailableWidth / CharacterWidth)
	)

	return {
		LabelPosition = SliderPosition,
		LabelDisplayText = TruncateTextWithAsciiEllipsis(
			tostring(Element._Text or ""),
			MaximumLabelCharacters
		),
		ValuePosition = Vector2.new(ValuePositionX, SliderPosition.Y),
		ValueDisplayText = ValueDisplayText,
	}
end

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

-- Measure a notification from its complete text. Short messages expand
-- horizontally, while longer messages wrap at the configured maximum width and
-- increase the box height. No content is replaced with an ellipsis.
local function GetNotificationLayout(NotificationText)
	local ViewportSize = GetViewportSize()
	local MaximumViewportWidth = math.max(
		1,
		ViewportSize.X - Theme.NotificationMargin * 2
	)
	local MinimumNotificationWidth = math.min(
		Theme.NotificationWidth,
		MaximumViewportWidth
	)
	local MaximumNotificationWidth = math.max(
		MinimumNotificationWidth,
		math.min(
			Theme.NotificationMaximumWidth or Theme.NotificationWidth,
			MaximumViewportWidth
		)
	)
	local CharacterWidth = Theme.ElementFontSize
		* ((Theme.FontCharWidthRatio or 0.52) * 1.15)
	local LongestExplicitLineLength = 0

	for ExplicitLine in string.gmatch(
		string.format("%s\n", NotificationText),
		"([^\n]*)\n"
	) do
		LongestExplicitLineLength = math.max(
			LongestExplicitLineLength,
			#ExplicitLine
		)
	end

	local DesiredNotificationWidth = math.ceil(
		LongestExplicitLineLength * CharacterWidth
			+ Theme.NotificationHorizontalPadding * 2
	)
	local NotificationWidth = math.clamp(
		DesiredNotificationWidth,
		MinimumNotificationWidth,
		MaximumNotificationWidth
	)
	local WrappedLines = WrapText(
		NotificationText,
		math.max(
			1,
			NotificationWidth - Theme.NotificationHorizontalPadding * 2
		),
		Theme.ElementFontSize
	)
	local TextHeight = #WrappedLines * FontLineHeight(Theme.ElementFontSize)
	local NotificationHeight = math.max(
		Theme.NotificationHeight,
		TextHeight + Theme.NotificationVerticalPadding * 2
	)

	return {
		Lines = WrappedLines,
		Size = Vector2.new(NotificationWidth, NotificationHeight),
		TextStartOffsetY = math.floor((NotificationHeight - TextHeight) / 2),
	}
end

-- Show a transient notification next to a window or at a fixed screen position.
-- Window-specific notifications move with the window's notification stack.
function Library:ShowNotification(NotificationText, WindowOrPosition)
	NotificationText = tostring(NotificationText or "")
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

	local ActiveNotificationsList = TargetWindow
		and TargetWindow._ActiveNotifications
		or Library.ActiveNotifications
	local NotificationLayout = GetNotificationLayout(NotificationText)
	local NotificationPosition = TargetPosition

	local NotificationEntry = {
		Text = NotificationText,
		Lines = NotificationLayout.Lines,
		Size = NotificationLayout.Size,
		TextStartOffsetY = NotificationLayout.TextStartOffsetY,
		Duration = Theme.NotificationDuration
			+ math.max(0, #NotificationLayout.Lines - 1) * 0.65,
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
			Size = NotificationEntry.Size,
		})

		local NotificationBorder = CreateNotificationRectangleDrawing(Theme.NotificationBorder, false, 101, 0.8)
		ApplyDrawingProperties(NotificationBorder, {
			Position = NotificationPosition,
			Size = NotificationEntry.Size,
		})

		local NotificationAccentLine = CreateNotificationDrawingObject("Line")
		ApplyDrawingProperties(NotificationAccentLine, {
			From = Vector2.new(NotificationPosition.X + 3, NotificationPosition.Y + 4),
			To = Vector2.new(NotificationPosition.X + 3, NotificationPosition.Y + NotificationEntry.Size.Y - 4),
			Thickness = 2,
			Transparency = 1,
			Color = Theme.NotificationAccent,
			ZIndex = 103,
			Visible = true,
		})

		local NotificationTextLabels = {}
		for TextLineIndex, TextLine in ipairs(NotificationEntry.Lines) do
			local NotificationTextLabel = CreateNotificationTextDrawing(
				TextLine,
				Theme.ElementFontSize,
				Theme.NotificationText,
				102
			)
			ApplyDrawingProperties(NotificationTextLabel, {
				Position = Vector2.new(
					NotificationPosition.X + Theme.NotificationHorizontalPadding,
					NotificationPosition.Y
						+ NotificationEntry.TextStartOffsetY
						+ (TextLineIndex - 1)
							* FontLineHeight(Theme.ElementFontSize)
				),
				Transparency = 0.95,
			})
			table.insert(NotificationTextLabels, NotificationTextLabel)
		end

		NotificationEntry.Background = NotificationBackground
		NotificationEntry.Border = NotificationBorder
		NotificationEntry.AccentLine = NotificationAccentLine
		NotificationEntry.TextLabels = NotificationTextLabels
	end

	task.delay(NotificationEntry.Duration, function()
		-- Expire retained drawings and the stack entry atomically. A window may be
		-- destroyed before this timer fires, so cleanup only runs while the entry
		-- is still owned by its active notification list.
		local NotificationWasActive = false
		for EntryIndex, Entry in ipairs(ActiveNotificationsList) do
			if Entry == NotificationEntry then
				table.remove(ActiveNotificationsList, EntryIndex)
				NotificationWasActive = true
				break
			end
		end
		if not NotificationWasActive then
			return
		end

		if not UseImmediateMode then
			DestroyDrawing(NotificationEntry.Background, NotificationTrackedDrawings)
			DestroyDrawing(NotificationEntry.Border, NotificationTrackedDrawings)
			DestroyDrawing(NotificationEntry.AccentLine, NotificationTrackedDrawings)
			for TextLineIndex, NotificationTextLabel in ipairs(NotificationEntry.TextLabels or {}) do
				DestroyDrawing(NotificationTextLabel, NotificationTrackedDrawings)
			end
		end

		local CurrentTargetPosition = TargetWindow and TargetWindow._Position or TargetPosition
		RepositionNotificationStack(ActiveNotificationsList, CurrentTargetPosition)
	end)

	table.insert(ActiveNotificationsList, NotificationEntry)
	local CurrentTargetPosition = TargetWindow and TargetWindow._Position or TargetPosition
	RepositionNotificationStack(ActiveNotificationsList, CurrentTargetPosition)
end

-- Create a draggable window with pages, sections, elements, search, scrolling,
-- notifications, and adaptive viewport scaling.
function Library:CreateWindow(WindowConfiguration)
	WindowConfiguration = WindowConfiguration or {}
	WindowConfiguration.Title = WindowConfiguration.Title or "Window"
	WindowConfiguration.Position = WindowConfiguration.Position or Vector2.new(100, 100)

	local WindowTrackedDrawings = {}
	local GetTextBounds

	local DestroyAllTrackedDrawings = function()
		DestroyTrackedDrawingTable(WindowTrackedDrawings)
	end

	local CreateTrackedDrawingObject, CreateRectangleDrawing, CreateTextDrawing = MakeDrawingFactory(WindowTrackedDrawings)

	local TouchInputAvailable = Library:IsTouchInputAvailable()

	if TouchInputAvailable then
		local MobileTheme = {}
		for ThemePropertyName, ThemePropertyValue in pairs(Theme) do
			MobileTheme[ThemePropertyName] = ThemePropertyValue
		end

		-- Touch controls need a larger unscaled target than desktop controls. The
		-- viewport pass below performs the final proportional scaling and clamps
		-- the complete window to the currently visible phone or tablet area.
		MobileTheme.Font = 0
		MobileTheme.FontCharWidthRatio = 0.5
		MobileTheme.TitleFontSize = 19
		MobileTheme.HeaderSecondaryFontSize = 10
		MobileTheme.SectionFontSize = 15
		MobileTheme.SectionMetaFontSize = 10
		MobileTheme.ElementFontSize = 14
		MobileTheme.WindowWidth = 640
		MobileTheme.WindowVisibleHeight = 560
		MobileTheme.ElementHeight = 40
		MobileTheme.TitleBarHeight = 48
		MobileTheme.ElementPadding = 8
		MobileTheme.SectionPadding = 10
		MobileTheme.InnerMargin = 12
		MobileTheme.ScrollbarWidth = 8
		MobileTheme.WindowCornerRadius = 12
		MobileTheme.ControlCornerRadius = 10
		MobileTheme.CompactCornerRadius = 8
		MobileTheme.Base = nil
		Theme = MobileTheme
		Library.Theme = Theme
	end

	if not Theme.Base then
		Theme.Base = {
			TitleFontSize = Theme.TitleFontSize,
			HeaderSecondaryFontSize = Theme.HeaderSecondaryFontSize,
			SectionFontSize = Theme.SectionFontSize,
			SectionMetaFontSize = Theme.SectionMetaFontSize,
			ElementFontSize = Theme.ElementFontSize,
			WindowWidth = Theme.WindowWidth,
			TitleBarHeight = Theme.TitleBarHeight,
			WindowVisibleHeight = Theme.WindowVisibleHeight,
			ElementHeight = Theme.ElementHeight,
			ElementPadding = Theme.ElementPadding,
			SectionPadding = Theme.SectionPadding,
			InnerMargin = Theme.InnerMargin,
			ScrollbarWidth = Theme.ScrollbarWidth,
			SliderTrackHeight = Theme.SliderTrackHeight,
			SliderTrackHoverHeight = Theme.SliderTrackHoverHeight,
			SliderThumbRadius = Theme.SliderThumbRadius,
			SliderThumbHoverRadius = Theme.SliderThumbHoverRadius,
			ToggleIndicatorRadius = Theme.ToggleIndicatorRadius,
			ColorSwatchSize = Theme.ColorSwatchSize,
			ColorSwatchGap = Theme.ColorSwatchGap,
			TooltipWidth = Theme.TooltipWidth,
			TooltipPadding = Theme.TooltipPadding,
		}
	end

	local Window = {}
	Window._Connections = {}
	Window._ActiveNotifications = {}
	-- Interface construction can add more than one hundred elements before the
	-- first frame is presented. Defer intermediate layout passes while a caller
	-- builds that element tree, then perform one complete pass at the end.
	Window._LayoutBatchDepth = 0
	Window._LayoutRecalculationPending = false
	Window._HasCompletedLayout = false
	Window._Destroyed = false
	Window._Destroying = false
	Window._TouchInputAvailable = TouchInputAvailable
	Window._UseSingleColumnLayout = false
	Window._TouchLayoutWasPortrait = nil
	Window._ViewportScaleInitialized = false
	Window._CurrentViewportScale = 1
	Window._HasAppliedDeviceGeometry = false
	Window._LastPointerPosition = nil
	Window._InitialResponsiveBaseGeometry = {
		WindowWidth = Theme.Base.WindowWidth,
		WindowVisibleHeight = Theme.Base.WindowVisibleHeight,
	}
	Window._TouchInteractionState = {
		ActiveInputObject = nil,
		StartPosition = nil,
		PreviousPosition = nil,
		CurrentPosition = nil,
		CoordinateInset = nil,
		StartWindowPosition = nil,
		StartWindowSize = nil,
		GestureDistance = 0,
		Scrolling = false,
		ScrollTarget = nil,
	}

	Window._Position, Window._Title, Window._Description =
		WindowConfiguration.Position,
		WindowConfiguration.Title,
		tostring(WindowConfiguration.Description or WindowConfiguration.Subtitle or "")
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
	Window._ActiveTextSelectionBox = nil

	Window._Pages = {}
	Window._ActivePageIndex = 1
	Window._TabBarHeight = 40
	Window._TabDrawings = {}
	Window._TabScrollOffset = 0

	function Window:SetDescription(DescriptionText)
		Window._Description = tostring(DescriptionText or "")
		return Window
	end

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

	function Window:GetHeaderMetaText()
		local PageCount = #Window._Pages
		if PageCount == 0 then
			return "Page -- / --"
		end
		return string.format("Page %02d / %02d", Window._ActivePageIndex, PageCount)
	end


	local function NormalizeExecutorFunctionRequirements(Requirements)
		-- A descriptor preserves the requested function name even when the
		-- function value is nil. This is more reliable than a name-to-function
		-- dictionary because Lua omits dictionary entries whose values are nil.
		local NormalizedRequirements = {}

		local function AppendRequirement(RequirementName, RequirementFunction)
			local NormalizedName = tostring(RequirementName or "")
			if NormalizedName == "" then
				return
			end

			NormalizedRequirements[#NormalizedRequirements + 1] = {
				Name = NormalizedName,
				Function = RequirementFunction,
			}
		end

		if typeof(Requirements) ~= "table" then
			return NormalizedRequirements
		end

		if Requirements.Name ~= nil then
			AppendRequirement(
				Requirements.Name,
				rawget(Requirements, "Function") or rawget(Requirements, "Value")
			)
			return NormalizedRequirements
		end

		local ArrayRequirementCount = #Requirements
		for RequirementIndex = 1, ArrayRequirementCount do
			local Requirement = Requirements[RequirementIndex]
			if typeof(Requirement) == "string" then
				AppendRequirement(Requirement, nil)
			elseif typeof(Requirement) == "table" then
				AppendRequirement(
					Requirement.Name or Requirement[1],
					rawget(Requirement, "Function") or rawget(Requirement, "Value") or Requirement[2]
				)
			end
		end

		-- Name-to-function dictionaries remain supported for functions that are
		-- present. Missing functions should use descriptors so their names are
		-- not discarded by Lua before this normalization pass.
		for RequirementName, RequirementFunction in pairs(Requirements) do
			if typeof(RequirementName) == "string" and RequirementName ~= "Name" then
				AppendRequirement(RequirementName, RequirementFunction)
			end
		end

		return NormalizedRequirements
	end

	local function EnsureExecutorLockDrawingObjects(Element)
		if Element._ExecutorLockDrawingObjects
			or UseImmediateMode
			or not DrawingBackendAvailable then
			return
		end

		local LockBackgroundDrawing = CreateRectangleDrawing(
			Theme.LockedControlBackground,
			true,
			44,
			0.98
		)
		local LockBorderDrawing = CreateRectangleDrawing(
			Theme.LockedControlBorder,
			false,
			45,
			0.95
		)
		local LockIconCircleDrawing = CreateTrackedDrawingObject("Circle")
		ApplyDrawingProperties(LockIconCircleDrawing, {
			Filled = false,
			Radius = 8,
			NumSides = 64,
			Thickness = 2,
			Transparency = 1,
			Color = Theme.LockedControlIcon,
			ZIndex = 46,
			Visible = false,
		})
		local LockIconSlashDrawing = CreateTrackedDrawingObject("Line")
		ApplyDrawingProperties(LockIconSlashDrawing, {
			Thickness = 2,
			Transparency = 1,
			Color = Theme.LockedControlIcon,
			ZIndex = 47,
			Visible = false,
		})
		local LockTextDrawing = CreateTextDrawing(
			"",
			Theme.ElementFontSize,
			Theme.LockedControlText,
			47
		)

		Element._ExecutorLockDrawingObjects = {
			LockBackgroundDrawing,
			LockBorderDrawing,
			LockIconCircleDrawing,
			LockIconSlashDrawing,
			LockTextDrawing,
		}
		Element._ExecutorLockBackgroundDrawing = LockBackgroundDrawing
		Element._ExecutorLockBorderDrawing = LockBorderDrawing
		Element._ExecutorLockIconCircleDrawing = LockIconCircleDrawing
		Element._ExecutorLockIconSlashDrawing = LockIconSlashDrawing
		Element._ExecutorLockTextDrawing = LockTextDrawing
		SetDrawingObjectsVisibility(Element._ExecutorLockDrawingObjects, false)
	end

	local function RefreshExecutorRequirementTooltip(Element)
		local BaseTooltip = tostring(Element._BaseTooltip or "")
		if Element._IsLocked then
			local LockExplanation = tostring(
				Element._ExecutorLockMessage
				or "This control is unavailable on the current executor."
			)
			Element._Tooltip = BaseTooltip ~= ""
				and string.format("%s\n\n%s", BaseTooltip, LockExplanation)
				or LockExplanation
		else
			Element._Tooltip = BaseTooltip
		end
		Element._TooltipHoverStartedAt = nil
	end

	local function ConfigureElementExecutorRequirements(Element, ElementConfiguration)
		Element._RequiredExecutorFunctions = {}
		Element._MissingExecutorFunctionNames = {}
		Element._IsLocked = false
		Element._BaseTooltip = tostring(Element._Tooltip or "")

		local OriginalSetTooltip = Element.SetTooltip
		function Element:SetTooltip(NewTooltip)
			Element._BaseTooltip = tostring(NewTooltip or "")
			if OriginalSetTooltip then
				OriginalSetTooltip(Element, Element._BaseTooltip)
			end
			RefreshExecutorRequirementTooltip(Element)
		end

		function Element:GetMissingExecutorFunctionNames()
			local MissingFunctionNames = {}
			for MissingFunctionIndex, MissingFunctionName in ipairs(Element._MissingExecutorFunctionNames) do
				MissingFunctionNames[MissingFunctionIndex] = MissingFunctionName
			end
			return MissingFunctionNames
		end

		function Element:IsLocked()
			return Element._IsLocked == true
		end

		function Element:SetRequiredExecutorFunctions(NewRequirements, SuppressLayout)
			Element._RequiredExecutorFunctions = NormalizeExecutorFunctionRequirements(NewRequirements)
			local MissingFunctionNames = {}

			for RequirementIndex, Requirement in ipairs(Element._RequiredExecutorFunctions) do
				if not IsNativeExecutorFunction(Requirement.Function) then
					MissingFunctionNames[#MissingFunctionNames + 1] = Requirement.Name
				end
			end

			table.sort(MissingFunctionNames)
			Element._MissingExecutorFunctionNames = MissingFunctionNames
			Element._IsLocked = #MissingFunctionNames > 0

			if Element._IsLocked then
				local MissingFunctionList = table.concat(MissingFunctionNames, ", ")
				Element._ExecutorLockMessage = string.format(
					"Executor does not support the required function%s: %s.",
					#MissingFunctionNames == 1 and "" or "s",
					MissingFunctionList
				)
				Element._ExecutorLockDisplayText = string.format(
					"Executor does not support: %s",
					MissingFunctionList
				)
				EnsureExecutorLockDrawingObjects(Element)

				-- Locking an already active control also closes any transient
				-- interaction state so an inaccessible callback cannot remain
				-- reachable through a previously opened popup or text focus.
				if Element._Expanded then
					Element._Expanded = false
					Element._OptionsRegion = nil
					if Window._ActiveDropdown == Element then
						Window._ActiveDropdown = nil
					end
					for ItemIndex, ItemData in ipairs(Element._ItemDrawingObjects or {}) do
						SetDrawingObjectsVisibility({
							ItemData.BackgroundDrawing,
							ItemData.TextDrawing,
							ItemData.SeparatorDrawing,
						}, false)
					end
				end

				if Element._IsFocused then
					Element._IsFocused = false
					Element._IsSelected = false
					Element._SelectionDragging = false
				end

				if Window._ActiveColorPicker == Element and Element.ClosePopup then
					Element:ClosePopup()
				end
			else
				Element._ExecutorLockMessage = nil
				Element._ExecutorLockDisplayText = nil
				if Element._ExecutorLockDrawingObjects then
					SetDrawingObjectsVisibility(Element._ExecutorLockDrawingObjects, false)
				end
			end

			RefreshExecutorRequirementTooltip(Element)

			if not SuppressLayout then
				Window:RecalculateLayout()
			end
		end

		Element:SetRequiredExecutorFunctions(
			ElementConfiguration and ElementConfiguration.RequiredExecutorFunctions,
			true
		)
	end

	local function UpdateRetainedExecutorLock(
		Element,
		ElementAbsolutePosition,
		ElementAbsoluteSize,
		IsElementVisible,
		Section
	)
		local LockDrawingObjects = Element._ExecutorLockDrawingObjects
		if not LockDrawingObjects then
			return
		end

		local ShouldRenderLock = Element._IsLocked and IsElementVisible and Window._Visible
		if not ShouldRenderLock then
			SetDrawingObjectsVisibility(LockDrawingObjects, false)
			return
		end

		local AllowedMinimumPositionY, AllowedMaximumPositionY = GetSectionAllowedYRange(
			Section,
			Window,
			Window._Position.Y
		)
		local ClippedLockPosition, ClippedLockSize = ClipRectangleToYRange(
			ElementAbsolutePosition,
			ElementAbsoluteSize,
			AllowedMinimumPositionY,
			AllowedMaximumPositionY
		)
		if not ClippedLockPosition or not ClippedLockSize then
			SetDrawingObjectsVisibility(LockDrawingObjects, false)
			return
		end

		ApplyDrawingProperties(Element._ExecutorLockBackgroundDrawing, {
			Position = ClippedLockPosition,
			Size = ClippedLockSize,
			Color = Theme.LockedControlBackground,
			Visible = true,
		})
		ApplyDrawingProperties(Element._ExecutorLockBorderDrawing, {
			Position = ClippedLockPosition,
			Size = ClippedLockSize,
			Color = Theme.LockedControlBorder,
			Visible = true,
		})

		local IconRadius = math.min(8, math.max(5, ClippedLockSize.Y * 0.25))
		local IconCenter = Vector2.new(
			ClippedLockPosition.X + 14,
			ClippedLockPosition.Y + ClippedLockSize.Y / 2
		)
		ApplyDrawingProperties(Element._ExecutorLockIconCircleDrawing, {
			Position = IconCenter,
			Radius = IconRadius,
			Color = Theme.LockedControlIcon,
			Visible = true,
		})
		ApplyDrawingProperties(Element._ExecutorLockIconSlashDrawing, {
			From = IconCenter - Vector2.new(IconRadius * 0.7, IconRadius * 0.7),
			To = IconCenter + Vector2.new(IconRadius * 0.7, IconRadius * 0.7),
			Color = Theme.LockedControlIcon,
			Visible = true,
		})

		local AvailableTextWidth = math.max(1, ClippedLockSize.X - 38)
		local MaximumCharacters = math.max(
			1,
			math.floor(AvailableTextWidth / GetEditableTextCharacterWidth(Theme.ElementFontSize))
		)
		local DisplayText = TruncateTextWithAsciiEllipsis(
			Element._ExecutorLockDisplayText or "Executor capability unavailable",
			MaximumCharacters
		)
		ApplyDrawingProperties(Element._ExecutorLockTextDrawing, {
			Text = DisplayText,
			Position = Vector2.new(
				ClippedLockPosition.X + 30,
				ClippedLockPosition.Y + (ClippedLockSize.Y - Theme.ElementFontSize) / 2
			),
			Size = Theme.ElementFontSize,
			Color = Theme.LockedControlText,
			Visible = true,
		})
	end

	local function DrawImmediateExecutorLock(
		Element,
		ElementPosition,
		ElementSize,
		AllowedMinimumPositionY,
		AllowedMaximumPositionY
	)
		if not Element._IsLocked then
			return
		end

		local ClippedLockPosition, ClippedLockSize = ClipRectangleToYRange(
			ElementPosition,
			ElementSize,
			AllowedMinimumPositionY,
			AllowedMaximumPositionY
		)
		if not ClippedLockPosition or not ClippedLockSize then
			return
		end

		DrawingImmediateFilledRectangle(
			ClippedLockPosition,
			ClippedLockSize,
			Theme.LockedControlBackground,
			0.98,
			0
		)
		DrawingImmediateRectangle(
			ClippedLockPosition,
			ClippedLockSize,
			Theme.LockedControlBorder,
			0.95,
			0,
			1
		)

		local IconRadius = math.min(8, math.max(5, ClippedLockSize.Y * 0.25))
		local IconCenter = Vector2.new(
			ClippedLockPosition.X + 14,
			ClippedLockPosition.Y + ClippedLockSize.Y / 2
		)
		DrawingImmediateCircle(
			IconCenter,
			IconRadius,
			Theme.LockedControlIcon,
			1,
			64,
			2
		)
		DrawingImmediateLine(
			IconCenter - Vector2.new(IconRadius * 0.7, IconRadius * 0.7),
			IconCenter + Vector2.new(IconRadius * 0.7, IconRadius * 0.7),
			Theme.LockedControlIcon,
			1,
			2
		)

		local AvailableTextWidth = math.max(1, ClippedLockSize.X - 38)
		local MaximumCharacters = math.max(
			1,
			math.floor(AvailableTextWidth / GetEditableTextCharacterWidth(Theme.ElementFontSize))
		)
		local DisplayText = TruncateTextWithAsciiEllipsis(
			Element._ExecutorLockDisplayText or "Executor capability unavailable",
			MaximumCharacters
		)
		DrawingImmediateText(
			Vector2.new(
				ClippedLockPosition.X + 30,
				ClippedLockPosition.Y + (ClippedLockSize.Y - Theme.ElementFontSize) / 2
			),
			Theme.Font,
			Theme.ElementFontSize,
			Theme.LockedControlText,
			1,
			DisplayText,
			false
		)
	end

	Window.OnSave = function() end
	Window.OnExit = function() end

	local TitleBarBackgroundDrawing, TitleBarHighlightDrawing, TitleBarAccentWashDrawing,
		TitleBarBorderDrawing, TitleBarTextDrawing, TitleBarDescriptionDrawing,
		TitleBarMetaDrawing, TitleBarActionSeparatorDrawing,
		WindowBodyBackgroundDrawing, WindowBodyTopSheenDrawing,
		WindowBodyBottomShadeDrawing, WindowBodyBorderDrawing,
		TitleAccentCircleDrawing, TitleAccentOuterGlowCircleDrawing, WindowTopAccentDrawing,
		TitleBarSeparatorDrawing, CloseButtonBackgroundDrawing, CloseButtonBorderDrawing,
		CloseButtonTextDrawing, TouchLauncherBackgroundDrawing,
		TouchLauncherBorderDrawing, TouchLauncherTextDrawing

	if not UseImmediateMode and DrawingBackendAvailable then

		WindowBodyBackgroundDrawing = CreateRectangleDrawing(Theme.WindowBackground, true, 1, 0.97)
		ApplyDrawingProperties(WindowBodyBackgroundDrawing, {
			Position = Vector2.new(WindowConfiguration.Position.X, WindowConfiguration.Position.Y + Theme.TitleBarHeight),
			Size = Vector2.new(Theme.WindowWidth, 10),
		})

		WindowBodyTopSheenDrawing = CreateRectangleDrawing(Theme.WindowSurfaceHighlight, true, 2, 0.26)
		ApplyDrawingProperties(WindowBodyTopSheenDrawing, {
			Position = Vector2.new(WindowConfiguration.Position.X, WindowConfiguration.Position.Y + Theme.TitleBarHeight),
			Size = Vector2.new(Theme.WindowWidth, 44),
		})

		WindowBodyBottomShadeDrawing = CreateRectangleDrawing(Theme.WindowSurfaceShade, true, 2, 0.22)
		ApplyDrawingProperties(WindowBodyBottomShadeDrawing, {
			Position = Vector2.new(WindowConfiguration.Position.X, WindowConfiguration.Position.Y + Theme.TitleBarHeight),
			Size = Vector2.new(Theme.WindowWidth, 44),
		})

		WindowBodyBorderDrawing = CreateRectangleDrawing(Theme.WindowBorder, false, 2, 0.8)
		ApplyDrawingProperties(WindowBodyBorderDrawing, {
			Position = GetRenderProperty(WindowBodyBackgroundDrawing, "Position"),
			Size = GetRenderProperty(WindowBodyBackgroundDrawing, "Size"),
		})

		TitleBarBackgroundDrawing = CreateRectangleDrawing(Theme.TitleBarBackground, true, 3, 0.97)
		ApplyDrawingProperties(TitleBarBackgroundDrawing, {
			Position = WindowConfiguration.Position,
			Size = Vector2.new(Theme.WindowWidth, Theme.TitleBarHeight),
		})

		TitleBarHighlightDrawing = CreateRectangleDrawing(Theme.TitleBarHighlight, true, 4, 0.32)
		ApplyDrawingProperties(TitleBarHighlightDrawing, {
			Position = WindowConfiguration.Position,
			Size = Vector2.new(Theme.WindowWidth, math.max(6, Theme.TitleBarHeight * 0.45)),
		})

		TitleBarAccentWashDrawing = CreateRectangleDrawing(Theme.TitleBarAccentWash, true, 4, 0.34)
		ApplyDrawingProperties(TitleBarAccentWashDrawing, {
			Position = WindowConfiguration.Position,
			-- Keep one continuous title-bar color instead of ending the accent wash
			-- halfway across the header and exposing a different right side.
			Size = Vector2.new(Theme.WindowWidth, Theme.TitleBarHeight),
		})

		TitleBarBorderDrawing = CreateRectangleDrawing(Theme.WindowBorder, false, 4, 0.8)
		ApplyDrawingProperties(TitleBarBorderDrawing, {
			Position = WindowConfiguration.Position,
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
			NumSides = 48,
			Transparency = 1,
			Color = Theme.TitleBarSeparator,
			ZIndex = 6,
			Visible = true,
		})

		TitleAccentOuterGlowCircleDrawing = CreateTrackedDrawingObject("Circle")
		ApplyDrawingProperties(TitleAccentOuterGlowCircleDrawing, {
			Filled = false,
			Radius = 5,
			NumSides = 48,
			Transparency = 0.4,
			Color = Theme.TitleBarSeparator,
			Thickness = 1,
			ZIndex = 5,
			Visible = true,
		})

		TitleBarTextDrawing = CreateTextDrawing(WindowConfiguration.Title, Theme.TitleFontSize, Theme.TitleBarText, 6)
		TitleBarDescriptionDrawing = CreateTextDrawing(
			Window._Description,
			Theme.HeaderSecondaryFontSize,
			Theme.TextBoxPlaceholder,
			6
		)
		TitleBarMetaDrawing = CreateTextDrawing(
			Window:GetHeaderMetaText(),
			Theme.HeaderSecondaryFontSize,
			Theme.LabelText,
			6
		)
		TitleBarActionSeparatorDrawing = CreateTrackedDrawingObject("Line")
		ApplyDrawingProperties(TitleBarActionSeparatorDrawing, {
			Thickness = 1,
			Transparency = 0.45,
			Color = Theme.WindowBorder,
			ZIndex = 6,
			Visible = true,
		})

		CloseButtonBackgroundDrawing = CreateRectangleDrawing(Theme.CloseButtonBackground, true, 5, 0.9)
		CloseButtonBorderDrawing = CreateRectangleDrawing(Theme.CloseButtonBorder, false, 6, 0.9)
		CloseButtonTextDrawing = CreateTextDrawing("X", 13, Theme.TitleBarText, 7)
		ApplyDrawingProperties(CloseButtonTextDrawing, { Visible = true })

		if TouchInputAvailable then
			-- The launcher is intentionally excluded from Window._DrawingObjects. A
			-- normal hide operation can therefore conceal every window control while
			-- leaving this small, independently managed recovery control available.
			TouchLauncherBackgroundDrawing = CreateTrackedDrawingObject("Circle")
			ApplyDrawingProperties(TouchLauncherBackgroundDrawing, {
				Filled = true,
				Radius = 32,
				NumSides = 64,
				Transparency = 0.96,
				Color = Theme.TouchLauncherBackground,
				ZIndex = 120,
				Visible = false,
			})

			TouchLauncherBorderDrawing = CreateTrackedDrawingObject("Circle")
			ApplyDrawingProperties(TouchLauncherBorderDrawing, {
				Filled = false,
				Radius = 32,
				NumSides = 64,
				Thickness = 2,
				Transparency = 0.95,
				Color = Theme.TouchLauncherBorder,
				ZIndex = 121,
				Visible = false,
			})

			TouchLauncherTextDrawing = CreateTextDrawing("C", 20, Theme.TouchLauncherText, 122)
			ApplyDrawingProperties(TouchLauncherTextDrawing, { Visible = false })
		end

		WindowTopAccentDrawing = CreateTrackedDrawingObject("Line")
		ApplyDrawingProperties(WindowTopAccentDrawing, {
			Thickness = 1.5,
			Transparency = 0.95,
			Color = Theme.TitleBarSeparator,
			ZIndex = 5,
			Visible = true,
		})

		Window._TopShimmerDrawing = CreateTrackedDrawingObject("Line")
		ApplyDrawingProperties(Window._TopShimmerDrawing, {
			Thickness = 2,
			Transparency = 0.9,
			Color = Theme.AccentPrimary,
			ZIndex = 6,
			Visible = true,
		})

		-- The lower edge stays intentionally clean; status text is not rendered.

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
			NumSides = 48,
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
			NumSides = 48,
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

		Window._TooltipBackgroundDrawing = CreateRectangleDrawing(Theme.TooltipBackground, true, 60, 0.98)
		Window._TooltipBorderDrawing = CreateRectangleDrawing(Theme.TooltipBorder, false, 61, 0.9)
		Window._TooltipTextDrawings = {}
		for TooltipLineIndex = 1, Theme.TooltipMaximumLines do
			Window._TooltipTextDrawings[TooltipLineIndex] = CreateTextDrawing("", Theme.ElementFontSize, Theme.TooltipText, 62)
		end
		ApplyDrawingProperties(Window._TooltipBackgroundDrawing, { Visible = false })
		ApplyDrawingProperties(Window._TooltipBorderDrawing, { Visible = false })

		Window._DrawingObjects = {
			WindowBodyBackgroundDrawing, WindowBodyTopSheenDrawing, WindowBodyBottomShadeDrawing, WindowBodyBorderDrawing,
			TitleBarBackgroundDrawing, TitleBarHighlightDrawing, TitleBarAccentWashDrawing, TitleBarBorderDrawing,
			TitleBarTextDrawing, TitleBarDescriptionDrawing, TitleBarMetaDrawing, TitleBarActionSeparatorDrawing,
			TitleAccentCircleDrawing, TitleAccentOuterGlowCircleDrawing, TitleBarSeparatorDrawing,
			CloseButtonBackgroundDrawing, CloseButtonBorderDrawing, CloseButtonTextDrawing,
			WindowTopAccentDrawing,
		}
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
		table.insert(Window._DrawingObjects, Window._TooltipBackgroundDrawing)
		table.insert(Window._DrawingObjects, Window._TooltipBorderDrawing)
		
		for DiscardTextIndex, TextDrawingObject in ipairs(Window._SearchDropdownTextDrawings) do
			table.insert(Window._DrawingObjects, TextDrawingObject)
		end
		for DiscardTooltipTextIndex, TooltipTextDrawingObject in ipairs(Window._TooltipTextDrawings) do
			table.insert(Window._DrawingObjects, TooltipTextDrawingObject)
		end
	end

	function Window:GetCurrentPointerPosition()
		-- Touch input does not consistently update GetMouseLocation across
		-- executors. Preserve the latest touch coordinate so hit testing, retained
		-- rendering, and the immediate renderer all inspect the same position.
		if Window._TouchInputAvailable then
			local TouchInteractionState = Window._TouchInteractionState
			if TouchInteractionState and TouchInteractionState.CurrentPosition then
				return TouchInteractionState.CurrentPosition
			end
			if Window._LastPointerPosition then
				return Window._LastPointerPosition
			end
		end
		return GetMouseLocation(UserInputService)
	end

	function Window:GetTouchLauncherGeometry()
		local Camera = GetCurrentCamera()
		local ViewportSize = Camera and Camera.ViewportSize or Vector2.new(1920, 1080)
		local LauncherRadius = math.clamp(Theme.ElementHeight * 0.82, 28, 38)
		local LauncherMargin = math.max(8, math.floor(LauncherRadius * 0.28))
		local LauncherCenter

		-- TopbarInset is the live rectangle Roblox reserves as usable top-bar
		-- space after its own controls and device safe areas are accounted for.
		-- Anchoring to its leading edge keeps the recovery control beside Roblox's
		-- panel on phones and tablets without assuming a particular panel width.
		local TopbarInsetReadSucceeded, TopbarInset = pcall(function()
			return GraphicalUserInterfaceService.TopbarInset
		end)
		if TopbarInsetReadSucceeded and typeof(TopbarInset) == "Rect" and TopbarInset.Height > 0 then
			LauncherCenter = Vector2.new(
				TopbarInset.Min.X + LauncherMargin + LauncherRadius,
				TopbarInset.Min.Y + TopbarInset.Height / 2
			)
		else
			local TopLeftInset = GetTouchInputCoordinateInset()
			LauncherCenter = Vector2.new(
				TopLeftInset.X + LauncherMargin + LauncherRadius,
				math.max(LauncherMargin + LauncherRadius, TopLeftInset.Y / 2)
			)
		end

		LauncherCenter = Vector2.new(
			math.clamp(LauncherCenter.X, LauncherRadius + LauncherMargin, ViewportSize.X - LauncherRadius - LauncherMargin),
			math.clamp(LauncherCenter.Y, LauncherRadius + LauncherMargin, ViewportSize.Y - LauncherRadius - LauncherMargin)
		)
		return {
			Center = LauncherCenter,
			Radius = LauncherRadius,
			HitRadius = LauncherRadius + 12,
		}
	end

	function Window:ApplyTouchViewportGeometry(ViewportSize, ViewportScale, ShouldResetResponsiveBase)
		if not Window._TouchInputAvailable then
			return
		end

		local ViewportMargin = 16
		local PortraitLayout = ViewportSize.Y > ViewportSize.X
		local TouchOrientationChanged = Window._TouchLayoutWasPortrait ~= nil
			and Window._TouchLayoutWasPortrait ~= PortraitLayout
		Window._TouchLayoutWasPortrait = PortraitLayout
		Window._UseSingleColumnLayout = PortraitLayout or ViewportSize.X <= 760

		if (ShouldResetResponsiveBase or TouchOrientationChanged) and Window._InitialResponsiveBaseGeometry then
			-- Restore the original touch dimensions before recomputing the responsive
			-- profile. This gives configuration reset and orientation changes a real
			-- size reset even after a user persisted geometry for another layout.
			Theme.Base.WindowWidth = Window._InitialResponsiveBaseGeometry.WindowWidth
			Theme.Base.WindowVisibleHeight = Window._InitialResponsiveBaseGeometry.WindowVisibleHeight
			Theme.WindowWidth = Theme.Base.WindowWidth * ViewportScale
			Theme.WindowVisibleHeight = Theme.Base.WindowVisibleHeight * ViewportScale
			Window._HasAppliedDeviceGeometry = false
		end

		local MaximumWindowWidth = math.max(180, ViewportSize.X - ViewportMargin * 2)
		local MaximumVisibleBodyHeight = math.max(
			180,
			ViewportSize.Y - Theme.TitleBarHeight - ViewportMargin * 2
		)

		if not Window._HasAppliedDeviceGeometry then
			-- Landscape touch screens benefit from a compact centered tool window so
			-- Roblox controls remain reachable around it. Portrait screens receive a
			-- wider single-column surface while still preserving outside margins.
			local PreferredWidthFraction = PortraitLayout and 0.92 or 0.66
			local MaximumPreferredWidth = PortraitLayout and 820 or 880
			local MinimumPreferredWidth = math.min(PortraitLayout and 320 or 520, MaximumWindowWidth)
			local PreferredWindowWidth = math.min(
				MaximumPreferredWidth,
				ViewportSize.X * PreferredWidthFraction
			)
			Theme.WindowWidth = math.clamp(
				PreferredWindowWidth,
				MinimumPreferredWidth,
				MaximumWindowWidth
			)

			local PreferredBodyHeightFraction = PortraitLayout and 0.68 or 0.60
			local MaximumPreferredBodyHeight = PortraitLayout and 760 or 580
			local MinimumPreferredBodyHeight = math.min(PortraitLayout and 320 or 260, MaximumVisibleBodyHeight)
			local PreferredBodyHeight = math.min(
				MaximumPreferredBodyHeight,
				ViewportSize.Y * PreferredBodyHeightFraction
			)
			Theme.WindowVisibleHeight = math.clamp(
				PreferredBodyHeight,
				MinimumPreferredBodyHeight,
				MaximumVisibleBodyHeight
			)
		end

		Theme.WindowWidth = math.clamp(
			Theme.WindowWidth,
			math.min(300, MaximumWindowWidth),
			MaximumWindowWidth
		)
		Theme.WindowVisibleHeight = math.clamp(
			Theme.WindowVisibleHeight,
			math.min(240, MaximumVisibleBodyHeight),
			MaximumVisibleBodyHeight
		)
		Window._VisibleHeight = Theme.WindowVisibleHeight
	end

	function Window:IsPointInsideTouchLauncher(Point)
		if not Window._TouchInputAvailable or typeof(Point) ~= "Vector2" then
			return false
		end

		local LauncherGeometry = Window:GetTouchLauncherGeometry()
		return (Point - LauncherGeometry.Center).Magnitude <= LauncherGeometry.HitRadius
	end

	function Window:UpdateTouchLauncherDrawings()
		if UseImmediateMode or not Window._TouchInputAvailable then
			return
		end
		if not TouchLauncherBackgroundDrawing or not TouchLauncherBorderDrawing or not TouchLauncherTextDrawing then
			return
		end

		local LauncherShouldBeVisible = not Window._Destroyed
			and (not Window._Visible or not Library._Visible)
		local LauncherGeometry = Window:GetTouchLauncherGeometry()
		local LauncherTextSize = math.max(18, Theme.TitleFontSize)
		local LauncherTextBounds = GetTextBounds
			and GetTextBounds("C", LauncherTextSize)
			or Vector2.new(LauncherTextSize * 0.6, LauncherTextSize)

		ApplyDrawingProperties(TouchLauncherBackgroundDrawing, {
			Position = LauncherGeometry.Center,
			Radius = LauncherGeometry.Radius,
			Color = Theme.TouchLauncherBackground,
			Visible = LauncherShouldBeVisible,
		})
		ApplyDrawingProperties(TouchLauncherBorderDrawing, {
			Position = LauncherGeometry.Center,
			Radius = LauncherGeometry.Radius,
			Color = Theme.TouchLauncherBorder,
			Visible = LauncherShouldBeVisible,
		})
		ApplyDrawingProperties(TouchLauncherTextDrawing, {
			Position = LauncherGeometry.Center - LauncherTextBounds / 2,
			Size = LauncherTextSize,
			Color = Theme.TouchLauncherText,
			Visible = LauncherShouldBeVisible,
		})
	end

	Window._SearchActive = false
	Window._SearchResults = {}
	Window._HoveredSearchResultIndex = nil
	Window._HighlightedElement = nil
	Window._HoveredTooltipElement = nil
	Window._TooltipVisible = false
	Window._TooltipNeedsLayout = false
	Window._SearchTextBox = {
		_Type = "TextBox",
		_IsSearch = true,
		_Text = "",
		_Value = "",
		_IsFocused = false,
		_IsSelected = false,
		_CursorIndex = 1,
		_SelectionStartIndex = nil,
		_SelectionEndIndex = nil,
		_SelectionAnchorIndex = 1,
		_SelectionDragging = false,
		_CursorVisible = false,
		_CursorBlinkTime = 0,
		_Placeholder = string.format("Search elements%s", AsciiEllipsis),
		SetValue = NewCClosure(function(Self, NewValue)
			Self._Value = tostring(NewValue or "")
			Self._CursorIndex = ClampTextBoxCursorIndex(Self, Self._CursorIndex)
			if Window.SynchronizeNativeTextInputValue then
				Window:SynchronizeNativeTextInputValue(Self)
			end
			Window:PerformSearch()
		end)
	}

	-- Drawing text boxes cannot delegate text composition, clipboard operations,
	-- or platform keyboard behavior to Roblox by themselves. One transparent
	-- native TextBox therefore acts as the only input bridge for the complete
	-- window on desktop, tablet, and phone.
	Window._NativeTextInputState = {
		Available = false,
		Synchronizing = false,
		TargetElement = nil,
		ScreenGui = nil,
		TextBox = nil,
		CaptureFocus = nil,
		ReleaseFocus = nil,
	}

	do
		local NativeTextInputState = Window._NativeTextInputState
		local NativeTextInputScreenGui
		local NativeTextInputTextBox
		local NativeInputCreationSucceeded = pcall(function()
			NativeTextInputScreenGui = CloneReference(CreateInstance("ScreenGui"))
			NativeTextInputScreenGui.Name = RandomString(32)
			NativeTextInputScreenGui.DisplayOrder = 2147483647
			NativeTextInputScreenGui.IgnoreGuiInset = true
			NativeTextInputScreenGui.ResetOnSpawn = false
			NativeTextInputScreenGui.ZIndexBehavior = Enum.ZIndexBehavior.Global

			NativeTextInputTextBox = CloneReference(CreateInstance("TextBox"))
			NativeTextInputTextBox.Name = RandomString(32)
			NativeTextInputTextBox.Active = true
			NativeTextInputTextBox.BackgroundTransparency = 1
			NativeTextInputTextBox.BorderSizePixel = 0
			NativeTextInputTextBox.ClearTextOnFocus = false
			NativeTextInputTextBox.MultiLine = false
			NativeTextInputTextBox.Position = UDim2.new(0, 0, 0, 0)
			NativeTextInputTextBox.Size = UDim2.new(0, 1, 0, 1)
			NativeTextInputTextBox.Text = ""
			NativeTextInputTextBox.TextEditable = true
			NativeTextInputTextBox.TextTransparency = 1
			NativeTextInputTextBox.Visible = true
			-- The bridge is fully transparent, so it does not require an extreme
			-- rendering layer. A conservative value remains compatible with Roblox
			-- clients that still validate GuiObject.ZIndex against a narrow range.
			NativeTextInputTextBox.ZIndex = 10
			pcall(function()
				NativeTextInputTextBox.ShowNativeInput = true
			end)
			NativeTextInputTextBox.Parent = NativeTextInputScreenGui
			NativeTextInputScreenGui.Parent = CoreGui
		end)

		if NativeInputCreationSucceeded and NativeTextInputScreenGui and NativeTextInputTextBox then
			NativeTextInputState.Available = true
			NativeTextInputState.ScreenGui = NativeTextInputScreenGui
			NativeTextInputState.TextBox = NativeTextInputTextBox
			NativeTextInputState.CaptureFocus = CloneFunction(NativeTextInputTextBox.CaptureFocus)
			NativeTextInputState.ReleaseFocus = CloneFunction(NativeTextInputTextBox.ReleaseFocus)

			local function ConnectNativeTextInputSignal(TargetSignal, CallbackFunction)
				-- Reuse the library-wide cloned RBXScriptSignal connection method so
				-- every native bridge signal follows the same trusted call path.
				return ConnectSignal(TargetSignal, NewCClosure(CallbackFunction))
			end

			local function SynchronizeDrawingSelectionFromNative()
				-- CursorPosition is the active end of a native Roblox selection,
				-- while SelectionStart is its anchor. The Drawing presentation uses
				-- the same one-based, half-open positions, so no character-index
				-- conversion is necessary.
				if NativeTextInputState.Synchronizing then
					return
				end

				local TargetElement = NativeTextInputState.TargetElement
				if not TargetElement or Window._Destroyed then
					return
				end

				local NativeCursorPosition = tonumber(NativeTextInputTextBox.CursorPosition)
				local NativeSelectionStart = tonumber(NativeTextInputTextBox.SelectionStart)
				if not NativeCursorPosition or NativeCursorPosition < 1 then
					return
				end

				if NativeSelectionStart and NativeSelectionStart >= 1
					and NativeSelectionStart ~= NativeCursorPosition then
					SetTextBoxSelectionRange(TargetElement, NativeSelectionStart, NativeCursorPosition)
					TargetElement._SelectionAnchorIndex = NativeSelectionStart
				else
					SetTextBoxCursorIndex(TargetElement, NativeCursorPosition)
					ClearTextBoxSelection(TargetElement)
				end

				TargetElement._CursorVisible = true
				TargetElement._CursorBlinkTime = tick()
			end

			local NativeTextChangedSignal = GetPropertyChangedSignal(
				NativeTextInputTextBox,
				"Text"
			)
			local NativeTextChangedConnection = ConnectNativeTextInputSignal(NativeTextChangedSignal, function()
				if NativeTextInputState.Synchronizing then
					return
				end

				local TargetElement = NativeTextInputState.TargetElement
				if not TargetElement or Window._Destroyed then
					return
				end

				local UpdatedText = tostring(NativeTextInputTextBox.Text or "")
				NativeTextInputState.Synchronizing = true
				TargetElement:SetValue(UpdatedText)
				NativeTextInputState.Synchronizing = false
				SynchronizeDrawingSelectionFromNative()
				Window:RecalculateLayout()
			end)
			table.insert(Window._Connections, NativeTextChangedConnection)

			local NativeCursorChangedSignal = GetPropertyChangedSignal(
				NativeTextInputTextBox,
				"CursorPosition"
			)
			local NativeCursorChangedConnection = ConnectNativeTextInputSignal(
				NativeCursorChangedSignal,
				SynchronizeDrawingSelectionFromNative
			)
			table.insert(Window._Connections, NativeCursorChangedConnection)

			local NativeSelectionChangedSignal = GetPropertyChangedSignal(
				NativeTextInputTextBox,
				"SelectionStart"
			)
			local NativeSelectionChangedConnection = ConnectNativeTextInputSignal(
				NativeSelectionChangedSignal,
				SynchronizeDrawingSelectionFromNative
			)
			table.insert(Window._Connections, NativeSelectionChangedConnection)

			local NativeFocusLostSignal = NativeTextInputTextBox.FocusLost
			local NativeFocusLostConnection = ConnectNativeTextInputSignal(NativeFocusLostSignal, function(EnterPressed)
				local TargetElement = NativeTextInputState.TargetElement
				if EnterPressed
					and TargetElement
					and TargetElement._KeyboardSuggestionIndex
					and typeof(TargetElement.ApplySuggestion) == "function" then
					TargetElement:ApplySuggestion(TargetElement._KeyboardSuggestionIndex)
				end

				NativeTextInputState.TargetElement = nil
				if TargetElement then
					TargetElement._IsFocused = false
					TargetElement._CursorVisible = false
					TargetElement._SelectionDragging = false
					ClearTextBoxSelection(TargetElement)
				end
				Window._ActiveTextSelectionBox = nil
				if not Window._Destroyed and not Window._Destroying then
					Window:RecalculateLayout()
				end
			end)
			table.insert(Window._Connections, NativeFocusLostConnection)

			-- ReturnPressedFromOnScreenKeyboard is available on current clients, but
			-- several executor object bridges omit the signal. Keep the ordinary
			-- FocusLost path functional when that optional signal cannot be observed.
			local NativeReturnConnectionCreationSucceeded, NativeReturnConnection = pcall(function()
				local NativeReturnPressedSignal = NativeTextInputTextBox.ReturnPressedFromOnScreenKeyboard
				return ConnectNativeTextInputSignal(NativeReturnPressedSignal, function()
					if NativeTextInputState.TargetElement then
						pcall(NativeTextInputState.ReleaseFocus, NativeTextInputTextBox, true)
					end
				end)
			end)
			if NativeReturnConnectionCreationSucceeded and NativeReturnConnection then
				table.insert(Window._Connections, NativeReturnConnection)
			end
		else
			-- Creation can fail after either object has already been allocated.
			-- Destroy both references independently so an unparented TextBox cannot
			-- survive as an unreachable native input target.
			if NativeTextInputTextBox then
				pcall(DestroyInstance, NativeTextInputTextBox)
			end
			if NativeTextInputScreenGui then
				pcall(DestroyInstance, NativeTextInputScreenGui)
			end
		end
	end

	function Window:SynchronizeNativeTextInputValue(TargetElement)
		-- Programmatic changes, including accepted autocomplete suggestions, must
		-- update the native editor while it owns focus. The guard prevents the
		-- native Text signal from feeding the same value back into the Drawing
		-- element recursively.
		local NativeTextInputState = Window._NativeTextInputState
		if not NativeTextInputState
			or not NativeTextInputState.Available
			or NativeTextInputState.Synchronizing
			or NativeTextInputState.TargetElement ~= TargetElement then
			return false
		end

		local NativeTextInputTextBox = NativeTextInputState.TextBox
		local NormalizedValue = tostring(TargetElement._Value or "")
		NativeTextInputState.Synchronizing = true
		if NativeTextInputTextBox.Text ~= NormalizedValue then
			NativeTextInputTextBox.Text = NormalizedValue
		end
		NativeTextInputState.Synchronizing = false
		return true
	end

	function Window:SynchronizeNativeTextInputSelection(TargetElement)
		-- Mouse selection is calculated against Drawing text geometry. Mirror its
		-- anchor and active cursor into the native TextBox so subsequent typing,
		-- copying, and deletion operate on exactly the highlighted characters.
		local NativeTextInputState = Window._NativeTextInputState
		if not NativeTextInputState
			or not NativeTextInputState.Available
			or NativeTextInputState.TargetElement ~= TargetElement then
			return false
		end

		local NativeTextInputTextBox = NativeTextInputState.TextBox
		local NativeCursorPosition = ClampTextBoxCursorIndex(TargetElement, TargetElement._CursorIndex)
		local NativeSelectionStart = -1
		if TargetElement._IsSelected then
			NativeSelectionStart = ClampTextBoxCursorIndex(
				TargetElement,
				TargetElement._SelectionAnchorIndex or TargetElement._SelectionStartIndex
			)
		end

		NativeTextInputState.Synchronizing = true
		NativeTextInputTextBox.CursorPosition = NativeCursorPosition
		NativeTextInputTextBox.SelectionStart = NativeSelectionStart
		NativeTextInputState.Synchronizing = false
		return true
	end

	function Window:FocusNativeTextInput(TargetElement)
		local NativeTextInputState = Window._NativeTextInputState
		if not NativeTextInputState
			or not NativeTextInputState.Available
			or not TargetElement then
			return false
		end

		local NativeTextInputTextBox = NativeTextInputState.TextBox
		NativeTextInputState.TargetElement = TargetElement
		NativeTextInputState.Synchronizing = true
		NativeTextInputTextBox.Text = tostring(TargetElement._Value or "")
		NativeTextInputTextBox.PlaceholderText = tostring(TargetElement._Placeholder or "")
		NativeTextInputTextBox.CursorPosition = ClampTextBoxCursorIndex(TargetElement, TargetElement._CursorIndex)
		if TargetElement._IsSelected then
			NativeTextInputTextBox.SelectionStart = ClampTextBoxCursorIndex(
				TargetElement,
				TargetElement._SelectionAnchorIndex or TargetElement._SelectionStartIndex
			)
		else
			NativeTextInputTextBox.SelectionStart = -1
		end
		NativeTextInputState.Synchronizing = false

		-- CaptureFocus is deferred until the pointer callback finishes. Roblox can
		-- otherwise discard a focus request made inside the same mouse or touch
		-- event that selected the Drawing control.
		task.defer(function()
			if not Window._Destroyed
				and Window._Visible
				and NativeTextInputState.TargetElement == TargetElement then
				local FocusCaptureSucceeded = pcall(
					NativeTextInputState.CaptureFocus,
					NativeTextInputTextBox
				)
				if not FocusCaptureSucceeded then
					-- There is intentionally no manual keyboard editor. If the
					-- executor cannot focus Roblox's native TextBox, return the
					-- Drawing control to an honest unfocused state.
					NativeTextInputState.TargetElement = nil
					TargetElement._IsFocused = false
					TargetElement._CursorVisible = false
					TargetElement._SelectionDragging = false
					ClearTextBoxSelection(TargetElement)
					Window._ActiveTextSelectionBox = nil
					Window:RecalculateLayout()
				end
			end
		end)
		return true
	end

	function Window:ReleaseNativeTextInput(TargetElement)
		local NativeTextInputState = Window._NativeTextInputState
		if not NativeTextInputState or not NativeTextInputState.Available then
			return
		end
		if TargetElement and NativeTextInputState.TargetElement ~= TargetElement then
			return
		end

		local CurrentTargetElement = NativeTextInputState.TargetElement
		NativeTextInputState.TargetElement = nil
		pcall(NativeTextInputState.ReleaseFocus, NativeTextInputState.TextBox, false)
		if CurrentTargetElement then
			CurrentTargetElement._IsFocused = false
			CurrentTargetElement._CursorVisible = false
			CurrentTargetElement._SelectionDragging = false
			ClearTextBoxSelection(CurrentTargetElement)
		end
		Window._ActiveTextSelectionBox = nil
	end

	function Window:DestroyNativeTextInput()
		local NativeTextInputState = Window._NativeTextInputState
		if not NativeTextInputState then
			return
		end

		Window:ReleaseNativeTextInput()
		if NativeTextInputState.ScreenGui then
			pcall(DestroyInstance, NativeTextInputState.ScreenGui)
		end
		NativeTextInputState.Available = false
		NativeTextInputState.ScreenGui = nil
		NativeTextInputState.TextBox = nil
	end

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
					-- Search result rows have a fixed height, so embedded line
					-- breaks from information labels must be collapsed before the
					-- result is painted. Otherwise one match can draw through the
					-- following rows and make the complete overlay unreadable.
					local SingleLineMatchText = tostring(MatchText)
						:gsub("%s+", " ")
						:gsub("^%s+", "")
						:gsub("%s+$", "")
					table.insert(Window._SearchResults, {
						Section = Section,
						Element = Element,
						Text = string.format("[%s] > %s", Section._Title, SingleLineMatchText)
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

	function Window:BeginLayoutBatch()
		if Window._Destroyed then
			return
		end

		if Window._LayoutBatchDepth == 0 then
			-- Input and animation processing must not inspect sections while their
			-- coordinates are intentionally deferred by the construction batch.
			Window._HasCompletedLayout = false
		end
		Window._LayoutBatchDepth = Window._LayoutBatchDepth + 1
	end

	function Window:EndLayoutBatch()
		if Window._LayoutBatchDepth <= 0 then
			return
		end

		Window._LayoutBatchDepth = Window._LayoutBatchDepth - 1
		if Window._LayoutBatchDepth == 0 and Window._LayoutRecalculationPending then
			Window._LayoutRecalculationPending = false
			Window:RecalculateLayout()
		elseif Window._LayoutBatchDepth == 0 then
			Window._HasCompletedLayout = true
		end
	end

	function Window:RecalculateLayout()
		-- Any number of element setters may request layout while a construction
		-- batch is active. Remember only that a pass is needed; repeated requests
		-- intentionally collapse into one final recalculation.
		if Window._LayoutBatchDepth > 0 then
			Window._LayoutRecalculationPending = true
			return
		end

		Window._LayoutRecalculationPending = false
		RepositionNotificationStack(Window._ActiveNotifications, Window._Position)
		if not DrawingBackendAvailable then
			Window._HasCompletedLayout = true
			return
		end

		local WindowPosition = Window._Position
		local ViewportStart, ViewportEnd = GetWindowContentViewportYRange(Window, WindowPosition.Y)
		local LayoutRequiresScrollbarCorrection = false

		local SearchBarHeightOffset = 0
		if Window._SearchActive then
			SearchBarHeightOffset = 32
		end

		-- Only portrait touch layouts collapse to one column. Desktop windows retain
		-- the dense two-column information layout at every permitted resize width,
		-- matching Contact's original scan-friendly composition.
		local UseSingleColumnLayout = Window._UseSingleColumnLayout == true
		local ColumnWidth = UseSingleColumnLayout
			and (Theme.WindowWidth - Theme.InnerMargin * 2)
			or ((Theme.WindowWidth - Theme.InnerMargin * 3) / 2)
		local ColumnOnePositionY = Theme.SectionPadding + SearchBarHeightOffset
		local ColumnTwoPositionY = Theme.SectionPadding + SearchBarHeightOffset

		
		if not UseImmediateMode and #Window._Pages > 0 then
			for DiscardSectionIndex, SectionObject in ipairs(Window._Sections) do
				if SectionObject._PageIndex and SectionObject._PageIndex ~= Window._ActivePageIndex then
					local VisibilityObjects = {
						SectionObject._FullBackground, SectionObject._Background, SectionObject._Border,
						SectionObject._TextLabel, SectionObject._IndexTextLabel,
						SectionObject._AccentLine, SectionObject._LeftAccentLine,
					}
					SetDrawingObjectsVisibility(VisibilityObjects, false)
					for DiscardElementIndex, Element in ipairs(SectionObject._Elements) do
						if Element._Type == "TextLabel" then
							SetDrawingObjectsVisibility({ Element._AccentLineDrawing }, false)
							for DiscardLineDrawingIndex, LineDrawingObject in ipairs(Element._LineDrawings or {}) do
								SetRenderProperty(LineDrawingObject, "Visible", false)
							end
							Theme:HideInlineVisualDrawings(Element)
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
							if Element._SuggestionBackgroundDrawing then SetRenderProperty(Element._SuggestionBackgroundDrawing, "Visible", false) end
							if Element._SuggestionBorderDrawing then SetRenderProperty(Element._SuggestionBorderDrawing, "Visible", false) end
							for SuggestionRowIndex, SuggestionRow in ipairs(Element._SuggestionRows or {}) do
								SetDrawingObjectsVisibility({ SuggestionRow.HoverDrawing, SuggestionRow.TextDrawing }, false)
							end
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
								Element._TrackFillDrawing, Element._ThumbDrawing,
							}, false)
						elseif Element._Type == "ColorPicker" then
							SetDrawingObjectsVisibility({ Element._LabelDrawing, Element._SwatchDrawing, Element._SwatchBorderDrawing }, false)
							if Element._HoverBackgroundDrawing then SetRenderProperty(Element._HoverBackgroundDrawing, "Visible", false) end
							if Element._AccentLineDrawing then SetRenderProperty(Element._AccentLineDrawing, "Visible", false) end
							if Element._ChevronDrawing then SetRenderProperty(Element._ChevronDrawing, "Visible", false) end
						end
						if Element._ExecutorLockDrawingObjects then
							SetDrawingObjectsVisibility(Element._ExecutorLockDrawingObjects, false)
						end
					end
				end
			end
		end

		for SectionIndex, Section in ipairs(Window:GetActiveSections()) do

			local IsColumnOne = UseSingleColumnLayout or (ColumnOnePositionY <= ColumnTwoPositionY)
			local CurrentX = (IsColumnOne and Theme.InnerMargin or (Theme.InnerMargin * 2 + ColumnWidth))
			local CurrentY = Theme.TitleBarHeight + Window._TabBarHeight + (IsColumnOne and ColumnOnePositionY or ColumnTwoPositionY)

			Section._PositionX = CurrentX
			Section._PositionY = CurrentY
			Section._Width = ColumnWidth

			local SectionScrollOffset = Section._SectionScrollOffset or 0
			local SectionContentHeight = Theme.ElementHeight + Theme.ElementPadding

			-- Estimate the effective section limit before laying out elements so
			-- element widths can reserve room for a section-local scrollbar on the
			-- first pass after a resize. This limit intentionally ignores the
			-- remaining on-screen height; the main window scroll handles sections
			-- that are positioned below the current viewport.
			local EstimatedEffectiveMaxHeight = Section._MaxHeight

			local HasScrollbar = EstimatedEffectiveMaxHeight and Section._FullContentHeight and Section._FullContentHeight > EstimatedEffectiveMaxHeight
			for ElementIndex, Element in ipairs(Section._Elements) do
				Element._PositionX = CurrentX + 5
				Element._PositionY = CurrentY + SectionContentHeight - SectionScrollOffset
				Element._Width = ColumnWidth - 10 - (HasScrollbar and (Theme.ScrollbarWidth + 4) or 0)
				local ElementAvailableWidth = Theme:GetElementAvailableWidth(Element, Window)
				Element._AvailableWidth = ElementAvailableWidth

				if Element._Type == "TextLabel" then
					local AvailWidth = TextAvailableWidth(ElementAvailableWidth, Theme.ElementFontSize)
					if not Element._WrappedLines or Element._LastText ~= Element._Text or Element._LastWidth ~= ElementAvailableWidth or Element._LastFontSize ~= Theme.ElementFontSize then
						Element._LastText = Element._Text
						Element._LastWidth = ElementAvailableWidth
						Element._LastFontSize = Theme.ElementFontSize
						Element._WrappedLines = WrapText(Element._Text, AvailWidth, Theme.ElementFontSize)
					end
					Element._Height = TextBlockHeight(#Element._WrappedLines, Theme.ElementFontSize)
				elseif Element._Type == "TextBox" then
					local TextBoxMetrics = GetTextBoxLayoutMetrics(
						Element,
						Vector2.new(0, 0),
						ElementAvailableWidth
					)
					Element._TextBoxBaseHeight = TextBoxMetrics.BaseHeight
					Element._Height = TextBoxMetrics.BaseHeight + GetTextBoxSuggestionDropdownHeight(Element)
				end
				if Element._Type == "Slider" then
					-- The visual track starts and ends at the thumb centers. Reserving
					-- the maximum hover radius on both sides keeps the complete circle
					-- inside the element at minimum and maximum values.
					local SliderHorizontalInset = math.min(
						Theme.SliderThumbHoverRadius,
						ElementAvailableWidth / 2
					)
					Element._TrackPositionX = Element._PositionX + SliderHorizontalInset
					Element._TrackPositionY = Element._PositionY + Theme.ElementFontSize + 5
					Element._TrackTotalWidth = math.max(
						1,
						ElementAvailableWidth - SliderHorizontalInset * 2
					)
					Element._TrackTotalHeight = Theme.SliderTrackHeight
				elseif Element._Type == "ColorPicker" then
					Element._SwatchSize = Theme.ColorSwatchSize
					Element._SwatchPositionX = Element._PositionX + ElementAvailableWidth - Element._SwatchSize - 5
					Element._SwatchPositionY = Element._PositionY + (Element._Height - Element._SwatchSize) / 2
				elseif Element._Type == "Dropdown" then
					local ItemVerticalOffset = Element._PositionY + Element._Height
					local DropdownScrollOffset = ClampDropdownScrollOffset(Element)
					Element._OptionsRegion = nil
					if Element._Expanded then
						Element._OptionsRegion = {
							Position = WindowPosition + Vector2.new(Element._PositionX, ItemVerticalOffset - Window._ScrollOffset),
							Size = Vector2.new(ElementAvailableWidth, GetDropdownOptionsHeight(Element)),
						}
					end
					for ItemIndex, ItemData in ipairs(Element._ItemDrawingObjects) do
						ItemData._PositionX = Element._PositionX
						ItemData._PositionY = ItemVerticalOffset + (ItemIndex - 1) * Theme.ElementHeight - DropdownScrollOffset
						ItemData._Width = ElementAvailableWidth
					end
				end

				local CurrentPadding = Theme.ElementPadding
				local NextElement = Section._Elements[ElementIndex + 1]
				if Element._Type == "TextLabel" and NextElement and NextElement._Type == "TextLabel" then
					CurrentPadding = 2
				end

				SectionContentHeight = SectionContentHeight + Element._Height + CurrentPadding

				if Element._Type == "Dropdown" and Element._Expanded then
					SectionContentHeight = SectionContentHeight + GetDropdownOptionsHeight(Element)
				end

				if not UseImmediateMode then
					local ElementAbsolutePosition = WindowPosition + Vector2.new(Element._PositionX, Element._PositionY - Window._ScrollOffset)
					local ElementAbsoluteSize = Vector2.new(ElementAvailableWidth, Element._Height)

					local InteractiveBodyHeight = Element._Type == "TextBox"
						and (Element._TextBoxBaseHeight or Element._Height)
						or Element._Height
					local IsElementVisible = Element._Type == "TextLabel"
						and IsElementVisibleInViewport(ElementAbsolutePosition.Y, Element._Height, Section, Window, WindowPosition.Y)
						or IsElementFullyVisibleInViewport(ElementAbsolutePosition.Y, InteractiveBodyHeight, Section, Window, WindowPosition.Y)

					if Element._Type == "TextLabel" then

						if not Element._WrappedLines or #Element._WrappedLines == 0 then
							local AvailWidth = TextAvailableWidth(ElementAvailableWidth, Theme.ElementFontSize)
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
						for VisualIndex, VisualData in ipairs(Element._InlineVisualDrawings or {}) do
							local LineY = ElementAbsolutePosition.Y + VerticalPadding + (VisualData.LineIndex - 1) * LineHeight
							local IsVisualVisible = IsElementVisible and (LineY >= AllowedMinY) and (LineY + LineHeight <= AllowedMaxY)
							local VisualRadius = VisualData.Radius or math.max(3, Theme.ElementFontSize * 0.32)
							ApplyDrawingProperties(VisualData.DrawingObject, {
								Position = Vector2.new(
									ElementAbsolutePosition.X + HorizontalInset + VisualData.ColumnIndex * VisualData.CharacterWidth + VisualRadius,


									LineY + (LineHeight / 2)
								),
								Radius = VisualRadius,
								NumSides = 64,
								Color = VisualData.Color,
								Filled = true,
								Visible = IsVisualVisible,
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
							local AvailableTextWidth = ElementAbsoluteSize.X - 20
							local CharacterWidth = GetEditableTextCharacterWidth(Theme.ElementFontSize)
							local MaximumCharacters = math.max(1, math.floor(AvailableTextWidth / CharacterWidth))
							local DisplayText = TruncateTextWithAsciiEllipsis(Element._Text, MaximumCharacters)
							ApplyDrawingProperties(Element._TextDrawing, {
								Text = DisplayText,
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
							-- Reserve the indicator region so descriptive toggle names never
							-- paint beneath the circular state marker on narrow sections.
							local AvailableTextWidth = math.max(1, ElementAbsoluteSize.X - 42)
							local CharacterWidth = GetEditableTextCharacterWidth(Theme.ElementFontSize)
							local MaximumCharacters = math.max(1, math.floor(AvailableTextWidth / CharacterWidth))
							local DisplayText = TruncateTextWithAsciiEllipsis(Element._Text, MaximumCharacters)
							ApplyDrawingProperties(Element._TextDrawing, {
								Text = DisplayText,
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
							ApplyDrawingProperties(Element._IndicatorDrawing, {
								Position = Vector2.new(PipX, PipY),
								Radius = Theme.ToggleIndicatorRadius,
								Color = PipColor,
								Visible = IsElementVisible,
							})
						end
					elseif Element._Type == "TextBox" then
						local TextBoxMetrics = GetTextBoxLayoutMetrics(Element, ElementAbsolutePosition, ElementAbsoluteSize.X)
						local TextBoxBaseHeight = TextBoxMetrics.BaseHeight
						local TextBoxBaseSize = Vector2.new(ElementAbsoluteSize.X, TextBoxBaseHeight)

						if Element._IsFocused then
							local CurrentTimestamp = tick()
							if CurrentTimestamp - Element._CursorBlinkTime >= 0.53 then
								Element._CursorBlinkTime = CurrentTimestamp
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
							ApplyDrawingProperties(Element._BackgroundDrawing, { Position = ElementAbsolutePosition, Size = TextBoxBaseSize, Color = TextBoxBackgroundColor, Visible = IsElementVisible })
						end
						if Element._BorderDrawing then
							ApplyDrawingProperties(Element._BorderDrawing, { Position = ElementAbsolutePosition, Size = TextBoxBaseSize, Color = TextBoxBorderColor, Thickness = TextBoxBorderThickness, Visible = IsElementVisible })
						end

						if Element._AccentLineDrawing then
							local AccentFrom = Vector2.new(ElementAbsolutePosition.X, ElementAbsolutePosition.Y + 3)
							local AccentTo = Vector2.new(ElementAbsolutePosition.X, ElementAbsolutePosition.Y + TextBoxBaseHeight - 3)
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
								Position = TextBoxMetrics.LabelPosition,
								Text = TextBoxMetrics.LabelDisplayText,
								Size = Theme.ElementFontSize,
								Color = Theme.TextBoxText,
								Visible = IsElementVisible and TextBoxMetrics.LabelDisplayText ~= "",
							})
						end

						if Element._TextDrawing then
							local HasValue = Element._Value ~= ""
							local DisplayText = HasValue and Element._Value or Element._Placeholder
							local InputStartX = TextBoxMetrics.InputStartX
							local CharacterWidth = TextBoxMetrics.CharacterWidth
							local MaxChars = TextBoxMetrics.MaximumCharacters
							local ClippedText = GetTextBoxVisibleText(Element, DisplayText, MaxChars, HasValue)
							ApplyDrawingProperties(Element._TextDrawing, {
								Position = Vector2.new(InputStartX, TextBoxMetrics.InputTextPositionY),
								Text = ClippedText,
								Size = Theme.ElementFontSize,
								Color = HasValue and Theme.TextBoxText or Theme.TextBoxPlaceholder,
								Visible = IsElementVisible,
							})

							if Element._CursorDrawing then
								local DisplayStartIndex, DisplayEndIndex = GetVisibleTextBoxCharacterRange(Element, MaxChars)
								local CursorIndex = math.clamp(ClampTextBoxCursorIndex(Element, Element._CursorIndex), DisplayStartIndex, DisplayEndIndex)
								local CursorX = InputStartX + (CursorIndex - DisplayStartIndex) * CharacterWidth
								local CursorTopY = TextBoxMetrics.InputTextPositionY
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
								local InputStartX = TextBoxMetrics.InputStartX
								local CharacterWidth = TextBoxMetrics.CharacterWidth
								local MaxChars = TextBoxMetrics.MaximumCharacters
								local SelectionStartIndex, SelectionEndIndex = GetTextBoxSelectionBounds(Element)
								local DisplayStartIndex, DisplayEndIndex = GetVisibleTextBoxCharacterRange(Element, MaxChars)
								local VisibleSelectionStartIndex = SelectionStartIndex and math.max(SelectionStartIndex, DisplayStartIndex)
								local VisibleSelectionEndIndex = SelectionEndIndex and math.min(SelectionEndIndex, DisplayEndIndex)
								if VisibleSelectionStartIndex and VisibleSelectionEndIndex and VisibleSelectionStartIndex < VisibleSelectionEndIndex then
									local SelectionX = InputStartX + (VisibleSelectionStartIndex - DisplayStartIndex) * CharacterWidth
									local SelectionWidth = (VisibleSelectionEndIndex - VisibleSelectionStartIndex) * CharacterWidth
									ApplyDrawingProperties(Element._SelectionDrawing, {
										Position = Vector2.new(SelectionX - 2, TextBoxMetrics.InputTextPositionY - 2),
										Size = Vector2.new(SelectionWidth + 4, Theme.ElementFontSize + 4),
										Visible = true,
									})
								else
									SetRenderProperty(Element._SelectionDrawing, "Visible", false)
								end
							else
								SetRenderProperty(Element._SelectionDrawing, "Visible", false)
							end
						end

						if Element._IsFocused and #Element._Suggestions > 0 and IsElementVisible then
							local SuggestionCount = math.min(#Element._Suggestions, Element._MaximumSuggestions or 5)
							local SuggestionRowHeight = 22
							local SuggestionPosition = Vector2.new(ElementAbsolutePosition.X, ElementAbsolutePosition.Y + TextBoxBaseHeight + 2)
							local SuggestionSize = Vector2.new(ElementAbsoluteSize.X, SuggestionRowHeight * SuggestionCount)
							local AllowedMinY, AllowedMaxY = GetSectionAllowedYRange(Section, Window, WindowPosition.Y)
							local ClippedSuggestionPosition, ClippedSuggestionSize = ClipRectangleToYRange(
								SuggestionPosition,
								SuggestionSize,
								AllowedMinY,
								AllowedMaxY
							)
							Element._SuggestionDropdownRegion = ClippedSuggestionPosition and {
								Position = ClippedSuggestionPosition,
								Size = ClippedSuggestionSize,
							} or nil

							if ClippedSuggestionPosition and ClippedSuggestionSize then
								ApplyDrawingProperties(Element._SuggestionBackgroundDrawing, {
									Position = ClippedSuggestionPosition,
									Size = ClippedSuggestionSize,
									Visible = true,
								})
								ApplyDrawingProperties(Element._SuggestionBorderDrawing, {
									Position = ClippedSuggestionPosition,
									Size = ClippedSuggestionSize,
									Visible = true,
								})
							else
								ApplyDrawingProperties(Element._SuggestionBackgroundDrawing, { Visible = false })
								ApplyDrawingProperties(Element._SuggestionBorderDrawing, { Visible = false })
							end

							for SuggestionRowIndex, SuggestionRow in ipairs(Element._SuggestionRows or {}) do
								local SuggestionText = Element._Suggestions[SuggestionRowIndex]
								local SuggestionY = SuggestionPosition.Y + (SuggestionRowIndex - 1) * SuggestionRowHeight
								local RowIsVisible = SuggestionText ~= nil
									and SuggestionRowIndex <= SuggestionCount
									and SuggestionY >= AllowedMinY
									and SuggestionY + SuggestionRowHeight <= AllowedMaxY
								if RowIsVisible then
									local MaximumSuggestionCharacters = math.max(1, math.floor((SuggestionSize.X - 16) / TextBoxMetrics.CharacterWidth))
									ApplyDrawingProperties(SuggestionRow.TextDrawing, {
										Text = TruncateTextWithAsciiEllipsis(SuggestionText, MaximumSuggestionCharacters),
										Position = Vector2.new(SuggestionPosition.X + 8, SuggestionY + (SuggestionRowHeight - Theme.ElementFontSize) / 2),
										Color = (Element._HoveredSuggestionIndex or Element._KeyboardSuggestionIndex) == SuggestionRowIndex and Theme.TitleBarTextHover or Theme.DropdownText,
										Visible = true,
									})
									ApplyDrawingProperties(SuggestionRow.HoverDrawing, {
										Position = Vector2.new(SuggestionPosition.X, SuggestionY),
										Size = Vector2.new(SuggestionSize.X, SuggestionRowHeight),
										Visible = (Element._HoveredSuggestionIndex or Element._KeyboardSuggestionIndex) == SuggestionRowIndex,
									})
								else
									ApplyDrawingProperties(SuggestionRow.HoverDrawing, { Visible = false })
									ApplyDrawingProperties(SuggestionRow.TextDrawing, { Visible = false })
								end
							end
						else
							Element._SuggestionDropdownRegion = nil
							if Element._SuggestionBackgroundDrawing then ApplyDrawingProperties(Element._SuggestionBackgroundDrawing, { Visible = false }) end
							if Element._SuggestionBorderDrawing then ApplyDrawingProperties(Element._SuggestionBorderDrawing, { Visible = false }) end
							for SuggestionRowIndex, SuggestionRow in ipairs(Element._SuggestionRows or {}) do
								ApplyDrawingProperties(SuggestionRow.HoverDrawing, { Visible = false })
								ApplyDrawingProperties(SuggestionRow.TextDrawing, { Visible = false })
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
							local AvailableTextWidth = ElementAbsoluteSize.X - 32
							local CharacterWidth = GetEditableTextCharacterWidth(Theme.ElementFontSize)
							local MaximumCharacters = math.max(1, math.floor(AvailableTextWidth / CharacterWidth))
							local FullText = string.format("%s: %s", Element._Text, Element:GetDisplayValueText())
							local DisplayText = TruncateTextWithAsciiEllipsis(FullText, MaximumCharacters)
							ApplyDrawingProperties(Element._TextDrawing, {
								Text = DisplayText,
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
							local OptionsRegion = Element._OptionsRegion
							for ItemIndex, ItemData in ipairs(Element._ItemDrawingObjects) do
								local ItemAbsolutePosition = WindowPosition + Vector2.new(ItemData._PositionX, ItemData._PositionY - Window._ScrollOffset)
								local IsInsideDropdownRegion = OptionsRegion
									and ItemAbsolutePosition.Y + Theme.ElementHeight > OptionsRegion.Position.Y
									and ItemAbsolutePosition.Y < OptionsRegion.Position.Y + OptionsRegion.Size.Y
								local IsItemVisible = IsInsideDropdownRegion and IsElementFullyVisibleInViewport(
									ItemAbsolutePosition.Y,
									Theme.ElementHeight,
									Section,
									Window,
									WindowPosition.Y
								)
								local IsItemHovered = IsItemVisible and IsPointInsideRectangle(Window:GetCurrentPointerPosition(), ItemAbsolutePosition, Vector2.new(ItemData._Width, Theme.ElementHeight))

								if ItemData.BackgroundDrawing then
									ApplyDrawingProperties(ItemData.BackgroundDrawing, {
										Position = ItemAbsolutePosition,
										Size = Vector2.new(ElementAbsoluteSize.X, Theme.ElementHeight),
										Color = IsItemHovered and Theme.DropdownItemHover or Theme.DropdownItemBackground,
										Visible = IsItemVisible,
									})
								end
								if ItemData.TextDrawing then
									local AvailableItemTextWidth = ElementAbsoluteSize.X - 24
									local CharacterWidth = GetEditableTextCharacterWidth(Theme.ElementFontSize)
									local MaximumCharacters = math.max(1, math.floor(AvailableItemTextWidth / CharacterWidth))
									local DisplayItemText = TruncateTextWithAsciiEllipsis(Element:GetOptionDisplayText(ItemData.Value), MaximumCharacters)
									ApplyDrawingProperties(ItemData.TextDrawing, {
										Text = DisplayItemText,
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
						local SliderTextMetrics = Theme:GetSliderTextLayoutMetrics(
							Element,
							ElementAbsolutePosition,
							Element._AvailableWidth or Element._TrackTotalWidth
						)
						if Element._LabelDrawing then
							ApplyDrawingProperties(Element._LabelDrawing, {
								Position = SliderTextMetrics.LabelPosition,
								Text = SliderTextMetrics.LabelDisplayText,
								Color = SliderLabelColor,
								Size = Theme.ElementFontSize,
								Visible = IsElementVisible,
							})
						end
						if Element._ValueTextDrawing then
							ApplyDrawingProperties(Element._ValueTextDrawing, {
								Position = SliderTextMetrics.ValuePosition,
								Text = SliderTextMetrics.ValueDisplayText,
								Color = ValueColor,
								Size = Theme.ElementFontSize,
								Visible = IsElementVisible,
							})
						end

						local TrackHeight = LerpValue(
							Theme.SliderTrackHeight,
							Theme.SliderTrackHoverHeight,
							Element._HoverFactor or 0
						)
						local TrackAbsolutePosition = Vector2.new(
							WindowPosition.X + Element._TrackPositionX,
							WindowPosition.Y + Element._TrackPositionY - Window._ScrollOffset
								- (TrackHeight - Theme.SliderTrackHeight) / 2
						)
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
						local ThumbRadius = LerpValue(
							Theme.SliderThumbRadius,
							Theme.SliderThumbHoverRadius,
							Element._ThumbHoverFactor or 0
						)
						ThumbRadius = math.min(
							ThumbRadius,
							(Element._AvailableWidth or Element._TrackTotalWidth) / 2
						)
						local ThumbColor = Theme.SliderTrackFill:Lerp(
							Theme.SliderTrackFillHover,
							Element._ThumbHoverFactor or 0
						)
						local ThumbCenter = TrackAbsolutePosition + Vector2.new(FillWidth, TrackHeight / 2)
						if Element._ThumbDrawing then
							ApplyDrawingProperties(Element._ThumbDrawing, {
								Position = ThumbCenter,
								Radius = ThumbRadius,
								Color = ThumbColor,
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
					UpdateRetainedExecutorLock(
						Element,
						ElementAbsolutePosition,
						ElementAbsoluteSize,
						IsElementVisible,
						Section
					)
				end
			end

			Section._FullContentHeight = SectionContentHeight
			local RequiresSectionScrollbar = Section._MaxHeight ~= nil and SectionContentHeight > Section._MaxHeight
			if RequiresSectionScrollbar ~= (HasScrollbar == true) then
				-- Dynamic labels, suggestions, and dropdown expansion can change a
				-- section from non-scrollable to scrollable during this very layout
				-- pass. Run one corrected pass so every element immediately reserves
				-- the scrollbar width instead of waiting for another input event.
				LayoutRequiresScrollbarCorrection = true
			end

			-- Section maximum heights are stored in design space and converted to
			-- screen space whenever the viewport scale changes. This keeps a panel's
			-- visible height proportional to the controls inside it at every desktop,
			-- phone, and tablet scale.
			local EffectiveMaxHeight = Section._MaxHeight

			if EffectiveMaxHeight and SectionContentHeight > EffectiveMaxHeight then
				-- Store both the full canvas height and the clipped viewport height.
				-- The renderer uses the clipped height for the border, while input
				-- and scrollbar math keep using the full content height for scrolling.
				Section._ClippedHeight = EffectiveMaxHeight
				-- SectionContentHeight already includes the header and the final body
				-- padding. Subtracting the visible height therefore produces the exact
				-- travel needed to reveal the last control. Adding another header here
				-- used to make the scrollbar range disagree with the rendered content.
				Section._SectionMaxScroll = math.max(0, SectionContentHeight - EffectiveMaxHeight)
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

				local CurrentMousePos = Window:GetCurrentPointerPosition()
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

				if Section._TextLabel then
					local TitleColor = Theme.SectionText:Lerp(Theme.SectionTextHover, Section._HoverFactor or 0)
					local TitleY = SectionAbsolutePosition.Y + (Theme.ElementHeight - Theme.SectionFontSize) / 2
					local IsTitleVisible = IsSectionVisible and (TitleY >= ViewportStart) and (TitleY + Theme.SectionFontSize <= ViewportEnd)
					local SectionIndexText = string.format("%02d", Section._Index or 0)
					local SectionIndexBounds = GetTextBounds(SectionIndexText, Theme.SectionMetaFontSize)
					local AvailableTitleWidth = math.max(
						1,
						Section._Width - SectionIndexBounds.X - 34
					)
					local MaximumTitleCharacters = math.max(
						1,
						math.floor(AvailableTitleWidth / GetEditableTextCharacterWidth(Theme.SectionFontSize))
					)
					ApplyDrawingProperties(Section._TextLabel, {
						Text = TruncateTextWithAsciiEllipsis(Section._Title, MaximumTitleCharacters),
						Position = Vector2.new(SectionAbsolutePosition.X + 10, TitleY),
						Color = TitleColor,
						Visible = IsTitleVisible,
					})

					if Section._IndexTextLabel then
						ApplyDrawingProperties(Section._IndexTextLabel, {
							Text = SectionIndexText,
							Size = Theme.SectionMetaFontSize,
							Position = Vector2.new(
								SectionAbsolutePosition.X + Section._Width - SectionIndexBounds.X - 10,
								SectionAbsolutePosition.Y + (Theme.ElementHeight - Theme.SectionMetaFontSize) / 2
							),
							Color = Theme.TextBoxPlaceholder,
							Visible = IsTitleVisible,
						})
					end
				end
			end

			local SectionLayoutHeight = Section._ContentHeight or SectionContentHeight
			if IsColumnOne then
				ColumnOnePositionY = ColumnOnePositionY + SectionLayoutHeight + Theme.SectionPadding
			else
				ColumnTwoPositionY = ColumnTwoPositionY + SectionLayoutHeight + Theme.SectionPadding
			end
		end

		local ContentHeight = UseSingleColumnLayout
			and ColumnOnePositionY
			or math.max(ColumnOnePositionY, ColumnTwoPositionY)
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

				local TabLayout = GetPageTabLayout(Window, Theme.WindowWidth)
				Window._TabScrollOffset = math.clamp(Window._TabScrollOffset or 0, 0, TabLayout.MaximumScroll)

				for PageIndex, Page in ipairs(Window._Pages) do
					local TabDrawings = Window._TabDrawings[PageIndex]
					if TabDrawings then
						local TabWidth = TabLayout.Widths[PageIndex]
						local TabX = WindowPosition.X + TabLayout.Padding + TabLayout.Offsets[PageIndex] - Window._TabScrollOffset
						local TabY = WindowPosition.Y + Theme.TitleBarHeight + 5
						local TabHeight = Window._TabBarHeight - 10
						
						local TabVisible = Window._Visible and Library:IsPageTabFullyInsideViewport(
							TabLayout,
							WindowPosition.X,
							Theme.WindowWidth,
							TabX,
							TabWidth
						)

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
				if TabLayout.MaximumScroll > 0 and Window._TabScrollbarDrawing then
					local ScrollProgress = Window._TabScrollOffset / TabLayout.MaximumScroll
					local AvailableTabWidth = TabLayout.AvailableWidth
					local HandleWidth = math.clamp(
						(AvailableTabWidth / TabLayout.ContentWidth) * AvailableTabWidth,
						30,
						AvailableTabWidth
					)
					local HandleX = WindowPosition.X + TabLayout.Padding + (AvailableTabWidth - HandleWidth) * ScrollProgress
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



			-- Responsive resizing must update the retained title rectangles as well as
			-- the body. Leaving their construction-time width untouched made the title
			-- bar and the final tab visibly protrude after a mobile geometry change.
			ApplyDrawingProperties(TitleBarBackgroundDrawing, {
				Position = WindowPosition,
				Size = Vector2.new(Theme.WindowWidth, Theme.TitleBarHeight),
				Color = Theme.TitleBarBackground,
			})
			ApplyDrawingProperties(TitleBarHighlightDrawing, {
				Position = WindowPosition,
				Size = Vector2.new(Theme.WindowWidth, math.max(6, Theme.TitleBarHeight * 0.45)),
				Color = Theme.TitleBarHighlight,
				Visible = Window._Visible,
			})
			ApplyDrawingProperties(TitleBarAccentWashDrawing, {
				Position = WindowPosition,
				Size = Vector2.new(Theme.WindowWidth, Theme.TitleBarHeight),
				Color = Theme.TitleBarAccentWash,
				Visible = Window._Visible,
			})
			ApplyDrawingProperties(TitleBarBorderDrawing, {
				Position = WindowPosition,
				Size = Vector2.new(Theme.WindowWidth, Theme.TitleBarHeight),
				Color = Theme.WindowBorder,
			})

			local TitleTextPositionY = Window._Description ~= ""
				and WindowPosition.Y + 7
				or WindowPosition.Y + (Theme.TitleBarHeight - Theme.TitleFontSize) / 2

			if TitleBarTextDrawing then
				ApplyDrawingProperties(TitleBarTextDrawing, {
					Text = Window._Title,
					Size = Theme.TitleFontSize,
					Position = Vector2.new(
						WindowPosition.X + Theme.InnerMargin + 12,
						TitleTextPositionY
					),
					Color = Window._TitleTextHovered and Theme.TitleBarTextHover or Theme.TitleBarText,
					Visible = Window._Visible,
				})
			end

			if TitleBarDescriptionDrawing then
				ApplyDrawingProperties(TitleBarDescriptionDrawing, {
					Text = Window._Description,
					Size = Theme.HeaderSecondaryFontSize,
					Position = Vector2.new(
						WindowPosition.X + Theme.InnerMargin + 12,
						WindowPosition.Y + Theme.TitleFontSize + 10
					),
					Color = Theme.TextBoxPlaceholder,
					Visible = Window._Visible and Window._Description ~= "",
				})
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

			if Window._ResizeGripLines then
				local ResizeGripCornerInset = Window._TouchInputAvailable and 7 or 5
				local ResizeGripLineSpacing = Window._TouchInputAvailable and 6 or 4
				local ResizeGripCornerPosition = Vector2.new(
					WindowPosition.X + Theme.WindowWidth - ResizeGripCornerInset,
					WindowPosition.Y + Theme.TitleBarHeight + Window._VisibleHeight - ResizeGripCornerInset
				)
				local ResizeGripColor = Window._ResizeGripHovered and Theme.TitleBarTextHover or Theme.TitleBarSeparator
				for ResizeGripLineIndex, ResizeGripLineObject in ipairs(Window._ResizeGripLines) do
					local ResizeGripOffset = ResizeGripLineIndex * ResizeGripLineSpacing
					ApplyDrawingProperties(ResizeGripLineObject, {
						From = ResizeGripCornerPosition - Vector2.new(ResizeGripOffset, 0),
						To = ResizeGripCornerPosition - Vector2.new(0, ResizeGripOffset),
						Color = ResizeGripColor,
						Thickness = Window._TouchInputAvailable and 2 or 1.35,
						Transparency = Window._ResizeGripHovered and 0.9 or 0.42,
						Visible = Window._Visible,
					})
				end
			end
		end

		local CloseButtonSize = Window._TouchInputAvailable and math.max(32, Theme.ElementHeight) or 24
		local CloseButtonPosX = WindowPosition.X + Theme.WindowWidth - CloseButtonSize - 10
		local CloseButtonPosY = WindowPosition.Y + (Theme.TitleBarHeight - CloseButtonSize) / 2
		Window._CloseButtonRegion = {
			Position = Vector2.new(CloseButtonPosX, CloseButtonPosY),
			Size = Vector2.new(CloseButtonSize, CloseButtonSize)
		}

		local SearchButtonSize = CloseButtonSize
		local SearchButtonPosX = CloseButtonPosX - SearchButtonSize - 8
		local SearchButtonPosY = CloseButtonPosY
		Window._SearchButtonRegion = {
			Position = Vector2.new(SearchButtonPosX, SearchButtonPosY),
			Size = Vector2.new(SearchButtonSize, SearchButtonSize)
		}

		if not UseImmediateMode then
			local HeaderMetaText = Window:GetHeaderMetaText()
			local HeaderMetaBounds = GetTextBounds(HeaderMetaText, Theme.HeaderSecondaryFontSize)
			local HeaderActionSeparatorX = SearchButtonPosX - 10
			local HeaderMetaPositionX = HeaderActionSeparatorX - HeaderMetaBounds.X - 10
			local TitleBounds = GetTextBounds(Window._Title, Theme.TitleFontSize)
			local DescriptionBounds = Window._Description ~= ""
				and GetTextBounds(Window._Description, Theme.HeaderSecondaryFontSize)
				or Vector2.new(0, 0)
			local HeaderTextWidth = math.max(TitleBounds.X, DescriptionBounds.X)
			local TitleSafeRightX = WindowPosition.X + Theme.InnerMargin + 12 + HeaderTextWidth + 20
			local HeaderMetaVisible = Window._Visible and HeaderMetaPositionX > TitleSafeRightX

			if TitleBarMetaDrawing then
				ApplyDrawingProperties(TitleBarMetaDrawing, {
					Text = HeaderMetaText,
					Size = Theme.HeaderSecondaryFontSize,
					Position = Vector2.new(
						HeaderMetaPositionX,
						WindowPosition.Y + (Theme.TitleBarHeight - Theme.HeaderSecondaryFontSize) / 2
					),
					Color = Theme.LabelText,
					Visible = HeaderMetaVisible,
				})
			end

			if TitleBarActionSeparatorDrawing then
				ApplyDrawingProperties(TitleBarActionSeparatorDrawing, {
					From = Vector2.new(HeaderActionSeparatorX, WindowPosition.Y + 10),
					To = Vector2.new(HeaderActionSeparatorX, WindowPosition.Y + Theme.TitleBarHeight - 10),
					Color = Theme.WindowBorder,
					Visible = HeaderMetaVisible,
				})
			end

			if Window._SearchIconCircle and Window._SearchIconLine then
				local SearchButtonCenterOffset = Window._SearchButtonRegion.Size / 2
				local CenterPoint = Window._SearchButtonRegion.Position + SearchButtonCenterOffset
				local MouseIsOverSearch = IsPointInsideRectangle(Window:GetCurrentPointerPosition(), Window._SearchButtonRegion.Position, Window._SearchButtonRegion.Size)
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
				local CharacterWidth = GetEditableTextCharacterWidth(Theme.ElementFontSize)
				local MaxQueryChars = math.max(1, math.floor(AvailableQueryWidth / CharacterWidth))
				SearchDisplayText = GetTextBoxVisibleText(
					Window._SearchTextBox,
					SearchDisplayText,
					MaxQueryChars,
					Window._SearchTextBox._Value ~= ""
				)

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
					Window._HighlightedSection = nil
					ApplyDrawingProperties(Window._ElementHighlightDrawing, { Visible = false })
				else
					local HighlightAlpha = math.clamp(1 - (ElapsedTime / 2.0), 0, 1)
					local HighlightAbsolutePosition = WindowPosition + Vector2.new(HighlightElement._PositionX, HighlightElement._PositionY - Window._ScrollOffset)
					local HighlightAbsoluteSize = Vector2.new(Theme:GetElementAvailableWidth(HighlightElement, Window), HighlightElement._Height)
					local HighlightSection = HighlightElement._Section or Window._HighlightedSection
					local HighlightIsVisible = HighlightSection ~= nil and IsElementFullyVisibleInViewport(
						HighlightAbsolutePosition.Y,
						HighlightAbsoluteSize.Y,
						HighlightSection,
						Window,
						WindowPosition.Y
					)

					ApplyDrawingProperties(Window._ElementHighlightDrawing, {
						Position = HighlightAbsolutePosition,
						Size = HighlightAbsoluteSize,
						Thickness = 2,
						Color = Theme.TitleBarSeparator,
						Transparency = HighlightAlpha,
						Visible = HighlightIsVisible,
					})
				end
			end

			local TooltipGeometry = GetTooltipGeometry(Window, Window:GetCurrentPointerPosition())
			if TooltipGeometry then
				ApplyDrawingProperties(Window._TooltipBackgroundDrawing, {
					Position = TooltipGeometry.Position,
					Size = TooltipGeometry.Size,
					Color = Theme.TooltipBackground,
					Visible = Window._Visible,
				})
				ApplyDrawingProperties(Window._TooltipBorderDrawing, {
					Position = TooltipGeometry.Position,
					Size = TooltipGeometry.Size,
					Color = Theme.TooltipBorder,
					Visible = Window._Visible,
				})
				for TooltipLineIndex, TooltipTextDrawingObject in ipairs(Window._TooltipTextDrawings) do
					local TooltipLine = TooltipGeometry.Lines[TooltipLineIndex]
					if TooltipLine then
						ApplyDrawingProperties(TooltipTextDrawingObject, {
							Text = TooltipLine,
							Position = TooltipGeometry.Position + Vector2.new(
								Theme.TooltipPadding,
								Theme.TooltipPadding + (TooltipLineIndex - 1) * FontLineHeight(Theme.ElementFontSize)
							),
							Size = Theme.ElementFontSize,
							Color = Theme.TooltipText,
							Visible = Window._Visible,
						})
					else
						ApplyDrawingProperties(TooltipTextDrawingObject, { Visible = false })
					end
				end
			else
				ApplyDrawingProperties(Window._TooltipBackgroundDrawing, { Visible = false })
				ApplyDrawingProperties(Window._TooltipBorderDrawing, { Visible = false })
				for TooltipLineIndex, TooltipTextDrawingObject in ipairs(Window._TooltipTextDrawings) do
					ApplyDrawingProperties(TooltipTextDrawingObject, { Visible = false })
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

		-- A section can gain or lose its private scrollbar while the current pass
		-- is measuring dynamic labels, suggestions, or an expanded dropdown. Run
		-- one guarded correction pass after all sections have been measured so
		-- every control reserves the final scrollbar width immediately.
		if LayoutRequiresScrollbarCorrection and not Window._ApplyingScrollbarLayoutCorrection then
			Window._ApplyingScrollbarLayoutCorrection = true
			Window:RecalculateLayout()
			Window._ApplyingScrollbarLayoutCorrection = false
		end
		Window._HasCompletedLayout = true
	end

	local function UpdateElementsVisibility()
		if UseImmediateMode then return end
		for DiscardIndex, Section in ipairs(Window._Sections) do
			local SectionBelongsToActivePage = not Section._PageIndex
				or Section._PageIndex == Window._ActivePageIndex
			local ShouldForceHideSection = not Window._Visible or not SectionBelongsToActivePage
			if ShouldForceHideSection then
				SetDrawingObjectsVisibility({
					Section._FullBackground,
					Section._Background,
					Section._Border,
					Section._TextLabel,
					Section._IndexTextLabel,
					Section._AccentLine,
					Section._LeftAccentLine,
					Section._ScrollbarTrack,
					Section._ScrollbarHandle,
				}, false)

				for ElementIndex, Element in ipairs(Section._Elements) do
					if Element._Type == "TextLabel" then
						SetDrawingObjectsVisibility({ Element._AccentLineDrawing }, false)
						for LineIndex, LineDrawingObject in ipairs(Element._LineDrawings or {}) do
							SetRenderProperty(LineDrawingObject, "Visible", false)
						end
						Theme:HideInlineVisualDrawings(Element)
					elseif Element._Type == "TextButton" then
						SetDrawingObjectsVisibility({
							Element._BackgroundDrawing,
							Element._BorderDrawing,
							Element._TextDrawing,
							Element._AccentLineDrawing,
						}, false)
					elseif Element._Type == "Toggle" then
						SetDrawingObjectsVisibility({
							Element._BackgroundDrawing,
							Element._BorderDrawing,
							Element._TextDrawing,
							Element._IndicatorDrawing,
							Element._AccentLineDrawing,
						}, false)
					elseif Element._Type == "TextBox" then
						SetDrawingObjectsVisibility({
							Element._BackgroundDrawing,
							Element._BorderDrawing,
							Element._LabelDrawing,
							Element._TextDrawing,
							Element._AccentLineDrawing,
							Element._SelectionDrawing,
							Element._CursorDrawing,
							Element._SuggestionBackgroundDrawing,
							Element._SuggestionBorderDrawing,
						}, false)
						for SuggestionRowIndex, SuggestionRow in ipairs(Element._SuggestionRows or {}) do
							SetDrawingObjectsVisibility({ SuggestionRow.HoverDrawing, SuggestionRow.TextDrawing }, false)
						end
					elseif Element._Type == "Dropdown" then
						SetDrawingObjectsVisibility({
							Element._BackgroundDrawing,
							Element._BorderDrawing,
							Element._TextDrawing,
							Element._ArrowDrawing,
							Element._AccentLineDrawing,
						}, false)
						for ItemIndex, ItemData in ipairs(Element._ItemDrawingObjects or {}) do
							SetDrawingObjectsVisibility({
								ItemData.BackgroundDrawing,
								ItemData.TextDrawing,
								ItemData.SeparatorDrawing,
							}, false)
						end
					elseif Element._Type == "Slider" then
						SetDrawingObjectsVisibility({
							Element._LabelDrawing,
							Element._ValueTextDrawing,
							Element._TrackBackgroundDrawing,
							Element._TrackBorderDrawing,
							Element._TrackFillDrawing,
							Element._ThumbDrawing,
						}, false)
					elseif Element._Type == "ColorPicker" then
						SetDrawingObjectsVisibility({
							Element._LabelDrawing,
							Element._SwatchDrawing,
							Element._SwatchBorderDrawing,
							Element._HoverBackgroundDrawing,
							Element._AccentLineDrawing,
							Element._ChevronDrawing,
						}, false)
						if Window._ActiveColorPicker == Element then
							Element:ClosePopup()
						end
					end
					if Element._ExecutorLockDrawingObjects then
						SetDrawingObjectsVisibility(Element._ExecutorLockDrawingObjects, false)
					end
				end
			end
		end
	end

	function Window:SetActivePage(PageIndex)
		-- Every navigation path enters through this method so mouse clicks, touch
		-- taps, search results, and future programmatic navigation all reset the
		-- same page-local scroll state and visibility graph.
		local NumericPageIndex = tonumber(PageIndex)
		if not NumericPageIndex or NumericPageIndex % 1 ~= 0 or not Window._Pages[NumericPageIndex] then
			return false
		end

		if NumericPageIndex == Window._ActivePageIndex then
			return true
		end

		Window._ActivePageIndex = NumericPageIndex
		Window._ScrollOffset = 0
		UpdateElementsVisibility()
		Window:RecalculateLayout()
		return true
	end

	function Window:GetPageTabIndexAtPosition(PointerPosition)
		if typeof(PointerPosition) ~= "Vector2" or Window._TabBarHeight <= 0 then
			return nil
		end

		local TabLayout = GetPageTabLayout(Window, Theme.WindowWidth)
		local TabVerticalInset = Window._TouchInputAvailable and 1 or 5
		local TabHeight = math.max(
			1,
			Window._TabBarHeight - TabVerticalInset * 2
		)
		local TabPositionY = Window._Position.Y + Theme.TitleBarHeight + TabVerticalInset

		for PageIndex = 1, #Window._Pages do
			local TabWidth = TabLayout.Widths[PageIndex]
			local TabPositionX = Window._Position.X
				+ TabLayout.Padding
				+ TabLayout.Offsets[PageIndex]
				- (Window._TabScrollOffset or 0)
			local TabIsFullyVisible = Library:IsPageTabFullyInsideViewport(
				TabLayout,
				Window._Position.X,
				Theme.WindowWidth,
				TabPositionX,
				TabWidth
			)

			if TabIsFullyVisible and IsPointInsideRectangle(
				PointerPosition,
				Vector2.new(TabPositionX, TabPositionY),
				Vector2.new(TabWidth, TabHeight)
			) then
				return PageIndex
			end
		end

		return nil
	end

	local function SetEntireWindowVisibility(IsVisible)
		if UseImmediateMode then
			Window._Visible = IsVisible
			return
		end

		Window._Visible = IsVisible
		if IsVisible then
			SetDrawingObjectsVisibility(Window._DrawingObjects, true)
			-- Reopening must rebuild positions and clipping before any retained object
			-- is allowed to remain visible. This prevents the previous hidden frame
			-- from flashing at stale coordinates after a move or resize.
			Window:RecalculateLayout()
		else
			-- WindowTrackedDrawings is the authoritative retained-mode registry. It
			-- includes section controls, inline symbols, executor locks, popups, and
			-- every other drawing created after the initial window shell. Hiding the
			-- complete registry prevents a late layout or animation pass from leaving
			-- isolated controls visible after the window itself has disappeared.
			SetDrawingObjectsVisibility(WindowTrackedDrawings, false)
			UpdateElementsVisibility()
		end
		Window:UpdateTouchLauncherDrawings()
	end

	function Window:SetVisible(IsVisible)
		local ShouldBeVisible = IsVisible == true
		if not ShouldBeVisible then
			-- Hidden windows must release every capture request immediately. Keeping
			-- a focused text box or drag operation alive would continue sinking
			-- Roblox input even though no control is visible.
			Window._Dragging = false
			Window._Resizing = false
			Window._DraggingScrollbar = false
			Window._ActiveSlider = nil
			Window._ActiveTextSelectionBox = nil
			Window._MouseInWindow = false
			Window._HoveredTooltipElement = nil
			Window._TooltipVisible = false
			Window:ReleaseNativeTextInput()
			local TouchInteractionState = Window._TouchInteractionState
			if TouchInteractionState then
				TouchInteractionState.ActiveInputObject = nil
				TouchInteractionState.StartPosition = nil
				TouchInteractionState.PreviousPosition = nil
				TouchInteractionState.CurrentPosition = nil
				TouchInteractionState.StartWindowPosition = nil
				TouchInteractionState.StartWindowSize = nil
				TouchInteractionState.GestureDistance = 0
				TouchInteractionState.Scrolling = false
				TouchInteractionState.ScrollTarget = nil
			end

			for SectionIndex, Section in ipairs(Window._Sections) do
				Section._DraggingScrollbar = false
				for ElementIndex, Element in ipairs(Section._Elements) do
					Element._IsHovered = false
					Element._TooltipHoverStartedAt = nil
					if Element._Type == "TextBox" then
						Element._IsFocused = false
						Element._CursorVisible = false
						Element._SelectionDragging = false
						ClearTextBoxSelection(Element)
					end
				end
			end

			if Window._SearchTextBox then
				Window._SearchTextBox._IsFocused = false
				Window._SearchTextBox._CursorVisible = false
				Window._SearchTextBox._SelectionDragging = false
				ClearTextBoxSelection(Window._SearchTextBox)
			end

			Window:SetInputBlocking("Scroll", false)
			Window:SetInputBlocking("Camera", false)
			Window:SetInputBlocking("Interface", false)
			Window._ScrollSinkActive = false
			Window._CameraSinkActive = false
			Window._InterfaceSinkActive = false
			Library:ClearInputBlockingForWindow(Window)
		end

		SetEntireWindowVisibility(ShouldBeVisible)
		if Window._TouchInputAvailable and not Window._Destroyed then
			-- Keep a position-aware touch action registered while the interface is
			-- either visible or represented by its launcher. The action itself passes
			-- touches outside those regions, so normal mobile game controls remain
			-- usable without allowing a User Interface tap to reach Roblox underneath.
			Window:SetInputBlocking("TouchInterface", true)
		end
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

	function Window:GetGeometrySignature()
		-- Geometry watchers only need a stable comparison key. Keeping its format
		-- in the library prevents every consumer from rebuilding the same string.
		local Geometry = Window:GetGeometry()
		return string.format(
			"%.0f:%.0f:%.0f:%.0f",
			Geometry.PositionX,
			Geometry.PositionY,
			Geometry.WindowWidth,
			Geometry.WindowVisibleHeight
		)
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

	function Window:CreatePage(PageConfiguration)
		-- Pages become tabs. Sections created through a page are scoped to that
		-- page and hidden when another page is active.
		PageConfiguration = PageConfiguration or {}
		PageConfiguration.Title = PageConfiguration.Title or "Page"

		local PageIndex = #Window._Pages + 1
		local Page = {
			Title = PageConfiguration.Title,
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

		function Page:CreateSection(SectionConfiguration)
			SectionConfiguration = SectionConfiguration or {}
			SectionConfiguration._PageIndex = PageIndex
			return Window:CreateSection(SectionConfiguration)
		end

		Window:RecalculateLayout()
		UpdateElementsVisibility()

		return Page
	end

	function Window:CreateSection(SectionConfiguration)
		-- Sections are vertical groups. A MaxHeight turns the section into an
		-- independently scrollable panel inside the window.
		SectionConfiguration = SectionConfiguration or {}
		SectionConfiguration.Title = SectionConfiguration.Title or "Section"

		local Section = {}
		Section._Title = SectionConfiguration.Title
		Section._Elements = {}
		-- Geometry receives harmless defaults immediately because a PreRender
		-- frame or pointer event may arrive while a batched interface is still
		-- constructing its section tree. RecalculateLayout replaces these values
		-- with the final column geometry before the section becomes interactive.
		Section._PositionX = 0
		Section._PositionY = 0
		Section._Width = 0
		Section._ContentHeight = 0
		Section._FullContentHeight = 0
		Section._IsHovered = false
		-- Keep the authored limit separately from its scaled screen-space value.
		-- A viewport change can then rebuild every section limit from the original
		-- number instead of repeatedly scaling an already scaled result.
		Section._BaseMaximumHeight = tonumber(SectionConfiguration.MaxHeight)
		Section._MaxHeight = Section._BaseMaximumHeight
			and Section._BaseMaximumHeight * (Window._CurrentViewportScale or 1)
			or nil
		Section._SectionScrollOffset = 0
		Section._SectionMaxScroll = 0
		Section._DraggingScrollbar = false
		Section._ScrollbarHovered = false

		local PageIndex = SectionConfiguration._PageIndex
		if not PageIndex and #Window._Pages > 0 then
			PageIndex = 1
		end

		Section._Index = PageIndex
			and (#Window._Pages[PageIndex].Sections + 1)
			or (#Window._Sections + 1)
		if PageIndex then
			Section._PageIndex = PageIndex
			table.insert(Window._Pages[PageIndex].Sections, Section)
		end

		if not UseImmediateMode and DrawingBackendAvailable then
			Section._FullBackground = CreateRectangleDrawing(Theme.SectionBodyBackground, true, 4, 1)
			Section._Background = CreateRectangleDrawing(Theme.SectionBackground, true, 5, 0.95)
			Section._Border = CreateRectangleDrawing(Theme.WindowBorder, false, 6, 0.6)
			Section._TextLabel = CreateTextDrawing(SectionConfiguration.Title, Theme.SectionFontSize, Theme.SectionText, 7)
			Section._IndexTextLabel = CreateTextDrawing(
				string.format("%02d", Section._Index),
				Theme.SectionMetaFontSize,
				Theme.TextBoxPlaceholder,
				7
			)
			Section._AccentLine = CreateTrackedDrawingObject("Line")
			ApplyDrawingProperties(Section._AccentLine, {
				Thickness = 1,
				Transparency = 0.7,
				Color = Theme.TitleBarSeparator,
				ZIndex = 8,
				Visible = false,
			})
			Section._LeftAccentLine = CreateTrackedDrawingObject("Line")
			ApplyDrawingProperties(Section._LeftAccentLine, {
				Thickness = 2,
				Transparency = 0.8,
				Color = Theme.TitleBarSeparator,
				ZIndex = 8,
				Visible = false,
			})
			if Section._MaxHeight then
				Section._ScrollbarTrack = CreateRectangleDrawing(Theme.ScrollbarBackground, true, 8, 1)
				Section._ScrollbarHandle = CreateRectangleDrawing(Theme.ScrollbarHandle, true, 9, 1)
			end
		end

		function Section:CreateTextLabel(LabelConfiguration)
			-- Text labels can wrap across multiple Drawing text objects and can be
			-- clicked for copy-style callbacks.
			LabelConfiguration = LabelConfiguration or {}
			LabelConfiguration.Text = LabelConfiguration.Text or "Label"
			local HasExplicitCallback = typeof(LabelConfiguration.Callback) == "function"
			LabelConfiguration.Callback = LabelConfiguration.Callback or function() end

			local Element = {}
			Element._Section = Section
			Element._Type = "TextLabel"
			Element._Height = TextBlockHeight(1, Theme.ElementFontSize)
			Element._Text = LabelConfiguration.Text
			Element._Callback = LabelConfiguration.Callback
			Element._Interactive = HasExplicitCallback
			Element._PositionX = 0
			Element._PositionY = 0
			Element._Width = 0
			Element._IsHovered = false
			ConfigureElementTooltip(Element, LabelConfiguration)
			ConfigureElementExecutorRequirements(Element, LabelConfiguration)

			Element._LineDrawings = {}
			Element._InlineVisualDrawings = {}

			if not UseImmediateMode and DrawingBackendAvailable then

				Element._TextDrawing = nil
				Element._AccentLineDrawing = CreateTrackedDrawingObject("Line")
				ApplyDrawingProperties(Element._AccentLineDrawing, {
					Thickness = 1,
					Transparency = 0.4,
					Color = Theme.SectionText,
					ZIndex = 10,
					Visible = false,
				})
			end

			local function DestroyLineDrawings()
				-- Wrapped text is rebuilt when width or text changes, so stale line
				-- objects must be removed before creating new ones.
				for LineIndex, LineDrawingObject in ipairs(Element._LineDrawings) do
					DestroyDrawing(LineDrawingObject, WindowTrackedDrawings)
				end
				Element._LineDrawings = {}
				for VisualIndex, VisualData in ipairs(Element._InlineVisualDrawings) do
					DestroyDrawing(VisualData.DrawingObject, WindowTrackedDrawings)
				end
				Element._InlineVisualDrawings = {}
			end

			function Element:_RebuildLineDrawings(WrappedLines)
				DestroyLineDrawings()
				if UseImmediateMode or not DrawingBackendAvailable then return end
				for LineIndex, LineText in ipairs(WrappedLines) do
					local RenderText, InlineVisuals = Theme:ParseInlineVisualLine(LineText, Theme.ElementFontSize)
					local LineDrawingObject = CreateTextDrawing(RenderText, Theme.ElementFontSize, Theme.LabelText, 10)
					table.insert(Element._LineDrawings, LineDrawingObject)
					for VisualIndex, VisualData in ipairs(InlineVisuals) do
						local VisualRadius = math.max(3, Theme.ElementFontSize * 0.32)
						local InlineDrawingObject = CreateTrackedDrawingObject("Circle")
						ApplyDrawingProperties(InlineDrawingObject, {
							Filled = true,
							Radius = VisualRadius,
							NumSides = 64,
							Transparency = 1,
							Color = VisualData.Color,
							ZIndex = 11,
							Visible = false,
						})
						table.insert(Element._InlineVisualDrawings, {
							LineIndex = LineIndex,
							ColumnIndex = VisualData.ColumnIndex,
							CharacterWidth = VisualData.CharacterWidth,
							Color = VisualData.Color,
							Radius = VisualRadius,
							DrawingObject = InlineDrawingObject,
						})
					end
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

		function Section:CreateTextBox(TextBoxConfiguration)
			-- Text boxes support focus, selection, clipboard paste, cursor blink,
			-- and callback updates when their value changes.
			TextBoxConfiguration = TextBoxConfiguration or {}
			TextBoxConfiguration.Text = TextBoxConfiguration.Text or "TextBox"
			TextBoxConfiguration.Default = TextBoxConfiguration.Default or ""
			TextBoxConfiguration.Placeholder = TextBoxConfiguration.Placeholder or string.format("Type here%s", AsciiEllipsis)
			TextBoxConfiguration.Callback = TextBoxConfiguration.Callback or function() end
			TextBoxConfiguration.SuggestionProvider = TextBoxConfiguration.SuggestionProvider or nil
			TextBoxConfiguration.SuggestionCallback = TextBoxConfiguration.SuggestionCallback or nil
			TextBoxConfiguration.MaximumSuggestions = TextBoxConfiguration.MaximumSuggestions or 5

			local Element = {}
			Element._Section = Section
			Element._Type = "TextBox"
			Element._Height = Theme.ElementHeight
			Element._Text = TextBoxConfiguration.Text
			Element._Value = TextBoxConfiguration.Default
			Element._Placeholder = TextBoxConfiguration.Placeholder
			Element._Callback = TextBoxConfiguration.Callback
			Element._SuggestionProvider = TextBoxConfiguration.SuggestionProvider
			Element._SuggestionCallback = TextBoxConfiguration.SuggestionCallback
			Element._MaximumSuggestions = TextBoxConfiguration.MaximumSuggestions
			Element._Suggestions = {}
			Element._HoveredSuggestionIndex = nil
			Element._KeyboardSuggestionIndex = nil
			Element._SuggestionDropdownRegion = nil
			Element._TextBoxLayout = TextBoxConfiguration.Layout or "Automatic"
			Element._IsFocused = false
			Element._IsSelected = false
			Element._CursorIndex = #Element._Value + 1
			Element._SelectionStartIndex = nil
			Element._SelectionEndIndex = nil
			Element._SelectionAnchorIndex = Element._CursorIndex
			Element._SelectionDragging = false
			Element._PositionX = 0
			Element._PositionY = 0
			Element._Width = 0

			Element._CursorVisible = false
			Element._CursorBlinkTime = 0
			Element._IsHovered = false
			Element._DisplayOffset = 1
			ConfigureElementTooltip(Element, TextBoxConfiguration)
			ConfigureElementExecutorRequirements(Element, TextBoxConfiguration)

			if not UseImmediateMode and DrawingBackendAvailable then
				Element._BackgroundDrawing = CreateRectangleDrawing(Theme.TextBoxBackground, true, 10, 0.95)
				Element._BorderDrawing = CreateRectangleDrawing(Theme.TextBoxBorder, false, 11, 0.7)
				Element._LabelDrawing = CreateTextDrawing(string.format("%s: ", TextBoxConfiguration.Text), Theme.ElementFontSize, Theme.LabelText, 12)
				Element._TextDrawing = CreateTextDrawing(TextBoxConfiguration.Default ~= "" and TextBoxConfiguration.Default or TextBoxConfiguration.Placeholder, Theme.ElementFontSize, TextBoxConfiguration.Default ~= "" and Theme.TextBoxText or Theme.TextBoxPlaceholder, 12)
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

				Element._SuggestionBackgroundDrawing = CreateRectangleDrawing(Theme.DropdownBackground, true, 20, 0.98)
				Element._SuggestionBorderDrawing = CreateRectangleDrawing(Theme.DropdownBorder, false, 21, 0.85)
				Element._SuggestionRows = {}
				ApplyDrawingProperties(Element._SuggestionBackgroundDrawing, { Visible = false })
				ApplyDrawingProperties(Element._SuggestionBorderDrawing, { Visible = false })
				for SuggestionRowIndex = 1, Element._MaximumSuggestions do
					local SuggestionHoverDrawing = CreateRectangleDrawing(Theme.DropdownItemHover, true, 21, 0.75)
					local SuggestionTextDrawing = CreateTextDrawing("", Theme.ElementFontSize, Theme.DropdownText, 22)
					ApplyDrawingProperties(SuggestionHoverDrawing, { Visible = false })
					ApplyDrawingProperties(SuggestionTextDrawing, { Visible = false })
					Element._SuggestionRows[SuggestionRowIndex] = {
						HoverDrawing = SuggestionHoverDrawing,
						TextDrawing = SuggestionTextDrawing,
					}
				end
			end

			function Element:SetValue(NewValue, SuppressCallback, ForceCallback)
				local NormalizedValue = tostring(NewValue or "")
				local ValueChanged = Element._Value ~= NormalizedValue
				Element._Value = NormalizedValue
				if not Element._IsFocused then
					Element._CursorIndex = #Element._Value + 1
					Element._SelectionAnchorIndex = Element._CursorIndex
					Element._DisplayOffset = 1
				end
				Element._CursorIndex = ClampTextBoxCursorIndex(Element, Element._CursorIndex)
				Element._SelectionAnchorIndex = ClampTextBoxCursorIndex(Element, Element._SelectionAnchorIndex)
				if Element._TextDrawing then
					local HasValue = Element._Value ~= ""
					SetRenderProperty(Element._TextDrawing, "Text", HasValue and Element._Value or Element._Placeholder)
					SetRenderProperty(Element._TextDrawing, "Color", HasValue and Theme.TextBoxText or Theme.TextBoxPlaceholder)
				end
				if ValueChanged then
					Element:RefreshSuggestions()
				end
				Window:SynchronizeNativeTextInputValue(Element)
				if not SuppressCallback and (ValueChanged or ForceCallback) then
					InvokeCallback(Element._Callback, Element._Value)
				end
			end

			function Element:GetValue()
				return Element._Value
			end

			function Element:SetPlaceholder(NewPlaceholder)
				-- Placeholders are mutable because dependent controls can change the
				-- expected input format at runtime. Retained and immediate renderers
				-- both read the same normalized field, while an empty retained text
				-- box is refreshed immediately so no extra layout pass is required.
				Element._Placeholder = tostring(NewPlaceholder or "")
				if Element._Value == "" and Element._TextDrawing then
					SetRenderProperty(Element._TextDrawing, "Text", Element._Placeholder)
					SetRenderProperty(Element._TextDrawing, "Color", Theme.TextBoxPlaceholder)
				end
			end

			function Element:SetSuggestionProvider(NewSuggestionProvider)
				Element._SuggestionProvider = NewSuggestionProvider
				Element:RefreshSuggestions()
			end

			function Element:RefreshSuggestions()
				local PreviousSuggestionCount = #Element._Suggestions
				table.clear(Element._Suggestions)
				Element._HoveredSuggestionIndex = nil
				Element._KeyboardSuggestionIndex = nil

				if typeof(Element._SuggestionProvider) ~= "function" or Element._Value == "" then
					if PreviousSuggestionCount > 0 then
						Window:RecalculateLayout()
					end
					return
				end

				local Success, Suggestions = pcall(Element._SuggestionProvider, Element._Value)
				if not Success or typeof(Suggestions) ~= "table" then
					if PreviousSuggestionCount > 0 then
						Window:RecalculateLayout()
					end
					return
				end

				for SuggestionIndex, SuggestionValue in ipairs(Suggestions) do
					if #Element._Suggestions >= Element._MaximumSuggestions then
						break
					end

					if SuggestionValue ~= nil then
						Element._Suggestions[#Element._Suggestions + 1] = tostring(SuggestionValue)
					end
				end

				if PreviousSuggestionCount ~= #Element._Suggestions then
					Window:RecalculateLayout()
				end
			end

			function Element:ApplySuggestion(SuggestionIndex)
				local SuggestionText = Element._Suggestions[SuggestionIndex]
				if not SuggestionText then
					return false
				end

				Element:SetValue(SuggestionText)
				Element._IsFocused = false
				Element._CursorVisible = false
				Element._HoveredSuggestionIndex = nil
				Element._KeyboardSuggestionIndex = nil
				Element._SuggestionDropdownRegion = nil

				if typeof(Element._SuggestionCallback) == "function" then
					InvokeCallback(Element._SuggestionCallback, SuggestionText)
				end

				Window:RecalculateLayout()

				return true
			end

			table.insert(Section._Elements, Element)
			Window:RecalculateLayout()
			return Element
		end

		function Section:CreateTextButton(ButtonConfiguration)
			-- Buttons are simple clickable commands with hover animation and an
			-- optional accent line.
			ButtonConfiguration = ButtonConfiguration or {}
			ButtonConfiguration.Text = ButtonConfiguration.Text or "Button"
			ButtonConfiguration.Callback = ButtonConfiguration.Callback or function() end

			local Element = {}
			Element._Section = Section
			Element._Type = "TextButton"
			Element._Height = Theme.ElementHeight
			Element._Text = ButtonConfiguration.Text
			Element._Callback = ButtonConfiguration.Callback
			Element._IsHovered = false
			Element._PositionX = 0
			Element._PositionY = 0
			Element._Width = 0
			ConfigureElementTooltip(Element, ButtonConfiguration)
			ConfigureElementExecutorRequirements(Element, ButtonConfiguration)

			if not UseImmediateMode and DrawingBackendAvailable then
				Element._BackgroundDrawing = CreateRectangleDrawing(Theme.ButtonBackground, true, 10, 0.95)
				Element._BorderDrawing = CreateRectangleDrawing(Theme.ButtonBorder, false, 11, 0.7)
				Element._TextDrawing = CreateTextDrawing(ButtonConfiguration.Text, Theme.ElementFontSize, Theme.ButtonText, 12)
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

		function Section:CreateToggle(ToggleConfiguration)
			-- Toggles store a boolean value and expose SetValue/GetValue helpers so
			-- external configuration code can synchronize them.
			ToggleConfiguration = ToggleConfiguration or {}
			ToggleConfiguration.Text = ToggleConfiguration.Text or "Toggle"
			ToggleConfiguration.Default = ToggleConfiguration.Default ~= nil and ToggleConfiguration.Default or false
			ToggleConfiguration.Callback = ToggleConfiguration.Callback or function() end

			local Element = {}
			Element._Section = Section
			Element._Type = "Toggle"
			Element._Height = Theme.ElementHeight
			Element._Text = ToggleConfiguration.Text
			Element._Value = ToggleConfiguration.Default
			Element._Callback = ToggleConfiguration.Callback
			Element._IsHovered = false
			Element._PositionX = 0
			Element._PositionY = 0
			Element._Width = 0
			ConfigureElementTooltip(Element, ToggleConfiguration)
			ConfigureElementExecutorRequirements(Element, ToggleConfiguration)

			if not UseImmediateMode and DrawingBackendAvailable then
				Element._BackgroundDrawing = CreateRectangleDrawing(Theme.ButtonBackground, true, 10, 0.95)
				Element._BorderDrawing = CreateRectangleDrawing(Theme.ButtonBorder, false, 11, 0.7)
				Element._TextDrawing = CreateTextDrawing(ToggleConfiguration.Text, Theme.ElementFontSize, Theme.ButtonText, 12)

				Element._IndicatorDrawing = CreateTrackedDrawingObject("Circle")
				ApplyDrawingProperties(Element._IndicatorDrawing, {
					Filled = true,
					Radius = Theme.ToggleIndicatorRadius,
					NumSides = 48,
					Transparency = 1,
					ZIndex = 13,
					Visible = false,
					Color = ToggleConfiguration.Default and Theme.ToggleActive or Theme.ToggleInactive,
				})
			end

			function Element:SetValue(NewValue, SuppressCallback, ForceCallback)
				local NormalizedValue = NewValue == true
				local ValueChanged = Element._Value ~= NormalizedValue
				Element._Value = NormalizedValue
				if Element._IndicatorDrawing then
					SetRenderProperty(Element._IndicatorDrawing, "Color",
						NormalizedValue and Theme.ToggleActive or Theme.ToggleInactive)
				end
				if not SuppressCallback and (ValueChanged or ForceCallback) then
					InvokeCallback(Element._Callback, NormalizedValue)
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

		function Section:CreateDropdown(DropdownConfiguration)
			-- Dropdowns render their options below the main element and temporarily
			-- increase layout height while expanded.
			DropdownConfiguration = DropdownConfiguration or {}
			DropdownConfiguration.Text = DropdownConfiguration.Text or "Select"
			DropdownConfiguration.Options = DropdownConfiguration.Options or {}
			DropdownConfiguration.Default = DropdownConfiguration.Default or (DropdownConfiguration.Options[1] or "")
			DropdownConfiguration.Callback = DropdownConfiguration.Callback or function() end
			DropdownConfiguration.MultiSelect = DropdownConfiguration.MultiSelect == true

			local Element = {}
			Element._Section = Section
			Element._Type = "Dropdown"
			Element._Height = Theme.ElementHeight
			Element._Text = DropdownConfiguration.Text
			Element._Options = DropdownConfiguration.Options
			Element._Value = DropdownConfiguration.Default
			Element._Callback = DropdownConfiguration.Callback
			Element._MultiSelect = DropdownConfiguration.MultiSelect
			Element._SelectedValues = {}
			Element._Expanded = false
			Element._IsHovered = false
			Element._ItemDrawingObjects = {}
			Element._MaximumVisibleItems = DropdownConfiguration.MaximumVisibleItems or 8
			Element._OptionsScrollOffset = 0
			Element._OptionsRegion = nil
			Element._PositionX = 0
			Element._PositionY = 0
			Element._Width = 0
			ConfigureElementTooltip(Element, DropdownConfiguration)
			ConfigureElementExecutorRequirements(Element, DropdownConfiguration)

			-- Multi-select dropdowns keep a set internally while exposing a stable array
			-- in option order. Ordinary dropdown behavior remains unchanged.
			local function NormalizeSelectionSet(SelectionValues)
				local SelectionSet = {}
				if type(SelectionValues) == "table" then
					for SelectionKey, SelectionValue in pairs(SelectionValues) do
						if type(SelectionKey) == "number" then
							SelectionSet[tostring(SelectionValue)] = true
						elseif SelectionValue == true then
							SelectionSet[tostring(SelectionKey)] = true
						end
					end
				elseif SelectionValues ~= nil then
					SelectionSet[tostring(SelectionValues)] = true
				end
				return SelectionSet
			end

			local function GetSelectedValueArray()
				local SelectedValues = {}
				for OptionIndex, OptionValue in ipairs(Element._Options) do
					if Element._SelectedValues[tostring(OptionValue)] then
						SelectedValues[#SelectedValues + 1] = OptionValue
					end
				end
				return SelectedValues
			end

			local function GetMultiSelectSummary()
				local SelectedValues = GetSelectedValueArray()
				if #SelectedValues == 0 then
					return "None"
				end
				if #SelectedValues <= 3 then
					local DisplayValues = {}
					for SelectionIndex, SelectionValue in ipairs(SelectedValues) do
						DisplayValues[SelectionIndex] = tostring(SelectionValue)
					end
					return table.concat(DisplayValues, ", ")
				end
				return string.format("%d selected", #SelectedValues)
			end

			function Element:GetOptionDisplayText(OptionValue)
				if not Element._MultiSelect then
					return tostring(OptionValue)
				end
				return string.format(
					"[%s] %s",
					Element._SelectedValues[tostring(OptionValue)] and "x" or " ",
					tostring(OptionValue)
				)
			end

			function Element:GetDisplayValueText()
				return Element._MultiSelect and GetMultiSelectSummary() or tostring(Element._Value)
			end

			local function RefreshDropdownText()
				local DisplayValue = Element:GetDisplayValueText()
				if Element._TextDrawing then
					SetRenderProperty(
						Element._TextDrawing,
						"Text",
						string.format("%s: %s", DropdownConfiguration.Text, DisplayValue)
					)
				end
				for ItemIndex, ItemData in ipairs(Element._ItemDrawingObjects) do
					if ItemData.TextDrawing then
						SetRenderProperty(
							ItemData.TextDrawing,
							"Text",
							Element:GetOptionDisplayText(ItemData.Value)
						)
					end
				end
			end

			if Element._MultiSelect then
				Element._SelectedValues = NormalizeSelectionSet(DropdownConfiguration.Default)
				Element._Value = GetSelectedValueArray()
			end

			if not UseImmediateMode and DrawingBackendAvailable then
				Element._BackgroundDrawing = CreateRectangleDrawing(Theme.DropdownBackground, true, 10, 0.95)
				Element._BorderDrawing = CreateRectangleDrawing(Theme.DropdownBorder, false, 11, 0.7)
				Element._TextDrawing = CreateTextDrawing(
					string.format(
						"%s: %s",
						DropdownConfiguration.Text,
						Element._MultiSelect and GetMultiSelectSummary() or tostring(DropdownConfiguration.Default)
					),
					Theme.ElementFontSize,
					Theme.DropdownText,
					12
				)
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

			for OptionIndex, OptionText in ipairs(DropdownConfiguration.Options) do
				local ItemData = {
					Value = OptionText,
					_PositionX = 0,
					_PositionY = 0,
					_Width = 0,
				}

				if not UseImmediateMode and DrawingBackendAvailable then
					local ItemBackground = CreateRectangleDrawing(Theme.DropdownItemBackground, true, 20, 0.95)
					ApplyDrawingProperties(ItemBackground, { Visible = false })

					local ItemText = CreateTextDrawing(
						Element:GetOptionDisplayText(OptionText),
						Theme.ElementFontSize,
						Theme.DropdownText,
						21
					)
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
					Element._OptionsRegion = nil
				end

				ClampDropdownScrollOffset(Element)

				if Element._ArrowDrawing then
					SetRenderProperty(Element._ArrowDrawing, "Text", Element._Expanded and "^" or "v")
				end

				for ItemIndex, ItemData in ipairs(Element._ItemDrawingObjects) do
					local ShouldBeVisible = Element._Expanded and Window._Visible
					SetDrawingObjectsVisibility({ ItemData.BackgroundDrawing, ItemData.TextDrawing }, ShouldBeVisible)
				end

				Window:RecalculateLayout()
			end

			function Element:SetSelections(NewSelections, SuppressCallback, ForceCallback)
				if not Element._MultiSelect then
					Element:SetValue(NewSelections, SuppressCallback, ForceCallback)
					return
				end

				local PreviousSelections = GetSelectedValueArray()
				Element._SelectedValues = NormalizeSelectionSet(NewSelections)
				Element._Value = GetSelectedValueArray()
				RefreshDropdownText()

				local ValueChanged = #PreviousSelections ~= #Element._Value
				if not ValueChanged then
					for SelectionIndex, SelectionValue in ipairs(Element._Value) do
						if PreviousSelections[SelectionIndex] ~= SelectionValue then
							ValueChanged = true
							break
						end
					end
				end

				if (ValueChanged or ForceCallback) and not SuppressCallback then
					InvokeCallback(Element._Callback, table.clone(Element._Value))
				end
			end

			function Element:ToggleSelection(OptionValue, SuppressCallback)
				if not Element._MultiSelect then
					Element:SetValue(OptionValue, SuppressCallback)
					return
				end
				local OptionKey = tostring(OptionValue)
				Element._SelectedValues[OptionKey] = not Element._SelectedValues[OptionKey] or nil
				Element._Value = GetSelectedValueArray()
				RefreshDropdownText()
				if not SuppressCallback then
					InvokeCallback(Element._Callback, table.clone(Element._Value))
				end
			end

			function Element:SetValue(NewValue, SuppressCallback, ForceCallback)
				if Element._MultiSelect then
					Element:SetSelections(NewValue, SuppressCallback, ForceCallback)
					return
				end
				local ValueChanged = Element._Value ~= NewValue
				Element._Value = NewValue
				RefreshDropdownText()
				if (ValueChanged or ForceCallback) and not SuppressCallback then
					InvokeCallback(Element._Callback, NewValue)
				end
			end

			function Element:GetValue()
				return Element._MultiSelect and table.clone(Element._Value) or Element._Value
			end

			function Element:SetOptions(NewOptions, NewDefault, ForceCallback, SuppressCallback)
				-- Dynamic data such as marketplace products and class folders can
				-- arrive after the dropdown is created. Rebuilding the item model
				-- keeps async sections from needing to recreate the whole control.
				-- Programmatic refreshes may suppress their callback when the caller
				-- applies the matching state itself immediately after this method.
				if Element._Expanded then
					Element:Toggle()
				end
				Element._OptionsScrollOffset = 0
				Element._OptionsRegion = nil

				for ItemIndex, ItemData in ipairs(Element._ItemDrawingObjects) do
					DestroyDrawing(ItemData.BackgroundDrawing, WindowTrackedDrawings)
					DestroyDrawing(ItemData.TextDrawing, WindowTrackedDrawings)
					DestroyDrawing(ItemData.SeparatorDrawing, WindowTrackedDrawings)
				end

				local PreviousValue = Element._Value
				local NormalizedOptions = {}
				for OptionIndex, OptionValue in ipairs(NewOptions or {}) do
					NormalizedOptions[OptionIndex] = OptionValue
				end
				Element._Options = NormalizedOptions
				Element._ItemDrawingObjects = {}

				if Element._MultiSelect then
					local RequestedSelections = NewDefault ~= nil and NewDefault or PreviousValue
					Element._SelectedValues = NormalizeSelectionSet(RequestedSelections)
					Element._Value = GetSelectedValueArray()
				end

				local PreviousValueStillExists = false
				local RequestedDefaultExists = false
				for OptionIndex, OptionValue in ipairs(Element._Options) do
					if OptionValue == PreviousValue then
						PreviousValueStillExists = true
					end
					if NewDefault ~= nil and OptionValue == NewDefault then
						RequestedDefaultExists = true
					end
				end
				if not Element._MultiSelect then
					if RequestedDefaultExists then
						Element._Value = NewDefault
					elseif PreviousValueStillExists then
						Element._Value = PreviousValue
					else
						Element._Value = Element._Options[1] or ""
					end
				end

				for OptionIndex, OptionText in ipairs(Element._Options) do
					local ItemData = {
						Value = OptionText,
						_PositionX = 0,
						_PositionY = 0,
						_Width = 0,
					}

					if not UseImmediateMode and DrawingBackendAvailable then
						local ItemBackground = CreateRectangleDrawing(Theme.DropdownItemBackground, true, 20, 0.95)
						ApplyDrawingProperties(ItemBackground, { Visible = false })

						local ItemText = CreateTextDrawing(
							Element:GetOptionDisplayText(OptionText),
							Theme.ElementFontSize,
							Theme.DropdownText,
							21
						)
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

				RefreshDropdownText()

				if not SuppressCallback then
					if Element._MultiSelect then
						if ForceCallback then
							InvokeCallback(Element._Callback, table.clone(Element._Value))
						end
					elseif Element._Value ~= PreviousValue or ForceCallback then
						InvokeCallback(Element._Callback, Element._Value)
					end
				end
				Window:RecalculateLayout()
			end

			table.insert(Section._Elements, Element)
			Window:RecalculateLayout()
			return Element
		end

		function Section:CreateSlider(SliderConfiguration)
			-- Sliders map horizontal mouse position to a snapped numeric value.
			SliderConfiguration = SliderConfiguration or {}
			SliderConfiguration.Text = SliderConfiguration.Text or "Slider"
			SliderConfiguration.Min = SliderConfiguration.Min or 0
			SliderConfiguration.Max = SliderConfiguration.Max or 100
			SliderConfiguration.Default = SliderConfiguration.Default or SliderConfiguration.Min
			SliderConfiguration.Increment = SliderConfiguration.Increment or 1
			SliderConfiguration.Callback = SliderConfiguration.Callback or function() end

			local Element = {}
			Element._Section = Section
			Element._Type = "Slider"
			Element._Height = Theme.ElementHeight + 10
			Element._Text = SliderConfiguration.Text
			Element._MinValue = SliderConfiguration.Min
			Element._MaxValue = SliderConfiguration.Max
			Element._Value = SliderConfiguration.Default
			Element._IncrementStep = SliderConfiguration.Increment
			Element._Callback = SliderConfiguration.Callback
			Element._TrackPositionX = 0
			Element._TrackPositionY = 0
			Element._TrackTotalWidth = 0
			Element._TrackTotalHeight = 6
			Element._PositionX = 0
			Element._PositionY = 0
			Element._Width = 0
			Element._IsHovered = false
			ConfigureElementTooltip(Element, SliderConfiguration)
			ConfigureElementExecutorRequirements(Element, SliderConfiguration)
			Element._IsThumbHovered = false

			local function SnapToIncrement(RawValue)
				-- Snapping happens before clamping so increments behave predictably
				-- near both ends of the range.
				local SnappedValue = math.floor((RawValue - Element._MinValue) / Element._IncrementStep + 0.5) * Element._IncrementStep + Element._MinValue
				return math.clamp(SnappedValue, Element._MinValue, Element._MaxValue)
			end

			if not UseImmediateMode and DrawingBackendAvailable then
				Element._LabelDrawing = CreateTextDrawing(SliderConfiguration.Text, Theme.ElementFontSize, Theme.SliderText, 10)
				Element._ValueTextDrawing = CreateTextDrawing(tostring(SliderConfiguration.Default), Theme.ElementFontSize, Theme.SectionText, 10)
				Element._TrackBackgroundDrawing = CreateRectangleDrawing(Theme.SliderTrackBackground, true, 10, 0.95)
				Element._TrackBorderDrawing = CreateRectangleDrawing(Theme.SliderBorder, false, 11, 0.6)
				Element._TrackFillDrawing = CreateRectangleDrawing(Theme.SliderTrackFill, true, 12, 0.95)

				Element._ThumbDrawing = CreateTrackedDrawingObject("Circle")
				ApplyDrawingProperties(Element._ThumbDrawing, {
					-- The slider uses one solid accent-colored thumb. A previous
					-- secondary inner circle created a white ring around the active
					-- color and made the control visually inconsistent with toggles.
					Color = Theme.SliderTrackFill,
					Filled = true,
					Radius = 7,
					NumSides = 48,
					Transparency = 1,
					ZIndex = 13,
					Visible = false,
				})
			end

			function Element:SetValue(NewValue, SuppressCallback)
				NewValue = SnapToIncrement(NewValue)
				Element._Value = NewValue

				if Element._ValueTextDrawing then
					SetRenderProperty(Element._ValueTextDrawing, "Text", tostring(NewValue))
				end

				if not UseImmediateMode and DrawingBackendAvailable then
					Window:RecalculateLayout()
				end

				if not SuppressCallback then
					InvokeCallback(Element._Callback, NewValue)
				end
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

		function Section:CreateColorPicker(ColorPickerConfiguration)
			-- Color pickers keep a compact swatch in the section and open a
			-- larger popup palette when the user wants to choose a new value.
			ColorPickerConfiguration = ColorPickerConfiguration or {}
			ColorPickerConfiguration.Text = ColorPickerConfiguration.Text or "Color"
			ColorPickerConfiguration.Default = ColorPickerConfiguration.Default or Color3.fromRGB(255, 255, 255)
			ColorPickerConfiguration.Callback = ColorPickerConfiguration.Callback or function() end

			local Element = {}
			Element._Section = Section
			Element._Type = "ColorPicker"
			Element._Height = Theme.ElementHeight
			Element._Text = ColorPickerConfiguration.Text
			Element._Value = ColorPickerConfiguration.Default
			Element._Callback = ColorPickerConfiguration.Callback
			Element._SwatchDrawingObjects = {}
			Element._SelectedSwatchIndex = nil
			Element._PositionX = 0
			Element._PositionY = 0
			Element._Width = 0
			Element._IsHovered = false
			Element._HoveredSwatchIndex = nil
			ConfigureElementTooltip(Element, ColorPickerConfiguration)
			ConfigureElementExecutorRequirements(Element, ColorPickerConfiguration)

			for PaletteIndex, PaletteColor in ipairs(ColorPalette) do
				if PaletteColor == ColorPickerConfiguration.Default then
					Element._SelectedSwatchIndex = PaletteIndex
					break
				end
			end

			if not UseImmediateMode and DrawingBackendAvailable then
				Element._LabelDrawing = CreateTextDrawing(ColorPickerConfiguration.Text, Theme.ElementFontSize, Theme.LabelText, 10)
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
		if Window._Destroyed or Window._Destroying then
			return
		end
		Window._Destroying = true

		-- OnExit belongs to the lifecycle itself, not only to the close button.
		-- Programmatic destruction now performs the same application cleanup and
		-- the guard above guarantees that the callback runs exactly once.
		InvokeCallback(Window.OnExit)

		-- Close temporary panels before destroying drawing objects. Their close
		-- methods clear active state and remove popup-specific drawings through
		-- the same code path used during normal interaction.
		if Window._ActiveDropdown then
			Window._ActiveDropdown:Toggle()
		end
		if Window._ActiveColorPicker then
			Window._ActiveColorPicker:ClosePopup()
		end
		Window:DestroyNativeTextInput()

		DestroyAllTrackedDrawings()

		for EntryIndex = #Window._ActiveNotifications, 1, -1 do
			local Entry = Window._ActiveNotifications[EntryIndex]
			DestroyDrawing(Entry.Background, NotificationTrackedDrawings)
			DestroyDrawing(Entry.Border, NotificationTrackedDrawings)
			DestroyDrawing(Entry.AccentLine, NotificationTrackedDrawings)
			for TextLineIndex, NotificationTextLabel in ipairs(Entry.TextLabels or {}) do
				DestroyDrawing(NotificationTextLabel, NotificationTrackedDrawings)
			end
			table.remove(Window._ActiveNotifications, EntryIndex)
		end

		Window:SetInputBlocking("Scroll", false)
		Window:SetInputBlocking("Camera", false)
		Window:SetInputBlocking("Interface", false)
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
		Window._Destroying = false
	end

	local PreviousMouseButtonState = false
	local PreviousSecondaryMouseButtonState = false
	local QueuedPrimaryClick = false
	local QueuedPrimaryClickPosition = nil
	local PrimaryMouseButtonHeld = false

	local WindowHasFocus = true
	local UpdateHoverState

	local function GetWindowResizeLimits()
		local Camera = GetCurrentCamera()
		local ViewportSize = Camera and Camera.ViewportSize or Vector2.new(1920, 1080)
		if Window._TouchInputAvailable then
			local MaximumWidth = math.max(180, ViewportSize.X - 16)
			local MaximumVisibleHeight = math.max(180, ViewportSize.Y - Theme.TitleBarHeight - 16)
			return {
				MinimumWidth = math.min(300, MaximumWidth),
				MinimumVisibleHeight = math.min(240, MaximumVisibleHeight),
				MaximumWidth = MaximumWidth,
				MaximumVisibleHeight = MaximumVisibleHeight,
			}
		end

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
		local CurrentScale = Window._CurrentViewportScale
			or (BaseWindowWidth ~= 0 and (Theme.WindowWidth / BaseWindowWidth) or 1)
		if CurrentScale == 0 then
			CurrentScale = 1
		end

		Theme.WindowWidth = ClampedWindowWidth
		Theme.WindowVisibleHeight = ClampedVisibleHeight
		Window._HasAppliedDeviceGeometry = true

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

		local TouchPointerIsActive = Window._TouchInteractionState
			and Window._TouchInteractionState.ActiveInputObject ~= nil
		local PointerRequestsCapture = Window._MouseInWindow
			and (not Window._TouchInputAvailable or TouchPointerIsActive)
		local ShouldCaptureInterface = PointerRequestsCapture
			or PrimaryMouseButtonHeld
			or Window._Dragging
			or Window._Resizing
			or Window._ActiveSlider ~= nil
			or Window._ActiveTextSelectionBox ~= nil
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
		if Window._ActiveTextSelectionBox then
			Window._ActiveTextSelectionBox._SelectionDragging = false
			Window._ActiveTextSelectionBox = nil
		end
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
		Window:ReleaseNativeTextInput()
		local ShouldRecalculateLayout = false
		for FocusSectionIndex, FocusSection in ipairs(Window:GetActiveSections()) do
			for FocusElementIndex, FocusElement in ipairs(FocusSection._Elements) do
				if FocusElement._Type == "TextBox" then
					if FocusElement._IsFocused and #FocusElement._Suggestions > 0 then
						ShouldRecalculateLayout = true
					end
					FocusElement._IsFocused = false
					FocusElement._CursorVisible = false
					FocusElement._SelectionDragging = false
					ClearTextBoxSelection(FocusElement)
					FocusElement._HoveredSuggestionIndex = nil
					FocusElement._KeyboardSuggestionIndex = nil
					FocusElement._SuggestionDropdownRegion = nil
				end
			end
		end
		if Window._SearchTextBox then
			Window._SearchTextBox._SelectionDragging = false
			ClearTextBoxSelection(Window._SearchTextBox)
		end
		Window._ActiveTextSelectionBox = nil
		if ShouldRecalculateLayout then
			Window:RecalculateLayout()
		end
	end

	local function GetTextBoxInputMetrics(TextBoxElement, TextBoxPosition, TextBoxWidth)
		-- Mouse selection and rendering share the same geometry values so the
		-- selected range lines up with the visible characters.
		return GetTextBoxLayoutMetrics(TextBoxElement, TextBoxPosition, TextBoxWidth)
	end

	local function BeginTextBoxMouseSelection(TextBoxElement, MousePosition, TextBoxPosition, TextBoxWidth)
		local Metrics = GetTextBoxInputMetrics(TextBoxElement, TextBoxPosition, TextBoxWidth)
		local CursorIndex = GetTextBoxCharacterIndexFromMouseX(
			TextBoxElement,
			MousePosition.X,
			Metrics.InputStartX,
			Metrics.CharacterWidth,
			Metrics.MaximumCharacters
		)

		-- Cursor geometry is prepared before focus so the hidden native editor
		-- opens at the exact character selected through the Drawing control.
		TextBoxElement._SelectionAnchorIndex = CursorIndex
		SetTextBoxCursorIndex(TextBoxElement, CursorIndex)
		ClearTextBoxSelection(TextBoxElement)
		if not Window:FocusNativeTextInput(TextBoxElement) then
			TextBoxElement._IsFocused = false
			TextBoxElement._CursorVisible = false
			TextBoxElement._SelectionDragging = false
			Window._ActiveTextSelectionBox = nil
			return false
		end

		TextBoxElement._IsFocused = true
		TextBoxElement._CursorVisible = true
		TextBoxElement._CursorBlinkTime = tick()
		TextBoxElement._SelectionDragging = true
		Window._ActiveTextSelectionBox = TextBoxElement
		Window:SynchronizeNativeTextInputSelection(TextBoxElement)
		return true
	end

	local function UpdateActiveTextBoxMouseSelection(MousePosition)
		local TextBoxElement = Window._ActiveTextSelectionBox
		if not TextBoxElement or not TextBoxElement._SelectionDragging then
			return
		end

		local TextBoxPosition
		local TextBoxWidth
		if TextBoxElement._IsSearch and Window._SearchTextBoxRegion then
			TextBoxPosition = Window._SearchTextBoxRegion.Position
			TextBoxWidth = Window._SearchTextBoxRegion.Size.X
		else
			TextBoxPosition = Vector2.new(Window._Position.X + TextBoxElement._PositionX, Window._Position.Y + TextBoxElement._PositionY - Window._ScrollOffset)
			TextBoxWidth = Theme:GetElementAvailableWidth(TextBoxElement, Window)
		end

		local Metrics = GetTextBoxInputMetrics(TextBoxElement, TextBoxPosition, TextBoxWidth)
		local CursorIndex = GetTextBoxCharacterIndexFromMouseX(
			TextBoxElement,
			MousePosition.X,
			Metrics.InputStartX,
			Metrics.CharacterWidth,
			Metrics.MaximumCharacters
		)

		SetTextBoxSelectionRange(TextBoxElement, TextBoxElement._SelectionAnchorIndex or CursorIndex, CursorIndex)
		Window:SynchronizeNativeTextInputSelection(TextBoxElement)
	end

	local function SetSearchTextBoxFocus(IsFocused)
		-- Search is not stored inside a section, but it uses the same native
		-- TextBox bridge and focus lifecycle as every regular text field.
		local ShouldFocus = IsFocused == true
		if not ShouldFocus then
			Window:ReleaseNativeTextInput(Window._SearchTextBox)
			Window._SearchTextBox._IsFocused = false
			Window._SearchTextBox._CursorVisible = false
			Window._SearchTextBox._CursorBlinkTime = 0
			Window._SearchTextBox._SelectionDragging = false
			ClearTextBoxSelection(Window._SearchTextBox)
			return false
		end

		if not Window:FocusNativeTextInput(Window._SearchTextBox) then
			Window._SearchTextBox._IsFocused = false
			Window._SearchTextBox._CursorVisible = false
			return false
		end

		Window._SearchTextBox._IsFocused = true
		Window._SearchTextBox._CursorVisible = true
		Window._SearchTextBox._CursorBlinkTime = tick()
		return true
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

	function Window:ResolveTouchScrollTarget(PointerPosition)
		-- Title-bar controls remain tappable, while dragging empty title-bar space
		-- moves the complete window. The resize corner receives the same direct
		-- manipulation treatment so touch users do not need a tiny scrollbar-like
		-- gesture to change the window size.
		if Window._CloseButtonRegion and IsPointInsideRectangle(
			PointerPosition,
			Window._CloseButtonRegion.Position,
			Window._CloseButtonRegion.Size
		) then
			return {
				Kind = "Control",
				ControlName = "Close",
				Region = Window._CloseButtonRegion,
			}
		end
		if Window._SearchButtonRegion and IsPointInsideRectangle(
			PointerPosition,
			Window._SearchButtonRegion.Position,
			Window._SearchButtonRegion.Size
		) then
			return {
				Kind = "Control",
				ControlName = "Search",
				Region = Window._SearchButtonRegion,
			}
		end
		if IsPointInsideRectangle(PointerPosition, Window._ResizeGripRegion.Position, Window._ResizeGripRegion.Size) then
			return { Kind = "Resize" }
		end

		local TitleBarPosition = Window._Position
		local TitleBarSize = Vector2.new(Theme.WindowWidth, Theme.TitleBarHeight)
		if IsPointInsideRectangle(PointerPosition, TitleBarPosition, TitleBarSize) then
			return { Kind = "Title bar" }
		end

		local TabBarPosition = Window._Position + Vector2.new(0, Theme.TitleBarHeight)
		local TabBarSize = Vector2.new(Theme.WindowWidth, Window._TabBarHeight)
		if Window._TabBarHeight > 0 and IsPointInsideRectangle(PointerPosition, TabBarPosition, TabBarSize) then
			return {
				Kind = "Tabs",
				PageIndex = Window:GetPageTabIndexAtPosition(PointerPosition),
			}
		end

		local ActiveDropdown = Window._ActiveDropdown
		if ActiveDropdown and ActiveDropdown._Expanded and ActiveDropdown._OptionsRegion
			and IsPointInsideRectangle(PointerPosition, ActiveDropdown._OptionsRegion.Position, ActiveDropdown._OptionsRegion.Size)
		then
			return { Kind = "Dropdown", Element = ActiveDropdown }
		end

		for SectionIndex, ScrollableSection in ipairs(Window:GetActiveSections()) do
			if ScrollableSection._SectionMaxScroll and ScrollableSection._SectionMaxScroll > 0 then
				local SectionPosition = Window._Position + Vector2.new(
					ScrollableSection._PositionX,
					ScrollableSection._PositionY - Window._ScrollOffset
				)
				local SectionSize = Vector2.new(
					ScrollableSection._Width,
					ScrollableSection._ClippedHeight or ScrollableSection._ContentHeight or 0
				)
				if IsPointInsideRectangle(PointerPosition, SectionPosition, SectionSize) then
					return { Kind = "Section", Section = ScrollableSection }
				end
			end
		end

		return { Kind = "Window" }
	end

	function Window:ApplyTouchMovement(MovementDelta, TotalMovementDelta, TouchTarget)
		if not TouchTarget then
			return
		end

		if TouchTarget.Kind == "Title bar" then
			local StartWindowPosition = Window._TouchInteractionState.StartWindowPosition or Window._Position
			Window._Position = ClampWindowPosition(StartWindowPosition + TotalMovementDelta)
		elseif TouchTarget.Kind == "Resize" then
			local StartWindowSize = Window._TouchInteractionState.StartWindowSize
				or Vector2.new(Theme.WindowWidth, Window._VisibleHeight)
			ApplyWindowSize(
				StartWindowSize.X + TotalMovementDelta.X,
				StartWindowSize.Y + TotalMovementDelta.Y
			)
		elseif TouchTarget.Kind == "Tabs" then
			local TabLayout = GetPageTabLayout(Window, Theme.WindowWidth)
			Window._TabScrollOffset = math.clamp(
				(Window._TabScrollOffset or 0) - MovementDelta.X,
				0,
				TabLayout.MaximumScroll
			)
		elseif TouchTarget.Kind == "Dropdown" and TouchTarget.Element then
			local DropdownElement = TouchTarget.Element
			DropdownElement._OptionsScrollOffset = math.clamp(
				(DropdownElement._OptionsScrollOffset or 0) - MovementDelta.Y,
				0,
				GetDropdownMaximumScroll(DropdownElement)
			)
		elseif TouchTarget.Kind == "Section" and TouchTarget.Section then
			local ScrollableSection = TouchTarget.Section
			local PreviousSectionScrollOffset = ScrollableSection._SectionScrollOffset or 0
			ScrollableSection._SectionScrollOffset = math.clamp(
				PreviousSectionScrollOffset - MovementDelta.Y,
				0,
				ScrollableSection._SectionMaxScroll or 0
			)
			if ScrollableSection._SectionScrollOffset == PreviousSectionScrollOffset then
				-- Once an inner section reaches its boundary, continue the same gesture
				-- through the page canvas instead of making the user lift their finger
				-- and begin a second swipe outside the section.
				Window._ScrollOffset = math.clamp(
					Window._ScrollOffset - MovementDelta.Y,
					0,
					Window._MaxScroll
				)
			end
		elseif TouchTarget.Kind == "Window" then
			Window._ScrollOffset = math.clamp(
				Window._ScrollOffset - MovementDelta.Y,
				0,
				Window._MaxScroll
			)
		end

		Window:RecalculateLayout()
	end

	table.insert(Window._Connections, ConnectSignal(UserInputService.WindowFocusReleased, NewCClosure(function()
		WindowHasFocus = false
		PreviousSecondaryMouseButtonState = false
	end)))
	table.insert(Window._Connections, ConnectSignal(UserInputService.WindowFocused, NewCClosure(function()
		WindowHasFocus = true
	end)))

	function Window:ProcessTouchInput(InputState, InputObject)
		-- ContextActionService is the authoritative mobile path because it continues
		-- receiving touches while Roblox CoreGui is open. UserInputService also calls
		-- this method as an idempotent compatibility path for executors that omit a
		-- ContextActionService Change or End state.
		if Window._Destroyed or not InputObject or InputObject.UserInputType ~= Enum.UserInputType.Touch then
			return false
		end

		local TouchInteractionState = Window._TouchInteractionState
		local CoordinateInset = InputState == Enum.UserInputState.Begin
			and GetTouchInputCoordinateInset()
			or TouchInteractionState.CoordinateInset
			or GetTouchInputCoordinateInset()
		local PointerPosition = GetTouchInputScreenPosition(InputObject, CoordinateInset)

		if InputState == Enum.UserInputState.Begin then
			-- One window interaction owns one finger. Additional fingers pass through
			-- to the game so a camera or movement gesture is not accidentally captured.
			if TouchInteractionState.ActiveInputObject then
				return TouchInteractionState.ActiveInputObject == InputObject
			end

			Window._LastPointerPosition = PointerPosition
			if not Window._Visible or not Library._Visible then
				if Window:IsPointInsideTouchLauncher(PointerPosition) then
					Library._Visible = true
					Window:SetVisible(true)
					Window:RecalculateLayout()
					return true
				end
				return false
			end

			UpdateHoverState(PointerPosition)
			if not Window._MouseInWindow then
				return false
			end

			PrimaryMouseButtonHeld = true
			PreviousMouseButtonState = true
			TouchInteractionState.ActiveInputObject = InputObject
			TouchInteractionState.StartPosition = PointerPosition
			TouchInteractionState.PreviousPosition = PointerPosition
			TouchInteractionState.CurrentPosition = PointerPosition
			TouchInteractionState.CoordinateInset = CoordinateInset
			TouchInteractionState.StartWindowPosition = Window._Position
			TouchInteractionState.StartWindowSize = Vector2.new(Theme.WindowWidth, Window._VisibleHeight)
			TouchInteractionState.GestureDistance = 0
			TouchInteractionState.Scrolling = false
			TouchInteractionState.ScrollTarget = Window:ResolveTouchScrollTarget(PointerPosition)
			QueuedPrimaryClick = false
			QueuedPrimaryClickPosition = nil
			RefreshInterfaceCaptureState()
			return true
		end

		if TouchInteractionState.ActiveInputObject ~= InputObject then
			return false
		end

		if InputState == Enum.UserInputState.Change then
			local PreviousPointerPosition = TouchInteractionState.PreviousPosition or PointerPosition
			local StartPointerPosition = TouchInteractionState.StartPosition or PointerPosition
			local MovementDelta = PointerPosition - PreviousPointerPosition
			local TotalMovementDelta = PointerPosition - StartPointerPosition
			local TouchTarget = TouchInteractionState.ScrollTarget
			TouchInteractionState.CurrentPosition = PointerPosition
			TouchInteractionState.PreviousPosition = PointerPosition
			TouchInteractionState.GestureDistance = math.max(
				TouchInteractionState.GestureDistance or 0,
				TotalMovementDelta.Magnitude
			)
			Window._LastPointerPosition = PointerPosition

			local GestureActivationDistance = math.clamp(Theme.ElementHeight * 0.42, 14, 22)
			local GestureWasActive = TouchInteractionState.Scrolling == true
			if not GestureWasActive and TouchTarget then
				local HorizontalDistance = math.abs(TotalMovementDelta.X)
				local VerticalDistance = math.abs(TotalMovementDelta.Y)
				if TouchTarget.Kind == "Tabs" then
					TouchInteractionState.Scrolling = HorizontalDistance >= GestureActivationDistance
						and HorizontalDistance >= VerticalDistance
					if not TouchInteractionState.Scrolling
						and TotalMovementDelta.Magnitude >= GestureActivationDistance * 1.5
					then
						-- A large vertical departure from the tab bar cancels the tap without
						-- turning it into an unrelated page-scroll gesture.
						TouchInteractionState.Scrolling = true
					end
				elseif TouchTarget.Kind == "Window"
					or TouchTarget.Kind == "Section"
					or TouchTarget.Kind == "Dropdown"
				then
					TouchInteractionState.Scrolling = VerticalDistance >= GestureActivationDistance
						and VerticalDistance >= HorizontalDistance * 0.65
				elseif TouchTarget.Kind == "Control" then
					TouchInteractionState.Scrolling = TotalMovementDelta.Magnitude >= GestureActivationDistance
				else
					TouchInteractionState.Scrolling = TotalMovementDelta.Magnitude >= GestureActivationDistance
				end
			end

			if TouchInteractionState.Scrolling then
				QueuedPrimaryClick = false
				QueuedPrimaryClickPosition = nil
				if TouchTarget and TouchTarget.Kind == "Title bar" then
					Window._Dragging = true
					Window._DragOffset = StartPointerPosition - TouchInteractionState.StartWindowPosition
				elseif TouchTarget and TouchTarget.Kind == "Resize" then
					Window._Resizing = true
					Window._ResizeStartMousePosition = StartPointerPosition
					Window._ResizeStartSize = TouchInteractionState.StartWindowSize
				end

				local AppliedMovementDelta = GestureWasActive and MovementDelta or TotalMovementDelta
				Window:ApplyTouchMovement(AppliedMovementDelta, TotalMovementDelta, TouchTarget)
			end

			RefreshInterfaceCaptureState()
			return true
		end

		if InputState ~= Enum.UserInputState.End and InputState ~= Enum.UserInputState.Cancel then
			return true
		end

		-- Some Android builds report an already-reset Position on End. The latest
		-- Change position is therefore authoritative, falling back to Begin when the
		-- finger never moved.
		local FinalPointerPosition = TouchInteractionState.CurrentPosition
			or TouchInteractionState.StartPosition
			or PointerPosition
		local TouchTarget = TouchInteractionState.ScrollTarget
		local ShouldActivateTap = InputState == Enum.UserInputState.End
			and not TouchInteractionState.Scrolling
		Window._LastPointerPosition = FinalPointerPosition

		TouchInteractionState.ActiveInputObject = nil
		TouchInteractionState.StartPosition = nil
		TouchInteractionState.PreviousPosition = nil
		TouchInteractionState.CurrentPosition = nil
		TouchInteractionState.CoordinateInset = nil
		TouchInteractionState.StartWindowPosition = nil
		TouchInteractionState.StartWindowSize = nil
		TouchInteractionState.GestureDistance = 0
		TouchInteractionState.Scrolling = false
		TouchInteractionState.ScrollTarget = nil
		ReleasePrimaryPointerCapture()

		if not ShouldActivateTap or not Window._Visible or not Library._Visible or not TouchTarget then
			return true
		end

		if TouchTarget.Kind == "Tabs" then
			local ReleasedPageIndex = Window:GetPageTabIndexAtPosition(FinalPointerPosition)
			if TouchTarget.PageIndex and ReleasedPageIndex == TouchTarget.PageIndex then
				Window:SetActivePage(TouchTarget.PageIndex)
			end
			return true
		elseif TouchTarget.Kind == "Control" then
			local ReleasedInsideControl = TouchTarget.Region and IsPointInsideRectangle(
				FinalPointerPosition,
				TouchTarget.Region.Position,
				TouchTarget.Region.Size
			)
			if not ReleasedInsideControl then
				return true
			end

			if TouchTarget.ControlName == "Close" then
				Window:SetVisible(false)
			elseif TouchTarget.ControlName == "Search" then
				SetSearchActive(not Window._SearchActive, true)
				Window:RecalculateLayout()
			end
			return true
		elseif TouchTarget.Kind == "Title bar" or TouchTarget.Kind == "Resize" then
			return true
		end

		-- Ordinary elements continue through the shared primary-click dispatcher so
		-- toggles, dropdowns, sliders, and text boxes retain identical mouse logic.
		UpdateHoverState(FinalPointerPosition)
		QueuedPrimaryClickPosition = FinalPointerPosition
		QueuedPrimaryClick = true
		return true
	end

	table.insert(Window._Connections, ConnectSignal(UserInputService.InputBegan, NewCClosure(function(InputObject)
		if Window._Destroyed then
			return
		end

		local InputType = InputObject.UserInputType
		local IsTouchPointer = InputType == Enum.UserInputType.Touch
		if InputType ~= Enum.UserInputType.MouseButton1 and not IsTouchPointer then
			return
		end
		if IsTouchPointer then
			Window:ProcessTouchInput(Enum.UserInputState.Begin, InputObject)
			return
		end

		local CurrentPointerPosition = GetMouseLocation(UserInputService)
		Window._LastPointerPosition = CurrentPointerPosition

		if not Window._Visible or not Library._Visible then
			return
		end

		if not UpdateHoverState then
			return
		end
		UpdateHoverState(CurrentPointerPosition)

		if Window._MouseInWindow then
			PrimaryMouseButtonHeld = true
			PreviousMouseButtonState = true
			QueuedPrimaryClickPosition = CurrentPointerPosition
			QueuedPrimaryClick = true
			RefreshInterfaceCaptureState()
		end
	end)))

	table.insert(Window._Connections, ConnectSignal(UserInputService.InputChanged, NewCClosure(function(InputObject)
		if InputObject.UserInputType ~= Enum.UserInputType.Touch or Window._Destroyed then
			return
		end

		Window:ProcessTouchInput(Enum.UserInputState.Change, InputObject)
	end)))

	table.insert(Window._Connections, ConnectSignal(UserInputService.InputEnded, NewCClosure(function(InputObject)
		if InputObject.UserInputType == Enum.UserInputType.Touch then
			Window:ProcessTouchInput(Enum.UserInputState.End, InputObject)
			return
		end

		if InputObject.UserInputType ~= Enum.UserInputType.MouseButton1 then
			return
		end

		ReleasePrimaryPointerCapture()
	end)))

	UpdateHoverState = function(CurrentMousePosition)
		local PreviousTooltipVisible = Window._TooltipVisible == true
		Window._HoveredTooltipElement = nil

		-- A render step can run between two constructors while a layout batch is
		-- still assigning section geometry. Ignore that frame completely instead
		-- of reading provisional coordinates or exposing unfinished draw objects.
		if not Window._HasCompletedLayout then
			Window._TooltipVisible = false
			Window._TooltipNeedsLayout = PreviousTooltipVisible
			Window._MouseInWindow = false
			return
		end

		-- Frame processing continues while a window is hidden so animations
		-- can resume smoothly. Clear every transient hover state before returning;
		-- otherwise an invisible control could accumulate the tooltip delay or
		-- request input capture merely because the pointer overlaps its old bounds.
		if not Window._Visible or not Library._Visible then
			Window._TooltipVisible = false
			Window._TooltipNeedsLayout = PreviousTooltipVisible
			Window._CloseButtonHovered = false
			Window._TitleTextHovered = false
			Window._TitleBarHovered = false
			Window._SearchButtonHovered = false
			Window._ResizeGripHovered = false
			Window._ScrollbarHovered = false
			Window._MouseInWindow = false
			for SectionIndex, Section in ipairs(Window._Sections) do
				Section._IsHovered = false
				Section._ScrollbarHovered = false
				for ElementIndex, Element in ipairs(Section._Elements) do
					Element._IsHovered = false
					Element._TooltipHoverStartedAt = nil
					Element._IsThumbHovered = false
					Element._IsSwatchHovered = false
				end
			end
			if Window._ScrollSinkActive then
				Window._ScrollSinkActive = false
				Window:SetInputBlocking("Scroll", false)
			end
			if Window._CameraSinkActive then
				Window._CameraSinkActive = false
				Window:SetInputBlocking("Camera", false)
			end
			return
		end

		for SectionIndex, Section in ipairs(Window._Sections) do
			local IsActivePage = (not Section._PageIndex) or (Section._PageIndex == Window._ActivePageIndex)
			if not IsActivePage then
				Section._IsHovered = false
				Section._ScrollbarHovered = false
				for DiscardElementIndex, Element in ipairs(Section._Elements) do
					Element._IsHovered = false
					Element._TooltipHoverStartedAt = nil
					if Element._Type == "Slider" then
						Element._IsThumbHovered = false
					elseif Element._Type == "ColorPicker" then
						Element._IsSwatchHovered = false
					end
				end
			end
		end

		local HoveredPageIndex = Window:GetPageTabIndexAtPosition(CurrentMousePosition)
		for PageIndex, Page in ipairs(Window._Pages) do
			Page._IsHovered = PageIndex == HoveredPageIndex
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
			local AllowedMinimumPositionY, AllowedMaximumPositionY = GetSectionAllowedYRange(Section, Window, Window._Position.Y)
			local SectionVisible = (SectionYPosition + (Section._ContentHeight or 0) > ViewportStart)
				and (SectionYPosition < ViewportEnd)
			Section._IsHovered = SectionVisible and IsPointInsideRectangle(CurrentMousePosition, SectionHeaderPosition, SectionHeaderSize)

			for ElementIndex, Element in ipairs(Section._Elements) do
				local ElementYPosition = Window._Position.Y + Element._PositionY - Window._ScrollOffset
				local ElementRegionPosition = Vector2.new(Window._Position.X + Element._PositionX, ElementYPosition)
				local ElementWidth = Theme:GetElementAvailableWidth(Element, Window)
				local ElementRegionSize = Vector2.new(ElementWidth, Element._Height)
				local IsElementVisible = IsElementVisibleInViewport(ElementYPosition, Element._Height, Section, Window, Window._Position.Y)
				-- A tall element inside an independently scrolling section can remain
				-- partially visible while most of its original rectangle sits beneath
				-- another section. Hit testing must use the same clipped rectangle as
				-- rendering; otherwise the invisible remainder steals clicks from the
				-- controls drawn above it.
				local ClippedElementRegionPosition, ClippedElementRegionSize = ClipRectangleToYRange(
					ElementRegionPosition,
					ElementRegionSize,
					AllowedMinimumPositionY,
					AllowedMaximumPositionY
				)
				local IsCurrentlyHovered = IsElementVisible
					and ClippedElementRegionPosition ~= nil
					and IsPointInsideRectangle(CurrentMousePosition, ClippedElementRegionPosition, ClippedElementRegionSize)

				if Element._Type == "Slider" then
					local TrackAbsolutePositionX = Window._Position.X + (Element._TrackPositionX or Element._PositionX)
					local TrackAbsolutePositionY = ElementYPosition + Theme.ElementFontSize + 5
					local TrackPos = Vector2.new(TrackAbsolutePositionX, TrackAbsolutePositionY)
					local TrackSize = Vector2.new(Element._TrackTotalWidth or ElementWidth, 16)
					local ClippedTrackPosition, ClippedTrackSize = ClipRectangleToYRange(
						TrackPos,
						TrackSize,
						AllowedMinimumPositionY,
						AllowedMaximumPositionY
					)
					Element._IsHovered = IsElementVisible
						and ClippedTrackPosition ~= nil
						and IsPointInsideRectangle(CurrentMousePosition, ClippedTrackPosition, ClippedTrackSize)

					local Value = Element._Value or 0
					local Range = (Element._MaxValue or 100) - (Element._MinValue or 0)
					if Range == 0 then Range = 1 end
					local NormalizedValue = math.clamp((Value - (Element._MinValue or 0)) / Range, 0, 1)
					local ThumbX = TrackAbsolutePositionX + math.floor((Element._TrackTotalWidth or Element._Width) * NormalizedValue)
					local ThumbY = TrackAbsolutePositionY
						+ (Element._TrackTotalHeight or Theme.SliderTrackHeight) / 2
					local ThumbHitSize = Theme.SliderThumbHoverRadius + 5
					Element._IsThumbHovered = IsElementVisible
						and ThumbY + ThumbHitSize > AllowedMinimumPositionY
						and ThumbY - ThumbHitSize < AllowedMaximumPositionY
						and math.abs(CurrentMousePosition.X - ThumbX) < ThumbHitSize
						and math.abs(CurrentMousePosition.Y - ThumbY) < ThumbHitSize
					Element._IsHovered = Element._IsHovered or Element._IsThumbHovered
				elseif Element._Type == "ColorPicker" then
					local SwatchAbsolutePosition = Window._Position + Vector2.new(Element._SwatchPositionX, Element._SwatchPositionY - Window._ScrollOffset)
					local SwatchSizeVector = Vector2.new(Element._SwatchSize, Element._SwatchSize)
					local ClippedSwatchPosition, ClippedSwatchSize = ClipRectangleToYRange(
						SwatchAbsolutePosition,
						SwatchSizeVector,
						AllowedMinimumPositionY,
						AllowedMaximumPositionY
					)
					Element._IsSwatchHovered = IsElementVisible
						and ClippedSwatchPosition ~= nil
						and IsPointInsideRectangle(CurrentMousePosition, ClippedSwatchPosition, ClippedSwatchSize)
					Element._IsHovered = Element._IsSwatchHovered
				elseif Element._Type == "TextBox" then
					Element._HoveredSuggestionIndex = nil
					local TextBoxMetrics = GetTextBoxLayoutMetrics(Element, ElementRegionPosition, ElementWidth)
					local TextBoxBaseRegionSize = Vector2.new(ElementWidth, TextBoxMetrics.BaseHeight)
					local ClippedTextBoxPosition, ClippedTextBoxSize = ClipRectangleToYRange(
						ElementRegionPosition,
						TextBoxBaseRegionSize,
						AllowedMinimumPositionY,
						AllowedMaximumPositionY
					)
					if Element._IsFocused and Element._SuggestionDropdownRegion and IsPointInsideRectangle(CurrentMousePosition, Element._SuggestionDropdownRegion.Position, Element._SuggestionDropdownRegion.Size) then
						local RelativeSuggestionY = CurrentMousePosition.Y - Element._SuggestionDropdownRegion.Position.Y
						local SuggestionIndex = math.floor(RelativeSuggestionY / 22) + 1
						if SuggestionIndex >= 1 and SuggestionIndex <= #Element._Suggestions then
							Element._HoveredSuggestionIndex = SuggestionIndex
							Element._IsHovered = true
						else
							Element._IsHovered = IsElementVisible
								and ClippedTextBoxPosition ~= nil
								and IsPointInsideRectangle(CurrentMousePosition, ClippedTextBoxPosition, ClippedTextBoxSize)
						end
					else
						Element._IsHovered = IsElementVisible
							and ClippedTextBoxPosition ~= nil
							and IsPointInsideRectangle(CurrentMousePosition, ClippedTextBoxPosition, ClippedTextBoxSize)
					end
				else
					Element._IsHovered = IsCurrentlyHovered
				end

				-- A locked control uses its complete clipped rectangle as the hover
				-- target. This keeps its explanation discoverable even for controls
				-- whose normal interaction target is only a thumb or color swatch.
				if Element._IsLocked then
					Element._IsHovered = IsCurrentlyHovered
					Element._IsThumbHovered = false
					Element._IsSwatchHovered = false
				end

				if Element._IsHovered and Element._Tooltip and Element._Tooltip ~= "" then
					Element._TooltipHoverStartedAt = Element._TooltipHoverStartedAt or tick()
					Window._HoveredTooltipElement = Element
				else
					Element._TooltipHoverStartedAt = nil
				end
			end
		end

		local HoveredTooltipElement = Window._HoveredTooltipElement
		Window._TooltipVisible = HoveredTooltipElement ~= nil
			and HoveredTooltipElement._TooltipHoverStartedAt ~= nil
			and tick() - HoveredTooltipElement._TooltipHoverStartedAt >= Theme.TooltipDelay
		if Window._TooltipVisible ~= PreviousTooltipVisible or Window._TooltipVisible then
			Window._TooltipNeedsLayout = true
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
		local MouseInWindow = Window._Visible and (
			IsPointInsideRectangle(CurrentMousePosition, SinkBodyPosition, SinkBodySize)
			or IsPointInsideRectangle(CurrentMousePosition, SinkTitlePosition, SinkTitleSize)
		) or false
		Window._MouseInWindow = MouseInWindow
		local TouchPointerIsActive = Window._TouchInteractionState
			and Window._TouchInteractionState.ActiveInputObject ~= nil
		local PointerRequestsCapture = MouseInWindow
			and (not Window._TouchInputAvailable or TouchPointerIsActive)
		if PointerRequestsCapture ~= Window._ScrollSinkActive then
			Window._ScrollSinkActive = PointerRequestsCapture
			Window:SetInputBlocking("Scroll", PointerRequestsCapture)
		end
		if PointerRequestsCapture ~= Window._CameraSinkActive then
			Window._CameraSinkActive = PointerRequestsCapture
			Window:SetInputBlocking("Camera", PointerRequestsCapture)
		end
		RefreshInterfaceCaptureState()
		Window._TitleBarHovered = Window._Visible and IsPointInsideRectangle(CurrentMousePosition, SinkTitlePosition, SinkTitleSize) or false

		local ResizeGripSize = GetWindowResizeGripHitSize(Window)
		local ResizeGripPosition = Vector2.new(
			Window._Position.X + Theme.WindowWidth - ResizeGripSize,
			Window._Position.Y + Theme.TitleBarHeight + Window._VisibleHeight - ResizeGripSize
		)
		Window._ResizeGripRegion = {
			Position = ResizeGripPosition,
			Size = Vector2.new(ResizeGripSize, ResizeGripSize)
		}
		Window._ResizeGripHovered = Window._Visible and IsPointInsideRectangle(CurrentMousePosition, Window._ResizeGripRegion.Position, Window._ResizeGripRegion.Size) or false

		local TitleHitboxPosition = Vector2.new(Window._Position.X + Theme.InnerMargin, Window._Position.Y)
		local TitleHitboxSize = Vector2.new(math.min(180, Theme.WindowWidth / 2), Theme.TitleBarHeight)
		Window._TitleTextHovered = IsPointInsideRectangle(CurrentMousePosition, TitleHitboxPosition, TitleHitboxSize)

		if Window._CloseButtonRegion then
			Window._CloseButtonHovered = IsPointInsideRectangle(CurrentMousePosition, Window._CloseButtonRegion.Position, Window._CloseButtonRegion.Size)
		else
			Window._CloseButtonHovered = false
		end

		if Window._ActiveDropdown then
			local ActiveDropdown = Window._ActiveDropdown
			local DropdownSection = ActiveDropdown._Section
			for ItemIndex, ItemData in ipairs(ActiveDropdown._ItemDrawingObjects) do
				local OptionsRegion = ActiveDropdown._OptionsRegion
				local ItemRegionPosition = Vector2.new(Window._Position.X + ItemData._PositionX, Window._Position.Y + ItemData._PositionY - Window._ScrollOffset)
				local ItemRegionSize = Vector2.new(ItemData._Width, Theme.ElementHeight)
				local IsInsideOptionsRegion = OptionsRegion
					and ItemRegionPosition.Y >= OptionsRegion.Position.Y
					and ItemRegionPosition.Y + Theme.ElementHeight <= OptionsRegion.Position.Y + OptionsRegion.Size.Y
				local IsInsideSectionViewport = DropdownSection and IsElementFullyVisibleInViewport(
					ItemRegionPosition.Y,
					Theme.ElementHeight,
					DropdownSection,
					Window,
					Window._Position.Y
				)
				ItemData._IsHovered = IsInsideOptionsRegion
					and IsInsideSectionViewport
					and IsPointInsideRectangle(CurrentMousePosition, ItemRegionPosition, ItemRegionSize)
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

	local InterfaceFrameConnection = ConnectSignal(InterfaceFrameSignal, NewCClosure(function(DeltaTime)
		if Window._Destroyed then return end
		if not Library._Visible or not Window._Visible then
			if PrimaryMouseButtonHeld then
				-- A keyboard hide or external visibility change can occur while a
				-- pointer is still down. Release the local capture immediately so the
				-- stale input cannot keep future interactions permanently held.
				ReleasePrimaryPointerCapture()
			end

			if not UseImmediateMode then
				-- Treat hidden retained windows as an atomic render state on every
				-- frame. This also repairs visibility if a setter or an already queued
				-- layout pass touched an individual drawing after SetVisible returned.
				SetDrawingObjectsVisibility(WindowTrackedDrawings, false)
				Window:UpdateTouchLauncherDrawings()
			end
			return
		end

		local DeltaSeconds = DeltaTime or 0.0167
		local VisualTime = os.clock()
		local AmbientPulse = (math.sin(VisualTime * 2.4) + 1) * 0.5
		Window._AmbientPulse = AmbientPulse
		Window._AmbientAccentColor = Theme.AccentPrimary:Lerp(
			Theme.AccentSecondary,
			(math.sin(VisualTime * 0.72) + 1) * 0.5
		)

		-- The site uses soft luminous accents rather than a static colored frame.
		-- Animate only the two tiny retained primitives here, avoiding a complete
		-- layout pass on every frame while still keeping retained/immediate parity.
		if not UseImmediateMode then
			local AccentCenter = Window._Position + Vector2.new(
				Theme.InnerMargin + 4,
				Theme.TitleBarHeight * 0.5
			)
			ApplyDrawingProperties(TitleAccentCircleDrawing, {
				Position = AccentCenter,
				Radius = LerpValue(2.2, 3.1, AmbientPulse),
				Color = Window._AmbientAccentColor,
				Transparency = LerpValue(0.78, 1, AmbientPulse),
				Visible = true,
			})
			ApplyDrawingProperties(TitleAccentOuterGlowCircleDrawing, {
				Position = AccentCenter,
				Radius = LerpValue(5, 8, AmbientPulse),
				Color = Window._AmbientAccentColor,
				Transparency = LerpValue(0.18, 0.48, AmbientPulse),
				Visible = true,
			})
			if Window._TopShimmerDrawing then
				local ShimmerWidth = math.clamp(Theme.WindowWidth * 0.16, 54, 112)
				local ShimmerTravel = math.max(0, Theme.WindowWidth - ShimmerWidth)
				local ShimmerProgress = (VisualTime * 0.16) % 1
				local ShimmerStartX = Window._Position.X + ShimmerTravel * ShimmerProgress
				ApplyDrawingProperties(Window._TopShimmerDrawing, {
					From = Vector2.new(ShimmerStartX, Window._Position.Y),
					To = Vector2.new(ShimmerStartX + ShimmerWidth, Window._Position.Y),
					Color = Window._AmbientAccentColor,
					Transparency = LerpValue(0.58, 0.95, AmbientPulse),
					Visible = true,
				})
			end
		end
		local CurrentMousePosition = QueuedPrimaryClickPosition or Window:GetCurrentPointerPosition()
		if QueuedPrimaryClickPosition then
			Window._LastPointerPosition = QueuedPrimaryClickPosition
		end

		-- Layout construction is intentionally atomic from the renderer's point of
		-- view. Waiting for the completed pass also prevents animation code below
		-- from requesting a second pass against a partially populated section.
		if not Window._HasCompletedLayout then
			return
		end
		UpdateHoverState(CurrentMousePosition)

		local AnimationChanged = Window._TooltipNeedsLayout == true
		Window._TooltipNeedsLayout = false
		local function UpdateAnimationState(CurrentFactor, TargetState, DeltaSecondsValue, Speed)
			local NewFactor = Theme.UpdateAnimationFactor(CurrentFactor, TargetState, DeltaSecondsValue, Speed)
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
		QueuedPrimaryClickPosition = nil

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

		if Window._ActiveTextSelectionBox and IsPrimaryMouseButtonDown then
			UpdateActiveTextBoxMouseSelection(CurrentMousePosition)
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
			Window._Position = ClampWindowPosition(CurrentMousePosition - Window._DragOffset)
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
							Window:SetActivePage(TargetSection._PageIndex)
						end

						local TargetScroll = TargetSection._PositionY - Theme.TitleBarHeight - 10
						Window._ScrollOffset = math.clamp(TargetScroll, 0, Window._MaxScroll)

						Window._HighlightedElement = TargetElement
						Window._HighlightedSection = TargetSection
						TargetElement._HighlightTime = tick()

						SetSearchActive(false, true)

						Window:RecalculateLayout()
						return
					end
				elseif Window._SearchTextBox._IsHovered then
					ClearFocusedTextBoxes()
					SetSearchTextBoxFocus(true)
					if Window._SearchTextBoxRegion then
						BeginTextBoxMouseSelection(
							Window._SearchTextBox,
							CurrentMousePosition,
							Window._SearchTextBoxRegion.Position,
							Window._SearchTextBoxRegion.Size.X
						)
					end
					Window:RecalculateLayout()
					return
				else
					SetSearchTextBoxFocus(false)
					Window:RecalculateLayout()
				end
			end

			if Window._CloseButtonHovered then
				if Window._TouchInputAvailable then
					Window:SetVisible(false)
				else
					Window:Destroy()
				end
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
						Window:SetActivePage(PageIndex)
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
				local DropdownSection = ExpandedDropdown._Section

				for ItemIndex, ItemData in ipairs(ExpandedDropdown._ItemDrawingObjects) do
					local OptionsRegion = ExpandedDropdown._OptionsRegion
					local ItemRegionPosition = Vector2.new(Window._Position.X + ItemData._PositionX, Window._Position.Y + ItemData._PositionY - Window._ScrollOffset)
					local ItemRegionSize = Vector2.new(ItemData._Width, Theme.ElementHeight)
					local IsInsideOptionsRegion = OptionsRegion
						and ItemRegionPosition.Y >= OptionsRegion.Position.Y
						and ItemRegionPosition.Y + Theme.ElementHeight <= OptionsRegion.Position.Y + OptionsRegion.Size.Y
					local IsInsideSectionViewport = DropdownSection and IsElementFullyVisibleInViewport(
						ItemRegionPosition.Y,
						Theme.ElementHeight,
						DropdownSection,
						Window,
						Window._Position.Y
					)
					if IsInsideOptionsRegion
						and IsInsideSectionViewport
						and IsPointInsideRectangle(CurrentMousePosition, ItemRegionPosition, ItemRegionSize) then
						if ExpandedDropdown._MultiSelect then
							ExpandedDropdown:ToggleSelection(ItemData.Value)
						else
							ExpandedDropdown:SetValue(ItemData.Value)
							ExpandedDropdown:Toggle()
						end
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
						if Element._IsLocked then
							ClearFocusedTextBoxes()
							return
						end

						if Element._Type == "TextButton" then
							ClearFocusedTextBoxes()
							InvokeCallback(Element._Callback)
							return

						elseif Element._Type == "TextLabel" then
							if Element._Interactive then
								ClearFocusedTextBoxes()
								InvokeCallback(Element._Callback)
								return
							end

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
							if Element._HoveredSuggestionIndex and Element:ApplySuggestion(Element._HoveredSuggestionIndex) then
								return
							end
							ClearFocusedTextBoxes()
							local TextBoxPosition = Vector2.new(Window._Position.X + Element._PositionX, Window._Position.Y + Element._PositionY - Window._ScrollOffset)
							local TextBoxWidth = Theme:GetElementAvailableWidth(Element, Window)
							BeginTextBoxMouseSelection(Element, CurrentMousePosition, TextBoxPosition, TextBoxWidth)
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

	table.insert(Window._Connections, ConnectSignal(UserInputService.InputChanged, NewCClosure(function()
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

	table.insert(Window._Connections, InterfaceFrameConnection)
	table.insert(Library._Windows, Window)

	if UseImmediateMode and DrawingImmediateGetPaint then
		local PaintSignal = DrawingImmediateGetPaint(1)
		local ConnectToPaintSignal = CloneFunction(PaintSignal.Connect)
		local PaintConnection = ConnectToPaintSignal(PaintSignal, NewCClosure(function()
			if Window._Destroyed then
				return
			end

			if not Library._Visible or not Window._Visible then
				if Window._TouchInputAvailable then
					local LauncherGeometry = Window:GetTouchLauncherGeometry()
					local LauncherTextSize = math.max(18, Theme.TitleFontSize)
					local LauncherTextBounds = GetTextBounds("C", LauncherTextSize)
					DrawImmediateSolidCircle(
						LauncherGeometry.Center,
						LauncherGeometry.Radius + 4,
						Theme.WindowSurfaceShade,
						0.35,
						64
					)
					DrawImmediateSolidCircle(
						LauncherGeometry.Center,
						LauncherGeometry.Radius,
						Theme.TouchLauncherBackground,
						0.96,
						64
					)
					DrawingImmediateCircle(
						LauncherGeometry.Center,
						LauncherGeometry.Radius,
						Theme.TouchLauncherBorder,
						0.95,
						64,
						2
					)
					DrawingImmediateText(
						LauncherGeometry.Center - LauncherTextBounds / 2,
						Theme.Font,
						LauncherTextSize,
						Theme.TouchLauncherText,
						1,
						"C",
						false
					)
				end
				return
			end

			local WindowPosition = Window._Position
			local VisualTime = os.clock()
			local AmbientPulse = Window._AmbientPulse
				or (math.sin(VisualTime * 2.4) + 1) * 0.5
			local AmbientAccentColor = Window._AmbientAccentColor
				or Theme.AccentPrimary:Lerp(
					Theme.AccentSecondary,
					(math.sin(VisualTime * 0.72) + 1) * 0.5
				)
			local ViewportStart, ViewportEnd = GetWindowContentViewportYRange(Window, WindowPosition.Y)
			local WindowWidth = Theme.WindowWidth

			local ContentHeight = Window._VisibleHeight

			local BodyPosition = Vector2.new(WindowPosition.X, WindowPosition.Y + Theme.TitleBarHeight)
			local BodySize = Vector2.new(WindowWidth, ContentHeight)

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
			local ShimmerWidth = math.clamp(WindowWidth * 0.16, 54, 112)
			local ShimmerTravel = math.max(0, WindowWidth - ShimmerWidth)
			local ShimmerStartX = WindowPosition.X
				+ ShimmerTravel * ((VisualTime * 0.16) % 1)
			DrawingImmediateLine(
				Vector2.new(ShimmerStartX, WindowPosition.Y),
				Vector2.new(ShimmerStartX + ShimmerWidth, WindowPosition.Y),
				AmbientAccentColor,
				LerpValue(0.58, 0.95, AmbientPulse),
				2
			)

			local CurrentMousePosition = Window:GetCurrentPointerPosition()
			local MouseInsideBody = IsPointInsideRectangle(CurrentMousePosition, BodyPosition, BodySize)

			local TitleBarCheckPos = Vector2.new(WindowPosition.X, WindowPosition.Y)
			local TitleBarCheckSize = Vector2.new(WindowWidth, Theme.TitleBarHeight)
			local MouseInsideWindow = MouseInsideBody or IsPointInsideRectangle(CurrentMousePosition, TitleBarCheckPos, TitleBarCheckSize)
			Window._MouseInWindow = MouseInsideWindow
			local TouchPointerIsActive = Window._TouchInteractionState
				and Window._TouchInteractionState.ActiveInputObject ~= nil
			local PointerRequestsCapture = MouseInsideWindow
				and (not Window._TouchInputAvailable or TouchPointerIsActive)
			if PointerRequestsCapture ~= Window._ScrollSinkActive then
				Window._ScrollSinkActive = PointerRequestsCapture
				Window:SetInputBlocking("Scroll", PointerRequestsCapture)
			end

			if PointerRequestsCapture ~= Window._CameraSinkActive then
				Window._CameraSinkActive = PointerRequestsCapture
				Window:SetInputBlocking("Camera", PointerRequestsCapture)
			end
			RefreshInterfaceCaptureState()

			local TitleBarSize = Vector2.new(WindowWidth, Theme.TitleBarHeight)
			DrawingImmediateFilledRectangle(WindowPosition, TitleBarSize, Theme.TitleBarBackground, 1, 0)
			DrawingImmediateFilledRectangle(WindowPosition, Vector2.new(WindowWidth, math.max(6, Theme.TitleBarHeight * 0.45)), Theme.TitleBarHighlight, 0.32, 0)
			DrawingImmediateFilledRectangle(WindowPosition, TitleBarSize, Theme.TitleBarAccentWash, 0.34, 0)
			Window._TitleBarHovered = IsPointInsideRectangle(CurrentMousePosition, WindowPosition, TitleBarSize)
			local ResizeGripSize = GetWindowResizeGripHitSize(Window)
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

				local TabLayout = GetPageTabLayout(Window, WindowWidth)
				Window._TabScrollOffset = math.clamp(Window._TabScrollOffset or 0, 0, TabLayout.MaximumScroll)
				for PageIndex, Page in ipairs(Window._Pages) do
					local TabWidth = TabLayout.Widths[PageIndex]
					local TabX = WindowPosition.X + TabLayout.Padding + TabLayout.Offsets[PageIndex] - Window._TabScrollOffset
					local TabY = WindowPosition.Y + Theme.TitleBarHeight + 5
					local TabHeight = Window._TabBarHeight - 10
					
					if Library:IsPageTabFullyInsideViewport(
						TabLayout,
						WindowPosition.X,
						WindowWidth,
						TabX,
						TabWidth
					) then
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
				if TabLayout.MaximumScroll > 0 then
					local ScrollProgress = Window._TabScrollOffset / TabLayout.MaximumScroll
					local AvailableTabWidth = TabLayout.AvailableWidth
					local HandleWidth = math.clamp(
						(AvailableTabWidth / TabLayout.ContentWidth) * AvailableTabWidth,
						30,
						AvailableTabWidth
					)
					local HandleX = WindowPosition.X + TabLayout.Padding + (AvailableTabWidth - HandleWidth) * ScrollProgress
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

			local TitleTextX = WindowPosition.X + Theme.InnerMargin + 12
			local TitleTextY = Window._Description ~= ""
				and WindowPosition.Y + 7
				or WindowPosition.Y + (Theme.TitleBarHeight - Theme.TitleFontSize) / 2
			local TitleTextColor = Theme.TitleBarText:Lerp(
				Theme.TitleBarTextHover,
				Window._TitleTextHoverFactor or 0
			)

			local TitleDotCenter = Vector2.new(
				WindowPosition.X + Theme.InnerMargin + 4,
				WindowPosition.Y + Theme.TitleBarHeight / 2
			)
			DrawingImmediateCircle(
				TitleDotCenter,
				LerpValue(5, 8, AmbientPulse),
				AmbientAccentColor,
				LerpValue(0.18, 0.48, AmbientPulse),
				48,
				1
			)
			DrawImmediateSolidCircle(
				TitleDotCenter,
				LerpValue(2.2, 3.1, AmbientPulse),
				AmbientAccentColor,
				LerpValue(0.78, 1, AmbientPulse),
				48
			)
			DrawingImmediateText(
				Vector2.new(TitleTextX, TitleTextY),
				Theme.Font, Theme.TitleFontSize, TitleTextColor, 1, Window._Title, false
			)
			if Window._Description ~= "" then
				DrawingImmediateText(
					Vector2.new(TitleTextX, WindowPosition.Y + Theme.TitleFontSize + 10),
					Theme.Font, Theme.HeaderSecondaryFontSize, Theme.TextBoxPlaceholder, 1, Window._Description, false
				)
			end

			if Window._SearchButtonRegion then
				local HeaderMetaText = Window:GetHeaderMetaText()
				local HeaderMetaBounds = GetTextBounds(HeaderMetaText, Theme.HeaderSecondaryFontSize)
				local HeaderActionSeparatorX = Window._SearchButtonRegion.Position.X - 10
				local HeaderMetaPositionX = HeaderActionSeparatorX - HeaderMetaBounds.X - 10
				local TitleBounds = GetTextBounds(Window._Title, Theme.TitleFontSize)
				local DescriptionBounds = Window._Description ~= ""
					and GetTextBounds(Window._Description, Theme.HeaderSecondaryFontSize)
					or Vector2.new(0, 0)
				local HeaderTextWidth = math.max(TitleBounds.X, DescriptionBounds.X)
				local TitleSafeRightX = TitleTextX + HeaderTextWidth + 20
				if HeaderMetaPositionX > TitleSafeRightX then
					DrawingImmediateText(
						Vector2.new(
							HeaderMetaPositionX,
							WindowPosition.Y + (Theme.TitleBarHeight - Theme.HeaderSecondaryFontSize) / 2
						),
						Theme.Font, Theme.HeaderSecondaryFontSize, Theme.LabelText, 1, HeaderMetaText, false
					)
					DrawingImmediateLine(
						Vector2.new(HeaderActionSeparatorX, WindowPosition.Y + 10),
						Vector2.new(HeaderActionSeparatorX, WindowPosition.Y + Theme.TitleBarHeight - 10),
						Theme.WindowBorder,
						0.45,
						1
					)
				end
			end

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
				local SearchIconCenter = Window._SearchButtonRegion.Position + Window._SearchButtonRegion.Size / 2

				DrawingImmediateCircle(SearchIconCenter, 4.5, SearchIconColor, 1, 48, 1)
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
						local SectionIndexText = string.format("%02d", Section._Index or 0)
						local SectionIndexBounds = GetTextBounds(SectionIndexText, Theme.SectionMetaFontSize)
						local AvailableTitleWidth = math.max(1, Section._Width - SectionIndexBounds.X - 34)
						local MaximumTitleCharacters = math.max(
							1,
							math.floor(AvailableTitleWidth / GetEditableTextCharacterWidth(Theme.SectionFontSize))
						)
						DrawingImmediateText(
							Vector2.new(WindowPosition.X + Section._PositionX + 10, TitleY),
							Theme.Font, Theme.SectionFontSize, SectionTitleColor, 1,
							TruncateTextWithAsciiEllipsis(Section._Title, MaximumTitleCharacters),
							false
						)

						DrawingImmediateText(
							Vector2.new(
								WindowPosition.X + Section._PositionX + Section._Width - SectionIndexBounds.X - 10,
								SectionYPosition + (Theme.ElementHeight - Theme.SectionMetaFontSize) / 2
							),
							Theme.Font, Theme.SectionMetaFontSize, Theme.TextBoxPlaceholder, 1, SectionIndexText, false
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
						local ElementSize = Vector2.new(Theme:GetElementAvailableWidth(Element, Window), Element._Height)

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
									local RenderText, InlineVisuals = Theme:ParseInlineVisualLine(LineText, Theme.ElementFontSize)
									local LinePosition = Vector2.new(
										WindowPosition.X + Element._PositionX + HorizontalInset,
										LineY
									)
									DrawingImmediateText(
										LinePosition,
										Theme.Font, Theme.ElementFontSize, LabelTextColor, 1, RenderText, false
									)
									for VisualIndex, VisualData in ipairs(InlineVisuals) do
										if VisualData.Shape == "Circle" then
											local VisualRadius = math.max(3, Theme.ElementFontSize * 0.32)
											local VisualTopLeft = Vector2.new(
												LinePosition.X + VisualData.ColumnIndex * VisualData.CharacterWidth,
												LineY + (LineHeight / 2) - VisualRadius
											)
											DrawImmediateSolidCircle(
												VisualTopLeft + Vector2.new(VisualRadius, VisualRadius),
												VisualRadius,
												VisualData.Color,
												1,
												64
											)
										end
									end
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
								-- Truncate text if it exceeds the button's bounds, keeping style consistent with PascalCase names.
								local AvailableTextWidth = ElementSize.X - 20
								local CharacterWidth = GetEditableTextCharacterWidth(Theme.ElementFontSize)
								local MaximumCharacters = math.max(1, math.floor(AvailableTextWidth / CharacterWidth))
								local DisplayText = TruncateTextWithAsciiEllipsis(Element._Text, MaximumCharacters)
								DrawingImmediateText(
									Vector2.new(WindowPosition.X + Element._PositionX + 10, TextY),
									Theme.Font, Theme.ElementFontSize, Theme.ButtonText, 1, DisplayText, false
								)
							end
						elseif Element._Type == "Toggle" then
							local ToggleBg = Theme.ButtonBackground:Lerp(Theme.ButtonBackgroundHover, Element._HoverFactor or 0)
							local ClippedPos, ClippedSize = ClipRectangleToYRange(ElementPosition, ElementSize, AllowedMinY, AllowedMaxY)
							if ClippedPos and ClippedSize then
								DrawingImmediateFilledRectangle(ClippedPos, ClippedSize, ToggleBg, 1, 0)
								DrawingImmediateRectangle(ClippedPos, ClippedSize, Theme.ButtonBorder, 0.8, 0, 1)
							end

							local TextY = ElementYPosition + (Element._Height - Theme.ElementFontSize) / 2
							if TextY >= AllowedMinY and TextY + Theme.ElementFontSize <= AllowedMaxY then
								local AvailableTextWidth = math.max(1, ElementSize.X - 42)
								local CharacterWidth = GetEditableTextCharacterWidth(Theme.ElementFontSize)
								local MaximumCharacters = math.max(1, math.floor(AvailableTextWidth / CharacterWidth))
								local DisplayText = TruncateTextWithAsciiEllipsis(Element._Text, MaximumCharacters)
								DrawingImmediateText(
									Vector2.new(WindowPosition.X + Element._PositionX + 10, TextY),
									Theme.Font, Theme.ElementFontSize, Theme.ButtonText, 1, DisplayText, false
								)
							end

							local PipX = WindowPosition.X + Element._PositionX + ElementSize.X - 14
							local PipY = ElementYPosition + Element._Height / 2
							local PipColor = Theme.ToggleInactive:Lerp(Theme.ToggleActive, Element._ActiveFactor or 0)
							local ToggleIndicatorRadius = Theme.ToggleIndicatorRadius
							if PipY - ToggleIndicatorRadius >= AllowedMinY
								and PipY + ToggleIndicatorRadius <= AllowedMaxY
							then
								-- Use the stable rounded-square circle helper shared by
								-- toggle and slider indicators. Dropdown arrows remain
								-- the only triangular controls in the interface.
								DrawImmediateSolidCircle(
									Vector2.new(PipX, PipY),
									ToggleIndicatorRadius,
									PipColor,
									1,
									64
								)
							end
						elseif Element._Type == "TextBox" then
							local TextBoxMetrics = GetTextBoxLayoutMetrics(Element, ElementPosition, ElementSize.X)
							local TextBoxBaseHeight = TextBoxMetrics.BaseHeight
							local TextBoxBaseSize = Vector2.new(ElementSize.X, TextBoxBaseHeight)
							if Element._IsFocused then
								local CurrentTimestamp = tick()
								if CurrentTimestamp - Element._CursorBlinkTime >= 0.53 then
									Element._CursorBlinkTime = CurrentTimestamp
									Element._CursorVisible = not Element._CursorVisible
								end
							else
								Element._CursorVisible = false
								Element._CursorBlinkTime = 0
							end

							local TextBoxBackgroundColor = Theme.TextBoxBackground:Lerp(Theme.TextBoxBackgroundHover, Element._HoverFactor or 0)
							local TextBoxBorderColor = Theme.TextBoxBorder:Lerp(Theme.TextBoxBorderFocused, Element._FocusFactor or 0)
							local TextBoxBorderThickness = LerpValue(1, 2, Element._FocusFactor or 0)

							local ClippedPos, ClippedSize = ClipRectangleToYRange(ElementPosition, TextBoxBaseSize, AllowedMinY, AllowedMaxY)
							if ClippedPos and ClippedSize then
								DrawingImmediateFilledRectangle(ClippedPos, ClippedSize, TextBoxBackgroundColor, 1, 0)
								DrawingImmediateRectangle(ClippedPos, ClippedSize, TextBoxBorderColor, 1, 0, TextBoxBorderThickness)
							end

							if (Element._FocusFactor or 0) > 0.01 then
								local AccentFrom, AccentTo = ClipVerticalLineToYRange(
									Vector2.new(ElementPosition.X, ElementYPosition + 3),
									Vector2.new(ElementPosition.X, ElementYPosition + TextBoxBaseHeight - 3),
									AllowedMinY, AllowedMaxY
								)
								if AccentFrom and AccentTo then
									DrawingImmediateLine(AccentFrom, AccentTo, Theme.TextBoxBorderFocused, Element._FocusFactor or 0, 2)
								end
							end

							local LabelTextY = TextBoxMetrics.LabelPosition.Y
							if LabelTextY >= AllowedMinY and LabelTextY + Theme.ElementFontSize <= AllowedMaxY then
								if TextBoxMetrics.LabelDisplayText ~= "" then
									DrawingImmediateText(
										TextBoxMetrics.LabelPosition,
										Theme.Font, Theme.ElementFontSize, Theme.LabelText, 1, TextBoxMetrics.LabelDisplayText, false
									)
								end
							end

							local InputStartX = TextBoxMetrics.InputStartX

							local HasValue = Element._Value ~= ""
							local DisplayText = HasValue and Element._Value or Element._Placeholder
							local DisplayColor = HasValue and Theme.TextBoxText or Theme.TextBoxPlaceholder

							local CharacterWidth = TextBoxMetrics.CharacterWidth
							local MaxChars = TextBoxMetrics.MaximumCharacters
							local ClippedText = GetTextBoxVisibleText(Element, DisplayText, MaxChars, HasValue)

							DrawImmediateTextBoxSelectionAndCursor(
								Element,
								InputStartX,
								TextBoxMetrics.InputTextPositionY,
								CharacterWidth,
								MaxChars,
								AllowedMinY,
								AllowedMaxY,
								HasValue
							)

							if TextBoxMetrics.InputTextPositionY >= AllowedMinY and TextBoxMetrics.InputTextPositionY + Theme.ElementFontSize <= AllowedMaxY then
								DrawingImmediateText(
									Vector2.new(InputStartX, TextBoxMetrics.InputTextPositionY),
									Theme.Font, Theme.ElementFontSize, DisplayColor, 1, ClippedText, false
								)
							end

							if Element._IsFocused and #Element._Suggestions > 0 then
								local SuggestionCount = math.min(#Element._Suggestions, Element._MaximumSuggestions or 5)
								local SuggestionRowHeight = 22
								local SuggestionPosition = Vector2.new(ElementPosition.X, ElementYPosition + TextBoxBaseHeight + 2)
								local SuggestionSize = Vector2.new(ElementSize.X, SuggestionRowHeight * SuggestionCount)
								local ClippedSuggestionPosition, ClippedSuggestionSize = ClipRectangleToYRange(
									SuggestionPosition,
									SuggestionSize,
									AllowedMinY,
									AllowedMaxY
								)
								Element._SuggestionDropdownRegion = ClippedSuggestionPosition and {
									Position = ClippedSuggestionPosition,
									Size = ClippedSuggestionSize,
								} or nil

								if ClippedSuggestionPosition and ClippedSuggestionSize then
									DrawingImmediateFilledRectangle(ClippedSuggestionPosition, ClippedSuggestionSize, Theme.DropdownBackground, 0.98, 0)
									DrawingImmediateRectangle(ClippedSuggestionPosition, ClippedSuggestionSize, Theme.DropdownBorder, 0.85, 0, 1)
								end

								for SuggestionIndex = 1, SuggestionCount do
									local SuggestionText = Element._Suggestions[SuggestionIndex]
									local SuggestionY = SuggestionPosition.Y + (SuggestionIndex - 1) * SuggestionRowHeight
									local SuggestionRowIsVisible = SuggestionY >= AllowedMinY
										and SuggestionY + SuggestionRowHeight <= AllowedMaxY
									if SuggestionRowIsVisible
										and (Element._HoveredSuggestionIndex or Element._KeyboardSuggestionIndex) == SuggestionIndex then
										DrawingImmediateFilledRectangle(
											Vector2.new(SuggestionPosition.X, SuggestionY),
											Vector2.new(SuggestionSize.X, SuggestionRowHeight),
											Theme.DropdownItemHover,
											0.75,
											0
										)
									end

									if SuggestionRowIsVisible then
										local SuggestionCharacterWidth = Theme.ElementFontSize * Theme.FontCharWidthRatio * 1.25
										local SuggestionMaximumCharacters = math.max(1, math.floor((SuggestionSize.X - 16) / SuggestionCharacterWidth))
										local DisplaySuggestionText = TruncateTextWithAsciiEllipsis(SuggestionText, SuggestionMaximumCharacters)
										DrawingImmediateText(
											Vector2.new(SuggestionPosition.X + 8, SuggestionY + (SuggestionRowHeight - Theme.ElementFontSize) / 2),
											Theme.Font,
											Theme.ElementFontSize,
											(Element._HoveredSuggestionIndex or Element._KeyboardSuggestionIndex) == SuggestionIndex and Theme.TitleBarTextHover or Theme.DropdownText,
											1,
											DisplaySuggestionText,
											false
										)
									end
								end
							else
								Element._SuggestionDropdownRegion = nil
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
								-- Truncate text if it exceeds the dropdown's bounds, keeping style consistent with PascalCase names.
								local AvailableTextWidth = ElementSize.X - 32
								local CharacterWidth = GetEditableTextCharacterWidth(Theme.ElementFontSize)
								local MaximumCharacters = math.max(1, math.floor(AvailableTextWidth / CharacterWidth))
								local FullText = string.format("%s: %s", Element._Text, Element:GetDisplayValueText())
								local DisplayText = TruncateTextWithAsciiEllipsis(FullText, MaximumCharacters)
								DrawingImmediateText(
									Vector2.new(WindowPosition.X + Element._PositionX + 8, TextY),
									Theme.Font, Theme.ElementFontSize, Theme.DropdownText, 1, DisplayText, false
								)
								DrawingImmediateText(
									Vector2.new(WindowPosition.X + Element._PositionX + ElementSize.X - 18, TextY),
									Theme.Font, Theme.ElementFontSize, Theme.DropdownArrow, 1, Element._Expanded and "^" or "v", false
								)
							end

							if Element._Expanded then
								local OptionsRegion = Element._OptionsRegion
								for ItemIndex, ItemData in ipairs(Element._ItemDrawingObjects) do
									local ItemYPosition = WindowPosition.Y + ItemData._PositionY - Window._ScrollOffset
									local ItemSize = Vector2.new(ElementSize.X, Theme.ElementHeight)
									local ItemPosition = Vector2.new(WindowPosition.X + ItemData._PositionX, ItemYPosition)
									local ItemAllowedMinY = AllowedMinY
									local ItemAllowedMaxY = AllowedMaxY
									if OptionsRegion then
										ItemAllowedMinY = math.max(ItemAllowedMinY, OptionsRegion.Position.Y)
										ItemAllowedMaxY = math.min(ItemAllowedMaxY, OptionsRegion.Position.Y + OptionsRegion.Size.Y)
									end
									local ClippedItemPos, ClippedItemSize = ClipRectangleToYRange(ItemPosition, ItemSize, ItemAllowedMinY, ItemAllowedMaxY)
									if ClippedItemPos and ClippedItemSize then
										local IsHovered = IsPointInsideRectangle(CurrentMousePosition, ItemPosition, ItemSize)
											and CurrentMousePosition.Y >= ItemAllowedMinY
											and CurrentMousePosition.Y <= ItemAllowedMaxY
										DrawingImmediateFilledRectangle(ClippedItemPos, ClippedItemSize, IsHovered and Theme.DropdownItemHover or Theme.DropdownItemBackground, 1, 0)

										local ItemSeparatorY = ItemYPosition + Theme.ElementHeight - 1
										local SepFrom, SepTo = ClipHorizontalLineToYRange(
											Vector2.new(ItemPosition.X + 6, ItemSeparatorY),
											Vector2.new(ItemPosition.X + ItemSize.X - 6, ItemSeparatorY),
											ItemAllowedMinY, ItemAllowedMaxY
										)
										if SepFrom and SepTo then
											DrawingImmediateLine(SepFrom, SepTo, Theme.WindowBorder, 0.5, 1)
										end

										local ItemTextY = ItemYPosition + (Theme.ElementHeight - Theme.ElementFontSize) / 2
										if ItemTextY >= ItemAllowedMinY and ItemTextY + Theme.ElementFontSize <= ItemAllowedMaxY then
											-- Truncate item text if it exceeds the option area bounds.
											local AvailableItemTextWidth = ItemSize.X - 24
											local CharacterWidth = GetEditableTextCharacterWidth(Theme.ElementFontSize)
											local MaximumCharacters = math.max(1, math.floor(AvailableItemTextWidth / CharacterWidth))
											local DisplayItemText = TruncateTextWithAsciiEllipsis(Element:GetOptionDisplayText(ItemData.Value), MaximumCharacters)
											DrawingImmediateText(
												Vector2.new(WindowPosition.X + ItemData._PositionX + 12, ItemTextY),
												Theme.Font, Theme.ElementFontSize, IsHovered and Theme.TitleBarText or Theme.DropdownText, 1, DisplayItemText, false
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
							local SliderTextMetrics = Theme:GetSliderTextLayoutMetrics(
								Element,
								Vector2.new(WindowPosition.X + Element._PositionX, ElementYPosition),
								Element._AvailableWidth or Element._TrackTotalWidth
							)
							local TextY = SliderTextMetrics.LabelPosition.Y
							if TextY >= AllowedMinY and TextY + Theme.ElementFontSize <= AllowedMaxY then
								DrawingImmediateText(
									SliderTextMetrics.LabelPosition,
									Theme.Font, Theme.ElementFontSize, SliderLabelColor, 1, SliderTextMetrics.LabelDisplayText, false
								)
								local ValueColor = Theme.SectionText:Lerp(Theme.SectionTextHover, Element._ActiveFactor or 0)
								DrawingImmediateText(
									SliderTextMetrics.ValuePosition,
									Theme.Font, Theme.ElementFontSize, ValueColor, 1, SliderTextMetrics.ValueDisplayText, false
								)
							end

							local TrackHeight = LerpValue(
								Theme.SliderTrackHeight,
								Theme.SliderTrackHoverHeight,
								Element._HoverFactor or 0
							)
							local TrackPosition = Vector2.new(
								WindowPosition.X + (Element._TrackPositionX or Element._PositionX),
								WindowPosition.Y + (Element._TrackPositionY or Element._PositionY)
									- Window._ScrollOffset
									- (TrackHeight - Theme.SliderTrackHeight) / 2
							)
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

							local ThumbRadius = LerpValue(
								Theme.SliderThumbRadius,
								Theme.SliderThumbHoverRadius,
								Element._ThumbHoverFactor or 0
							)
							ThumbRadius = math.min(
								ThumbRadius,
								(Element._AvailableWidth or Element._TrackTotalWidth) / 2
							)
							local ThumbColor = Theme.SliderTrackFill:Lerp(
								Theme.SliderTrackFillHover,
								Element._ThumbHoverFactor or 0
							)
							local ThumbY = TrackPosition.Y + TrackHeight / 2
							if ThumbY - ThumbRadius >= AllowedMinY and ThumbY + ThumbRadius <= AllowedMaxY then
								DrawImmediateSolidCircle(Vector2.new(TrackPosition.X + FillWidth, ThumbY), ThumbRadius, ThumbColor, 1, 64)
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
						DrawImmediateExecutorLock(
							Element,
							ElementPosition,
							ElementSize,
							AllowedMinY,
							AllowedMaxY
						)
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

			local ResizeGripCornerInset = Window._TouchInputAvailable and 7 or 5
			local ResizeGripLineSpacing = Window._TouchInputAvailable and 6 or 4
			local ResizeGripCornerPosition = Vector2.new(
				WindowPosition.X + WindowWidth - ResizeGripCornerInset,
				WindowPosition.Y + Theme.TitleBarHeight + ContentHeight - ResizeGripCornerInset
			)
			local ResizeGripColor = Window._ResizeGripHovered and Theme.TitleBarTextHover or Theme.TitleBarSeparator
			for ResizeGripLineIndex = 1, 3 do
				local ResizeGripOffset = ResizeGripLineIndex * ResizeGripLineSpacing
				DrawingImmediateLine(
					ResizeGripCornerPosition - Vector2.new(ResizeGripOffset, 0),
					ResizeGripCornerPosition - Vector2.new(0, ResizeGripOffset),
					ResizeGripColor,
					Window._ResizeGripHovered and 0.9 or 0.42,
					Window._TouchInputAvailable and 2 or 1.35
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
				DrawingImmediateCircle(TextboxIconCenter, 3.5, Theme.TextBoxPlaceholder, 1, 48, 1)
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
				local CharacterWidth = GetEditableTextCharacterWidth(Theme.ElementFontSize)
				local MaxQueryChars = math.max(1, math.floor(AvailableQueryWidth / CharacterWidth))
				SearchDisplayText = GetTextBoxVisibleText(
					Window._SearchTextBox,
					SearchDisplayText,
					MaxQueryChars,
					Window._SearchTextBox._Value ~= ""
				)

				DrawImmediateTextBoxSelectionAndCursor(
					Window._SearchTextBox,
					SearchBarPosition.X + 24,
					SearchBarPosition.Y + (20 - Theme.ElementFontSize) / 2,
					CharacterWidth,
					MaxQueryChars,
					ViewportStart,
					ViewportEnd,
					HasSearchValue
				)

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
					local HighlightAbsoluteSize = Vector2.new(Theme:GetElementAvailableWidth(HighlightElement, Window), HighlightElement._Height)

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
				local ColorPickerMousePosition = Window:GetCurrentPointerPosition()
				for SwatchIndex = 1, #ColorPalette do
					local ColumnIndex = (SwatchIndex - 1) % Columns
					local RowIndex    = math.floor((SwatchIndex - 1) / Columns)
					local SwatchX = PopupPosition.X + Margin + ColumnIndex * (SwatchSize + SwatchGap)
					local SwatchY = GridStartY + RowIndex * (SwatchSize + SwatchGap)
					local SwatchPos  = Vector2.new(SwatchX, SwatchY)
					local SwatchSizeVector  = Vector2.new(SwatchSize, SwatchSize)
					local IsSelected = (SwatchIndex == ColorPicker._TempSelectedSwatchIndex)
					local IsHovered = IsPointInsideRectangle(ColorPickerMousePosition, SwatchPos, SwatchSizeVector)
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

			local TooltipGeometry = GetTooltipGeometry(Window, CurrentMousePosition)
			if TooltipGeometry then
				DrawingImmediateFilledRectangle(TooltipGeometry.Position, TooltipGeometry.Size, Theme.TooltipBackground, 0.98, 0)
				DrawingImmediateRectangle(TooltipGeometry.Position, TooltipGeometry.Size, Theme.TooltipBorder, 0.9, 0, 1)
				for TooltipLineIndex, TooltipLine in ipairs(TooltipGeometry.Lines) do
					DrawingImmediateText(
						TooltipGeometry.Position + Vector2.new(
							Theme.TooltipPadding,
							Theme.TooltipPadding + (TooltipLineIndex - 1) * FontLineHeight(Theme.ElementFontSize)
						),
						Theme.Font,
						Theme.ElementFontSize,
						Theme.TooltipText,
						1,
						TooltipLine,
						false
					)
				end
			end

			-- Immediate notifications have no retained objects to move, so refresh
			-- their shared positions immediately before painting every frame.
			RepositionNotificationStack(Window._ActiveNotifications, Window._Position)
			local PaintNotificationsList = {}
			for NotificationIndex, Entry in ipairs(Library.ActiveNotifications) do
				table.insert(PaintNotificationsList, Entry)
			end
			for NotificationIndex, Entry in ipairs(Window._ActiveNotifications) do
				table.insert(PaintNotificationsList, Entry)
			end

			for NotificationIndex, Entry in ipairs(PaintNotificationsList) do
				-- Keep this fallback local to the paint callback. Referencing another
				-- outer helper here would exceed Lua 5.1's upvalue limit for CreateWindow.
				local NotificationSize = typeof(Entry.Size) == "Vector2"
					and Entry.Size
					or Vector2.new(Theme.NotificationWidth, Theme.NotificationHeight)
				DrawingImmediateFilledRectangle(Entry.Position, NotificationSize, Theme.NotificationBackground, 1, 0)
				DrawingImmediateRectangle(Entry.Position, NotificationSize, Theme.NotificationBorder, 0.8, 0, 1)

				DrawingImmediateLine(
					Vector2.new(Entry.Position.X + 3, Entry.Position.Y + 4),
					Vector2.new(Entry.Position.X + 3, Entry.Position.Y + NotificationSize.Y - 4),
					Theme.NotificationAccent, 1, 2
				)
				for TextLineIndex, TextLine in ipairs(Entry.Lines or { Entry.Text }) do
					DrawingImmediateText(
						Vector2.new(
							Entry.Position.X + Theme.NotificationHorizontalPadding,
							Entry.Position.Y
								+ (Entry.TextStartOffsetY or Theme.NotificationVerticalPadding)
								+ (TextLineIndex - 1)
									* FontLineHeight(Theme.ElementFontSize)
						),
						Theme.Font,
						Theme.ElementFontSize,
						Theme.NotificationText,
						1,
						TextLine,
						false
					)
				end
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
		-- Desktop retains the original proportional scale, which produced the dense
		-- two-column layout on common 1200- and 1680-wide displays. Touch screens keep
		-- a larger lower bound so controls remain comfortable to press.
		local MinimumScale = Window._TouchInputAvailable and 0.78 or 0.62
		local Scale = math.clamp(RawScale, MinimumScale, 1.35)
		Window._CurrentViewportScale = Scale

		for ParameterKey, BaseValue in pairs(Theme.Base) do
			Theme[ParameterKey] = BaseValue * Scale
		end

		-- Section MaxHeight values belong to the same design coordinate system as
		-- the theme dimensions. Recalculate from the immutable authored value so
		-- local panel viewports and their scrollbars remain aligned after a display
		-- resize, orientation change, or a different desktop resolution.
		for SectionIndex, Section in ipairs(Window._Sections) do
			if Section._BaseMaximumHeight then
				Section._MaxHeight = Section._BaseMaximumHeight * Scale
			end
		end

		Window:ApplyTouchViewportGeometry(Viewport, Scale, false)

		Window._TabBarHeight = 34 * Scale
		Window._VisibleHeight = Theme.WindowVisibleHeight

		-- Keep the window inside the visible camera area after a resize, display
		-- mode change, or mobile rotation.
		local MaximumPositionX = math.max(8, Viewport.X - Theme.WindowWidth - 8)
		local MaximumPositionY = math.max(8, Viewport.Y - (Theme.TitleBarHeight + Window._VisibleHeight) - 8)
		if Window._TouchInputAvailable and not Window._ViewportScaleInitialized then
			Window._Position = Vector2.new(
				math.max(8, (Viewport.X - Theme.WindowWidth) / 2),
				math.max(8, (Viewport.Y - Theme.TitleBarHeight - Window._VisibleHeight) / 2)
			)
		else
			Window._Position = Vector2.new(
				math.clamp(Window._Position.X, 8, MaximumPositionX),
				math.clamp(Window._Position.Y, 8, MaximumPositionY)
			)
		end

		Window._ViewportScaleInitialized = true
		Window:UpdateTouchLauncherDrawings()
	end

	local ViewportConnection
	local function ConnectViewport()
		if ViewportConnection then
			pcall(ViewportConnection.Disconnect, ViewportConnection)
			ViewportConnection = nil
		end
		local Camera = GetCurrentCamera()
		if Camera then
			local ViewportSizeChangedSignal = GetPropertyChangedSignal(Camera, "ViewportSize")
			ViewportConnection = ConnectSignal(ViewportSizeChangedSignal, NewCClosure(function()
				UpdateViewportScale()
				Window:RecalculateLayout()
			end))
			table.insert(Window._Connections, ViewportConnection)
		end
	end

	local CurrentCameraChangedSignal = GetPropertyChangedSignal(Workspace, "CurrentCamera")
	local CameraConnection = ConnectSignal(CurrentCameraChangedSignal, NewCClosure(function()
		ConnectViewport()
		UpdateViewportScale()
		Window:RecalculateLayout()
	end))
	table.insert(Window._Connections, CameraConnection)

	if Window._TouchInputAvailable then
		-- Roblox can rebuild the top bar after orientation, chat, menu, or safe-area
		-- changes without changing the camera viewport. Track TopbarInset directly
		-- so the retained launcher follows the panel just as immediate mode does.
		local TopbarInsetChangedSignal = GetPropertyChangedSignal(
			GraphicalUserInterfaceService,
			"TopbarInset"
		)
		local TopbarInsetConnection = ConnectSignal(TopbarInsetChangedSignal, NewCClosure(function()
			Window:UpdateTouchLauncherDrawings()
		end))
		table.insert(Window._Connections, TopbarInsetConnection)
	end

	ConnectViewport()
	UpdateViewportScale()

	Window:RecalculateLayout()
	if Window._TouchInputAvailable then
		Window:SetInputBlocking("TouchInterface", true)
	end

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
	if not SupportedInputBlockingTypes[Type] then
		return false
	end

	local ShouldEnable = Enabled == true
	if Library._ActiveSinkStates[Type] == ShouldEnable then
		return true
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
				if InputObject and InputObject.UserInputType == Enum.UserInputType.MouseWheel then
					Library:ProcessMouseWheel(InputObject)
				end
				return Enum.ContextActionResult.Sink
			end, false, Priority, Enum.UserInputType.MouseWheel)
		elseif Type == "TouchInterface" then
			BindCoreActionAtPriority(ContextActionService, NewName, function(ActionName, InputState, InputObject)
				if not InputObject or InputObject.UserInputType ~= Enum.UserInputType.Touch then
					return Enum.ContextActionResult.Pass
				end

				local PointerPosition = GetTouchInputScreenPosition(InputObject)
				for RequestedWindow, RequestTable in pairs(Library._InputBlockingRequests) do
					if RequestTable.TouchInterface and RequestedWindow and not RequestedWindow._Destroyed then
						-- Route the touch through the same high-priority action that blocks
						-- CoreGui. Merely sinking here and waiting for UserInputService made
						-- taps unreliable on Android, especially above Roblox menus.
						if typeof(RequestedWindow.ProcessTouchInput) == "function" then
							local ProcessingSucceeded, TouchWasHandled = pcall(
								RequestedWindow.ProcessTouchInput,
								RequestedWindow,
								InputState,
								InputObject
							)
							if ProcessingSucceeded and TouchWasHandled then
								return Enum.ContextActionResult.Sink
							end
						end

						local TouchInteractionState = RequestedWindow._TouchInteractionState
						if TouchInteractionState and TouchInteractionState.ActiveInputObject == InputObject then
							return Enum.ContextActionResult.Sink
						end

						if RequestedWindow._Visible and Library._Visible then
							local TitlePosition = RequestedWindow._Position
							local TitleSize = Vector2.new(Theme.WindowWidth, Theme.TitleBarHeight)
							local BodyPosition = TitlePosition + Vector2.new(0, Theme.TitleBarHeight)
							local BodySize = Vector2.new(Theme.WindowWidth, RequestedWindow._VisibleHeight)
							if IsPointInsideRectangle(PointerPosition, TitlePosition, TitleSize)
								or IsPointInsideRectangle(PointerPosition, BodyPosition, BodySize)
							then
								return Enum.ContextActionResult.Sink
							end
						elseif RequestedWindow.IsPointInsideTouchLauncher
							and RequestedWindow:IsPointInsideTouchLauncher(PointerPosition)
						then
							return Enum.ContextActionResult.Sink
						end
					end
				end

				return Enum.ContextActionResult.Pass
			end, false, Priority, Enum.UserInputType.Touch)
		elseif Type == "Interface" then
			BindCoreActionAtPriority(ContextActionService, NewName, function(ActionName, InputState, InputObject)
				if InputObject and InputObject.UserInputType == Enum.UserInputType.MouseWheel then
					Library:ProcessMouseWheel(InputObject)
				end
				return Enum.ContextActionResult.Sink
			end, false, Priority,
				Enum.UserInputType.MouseButton1,
				Enum.UserInputType.MouseButton2,
				Enum.UserInputType.MouseButton3,
				Enum.UserInputType.MouseWheel
			)
		elseif Type == "Camera" then
			BindCoreActionAtPriority(ContextActionService, NewName, function(ActionName, InputState, InputObject)
				if InputObject and InputObject.UserInputType == Enum.UserInputType.MouseWheel then
					Library:ProcessMouseWheel(InputObject)
				end
				return Enum.ContextActionResult.Sink
			end, false, Priority,
				Enum.UserInputType.MouseButton2,
				Enum.UserInputType.MouseWheel
			)
		end
	end
	return true
end

return Library
