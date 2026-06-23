local RawCloneReference = cloneref
local cloneref = (RawCloneReference and function(Object) 
    if typeof(Object) == "Instance" then 
        return RawCloneReference(Object) 
    end 
    return Object 
end) or (function(...) 
    return ... 
end)

local RawCloneFunction = clonefunc or clonefunction
local UseRawClone = RawCloneFunction
if UseRawClone and debug.info(UseRawClone, "s") ~= "[C]" then
    UseRawClone = nil
end

local clonefunc = UseRawClone and function(TargetFunction)
    if typeof(TargetFunction) == "function" then
        return UseRawClone(TargetFunction)
    end
    return TargetFunction
end or function(TargetFunction)
    return TargetFunction
end

local RawNewCClosure = newcclosure
local UseRawNewCClosure = RawNewCClosure
if UseRawNewCClosure and debug.info(UseRawNewCClosure, "s") ~= "[C]" then
    UseRawNewCClosure = nil
end

local newcclosure = UseRawNewCClosure and function(TargetFunction)
    if typeof(TargetFunction) == "function" then
        local Success, WrappedFunction = pcall(UseRawNewCClosure, TargetFunction)
        if Success and typeof(WrappedFunction) == "function" then
            return WrappedFunction
        end
    end
    return TargetFunction
end or function(TargetFunction)
    return TargetFunction
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
RootScreenGui.Parent = CoreGui
RootScreenGui.ZIndexBehavior = Enum.ZIndexBehavior.Global
RootScreenGui.IgnoreGuiInset = true

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
            return ObjectData.GuiObject ~= nil
        end

        return ObjectData[PropertyName] or ClassMethods[PropertyName]
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

do
    function BaseDrawingClass.Remove(Self)
        if Self.GuiObject then
            Self.GuiObject:Destroy()
            Self.GuiObject = nil
        end
    end

    function BaseDrawingClass.Destroy(Self)
        Self:Remove()
        for ObjectIndex, DrawingObject in ipairs(ActiveDrawingsList) do
            if DrawingObject == Self then
                table.remove(ActiveDrawingsList, ObjectIndex)
                break
            end
        end
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
        TextLabelInstance.RichText = true
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
        end
    end

    function ImageDrawing.Create()
        local ImageLabelInstance = cloneref(Instance.new("ImageLabel"))
        ImageLabelInstance.Name = GenerateRandomString()
        ImageLabelInstance.BorderSizePixel = 0
        ImageLabelInstance.BackgroundTransparency = 1
        ImageLabelInstance.Parent = RootScreenGui

        local ObjectData = {
            GuiObject = ImageLabelInstance,
            Visible = false,
            Data = "",
            Size = Vector2.new(0, 0),
            Position = Vector2.new(0, 0),
            Transparency = 1,
            ZIndex = 1,
            Color = Color3.new(0, 0, 0)
        }

        local ImageProxy = CreateDrawingProxy(ObjectData, setmetatable(ImageDrawing, {__index = BaseDrawingClass}), ImageDrawing.UpdateProperty)
        table.insert(ActiveDrawingsList, ImageProxy)
        return ImageProxy
    end
end

local TriangleDrawing = {}

do
    local function UpdateTriangle(ObjectData)
        local GuiObject = ObjectData.GuiObject
        if not GuiObject then
            return
        end
    end

    function TriangleDrawing.UpdateProperty(Self, ObjectData, PropertyName, PropertyValue)
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
        end
    end

    function TriangleDrawing.Create()
        local FrameInstance = cloneref(Instance.new("Frame"))
        FrameInstance.Name = GenerateRandomString()
        FrameInstance.BorderSizePixel = 0
        FrameInstance.Parent = RootScreenGui

        local ObjectData = {
            GuiObject = FrameInstance,
            Visible = false,
            PointA = Vector2.new(0, 0),
            PointB = Vector2.new(0, 0),
            PointC = Vector2.new(0, 0),
            Color = Color3.new(0, 0, 0),
            Transparency = 1,
            Filled = false,
            Thickness = 1,
            ZIndex = 1
        }

        local TriangleProxy = CreateDrawingProxy(ObjectData, setmetatable(TriangleDrawing, {__index = BaseDrawingClass}), TriangleDrawing.UpdateProperty)
        table.insert(ActiveDrawingsList, TriangleProxy)
        return TriangleProxy
    end
end

local QuadDrawing = {}

do
    function QuadDrawing.UpdateProperty(Self, ObjectData, PropertyName, PropertyValue)
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
        end
    end

    function QuadDrawing.Create()
        local FrameInstance = cloneref(Instance.new("Frame"))
        FrameInstance.Name = GenerateRandomString()
        FrameInstance.BorderSizePixel = 0
        FrameInstance.Parent = RootScreenGui

        local ObjectData = {
            GuiObject = FrameInstance,
            Visible = false,
            PointA = Vector2.new(0, 0),
            PointB = Vector2.new(0, 0),
            PointC = Vector2.new(0, 0),
            PointD = Vector2.new(0, 0),
            Color = Color3.new(0, 0, 0),
            Transparency = 1,
            Filled = false,
            Thickness = 1,
            ZIndex = 1
        }

        local QuadProxy = CreateDrawingProxy(ObjectData, setmetatable(QuadDrawing, {__index = BaseDrawingClass}), QuadDrawing.UpdateProperty)
        table.insert(ActiveDrawingsList, QuadProxy)
        return QuadProxy
    end
end

local function IsRenderObject(ObjectValue)
    return type(ObjectValue) == "table" and ObjectValue.__OBJECT_EXISTS ~= nil
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
    else
        error(string.format("invalid argument #1 to 'new' (Line, Text, Image, Circle, Square, Quad, or Triangle expected, got %s)", DrawingType), 2)
    end
end

local function SetRenderProperty(DrawingObject, PropertyName, PropertyValue)
    if not IsRenderObject(DrawingObject) then
        return
    end
    if type(PropertyName) ~= "string" then
        return
    end

    pcall(function()
        DrawingObject[PropertyName] = PropertyValue
    end)
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
        local DrawingObjectInstance = table.remove(ActiveDrawingsList, 1)
        
        if DrawingObjectInstance then
            DrawingObjectInstance:Remove()
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
