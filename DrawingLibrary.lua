local RawCloneReference = cloneref or clone_ref or clonereference
local CloneReferenceIsNative = false
if RawCloneReference then
    local Success, Source = pcall(debug.info, RawCloneReference, "s")
    if Success and Source == "[C]" then
        CloneReferenceIsNative = true
    end
end

local cloneref
if RawCloneReference and CloneReferenceIsNative then
    cloneref = RawCloneReference
else
    cloneref = function(Object)
        return Object
    end
end

local RawCloneFunction = clonefunc or clonefunction
local CloneIsNative = false
if RawCloneFunction then
    local Success, Source = pcall(debug.info, RawCloneFunction, "s")
    if Success and Source == "[C]" then
        CloneIsNative = true
    end
end

local clonefunc
if RawCloneFunction and CloneIsNative then
    clonefunc = RawCloneFunction
else
    clonefunc = function(TargetFunction)
        return TargetFunction
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

local newcclosure
if RawNewCClosure and NewCClosureIsNative then
    newcclosure = RawNewCClosure
else
    newcclosure = function(TargetFunction)
        return TargetFunction
    end
end

local UserInputService, CoreGui, RunService, TextService, GetService
local DrawingLibraryInstance = {}
local ActiveDrawingsList = {}

do
    GetService = clonefunc(game.GetService)

    UserInputService = cloneref(GetService(game, "UserInputService"))
    CoreGui = cloneref(GetService(game, "CoreGui"))
    RunService = cloneref(GetService(game, "RunService"))
    TextService = cloneref(GetService(game, "TextService"))
end

local function GenerateRandomString()
    local RandomStringResult = ""

    for StringCharacterIndex = 1, 16 do
        RandomStringResult = string.format("%s%s", RandomStringResult, string.char(math.random(97, 122)))
    end

    return RandomStringResult
end

local RootScreenGui = cloneref(Instance.new("ScreenGui"))
RootScreenGui.Name = GenerateRandomString()
RootScreenGui.ZIndexBehavior = Enum.ZIndexBehavior.Global
RootScreenGui.IgnoreGuiInset = true
RootScreenGui.ResetOnSpawn = false
RootScreenGui.DisplayOrder = 2147483647

local RootScreenGuiParent = CoreGui
if type(gethui) == "function" then
    local HiddenInterfaceSucceeded, HiddenInterfaceRoot = pcall(gethui)
    if HiddenInterfaceSucceeded and typeof(HiddenInterfaceRoot) == "Instance" then
        RootScreenGuiParent = cloneref(HiddenInterfaceRoot)
    end
end

if type(protect_gui) == "function" then
    pcall(protect_gui, RootScreenGui)
elseif type(syn) == "table" and type(syn.protect_gui) == "function" then
    pcall(syn.protect_gui, RootScreenGui)
end

RootScreenGui.Parent = RootScreenGuiParent

local FontMap = {
    [0] = Enum.Font.SourceSans,
    [1] = Enum.Font.Arial,
    [2] = Enum.Font.Roboto,
    [3] = Enum.Font.Code
}

local Fonts = {
    ["UI"] = 0,
    ["System"] = 1,
    ["Plex"] = 2,
    ["Monospace"] = 3
}

DrawingLibraryInstance.FontMap = FontMap
DrawingLibraryInstance.Font = Fonts

local function CreateDrawingProxy(ObjectData, ClassMethods, UpdateCallback)
    ObjectData.Exists = ObjectData.Exists ~= false
    local DrawingProxy = {}
    local ProxyMetatable = {}

    ProxyMetatable.__index = function(ProxySelf, PropertyName)
        if PropertyName == "TextBounds" and ObjectData.GuiObject and ObjectData.GuiObject:IsA("TextLabel") then
            local TargetFontId = ObjectData.Font
            local TargetFont = (TargetFontId and FontMap[TargetFontId]) or FontMap[0] or Enum.Font.Roboto
            local TargetSize = ObjectData.Size or 13
            local TargetText = ObjectData.Text or ""
            local SuccessStatus, CalculatedTextSize = pcall(TextService.GetTextSize, TextService, tostring(TargetText), TargetSize, TargetFont, Vector2.new(10000, 10000))
            if SuccessStatus then
                return Vector2.new(CalculatedTextSize.X, CalculatedTextSize.Y)
            end
            return Vector2.new(0, 0)
        end

        if PropertyName == "__OBJECT_EXISTS" then
            return ObjectData.Exists == true
        end

        -- Preserve valid false-valued properties such as Visible, Filled,
        -- Center, and Outline. Using boolean `or` here incorrectly replaced
        -- false with a class member lookup and returned nil to callers.
        local StoredPropertyValue = rawget(ObjectData, PropertyName)
        if StoredPropertyValue ~= nil then
            return StoredPropertyValue
        end

        return ClassMethods[PropertyName]
    end

    ProxyMetatable.__newindex = function(ProxySelf, PropertyName, PropertyValue)
        local IsNewValue = ObjectData[PropertyName] ~= PropertyValue
        ObjectData[PropertyName] = PropertyValue

        if UpdateCallback and (IsNewValue or PropertyName == "Font" or PropertyName == "Text") then
            UpdateCallback(ProxySelf, ObjectData, PropertyName, PropertyValue)
        end
    end

    ProxyMetatable.__tostring = function()
        return "Drawing"
    end

    return setmetatable(DrawingProxy, ProxyMetatable)
end

local BaseDrawingClass = {}

local function RemoveActiveDrawing(DrawingObject)
    for ObjectIndex = #ActiveDrawingsList, 1, -1 do
        if ActiveDrawingsList[ObjectIndex] == DrawingObject then
            table.remove(ActiveDrawingsList, ObjectIndex)
            return
        end
    end
end

do
    function BaseDrawingClass.Remove(Self)
        local GuiObject = Self.GuiObject
        if GuiObject then
            pcall(GuiObject.Destroy, GuiObject)
            Self.GuiObject = nil
        end
        Self.__OBJECT_EXISTS = false
        RemoveActiveDrawing(Self)
    end

    function BaseDrawingClass.Destroy(Self)
        Self:Remove()
    end
end

local SquareDrawing = {}

do
    function SquareDrawing.UpdateProperty(Self, ObjectData, PropertyName, PropertyValue)
        if not ObjectData or not ObjectData.GuiObject then
            return
        end
        
        local GuiObject = ObjectData.GuiObject
        local StrokeObject = ObjectData.StrokeObject
        local CornerObject = ObjectData.CornerObject

        if PropertyName == "Visible" then
            GuiObject.Visible = PropertyValue
        elseif PropertyName == "ZIndex" then
            GuiObject.ZIndex = PropertyValue
        elseif PropertyName == "Transparency" then
            if ObjectData.Filled then
                GuiObject.BackgroundTransparency = 1 - (PropertyValue or 1)
            else
                GuiObject.BackgroundTransparency = 1
            end
            if StrokeObject then
                StrokeObject.Transparency = 1 - (PropertyValue or 1)
            end
        elseif PropertyName == "Color" then
            GuiObject.BackgroundColor3 = PropertyValue
            if StrokeObject then
                StrokeObject.Color = PropertyValue
            end
        elseif PropertyName == "Position" then
            if PropertyValue then
                GuiObject.Position = UDim2.fromOffset(PropertyValue.X, PropertyValue.Y)
            end
        elseif PropertyName == "Size" then
            if PropertyValue then
                GuiObject.Size = UDim2.fromOffset(PropertyValue.X, PropertyValue.Y)
            end
        elseif PropertyName == "Filled" then
            if PropertyValue then
                GuiObject.BackgroundTransparency = 1 - (ObjectData.Transparency or 1)
                if StrokeObject then
                    StrokeObject.Enabled = false
                end
            else
                GuiObject.BackgroundTransparency = 1
                if StrokeObject then
                    StrokeObject.Enabled = true
                    StrokeObject.Thickness = ObjectData.Thickness or 1
                end
            end
        elseif PropertyName == "Thickness" then
            if StrokeObject then
                StrokeObject.Thickness = PropertyValue
            end
        elseif PropertyName == "Rounding" then
            if CornerObject then
                CornerObject.CornerRadius = UDim.new(0, PropertyValue or 0)
            end
        end
    end

    function SquareDrawing.Create()
        local FrameInstance = cloneref(Instance.new("Frame"))
        FrameInstance.Name = GenerateRandomString()
        FrameInstance.BorderSizePixel = 0
        FrameInstance.BackgroundColor3 = Color3.new(0, 0, 0)
        FrameInstance.BackgroundTransparency = 0
        FrameInstance.Position = UDim2.fromOffset(0, 0)
        FrameInstance.Size = UDim2.fromOffset(0, 0)
        FrameInstance.Visible = false
        FrameInstance.Parent = RootScreenGui

        local StrokeInstance = cloneref(Instance.new("UIStroke"))
        StrokeInstance.Name = GenerateRandomString()
        StrokeInstance.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
        StrokeInstance.LineJoinMode = Enum.LineJoinMode.Miter
        StrokeInstance.Thickness = 1
        StrokeInstance.Transparency = 0
        StrokeInstance.Enabled = false
        StrokeInstance.Parent = FrameInstance

        local CornerInstance = cloneref(Instance.new("UICorner"))
        CornerInstance.CornerRadius = UDim.new(0, 0)
        CornerInstance.Parent = FrameInstance

        local ObjectData = {
            GuiObject = FrameInstance,
            StrokeObject = StrokeInstance,
            CornerObject = CornerInstance,
            Visible = false,
            ZIndex = 1,
            Transparency = 1,
            Color = Color3.new(0, 0, 0),
            Thickness = 1,
            Filled = false,
            Size = Vector2.new(0, 0),
            Position = Vector2.new(0, 0),
            Rounding = 0
        }

        local SquareProxy = CreateDrawingProxy(ObjectData, setmetatable(SquareDrawing, {__index = BaseDrawingClass}), SquareDrawing.UpdateProperty)

        SquareDrawing.UpdateProperty(SquareProxy, ObjectData, "Visible", false)
        SquareDrawing.UpdateProperty(SquareProxy, ObjectData, "Color", ObjectData.Color)
        SquareDrawing.UpdateProperty(SquareProxy, ObjectData, "Filled", ObjectData.Filled)

        table.insert(ActiveDrawingsList, SquareProxy)
        return SquareProxy
    end
end

local TextDrawing = {}

do
    local function RecalculateTextBounds(ObjectData)
        local TargetFont = FontMap[ObjectData.Font] or Enum.Font.SourceSans
        local TargetSize = ObjectData.Size or 18
        local TargetText = ObjectData.Text or ""
        local TextBounds = TextService:GetTextSize(TargetText, TargetSize, TargetFont, Vector2.new(10000, 10000))
        ObjectData.GuiObject.Size = UDim2.fromOffset(math.ceil(TextBounds.X), math.ceil(TextBounds.Y))
    end

    function TextDrawing.UpdateProperty(Self, ObjectData, PropertyName, PropertyValue)
        local GuiObject = ObjectData.GuiObject
        if not GuiObject then
            return
        end

        if PropertyName == "Visible" then
            GuiObject.Visible = PropertyValue
        elseif PropertyName == "ZIndex" then
            GuiObject.ZIndex = PropertyValue
        elseif PropertyName == "Text" then
            GuiObject.Text = tostring(PropertyValue or "")
            RecalculateTextBounds(ObjectData)
        elseif PropertyName == "Color" then
            GuiObject.TextColor3 = PropertyValue
        elseif PropertyName == "Size" then
            GuiObject.TextSize = PropertyValue
            RecalculateTextBounds(ObjectData)
        elseif PropertyName == "Center" then
            GuiObject.TextXAlignment = PropertyValue and Enum.TextXAlignment.Center or Enum.TextXAlignment.Left
            GuiObject.AnchorPoint = PropertyValue and Vector2.new(0.5, 0) or Vector2.new(0, 0)
        elseif PropertyName == "Outline" then
            GuiObject.TextStrokeTransparency = PropertyValue and 0 or 1
        elseif PropertyName == "OutlineColor" then
            GuiObject.TextStrokeColor3 = PropertyValue
        elseif PropertyName == "Position" then
            if PropertyValue then
                GuiObject.Position = UDim2.fromOffset(PropertyValue.X, PropertyValue.Y)
            end
        elseif PropertyName == "Transparency" then
            GuiObject.TextTransparency = 1 - (PropertyValue or 1)
            GuiObject.TextStrokeTransparency = ObjectData.Outline and (1 - (PropertyValue or 1)) or 1
        elseif PropertyName == "Font" then
            local SelectedFont = FontMap[PropertyValue] or Enum.Font.SourceSans
            GuiObject.Font = SelectedFont
            RecalculateTextBounds(ObjectData)
        end
    end

    function TextDrawing.Create()
        local TextLabelInstance = cloneref(Instance.new("TextLabel"))
        TextLabelInstance.Name = GenerateRandomString()
        TextLabelInstance.BorderSizePixel = 0
        TextLabelInstance.BackgroundTransparency = 1
        TextLabelInstance.Parent = RootScreenGui
        TextLabelInstance.Visible = false
        -- Drawing.Text treats markup as ordinary text. RichText must stay off or
        -- values containing angle brackets render differently from native Drawing.
        TextLabelInstance.RichText = false
        TextLabelInstance.Font = FontMap[0]
        TextLabelInstance.TextSize = 18
        TextLabelInstance.AnchorPoint = Vector2.new(0, 0)
        TextLabelInstance.TextWrapped = false
        TextLabelInstance.AutomaticSize = Enum.AutomaticSize.None
        TextLabelInstance.Text = ""
        TextLabelInstance.TextColor3 = Color3.new(0, 0, 0)

        local ObjectData = {
            GuiObject = TextLabelInstance,
            Visible = false,
            Color = Color3.new(0, 0, 0),
            Text = "",
            Size = 18,
            Center = false,
            Outline = false,
            OutlineColor = Color3.new(0, 0, 0),
            Position = Vector2.new(0, 0),
            Font = 0,
            Transparency = 1,
            ZIndex = 1
        }

        local TextProxy = CreateDrawingProxy(ObjectData, setmetatable(TextDrawing, {__index = BaseDrawingClass}), TextDrawing.UpdateProperty)

        TextDrawing.UpdateProperty(TextProxy, ObjectData, "Visible", false)
        TextDrawing.UpdateProperty(TextProxy, ObjectData, "Color", ObjectData.Color)

        table.insert(ActiveDrawingsList, TextProxy)
        return TextProxy
    end
end

local LineDrawing = {}

do
    function LineDrawing.UpdateProperty(Self, ObjectData, PropertyName, PropertyValue)
        local GuiObject = ObjectData.GuiObject
        if not GuiObject then
            return
        end

        if PropertyName == "Visible" then
            GuiObject.Visible = PropertyValue
        elseif PropertyName == "ZIndex" then
            GuiObject.ZIndex = PropertyValue
        elseif PropertyName == "Color" then
            GuiObject.BackgroundColor3 = PropertyValue
        elseif PropertyName == "Transparency" then
            GuiObject.BackgroundTransparency = 1 - (PropertyValue or 1)
        elseif PropertyName == "From" or PropertyName == "To" or PropertyName == "Thickness" then
            local FromPos = ObjectData.From or Vector2.new(0, 0)
            local ToPos = ObjectData.To or Vector2.new(0, 0)
            local ThicknessValue = ObjectData.Thickness or 1
            local DeltaVector = ToPos - FromPos
            local DistanceValue = DeltaVector.Magnitude

            GuiObject.Size = UDim2.fromOffset(DistanceValue, ThicknessValue)
            GuiObject.Position = UDim2.fromOffset(FromPos.X + DeltaVector.X / 2, FromPos.Y + DeltaVector.Y / 2)
            GuiObject.Rotation = math.deg(math.atan2(DeltaVector.Y, DeltaVector.X))
        end
    end

    function LineDrawing.Create()
        local FrameInstance = cloneref(Instance.new("Frame"))
        FrameInstance.Name = GenerateRandomString()
        FrameInstance.BorderSizePixel = 0
        FrameInstance.BackgroundColor3 = Color3.new(0, 0, 0)
        FrameInstance.AnchorPoint = Vector2.new(0.5, 0.5)
        FrameInstance.Position = UDim2.fromOffset(0, 0)
        FrameInstance.Size = UDim2.fromOffset(0, 0)
        FrameInstance.Visible = false
        FrameInstance.Parent = RootScreenGui

        local ObjectData = {
            GuiObject = FrameInstance,
            Visible = false,
            Color = Color3.new(0, 0, 0),
            Thickness = 1,
            From = Vector2.new(0, 0),
            To = Vector2.new(0, 0),
            Transparency = 1,
            ZIndex = 1
        }

        local LineProxy = CreateDrawingProxy(ObjectData, setmetatable(LineDrawing, {__index = BaseDrawingClass}), LineDrawing.UpdateProperty)
        table.insert(ActiveDrawingsList, LineProxy)
        return LineProxy
    end
end

local CircleDrawing = {}

do
    function CircleDrawing.UpdateProperty(Self, ObjectData, PropertyName, PropertyValue)
        local GuiObject = ObjectData.GuiObject
        if not GuiObject then
            return
        end

        local StrokeObject = ObjectData.StrokeObject

        if PropertyName == "Visible" then
            GuiObject.Visible = PropertyValue
        elseif PropertyName == "ZIndex" then
            GuiObject.ZIndex = PropertyValue
        elseif PropertyName == "Color" then
            GuiObject.BackgroundColor3 = PropertyValue
            if StrokeObject then
                StrokeObject.Color = PropertyValue
            end
        elseif PropertyName == "Transparency" then
            if ObjectData.Filled then
                GuiObject.BackgroundTransparency = 1 - (PropertyValue or 1)
            else
                GuiObject.BackgroundTransparency = 1
            end
            if StrokeObject then
                StrokeObject.Transparency = 1 - (PropertyValue or 1)
            end
        elseif PropertyName == "Radius" or PropertyName == "Position" then
            local RadiusValue = ObjectData.Radius or 0
            local CenterPos = ObjectData.Position or Vector2.new(0, 0)
            GuiObject.Size = UDim2.fromOffset(RadiusValue * 2, RadiusValue * 2)
            GuiObject.Position = UDim2.fromOffset(CenterPos.X, CenterPos.Y)
        elseif PropertyName == "Filled" then
            if PropertyValue then
                GuiObject.BackgroundTransparency = 1 - (ObjectData.Transparency or 1)
                if StrokeObject then
                    StrokeObject.Enabled = false
                end
            else
                GuiObject.BackgroundTransparency = 1
                if StrokeObject then
                    StrokeObject.Enabled = true
                    StrokeObject.Thickness = ObjectData.Thickness or 1
                end
            end
        elseif PropertyName == "Thickness" then
            if StrokeObject then
                StrokeObject.Thickness = PropertyValue
            end
        end
    end

    function CircleDrawing.Create()
        local FrameInstance = cloneref(Instance.new("Frame"))
        FrameInstance.Name = GenerateRandomString()
        FrameInstance.BorderSizePixel = 0
        FrameInstance.BackgroundColor3 = Color3.new(0, 0, 0)
        FrameInstance.AnchorPoint = Vector2.new(0.5, 0.5)
        FrameInstance.Position = UDim2.fromOffset(0, 0)
        FrameInstance.Size = UDim2.fromOffset(0, 0)
        FrameInstance.Visible = false
        FrameInstance.Parent = RootScreenGui

        local UICornerInstance = cloneref(Instance.new("UICorner"))
        UICornerInstance.CornerRadius = UDim.new(1, 0)
        UICornerInstance.Parent = FrameInstance

        local StrokeInstance = cloneref(Instance.new("UIStroke"))
        StrokeInstance.Name = GenerateRandomString()
        StrokeInstance.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
        StrokeInstance.Thickness = 1
        StrokeInstance.Transparency = 0
        StrokeInstance.Enabled = false
        StrokeInstance.Parent = FrameInstance

        local ObjectData = {
            GuiObject = FrameInstance,
            StrokeObject = StrokeInstance,
            Visible = false,
            Color = Color3.new(0, 0, 0),
            Radius = 0,
            Position = Vector2.new(0, 0),
            Transparency = 1,
            Filled = false,
            Thickness = 1,
            NumSides = 250,
            ZIndex = 1
        }

        local CircleProxy = CreateDrawingProxy(ObjectData, setmetatable(CircleDrawing, {__index = BaseDrawingClass}), CircleDrawing.UpdateProperty)
        CircleDrawing.UpdateProperty(CircleProxy, ObjectData, "Filled", false)
        table.insert(ActiveDrawingsList, CircleProxy)
        return CircleProxy
    end
end

local ImageDrawing = {}

do
    function ImageDrawing.UpdateProperty(Self, ObjectData, PropertyName, PropertyValue)
        local GuiObject = ObjectData.GuiObject
        if not GuiObject then
            return
        end

        if PropertyName == "Visible" then
            GuiObject.Visible = PropertyValue
        elseif PropertyName == "ZIndex" then
            GuiObject.ZIndex = PropertyValue
        elseif PropertyName == "Data" then
            GuiObject.Image = PropertyValue
        elseif PropertyName == "Size" then
            if PropertyValue then
                GuiObject.Size = UDim2.fromOffset(PropertyValue.X, PropertyValue.Y)
            end
        elseif PropertyName == "Position" then
            if PropertyValue then
                GuiObject.Position = UDim2.fromOffset(PropertyValue.X, PropertyValue.Y)
            end
        elseif PropertyName == "Transparency" then
            GuiObject.ImageTransparency = 1 - (PropertyValue or 1)
        elseif PropertyName == "Color" then
            GuiObject.ImageColor3 = PropertyValue
        elseif PropertyName == "Rounding" then
            local CornerObject = ObjectData.CornerObject
            if CornerObject then
                CornerObject.CornerRadius = UDim.new(0, math.max(0, tonumber(PropertyValue) or 0))
            end
        end
    end

    function ImageDrawing.Create()
        local ImageLabelInstance = cloneref(Instance.new("ImageLabel"))
        ImageLabelInstance.Name = GenerateRandomString()
        ImageLabelInstance.BorderSizePixel = 0
        ImageLabelInstance.BackgroundTransparency = 1
        ImageLabelInstance.Position = UDim2.fromOffset(0, 0)
        ImageLabelInstance.Size = UDim2.fromOffset(0, 0)
        ImageLabelInstance.Visible = false
        ImageLabelInstance.Parent = RootScreenGui

        local CornerInstance = cloneref(Instance.new("UICorner"))
        CornerInstance.CornerRadius = UDim.new(0, 0)
        CornerInstance.Parent = ImageLabelInstance

        local ObjectData = {
            GuiObject = ImageLabelInstance,
            CornerObject = CornerInstance,
            Visible = false,
            Data = "",
            Size = Vector2.new(0, 0),
            Position = Vector2.new(0, 0),
            Transparency = 1,
            ZIndex = 1,
            Color = Color3.new(0, 0, 0),
            Rounding = 0
        }

        local ImageProxy = CreateDrawingProxy(ObjectData, setmetatable(ImageDrawing, {__index = BaseDrawingClass}), ImageDrawing.UpdateProperty)
        ImageDrawing.UpdateProperty(ImageProxy, ObjectData, "Color", ObjectData.Color)
        ImageDrawing.UpdateProperty(ImageProxy, ObjectData, "Rounding", ObjectData.Rounding)
        table.insert(ActiveDrawingsList, ImageProxy)
        return ImageProxy
    end
end

-- Roblox GUI objects do not provide a native arbitrary-polygon primitive. The
-- emulator builds polygon outlines from rotated Frames and filled polygons from
-- bounded horizontal scanlines. This keeps Triangle and Quad functional without
-- relying on a remote image asset or an executor-specific extension.
local PolygonDrawing = {}

local function CreatePolygonSegment(ParentObject)
    local SegmentFrame = cloneref(Instance.new("Frame"))
    SegmentFrame.Name = GenerateRandomString()
    SegmentFrame.AnchorPoint = Vector2.new(0.5, 0.5)
    SegmentFrame.BorderSizePixel = 0
    SegmentFrame.BackgroundColor3 = Color3.new(0, 0, 0)
    SegmentFrame.BackgroundTransparency = 0
    SegmentFrame.Visible = false
    SegmentFrame.Parent = ParentObject
    return SegmentFrame
end

local function ApplyPolygonSegment(SegmentFrame, FromPosition, ToPosition, Thickness, ObjectData)
    local DeltaVector = ToPosition - FromPosition
    local Distance = DeltaVector.Magnitude
    SegmentFrame.Position = UDim2.fromOffset(
        FromPosition.X + DeltaVector.X * 0.5,
        FromPosition.Y + DeltaVector.Y * 0.5
    )
    SegmentFrame.Size = UDim2.fromOffset(math.max(0.01, Distance), math.max(0.01, Thickness))
    SegmentFrame.Rotation = math.deg(math.atan2(DeltaVector.Y, DeltaVector.X))
    SegmentFrame.BackgroundColor3 = ObjectData.Color
    SegmentFrame.BackgroundTransparency = 1 - math.clamp(tonumber(ObjectData.Transparency) or 1, 0, 1)
    SegmentFrame.ZIndex = tonumber(ObjectData.ZIndex) or 1
    SegmentFrame.Visible = true
end

local function HidePolygonSegments(SegmentList, FirstHiddenIndex)
    for SegmentIndex = FirstHiddenIndex or 1, #SegmentList do
        SegmentList[SegmentIndex].Visible = false
    end
end

local function GetPolygonSegment(SegmentList, SegmentIndex, ParentObject)
    local SegmentFrame = SegmentList[SegmentIndex]
    if not SegmentFrame then
        SegmentFrame = CreatePolygonSegment(ParentObject)
        SegmentList[SegmentIndex] = SegmentFrame
    end
    return SegmentFrame
end

local function ReadPolygonPoints(ObjectData)
    local Points = {}
    for PointIndex, PropertyName in ipairs(ObjectData.PointPropertyNames) do
        local PointValue = ObjectData[PropertyName]
        if typeof(PointValue) ~= "Vector2" then
            return nil
        end
        Points[PointIndex] = PointValue
    end
    return Points
end

local function UpdatePolygon(ObjectData)
    local ContainerFrame = ObjectData.GuiObject
    if not ContainerFrame then
        return
    end

    ContainerFrame.Visible = ObjectData.Visible == true
    ContainerFrame.ZIndex = tonumber(ObjectData.ZIndex) or 1

    local Points = ReadPolygonPoints(ObjectData)
    if not Points or #Points < 3 then
        HidePolygonSegments(ObjectData.OutlineSegments)
        HidePolygonSegments(ObjectData.FillSegments)
        return
    end

    if ObjectData.Filled ~= true then
        HidePolygonSegments(ObjectData.FillSegments)
        local OutlineThickness = math.max(0.01, tonumber(ObjectData.Thickness) or 1)
        for PointIndex = 1, #Points do
            local NextPointIndex = PointIndex % #Points + 1
            ApplyPolygonSegment(
                GetPolygonSegment(ObjectData.OutlineSegments, PointIndex, ContainerFrame),
                Points[PointIndex],
                Points[NextPointIndex],
                OutlineThickness,
                ObjectData
            )
        end
        HidePolygonSegments(ObjectData.OutlineSegments, #Points + 1)
        return
    end

    HidePolygonSegments(ObjectData.OutlineSegments)
    local MinimumY, MaximumY = Points[1].Y, Points[1].Y
    for PointIndex = 2, #Points do
        MinimumY = math.min(MinimumY, Points[PointIndex].Y)
        MaximumY = math.max(MaximumY, Points[PointIndex].Y)
    end

    local PolygonHeight = math.max(0, MaximumY - MinimumY)
    local ScanlineStep = math.max(1, PolygonHeight / 192)
    local ScanlineThickness = ScanlineStep + 0.75
    local SegmentIndex = 0
    local ScanlineY = MinimumY + ScanlineStep * 0.5

    while ScanlineY < MaximumY and SegmentIndex < 256 do
        local Intersections = {}
        for PointIndex = 1, #Points do
            local FirstPoint = Points[PointIndex]
            local SecondPoint = Points[PointIndex % #Points + 1]
            local CrossesScanline = (FirstPoint.Y <= ScanlineY and SecondPoint.Y > ScanlineY)
                or (SecondPoint.Y <= ScanlineY and FirstPoint.Y > ScanlineY)
            if CrossesScanline then
                local EdgeProgress = (ScanlineY - FirstPoint.Y) / (SecondPoint.Y - FirstPoint.Y)
                Intersections[#Intersections + 1] = FirstPoint.X
                    + (SecondPoint.X - FirstPoint.X) * EdgeProgress
            end
        end
        table.sort(Intersections)

        for IntersectionIndex = 1, #Intersections - 1, 2 do
            if SegmentIndex >= 256 then
                break
            end
            local LeftX = Intersections[IntersectionIndex]
            local RightX = Intersections[IntersectionIndex + 1]
            if LeftX and RightX and RightX >= LeftX then
                SegmentIndex = SegmentIndex + 1
                ApplyPolygonSegment(
                    GetPolygonSegment(ObjectData.FillSegments, SegmentIndex, ContainerFrame),
                    Vector2.new(LeftX, ScanlineY),
                    Vector2.new(RightX, ScanlineY),
                    ScanlineThickness,
                    ObjectData
                )
            end
        end
        ScanlineY = ScanlineY + ScanlineStep
    end
    HidePolygonSegments(ObjectData.FillSegments, SegmentIndex + 1)
end

function PolygonDrawing.UpdateProperty(Self, ObjectData, PropertyName)
    if PropertyName == "Visible"
        or PropertyName == "ZIndex"
        or PropertyName == "Color"
        or PropertyName == "Transparency"
        or PropertyName == "Filled"
        or PropertyName == "Thickness"
        or (type(PropertyName) == "string" and string.match(PropertyName, "^Point[A-D]$"))
    then
        UpdatePolygon(ObjectData)
    end
end

local function CreatePolygonDrawing(PointPropertyNames)
    local ContainerFrame = cloneref(Instance.new("Frame"))
    ContainerFrame.Name = GenerateRandomString()
    ContainerFrame.BackgroundTransparency = 1
    ContainerFrame.BorderSizePixel = 0
    ContainerFrame.ClipsDescendants = false
    ContainerFrame.Position = UDim2.fromOffset(0, 0)
    ContainerFrame.Size = UDim2.new(1, 0, 1, 0)
    ContainerFrame.Visible = false
    ContainerFrame.Parent = RootScreenGui

    local ObjectData = {
        GuiObject = ContainerFrame,
        PointPropertyNames = PointPropertyNames,
        OutlineSegments = {},
        FillSegments = {},
        Visible = false,
        Color = Color3.new(0, 0, 0),
        Transparency = 1,
        Filled = false,
        Thickness = 1,
        ZIndex = 1,
    }
    for PointIndex, PropertyName in ipairs(PointPropertyNames) do
        ObjectData[PropertyName] = Vector2.new(0, 0)
    end

    local PolygonProxy = CreateDrawingProxy(
        ObjectData,
        setmetatable(PolygonDrawing, { __index = BaseDrawingClass }),
        PolygonDrawing.UpdateProperty
    )
    table.insert(ActiveDrawingsList, PolygonProxy)
    return PolygonProxy
end

local TriangleDrawing = {}
function TriangleDrawing.Create()
    return CreatePolygonDrawing({ "PointA", "PointB", "PointC" })
end

local QuadDrawing = {}
function QuadDrawing.Create()
    return CreatePolygonDrawing({ "PointA", "PointB", "PointC", "PointD" })
end

local FontDrawing = {}
function FontDrawing.Create()
    local ObjectData = {
        Data = "",
        Exists = true,
    }
    local FontProxy = CreateDrawingProxy(
        ObjectData,
        setmetatable(FontDrawing, { __index = BaseDrawingClass }),
        nil
    )
    table.insert(ActiveDrawingsList, FontProxy)
    return FontProxy
end

local ShaderDrawing = {}
function ShaderDrawing.Create()
    error("HLSL shaders are unavailable in the ScreenGui Drawing emulator", 2)
end

function ShaderDrawing.New()
    local ObjectData = {
        Vertex = "",
        Pixel = "",
        Position = Vector2.new(0, 0),
        Size = Vector2.new(0, 0),
        Exists = true,
    }
    local ShaderProxy = CreateDrawingProxy(
        ObjectData,
        setmetatable(ShaderDrawing, { __index = BaseDrawingClass }),
        nil
    )
    table.insert(ActiveDrawingsList, ShaderProxy)
    return ShaderProxy
end

local function IsRenderObject(ObjectValue)
    if type(ObjectValue) ~= "table" then
        return false
    end
    local PropertyReadSucceeded, ObjectExists = pcall(function()
        return ObjectValue.__OBJECT_EXISTS
    end)
    return PropertyReadSucceeded and ObjectExists == true
end

local CustomDrawingFonts = {
    UI = 0,
    System = 1,
    Plex = 2,
    Monospace = 3
}

local CustomDrawingNew = function(DrawingType)
    if type(DrawingType) ~= "string" then
        error(string.format("invalid argument #1 to 'new' (string expected, got %s)", type(DrawingType)), 2)
    end

    if DrawingType == "Square" then
        return SquareDrawing.Create()
    elseif DrawingType == "Text" then
        return TextDrawing.Create()
    elseif DrawingType == "Line" then
        return LineDrawing.Create()
    elseif DrawingType == "Circle" then
        return CircleDrawing.Create()
    elseif DrawingType == "Image" then
        return ImageDrawing.Create()
    elseif DrawingType == "Triangle" then
        return TriangleDrawing.Create()
    elseif DrawingType == "Quad" then
        return QuadDrawing.Create()
    elseif DrawingType == "Font" then
        return FontDrawing.Create()
    elseif DrawingType == "Shader" then
        return ShaderDrawing.New()
    else
        error(string.format("invalid argument #1 to 'new' (Line, Text, Image, Circle, Square, Quad, Triangle, Font, or Shader expected, got %s)", DrawingType), 2)
    end
end

local function SetRenderProperty(DrawingObject, PropertyName, PropertyValue)
    if not IsRenderObject(DrawingObject) then
        return
    end
    if type(PropertyName) ~= "string" then
        return
    end

    DrawingObject[PropertyName] = PropertyValue
end

local function GetRenderProperty(DrawingObject, PropertyName)
    if not IsRenderObject(DrawingObject) then
        return nil
    end

    if type(PropertyName) ~= "string" then
        return nil
    end

    return DrawingObject[PropertyName]
end

local function ClearDrawingCache()
    while #ActiveDrawingsList > 0 do
        local DrawingObjectInstance = ActiveDrawingsList[#ActiveDrawingsList]
        if DrawingObjectInstance then
            DrawingObjectInstance:Remove()
        else
            table.remove(ActiveDrawingsList)
        end
    end
end

local function DestroyDrawingObject(DrawingObjectInstance)
    if DrawingObjectInstance then
        DrawingObjectInstance:Destroy()
    end
end

DrawingLibraryInstance.new = CustomDrawingNew
DrawingLibraryInstance.Font = CustomDrawingFonts
DrawingLibraryInstance.Fonts = CustomDrawingFonts
DrawingLibraryInstance.IsRenderObject = IsRenderObject
DrawingLibraryInstance.SetRenderProperty = SetRenderProperty
DrawingLibraryInstance.GetRenderProperty = GetRenderProperty
DrawingLibraryInstance.ClearDrawingCache = ClearDrawingCache
DrawingLibraryInstance.ClearDrawCache = ClearDrawingCache
DrawingLibraryInstance.DestroyDrawingObject = DestroyDrawingObject

return DrawingLibraryInstance
