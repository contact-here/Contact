local CloneFunction, CloneReference, NewCClosure, SetClipboard, GetClipboard
local LastCopiedText = ""

do

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
		CloneFunction = function(TargetFunction)
			return TargetFunction
		end
	end

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
		CloneReference = function(TargetReference)
			return TargetReference
		end
	end

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
		NewCClosure = function(TargetFunction)
			return TargetFunction
		end
	end


	local RawSetClipboard = setclipboard or toclipboard or set_clipboard

	SetClipboard = RawSetClipboard and function(Text)
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
		LastCopiedText = Text
		return Text
	end

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

do
	local GetService = CloneFunction(game.GetService)

	UserInputService     = CloneReference(GetService(game, "UserInputService"))
	RunService           = CloneReference(GetService(game, "RunService"))
	ContextActionService = CloneReference(GetService(game, "ContextActionService"))
	Workspace            = CloneReference(GetService(game, "Workspace"))
end

local GetMouseLocation, IsMouseButtonPressed, IsKeyDown
local GetStringForKeyCode, GetKeysPressed, GetMouseButtonsPressed
local GetDeviceType
local HeartbeatSignalConnect
local BindCoreActionAtPriority, UnbindCoreAction
local InputBeganSignalConnect, InputChangedSignalConnect
local WindowFocusReleasedConnect, WindowFocusedConnect

do

	GetMouseLocation     = CloneFunction(UserInputService.GetMouseLocation)
	IsMouseButtonPressed = CloneFunction(UserInputService.IsMouseButtonPressed)
	IsKeyDown            = CloneFunction(UserInputService.IsKeyDown)
	GetStringForKeyCode  = CloneFunction(UserInputService.GetStringForKeyCode)

	GetKeysPressed           = CloneFunction(UserInputService.GetKeysPressed)

	GetMouseButtonsPressed   = CloneFunction(UserInputService.GetMouseButtonsPressed)
	GetDeviceType            = CloneDeviceType and CloneFunction(GetDeviceType) or function() return "Unknown" end

	HeartbeatSignalConnect = CloneFunction(RunService.Heartbeat.Connect)

	BindCoreActionAtPriority = CloneFunction(ContextActionService.BindCoreActionAtPriority)
	UnbindCoreAction         = CloneFunction(ContextActionService.UnbindCoreAction)

	InputBeganSignalConnect   = CloneFunction(UserInputService.InputBegan.Connect)
	InputChangedSignalConnect = CloneFunction(UserInputService.InputChanged.Connect)

	WindowFocusReleasedConnect = CloneFunction(UserInputService.WindowFocusReleased.Connect)
	WindowFocusedConnect       = CloneFunction(UserInputService.WindowFocused.Connect)
end

local SetRenderProperty, GetRenderProperty, IsRenderObject, ClearDrawCache

do
	local RawSetRenderProperty = typeof(setrenderproperty) == "function"
		and CloneFunction(setrenderproperty)

	SetRenderProperty = function(TargetObject, PropertyName, PropertyValue)
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

if typeof(Drawing) == "table" and typeof(Drawing.new) == "function" then
	local NativeCheckSuccess, NativeCheckSource = pcall(debug.info, Drawing.new, "s")
	if NativeCheckSuccess and NativeCheckSource == "[C]" then
		DrawingIsNative = true
	end
end

if not DrawingIsNative then
	local CustomDrawingLibraryLink = "https://raw.githubusercontent.com/placeholder-link-here/Drawing.lua"
	local RawHttpGet = game.HttpGet
	local RawRequestFunction = request or http_request or (syn and syn.request)
	local FetchedContent

	if RawRequestFunction then
		local RequestSuccess, RequestResult = pcall(RawRequestFunction, { Url = CustomDrawingLibraryLink, Method = "GET" })
		if RequestSuccess and RequestResult and (RequestResult.StatusCode == 200 or RequestResult.Status == 200) then
			FetchedContent = RequestResult.Body
		end
	end

	if not FetchedContent and RawHttpGet then
		local HttpGetSuccess, HttpGetResult = pcall(RawHttpGet, game, CustomDrawingLibraryLink)
		if HttpGetSuccess then
			FetchedContent = HttpGetResult
		end
	end

	if FetchedContent then
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


local function LerpValue(StartValue, EndValue, Factor)
	return StartValue + (EndValue - StartValue) * Factor
end

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

local function IsPointInsideRectangle(TestPoint, RectangleOrigin, RectangleSize)
	return TestPoint.X >= RectangleOrigin.X
		and TestPoint.X <= RectangleOrigin.X + RectangleSize.X
		and TestPoint.Y >= RectangleOrigin.Y
		and TestPoint.Y <= RectangleOrigin.Y + RectangleSize.Y
end

local function RandomString(Length)
	local Characters = "abcdefghijklmnopqrstuvwxyz0123456789"
	local Result = {}

	for Index = 1, Length do
		local RandomIndex = math.random(1, #Characters)
		Result[Index] = string.sub(Characters, RandomIndex, RandomIndex)
	end

	return table.concat(Result)
end

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
			local TestLine = CurrentLine == "" and Word or (CurrentLine .. " " .. Word)

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

local Theme = {

	WindowBackground  = Color3.fromRGB(10, 10, 13),
	WindowBorder      = Color3.fromRGB(55, 50, 70),
	WindowBorderHover = Color3.fromRGB(90, 75, 130),

	TitleBarBackground     = Color3.fromRGB(14, 13, 18),
	TitleBarBackgroundHover= Color3.fromRGB(22, 20, 30),
	TitleBarSeparator      = Color3.fromRGB(110, 90, 200),
	TitleBarText           = Color3.fromRGB(245, 242, 255),
	TitleBarTextHover      = Color3.fromRGB(255, 255, 255),

	SectionBackground      = Color3.fromRGB(18, 17, 25),
	SectionBackgroundHover = Color3.fromRGB(26, 24, 36),
	SectionText            = Color3.fromRGB(160, 130, 255),
	SectionTextHover       = Color3.fromRGB(195, 165, 255),

	LabelText      = Color3.fromRGB(185, 180, 200),
	LabelTextHover = Color3.fromRGB(220, 215, 240),

	ButtonBackground      = Color3.fromRGB(30, 27, 42),
	ButtonBackgroundHover = Color3.fromRGB(55, 48, 78),
	ButtonText            = Color3.fromRGB(235, 230, 255),
	ButtonBorder          = Color3.fromRGB(65, 58, 88),

	TextBoxBackground      = Color3.fromRGB(16, 15, 24),
	TextBoxBackgroundHover = Color3.fromRGB(24, 22, 36),
	TextBoxBorder          = Color3.fromRGB(60, 55, 82),
	TextBoxBorderFocused   = Color3.fromRGB(120, 95, 220),
	TextBoxText            = Color3.fromRGB(220, 215, 235),
	TextBoxPlaceholder     = Color3.fromRGB(80, 75, 105),
	TextBoxCursor          = Color3.fromRGB(170, 145, 255),

	DropdownBackground    = Color3.fromRGB(22, 20, 32),
	DropdownHover         = Color3.fromRGB(30, 27, 42),
	DropdownItemBackground= Color3.fromRGB(18, 17, 26),
	DropdownItemHover     = Color3.fromRGB(50, 44, 70),
	DropdownText          = Color3.fromRGB(215, 210, 230),
	DropdownBorder        = Color3.fromRGB(60, 55, 80),
	DropdownBorderHover   = Color3.fromRGB(120, 100, 180),
	DropdownArrow         = Color3.fromRGB(130, 115, 175),

	SliderTrackBackground = Color3.fromRGB(22, 20, 32),
	SliderTrackFill       = Color3.fromRGB(120, 90, 255),
	SliderTrackFillHover  = Color3.fromRGB(150, 115, 255),
	SliderThumb           = Color3.fromRGB(220, 210, 255),
	SliderThumbHover      = Color3.fromRGB(255, 245, 255),
	SliderText            = Color3.fromRGB(215, 210, 230),
	SliderBorder          = Color3.fromRGB(55, 50, 75),

	ColorPickerBorder      = Color3.fromRGB(55, 50, 75),
	ColorPickerSelectedBorder = Color3.fromRGB(180, 150, 255),
	ColorPickerSwatchHover = Color3.fromRGB(210, 180, 255),

	ScrollbarBackground  = Color3.fromRGB(22, 20, 30),
	ScrollbarHandle      = Color3.fromRGB(100, 85, 150),
	ScrollbarHandleHover = Color3.fromRGB(140, 120, 200),

	NotificationBackground = Color3.fromRGB(14, 13, 20),
	NotificationBorder     = Color3.fromRGB(90, 75, 135),
	NotificationText       = Color3.fromRGB(235, 230, 250),
	NotificationAccent     = Color3.fromRGB(110, 90, 200),

	SaveButtonBackground = Color3.fromRGB(25, 65, 45),
	SaveButtonHover      = Color3.fromRGB(35, 90, 62),
	ExitButtonBackground = Color3.fromRGB(75, 22, 30),
	ExitButtonHover      = Color3.fromRGB(105, 30, 42),
	CloseButtonHover     = Color3.fromRGB(210, 55, 70),

	SectionHover = Color3.fromRGB(22, 20, 30),

	Font            = 2,
	TitleFontSize   = 14,
	SectionFontSize = 13,
	ElementFontSize = 13,

	FontCharWidthRatio = 0.52,

	FontLineHeightRatio = 1.35,

	FontVerticalPaddingRatio = 0.5,

	FontHorizontalInsetRatio = 0.65,

	WindowWidth         = 500,
	TitleBarHeight      = 32,
	WindowVisibleHeight = 540,
	ElementHeight       = 28,
	ElementPadding      = 6,
	SectionPadding      = 10,
	InnerMargin         = 12,
	ScrollbarWidth      = 5,

	ColorSwatchSize = 24,
	ColorSwatchGap  = 4,

	NotificationWidth    = 260,
	NotificationHeight   = 36,
	NotificationDuration = 5,
	NotificationMargin   = 12,
}

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

local function ClipHorizontalLineToYRange(From, To, MinY, MaxY)
	local Y = From.Y
	if Y >= MinY and Y <= MaxY then
		return From, To
	else
		return nil, nil
	end
end

local function GetSectionAllowedYRange(Section, Window, WindowPositionY)
	local ViewportStart = WindowPositionY + Theme.TitleBarHeight
	local ViewportEnd = ViewportStart + Window._VisibleHeight
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

local function IsElementVisibleInViewport(ElementAbsolutePositionY, ElementHeight, Section, Window, WindowPositionY)
	if not Window._Visible then
		return false
	end

	local ViewportStart = WindowPositionY + Theme.TitleBarHeight
	local ViewportEnd = ViewportStart + Window._VisibleHeight
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

local function ApplyDrawingProperties(DrawingObject, Properties)
	if not DrawingObject then 
		return 
	end

	for PropertyName, PropertyValue in pairs(Properties) do
		SetRenderProperty(DrawingObject, PropertyName, PropertyValue)
	end
end

local function DestroyTrackedDrawingTable(DrawingTable)
	for ObjectIndex = #DrawingTable, 1, -1 do
		local DrawingObject = DrawingTable[ObjectIndex]
		if DrawingObject then
			pcall(DrawingObject.Destroy, DrawingObject)
		end
		DrawingTable[ObjectIndex] = nil
	end
end

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

local function DestroyDrawing(DrawingObject, TrackedDrawingsTable)
	if DrawingObject then
		if TrackedDrawingsTable then
			RemoveTrackedDrawing(TrackedDrawingsTable, DrawingObject)
		end
		pcall(DrawingObject.Destroy, DrawingObject)
	end
end

local function MakeDrawingFactory(TrackedDrawingsTable)
	local function CreateTrackedDrawingObject(ObjectType)
		if not DrawingBackendAvailable or UseImmediateMode then 
			return nil 
		end

		local DrawingObject = Drawing.new(ObjectType)
		table.insert(TrackedDrawingsTable, DrawingObject)

		return DrawingObject
	end

	local function CreateRectangleDrawing(FillColor, IsFilled, ZIndexValue, TransparencyValue)
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

local NotificationTrackedDrawings = {}
local CreateNotificationDrawingObject, CreateNotificationRectangleDrawing, CreateNotificationTextDrawing = MakeDrawingFactory(NotificationTrackedDrawings)

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
					local TabWidth = math.max(80, Theme.WindowWidth / math.min(TabCount, 5))
					local MaxTabScroll = math.max(0, (TabCount * TabWidth) - Theme.WindowWidth)
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
						Library:SetInputBlocking("Typing", false)
						return false
					elseif Input.KeyCode == Enum.KeyCode.Space then
						if FocusedBox._IsSelected then
							FocusedBox:SetValue(" ")
							FocusedBox._IsSelected = false
						else
							FocusedBox:SetValue(FocusedBox._Value .. " ")
						end
						return true
					elseif CtrlHeld and Input.KeyCode == Enum.KeyCode.V then
						local ClipboardText = GetClipboard()

						if ClipboardText and #ClipboardText > 0 then
							if FocusedBox._IsSelected then
								FocusedBox:SetValue(ClipboardText)
								FocusedBox._IsSelected = false
							else
								FocusedBox:SetValue(FocusedBox._Value .. ClipboardText)
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
								FocusedBox:SetValue(FocusedBox._Value .. Character)
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

function Library:Destroy()
	for ConnectionIndex, Connection in ipairs(Library.Connections) do
		if Connection then
			pcall(Connection.Disconnect, Connection)
		end
	end
	Library.Connections = {}

	for WindowIndex, Window in ipairs(Library._Windows) do
		if Window and not Window._Destroyed then
			pcall(Window.Destroy, Window)
		end
	end
	Library._Windows = {}

	DestroyTrackedDrawingTable(NotificationTrackedDrawings)
	NotificationTrackedDrawings = {}
end

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
	local VerticalStackOffset = #ActiveNotificationsList * (Theme.NotificationHeight + Theme.NotificationMargin)

	local NotificationPosition = Vector2.new(
		TargetPosition.X + Theme.WindowWidth + Theme.NotificationMargin,
		TargetPosition.Y + VerticalStackOffset
	)

	local NotificationEntry = {
		Text = NotificationText,
		Position = NotificationPosition,
		CreatedAt = tick(),
		Window = TargetWindow,
	}

	if not UseImmediateMode then

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
		for EntryIndex, Entry in ipairs(ActiveNotificationsList) do
			if Entry == NotificationEntry then
				table.remove(ActiveNotificationsList, EntryIndex)

				for RemainingIndex, RemainingEntry in ipairs(ActiveNotificationsList) do
					local NewY = TargetPosition.Y + (RemainingIndex - 1) * (Theme.NotificationHeight + Theme.NotificationMargin)
					RemainingEntry.Position = Vector2.new(RemainingEntry.Position.X, NewY)
					
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
		Theme = setmetatable({
			WindowWidth     = 340,
			ElementHeight   = 36,
			TitleBarHeight  = 40,
		}, { __index = Theme })
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
	Window._TitleTextHovered = false
	Window._DragOffset = Vector2.new(0, 0)

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

	Window._DrawingObjects = {}

	Window._ActiveDropdown = nil
	Window._ActiveSlider = nil

	Window._Pages = {}
	Window._ActivePageIndex = 1
	Window._TabBarHeight = 28
	Window._TabDrawings = {}
	Window._TabScrollOffset = 0

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
	local TitleBarBorderDrawing = nil
	local TitleBarTextDrawing = nil
	local WindowBodyBackgroundDrawing = nil
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

		CloseButtonBackgroundDrawing = CreateRectangleDrawing(Color3.fromRGB(160, 40, 52), true, 5, 0.9)
		CloseButtonBorderDrawing = CreateRectangleDrawing(Color3.fromRGB(120, 40, 50), false, 6, 0.9)
		CloseButtonTextDrawing = CreateTextDrawing("X", 13, Color3.fromRGB(255, 220, 225), 7)
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
			Thickness = 2,
			Transparency = 1,
			Color = Theme.TitleBarSeparator,
			ZIndex = 5,
			Visible = true,
		})


		Window._GlowDrawings = {}
		for GlowIndex = 1, 3 do
			Window._GlowDrawings[GlowIndex] = CreateRectangleDrawing(Theme.TitleBarSeparator, false, 0, 0.15 / GlowIndex)
		end

		Window._CornerBrackets = {}

		for BracketIndex = 1, 8 do
			Window._CornerBrackets[BracketIndex] = CreateTrackedDrawingObject("Line")
			ApplyDrawingProperties(Window._CornerBrackets[BracketIndex], {
				Thickness = 2,
				Color = Theme.TitleBarSeparator,
				ZIndex = 4,
				Visible = true,
			})
		end

		Window._SideTicks = {}
		for TickIndex = 1, 4 do
			Window._SideTicks[TickIndex] = CreateTrackedDrawingObject("Line")
			ApplyDrawingProperties(Window._SideTicks[TickIndex], {
				Thickness = 1.5,
				Color = Theme.TitleBarSeparator,
				ZIndex = 4,
				Visible = true,
			})
		end

		Window._SearchIconCircle = CreateTrackedDrawingObject("Circle")
		ApplyDrawingProperties(Window._SearchIconCircle, {
			Radius = 4,
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
			WindowBodyBackgroundDrawing, WindowBodyBorderDrawing,
			TitleBarBackgroundDrawing, TitleBarBorderDrawing, TitleBarTextDrawing,
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
		_Placeholder = "Search elements...",
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
		local ViewportStart = WindowPosition.Y + Theme.TitleBarHeight + Window._TabBarHeight
		local ViewportEnd = ViewportStart + Window._VisibleHeight

		local SearchBarHeightOffset = 0
		if Window._SearchActive then
			SearchBarHeightOffset = 32
		end

		local ColumnWidth = (Theme.WindowWidth - (Theme.InnerMargin * 3)) / 2
		local ColumnOnePositionY = Theme.SectionPadding + SearchBarHeightOffset
		local ColumnTwoPositionY = Theme.SectionPadding + SearchBarHeightOffset

		
		if not UseImmediateMode and #Window._Pages > 0 then
			for _, Sec in ipairs(Window._Sections) do
				if Sec._PageIndex and Sec._PageIndex ~= Window._ActivePageIndex then
					local VisibilityObjects = { Sec._FullBackground, Sec._Background, Sec._Border, Sec._TextLabel, Sec._AccentLine, Sec._LeftAccentLine, Sec._TopRightTechLine }
					if Sec._CornerBrackets then
						for _, LineObject in ipairs(Sec._CornerBrackets) do
							table.insert(VisibilityObjects, LineObject)
						end
					end
					SetDrawingObjectsVisibility(VisibilityObjects, false)
					for _, Element in ipairs(Sec._Elements) do
						if Element._Type == "TextLabel" then
							SetDrawingObjectsVisibility({ Element._AccentLineDrawing }, false)
							for _, LineObj in ipairs(Element._LineDrawings or {}) do
								SetRenderProperty(LineObj, "Visible", false)
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
							for _, ItemData in ipairs(Element._ItemDrawingObjects) do
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

			local HasScrollbar = Section._MaxHeight and Section._FullContentHeight and Section._FullContentHeight > Section._MaxHeight
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
						for LineIndex, LineObj in ipairs(Element._LineDrawings) do
							local LineY = ElementAbsolutePosition.Y + VerticalPadding + (LineIndex - 1) * LineHeight
							local IsLineVisible = IsElementVisible and (LineY >= AllowedMinY) and (LineY + LineHeight <= AllowedMaxY)
							ApplyDrawingProperties(LineObj, {
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
							local PipColor = Color3.fromRGB(80, 75, 100):Lerp(Color3.fromRGB(80, 220, 120), Element._ActiveFactor or 0)
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
							local ClippedText = DisplayText
							if #DisplayText > MaxChars then
								if Element._IsFocused then
									ClippedText = DisplayText:sub(#DisplayText - MaxChars + 1)
								else
									ClippedText = DisplayText:sub(1, MaxChars - 1) .. "\xe2\x80\xa6"
								end
							end
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
						local ValueColor = Theme.SectionText:Lerp(Color3.fromRGB(220, 200, 255), Element._ActiveFactor or 0)
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
						local NormalizedValue = (Element._Value - Element._MinValue) / Range
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
			if Section._MaxHeight and SectionContentHeight > Section._MaxHeight then
				Section._ClippedHeight = Section._MaxHeight
				Section._SectionMaxScroll = SectionContentHeight - Section._MaxHeight + Theme.ElementHeight + Theme.ElementPadding
				Section._SectionScrollOffset = math.clamp(Section._SectionScrollOffset or 0, 0, Section._SectionMaxScroll)
				Section._ContentHeight = Section._MaxHeight
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
						ApplyDrawingProperties(Section._FullBackground, { Position = ClippedPos, Size = ClippedSize, Visible = IsSectionVisible })
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
							Visible = IsSectionVisible,
						})
					else
						ApplyDrawingProperties(Section._LeftAccentLine, { Visible = false })
					end
				end

				if Section._MaxHeight and Section._SectionMaxScroll > 0 then
					local ScrollbarPositionX = SectionAbsolutePosition.X + Section._Width - Theme.ScrollbarWidth - 2
					local ScrollbarPositionY = SectionAbsolutePosition.Y + Theme.ElementHeight + 2
					local ScrollbarHeight = Section._ContentHeight - Theme.ElementHeight - 4
					local CanvasHeight = (Section._FullContentHeight or Section._ContentHeight or 0) - Theme.ElementHeight
					if CanvasHeight <= 0 then CanvasHeight = 1 end
					local HandleHeight = math.max(12, (((Section._ContentHeight or 0) - Theme.ElementHeight) / CanvasHeight) * ScrollbarHeight)
					local ScrollProgress = Section._SectionScrollOffset / Section._SectionMaxScroll
					local HandlePositionY = ScrollbarPositionY + (ScrollbarHeight - HandleHeight) * ScrollProgress

					local ScrollHandleColor = Theme.ScrollbarHandle:Lerp(Theme.ScrollbarHandleHover, Section._ScrollbarHoverFactor or 0)

					if Section._ScrollbarTrack then
						local TrackPos, TrackSize = ClipRectangleToYRange(
							Vector2.new(ScrollbarPositionX, ScrollbarPositionY),
							Vector2.new(Theme.ScrollbarWidth, ScrollbarHeight),
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
							Vector2.new(ScrollbarPositionX, HandlePositionY),
							Vector2.new(Theme.ScrollbarWidth, HandleHeight),
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
					local PositionX = SectionAbsolutePosition.X
					local PositionY = SectionAbsolutePosition.Y
					local Width = SectionFullSize.X
					local Height = SectionFullSize.Y
					local BracketColor = Theme.TitleBarSeparator:Lerp(Theme.SectionTextHover, Section._HoverFactor or 0)

					local From1, To1 = ClipHorizontalLineToYRange(Vector2.new(PositionX, PositionY), Vector2.new(PositionX + 6, PositionY), ViewportStart, ViewportEnd)
					if From1 and To1 then ApplyDrawingProperties(Section._CornerBrackets[1], { From = From1, To = To1, Color = BracketColor, Visible = IsSectionVisible }) else ApplyDrawingProperties(Section._CornerBrackets[1], { Visible = false }) end

					local From2, To2 = ClipVerticalLineToYRange(Vector2.new(PositionX, PositionY), Vector2.new(PositionX, PositionY + 6), ViewportStart, ViewportEnd)
					if From2 and To2 then ApplyDrawingProperties(Section._CornerBrackets[2], { From = From2, To = To2, Color = BracketColor, Visible = IsSectionVisible }) else ApplyDrawingProperties(Section._CornerBrackets[2], { Visible = false }) end

					local From3, To3 = ClipHorizontalLineToYRange(Vector2.new(PositionX + Width - 6, PositionY + Height), Vector2.new(PositionX + Width, PositionY + Height), ViewportStart, ViewportEnd)
					if From3 and To3 then ApplyDrawingProperties(Section._CornerBrackets[3], { From = From3, To = To3, Color = BracketColor, Visible = IsSectionVisible }) else ApplyDrawingProperties(Section._CornerBrackets[3], { Visible = false }) end

					local From4, To4 = ClipVerticalLineToYRange(Vector2.new(PositionX + Width, PositionY + Height - 6), Vector2.new(PositionX + Width, PositionY + Height), ViewportStart, ViewportEnd)
					if From4 and To4 then ApplyDrawingProperties(Section._CornerBrackets[4], { From = From4, To = To4, Color = BracketColor, Visible = IsSectionVisible }) else ApplyDrawingProperties(Section._CornerBrackets[4], { Visible = false }) end
				end

				if Section._TopRightTechLine then
					local PositionX = SectionAbsolutePosition.X
					local PositionY = SectionAbsolutePosition.Y
					local Width = SectionFullSize.X
					local LeftAccentColor = Theme.TitleBarSeparator:Lerp(Theme.SectionTextHover, Section._HoverFactor or 0)
					if PositionY >= ViewportStart and PositionY + 10 <= ViewportEnd then
						ApplyDrawingProperties(Section._TopRightTechLine, {
							From = Vector2.new(PositionX + Width - 10, PositionY),
							To = Vector2.new(PositionX + Width, PositionY + 10),
							Color = LeftAccentColor,
							Visible = IsSectionVisible,
						})
					else
						ApplyDrawingProperties(Section._TopRightTechLine, { Visible = false })
					end
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

			if IsColumnOne then
				ColumnOnePositionY = ColumnOnePositionY + SectionContentHeight + Theme.SectionPadding
			else
				ColumnTwoPositionY = ColumnTwoPositionY + SectionContentHeight + Theme.SectionPadding
			end
		end

		local ContentHeight = math.max(ColumnOnePositionY, ColumnTwoPositionY)
		Window._CanvasHeight = ContentHeight
		Window._MaxScroll = math.max(0, ContentHeight - Window._VisibleHeight)
		Window._ScrollOffset = math.clamp(Window._ScrollOffset, 0, Window._MaxScroll)

		Window._TotalHeight = Theme.TitleBarHeight + Theme.WindowVisibleHeight

		local BodyPosition = Vector2.new(WindowPosition.X, WindowPosition.Y + Theme.TitleBarHeight)

		local BodySize = Vector2.new(Theme.WindowWidth, Window._VisibleHeight)

		if not UseImmediateMode then
			ApplyDrawingProperties(WindowBodyBackgroundDrawing, { Position = BodyPosition, Size = BodySize, Color = Theme.WindowBackground })
			ApplyDrawingProperties(WindowBodyBorderDrawing, { Position = BodyPosition, Size = BodySize, Color = Theme.WindowBorder })

			if Window._TabBarHeight > 0 then
				if Window._TabBarBackgroundDrawing then
					ApplyDrawingProperties(Window._TabBarBackgroundDrawing, {
						Position = WindowPosition + Vector2.new(0, Theme.TitleBarHeight),
						Size = Vector2.new(Theme.WindowWidth, Window._TabBarHeight),
						Color = Theme.TitleBarBackground,
						Visible = Window._Visible,
					})
				end
				if Window._TabBarSeparatorDrawing then
					ApplyDrawingProperties(Window._TabBarSeparatorDrawing, {
						From = WindowPosition + Vector2.new(0, Theme.TitleBarHeight + Window._TabBarHeight),
						To = WindowPosition + Vector2.new(Theme.WindowWidth, Theme.TitleBarHeight + Window._TabBarHeight),
						Visible = Window._Visible,
					})
				end

				local TabCount = #Window._Pages
				local TabWidth = math.max(80, Theme.WindowWidth / math.min(TabCount, 5))
				local MaxTabScroll = math.max(0, (TabCount * TabWidth) - Theme.WindowWidth)
				Window._TabScrollOffset = math.clamp(Window._TabScrollOffset or 0, 0, MaxTabScroll)

				for PageIndex, Page in ipairs(Window._Pages) do
					local TabDrawings = Window._TabDrawings[PageIndex]
					if TabDrawings then
						local TabX = WindowPosition.X + (PageIndex - 1) * TabWidth - Window._TabScrollOffset
						local TabY = WindowPosition.Y + Theme.TitleBarHeight
						
						local TabVisible = Window._Visible
						if TabX < WindowPosition.X - 10 or TabX + TabWidth > WindowPosition.X + Theme.WindowWidth + 10 then
							TabVisible = false
						end

						local TextSize = GetTextBounds(Page.Title, Theme.ElementFontSize)
						local TextX = TabX + (TabWidth - TextSize.X) / 2
						local TextY = TabY + (Window._TabBarHeight - TextSize.Y) / 2

						local IsActive = (PageIndex == Window._ActivePageIndex)
						local HoverFactor = Page._HoverFactor or 0
						
						local BaseColor = IsActive and Theme.TitleBarText or Theme.LabelText
						local TargetColor = IsActive and Theme.TitleBarTextHover or Theme.LabelTextHover
						local TabColor = BaseColor:Lerp(TargetColor, HoverFactor)

						ApplyDrawingProperties(TabDrawings.TextDrawing, {
							Text = Page.Title,
							Position = Vector2.new(TextX, TextY),
							Color = TabColor,
							Visible = TabVisible,
						})

						if TabVisible and (IsActive or HoverFactor > 0.01) then
							local UnderlineY = TabY + Window._TabBarHeight - 2
							local UnderlineWidth = TextSize.X + 10
							local UnderlineX = TabX + (TabWidth - UnderlineWidth) / 2
							local UnderlineAlpha = IsActive and 1 or HoverFactor
							local UnderlineColor = Theme.TitleBarSeparator:Lerp(Theme.TitleBarTextHover, HoverFactor)

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
					local HandleWidth = math.clamp((Theme.WindowWidth / (TabCount * TabWidth)) * Theme.WindowWidth, 30, Theme.WindowWidth)
					local HandleX = WindowPosition.X + (Theme.WindowWidth - HandleWidth) * ScrollProgress
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
					Transparency = 1,
					Thickness = 2,
					Visible = Window._Visible
				})
			end


			ApplyDrawingProperties(TitleBarBackgroundDrawing, { Position = WindowPosition, Color = Theme.TitleBarBackground })
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
				local FullWindowSize = Vector2.new(Theme.WindowWidth, Theme.TitleBarHeight + Window._VisibleHeight)
				local PositionX = WindowPosition.X
				local PositionY = WindowPosition.Y
				local Width = FullWindowSize.X
				local Height = FullWindowSize.Y
				local BracketDrawings = Window._CornerBrackets
				ApplyDrawingProperties(BracketDrawings[1], { From = Vector2.new(PositionX, PositionY), To = Vector2.new(PositionX + 8, PositionY), Visible = Window._Visible })
				ApplyDrawingProperties(BracketDrawings[2], { From = Vector2.new(PositionX, PositionY), To = Vector2.new(PositionX, PositionY + 8), Visible = Window._Visible })
				ApplyDrawingProperties(BracketDrawings[3], { From = Vector2.new(PositionX + Width, PositionY), To = Vector2.new(PositionX + Width - 8, PositionY), Visible = Window._Visible })
				ApplyDrawingProperties(BracketDrawings[4], { From = Vector2.new(PositionX + Width, PositionY), To = Vector2.new(PositionX + Width, PositionY + 8), Visible = Window._Visible })
				ApplyDrawingProperties(BracketDrawings[5], { From = Vector2.new(PositionX, PositionY + Height), To = Vector2.new(PositionX + 8, PositionY + Height), Visible = Window._Visible })
				ApplyDrawingProperties(BracketDrawings[6], { From = Vector2.new(PositionX, PositionY + Height), To = Vector2.new(PositionX, PositionY + Height - 8), Visible = Window._Visible })
				ApplyDrawingProperties(BracketDrawings[7], { From = Vector2.new(PositionX + Width, PositionY + Height), To = Vector2.new(PositionX + Width - 8, PositionY + Height), Visible = Window._Visible })
				ApplyDrawingProperties(BracketDrawings[8], { From = Vector2.new(PositionX + Width, PositionY + Height), To = Vector2.new(PositionX + Width, PositionY + Height - 8), Visible = Window._Visible })
			end

			if Window._SideTicks then
				local LeftPositionX = WindowPosition.X
				local RightPositionX = WindowPosition.X + Theme.WindowWidth
				local TopPositionY = WindowPosition.Y + Theme.TitleBarHeight + 50
				local BottomPositionY = WindowPosition.Y + Theme.TitleBarHeight + 150
				ApplyDrawingProperties(Window._SideTicks[1], { From = Vector2.new(LeftPositionX - 4, TopPositionY), To = Vector2.new(LeftPositionX, TopPositionY), Visible = Window._Visible })
				ApplyDrawingProperties(Window._SideTicks[2], { From = Vector2.new(LeftPositionX - 4, BottomPositionY), To = Vector2.new(LeftPositionX, BottomPositionY), Visible = Window._Visible })
				ApplyDrawingProperties(Window._SideTicks[3], { From = Vector2.new(RightPositionX, TopPositionY), To = Vector2.new(RightPositionX + 4, TopPositionY), Visible = Window._Visible })
				ApplyDrawingProperties(Window._SideTicks[4], { From = Vector2.new(RightPositionX, BottomPositionY), To = Vector2.new(RightPositionX + 4, BottomPositionY), Visible = Window._Visible })
			end
		end

		local CloseButtonSize = 20
		local CloseButtonPosX = WindowPosition.X + Theme.WindowWidth - CloseButtonSize - 8
		local CloseButtonPosY = WindowPosition.Y + (Theme.TitleBarHeight - CloseButtonSize) / 2
		Window._CloseButtonRegion = {
			Position = Vector2.new(CloseButtonPosX, CloseButtonPosY),
			Size = Vector2.new(CloseButtonSize, CloseButtonSize)
		}

		local SearchButtonSize = 20
		local SearchButtonPosX = CloseButtonPosX - SearchButtonSize - 8
		local SearchButtonPosY = CloseButtonPosY
		Window._SearchButtonRegion = {
			Position = Vector2.new(SearchButtonPosX, SearchButtonPosY),
			Size = Vector2.new(SearchButtonSize, SearchButtonSize)
		}

		if not UseImmediateMode then
			if Window._SearchIconCircle and Window._SearchIconLine then
				local CenterPoint = Window._SearchButtonRegion.Position + Vector2.new(9, 9)
				local MouseIsOverSearch = IsPointInsideRectangle(GetMouseLocation(UserInputService), Window._SearchButtonRegion.Position, Window._SearchButtonRegion.Size)
				local SearchIconColor = Window._SearchActive and Theme.TitleBarSeparator or (MouseIsOverSearch and Theme.TitleBarTextHover or Theme.TitleBarText)

				ApplyDrawingProperties(Window._SearchIconCircle, {
					Position = CenterPoint,
					Color = SearchIconColor,
					Visible = Window._Visible,
				})
				ApplyDrawingProperties(Window._SearchIconLine, {
					From = CenterPoint + Vector2.new(3, 3),
					To = CenterPoint + Vector2.new(7, 7),
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
				if #SearchDisplayText > MaxQueryChars then
					if Window._SearchTextBox._IsFocused then
						SearchDisplayText = string.sub(SearchDisplayText, #SearchDisplayText - MaxQueryChars + 1)
					else
						SearchDisplayText = string.sub(SearchDisplayText, 1, MaxQueryChars - 1) .. "..."
					end
				end

				if Window._SearchTextBox._IsFocused and Window._SearchTextBox._CursorVisible then
					SearchDisplayText = SearchDisplayText .. "|"
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
							if #DisplayResultText > MaxChars then
								DisplayResultText = string.sub(DisplayResultText, 1, MaxChars - 3) .. "..."
							end

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
			local CloseColor = Window._CloseButtonHovered and Theme.CloseButtonHover or Color3.fromRGB(160, 40, 52)
			local BorderColor = Window._CloseButtonHovered and Color3.fromRGB(255, 100, 115) or Color3.fromRGB(120, 40, 50)

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

			local VisibilityObjects = { Section._FullBackground, Section._Background, Section._Border, Section._TextLabel, Section._AccentLine, Section._LeftAccentLine, Section._TopRightTechLine }
			if Section._CornerBrackets then
				for DiscardLineIndex, LineObject in ipairs(Section._CornerBrackets) do
					table.insert(VisibilityObjects, LineObject)
				end
			end
			SetDrawingObjectsVisibility(VisibilityObjects, IsSectionVisible)

			for ElementIndex, Element in ipairs(Section._Elements) do
				if Element._Type == "TextLabel" then
					SetDrawingObjectsVisibility({ Element._AccentLineDrawing }, IsSectionVisible)
					for LineIndex, LineObj in ipairs(Element._LineDrawings or {}) do
						SetRenderProperty(LineObj, "Visible", IsSectionVisible)
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
		UpdateElementsVisibility()
	end

	function Window:SetVisible(IsVisible)
		SetEntireWindowVisibility(IsVisible)
	end

	function GetTextBounds(Text, FontSize)
		local Ratio = Theme.FontCharWidthRatio or 0.52
		local CharWidth = FontSize * (Ratio * 1.15)
		return Vector2.new(#Text * CharWidth, FontLineHeight(FontSize))
	end

	function Window:CreatePage(PageConfig)
		PageConfig = PageConfig or {}
		PageConfig.Title = PageConfig.Title or "Page"

		local PageIndex = #Window._Pages + 1
		local Page = {
			Title = PageConfig.Title,
			Sections = {},
			_Index = PageIndex,
			_HoverFactor = 0,
		}

		Window._TabBarHeight = 28

		if #Window._Pages == 0 then
			Window._ActivePageIndex = 1
		end

		table.insert(Window._Pages, Page)

		if #Window._Pages == 1 then
			for _, Sec in ipairs(Window._Sections) do
				if not Sec._PageIndex then
					Sec._PageIndex = 1
					table.insert(Page.Sections, Sec)
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

			local TabText = CreateTextDrawing(Page.Title, Theme.ElementFontSize, Theme.LabelText, 5)
			ApplyDrawingProperties(TabText, { Visible = Window._Visible })

			local TabUnderline = CreateTrackedDrawingObject("Line")
			ApplyDrawingProperties(TabUnderline, {
				Thickness = 2,
				Color = Theme.TitleBarSeparator,
				ZIndex = 5,
				Visible = false,
			})

			Window._TabDrawings[PageIndex] = {
				TextDrawing = TabText,
				UnderlineDrawing = TabUnderline,
			}

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
			Section._FullBackground = CreateRectangleDrawing(Color3.fromRGB(13, 12, 18), true, 4, 1)
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
					Thickness = 2,
					Color = Theme.TitleBarSeparator,
					ZIndex = 8,
					Visible = true,
				})
			end

			Section._TopRightTechLine = CreateTrackedDrawingObject("Line")
			ApplyDrawingProperties(Section._TopRightTechLine, {
				Thickness = 1.5,
				Transparency = 0.7,
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
				for LineIndex, LineObj in ipairs(Element._LineDrawings) do
					DestroyDrawing(LineObj, WindowTrackedDrawings)
				end
				Element._LineDrawings = {}
			end

			function Element:_RebuildLineDrawings(WrappedLines)
				DestroyLineDrawings()
				if UseImmediateMode or not DrawingBackendAvailable then return end
				for LineIndex, LineText in ipairs(WrappedLines) do
					local LineObj = CreateTextDrawing(LineText, Theme.ElementFontSize, Theme.LabelText, 10)
					table.insert(Element._LineDrawings, LineObj)
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
			TextBoxConfig = TextBoxConfig or {}
			TextBoxConfig.Text = TextBoxConfig.Text or "TextBox"
			TextBoxConfig.Default = TextBoxConfig.Default or ""
			TextBoxConfig.Placeholder = TextBoxConfig.Placeholder or "Type here..."
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
				Element._LabelDrawing = CreateTextDrawing(TextBoxConfig.Text .. ": ", Theme.ElementFontSize, Theme.LabelText, 12)
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
				Element._SelectionDrawing = CreateRectangleDrawing(Color3.fromRGB(0, 120, 215), true, 11, 0.5)
				ApplyDrawingProperties(Element._SelectionDrawing, { Visible = false })
			end

			function Element:SetValue(NewValue)
				Element._Value = NewValue
				if Element._TextDrawing then
					local HasValue = NewValue ~= ""
					SetRenderProperty(Element._TextDrawing, "Text", HasValue and NewValue or Element._Placeholder)
					SetRenderProperty(Element._TextDrawing, "Color", HasValue and Theme.TextBoxText or Theme.TextBoxPlaceholder)
				end
				if Element._Callback then
					pcall(Element._Callback, NewValue)
				end
			end

			function Element:GetValue()
				return Element._Value
			end

			table.insert(Section._Elements, Element)
			Window:RecalculateLayout()
			return Element
		end

		function Section:CreateTextButton(ButtonConfig)
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
					Color = ToggleConfig.Default and Color3.fromRGB(80, 220, 120) or Color3.fromRGB(80, 75, 100),
				})
				Element._AccentLineDrawing = CreateTrackedDrawingObject("Line")
				ApplyDrawingProperties(Element._AccentLineDrawing, {
					Thickness = 2,
					Transparency = 0,
					Color = Color3.fromRGB(80, 220, 120),
					ZIndex = 14,
					Visible = ToggleConfig.Default == true,
				})
			end

			function Element:SetValue(NewValue)
				Element._Value = NewValue
				if Element._IndicatorDrawing then
					SetRenderProperty(Element._IndicatorDrawing, "Color",
						NewValue and Color3.fromRGB(80, 220, 120) or Color3.fromRGB(80, 75, 100))
				end
				if Element._AccentLineDrawing then
					SetRenderProperty(Element._AccentLineDrawing, "Visible", NewValue == true)
				end
				if Element._Callback then
					pcall(Element._Callback, NewValue)
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
				Element._TextDrawing = CreateTextDrawing(DropdownConfig.Text .. ": " .. DropdownConfig.Default, Theme.ElementFontSize, Theme.DropdownText, 12)
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
					SetRenderProperty(Element._TextDrawing, "Text", DropdownConfig.Text .. ": " .. NewValue)
				end
				if Element._Callback then
					pcall(Element._Callback, NewValue)
				end
			end

			function Element:GetValue()
				return Element._Value
			end

			table.insert(Section._Elements, Element)
			Window:RecalculateLayout()
			return Element
		end

		function Section:CreateSlider(SliderConfig)
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

				if Element._Callback then
					pcall(Element._Callback, NewValue)
				end
			end

			function Element:GetValue()
				return Element._Value
			end

			function Element:_UpdateValueFromMousePosition(MousePositionX)
				local AbsoluteTrackPositionX = Window._Position.X + Element._TrackPositionX
				local NormalizedFactor = math.clamp(
					(MousePositionX - AbsoluteTrackPositionX) / Element._TrackTotalWidth, 0, 1
				)
				local InterpolatedValue = LerpValue(Element._MinValue, Element._MaxValue, NormalizedFactor)
				Element:SetValue(InterpolatedValue)
			end

			table.insert(Section._Elements, Element)
			Window:RecalculateLayout()
			return Element
		end

		function Section:CreateColorPicker(PickerConfig)
			PickerConfig = PickerConfig or {}
			PickerConfig.Text = PickerConfig.Text or "Color"
			PickerConfig.Default = PickerConfig.Default or Color3.fromRGB(255, 255, 255)
			PickerConfig.Callback = PickerConfig.Callback or function() end

			local AvailableSwatchWidth = Theme.WindowWidth - (Theme.InnerMargin * 2)
			local SwatchColumnsPerRow = math.floor(
				(AvailableSwatchWidth + Theme.ColorSwatchGap) / (Theme.ColorSwatchSize + Theme.ColorSwatchGap)
			)
			local TotalSwatchRows = math.ceil(#ColorPalette / SwatchColumnsPerRow)
			local SwatchGridTotalHeight = TotalSwatchRows * (Theme.ColorSwatchSize + Theme.ColorSwatchGap)

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
				Window._ActiveColorPicker = Element
				Element._TempSelectedSwatchIndex = Element._SelectedSwatchIndex

				if not UseImmediateMode and DrawingBackendAvailable then
					Element:_BuildPopupDrawings()
				end
			end

			function Element:ClosePopup()
				Window._ActiveColorPicker = nil

				if not UseImmediateMode then
					Element:_DestroyPopupDrawings()
				end
			end

			function Element:_BuildPopupDrawings()
				Element:_DestroyPopupDrawings()

				local Camera = Workspace.CurrentCamera
				local ViewportSize = Camera and Camera.ViewportSize or Vector2.new(1920, 1080)
				local Scale = math.clamp(math.min(ViewportSize.X / 1920, ViewportSize.Y / 1080), 1.0, 2.0)

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
				
				local TitleBounds = GetTextBounds("Select color", 12 * Scale)
				ApplyDrawingProperties(Element._PopupTitleDrawing, { Position = Vector2.new(PopupPosition.X + Margin, PopupPosition.Y + (HeaderHeight - TitleBounds.Y) / 2), Visible = true })

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
				Element._PopupSaveText = CreateTextDrawing("Save", 12 * Scale, Theme.ButtonText, 53)
				local SaveBounds = GetTextBounds("Save", 12 * Scale)
				ApplyDrawingProperties(Element._PopupSaveText, { Position = Vector2.new(SavePos.X + (ButtonWidth - SaveBounds.X) / 2, SavePos.Y + (ButtonHeight - SaveBounds.Y) / 2), Visible = true })

				Element._PopupExitBackground  = CreateRectangleDrawing(Theme.ExitButtonBackground, true, 52, 1)
				ApplyDrawingProperties(Element._PopupExitBackground, { Position = ExitPos, Size = ButtonSize, Visible = true })
				Element._PopupExitText = CreateTextDrawing("Exit", 12 * Scale, Theme.ButtonText, 53)
				local ExitBounds = GetTextBounds("Exit", 12 * Scale)
				ApplyDrawingProperties(Element._PopupExitText, { Position = Vector2.new(ExitPos.X + (ButtonWidth - ExitBounds.X) / 2, ExitPos.Y + (ButtonHeight - ExitBounds.Y) / 2), Visible = true })
			end

			function Element:_DestroyPopupDrawings()
				DestroyDrawing(Element._PopupBgDrawing, WindowTrackedDrawings)
				DestroyDrawing(Element._PopupBorderDrawing, WindowTrackedDrawings)
				DestroyDrawing(Element._PopupHeaderDrawing, WindowTrackedDrawings)
				DestroyDrawing(Element._PopupTitleDrawing, WindowTrackedDrawings)
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
				Element._PopupSaveBackground        = nil
				Element._PopupSaveText       = nil
				Element._PopupExitBackground        = nil
				Element._PopupExitText       = nil
				Element._PopupSwatchDrawings = {}
				Element._PopupPos            = nil
			end

			function Element:SelectSwatch(TargetSwatchIndex)

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

				if Element._Callback then
					pcall(Element._Callback, Element._Value)
				end
			end

			function Element:SetValue(NewColor)
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

				if Element._Callback then
					pcall(Element._Callback, Element._Value)
				end
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
		DestroyAllTrackedDrawings()

		for EntryIndex = #Window._ActiveNotifications, 1, -1 do
			local Entry = Window._ActiveNotifications[EntryIndex]
			DestroyDrawing(Entry.Background, NotificationTrackedDrawings)
			DestroyDrawing(Entry.Border, NotificationTrackedDrawings)
			DestroyDrawing(Entry.AccentLine, NotificationTrackedDrawings)
			DestroyDrawing(Entry.TextLabel, NotificationTrackedDrawings)
			table.remove(Window._ActiveNotifications, EntryIndex)
		end

		Library:SetInputBlocking("Scroll", false)
		Library:SetInputBlocking("Camera", false)
		Library:SetInputBlocking("Typing", false)

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

	local WindowHasFocus = true

	table.insert(Window._Connections, WindowFocusReleasedConnect(UserInputService.WindowFocusReleased, NewCClosure(function()
		WindowHasFocus = false
	end)))
	table.insert(Window._Connections, WindowFocusedConnect(UserInputService.WindowFocused, NewCClosure(function()
		WindowHasFocus = true
	end)))

	local HeartbeatConnection = HeartbeatSignalConnect(RunService.Heartbeat, NewCClosure(function(DeltaTime)
		if Window._Destroyed then return end

		local Dt = DeltaTime or 0.0167
		local CurrentMousePosition = GetMouseLocation(UserInputService)

		local AnimationChanged = false
		local function UpdateAnim(CurrentFactor, TargetState, Dt, Speed)
			local NewFactor = UpdateAnimationFactor(CurrentFactor, TargetState, Dt, Speed)
			if NewFactor ~= CurrentFactor then
				AnimationChanged = true
			end
			return NewFactor
		end

		Window._CloseButtonHoverFactor = UpdateAnim(Window._CloseButtonHoverFactor or 0, Window._CloseButtonHovered, Dt, 12)
		Window._TitleTextHoverFactor = UpdateAnim(Window._TitleTextHoverFactor or 0, Window._TitleTextHovered, Dt, 12)

		for PageIndex, Page in ipairs(Window._Pages) do
			local IsTabHovered = false
			if Window._TabBarHeight > 0 then
				local TabCount = #Window._Pages
				local TabWidth = math.max(80, Theme.WindowWidth / math.min(TabCount, 5))
				local TabX = Window._Position.X + (PageIndex - 1) * TabWidth - (Window._TabScrollOffset or 0)
				local TabY = Window._Position.Y + Theme.TitleBarHeight
				IsTabHovered = IsPointInsideRectangle(CurrentMousePosition, Vector2.new(TabX, TabY), Vector2.new(TabWidth, Window._TabBarHeight))
			end
			Page._HoverFactor = UpdateAnim(Page._HoverFactor or 0, IsTabHovered, Dt, 12)
		end

		if Window._SearchActive then
			local SearchBox = Window._SearchTextBox
			SearchBox._HoverFactor = UpdateAnim(SearchBox._HoverFactor or 0, SearchBox._IsHovered, Dt, 12)
			SearchBox._FocusFactor = UpdateAnim(SearchBox._FocusFactor or 0, SearchBox._IsFocused, Dt, 12)
		end

		for SectionIndex, Section in ipairs(Window._Sections) do
			Section._HoverFactor = UpdateAnim(Section._HoverFactor or 0, Section._IsHovered, Dt, 12)
			Section._ScrollbarHoverFactor = UpdateAnim(Section._ScrollbarHoverFactor or 0, Section._ScrollbarHovered or Section._DraggingScrollbar, Dt, 12)

			for ElementIndex, Element in ipairs(Section._Elements) do
				Element._HoverFactor = UpdateAnim(Element._HoverFactor or 0, Element._IsHovered, Dt, 12)
				Element._FocusFactor = UpdateAnim(Element._FocusFactor or 0, Element._IsFocused, Dt, 12)
				Element._ExpandFactor = UpdateAnim(Element._ExpandFactor or 0, Element._Expanded, Dt, 12)
				Element._ActiveFactor = UpdateAnim(Element._ActiveFactor or 0, (Element._Type == "Slider" and Window._ActiveSlider == Element) or (Element._Type == "Toggle" and Element._Value) or false, Dt, 12)
				if Element._Type == "Slider" then
					Element._ThumbHoverFactor = UpdateAnim(Element._ThumbHoverFactor or 0, Element._IsThumbHovered or (Window._ActiveSlider == Element), Dt, 12)
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

		if not WindowHasFocus then return end

		local IsMouseButtonDown = IsMouseButtonPressed(UserInputService, Enum.UserInputType.MouseButton1)

		local MouseButtonJustPressed = IsMouseButtonDown and not PreviousMouseButtonState
		local MouseButtonJustReleased = not IsMouseButtonDown and PreviousMouseButtonState

		local PressedButtons = GetMouseButtonsPressed(UserInputService)
		for ButtonIndex, Btn in ipairs(PressedButtons) do
			if Btn.UserInputType == Enum.UserInputType.MouseButton2 then
				if Window._ActiveDropdown then
					Window._ActiveDropdown:Toggle()
				end
				if Window._ActiveColorPicker then
					Window._ActiveColorPicker:ClosePopup()
				end
				break
			end
		end

		PreviousMouseButtonState = IsMouseButtonDown

		if not Window._Visible then return end

		if Window._ActiveSlider and IsMouseButtonDown then
			Window._ActiveSlider:_UpdateValueFromMousePosition(CurrentMousePosition.X)
		end

		if MouseButtonJustReleased then
			Window._Dragging = false
			Window._ActiveSlider = nil
			Window._DraggingScrollbar = false
			for SectionIndex, ScrollableSection in ipairs(Window._Sections) do
				ScrollableSection._DraggingScrollbar = false
			end
		end

		if Window._Dragging and IsMouseButtonDown and Window._DragOffset then
			Window._Position = CurrentMousePosition - Window._DragOffset
			Window:RecalculateLayout()
		end

		if Window._DraggingScrollbar and IsMouseButtonDown then
			local ScrollbarYPosition = Window._Position.Y + Theme.TitleBarHeight + 2
			local ScrollbarHeight = Window._VisibleHeight - 4
			local HandleHeight = math.max(20, (Window._VisibleHeight / Window._CanvasHeight) * ScrollbarHeight)

			local RelativeY = math.clamp(CurrentMousePosition.Y - ScrollbarYPosition - (HandleHeight / 2), 0, ScrollbarHeight - HandleHeight)
			local ScrollPercent = RelativeY / (ScrollbarHeight - HandleHeight)
			Window._ScrollOffset = ScrollPercent * Window._MaxScroll
			Window:RecalculateLayout()
		end

		for SectionIndex, ScrollableSection in ipairs(Window:GetActiveSections()) do
			if ScrollableSection._DraggingScrollbar and IsMouseButtonDown and ScrollableSection._MaxHeight and ScrollableSection._SectionMaxScroll > 0 then
				local SectionAbsolutePosition = Window._Position + Vector2.new(ScrollableSection._PositionX, ScrollableSection._PositionY - Window._ScrollOffset)
				local ScrollbarPositionY = SectionAbsolutePosition.Y + Theme.ElementHeight + 2
				local ScrollbarHeight = (ScrollableSection._ClippedHeight or ScrollableSection._ContentHeight or 0) - Theme.ElementHeight - 4
				local CanvasHeight = (ScrollableSection._FullContentHeight or ScrollableSection._ContentHeight or 0) - Theme.ElementHeight
				if CanvasHeight <= 0 then CanvasHeight = 1 end
				local HandleHeight = math.max(12, (((ScrollableSection._ClippedHeight or ScrollableSection._ContentHeight or 0) - Theme.ElementHeight) / CanvasHeight) * ScrollbarHeight)

				local RelativeY = math.clamp(CurrentMousePosition.Y - ScrollbarPositionY - (HandleHeight / 2), 0, ScrollbarHeight - HandleHeight)
				local ScrollPercent = RelativeY / (ScrollbarHeight - HandleHeight)
				ScrollableSection._SectionScrollOffset = ScrollPercent * ScrollableSection._SectionMaxScroll
				Window:RecalculateLayout()
			end
		end

		if MouseButtonJustPressed then

			if Window._SearchButtonRegion and IsPointInsideRectangle(CurrentMousePosition, Window._SearchButtonRegion.Position, Window._SearchButtonRegion.Size) then
				Window._SearchActive = not Window._SearchActive
				if Window._SearchActive then
					Window._SearchTextBox._IsFocused = true
					Window._SearchTextBox._Value = ""
					Window._SearchResults = {}
					Library:SetInputBlocking("Typing", true)
				else
					Window._SearchTextBox._IsFocused = false
					Library:SetInputBlocking("Typing", false)
				end
				Window:RecalculateLayout()
				return
			end

			if Window._SearchActive then
				local InsideSearchTextBox = Window._SearchTextBoxRegion and IsPointInsideRectangle(CurrentMousePosition, Window._SearchTextBoxRegion.Position, Window._SearchTextBoxRegion.Size)
				local InsideSearchDropdown = Window._SearchDropdownRegion and #Window._SearchResults > 0 and IsPointInsideRectangle(CurrentMousePosition, Window._SearchDropdownRegion.Position, Window._SearchDropdownRegion.Size)

				if InsideSearchDropdown then
					local RelativeClickY = CurrentMousePosition.Y - (Window._SearchTextBoxRegion.Position.Y + Window._SearchTextBoxRegion.Size.Y)
					local ResultIndex = math.floor(RelativeClickY / 24) + 1
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

						Window._SearchTextBox._Value = ""
						Window._SearchTextBox._IsFocused = false
						Window._SearchActive = false
						Library:SetInputBlocking("Typing", false)

						Window:RecalculateLayout()
						return
					end
				elseif InsideSearchTextBox then
					Window._SearchTextBox._IsFocused = true
					Library:SetInputBlocking("Typing", true)
					Window:RecalculateLayout()
					return
				else
					Window._SearchTextBox._IsFocused = false
					Library:SetInputBlocking("Typing", false)
					Window:RecalculateLayout()
				end
			end

			if Window._CloseButtonRegion and IsPointInsideRectangle(CurrentMousePosition, Window._CloseButtonRegion.Position, Window._CloseButtonRegion.Size) then
				pcall(Window.OnExit)
				Window:Destroy()
				return
			end

			if Window._MaxScroll > 0 then
				local ScrollbarPositionX = Window._Position.X + Theme.WindowWidth - Theme.ScrollbarWidth - 2
				local ScrollbarPositionY = Window._Position.Y + Theme.TitleBarHeight + 2
				local ScrollbarHeight = Window._VisibleHeight - 4
				local ScrollbarTrackRegion = Vector2.new(ScrollbarPositionX, ScrollbarPositionY)
				local ScrollbarTrackSize = Vector2.new(Theme.ScrollbarWidth + 4, ScrollbarHeight)

				if IsPointInsideRectangle(CurrentMousePosition, ScrollbarTrackRegion, ScrollbarTrackSize) then

					local RelativeClickY = math.clamp(CurrentMousePosition.Y - ScrollbarPositionY, 0, ScrollbarHeight)
					Window._ScrollOffset = (RelativeClickY / ScrollbarHeight) * Window._MaxScroll
					Window._DraggingScrollbar = true
					return
				end
			end

			for SectionIndex, ScrollableSection in ipairs(Window:GetActiveSections()) do
				if ScrollableSection._MaxHeight and ScrollableSection._SectionMaxScroll > 0 then
					local SectionAbsolutePosition = Window._Position + Vector2.new(ScrollableSection._PositionX, ScrollableSection._PositionY - Window._ScrollOffset)
					local ScrollbarPositionX = SectionAbsolutePosition.X + ScrollableSection._Width - Theme.ScrollbarWidth - 2
					local ScrollbarPositionY = SectionAbsolutePosition.Y + Theme.ElementHeight + 2
					local ScrollbarHeight = (ScrollableSection._ClippedHeight or ScrollableSection._ContentHeight or 0) - Theme.ElementHeight - 4
					local ScrollbarTrackRegion = Vector2.new(ScrollbarPositionX, ScrollbarPositionY)
					local ScrollbarTrackSize = Vector2.new(Theme.ScrollbarWidth + 4, ScrollbarHeight)

					if IsPointInsideRectangle(CurrentMousePosition, ScrollbarTrackRegion, ScrollbarTrackSize) then
						local RelativeClickY = math.clamp(CurrentMousePosition.Y - ScrollbarPositionY, 0, ScrollbarHeight)
						ScrollableSection._SectionScrollOffset = (RelativeClickY / ScrollbarHeight) * ScrollableSection._SectionMaxScroll
						ScrollableSection._DraggingScrollbar = true
						return
					end
				end
			end

			if Window._TabBarHeight > 0 then
				local TabBarRegionPosition = Window._Position + Vector2.new(0, Theme.TitleBarHeight)
				local TabBarRegionSize = Vector2.new(Theme.WindowWidth, Window._TabBarHeight)
				if IsPointInsideRectangle(CurrentMousePosition, TabBarRegionPosition, TabBarRegionSize) then
					local TabCount = #Window._Pages
					local TabWidth = math.max(80, Theme.WindowWidth / math.min(TabCount, 5))
					local RelativeX = CurrentMousePosition.X - TabBarRegionPosition.X + (Window._TabScrollOffset or 0)
					local PageClickedIndex = math.floor(RelativeX / TabWidth) + 1
					PageClickedIndex = math.clamp(PageClickedIndex, 1, TabCount)
					
					if PageClickedIndex ~= Window._ActivePageIndex then
						Window._ActivePageIndex = PageClickedIndex
						Window._ScrollOffset = 0
						UpdateElementsVisibility()
						Window:RecalculateLayout()
					end
					return
				end
			end

			local TitleBarRegionPosition = Window._Position
			local TitleBarRegionSize = Vector2.new(Theme.WindowWidth, Theme.TitleBarHeight)

			if IsPointInsideRectangle(CurrentMousePosition, TitleBarRegionPosition, TitleBarRegionSize) then
				Window._Dragging = true
				Window._DragOffset = CurrentMousePosition - Window._Position
				return
			end

			if Window._ActiveDropdown then
				local ExpandedDropdown = Window._ActiveDropdown

				for ItemIndex, ItemData in ipairs(ExpandedDropdown._ItemDrawingObjects) do
				local ItemRegionPosition = Vector2.new(Window._Position.X + ItemData._PositionX, Window._Position.Y + ItemData._PositionY - Window._ScrollOffset)
				local ItemRegionSize = Vector2.new(ItemData._Width, Theme.ElementHeight)

				if IsPointInsideRectangle(CurrentMousePosition, ItemRegionPosition, ItemRegionSize) then
					ExpandedDropdown:SetValue(ItemData.Value)
					ExpandedDropdown:Toggle()
					return
				end
				end
			end

			if Window._ActiveColorPicker then
				local ColorPicker = Window._ActiveColorPicker

				local PopupClickPosition, PopupWidth, PopupHeight, Columns, SwatchSize, SwatchGap, Margin, GridStartY, SavePos, ExitPos, ButtonSize
				if UseImmediateMode then
					local PopupGeometry = ColorPicker._PopupGeometry
					if not PopupGeometry then
						ColorPicker:ClosePopup()
						return
					end
					PopupClickPosition         = PopupGeometry.Position
					PopupWidth         = PopupGeometry.Width
					PopupHeight         = PopupGeometry.Height
					Columns    = PopupGeometry.Columns
					SwatchSize = PopupGeometry.SwatchSize
					SwatchGap  = PopupGeometry.SwatchGap
					Margin     = PopupGeometry.Margin
					GridStartY = PopupGeometry.GridStartY
					SavePos    = PopupGeometry.SavePos
					ExitPos    = PopupGeometry.ExitPos
					ButtonSize   = PopupGeometry.ButtonSize
				else
					PopupClickPosition = ColorPicker._PopupPos
					if not PopupClickPosition then

						return
					end
					PopupWidth         = ColorPicker._PopupWidth
					PopupHeight         = ColorPicker._PopupHeight
					Columns    = ColorPicker._PopupColumns
					SwatchSize = ColorPicker._PopupSwatchCellSize
					SwatchGap  = ColorPicker._PopupSwatchCellGap
					Margin     = ColorPicker._PopupMarginSize
					GridStartY = ColorPicker._PopupGridStartY
					SavePos    = ColorPicker._PopupSavePos
					ExitPos    = ColorPicker._PopupExitPos
					ButtonSize   = ColorPicker._PopupButtonSize
				end

				local PopupRegion = Vector2.new(PopupWidth, PopupHeight)
				if not IsPointInsideRectangle(CurrentMousePosition, PopupClickPosition, PopupRegion) then
					ColorPicker:ClosePopup()

				else
					if IsPointInsideRectangle(CurrentMousePosition, SavePos, ButtonSize) then
						ColorPicker:SelectSwatch(ColorPicker._TempSelectedSwatchIndex)
						ColorPicker:ClosePopup()
						return
					end
					if IsPointInsideRectangle(CurrentMousePosition, ExitPos, ButtonSize) then
						ColorPicker:ClosePopup()
						return
					end
					for SwatchIndex = 1, #ColorPalette do
						local ColumnIndex = (SwatchIndex - 1) % Columns
						local RowIndex = math.floor((SwatchIndex - 1) / Columns)
						local SwatchX  = PopupClickPosition.X + Margin + ColumnIndex * (SwatchSize + SwatchGap)
						local SwatchY  = GridStartY + RowIndex * (SwatchSize + SwatchGap)
						if IsPointInsideRectangle(CurrentMousePosition, Vector2.new(SwatchX, SwatchY), Vector2.new(SwatchSize, SwatchSize)) then
							ColorPicker._TempSelectedSwatchIndex = SwatchIndex

							if not UseImmediateMode then
								for SwatchPairIndex, SwatchPair in ipairs(ColorPicker._PopupSwatchDrawings or {}) do
									if SwatchPair.Border then
										local IsSwatchSelected = SwatchPairIndex == SwatchIndex
										ApplyDrawingProperties(SwatchPair.Border, { Color = IsSwatchSelected and Theme.ColorPickerSelectedBorder or Theme.ColorPickerBorder, Thickness = IsSwatchSelected and 2 or 1 })
									end
								end
							end
							return
						end
					end
					return
				end
			end

			for SectionIndex, Section in ipairs(Window:GetActiveSections()) do
				for ElementIndex, Element in ipairs(Section._Elements) do
					local ElementYPosition = Window._Position.Y + Element._PositionY - Window._ScrollOffset
					local ElementRegionPosition = Vector2.new(Window._Position.X + Element._PositionX, ElementYPosition)
					local ElementRegionSize = Vector2.new(Element._Width, Element._Height)

					local IsElementVisible = IsElementVisibleInViewport(ElementYPosition, Element._Height, Section, Window, Window._Position.Y)

					if IsElementVisible and IsPointInsideRectangle(CurrentMousePosition, ElementRegionPosition, ElementRegionSize) then
						if Element._Type == "TextButton" then
							if Element._Callback then
								pcall(Element._Callback)
							end
							return

						elseif Element._Type == "TextLabel" then
							if Element._Callback then
								pcall(Element._Callback)
							end
							return

						elseif Element._Type == "Toggle" then
							Element:Toggle()
							return

						elseif Element._Type == "Dropdown" then
							Element:Toggle()
							return

						elseif Element._Type == "Slider" then
							Window._ActiveSlider = Element
							Element:_UpdateValueFromMousePosition(CurrentMousePosition.X)
							return

						elseif Element._Type == "TextBox" then
							Element._IsFocused = true

							Element._CursorVisible = true
							Element._CursorBlinkTime = tick()
							Library:SetInputBlocking("Typing", true)
							return

						elseif Element._Type == "ColorPicker" then
							local SwatchRegionPosition = Vector2.new(Window._Position.X + Element._SwatchPositionX, ElementYPosition + (Element._Height - Element._SwatchSize) / 2)
							local SwatchRegionSize = Vector2.new(Element._SwatchSize, Element._SwatchSize)
							if IsPointInsideRectangle(CurrentMousePosition, SwatchRegionPosition, SwatchRegionSize) then
								if Window._ActiveColorPicker == Element then
									Element:ClosePopup()
								else
									if Window._ActiveColorPicker then Window._ActiveColorPicker:ClosePopup() end
									Element:OpenPopup()
								end
								return
							end
						end
					else
						if Element._Type == "TextBox" then
							Element._IsFocused = false
							Element._CursorVisible = false
							Library:SetInputBlocking("Typing", false)
						end
					end
				end
			end

		end

		for SectionIndex, Section in ipairs(Window._Sections) do
			local IsActivePage = (not Section._PageIndex) or (Section._PageIndex == Window._ActivePageIndex)
			if not IsActivePage then
				Section._IsHovered = false
				Section._ScrollbarHovered = false
				for _, Element in ipairs(Section._Elements) do
					Element._IsHovered = false
					if Element._Type == "Slider" then
						Element._IsThumbHovered = false
					elseif Element._Type == "ColorPicker" then
						Element._IsSwatchHovered = false
					end
				end
			end
		end

		for SectionIndex, Section in ipairs(Window:GetActiveSections()) do
			for ElementIndex, Element in ipairs(Section._Elements) do
				local ElementYPosition = Window._Position.Y + Element._PositionY - Window._ScrollOffset
				local ElementRegionPosition = Vector2.new(Window._Position.X + Element._PositionX, ElementYPosition)
				local ElementWidth = Element._Width - (Window._MaxScroll > 0 and Theme.ScrollbarWidth + 4 or 0)
				local ElementRegionSize = Vector2.new(ElementWidth, Element._Height)

				local IsElementVisible = IsElementVisibleInViewport(ElementYPosition, Element._Height, Section, Window, Window._Position.Y)

				local IsCurrentlyHovered = IsElementVisible and IsPointInsideRectangle(CurrentMousePosition, ElementRegionPosition, ElementRegionSize)

				if Element._Type == "TextButton" then
					Element._IsHovered = IsCurrentlyHovered

				elseif Element._Type == "Toggle" then
					Element._IsHovered = IsCurrentlyHovered

				elseif Element._Type == "Dropdown" then
					Element._IsHovered = IsCurrentlyHovered

				elseif Element._Type == "TextLabel" then
					Element._IsHovered = IsCurrentlyHovered

				elseif Element._Type == "Slider" then
					local TrackAbsolutePositionX = Window._Position.X + (Element._TrackPositionX or Element._PositionX)
					local TrackAbsolutePositionY = ElementYPosition + Theme.ElementFontSize + 5
					local TrackPos = Vector2.new(TrackAbsolutePositionX, TrackAbsolutePositionY)
					local TrackSize = Vector2.new(Element._TrackTotalWidth, 16)
					local IsTrackHovered = IsPointInsideRectangle(CurrentMousePosition, TrackPos, TrackSize)
					Element._IsHovered = not IsElementClipped and IsTrackHovered

					local Value = Element._Value or 0
					local Range = (Element._MaxValue or 100) - (Element._MinValue or 0)
					if Range == 0 then Range = 1 end
					local NormalizedValue = (Value - (Element._MinValue or 0)) / Range
					local ThumbX = TrackAbsolutePositionX + math.floor((Element._TrackTotalWidth or Element._Width) * NormalizedValue)
					local ThumbY = TrackAbsolutePositionY + 4
					local ThumbHitSize = 14
					local IsThumbHovered = math.abs(CurrentMousePosition.X - ThumbX) < ThumbHitSize and math.abs(CurrentMousePosition.Y - ThumbY) < ThumbHitSize
					Element._IsThumbHovered = not IsElementClipped and IsThumbHovered

				elseif Element._Type == "TextBox" then
					Element._IsHovered = IsCurrentlyHovered

				elseif Element._Type == "ColorPicker" then
					local SwatchAbsolutePosition = Window._Position + Vector2.new(Element._SwatchPositionX, Element._SwatchPositionY - Window._ScrollOffset)
					local SwatchSizeVector = Vector2.new(Element._SwatchSize, Element._SwatchSize)
					local IsSwatchHovered = IsPointInsideRectangle(CurrentMousePosition, SwatchAbsolutePosition, SwatchSizeVector)
					Element._IsHovered = not IsElementClipped and IsSwatchHovered
				end
			end
		end

		if Window._MaxScroll > 0 then
			local ScrollbarPosX = Window._Position.X + Theme.WindowWidth - Theme.ScrollbarWidth - 2
			local ScrollbarPosY = Window._Position.Y + Theme.TitleBarHeight + 2
			local ScrollbarSz = Vector2.new(Theme.ScrollbarWidth + 4, Window._VisibleHeight - 4)
			Window._ScrollbarHovered = IsPointInsideRectangle(CurrentMousePosition, Vector2.new(ScrollbarPosX - 2, ScrollbarPosY), ScrollbarSz)
		end

		for SectionIndex, ScrollableSection in ipairs(Window:GetActiveSections()) do
			if ScrollableSection._MaxHeight and ScrollableSection._SectionMaxScroll > 0 then
				local SectionAbsolutePosition = Window._Position + Vector2.new(ScrollableSection._PositionX, ScrollableSection._PositionY - Window._ScrollOffset)
				local ScrollbarPosX = SectionAbsolutePosition.X + ScrollableSection._Width - Theme.ScrollbarWidth - 2
				local ScrollbarPosY = SectionAbsolutePosition.Y + Theme.ElementHeight + 2
				local ScrollbarSz = Vector2.new(Theme.ScrollbarWidth + 4, (ScrollableSection._ClippedHeight or ScrollableSection._ContentHeight or 0) - Theme.ElementHeight - 4)
				ScrollableSection._ScrollbarHovered = IsPointInsideRectangle(CurrentMousePosition, Vector2.new(ScrollbarPosX - 2, ScrollbarPosY), ScrollbarSz)
			else
				ScrollableSection._ScrollbarHovered = false
			end
		end

		local SinkBodyPosition = Vector2.new(Window._Position.X, Window._Position.Y + Theme.TitleBarHeight)
		local SinkBodySize     = Vector2.new(Theme.WindowWidth, Window._VisibleHeight)
		local SinkTitlePos     = Vector2.new(Window._Position.X, Window._Position.Y)
		local SinkTitleSize    = Vector2.new(Theme.WindowWidth, Theme.TitleBarHeight)
		local MouseInWindow    = IsPointInsideRectangle(CurrentMousePosition, SinkBodyPosition, SinkBodySize)
			or IsPointInsideRectangle(CurrentMousePosition, SinkTitlePos, SinkTitleSize)
		if MouseInWindow ~= Window._ScrollSinkActive then
			Window._ScrollSinkActive = MouseInWindow
			Library:SetInputBlocking("Scroll", MouseInWindow)
		end
		if MouseInWindow ~= Window._CameraSinkActive then
			Window._CameraSinkActive = MouseInWindow
			Library:SetInputBlocking("Camera", MouseInWindow)
		end

		local TitleHitboxPos = Vector2.new(Window._Position.X + Theme.InnerMargin, Window._Position.Y)
		local TitleHitboxSize = Vector2.new(math.min(180, Theme.WindowWidth / 2), Theme.TitleBarHeight)
		local TitleTextHovered = IsPointInsideRectangle(CurrentMousePosition, TitleHitboxPos, TitleHitboxSize)
		if TitleTextHovered ~= Window._TitleTextHovered then
			Window._TitleTextHovered = TitleTextHovered
			if TitleBarTextDrawing then
				SetRenderProperty(TitleBarTextDrawing, "Color", TitleTextHovered and Theme.TitleBarTextHover or Theme.TitleBarText)
			end
		end

		if Window._CloseButtonRegion then
			local IsHovered = IsPointInsideRectangle(CurrentMousePosition, Window._CloseButtonRegion.Position, Window._CloseButtonRegion.Size)
			if IsHovered ~= Window._CloseButtonHovered then
				Window._CloseButtonHovered = IsHovered
				if CloseButtonBackgroundDrawing and CloseButtonBorderDrawing then
					local CloseColor = IsHovered and Theme.CloseButtonHover or Color3.fromRGB(160, 40, 52)
					local BorderColor = IsHovered and Color3.fromRGB(255, 100, 115) or Color3.fromRGB(120, 40, 50)
					SetRenderProperty(CloseButtonBackgroundDrawing, "Color", CloseColor)
					SetRenderProperty(CloseButtonBorderDrawing, "Color", BorderColor)
				end
			end
		end

		if SaveButtonBackgroundDrawing then
			local IsSaveHovered = IsPointInsideRectangle(CurrentMousePosition, GetRenderProperty(SaveButtonBackgroundDrawing, "Position"), GetRenderProperty(SaveButtonBackgroundDrawing, "Size"))
			SetRenderProperty(SaveButtonBackgroundDrawing, "Color", IsSaveHovered and Theme.SaveButtonHover or Theme.SaveButtonBackground)
		end

		if ExitButtonBackgroundDrawing then
			local IsExitHovered = IsPointInsideRectangle(CurrentMousePosition, GetRenderProperty(ExitButtonBackgroundDrawing, "Position"), GetRenderProperty(ExitButtonBackgroundDrawing, "Size"))
			SetRenderProperty(ExitButtonBackgroundDrawing, "Color", IsExitHovered and Theme.ExitButtonHover or Theme.ExitButtonBackground)
		end

		if Window._ActiveDropdown then
			for ItemIndex, ItemData in ipairs(Window._ActiveDropdown._ItemDrawingObjects) do
				local ItemRegionPosition = Vector2.new(Window._Position.X + ItemData._PositionX, Window._Position.Y + ItemData._PositionY - Window._ScrollOffset)
				local ItemRegionSize = Vector2.new(ItemData._Width, Theme.ElementHeight)
				local IsItemHovered = IsPointInsideRectangle(CurrentMousePosition, ItemRegionPosition, ItemRegionSize)

				if ItemData.BackgroundDrawing then
					ApplyDrawingProperties(ItemData.BackgroundDrawing, {
						Color = IsItemHovered and Theme.DropdownItemHover or Theme.DropdownItemBackground,
					})
				end
			end
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

		local Camera = Workspace.CurrentCamera
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
			local ViewportStart = WindowPosition.Y + Theme.TitleBarHeight + Window._TabBarHeight
			local ViewportEnd = ViewportStart + Window._VisibleHeight
			local WindowWidth = Theme.WindowWidth

			local ContentHeight = Window._VisibleHeight

			local BodyPosition = Vector2.new(WindowPosition.X, WindowPosition.Y + Theme.TitleBarHeight)
			local BodySize = Vector2.new(WindowWidth, ContentHeight)

			local FullWindowSize = Vector2.new(WindowWidth, Theme.TitleBarHeight + ContentHeight)
			for GlowIndex = 1, 3 do
				DrawingImmediateRectangle(WindowPosition - Vector2.new(GlowIndex, GlowIndex), FullWindowSize + Vector2.new(GlowIndex * 2, GlowIndex * 2), Theme.TitleBarSeparator, 0.12 / GlowIndex, 0, 1)
			end

			DrawingImmediateFilledRectangle(BodyPosition, BodySize, Theme.WindowBackground, 1, 0)
			DrawingImmediateRectangle(BodyPosition, BodySize, Theme.WindowBorder, 0.8, 0, 1)

			DrawingImmediateLine(
				WindowPosition,
				Vector2.new(WindowPosition.X + WindowWidth, WindowPosition.Y),
				Theme.TitleBarSeparator,
				1,
				2
			)

			local PositionX = WindowPosition.X
			local PositionY = WindowPosition.Y
			local Width = FullWindowSize.X
			local Height = FullWindowSize.Y
			local BracketColor = Theme.TitleBarSeparator
			DrawingImmediateLine(Vector2.new(PositionX, PositionY), Vector2.new(PositionX + 8, PositionY), BracketColor, 1, 2)
			DrawingImmediateLine(Vector2.new(PositionX, PositionY), Vector2.new(PositionX, PositionY + 8), BracketColor, 1, 2)
			DrawingImmediateLine(Vector2.new(PositionX + Width, PositionY), Vector2.new(PositionX + Width - 8, PositionY), BracketColor, 1, 2)
			DrawingImmediateLine(Vector2.new(PositionX + Width, PositionY), Vector2.new(PositionX + Width, PositionY + 8), BracketColor, 1, 2)
			DrawingImmediateLine(Vector2.new(PositionX, PositionY + Height), Vector2.new(PositionX + 8, PositionY + Height), BracketColor, 1, 2)
			DrawingImmediateLine(Vector2.new(PositionX, PositionY + Height), Vector2.new(PositionX, PositionY + Height - 8), BracketColor, 1, 2)
			DrawingImmediateLine(Vector2.new(PositionX + Width, PositionY + Height), Vector2.new(PositionX + Width - 8, PositionY + Height), BracketColor, 1, 2)
			DrawingImmediateLine(Vector2.new(PositionX + Width, PositionY + Height), Vector2.new(PositionX + Width, PositionY + Height - 8), BracketColor, 1, 2)
			local LeftPositionX = WindowPosition.X
			local RightPositionX = WindowPosition.X + WindowWidth
			local TopPositionY = WindowPosition.Y + Theme.TitleBarHeight + 50
			local BottomPositionY = WindowPosition.Y + Theme.TitleBarHeight + 150
			local TickColor = Theme.TitleBarSeparator
			DrawingImmediateLine(Vector2.new(LeftPositionX - 4, TopPositionY), Vector2.new(LeftPositionX, TopPositionY), TickColor, 1, 1.5)
			DrawingImmediateLine(Vector2.new(LeftPositionX - 4, BottomPositionY), Vector2.new(LeftPositionX, BottomPositionY), TickColor, 1, 1.5)
			DrawingImmediateLine(Vector2.new(RightPositionX, TopPositionY), Vector2.new(RightPositionX + 4, TopPositionY), TickColor, 1, 1.5)
			DrawingImmediateLine(Vector2.new(RightPositionX, BottomPositionY), Vector2.new(RightPositionX + 4, BottomPositionY), TickColor, 1, 1.5)

			local CurrentMousePosition = GetMouseLocation(UserInputService)
			local MouseInsideBody = IsPointInsideRectangle(CurrentMousePosition, BodyPosition, BodySize)

			local TitleBarCheckPos = Vector2.new(WindowPosition.X, WindowPosition.Y)
			local TitleBarCheckSize = Vector2.new(WindowWidth, Theme.TitleBarHeight)
			local MouseInsideWindow = MouseInsideBody or IsPointInsideRectangle(CurrentMousePosition, TitleBarCheckPos, TitleBarCheckSize)
			if MouseInsideWindow ~= Window._ScrollSinkActive then
				Window._ScrollSinkActive = MouseInsideWindow
				Library:SetInputBlocking("Scroll", MouseInsideWindow)
			end

			if MouseInsideWindow ~= Window._CameraSinkActive then
				Window._CameraSinkActive = MouseInsideWindow
				Library:SetInputBlocking("Camera", MouseInsideWindow)
			end

			local TitleBarSize = Vector2.new(WindowWidth, Theme.TitleBarHeight)
			DrawingImmediateFilledRectangle(WindowPosition, TitleBarSize, Theme.TitleBarBackground, 1, 0)
			Window._TitleBarHovered = IsPointInsideRectangle(CurrentMousePosition, WindowPosition, TitleBarSize)

			local SeparatorStart = Vector2.new(WindowPosition.X, WindowPosition.Y + Theme.TitleBarHeight)
			local SeparatorEnd = Vector2.new(WindowPosition.X + WindowWidth, WindowPosition.Y + Theme.TitleBarHeight)
			DrawingImmediateLine(SeparatorStart, SeparatorEnd, Theme.TitleBarSeparator, 0.85, 2)

			if Window._TabBarHeight > 0 then
				local TabBarPos = WindowPosition + Vector2.new(0, Theme.TitleBarHeight)
				local TabBarSize = Vector2.new(WindowWidth, Window._TabBarHeight)
				DrawingImmediateFilledRectangle(TabBarPos, TabBarSize, Theme.TitleBarBackground, 1, 0)
				DrawingImmediateLine(
					TabBarPos + Vector2.new(0, Window._TabBarHeight),
					TabBarPos + Vector2.new(WindowWidth, Window._TabBarHeight),
					Theme.TitleBarSeparator,
					0.85,
					2
				)

				local TabCount = #Window._Pages
				local TabWidth = math.max(80, WindowWidth / math.min(TabCount, 5))
				local MaxTabScroll = math.max(0, (TabCount * TabWidth) - WindowWidth)
				Window._TabScrollOffset = math.clamp(Window._TabScrollOffset or 0, 0, MaxTabScroll)
				for PageIndex, Page in ipairs(Window._Pages) do
					local TabX = WindowPosition.X + (PageIndex - 1) * TabWidth - Window._TabScrollOffset
					local TabY = WindowPosition.Y + Theme.TitleBarHeight
					
					if TabX >= WindowPosition.X - 10 and TabX + TabWidth <= WindowPosition.X + WindowWidth + 10 then
						local TextSize = GetTextBounds(Page.Title, Theme.ElementFontSize)
						local TextX = TabX + (TabWidth - TextSize.X) / 2
						local TextY = TabY + (Window._TabBarHeight - TextSize.Y) / 2

						local IsActive = (PageIndex == Window._ActivePageIndex)
						local HoverFactor = Page._HoverFactor or 0
						
						local BaseColor = IsActive and Theme.TitleBarText or Theme.LabelText
						local TargetColor = IsActive and Theme.TitleBarTextHover or Theme.LabelTextHover
						local TabColor = BaseColor:Lerp(TargetColor, HoverFactor)

						DrawingImmediateText(
							Vector2.new(TextX, TextY),
							Theme.Font, Theme.ElementFontSize, TabColor, 1, Page.Title, false
						)

						if IsActive or HoverFactor > 0.01 then
							local UnderlineY = TabY + Window._TabBarHeight - 2
							local UnderlineWidth = TextSize.X + 10
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
					local HandleWidth = math.clamp((WindowWidth / (TabCount * TabWidth)) * WindowWidth, 30, WindowWidth)
					local HandleX = WindowPosition.X + (WindowWidth - HandleWidth) * ScrollProgress
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
				local CloseColor = Color3.fromRGB(160, 40, 52):Lerp(Theme.CloseButtonHover, Window._CloseButtonHoverFactor or 0)
				DrawingImmediateFilledRectangle(CloseRegion.Position, CloseRegion.Size, CloseColor, 0.9, 0)

				DrawingImmediateRectangle(CloseRegion.Position, CloseRegion.Size,
					Color3.fromRGB(120, 40, 50):Lerp(Color3.fromRGB(255, 100, 115), Window._CloseButtonHoverFactor or 0),
					0.9, 0, 1)

				DrawingImmediateText(
					Vector2.new(CloseRegion.Position.X + 5, CloseRegion.Position.Y + 3),
					Theme.Font, 13, Color3.fromRGB(255, 220, 225), 1, "X", false
				)
			end

			if Window._SearchButtonRegion then
				local MouseIsOverSearch = IsPointInsideRectangle(CurrentMousePosition, Window._SearchButtonRegion.Position, Window._SearchButtonRegion.Size)
				local SearchIconColor = Window._SearchActive and Theme.TitleBarSeparator or (MouseIsOverSearch and Theme.TitleBarTextHover or Theme.TitleBarText)
				local SearchIconCenter = Window._SearchButtonRegion.Position + Vector2.new(9, 9)

				DrawingImmediateCircle(SearchIconCenter, 4, SearchIconColor, 1, 12, 1)
				DrawingImmediateLine(SearchIconCenter + Vector2.new(3, 3), SearchIconCenter + Vector2.new(7, 7), SearchIconColor, 1, 1.5)
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
						DrawingImmediateFilledRectangle(ClippedBgPos, ClippedBgSize, Color3.fromRGB(13, 12, 18), 1, 0)
						local SectionBorderColor = Theme.WindowBorder:Lerp(Theme.WindowBorderHover, Section._HoverFactor or 0)
						DrawingImmediateRectangle(ClippedBgPos, ClippedBgSize, SectionBorderColor, 0.6, 0, 1)
					end

					local LeftAccentColor = Theme.TitleBarSeparator:Lerp(Theme.SectionTextHover, Section._HoverFactor or 0)
					local LeftAccentFrom, LeftAccentTo = ClipVerticalLineToYRange(SectionHeaderPosition, Vector2.new(SectionHeaderPosition.X, SectionHeaderPosition.Y + SectionFullHeight), ViewportStart, ViewportEnd)
					if LeftAccentFrom and LeftAccentTo then
						DrawingImmediateLine(LeftAccentFrom, LeftAccentTo, LeftAccentColor, 0.8, 2)
					end

					local SectionPositionX = SectionHeaderPosition.X
					local SectionPositionY = SectionHeaderPosition.Y
					local SectionWidth = SectionFullSize.X
					local SectionHeight = SectionFullSize.Y

					local From1, To1 = ClipHorizontalLineToYRange(Vector2.new(SectionPositionX, SectionPositionY), Vector2.new(SectionPositionX + 6, SectionPositionY), ViewportStart, ViewportEnd)
					if From1 and To1 then DrawingImmediateLine(From1, To1, LeftAccentColor, 1, 2) end

					local From2, To2 = ClipVerticalLineToYRange(Vector2.new(SectionPositionX, SectionPositionY), Vector2.new(SectionPositionX, SectionPositionY + 6), ViewportStart, ViewportEnd)
					if From2 and To2 then DrawingImmediateLine(From2, To2, LeftAccentColor, 1, 2) end

					local From3, To3 = ClipHorizontalLineToYRange(Vector2.new(SectionPositionX + SectionWidth - 6, SectionPositionY + SectionHeight), Vector2.new(SectionPositionX + SectionWidth, SectionPositionY + SectionHeight), ViewportStart, ViewportEnd)
					if From3 and To3 then DrawingImmediateLine(From3, To3, LeftAccentColor, 1, 2) end

					local From4, To4 = ClipVerticalLineToYRange(Vector2.new(SectionPositionX + SectionWidth, SectionPositionY + SectionHeight - 6), Vector2.new(SectionPositionX + SectionWidth, SectionPositionY + SectionHeight), ViewportStart, ViewportEnd)
					if From4 and To4 then DrawingImmediateLine(From4, To4, LeftAccentColor, 1, 2) end

					if SectionPositionY >= ViewportStart and SectionPositionY + 10 <= ViewportEnd then
						DrawingImmediateLine(
							Vector2.new(SectionPositionX + SectionWidth - 10, SectionPositionY),
							Vector2.new(SectionPositionX + SectionWidth, SectionPositionY + 10),
							LeftAccentColor, 0.7, 1.5
						)
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

					if Section._MaxHeight and Section._SectionMaxScroll > 0 then
						local ScrollbarPositionX = SectionHeaderPosition.X + Section._Width - Theme.ScrollbarWidth - 2
						local ScrollbarPositionY = SectionHeaderPosition.Y + Theme.ElementHeight + 2
						local ScrollbarHeight = SectionFullHeight - Theme.ElementHeight - 4
						local SectionCanvasHeight = (Section._FullContentHeight or Section._ContentHeight or 0) - Theme.ElementHeight
						if SectionCanvasHeight <= 0 then SectionCanvasHeight = 1 end
						local HandleHeight = math.max(12, (((SectionFullHeight or Section._ContentHeight or 0) - Theme.ElementHeight) / SectionCanvasHeight) * ScrollbarHeight)
						local ScrollProgress = Section._SectionScrollOffset / Section._SectionMaxScroll
						local HandlePositionY = ScrollbarPositionY + (ScrollbarHeight - HandleHeight) * ScrollProgress

						local ScrollHandleColor = Theme.ScrollbarHandle:Lerp(Theme.ScrollbarHandleHover, Section._ScrollbarHoverFactor or 0)

						local TrackPos, TrackSize = ClipRectangleToYRange(
							Vector2.new(ScrollbarPositionX, ScrollbarPositionY),
							Vector2.new(Theme.ScrollbarWidth, ScrollbarHeight),
							ViewportStart, ViewportEnd
						)
						if TrackPos and TrackSize then
							DrawingImmediateFilledRectangle(TrackPos, TrackSize, Theme.ScrollbarBackground, 1, 0)
						end

						local HandlePos, HandleSize = ClipRectangleToYRange(
							Vector2.new(ScrollbarPositionX, HandlePositionY),
							Vector2.new(Theme.ScrollbarWidth, HandleHeight),
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
									DrawingImmediateLine(AccentFrom, AccentTo, Color3.fromRGB(80, 220, 120), Element._ActiveFactor or 0, 2)
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
							local PipColor = Color3.fromRGB(80, 75, 100):Lerp(Color3.fromRGB(80, 220, 120), Element._ActiveFactor or 0)
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
										Theme.Font, Theme.ElementFontSize, Theme.LabelText, 1, Element._Text .. ": ", false
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
							local ClippedText = DisplayText
							if #DisplayText > MaxChars then
								if Element._IsFocused then
									ClippedText = DisplayText:sub(#DisplayText - MaxChars + 1)
								else
									ClippedText = DisplayText:sub(1, MaxChars - 1) .. "\xe2\x80\xa6"
								end
							end

							if Element._IsSelected and HasValue then
								local SelectionWidth = math.min(#ClippedText * CharacterWidth, AvailableInputWidth)
								local SelPos = Vector2.new(InputStartX - 2, ElementYPosition + (Element._Height - Theme.ElementFontSize) / 2 - 2)
								local SelSize = Vector2.new(SelectionWidth + 4, Theme.ElementFontSize + 4)
								local ClippedSelPos, ClippedSelSize = ClipRectangleToYRange(SelPos, SelSize, AllowedMinY, AllowedMaxY)
								if ClippedSelPos and ClippedSelSize then
									DrawingImmediateFilledRectangle(ClippedSelPos, ClippedSelSize, Color3.fromRGB(0, 120, 215), 0.5, 0)
								end
							end

							if TextY >= AllowedMinY and TextY + Theme.ElementFontSize <= AllowedMaxY then
								DrawingImmediateText(
									Vector2.new(InputStartX, TextY),
									Theme.Font, Theme.ElementFontSize, DisplayColor, 1, ClippedText .. CursorSuffix, false
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
									Theme.Font, Theme.ElementFontSize, Theme.DropdownText, 1, Element._Text .. ": " .. Element._Value, false
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
								local ValueColor = Theme.SectionText:Lerp(Color3.fromRGB(220, 200, 255), Element._ActiveFactor or 0)
								DrawingImmediateText(
									Vector2.new(WindowPosition.X + Element._PositionX + Element._TrackTotalWidth - 48, TextY),
									Theme.Font, Theme.ElementFontSize, ValueColor, 1, tostring(Value), false
								)
							end

							local TrackPosition = Vector2.new(WindowPosition.X + (Element._TrackPositionX or Element._PositionX), ElementYPosition + Theme.ElementFontSize + 5)
							local TrackHeight = LerpValue(8, 10, Element._HoverFactor or 0)
							local TrackSize = Vector2.new(Element._TrackTotalWidth, TrackHeight)
							local NormalizedValue = (Value - Minimum) / Range
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

			if Window._MaxScroll > 0 then
				local ScrollbarPositionX = WindowPosition.X + Theme.WindowWidth - Theme.ScrollbarWidth - 2
				local ScrollbarPositionY = WindowPosition.Y + Theme.TitleBarHeight + 2
				local ScrollbarHeight = Window._VisibleHeight - 4
				local HandleHeight = math.max(20, (Window._VisibleHeight / Window._CanvasHeight) * ScrollbarHeight)
				local ScrollProgress = Window._ScrollOffset / Window._MaxScroll
				local HandlePositionY = ScrollbarPositionY + (ScrollbarHeight - HandleHeight) * ScrollProgress

				local IsScrollActive = Window._ScrollbarHovered or Window._DraggingScrollbar
				local ScrollHandleColor = IsScrollActive and Theme.ScrollbarHandleHover or Theme.ScrollbarHandle

				DrawingImmediateFilledRectangle(
					Vector2.new(ScrollbarPositionX, ScrollbarPositionY),
					Vector2.new(Theme.ScrollbarWidth, ScrollbarHeight),
					Theme.ScrollbarBackground, 1, 0
				)

				DrawingImmediateFilledRectangle(
					Vector2.new(ScrollbarPositionX, HandlePositionY),
					Vector2.new(Theme.ScrollbarWidth, HandleHeight),
					ScrollHandleColor, 1, 0
				)

				if IsScrollActive then
					DrawingImmediateLine(
						Vector2.new(ScrollbarPositionX + math.floor(Theme.ScrollbarWidth / 2), HandlePositionY + 3),
						Vector2.new(ScrollbarPositionX + math.floor(Theme.ScrollbarWidth / 2), HandlePositionY + HandleHeight - 3),
						Theme.TitleBarSeparator, 0.7, 1
					)
				end
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
				if #SearchDisplayText > MaxQueryChars then
					if Window._SearchTextBox._IsFocused then
						SearchDisplayText = string.sub(SearchDisplayText, #SearchDisplayText - MaxQueryChars + 1)
					else
						SearchDisplayText = string.sub(SearchDisplayText, 1, MaxQueryChars - 1) .. "..."
					end
				end

				if Window._SearchTextBox._IsFocused and Window._SearchTextBox._CursorVisible then
					SearchDisplayText = SearchDisplayText .. "|"
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
						if #DisplayResultText > MaxChars then
							DisplayResultText = string.sub(DisplayResultText, 1, MaxChars - 3) .. "..."
						end

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

				local Camera = Workspace.CurrentCamera
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
				DrawingImmediateText(Vector2.new(PopupPosition.X + Margin, PopupPosition.Y + (HeaderHeight - 12) / 2), Theme.Font, 12, Theme.TitleBarText, 1, "Select color", false)

				local GridStartY = PopupPosition.Y + HeaderHeight + Margin
				for SwatchIndex = 1, #ColorPalette do
					local ColumnIndex = (SwatchIndex - 1) % Columns
					local RowIndex    = math.floor((SwatchIndex - 1) / Columns)
					local SwatchX = PopupPosition.X + Margin + ColumnIndex * (SwatchSize + SwatchGap)
					local SwatchY = GridStartY + RowIndex * (SwatchSize + SwatchGap)
					local SwatchPos  = Vector2.new(SwatchX, SwatchY)
					local SwatchSizeVector  = Vector2.new(SwatchSize, SwatchSize)
					local IsSelected = (SwatchIndex == ColorPicker._TempSelectedSwatchIndex)
					DrawingImmediateFilledRectangle(SwatchPos, SwatchSizeVector, ColorPalette[SwatchIndex], 1, 0)
					DrawingImmediateRectangle(SwatchPos, SwatchSizeVector, IsSelected and Theme.ColorPickerSelectedBorder or Theme.ColorPickerBorder, 1, 0, IsSelected and 2 or 1)
				end

				local SaveButtonY    = GridStartY + GridHeight + 10
				local SaveButtonSize = Vector2.new((PopupWidth - Margin * 3) / 2, 24)
				local SaveButtonPos  = Vector2.new(PopupPosition.X + Margin, SaveButtonY)
				local ExitButtonPos  = Vector2.new(SaveButtonPos.X + SaveButtonSize.X + Margin, SaveButtonY)
				local CurrentMousePosition = GetMouseLocation(UserInputService)
				local IsSaveHovered = IsPointInsideRectangle(CurrentMousePosition, SaveButtonPos, SaveButtonSize)
				local IsExitHovered = IsPointInsideRectangle(CurrentMousePosition, ExitButtonPos, SaveButtonSize)

				DrawingImmediateFilledRectangle(SaveButtonPos, SaveButtonSize, IsSaveHovered and Theme.SaveButtonHover or Theme.SaveButtonBackground, 1, 0)
				DrawingImmediateText(Vector2.new(SaveButtonPos.X + (SaveButtonSize.X - 30) / 2, SaveButtonPos.Y + (SaveButtonSize.Y - 12) / 2), Theme.Font, 12, Theme.ButtonText, 1, "Save", false)
				DrawingImmediateFilledRectangle(ExitButtonPos, SaveButtonSize, IsExitHovered and Theme.ExitButtonHover or Theme.ExitButtonBackground, 1, 0)
				DrawingImmediateText(Vector2.new(ExitButtonPos.X + (SaveButtonSize.X - 30) / 2, ExitButtonPos.Y + (SaveButtonSize.Y - 12) / 2), Theme.Font, 12, Theme.ButtonText, 1, "Exit", false)

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
		local Camera = Workspace.CurrentCamera
		local Viewport = Camera and Camera.ViewportSize or Vector2.new(1920, 1080)
		local Scale = math.clamp(math.min(Viewport.X / 1920, Viewport.Y / 1080), 1.0, 2.0)
		for ParameterKey, BaseValue in pairs(Theme.Base) do
			Theme[ParameterKey] = BaseValue * Scale
		end
		Window._TabBarHeight = 28 * Scale
		Window._VisibleHeight = Theme.WindowVisibleHeight
	end

	local ViewportConnection
	local function ConnectViewport()
		if ViewportConnection then
			ViewportConnection:Disconnect()
			ViewportConnection = nil
		end
		local Camera = Workspace.CurrentCamera
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

function Library:SetInputBlocking(Type, Enabled)
	local Priority = 1
	local ExistingName = Library._ActiveSinks[Type]

	if ExistingName then
		UnbindCoreAction(ContextActionService, ExistingName)
		Library._ActiveSinks[Type] = nil
	end

	if Enabled then

		local NewName = RandomString(16)
		Library._ActiveSinks[Type] = NewName

		if Type == "Scroll" then
			BindCoreActionAtPriority(ContextActionService, NewName, function(ActionName, InputState, InputObject)
				return Enum.ContextActionResult.Sink
			end, false, Priority, Enum.UserInputType.MouseWheel)
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
