-- PulseCore Version: 2.5.9
-- Version scheme: 1.0.0 -> 1.0.5 -> 1.0.10; each release increments the final component by 5.
SCRIPT_VERSION = "2.5.9"
local guiDestroyed = false

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
HttpService = game:GetService("HttpService")
LogService = game:GetService("LogService")
TextChatService = game:GetService("TextChatService")

local localPlayer = Players.LocalPlayer
local playerGui = localPlayer:WaitForChild("PlayerGui")

DEFAULT_SPEED_BONUS = 16
MIN_SPEED_BONUS = 1
MAX_SPEED_BONUS = 1000

DEFAULT_JUMP_BONUS = 50
MIN_JUMP_BONUS = 0
MAX_JUMP_BONUS = 200

DEFAULT_BOOST_KEY = Enum.KeyCode.R
DEFAULT_INTERFACE_KEY = Enum.KeyCode.V
DEFAULT_NOCLIP_KEY = Enum.KeyCode.N
DEFAULT_FLIGHT_KEY = Enum.KeyCode.F
DEFAULT_FLIGHT_SPEED = 50
MIN_FLIGHT_SPEED = 1
MAX_FLIGHT_SPEED = 200
MAX_ABILITIES = 4
ABILITY_DEFAULT_KEYS = {
    Enum.KeyCode.E,
    Enum.KeyCode.Q,
    Enum.KeyCode.Z,
    Enum.KeyCode.C,
}

MAX_CONFIG_NAME_LENGTH = 32
CONFIG_ATTRIBUTE_NAME = "SpeedBoostConfigsV1"
AUTO_LOAD_ATTRIBUTE_NAME = "SpeedBoostAutoLoadV1"
CONSOLE_MODE_ATTRIBUTE_NAME = "PulseCoreConsoleModeV1"

UPDATE_CHECK_RAW_URL = "https://raw.githubusercontent.com/Marckoq/loader/main/PulseCore.lua"
UPDATE_CHECK_BUILD_ID = "2.5.9"
UPDATE_CHECK_FINGERPRINT = "cb4cbb8a9d577bb8826a178fa50e09f5"
UPDATE_CHECK_INTERVAL = 0.50
UPDATE_NOTIFICATION_DURATION = 8


CONFIG_ROOT_PATH = nil
CONFIG_AUTOLOAD_FILE = nil
CONFIG_INDEX_FILE = nil
CONFIG_FILE_EXTENSION = ".json"
CONFIG_PATH_FALLBACK = false

CUSTOM_LMS_ROOT = "PulseCore\\Custom LMS"
CUSTOM_LMS_CHARACTERS = {
    "Sonic",
    "Tails",
    "Knuckles",
    "Eggman",
    "Amy",
    "Cream",
    "Silver",
    "Blaze",
    "Metal Sonic",
}
CUSTOM_LMS_AUDIO_EXTENSIONS = {
    mp3 = true,
    ogg = true,
    wav = true,
}
CUSTOM_LMS_STANDARD_SOUND_NAMES = {
    TailsSolo = true,
    CreamSolo = true,
    EggmanSolo = true,
    KnucklesSolo = true,
    MetalSonicSolo = true,
    SonicSolo = true,
    SilverSolo = true,
    BlazeSolo = true,
    AmySolo = true,
}
CUSTOM_LMS_STANDARD_SOUND_IDS = {
    ["101018907191326"] = true,
    ["101771084079612"] = true,
    ["86981182369115"] = true,
    ["82683591153670"] = true,
    ["82965945880276"] = true,
    ["136212496176401"] = true,
    ["77138683500819"] = true,
    ["132006407031162"] = true,
    ["136872859122533"] = true,
}

function getPulseCoreExecutorName()
    local resolvers = {
        function()
            return identifyexecutor
        end,
        function()
            return getexecutorname
        end,
        function()
            return whatexecutor
        end,
    }

    for _, getResolver in ipairs(resolvers) do
        local okResolver, resolver = pcall(getResolver)

        if okResolver and type(resolver) == "function" then
            local ok, result = pcall(resolver)

            if ok and result and tostring(result) ~= "" then
                local executorName = tostring(result)
                    :gsub('[<>:"/\\|?*]', "_")
                    :gsub("[%c]", "_")
                    :gsub("%s+$", "")

                if executorName ~= "" then
                    return executorName
                end
            end
        end
    end

    return "Executor"
end

function getPulseCoreEnvironment()
    local environments = {}

    local function addEnvironment(environment)
        if type(environment) ~= "table" then
            return
        end

        for _, existing in ipairs(environments) do
            if existing == environment then
                return
            end
        end

        table.insert(environments, environment)
    end

    pcall(function()
        addEnvironment(_ENV)
    end)

    pcall(function()
        local getgenv = _G.getgenv
        if type(getgenv) == "function" then
            addEnvironment(getgenv())
        end
    end)

    pcall(function()
        local getfenv = _G.getfenv
        if type(getfenv) == "function" then
            addEnvironment(getfenv(0))
        end
    end)

    addEnvironment(_G)

    return environments
end

function getPulseCoreFileApi(functionName)


    local directResolvers = {
        readfile = function()
            return readfile
        end,
        writefile = function()
            return writefile
        end,
        makefolder = function()
            return makefolder
        end,
        appendfile = function()
            return appendfile
        end,
        listfiles = function()
            return listfiles
        end,
        isfile = function()
            return isfile
        end,
        isfolder = function()
            return isfolder
        end,
        delfile = function()
            return delfile
        end,
        delfolder = function()
            return delfolder
        end,
    }

    local directResolver = directResolvers[functionName]
    if directResolver then
        local ok, direct = pcall(directResolver)
        if ok and type(direct) == "function" then
            return direct
        end
    end

    local aliases = {
        readfile = {"read", "readfile"},
        writefile = {"write", "writefile"},
        appendfile = {"append", "appendfile"},
        listfiles = {"listdir", "listfiles"},
        makefolder = {"makefolder", "mkdir"},
        isfile = {"isfile", "isFile"},
        isfolder = {"isfolder", "isFolder"},
        delfile = {"delfile", "delete", "remove"},
        delfolder = {"delfolder", "deletedir"},
    }

    local names = aliases[functionName] or {functionName}

    for _, environment in ipairs(getPulseCoreEnvironment()) do
        for _, name in ipairs(names) do
            local ok, candidate = pcall(function()
                return environment["syn_io_" .. name]
            end)

            if ok and type(candidate) == "function" then
                return candidate
            end
        end

        local okSyn, synTable = pcall(function()
            return environment.syn
        end)

        if okSyn and type(synTable) == "table" and type(synTable.io) == "table" then
            for _, name in ipairs(names) do
                local candidate = synTable.io[name]
                if type(candidate) == "function" then
                    return candidate
                end
            end
        end
    end

    return nil
end

function getPulseCoreCustomAsset(filePath)
    if type(filePath) ~= "string" or filePath == "" then
        return nil
    end

    local resolvers = {
        function()
            return getcustomasset
        end,
        function()
            return getsynasset
        end,
        function()
            return getasset
        end,
    }

    for _, getResolver in ipairs(resolvers) do
        local okResolver, resolver = pcall(getResolver)

        if okResolver and type(resolver) == "function" then
            local ok, asset = pcall(resolver, filePath)
            if ok and type(asset) == "string" and asset ~= "" then
                return asset
            end
        end
    end

    return nil
end

function getPulseCoreMissingFileApis()
    local required = {"makefolder", "writefile", "readfile"}
    local missing = {}

    for _, functionName in ipairs(required) do
        if not getPulseCoreFileApi(functionName) then
            table.insert(missing, functionName)
        end
    end

    return missing
end

function getPulseCoreLocalAppData()
    local getenv = rawget(os, "getenv")

    if type(getenv) == "function" then
        local ok, localAppData = pcall(getenv, "LOCALAPPDATA")

        if ok and type(localAppData) == "string" and localAppData ~= "" then
            return localAppData, false
        end

        local okUser, userProfile = pcall(getenv, "USERPROFILE")

        if okUser and type(userProfile) == "string" and userProfile ~= "" then
            return userProfile .. "\\AppData\\Local", false
        end
    end



    return "PulseCore\\Configs", true
end

function initializePulseCoreConfigPath()
    local directRealSignals = false

    pcall(function()
        directRealSignals = type(readfile) == "function"
            and type(writefile) == "function"
            and type(makefolder) == "function"
    end)

    local missing = getPulseCoreMissingFileApis()
    if #missing > 0 then
        return false, "Missing file API: " .. table.concat(missing, ", ")
    end

    if not CONFIG_ROOT_PATH then
        local executorName = string.lower(getPulseCoreExecutorName())

        if executorName == "real" or directRealSignals then
            CONFIG_ROOT_PATH = "PulseCore/Configs"
            CONFIG_PATH_FALLBACK = true
        else
            local localAppData = getPulseCoreLocalAppData()

            if localAppData then
                CONFIG_ROOT_PATH = localAppData
                    .. "\\" .. getPulseCoreExecutorName()
                    .. "\\workspace\\PulseCore\\Configs"
                CONFIG_PATH_FALLBACK = false
            else
                CONFIG_ROOT_PATH = "PulseCore/Configs"
                CONFIG_PATH_FALLBACK = true
            end
        end

        CONFIG_AUTOLOAD_FILE = CONFIG_ROOT_PATH .. "\\AutoLoad.txt"
        CONFIG_INDEX_FILE = CONFIG_ROOT_PATH .. "\\ConfigIndex.json"
    end

    local makeFolderApi = getPulseCoreFileApi("makefolder")
    local isFolderApi = getPulseCoreFileApi("isfolder")

    if not makeFolderApi then
        return false, "Missing file API: makefolder"
    end




    local created, createError = pcall(function()
        makeFolderApi(CONFIG_ROOT_PATH)
    end)

    if not created then
        return false, "Config folder could not be created: " .. tostring(createError)
    end

    if isFolderApi then
        local verified = false
        pcall(function()
            verified = isFolderApi(CONFIG_ROOT_PATH)
        end)

        if not verified then
            return false, "The executor rejected the Configs folder path."
        end
    end

    return true, nil
end

function getPulseCoreConfigFilePath(configName)
    if not CONFIG_ROOT_PATH or not configName then
        return nil
    end

    return CONFIG_ROOT_PATH .. "\\" .. configName .. CONFIG_FILE_EXTENSION
end

function isReservedWindowsConfigName(name)
    local upper = string.upper(name):gsub("%.[^%.]*$", "")
    return upper == "CON"
        or upper == "PRN"
        or upper == "AUX"
        or upper == "NUL"
        or upper:match("^COM[1-9]$")
        or upper:match("^LPT[1-9]$")
end

function getPulseCoreConfigFilePath(configName)
    if not CONFIG_ROOT_PATH or not configName then
        return nil
    end

    return CONFIG_ROOT_PATH .. "\\" .. configName .. CONFIG_FILE_EXTENSION
end

function isReservedWindowsConfigName(name)
    local upper = string.upper(name):gsub("%.[^%.]*$", "")
    return upper == "CON"
        or upper == "PRN"
        or upper == "AUX"
        or upper == "NUL"
        or upper:match("^COM[1-9]$")
        or upper:match("^LPT[1-9]$")
end

function getPulseCoreConfigFilePath(configName)
    if not CONFIG_ROOT_PATH or not configName then
        return nil
    end

    return CONFIG_ROOT_PATH .. "\\" .. configName .. CONFIG_FILE_EXTENSION
end

function isReservedWindowsConfigName(name)
    local upper = string.upper(name):gsub("%.[^%.]*$", "")
    return upper == "CON"
        or upper == "PRN"
        or upper == "AUX"
        or upper == "NUL"
        or upper:match("^COM[1-9]$")
        or upper:match("^LPT[1-9]$")
end


ESP_HIGHLIGHT_NAME = "SpeedBoostVisualESP"


EXECUTIONER_NAMES = {
    ["2011x"] = true,
    ["kolossos"] = true,
    ["tripwire"] = true,
    ["fleetway"] = true,
}

SURVIVOR_NAMES = {
    ["sonic"] = true,
    ["tails"] = true,
    ["knuckles"] = true,
    ["eggman"] = true,
    ["amy"] = true,
    ["cream"] = true,
    ["blaze"] = true,
    ["silver"] = true,
    ["metalsonic"] = true,
}

COLORS = {

    Cyan = Color3.fromRGB(210, 210, 210),
    CyanDark = Color3.fromRGB(68, 68, 68),
    CyanDeep = Color3.fromRGB(18, 18, 18),
    Panel = Color3.fromRGB(10, 10, 10),
    Card = Color3.fromRGB(22, 22, 22),
    Input = Color3.fromRGB(15, 15, 15),
    Border = Color3.fromRGB(70, 70, 70),
    Sidebar = Color3.fromRGB(14, 14, 14),
    Topbar = Color3.fromRGB(12, 12, 12),
    Text = Color3.fromRGB(242, 242, 242),
    MutedText = Color3.fromRGB(165, 165, 165),
    Green = Color3.fromRGB(110, 220, 145),
    Red = Color3.fromRGB(235, 95, 105),
    ESPBlue = Color3.fromRGB(70, 130, 255),
    ESPRed = Color3.fromRGB(255, 35, 55),
    Yellow = Color3.fromRGB(225, 195, 100),
    White = Color3.fromRGB(255, 255, 255),
}

oldGui = playerGui:FindFirstChild("AssemblySpeedBoostUI")
if oldGui then
    oldGui:Destroy()
end

oldConsoleGui = playerGui:FindFirstChild("PulseCoreLiveConsoleUI")
if oldConsoleGui then
    oldConsoleGui:Destroy()
end

oldESPInfoGui = playerGui:FindFirstChild("PulseCoreESPInfoUI")
if oldESPInfoGui then
    oldESPInfoGui:Destroy()
end

function create(className, properties, parent)
    local object = Instance.new(className)

    for property, value in pairs(properties or {}) do
        object[property] = value
    end

    object.Parent = parent
    return object
end

function addCorner(parent, radius)
    return create("UICorner", {
        CornerRadius = UDim.new(0, radius),
    }, parent)
end

function addStroke(parent, color, transparency, thickness)
    return create("UIStroke", {
        Color = color,
        Transparency = transparency or 0,
        Thickness = thickness or 1,
        ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
    }, parent)
end

liveConsoleState = {
    gui = nil,
    frame = nil,
    scroll = nil,
    layout = nil,
    searchBox = nil,
    countLabel = nil,
    autoButton = nil,
    clearButton = nil,
    filterButtons = {},
    records = {},
    pendingLogs = {},
    connections = {},
    logConnection = nil,
    autoscroll = true,
    searchText = "",
    filters = {
        MessageOutput = true,
        MessageInfo = true,
        MessageWarning = true,
        MessageError = true,
    },
}

function disconnectLiveConsoleConnection(connection)
    if connection then
        pcall(function()
            connection:Disconnect()
        end)
    end
end

function keepLiveConsoleConnection(connection)
    if connection then
        table.insert(liveConsoleState.connections, connection)
    end
    return connection
end

function getConsoleTypeName(messageType)
    if messageType and messageType.Name then
        return messageType.Name
    end
    return "MessageOutput"
end

function getConsoleTypeLabel(typeName)
    if typeName == "MessageError" then
        return "ERROR"
    elseif typeName == "MessageWarning" then
        return "WARN"
    elseif typeName == "MessageInfo" then
        return "INFO"
    end
    return "DEBUG"
end

function getConsoleTypeColor(typeName)
    if typeName == "MessageError" then
        return COLORS.Red
    elseif typeName == "MessageWarning" then
        return COLORS.Yellow
    elseif typeName == "MessageInfo" then
        return COLORS.Cyan
    end
    return COLORS.Text
end

function updateLiveConsoleFilterButtons()
    local map = {
        Output = "MessageOutput",
        Info = "MessageInfo",
        Warning = "MessageWarning",
        Error = "MessageError",
    }

    for buttonName, typeName in pairs(map) do
        local button = liveConsoleState.filterButtons[buttonName]
        if button and button.Parent then
            local enabled = liveConsoleState.filters[typeName] == true
            button.BackgroundColor3 = enabled and COLORS.CyanDark or COLORS.Input
            button.TextColor3 = enabled and COLORS.Text or COLORS.MutedText
        end
    end
end

function refreshLiveConsoleCanvas(forceBottom)
    task.defer(function()
        local scroll = liveConsoleState.scroll
        local layout = liveConsoleState.layout

        if not scroll or not scroll.Parent or not layout then
            return
        end

        scroll.CanvasSize = UDim2.fromOffset(0, layout.AbsoluteContentSize.Y + 18)

        if forceBottom or liveConsoleState.autoscroll then
            scroll.CanvasPosition = Vector2.new(
                0,
                math.max(
                    0,
                    layout.AbsoluteContentSize.Y - scroll.AbsoluteWindowSize.Y + 18
                )
            )
        end
    end)
end

function updateLiveConsoleCount()
    if not liveConsoleState.countLabel or not liveConsoleState.countLabel.Parent then
        return
    end

    local visibleCount = 0
    for _, record in ipairs(liveConsoleState.records) do
        if record.label and record.label.Parent and record.label.Visible then
            visibleCount = visibleCount + 1
        end
    end

    liveConsoleState.countLabel.Text = string.format(
        "%d / %d",
        visibleCount,
        #liveConsoleState.records
    )
end

function refreshLiveConsoleFilters()
    local searchText = string.lower(liveConsoleState.searchText or "")

    for _, record in ipairs(liveConsoleState.records) do
        local label = record.label

        if label and label.Parent then
            local typeAllowed = liveConsoleState.filters[record.typeName] ~= false
            local textAllowed = searchText == ""
                or string.find(record.searchText, searchText, 1, true) ~= nil

            label.Visible = typeAllowed and textAllowed
        end
    end

    updateLiveConsoleFilterButtons()
    updateLiveConsoleCount()
    refreshLiveConsoleCanvas(false)
end

function clearLiveConsole()
    for _, record in ipairs(liveConsoleState.records) do
        if record.label and record.label.Parent then
            record.label:Destroy()
        end
    end

    table.clear(liveConsoleState.records)
    table.clear(liveConsoleState.pendingLogs)
    updateLiveConsoleCount()
    refreshLiveConsoleCanvas(false)
end

function appendLiveConsoleLog(message, messageType, timestampText)
    local scroll = liveConsoleState.scroll
    if not scroll or not scroll.Parent then
        return
    end

    local typeName = getConsoleTypeName(messageType)
    local typeLabel = getConsoleTypeLabel(typeName)
    local messageText = tostring(message or "")
    local timeText = timestampText or os.date("%H:%M:%S")

    local fullText = string.format(
        "[%s] [%s] %s",
        timeText,
        typeLabel,
        messageText
    )

    local label = create("TextLabel", {
        Size = UDim2.new(1, -6, 0, 18),
        AutomaticSize = Enum.AutomaticSize.Y,
        BackgroundTransparency = 1,
        Text = fullText,
        Font = Enum.Font.Code,
        TextSize = 12,
        TextColor3 = getConsoleTypeColor(typeName),
        TextWrapped = true,
        TextXAlignment = Enum.TextXAlignment.Left,
        TextYAlignment = Enum.TextYAlignment.Top,
        RichText = false,
    }, scroll)

    table.insert(liveConsoleState.records, {
        label = label,
        typeName = typeName,
        searchText = string.lower(fullText),
    })

    if #liveConsoleState.records > 500 then
        local oldest = table.remove(liveConsoleState.records, 1)
        if oldest and oldest.label and oldest.label.Parent then
            oldest.label:Destroy()
        end
    end

    local searchText = string.lower(liveConsoleState.searchText or "")
    local typeAllowed = liveConsoleState.filters[typeName] ~= false
    local textAllowed = searchText == ""
        or string.find(string.lower(fullText), searchText, 1, true) ~= nil

    label.Visible = typeAllowed and textAllowed

    updateLiveConsoleCount()
    refreshLiveConsoleCanvas(false)
end

function isPulseCoreLogMessage(message)
    local text = tostring(message or "")
    if text == "" then
        return false
    end



    return string.find(text, "[PulseCore]", 1, true) ~= nil
        or string.find(text, "[Speed Boost]", 1, true) ~= nil
        or string.find(text, "PulseCore", 1, true) ~= nil
        or string.find(text, "AssemblySpeedBoostUI", 1, true) ~= nil
end

function getPulseCoreLogTypeFromColor(color)
    if color == COLORS.Red then
        return Enum.MessageType.MessageError
    elseif color == COLORS.Yellow then
        return Enum.MessageType.MessageWarning
    end
    return Enum.MessageType.MessageInfo
end

function recordPulseCoreLog(message, messageType, timestampText)
    local messageText = tostring(message or "")
    if messageText == "" then
        return
    end

    local entry = {
        message = messageText,
        messageType = messageType or Enum.MessageType.MessageInfo,
        timestampText = timestampText or os.date("%H:%M:%S"),
    }

    table.insert(liveConsoleState.pendingLogs, entry)
    if #liveConsoleState.pendingLogs > 500 then
        table.remove(liveConsoleState.pendingLogs, 1)
    end

    if liveConsoleState.scroll and liveConsoleState.scroll.Parent then
        appendLiveConsoleLog(entry.message, entry.messageType, entry.timestampText)
    end
end

function logPulseCoreInfo(message)
    recordPulseCoreLog("[PulseCore] " .. tostring(message or ""), Enum.MessageType.MessageInfo)
end

function logPulseCoreWarning(message)
    recordPulseCoreLog("[PulseCore] " .. tostring(message or ""), Enum.MessageType.MessageWarning)
end

function logPulseCoreError(message)
    recordPulseCoreLog("[PulseCore] " .. tostring(message or ""), Enum.MessageType.MessageError)
end

function logPulseCoreStatus(message, color)
    recordPulseCoreLog("[PulseCore] " .. tostring(message or ""), getPulseCoreLogTypeFromColor(color))
end

function destroyLiveConsoleMode()
    disconnectLiveConsoleConnection(liveConsoleState.logConnection)
    liveConsoleState.logConnection = nil

    for _, connection in ipairs(liveConsoleState.connections) do
        disconnectLiveConsoleConnection(connection)
    end
    table.clear(liveConsoleState.connections)

    local gui = liveConsoleState.gui
    local frame = liveConsoleState.frame

    if gui and gui.Parent and frame and frame.Parent then
        local closeTween = TweenService:Create(
            frame,
            TweenInfo.new(0.20, Enum.EasingStyle.Quint, Enum.EasingDirection.In),
            {
                Position = UDim2.fromScale(0.5, 0.86),
                BackgroundTransparency = 1,
            }
        )
        closeTween:Play()

        task.spawn(function()
            closeTween.Completed:Wait()
            if gui and gui.Parent then
                gui:Destroy()
            end
        end)
    elseif gui and gui.Parent then
        gui:Destroy()
    end

    liveConsoleState.gui = nil
    liveConsoleState.frame = nil
    liveConsoleState.scroll = nil
    liveConsoleState.layout = nil
    liveConsoleState.searchBox = nil
    liveConsoleState.countLabel = nil
    liveConsoleState.autoButton = nil
    liveConsoleState.clearButton = nil
    liveConsoleState.filterButtons = {}
    liveConsoleState.records = {}
end

function runLiveConsoleMode()
    if liveConsoleState.gui and liveConsoleState.gui.Parent then
        liveConsoleState.gui.Enabled = true
        return
    end

    local consoleGui = create("ScreenGui", {
        Name = "PulseCoreLiveConsoleUI",
        ResetOnSpawn = false,
        IgnoreGuiInset = false,
        DisplayOrder = 1100,
        ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
    }, playerGui)

    liveConsoleState.gui = consoleGui

    local frame = create("Frame", {
        Name = "LiveConsole",
        AnchorPoint = Vector2.new(0.5, 0.5),
        Position = UDim2.fromScale(0.5, 0.80),
        Size = UDim2.fromOffset(820, 278),
        BackgroundColor3 = COLORS.Panel,
        BackgroundTransparency = 0.06,
        BorderSizePixel = 0,
        ClipsDescendants = true,
        Active = true,
    }, consoleGui)

    liveConsoleState.frame = frame
    frame.Position = UDim2.fromScale(0.5, 0.86)
    frame.BackgroundTransparency = 1

    addCorner(frame, 12)
    addStroke(frame, COLORS.Border, 0.20, 1.2)

    create("UIGradient", {
        Rotation = 25,
        Color = ColorSequence.new({
            ColorSequenceKeypoint.new(0, Color3.fromRGB(24, 24, 24)),
            ColorSequenceKeypoint.new(0.45, Color3.fromRGB(14, 14, 14)),
            ColorSequenceKeypoint.new(1, Color3.fromRGB(7, 7, 7)),
        }),
    }, frame)

    local topBar = create("Frame", {
        Name = "TopBar",
        Size = UDim2.new(1, 0, 0, 38),
        BackgroundColor3 = COLORS.Topbar,
        BackgroundTransparency = 0.04,
        BorderSizePixel = 0,
        Active = true,
        ZIndex = 4,
    }, frame)

    create("TextLabel", {
        Position = UDim2.fromOffset(13, 0),
        Size = UDim2.new(0, 240, 1, 0),
        BackgroundTransparency = 1,
        Text = "PULSECORE LIVE CONSOLE",
        Font = Enum.Font.GothamBold,
        TextSize = 13,
        TextColor3 = COLORS.Text,
        TextXAlignment = Enum.TextXAlignment.Left,
        ZIndex = 5,
    }, topBar)

    liveConsoleState.countLabel = create("TextLabel", {
        Position = UDim2.fromOffset(250, 0),
        Size = UDim2.fromOffset(80, 38),
        BackgroundTransparency = 1,
        Text = "0 / 0",
        Font = Enum.Font.Code,
        TextSize = 11,
        TextColor3 = COLORS.MutedText,
        TextXAlignment = Enum.TextXAlignment.Left,
        ZIndex = 5,
    }, topBar)

    local hideButton = create("TextButton", {
        AnchorPoint = Vector2.new(1, 0.5),
        Position = UDim2.new(1, -10, 0.5, 0),
        Size = UDim2.fromOffset(32, 28),
        BackgroundColor3 = COLORS.Input,
        BorderSizePixel = 0,
        Text = "X",
        Font = Enum.Font.GothamBold,
        TextSize = 12,
        TextColor3 = COLORS.MutedText,
        AutoButtonColor = true,
        ZIndex = 5,
    }, topBar)
    addCorner(hideButton, 7)
    addStroke(hideButton, COLORS.Border, 0.35, 1)

    local toolbar = create("Frame", {
        Position = UDim2.fromOffset(8, 42),
        Size = UDim2.new(1, -16, 0, 34),
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
    }, frame)

    local function createFilterButton(name, textValue, x, width)
        local button = create("TextButton", {
            Position = UDim2.fromOffset(x, 0),
            Size = UDim2.fromOffset(width, 30),
            BackgroundColor3 = COLORS.CyanDark,
            BorderSizePixel = 0,
            Text = textValue,
            Font = Enum.Font.GothamBold,
            TextSize = 10,
            TextColor3 = COLORS.Text,
            AutoButtonColor = false,
        }, toolbar)
        addCorner(button, 7)
        addStroke(button, COLORS.Border, 0.40, 1)
        liveConsoleState.filterButtons[name] = button
        return button
    end

    local outputButton = createFilterButton("Output", "DEBUG", 0, 66)
    local infoButton = createFilterButton("Info", "INFO", 72, 54)
    local warningButton = createFilterButton("Warning", "WARN", 132, 58)
    local errorButton = createFilterButton("Error", "ERROR", 196, 60)

    liveConsoleState.clearButton = create("TextButton", {
        Position = UDim2.fromOffset(262, 0),
        Size = UDim2.fromOffset(58, 30),
        BackgroundColor3 = COLORS.Input,
        BorderSizePixel = 0,
        Text = "CLEAR",
        Font = Enum.Font.GothamBold,
        TextSize = 10,
        TextColor3 = COLORS.Text,
    }, toolbar)
    addCorner(liveConsoleState.clearButton, 7)
    addStroke(liveConsoleState.clearButton, COLORS.Border, 0.40, 1)

    liveConsoleState.autoButton = create("TextButton", {
        Position = UDim2.fromOffset(326, 0),
        Size = UDim2.fromOffset(72, 30),
        BackgroundColor3 = COLORS.CyanDark,
        BorderSizePixel = 0,
        Text = "AUTO: ON",
        Font = Enum.Font.GothamBold,
        TextSize = 10,
        TextColor3 = COLORS.Text,
        AutoButtonColor = false,
