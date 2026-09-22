SCRIPT_VERSION = "2026.09.21"

Players = game:GetService("Players")
RunService = game:GetService("RunService")
TweenService = game:GetService("TweenService")
UserInputService = game:GetService("UserInputService")
HttpService = game:GetService("HttpService")
LogService = game:GetService("LogService")
TextChatService = game:GetService("TextChatService")

localPlayer = Players.LocalPlayer
playerGui = localPlayer:WaitForChild("PlayerGui")

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


CONFIG_ROOT_PATH = nil
CONFIG_AUTOLOAD_FILE = nil
CONFIG_INDEX_FILE = nil
CONFIG_FILE_EXTENSION = ".json"
CONFIG_PATH_FALLBACK = false

-- Only these player nicknames receive the Fun and Combat tabs.
-- Add approved Roblox usernames/display names here.
SPECIAL_TAB_NICKNAMES = {
    "CommunityGame125",
}

function normalizeSpecialTabNickname(value)
    return string.lower(tostring(value or "")):gsub("[%s_%-%.]", "")
end

function isSpecialTabsAllowed()
    local allowed = {}

    -- Accept both list syntax:
    -- { "Nickname" }
    -- and dictionary syntax:
    -- { ["Nickname"] = true } / { Nickname = true }
    for key, nickname in pairs(SPECIAL_TAB_NICKNAMES) do
        local value = nil

        if type(key) == "number" then
            value = nickname
        elseif nickname == true or nickname == 1 then
            value = key
        elseif type(nickname) == "string" then
            value = nickname
        end

        if type(value) == "string" and value ~= "" then
            allowed[normalizeSpecialTabNickname(value)] = true
        end
    end

    local candidates = {
        localPlayer.Name,
        localPlayer.DisplayName,
    }

    local character = localPlayer.Character
    if character then
        table.insert(candidates, character.Name)

        local attributeNames = {
            "Nickname",
            "PlayerName",
            "Username",
            "DisplayName",
            "Character",
        }

        for _, attributeName in ipairs(attributeNames) do
            local attributeValue = character:GetAttribute(attributeName)

            if type(attributeValue) == "string" and attributeValue ~= "" then
                table.insert(candidates, attributeValue)
            end
        end
    end

    for _, candidate in ipairs(candidates) do
        local normalizedCandidate = normalizeSpecialTabNickname(candidate)

        if normalizedCandidate ~= "" and allowed[normalizedCandidate] then
            return true
        end
    end

    return false
end

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
    -- First try direct global references. Real exposes its filesystem API
    -- as normal globals, and this avoids executor-specific environment quirks.
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

    -- Some executors sandbox their filesystem to their own workspace and
    -- do not expose Windows environment variables to Luau.
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

    -- Real resolves all filesystem paths relative to its workspace.
    -- Its makefolder implementation is recursive, so creating the final path
    -- is sufficient and also creates missing parent directories.
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

-- Имена нормализуются: пробелы, дефисы и подчёркивания не учитываются.
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
    -- Black / graphite interface palette.
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

    -- Only accept messages explicitly associated with PulseCore / its features.
    -- This intentionally rejects unrelated game Output, Info, Warning and Error messages.
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
    }, toolbar)
    addCorner(liveConsoleState.autoButton, 7)
    addStroke(liveConsoleState.autoButton, COLORS.Border, 0.40, 1)

    liveConsoleState.searchBox = create("TextBox", {
        Position = UDim2.new(0, 406, 0, 0),
        Size = UDim2.new(1, -406, 0, 30),
        BackgroundColor3 = COLORS.Input,
        BorderSizePixel = 0,
        ClearTextOnFocus = false,
        PlaceholderText = "Search PulseCore logs...",
        PlaceholderColor3 = COLORS.MutedText,
        Text = "",
        Font = Enum.Font.Code,
        TextSize = 11,
        TextColor3 = COLORS.Text,
        TextXAlignment = Enum.TextXAlignment.Left,
    }, toolbar)
    addCorner(liveConsoleState.searchBox, 7)
    addStroke(liveConsoleState.searchBox, COLORS.Border, 0.40, 1)
    create("UIPadding", {
        PaddingLeft = UDim.new(0, 10),
        PaddingRight = UDim.new(0, 10),
    }, liveConsoleState.searchBox)

    local consoleScroll = create("ScrollingFrame", {
        Position = UDim2.fromOffset(8, 80),
        Size = UDim2.new(1, -16, 1, -88),
        BackgroundColor3 = COLORS.Input,
        BackgroundTransparency = 0.18,
        BorderSizePixel = 0,
        CanvasSize = UDim2.fromOffset(0, 0),
        ScrollBarThickness = 5,
        ScrollBarImageColor3 = COLORS.Cyan,
        ScrollBarImageTransparency = 0.15,
        ScrollingDirection = Enum.ScrollingDirection.Y,
        Active = true,
        ClipsDescendants = true,
    }, frame)

    liveConsoleState.scroll = consoleScroll
    addCorner(consoleScroll, 9)
    addStroke(consoleScroll, COLORS.Border, 0.45, 1)

    create("UIPadding", {
        PaddingTop = UDim.new(0, 8),
        PaddingBottom = UDim.new(0, 8),
        PaddingLeft = UDim.new(0, 10),
        PaddingRight = UDim.new(0, 10),
    }, consoleScroll)

    local consoleLayout = create("UIListLayout", {
        FillDirection = Enum.FillDirection.Vertical,
        HorizontalAlignment = Enum.HorizontalAlignment.Left,
        SortOrder = Enum.SortOrder.LayoutOrder,
        Padding = UDim.new(0, 3),
    }, consoleScroll)

    liveConsoleState.layout = consoleLayout

    local dragging = false
    local dragStart = nil
    local frameStart = nil

    keepLiveConsoleConnection(topBar.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 then
            dragging = true
            dragStart = input.Position
            frameStart = frame.Position
        end
    end))

    keepLiveConsoleConnection(UserInputService.InputChanged:Connect(function(input)
        if dragging and input.UserInputType == Enum.UserInputType.MouseMovement then
            local delta = input.Position - dragStart
            frame.Position = UDim2.new(
                frameStart.X.Scale,
                frameStart.X.Offset + delta.X,
                frameStart.Y.Scale,
                frameStart.Y.Offset + delta.Y
            )
        end
    end))

    keepLiveConsoleConnection(UserInputService.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 then
            dragging = false
        end
    end))

    local filterMap = {
        { outputButton, "MessageOutput" },
        { infoButton, "MessageInfo" },
        { warningButton, "MessageWarning" },
        { errorButton, "MessageError" },
    }

    for _, entry in ipairs(filterMap) do
        local button = entry[1]
        local typeName = entry[2]

        keepLiveConsoleConnection(button.Activated:Connect(function()
            liveConsoleState.filters[typeName] = not liveConsoleState.filters[typeName]
            refreshLiveConsoleFilters()
        end))
    end

    keepLiveConsoleConnection(liveConsoleState.clearButton.Activated:Connect(function()
        clearLiveConsole()
    end))

    keepLiveConsoleConnection(liveConsoleState.autoButton.Activated:Connect(function()
        liveConsoleState.autoscroll = not liveConsoleState.autoscroll
        liveConsoleState.autoButton.Text = liveConsoleState.autoscroll and "AUTO: ON" or "AUTO: OFF"
        liveConsoleState.autoButton.BackgroundColor3 =
            liveConsoleState.autoscroll and COLORS.CyanDark or COLORS.Input

        if liveConsoleState.autoscroll then
            refreshLiveConsoleCanvas(true)
        end
    end))

    keepLiveConsoleConnection(liveConsoleState.searchBox:GetPropertyChangedSignal("Text"):Connect(function()
        liveConsoleState.searchText = string.lower(liveConsoleState.searchBox.Text or "")
        refreshLiveConsoleFilters()
    end))

    keepLiveConsoleConnection(consoleLayout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
        refreshLiveConsoleCanvas(false)
    end))

    keepLiveConsoleConnection(hideButton.Activated:Connect(function()
        localPlayer:SetAttribute(CONSOLE_MODE_ATTRIBUTE_NAME, false)
    end))

    -- Never import the game's global LogHistory: the console is intended to show
    -- PulseCore-related diagnostics only. Re-display our own buffered records instead.
    local bufferedLogs = table.clone(liveConsoleState.pendingLogs)
    table.clear(liveConsoleState.records)

    for _, entry in ipairs(bufferedLogs) do
        if type(entry) == "table" then
            appendLiveConsoleLog(entry.message, entry.messageType, entry.timestampText)
        end
    end

    logPulseCoreInfo("Live Console attached. Filtering to PulseCore diagnostics only.")

    liveConsoleState.logConnection = LogService.MessageOut:Connect(function(message, messageType)
        if isPulseCoreLogMessage(message) then
            recordPulseCoreLog(message, messageType)
        end
    end)

    updateLiveConsoleFilterButtons()
    updateLiveConsoleCount()
    refreshLiveConsoleCanvas(true)

    local openTween = TweenService:Create(
        frame,
        TweenInfo.new(0.28, Enum.EasingStyle.Quint, Enum.EasingDirection.Out),
        {
            Position = UDim2.fromScale(0.5, 0.80),
            BackgroundTransparency = 0.06,
        }
    )
    openTween:Play()
end

screenGui = create("ScreenGui", {
    Name = "AssemblySpeedBoostUI",
    ResetOnSpawn = false,
    IgnoreGuiInset = false,
    DisplayOrder = 1000,
    ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
}, playerGui)

uiScale = create("UIScale", {
    Scale = 1,
}, screenGui)

expandedSize = UDim2.fromOffset(820, 640)
minimizedSize = UDim2.fromOffset(820, 56)

mainFrame = create("Frame", {
    Name = "MainFrame",
    AnchorPoint = Vector2.new(0.5, 0.5),
    Position = UDim2.fromScale(0.5, 0.39),
    Size = expandedSize,
    BackgroundColor3 = COLORS.Panel,
    BackgroundTransparency = 0.16,
    BorderSizePixel = 0,
    ClipsDescendants = true,
    Active = true,
    Visible = true,
}, screenGui)
addCorner(mainFrame, 14)
addStroke(mainFrame, COLORS.Border, 0.24, 1.35)

create("UIGradient", {
    Rotation = 35,
    Color = ColorSequence.new({
        ColorSequenceKeypoint.new(0, Color3.fromRGB(24, 24, 24)),
        ColorSequenceKeypoint.new(0.28, Color3.fromRGB(14, 14, 14)),
        ColorSequenceKeypoint.new(1, Color3.fromRGB(7, 7, 7)),
    }),
}, mainFrame)


-- Main interface starts immediately; no Key System is used.
topBar = create("Frame", {
    Name = "TopBar",
    Size = UDim2.new(1, 0, 0, 56),
    BackgroundColor3 = COLORS.Topbar,
    BackgroundTransparency = 0.13,
    BorderSizePixel = 0,
    Active = true,
    ZIndex = 5,
}, mainFrame)
addCorner(topBar, 14)

-- Заполняет нижнюю часть TopBar, оставляя округление только сверху.
create("Frame", {
    Name = "TopBarBottomFill",
    AnchorPoint = Vector2.new(0, 1),
    Position = UDim2.new(0, 0, 1, 0),
    Size = UDim2.new(1, 0, 0, 14),
    BackgroundColor3 = COLORS.Topbar,
    BackgroundTransparency = 0.13,
    BorderSizePixel = 0,
    ZIndex = 5,
}, topBar)

create("TextLabel", {
    Name = "Title",
    Position = UDim2.fromOffset(24, 0),
    Size = UDim2.new(1, -150, 1, 0),
    BackgroundTransparency = 1,
    Text = "✥  PULSECORE     " .. SCRIPT_VERSION,
    Font = Enum.Font.GothamBold,
    TextSize = 17,
    TextColor3 = COLORS.Cyan,
    TextXAlignment = Enum.TextXAlignment.Left,
    ZIndex = 6,
}, topBar)

minimizeButton = create("TextButton", {
    Name = "Minimize",
    AnchorPoint = Vector2.new(1, 0.5),
    Position = UDim2.new(1, -62, 0.5, 0),
    Size = UDim2.fromOffset(34, 34),
    BackgroundColor3 = COLORS.Topbar,
    BackgroundTransparency = 1,
    BorderSizePixel = 0,
    Text = "−",
    Font = Enum.Font.GothamBold,
    TextSize = 18,
    TextColor3 = COLORS.MutedText,
    AutoButtonColor = true,
    ZIndex = 7,
}, topBar)
addCorner(minimizeButton, 999)

closeButton = create("TextButton", {
    Name = "Close",
    AnchorPoint = Vector2.new(1, 0.5),
    Position = UDim2.new(1, -20, 0.5, 0),
    Size = UDim2.fromOffset(34, 34),
    BackgroundColor3 = COLORS.Topbar,
    BackgroundTransparency = 1,
    BorderSizePixel = 0,
    Text = "×",
    Font = Enum.Font.GothamBold,
    TextSize = 19,
    TextColor3 = COLORS.MutedText,
    AutoButtonColor = true,
    ZIndex = 7,
}, topBar)
addCorner(closeButton, 999)

bodyFrame = create("Frame", {
    Name = "Body",
    Position = UDim2.fromOffset(0, 56),
    Size = UDim2.new(1, 0, 1, -56),
    BackgroundTransparency = 1,
    ClipsDescendants = true,
}, mainFrame)

-- CanvasGroups let the whole interface and body fade without individually
-- tweening every label/button.
interfaceCanvasGroup = create("CanvasGroup", {
    Name = "InterfaceAnimationGroup",
    Position = UDim2.fromScale(0, 0),
    Size = UDim2.fromScale(1, 1),
    BackgroundTransparency = 1,
    BorderSizePixel = 0,
    GroupTransparency = 0,
    ClipsDescendants = true,
}, mainFrame)

topBar.Parent = interfaceCanvasGroup
bodyFrame.Parent = interfaceCanvasGroup

sidebar = create("Frame", {
    Name = "Sidebar",
    Position = UDim2.fromOffset(0, 0),
    Size = UDim2.new(0, 96, 1, 0),
    BackgroundColor3 = COLORS.Sidebar,
    BackgroundTransparency = 0.13,
    BorderSizePixel = 0,
    ClipsDescendants = true,
}, bodyFrame)
addCorner(sidebar, 14)

-- Preserve square internal edges while leaving only the outer lower-left corner rounded.
create("Frame", {
    Name = "SidebarTopFill",
    Position = UDim2.fromOffset(0, 0),
    Size = UDim2.new(1, 0, 0, 14),
    BackgroundColor3 = COLORS.Sidebar,
    BackgroundTransparency = 0.13,
    BorderSizePixel = 0,
    ZIndex = 1,
}, sidebar)

create("Frame", {
    Name = "SidebarRightFill",
    Position = UDim2.new(1, -14, 0, 0),
    Size = UDim2.new(0, 14, 1, 0),
    BackgroundColor3 = COLORS.Sidebar,
    BackgroundTransparency = 0.13,
    BorderSizePixel = 0,
    ZIndex = 1,
}, sidebar)

-- The sidebar uses one shared animated selection background and indicator.
function createTabButton(name, text, y)
    local button = create("TextButton", {
        Name = name,
        Position = UDim2.fromOffset(12, y),
        Size = UDim2.fromOffset(72, 46),
        BackgroundColor3 = Color3.fromRGB(77, 34, 108),
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        Text = text,
        Font = Enum.Font.GothamBold,
        TextSize = 11,
        TextColor3 = COLORS.MutedText,
        AutoButtonColor = false,
        Active = true,
        Selectable = true,
        ZIndex = 3,
    }, sidebar)
    addCorner(button, 9)
    return button
end

clientModules = {
    tabs = {},
    pages = {},
    autoSelect = {
        enabled = false,
        selectedCharacter = nil,
        connection = nil,
        selectionSerial = 0,
        characterButtons = {},
        characters = {
            { displayName = "Sonic", gameName = "Sonic" },
            { displayName = "Tails", gameName = "Tails" },
            { displayName = "Knuckles", gameName = "Knuckles" },
            { displayName = "Eggman", gameName = "Eggman" },
            { displayName = "Amy", gameName = "Amy" },
            { displayName = "Cream", gameName = "Cream" },
            { displayName = "Blaze", gameName = "Blaze" },
            { displayName = "Silver", gameName = "Silver" },
            { displayName = "Metal Sonic", gameName = "MetalSonic" },
        },
    },
    cooldown = {
        standard = {
            cooldownEnabled = false,
            cooldownUntil = 0,
            cooldownArmed = false,
            activeCooldownSeconds = 0,
            cooldownSerial = 0,
        },
    },
    boostTabs = {
        enabled = false,
        updateConnection = nil,
        updateAccumulator = 0,
    },
    combat = {
        autoAimEnabled = false,
        autoCounterEnabled = false,
        showTarget = true,
        aimPriority = "Weakest",
        aimSmoothness = 0.28,
        defenseKey = Enum.KeyCode.E,
        aimActiveUntil = 0,
        activeAttackTrack = nil,
        attackStopConnection = nil,
        renderBindName = "PulseCoreAutoAim",
        currentTarget = nil,
        currentTargetName = nil,
        currentCharacterName = nil,
        markerConnections = {},
        animationConnection = nil,
        characterConnection = nil,
        renderConnection = nil,
        scanConnection = nil,
        modelConnections = {},
        activeMarkers = {},
        serial = 0,
        lastCounterAt = 0,
    },
    fun = {
        spinEnabled = false,
        spinConnection = nil,
        spectateEnabled = false,
        spectateConnection = nil,
        originalCameraSubject = nil,
        characterLockValue = nil,
        originalCharacterLock = nil,
    },
    speedControl = {
        standardMethod = "WalkSpeed",
        standardMode = "Add",
        activeMethod = "WalkSpeed",
        activeMode = "Add",
        pendingMethod = nil,
        pendingMode = nil,
    },
    jumpBoost = {
        standardEnabled = false,
        activeBonus = 0,
        pendingBonus = nil,
        stateConnection = nil,
        humanoid = nil,
        rootPart = nil,
        lastJumpAt = 0,
    },
    animationLock = {
        humanoid = nil,
        animator = nil,
        renderConnection = nil,
        animationPlayedConnection = nil,
        tracks = setmetatable({}, { __mode = "k" }),
    },
    infFlight = {
        enabled = false,
        serial = 0,
        labelConnections = {},
        characterConnection = nil,
    },
    flight = {
        enabled = false,
        speed = DEFAULT_FLIGHT_SPEED,
        controlledHumanoid = nil,
        bodyVelocity = nil,
        bodyGyro = nil,
        renderConnection = nil,
        characterConnection = nil,
        diedConnection = nil,
        sliderDragging = false,
        sliderInputConnection = nil,
        savedPlatformStand = false,
        savedAutoRotate = true,
    },
    characterTools = {
        noclipEnabled = false,
        infinityJumpEnabled = false,

        -- Sharp Movement / Anti-Slide.
        sharpMovementEnabled = false,
        sharpMovementConnection = nil,

        noclipStates = setmetatable({}, { __mode = "k" }),
        noclipParts = {},
        noclipCharacter = nil,
        noclipConnection = nil,
        noclipDescendantConnection = nil,
        noclipCharacterConnection = nil,
        jumpConnection = nil,
    },
    inventoryOrder = {
        enabled = false,
        savedNames = {},
        characterConnection = nil,
        deathConnection = nil,
        backpackAddedConnection = nil,
        restoreSerial = 0,
        restoring = false,
    },
    console = {
        attributeConnection = nil,
    },
    camera = {
        defaultFov = workspace.CurrentCamera and workspace.CurrentCamera.FieldOfView or 70,
        defaultMaxZoom = localPlayer.CameraMaxZoomDistance,
        defaultMode = localPlayer.CameraMode,
        fov = workspace.CurrentCamera and workspace.CurrentCamera.FieldOfView or 70,
        maxZoom = localPlayer.CameraMaxZoomDistance,
        firstPerson = localPlayer.CameraMode == Enum.CameraMode.LockFirstPerson,
        applied = false,
    },
    performance = {
        modeEnabled = false,
        particlesDisabled = false,
        postEffectsDisabled = false,
        shadowsDisabled = false,
        particleCache = setmetatable({}, { __mode = "k" }),
        postEffectCache = setmetatable({}, { __mode = "k" }),
        descendantConnection = nil,
        shadowOriginal = nil,

        fpsLimiterEnabled = false,
        fpsLimit = 60,
        fpsMin = 15,
        fpsMax = 240,
        fpsOriginalCap = nil,
        fpsSliderDragging = false,
        fpsSliderInputConnection = nil,
    },
    hud = {
        showFps = false,
        showCoordinates = false,
        showSpeed = false,
        updateConnection = nil,
        updateAccumulator = 0,
        fpsAccumulator = 0,
        fpsFrames = 0,
        currentFps = 0,
    },
}

clientModules.tabs.info = createTabButton("InfoTab", "INFO", 14)
localTab = createTabButton("LocalTab", "LOCAL", 66)
visualsTab = createTabButton("VisualsTab", "VISUALS", 118)
clientModules.tabs.combat = createTabButton("CombatTab", "COMBAT", 170)
clientModules.tabs.fun = createTabButton("FunTab", "FUN", 222)
clientModules.tabs.performance = createTabButton("PerformanceTab", "PERFORMANCE", 274)
clientModules.tabs.autoSelect = createTabButton("AutoSelectTab", "AUTO", 326)
clientModules.tabs.keyList = createTabButton("KeyListTab", "KEY LIST", 378)
settingsTab = createTabButton("SettingsTab", "SETTINGS", 430)

clientModules.specialTabsAllowed = false

clientModules.tabAnimation = {
    currentName = nil,
    currentPage = nil,
    serial = 0,
    order = {
        Info = 1,
        Local = 2,
        Visuals = 3,
        Combat = 4,
        Fun = 5,
        Performance = 6,
        AutoSelect = 7,
        KeyList = 8,
        Settings = 9,
    },
}

clientModules.tabAnimation.selectionBackground = create("Frame", {
    Name = "AnimatedTabBackground",
    Position = clientModules.tabs.info.Position,
    Size = clientModules.tabs.info.Size,
    BackgroundColor3 = Color3.fromRGB(42, 42, 42),
    BackgroundTransparency = 0.24,
    BorderSizePixel = 0,
    ZIndex = 2,
}, sidebar)
addCorner(clientModules.tabAnimation.selectionBackground, 9)
addStroke(clientModules.tabAnimation.selectionBackground, COLORS.Cyan, 0.72, 1)

clientModules.tabAnimation.selectionBar = create("Frame", {
    Name = "AnimatedTabBar",
    AnchorPoint = Vector2.new(0, 0.5),
    Position = UDim2.fromOffset(0, clientModules.tabs.info.Position.Y.Offset + 27),
    Size = UDim2.fromOffset(3, 34),
    BackgroundColor3 = COLORS.Cyan,
    BackgroundTransparency = 0.04,
    BorderSizePixel = 0,
    ZIndex = 4,
}, sidebar)
addCorner(clientModules.tabAnimation.selectionBar, 999)

clientModules.sidebarCreator = create("TextLabel", {
    AnchorPoint = Vector2.new(0.5, 1),
    Position = UDim2.new(0.5, 0, 1, -4),
    Size = UDim2.new(1, -16, 0, 38),
    BackgroundTransparency = 1,
    Text = "PULSECORE\n" .. SCRIPT_VERSION,
    Font = Enum.Font.GothamMedium,
    TextSize = 10,
    TextColor3 = COLORS.MutedText,
    TextWrapped = true,
    TextXAlignment = Enum.TextXAlignment.Center,
    TextYAlignment = Enum.TextYAlignment.Center,
}, sidebar)

contentHost = create("Frame", {
    Name = "ContentHost",
    Position = UDim2.fromOffset(96, 0),
    Size = UDim2.new(1, -96, 1, 0),
    BackgroundTransparency = 1,
    ClipsDescendants = true,
}, bodyFrame)

bodyCanvasGroup = create("CanvasGroup", {
    Name = "BodyAnimationGroup",
    Position = UDim2.fromScale(0, 0),
    Size = UDim2.fromScale(1, 1),
    BackgroundTransparency = 1,
    BorderSizePixel = 0,
    GroupTransparency = 0,
    ClipsDescendants = true,
}, bodyFrame)

sidebar.Parent = bodyCanvasGroup
contentHost.Parent = bodyCanvasGroup

clientModules.header = {}
clientModules.header.frame = create("Frame", {
    Name = "PageHeader",
    Position = UDim2.fromOffset(0, 0),
    Size = UDim2.new(1, 0, 0, 64),
    BackgroundTransparency = 1,
    BorderSizePixel = 0,
}, contentHost)

clientModules.header.title = create("TextLabel", {
    Position = UDim2.fromOffset(24, 8),
    Size = UDim2.new(1, -64, 0, 30),
    BackgroundTransparency = 1,
    Text = "OVERVIEW",
    Font = Enum.Font.GothamBold,
    TextSize = 22,
    TextColor3 = COLORS.Text,
    TextXAlignment = Enum.TextXAlignment.Left,
}, clientModules.header.frame)

clientModules.header.subtitle = create("TextLabel", {
    Position = UDim2.fromOffset(24, 34),
    Size = UDim2.new(1, -64, 0, 18),
    BackgroundTransparency = 1,
    Text = "Creator, version and latest changes",
    Font = Enum.Font.GothamMedium,
    TextSize = 11,
    TextColor3 = COLORS.MutedText,
    TextXAlignment = Enum.TextXAlignment.Left,
}, clientModules.header.frame)

create("Frame", {
    Position = UDim2.new(0, 24, 1, -1),
    Size = UDim2.new(1, -48, 0, 1),
    BackgroundColor3 = COLORS.Border,
    BackgroundTransparency = 0.45,
    BorderSizePixel = 0,
}, clientModules.header.frame)

function createScrollingPage(name)
    local page = create("ScrollingFrame", {
        Name = name,
        Position = UDim2.fromOffset(0, 64),
        Size = UDim2.new(1, 0, 1, -64),
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        CanvasSize = UDim2.fromOffset(0, 0),
        ScrollBarThickness = 5,
        ScrollBarImageColor3 = COLORS.Cyan,
        ScrollBarImageTransparency = 0.25,
        ScrollingDirection = Enum.ScrollingDirection.Y,
        ScrollingEnabled = true,
        ElasticBehavior = Enum.ElasticBehavior.WhenScrollable,
        VerticalScrollBarPosition = Enum.VerticalScrollBarPosition.Right,
        Active = true,
        ClipsDescendants = true,
    }, contentHost)

    create("UIPadding", {
        PaddingTop = UDim.new(0, 22),
        PaddingBottom = UDim.new(0, 24),
        PaddingLeft = UDim.new(0, 22),
        PaddingRight = UDim.new(0, 22),
    }, page)

    local layout = create("UIListLayout", {
        FillDirection = Enum.FillDirection.Vertical,
        HorizontalAlignment = Enum.HorizontalAlignment.Left,
        SortOrder = Enum.SortOrder.LayoutOrder,
        Padding = UDim.new(0, 10),
    }, page)

    local function updateCanvas()
        page.CanvasSize = UDim2.fromOffset(0, layout.AbsoluteContentSize.Y + 46)
    end

    layout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(updateCanvas)
    task.defer(updateCanvas)

    return page
end

clientModules.pages.info = createScrollingPage("InfoPage")
localPage = createScrollingPage("LocalPage")
visualsPage = createScrollingPage("VisualsPage")
clientModules.pages.combat = createScrollingPage("CombatPage")
clientModules.pages.fun = createScrollingPage("FunPage")
clientModules.pages.camera = createScrollingPage("CameraPage")
-- Legacy pages stay hidden so old configs can be read without exposing removed tabs.
clientModules.pages.performance = createScrollingPage("PerformancePage")
clientModules.pages.hud = createScrollingPage("HudPage")
clientModules.pages.autoSelect = createScrollingPage("AutoSelectPage")
clientModules.pages.keyList = createScrollingPage("KeyListPage")
settingsPage = createScrollingPage("SettingsPage")
clientModules.pages.info.Visible = true
localPage.Visible = false
visualsPage.Visible = false
clientModules.pages.combat.Visible = false
clientModules.pages.fun.Visible = false
clientModules.pages.camera.Visible = false
clientModules.pages.performance.Visible = false
clientModules.pages.hud.Visible = false
clientModules.pages.autoSelect.Visible = false
clientModules.pages.keyList.Visible = false
settingsPage.Visible = false

function createSectionLabel(parent, text, layoutOrder)
    return create("TextLabel", {
        LayoutOrder = layoutOrder,
        Size = UDim2.new(1, 0, 0, 20),
        BackgroundTransparency = 1,
        Text = text,
        Font = Enum.Font.GothamBold,
        TextSize = 12,
        TextColor3 = COLORS.Cyan,
        TextXAlignment = Enum.TextXAlignment.Left,
    }, parent)
end

function createInputRow(parent, labelText, defaultText, placeholderText, layoutOrder)
    local row = create("Frame", {
        LayoutOrder = layoutOrder,
        Size = UDim2.new(1, 0, 0, 50),
        BackgroundColor3 = COLORS.Card,
        BackgroundTransparency = 0.16,
        BorderSizePixel = 0,
    }, parent)
    addCorner(row, 9)
    addStroke(row, COLORS.Border, 0.28, 1)

    create("TextLabel", {
        Position = UDim2.fromOffset(14, 0),
        Size = UDim2.new(1, -174, 1, 0),
        BackgroundTransparency = 1,
        Text = labelText,
        Font = Enum.Font.GothamMedium,
        TextSize = 13,
        TextColor3 = COLORS.Text,
        TextWrapped = true,
        TextXAlignment = Enum.TextXAlignment.Left,
    }, row)

    local textBox = create("TextBox", {
        AnchorPoint = Vector2.new(1, 0.5),
        Position = UDim2.new(1, -10, 0.5, 0),
        Size = UDim2.fromOffset(148, 34),
        BackgroundColor3 = COLORS.Input,
        BackgroundTransparency = 0,
        BorderSizePixel = 0,
        ClearTextOnFocus = false,
        Text = defaultText,
        PlaceholderText = placeholderText,
        PlaceholderColor3 = COLORS.MutedText,
        Font = Enum.Font.GothamMedium,
        TextSize = 14,
        TextColor3 = COLORS.Text,
        TextXAlignment = Enum.TextXAlignment.Center,
    }, row)
    addCorner(textBox, 7)
    addStroke(textBox, COLORS.Border, 0.22, 1)

    return textBox
end

function enforceIntegerTextBox(textBox, minimum, maximum)
    local editing = false

    local function sanitize()
        if editing or not textBox or not textBox.Parent then
            return
        end

        editing = true
        local digitsOnly = tostring(textBox.Text or ""):gsub("%D", "")

        if #digitsOnly > 3 then
            digitsOnly = digitsOnly:sub(1, 3)
        end

        if digitsOnly ~= "" then
            local value = tonumber(digitsOnly) or minimum
            value = math.clamp(value, minimum, maximum)
            digitsOnly = tostring(math.floor(value))
        end

        textBox.Text = digitsOnly
        editing = false
    end

    textBox:GetPropertyChangedSignal("Text"):Connect(sanitize)
    textBox.FocusLost:Connect(function()
        sanitize()
        if textBox.Text == "" then
            textBox.Text = tostring(minimum)
        end
    end)

    sanitize()
end

function createKeybindRow(parent, labelText, defaultText, layoutOrder)
    local row = create("Frame", {
        LayoutOrder = layoutOrder,
        Size = UDim2.new(1, 0, 0, 50),
        BackgroundColor3 = COLORS.Card,
        BackgroundTransparency = 0.16,
        BorderSizePixel = 0,
    }, parent)
    addCorner(row, 9)
    addStroke(row, COLORS.Border, 0.28, 1)

    create("TextLabel", {
        Position = UDim2.fromOffset(14, 0),
        Size = UDim2.new(1, -190, 1, 0),
        BackgroundTransparency = 1,
        Text = labelText,
        Font = Enum.Font.GothamMedium,
        TextSize = 13,
        TextColor3 = COLORS.Text,
        TextWrapped = true,
        TextXAlignment = Enum.TextXAlignment.Left,
    }, row)

    local button = create("TextButton", {
        AnchorPoint = Vector2.new(1, 0.5),
        Position = UDim2.new(1, -10, 0.5, 0),
        Size = UDim2.fromOffset(164, 34),
        BackgroundColor3 = COLORS.Input,
        BackgroundTransparency = 0,
        BorderSizePixel = 0,
        Text = defaultText,
        Font = Enum.Font.GothamBold,
        TextSize = 13,
        TextColor3 = COLORS.Text,
        AutoButtonColor = true,
    }, row)
    addCorner(button, 7)
    addStroke(button, COLORS.Border, 0.22, 1)

    return button
end

function createToggleRow(parent, labelText, layoutOrder)
    local row = create("Frame", {
        LayoutOrder = layoutOrder,
        Size = UDim2.new(1, 0, 0, 50),
        BackgroundColor3 = COLORS.Card,
        BackgroundTransparency = 0.16,
        BorderSizePixel = 0,
    }, parent)
    addCorner(row, 9)
    addStroke(row, COLORS.Border, 0.28, 1)

    create("TextLabel", {
        Position = UDim2.fromOffset(14, 0),
        Size = UDim2.new(1, -100, 1, 0),
        BackgroundTransparency = 1,
        Text = labelText,
        Font = Enum.Font.GothamMedium,
        TextSize = 13,
        TextColor3 = COLORS.Text,
        TextWrapped = true,
        TextXAlignment = Enum.TextXAlignment.Left,
    }, row)

    local button = create("TextButton", {
        AnchorPoint = Vector2.new(1, 0.5),
        Position = UDim2.new(1, -11, 0.5, 0),
        Size = UDim2.fromOffset(58, 30),
        BackgroundColor3 = COLORS.Input,
        BorderSizePixel = 0,
        Text = "",
        AutoButtonColor = false,
    }, row)
    addCorner(button, 999)

    local dot = create("Frame", {
        AnchorPoint = Vector2.new(0, 0.5),
        Position = UDim2.new(0, 5, 0.5, 0),
        Size = UDim2.fromOffset(22, 22),
        BackgroundColor3 = COLORS.MutedText,
        BorderSizePixel = 0,
        ZIndex = 2,
    }, button)
    addCorner(dot, 999)

    return button, dot
end

--==================================================
-- COMBAT
-- Built against the supplied save.rbxl character/animation layout.
--==================================================

function clientModules.combat.normalize(value)
    return string.lower(tostring(value or "")):gsub("[%s_%-%.]", "")
end

function clientModules.combat.attributeCharacter(model)
    if not model then
        return nil
    end

    local attributeNames = {
        "Character",
        "character",
        "CharacterName",
        "characterName",
        "SelectedCharacter",
        "selectedCharacter",
        "CurrentCharacter",
        "currentCharacter",
    }

    for _, attributeName in ipairs(attributeNames) do
        local value = model:GetAttribute(attributeName)
        if type(value) == "string" and value ~= "" then
            return value
        end
    end

    return nil
end

function clientModules.combat.animNames(model)
    local result = {}

    if not model then
        return result
    end

    local animate = model:FindFirstChild("Animate")
    local anims = animate and animate:FindFirstChild("Anims")

    if anims then
        for _, descendant in ipairs(anims:GetDescendants()) do
            if descendant:IsA("Animation") then
                result[clientModules.combat.normalize(descendant.Name)] = true
            end
        end
    end

    return result
end

function clientModules.combat.detectCharacter(model)
    if not model or not model:IsA("Model") then
        return nil
    end

    local attributeName = clientModules.combat.attributeCharacter(model)
    if attributeName then
        local normalized = clientModules.combat.normalize(attributeName)
        local aliases = {
            ["2011x"] = "2011x",
            ["2011X"] = "2011x",
            kolossos = "Kolossos",
            tripwire = "Tripwire",
            fleetway = "Fleetway",
            tails = "Tails",
            knuckles = "Knuckles",
            eggman = "Eggman",
            amy = "Amy",
            silver = "Silver",
            blaze = "Blaze",
        }

        for alias, canonical in pairs(aliases) do
            if normalized == clientModules.combat.normalize(alias) then
                return canonical
            end
        end
    end

    -- First use character-specific markers. This must happen before the
    -- generic ESP classifier because Fleetway/Tripwire can inherit Sonic's
    -- dodge/brake animation markers.
    local markerCharacters = {
        tripwire = "Tripwire",
        tailsdoll = "Tripwire",
        glorbwire = "Tripwire",
        deadglorbwire = "Tripwire",
        brighterday = "Tripwire",
        reachout = "Tripwire",
        fleetway = "Fleetway",
        chaosdash = "Fleetway",
        fatefuldrain = "Fleetway",
        lasersofdestrucation = "Fleetway",
        lasersofdestruction = "Fleetway",
        kolossos = "Kolossos",
        chargerun = "Kolossos",
        impalerun = "Kolossos",
        chargewarn = "Kolossos",
        killold = "Kolossos",
        block = "Kolossos",
        ["2011x"] = "2011x",
        rage = "2011x",
        ragemode = "2011x",
        godstrickery = "2011x",
        invis = "2011x",
        invisibility = "2011x",
        invisiblity = "2011x",
        tails = "Tails",
        canon = "Tails",
        strangledr = "Tails",
        amy = "Amy",
        hammer = "Amy",
        hammerthrow = "Amy",
        throwhold = "Amy",
        silver = "Silver",
        rockaim = "Silver",
        suspension = "Silver",
        blaze = "Blaze",
        solflame = "Blaze",
        burningjavelin = "Blaze",
        flamestart = "Blaze",
        flameloop = "Blaze",
        flameend = "Blaze",
        knuckles = "Knuckles",
        focus = "Knuckles",
        eggman = "Eggman",
        jetpack = "Eggman",
        energyshield = "Eggman",
    }

    for _, descendant in ipairs(model:GetDescendants()) do
        local normalized = clientModules.combat.normalize(descendant.Name)
        local characterName = markerCharacters[normalized]

        if characterName then
            return characterName
        end
    end

    -- Tripwire/TailsDoll has unique Glorbwire animation asset IDs in the rbxl.
    -- Check them before the generic Sonic fallback because Tripwire inherits
    -- Sonic Dodge/Brake animation names.
    local tripwireAnimationIds = {
        ["79953933012214"] = true,
        ["85598394392380"] = true,
        ["132547926723713"] = true,
        ["80215516605216"] = true,
    }

    for _, descendant in ipairs(model:GetDescendants()) do
        if descendant:IsA("Animation") then
            local animationId = tostring(descendant.AnimationId):match("%d+")
            if animationId and tripwireAnimationIds[animationId] then
                return "Tripwire"
            end
        end
    end

    -- The supplied rbxl has stable, character-specific animation templates.
    local names = clientModules.combat.animNames(model)

    if names.chargedash or names.missdash or names.grabhold or names.toss then
        return "Fleetway"
    end

    if names.chargerun or names.chargewarn or names.impalerun or names.killold or names.block then
        return "Kolossos"
    end

    if names.teleportattack then
        return "2011x"
    end

    if names.strangledr then
        return "Tails"
    end

    if names.throwhold then
        return "Amy"
    end

    if names.rockaim or names.minionrise then
        return "Silver"
    end

    if names.flamestart or names.flameloop or names.flameend then
        return "Blaze"
    end

    if names.focus then
        return "Knuckles"
    end

    if names.jetpack then
        return "Eggman"
    end

    -- Only after all character-specific evidence do we fall back to the
    -- general ESP classifier (which may see inherited Sonic markers).
    local group, displayName = getESPAbilityClassification(model)
    if displayName and displayName ~= "Unknown" then
        return displayName
    end

    if names.dodge1 or names.dodge2 or names.dodge3 or names.brake then
        return "Sonic"
    end

    return nil
end

function clientModules.combat.getRoot(model)
    if not model or not model.Parent then
        return nil
    end

    local root = model:FindFirstChild("HumanoidRootPart")
        or model.PrimaryPart
        or model:FindFirstChild("UpperTorso")
        or model:FindFirstChild("Torso")

    return root and root:IsA("BasePart") and root or nil
end

function clientModules.combat.getHealth(model)
    if not model then
        return nil
    end

    local humanoid = model:FindFirstChildOfClass("Humanoid")
    if humanoid then
        return humanoid.Health
    end

    local healthNames = {"Health", "HP", "CurrentHealth"}
    for _, name in ipairs(healthNames) do
        local value = model:FindFirstChild(name, true)
        if value and (value:IsA("NumberValue") or value:IsA("IntValue")) then
            return value.Value
        end
    end

    return nil
end

function clientModules.combat.getDistance(model)
    local localCharacter = localPlayer.Character
    local localRoot = clientModules.combat.getRoot(localCharacter)
    local root = clientModules.combat.getRoot(model)

    if not localRoot or not root then
        return math.huge
    end

    return (root.Position - localRoot.Position).Magnitude
end

function clientModules.combat.isAlive(model)
    local health = clientModules.combat.getHealth(model)
    if health ~= nil then
        return health > 0
    end

    local humanoid = model and model:FindFirstChildOfClass("Humanoid")
    return humanoid == nil or humanoid.Health > 0
end

function clientModules.combat.getPlayerModels()
    local result = {}
    local seen = {}

    local function addModel(model)
        if not model
            or not model:IsA("Model")
            or model == localPlayer.Character
            or seen[model]
            or not model:IsDescendantOf(workspace)
        then
            return
        end

        seen[model] = true
        table.insert(result, model)
    end

    local playersFolder = workspace:FindFirstChild("Players")
    if playersFolder then
        for _, child in ipairs(playersFolder:GetChildren()) do
            addModel(child)
        end
    end

    for _, player in ipairs(Players:GetPlayers()) do
        if player ~= localPlayer then
            addModel(player.Character)
        end
    end

    return result
end

function clientModules.combat.getTargetInfo(model)
    local group, displayName = getESPGroupForModel(model)
    local detectedName = clientModules.combat.detectCharacter(model)

    if detectedName then
        displayName = detectedName

        if detectedName == "2011x"
            or detectedName == "Kolossos"
            or detectedName == "Tripwire"
            or detectedName == "Fleetway"
        then
            group = "Executioner"
        else
            group = "Survivor"
        end
    end

    if not group then
        return nil
    end

    return {
        model = model,
        group = group,
        name = displayName or detectedName or model.Name,
        health = clientModules.combat.getHealth(model),
        distance = clientModules.combat.getDistance(model),
    }
end

function clientModules.combat.getCandidates()
    local localCharacter = localPlayer.Character
    local localName = clientModules.combat.detectCharacter(localCharacter)
    clientModules.combat.currentCharacterName = localName

    if not localName then
        return nil, {}
    end

    local localIsExecutioner =
        localName == "2011x"
        or localName == "Kolossos"
        or localName == "Tripwire"
        or localName == "Fleetway"

    local result = {}

    for _, model in ipairs(clientModules.combat.getPlayerModels()) do
        local info = clientModules.combat.getTargetInfo(model)

        if info and clientModules.combat.isAlive(model) then
            if localIsExecutioner then
                if info.group == "Survivor" then
                    table.insert(result, info)
                end
            elseif info.group == "Executioner"
                and (
                    info.name == "2011x"
                    or info.name == "Kolossos"
                    or info.name == "Tripwire"
                    or info.name == "Fleetway"
                )
            then
                table.insert(result, info)
            end
        end
    end

    return localName, result
end

function clientModules.combat.chooseTarget(candidates)
    if #candidates == 0 then
        return nil
    end

    local priority = clientModules.combat.aimPriority

    table.sort(candidates, function(a, b)
        if priority == "Strongest" then
            local ah = a.health or -math.huge
            local bh = b.health or -math.huge
            if ah ~= bh then
                return ah > bh
            end
        elseif priority == "Weakest" then
            local ah = a.health or math.huge
            local bh = b.health or math.huge
            if ah ~= bh then
                return ah < bh
            end
        end

        return a.distance < b.distance
    end)

    return candidates[1]
end

function clientModules.combat.refreshTarget()
    local _, candidates = clientModules.combat.getCandidates()
    local target = clientModules.combat.chooseTarget(candidates)

    clientModules.combat.currentTarget = target and target.model or nil
    clientModules.combat.currentTargetName = target and target.name or nil

    if clientModules.combat.targetLabel then
        if target then
            local hpText = target.health ~= nil and string.format(" • %.0f HP", target.health) or ""
            local distanceText = target.distance < math.huge
                and string.format(" • %.1f studs", target.distance)
                or ""
            clientModules.combat.targetLabel.Text =
                "Current target: " .. tostring(target.name) .. hpText .. distanceText
            clientModules.combat.targetLabel.TextColor3 = COLORS.Green
        else
            clientModules.combat.targetLabel.Text = "Current target: none"
            clientModules.combat.targetLabel.TextColor3 = COLORS.MutedText
        end
    end

    return target
end

function clientModules.combat.setPriority(priority)
    local priorities = {
        Weakest = true,
        Strongest = true,
        Nearest = true,
    }

    if priorities[priority] then
        clientModules.combat.aimPriority = priority
    end

    if clientModules.combat.priorityButtons then
        for name, button in pairs(clientModules.combat.priorityButtons) do
            local active = name == clientModules.combat.aimPriority
            button.BackgroundColor3 = active and COLORS.Cyan or COLORS.Input
            button.TextColor3 = active and COLORS.CyanDeep or COLORS.Text
        end
    end

    if clientModules.combat.priorityLabel then
        clientModules.combat.priorityLabel.Text =
            "Target priority: " .. clientModules.combat.aimPriority
    end
end

function clientModules.combat.updateVisuals()
    setSwitchVisual(
        clientModules.combat.autoAimButton,
        clientModules.combat.autoAimDot,
        clientModules.combat.autoAimEnabled
    )

    setSwitchVisual(
        clientModules.combat.autoCounterButton,
        clientModules.combat.autoCounterDot,
        clientModules.combat.autoCounterEnabled
    )

    setSwitchVisual(
        clientModules.combat.showTargetButton,
        clientModules.combat.showTargetDot,
        clientModules.combat.showTarget
    )

    clientModules.combat.setPriority(clientModules.combat.aimPriority)

    if clientModules.combat.aimSmoothnessBox
        and clientModules.combat.aimSmoothnessBox.Text == "" then
        clientModules.combat.aimSmoothnessBox.Text = tostring(clientModules.combat.aimSmoothness)
    end
end

function clientModules.combat.clearConnections()
    for _, connection in ipairs(clientModules.combat.markerConnections) do
        if connection then
            connection:Disconnect()
        end
    end
    clientModules.combat.markerConnections = {}

    if clientModules.combat.animationConnection then
        clientModules.combat.animationConnection:Disconnect()
        clientModules.combat.animationConnection = nil
    end

end

function clientModules.combat.refreshCharacterHooks()
    clientModules.combat.clearConnections()
    table.clear(clientModules.combat.activeMarkers)

    local character = localPlayer.Character
    if not character then
        return
    end

    local function checkMarker(instance)
        if not instance or not instance.Parent then
            return
        end

        local normalized = clientModules.combat.normalize(instance.Name)

        local allowed = {
            brighterday = true,
            reachout = true,
            lasersofdestrucation = true,
            lasersofdestruction = true,
            canon = true,
            lasercanon = true,
            lasercannon = true,
            hammer = true,
            hammerthrow = true,
            suspension = true,
            solflame = true,
            burningjavelin = true,
        }

        if allowed[normalized] and not instance:IsA("Animation") and not instance:IsA("Sound") then
            clientModules.combat.activeMarkers[instance] = true
            clientModules.combat.aimActiveUntil = time() + 0.12
        end
    end

    for _, descendant in ipairs(character:GetDescendants()) do
        checkMarker(descendant)
    end

    table.insert(clientModules.combat.markerConnections,
        character.DescendantAdded:Connect(checkMarker)
    )

    table.insert(clientModules.combat.markerConnections,
        character.DescendantRemoving:Connect(function(instance)
            clientModules.combat.activeMarkers[instance] = nil
        end)
    )

    local humanoid = character:FindFirstChildOfClass("Humanoid")
    if humanoid then
        clientModules.combat.animationConnection =
            humanoid.AnimationPlayed:Connect(function(track)
                if not clientModules.combat.autoAimEnabled then
                    return
                end

                local animation = track and track.Animation
                local animationName = animation and clientModules.combat.normalize(animation.Name)

                local allowed = {
                    charge = true,
                    brighterday = true,
                    reachout = true,
                    lasersofdestrucation = true,
                    lasersofdestruction = true,
                    chargedash = true,
                    missdash = true,
                    canon = true,
                    lasercanon = true,
                    lasercannon = true,
                    throw = true,
                    throwhold = true,
                    aim = true,
                    rockaim = true,
                    suspension = true,
                    flamestart = true,
                    flameloop = true,
                    flameend = true,
                    burningjavelin = true,
                    solflame = true,
                }

                if allowed[animationName] then
                    -- Do not use a fixed timer. Keep attack aim alive for the
                    -- actual animation track so long attacks are fully guided.
                    if clientModules.combat.attackStopConnection then
                        clientModules.combat.attackStopConnection:Disconnect()
                        clientModules.combat.attackStopConnection = nil
                    end

                    clientModules.combat.activeAttackTrack = track
                    clientModules.combat.attackStopConnection = track.Stopped:Connect(function()
                        if clientModules.combat.activeAttackTrack == track then
                            clientModules.combat.activeAttackTrack = nil
                        end

                        if clientModules.combat.attackStopConnection then
                            clientModules.combat.attackStopConnection:Disconnect()
                            clientModules.combat.attackStopConnection = nil
                        end
                    end)

                    -- Keep this non-zero for executors/animations that do not
                    -- report Stopped reliably.
                    clientModules.combat.aimActiveUntil = time() + 1
                end
            end)
    end
end

function clientModules.combat.pressDefenseKey()
    local keyCode = clientModules.combat.defenseKey or Enum.KeyCode.E
    local keyValue = keyCode.Value

    local sent = false

    pcall(function()
        local virtualInputManager = game:GetService("VirtualInputManager")
        virtualInputManager:SendKeyEvent(true, keyCode, false, game)
        task.wait(0.025)
        virtualInputManager:SendKeyEvent(false, keyCode, false, game)
        sent = true
    end)

    if not sent then
        pcall(function()
            local press = keypress
            local release = keyrelease

            if type(press) == "function" then
                press(keyValue)
                task.wait(0.025)
                if type(release) == "function" then
                    release(keyValue)
                end
                sent = true
            end
        end)
    end

    return sent
end

function clientModules.combat.detectDefenseCharacter(model)
    local name = clientModules.combat.detectCharacter(model)

    if name == "Kolossos" or name == "Knuckles" or name == "Eggman" then
        return name
    end

    local names = clientModules.combat.animNames(model)

    if names.block then
        return "Kolossos"
    end

    if names.focus then
        return "Knuckles"
    end

    if names.jetpack then
        return "Eggman"
    end

    return nil
end

function clientModules.combat.isEnemyAttack(model, track, markerName)
    local info = clientModules.combat.getTargetInfo(model)
    if not info or info.group ~= "Executioner" then
        return false
    end

    local animation = track and track.Animation
    local normalized = markerName
        and clientModules.combat.normalize(markerName)
        or (animation and clientModules.combat.normalize(animation.Name))

    if not normalized then
        return false
    end

    -- Auto Block / Counter on the survivor side reacts only to these attack
    -- families. Fleetway's rbxl uses ChargeDash/MissDash for Chaos Dash and
    -- GrabHold/Toss for Fateful Drain, so those internal animation markers
    -- are accepted as the corresponding abilities.
    if normalized == "attack"
        or normalized == "attack1"
        or normalized == "attack2"
        or normalized == "m1"
        or normalized == "charge"
        or normalized == "grab"
    then
        return true
    end

    if info.character == "Fleetway" then
        return normalized == "chaosdash"
            or normalized == "fatefuldrain"
            or normalized == "chargedash"
            or normalized == "missdash"
            or normalized == "grabhold"
            or normalized == "toss"
    end

    return false
end

function clientModules.combat.bindEnemyModel(model)
    if not model or clientModules.combat.modelConnections[model] then
        return
    end

    local humanoid = model:FindFirstChildOfClass("Humanoid")
    if not humanoid then
        return
    end

    local connections = {}

    local function tryDefend(track, markerName)
        if not clientModules.combat.autoCounterEnabled then
            return
        end

        -- This feature is for survivor-side Counter / Block / Energy Shield.
        local defenseCharacter = clientModules.combat.detectDefenseCharacter(localPlayer.Character)
        if not defenseCharacter then
            return
        end

        if not clientModules.combat.isEnemyAttack(model, track, markerName) then
            return
        end

        local distance = clientModules.combat.getDistance(model)

        -- Exact requested reaction window: 1–8 studs.
        if distance < 1 or distance > 8 then
            return
        end

        local now = time()
        -- No delay before the first key press. The small guard only prevents
        -- duplicate marker/animation signals from hammering the same defense.
        if now - clientModules.combat.lastCounterAt < 0.10 then
            return
        end

        clientModules.combat.lastCounterAt = now
        clientModules.combat.pressDefenseKey()
    end

    table.insert(connections, humanoid.AnimationPlayed:Connect(function(track)
        tryDefend(track, nil)
    end))

    -- Some attacks expose their ability name as a runtime descendant instead
    -- of the AnimationTrack name. Catch those markers as soon as they appear.
    table.insert(connections, model.DescendantAdded:Connect(function(instance)
        if not instance or not instance.Parent then
            return
        end

        local normalized = clientModules.combat.normalize(instance.Name)
        local attackMarkers = {
            attack = true,
            attack1 = true,
            attack2 = true,
            m1 = true,
            charge = true,
            grab = true,
            chaosdash = true,
            fatefuldrain = true,
            chargedash = true,
            missdash = true,
            grabhold = true,
            toss = true,
        }

        if attackMarkers[normalized] then
            tryDefend(nil, normalized)
        end
    end))

    clientModules.combat.modelConnections[model] = connections
end

function clientModules.combat.scanEnemyHooks()
    local valid = {}

    for _, model in ipairs(clientModules.combat.getPlayerModels()) do
        valid[model] = true
        clientModules.combat.bindEnemyModel(model)
    end

    for model, connections in pairs(clientModules.combat.modelConnections) do
        if not valid[model] or not model.Parent then
            if type(connections) == "table" then
                for _, connection in ipairs(connections) do
                    if connection then
                        connection:Disconnect()
                    end
                end
            elseif connections then
                connections:Disconnect()
            end

            clientModules.combat.modelConnections[model] = nil
        end
    end
end

function clientModules.combat.setAutoAimEnabled(enabled, silent)
    clientModules.combat.autoAimEnabled = enabled == true
    clientModules.combat.updateVisuals()

    if clientModules.combat.autoAimEnabled then
        clientModules.combat.refreshCharacterHooks()
    end

    if not silent then
        setStatus(
            clientModules.combat.autoAimEnabled
                and "Auto Aim enabled."
                or "Auto Aim disabled.",
            clientModules.combat.autoAimEnabled and COLORS.Green or COLORS.MutedText
        )
    end
end

function clientModules.combat.setAutoCounterEnabled(enabled, silent)
    clientModules.combat.autoCounterEnabled = enabled == true
    clientModules.combat.updateVisuals()

    if clientModules.combat.autoCounterEnabled then
        clientModules.combat.scanEnemyHooks()
    else
        for model, connections in pairs(clientModules.combat.modelConnections) do
            if type(connections) == "table" then
                for _, connection in ipairs(connections) do
                    if connection then
                        connection:Disconnect()
                    end
                end
            elseif connections then
                connections:Disconnect()
            end

            clientModules.combat.modelConnections[model] = nil
        end
    end

    if not silent then
        setStatus(
            clientModules.combat.autoCounterEnabled
                and "Auto Block / Counter enabled."
                or "Auto Block / Counter disabled.",
            clientModules.combat.autoCounterEnabled and COLORS.Green or COLORS.MutedText
        )
    end
end

function clientModules.combat.initialize()
    clientModules.combat.serial = clientModules.combat.serial + 1

    clientModules.combat.clearConnections()

    if clientModules.combat.renderConnection then
        clientModules.combat.renderConnection:Disconnect()
        clientModules.combat.renderConnection = nil
    end

    pcall(function()
        RunService:UnbindFromRenderStep(clientModules.combat.renderBindName)
    end)

    if clientModules.combat.scanConnection then
        clientModules.combat.scanConnection:Disconnect()
        clientModules.combat.scanConnection = nil
    end

    if clientModules.combat.characterConnection then
        clientModules.combat.characterConnection:Disconnect()
        clientModules.combat.characterConnection = nil
    end

    clientModules.combat.characterConnection = localPlayer.CharacterAdded:Connect(function()
        task.defer(function()
            if not guiDestroyed then
                clientModules.combat.refreshCharacterHooks()
            end
        end)
    end)

    clientModules.combat.refreshCharacterHooks()

    RunService:BindToRenderStep(
        clientModules.combat.renderBindName,
        Enum.RenderPriority.Camera.Value + 1,
        function()
            if guiDestroyed then
                return
            end

            local attackTrack = clientModules.combat.activeAttackTrack
            local attackActive = attackTrack
                and pcall(function()
                    return attackTrack.IsPlaying
                end)
                and attackTrack.IsPlaying

            if clientModules.combat.autoAimEnabled
                and attackActive
                and time() <= clientModules.combat.aimActiveUntil then
                -- Guide the actual attack direction while the supported ability
                -- is playing. The physical mouse is never moved.
                local target = clientModules.combat.refreshTarget()
                local camera = workspace.CurrentCamera
                local root = target and clientModules.combat.getRoot(target.model)
                local character = localPlayer.Character
                local characterRoot = character and clientModules.combat.getRoot(character)

                if root then
                    local targetPosition = root.Position

                    -- Many movement/melee abilities use the character's facing
                    -- direction rather than the cursor. Face the character
                    -- toward the selected target during the attack.
                    if characterRoot then
                        local characterPosition = characterRoot.Position
                        local flatTarget = Vector3.new(
                            targetPosition.X,
                            characterPosition.Y,
                            targetPosition.Z
                        )

                        if (flatTarget - characterPosition).Magnitude > 0.01 then
                            characterRoot.CFrame = CFrame.lookAt(
                                characterPosition,
                                flatTarget
                            )
                        end
                    end

                    -- Ranged abilities commonly take their direction from the
                    -- camera/mouse ray. Match the camera to the same target.
                    if camera then
                        local cameraPosition = camera.CFrame.Position
                        local desired = CFrame.lookAt(cameraPosition, targetPosition)
                        local smoothness = math.clamp(
                            tonumber(clientModules.combat.aimSmoothness) or 0.28,
                            0.02,
                            1
                        )

                        camera.CFrame = camera.CFrame:Lerp(desired, smoothness)
                    end
                end
            elseif clientModules.combat.showTarget then
                clientModules.combat.refreshTarget()
            end
        end
    )

    clientModules.combat.scanConnection = RunService.Heartbeat:Connect(function(deltaTime)
        if guiDestroyed then
            return
        end

        if clientModules.combat.autoCounterEnabled then
            clientModules.combat.scanEnemyHooks()
        end
    end)

    clientModules.combat.updateVisuals()
end

function clientModules.combat.shutdown()
    clientModules.combat.serial = clientModules.combat.serial + 1
    clientModules.combat.clearConnections()

    if clientModules.combat.characterConnection then
        clientModules.combat.characterConnection:Disconnect()
        clientModules.combat.characterConnection = nil
    end

    if clientModules.combat.renderConnection then
        clientModules.combat.renderConnection:Disconnect()
        clientModules.combat.renderConnection = nil
    end

    pcall(function()
        RunService:UnbindFromRenderStep(clientModules.combat.renderBindName)
    end)

    if clientModules.combat.scanConnection then
        clientModules.combat.scanConnection:Disconnect()
        clientModules.combat.scanConnection = nil
    end

    for model, connection in pairs(clientModules.combat.modelConnections) do
        if connection then
            connection:Disconnect()
        end
        clientModules.combat.modelConnections[model] = nil
    end

    clientModules.combat.currentTarget = nil
    clientModules.combat.currentTargetName = nil
    clientModules.combat.activeAttackTrack = nil

    if clientModules.combat.attackStopConnection then
        clientModules.combat.attackStopConnection:Disconnect()
        clientModules.combat.attackStopConnection = nil
    end

    table.clear(clientModules.combat.activeMarkers)
end

-- COMBAT UI
createSectionLabel(clientModules.pages.combat, "COMBAT / ASSIST", 1)

clientModules.combat.autoAimButton, clientModules.combat.autoAimDot =
    createToggleRow(clientModules.pages.combat, "Auto Aim", 2)

clientModules.combat.autoCounterButton, clientModules.combat.autoCounterDot =
    createToggleRow(clientModules.pages.combat, "Auto Block / Counter", 3)

clientModules.combat.showTargetButton, clientModules.combat.showTargetDot =
    createToggleRow(clientModules.pages.combat, "Show current target", 4)

clientModules.combat.priorityLabel = create("TextLabel", {
    LayoutOrder = 5,
    Size = UDim2.new(1, 0, 0, 22),
    BackgroundTransparency = 1,
    Text = "Target priority: Weakest",
    Font = Enum.Font.GothamBold,
    TextSize = 12,
    TextColor3 = COLORS.Cyan,
    TextXAlignment = Enum.TextXAlignment.Left,
}, clientModules.pages.combat)

do
    local row = create("Frame", {
        LayoutOrder = 6,
        Size = UDim2.new(1, 0, 0, 40),
        BackgroundTransparency = 1,
    }, clientModules.pages.combat)

    clientModules.combat.priorityButtons = {}

    local options = {"Weakest", "Strongest", "Nearest"}
    for index, option in ipairs(options) do
        local button = create("TextButton", {
            Position = UDim2.new((index - 1) / 3, index == 1 and 0 or 6, 0, 0),
            Size = UDim2.new(1 / 3, -6, 1, 0),
            BackgroundColor3 = COLORS.Input,
            BorderSizePixel = 0,
            Text = option,
            Font = Enum.Font.GothamBold,
            TextSize = 11,
            TextColor3 = COLORS.Text,
            AutoButtonColor = false,
        }, row)
        addCorner(button, 8)
        addStroke(button, COLORS.Border, 0.35, 1)

        button.Activated:Connect(function()
            clientModules.combat.setPriority(option)
        end)

        clientModules.combat.priorityButtons[option] = button
    end
end

clientModules.combat.aimSmoothnessBox = createInputRow(
    clientModules.pages.combat,
    "Aim smoothness (0.02–1.0)",
    "0.28",
    "Example: 0.25",
    7
)

clientModules.combat.targetLabel = create("TextLabel", {
    LayoutOrder = 8,
    Size = UDim2.new(1, 0, 0, 42),
    BackgroundColor3 = COLORS.Card,
    BackgroundTransparency = 0.16,
    BorderSizePixel = 0,
    Text = "Current target: none",
    Font = Enum.Font.GothamMedium,
    TextSize = 12,
    TextColor3 = COLORS.MutedText,
    TextWrapped = true,
    TextXAlignment = Enum.TextXAlignment.Left,
    TextYAlignment = Enum.TextYAlignment.Center,
}, clientModules.pages.combat)
addCorner(clientModules.combat.targetLabel, 9)
addStroke(clientModules.combat.targetLabel, COLORS.Border, 0.28, 1)
create("UIPadding", {
    PaddingLeft = UDim.new(0, 14),
    PaddingRight = UDim.new(0, 14),
}, clientModules.combat.targetLabel)

createSectionLabel(clientModules.pages.combat, "AUTO AIM / RBXL ABILITIES", 9)

create("TextLabel", {
    LayoutOrder = 10,
    Size = UDim2.new(1, 0, 0, 122),
    BackgroundColor3 = COLORS.CyanDeep,
    BackgroundTransparency = 0.22,
    BorderSizePixel = 0,
    Text = "Executioners:\n2011x — Charge\nTripwire — Brighter Day\nFleetway — Lasers of Destrucation\n\nSurvivors:\nTails — Laser Canon\nAmy — Hammer Throw\nSilver — Rock / Suspension\nBlaze — Sol Flame / Burning Javelin",
    Font = Enum.Font.GothamMedium,
    TextSize = 11,
    TextColor3 = COLORS.MutedText,
    TextWrapped = true,
    TextXAlignment = Enum.TextXAlignment.Left,
    TextYAlignment = Enum.TextYAlignment.Center,
}, clientModules.pages.combat)

createSectionLabel(clientModules.pages.combat, "AUTO BLOCK / COUNTER", 11)

create("TextLabel", {
    LayoutOrder = 12,
    Size = UDim2.new(1, 0, 0, 88),
    BackgroundColor3 = COLORS.CyanDeep,
    BackgroundTransparency = 0.22,
    BorderSizePixel = 0,
    Text = "Kolossos — Block\nKnuckles — Counter\nEggman — Energy Shield\n\nDefense input defaults to the rbxl AB1 key (E in the supplied save).",
    Font = Enum.Font.GothamMedium,
    TextSize = 11,
    TextColor3 = COLORS.MutedText,
    TextWrapped = true,
    TextXAlignment = Enum.TextXAlignment.Left,
    TextYAlignment = Enum.TextYAlignment.Center,
}, clientModules.pages.combat)


-- FUN / PLACE-SPECIFIC UI

function clientModules.fun.findFirstByName(name, className)
    for _, instance in ipairs(game:GetDescendants()) do
        if instance.Name == name
            and (not className or instance:IsA(className)) then
            return instance
        end
    end

    return nil
end

function clientModules.fun.getCharacter()
    return localPlayer.Character
end

function clientModules.fun.getCharacterRoot()
    local character = clientModules.fun.getCharacter()
    if not character then
        return nil
    end

    return character:FindFirstChild("HumanoidRootPart")
        or character.PrimaryPart
end

function clientModules.fun.setSpinEnabled(enabled, silent)
    enabled = enabled == true
    clientModules.fun.spinEnabled = enabled

    if clientModules.fun.spinConnection then
        clientModules.fun.spinConnection:Disconnect()
        clientModules.fun.spinConnection = nil
    end

    if enabled then
        clientModules.fun.spinConnection = RunService.RenderStepped:Connect(function(deltaTime)
            if guiDestroyed or not clientModules.fun.spinEnabled then
                return
            end

            local root = clientModules.fun.getCharacterRoot()
            if root and root:IsA("BasePart") then
                root.CFrame = root.CFrame * CFrame.Angles(0, math.rad(360) * deltaTime, 0)
            end
        end)
    end

    if clientModules.fun.spinButton then
        setSwitchVisual(
            clientModules.fun.spinButton,
            clientModules.fun.spinDot,
            enabled
        )
    end

    if not silent then
        setStatus(
            enabled and "Fun: Spin enabled." or "Fun: Spin disabled.",
            enabled and COLORS.Green or COLORS.MutedText
        )
    end
end

function clientModules.fun.findNearestPlayerCharacter()
    local root = clientModules.fun.getCharacterRoot()
    if not root then
        return nil
    end

    local nearestCharacter = nil
    local nearestDistance = math.huge

    for _, player in ipairs(Players:GetPlayers()) do
        if player ~= localPlayer and player.Character then
            local targetRoot = player.Character:FindFirstChild("HumanoidRootPart")
                or player.Character.PrimaryPart
            local humanoid = player.Character:FindFirstChildOfClass("Humanoid")

            if targetRoot and targetRoot:IsA("BasePart")
                and humanoid
                and humanoid.Health > 0 then
                local distance = (targetRoot.Position - root.Position).Magnitude

                if distance < nearestDistance then
                    nearestDistance = distance
                    nearestCharacter = player.Character
                end
            end
        end
    end

    return nearestCharacter
end

function clientModules.fun.setSpectateEnabled(enabled, silent)
    enabled = enabled == true
    clientModules.fun.spectateEnabled = enabled

    if clientModules.fun.spectateConnection then
        clientModules.fun.spectateConnection:Disconnect()
        clientModules.fun.spectateConnection = nil
    end

    local camera = workspace.CurrentCamera

    if enabled then
        if camera and not clientModules.fun.originalCameraSubject then
            clientModules.fun.originalCameraSubject = camera.CameraSubject
        end

        clientModules.fun.spectateConnection = RunService.RenderStepped:Connect(function()
            if guiDestroyed or not clientModules.fun.spectateEnabled then
                return
            end

            local currentCamera = workspace.CurrentCamera
            local targetCharacter = clientModules.fun.findNearestPlayerCharacter()
            local humanoid = targetCharacter
                and targetCharacter:FindFirstChildOfClass("Humanoid")

            if currentCamera and humanoid then
                currentCamera.CameraType = Enum.CameraType.Custom
                currentCamera.CameraSubject = humanoid
            end
        end)
    else
        if camera then
            local character = clientModules.fun.getCharacter()
            local humanoid = character and character:FindFirstChildOfClass("Humanoid")

            camera.CameraType = Enum.CameraType.Custom
            camera.CameraSubject = humanoid or clientModules.fun.originalCameraSubject
        end

        clientModules.fun.originalCameraSubject = nil
    end

    if clientModules.fun.spectateButton then
        setSwitchVisual(
            clientModules.fun.spectateButton,
            clientModules.fun.spectateDot,
            enabled
        )
    end

    if not silent then
        setStatus(
            enabled and "Fun: Spectate nearest enabled." or "Fun: Spectate disabled.",
            enabled and COLORS.Green or COLORS.MutedText
        )
    end
end

function clientModules.fun.setCharacterLockEnabled(enabled, silent)
    local value = clientModules.fun.characterLockValue
    if not value or not value.Parent then
        value = clientModules.fun.findFirstByName("CharacterLOCK", "BoolValue")
        clientModules.fun.characterLockValue = value
    end

    if not value then
        if clientModules.fun.characterLockButton then
            setSwitchVisual(
                clientModules.fun.characterLockButton,
                clientModules.fun.characterLockDot,
                false
            )
        end

        if not silent then
            setStatus("CharacterLOCK was not found in this place.", COLORS.Yellow)
        end
        return false
    end

    if clientModules.fun.originalCharacterLock == nil then
        clientModules.fun.originalCharacterLock = value.Value
    end

    value.Value = enabled == true

    if clientModules.fun.characterLockButton then
        setSwitchVisual(
            clientModules.fun.characterLockButton,
            clientModules.fun.characterLockDot,
            enabled == true
        )
    end

    if not silent then
        setStatus(
            enabled and "Place CharacterLOCK enabled locally." or "Place CharacterLOCK disabled locally.",
            COLORS.Green
        )
    end

    return true
end

function clientModules.fun.playPlaceAnimation(animationName)
    local character = clientModules.fun.getCharacter()
    local humanoid = character and character:FindFirstChildOfClass("Humanoid")

    if not humanoid then
        setStatus("No Humanoid found for the animation.", COLORS.Yellow)
        return false
    end

    local animator = humanoid:FindFirstChildOfClass("Animator")
    if not animator then
        animator = Instance.new("Animator")
        animator.Parent = humanoid
    end

    local animation = nil

    -- Prefer an existing animation object from this place.
    pcall(function()
        animation = clientModules.fun.findFirstByName(animationName, "Animation")
    end)

    if not animation then
        setStatus("Animation '" .. tostring(animationName) .. "' was not found.", COLORS.Yellow)
        return false
    end

    local ok, track = pcall(function()
        return animator:LoadAnimation(animation)
    end)

    if not ok or not track then
        setStatus("Could not load animation '" .. tostring(animationName) .. "'.", COLORS.Yellow)
        return false
    end

    track.Priority = Enum.AnimationPriority.Action
    track:Play(0.05, 1, 1)

    setStatus("Played place animation: " .. tostring(animationName) .. ".", COLORS.Green)
    return true
end

function clientModules.fun.forceSit(silent)
    local character = clientModules.fun.getCharacter()
    local humanoid = character and character:FindFirstChildOfClass("Humanoid")

    if humanoid then
        humanoid.Sit = true

        if not silent then
            setStatus("Fun: Sit.", COLORS.Green)
        end

        return true
    end

    if not silent then
        setStatus("No Humanoid found.", COLORS.Yellow)
    end

    return false
end

function clientModules.fun.forceStand(silent)
    local character = clientModules.fun.getCharacter()
    local humanoid = character and character:FindFirstChildOfClass("Humanoid")

    if humanoid then
        humanoid.Sit = false

        if not silent then
            setStatus("Fun: Stand.", COLORS.Green)
        end

        return true
    end

    if not silent then
        setStatus("No Humanoid found.", COLORS.Yellow)
    end

    return false
end

function clientModules.fun.getPlaceInfo()
    local function readValue(name, className)
        local value = clientModules.fun.findFirstByName(name, className)
        if not value then
            return "not found"
        end

        return tostring(value.Value)
    end

    return {
        gameVersion = readValue("GameVersion", "StringValue"),
        state = readValue("State", "StringValue"),
        exe = readValue("EXE", "StringValue"),
        characterLock = readValue("CharacterLOCK", "BoolValue"),
    }
end

function clientModules.fun.shutdown()
    clientModules.fun.setSpinEnabled(false, true)
    clientModules.fun.setSpectateEnabled(false, true)

    if clientModules.fun.characterLockValue
        and clientModules.fun.originalCharacterLock ~= nil
        and clientModules.fun.characterLockValue.Parent then
        pcall(function()
            clientModules.fun.characterLockValue.Value =
                clientModules.fun.originalCharacterLock
        end)
    end

    clientModules.fun.characterLockValue = nil
    clientModules.fun.originalCharacterLock = nil
end

createSectionLabel(clientModules.pages.fun, "FUN / PLACE", 1)

clientModules.fun.spinButton, clientModules.fun.spinDot =
    createToggleRow(clientModules.pages.fun, "Spin", 2)

clientModules.fun.spectateButton, clientModules.fun.spectateDot =
    createToggleRow(clientModules.pages.fun, "Spectate nearest player", 3)

clientModules.fun.characterLockButton, clientModules.fun.characterLockDot =
    createToggleRow(clientModules.pages.fun, "CharacterLOCK (local)", 4)

clientModules.fun.sitButton = create("TextButton", {
    LayoutOrder = 5,
    Size = UDim2.new(1, 0, 0, 38),
    BackgroundColor3 = COLORS.CyanDark,
    BackgroundTransparency = 0.11,
    BorderSizePixel = 0,
    Text = "SIT",
    Font = Enum.Font.GothamBold,
    TextSize = 13,
    TextColor3 = COLORS.Text,
    AutoButtonColor = true,
    Active = true,
    Selectable = true,
}, clientModules.pages.fun)
addCorner(clientModules.fun.sitButton, 12)
addStroke(clientModules.fun.sitButton, COLORS.Cyan, 0.35, 1)

clientModules.fun.standButton = clientModules.fun.sitButton:Clone()
clientModules.fun.standButton.Name = "StandButton"
clientModules.fun.standButton.Text = "STAND"
clientModules.fun.standButton.Parent = clientModules.pages.fun
clientModules.fun.standButton.LayoutOrder = 6

createSectionLabel(clientModules.pages.fun, "FUN / PLACE ANIMATIONS", 7)

local function createFunAnimationButton(text, animationName, layoutOrder)
    local button = create("TextButton", {
        LayoutOrder = layoutOrder,
        Size = UDim2.new(1, 0, 0, 38),
        BackgroundColor3 = COLORS.CyanDark,
        BackgroundTransparency = 0.11,
        BorderSizePixel = 0,
        Text = text,
        Font = Enum.Font.GothamBold,
        TextSize = 13,
        TextColor3 = COLORS.Text,
        AutoButtonColor = true,
        Active = true,
        Selectable = true,
    }, clientModules.pages.fun)
    addCorner(button, 12)
    addStroke(button, COLORS.Cyan, 0.35, 1)

    button.Activated:Connect(function()
        clientModules.fun.playPlaceAnimation(animationName)
    end)

    return button
end

clientModules.fun.throwButton =
    createFunAnimationButton("PLAY THROW", "Throw", 8)
clientModules.fun.downStabButton =
    createFunAnimationButton("PLAY DOWN STAB", "DownStab", 9)
clientModules.fun.stabPunchButton =
    createFunAnimationButton("PLAY STAB PUNCH", "StabPunch", 10)

clientModules.fun.infoLabel = create("TextLabel", {
    LayoutOrder = 11,
    Size = UDim2.new(1, 0, 0, 112),
    BackgroundColor3 = COLORS.CyanDeep,
    BackgroundTransparency = 0.22,
    BorderSizePixel = 0,
    Text = "PLACE DATA\nLoading...",
    Font = Enum.Font.GothamMedium,
    TextSize = 11,
    TextColor3 = COLORS.MutedText,
    TextWrapped = true,
    TextXAlignment = Enum.TextXAlignment.Left,
    TextYAlignment = Enum.TextYAlignment.Center,
}, clientModules.pages.fun)
addCorner(clientModules.fun.infoLabel, 12)
addStroke(clientModules.fun.infoLabel, COLORS.Border, 0.28, 1)

function clientModules.fun.refreshInfo()
    if not clientModules.fun.infoLabel or not clientModules.fun.infoLabel.Parent then
        return
    end

    local info = clientModules.fun.getPlaceInfo()
    clientModules.fun.infoLabel.Text = string.format(
        "PLACE DATA\nGameVersion: %s\nState: %s\nEXE: %s\nCharacterLOCK: %s",
        info.gameVersion,
        info.state,
        info.exe,
        info.characterLock
    )
end

clientModules.fun.refreshInfo()
function clientModules.speedControl.normalizeMethod(value)
    return "WalkSpeed"
end

function clientModules.speedControl.normalizeMode(value)
    return value == "Set" and "Set" or "Add"
end

function clientModules.speedControl.getMethodLabel(value)
    return clientModules.speedControl.normalizeMethod(value)
end

function clientModules.speedControl.getModeLabel(value)
    return clientModules.speedControl.normalizeMode(value) == "Set"
        and "Set (=)"
        or "Increase (+)"
end

function clientModules.speedControl.calculateTarget(baseSpeed, speedValue, mode)
    baseSpeed = math.max(tonumber(baseSpeed) or 0, 0)
    speedValue = math.max(tonumber(speedValue) or 0, 0)

    if clientModules.speedControl.normalizeMode(mode) == "Set" then
        return speedValue
    end

    return baseSpeed + speedValue
end

function clientModules.speedControl.createChoiceRow(parent, labelText, valueText, layoutOrder)
    return createKeybindRow(parent, labelText, valueText, layoutOrder)
end

createSectionLabel(clientModules.pages.info, "INFO  /  PULSECORE", 1)

do
    local creatorInfo = create("TextLabel", {
        LayoutOrder = 2,
        Size = UDim2.new(1, 0, 0, 64),
        BackgroundColor3 = COLORS.CyanDeep,
        BackgroundTransparency = 0.2,
        BorderSizePixel = 0,
        Text = "CREATOR\nMarckoq",
        Font = Enum.Font.GothamBold,
        TextSize = 16,
        TextColor3 = COLORS.Text,
        TextWrapped = true,
        TextXAlignment = Enum.TextXAlignment.Left,
        TextYAlignment = Enum.TextYAlignment.Center,
    }, clientModules.pages.info)
    addCorner(creatorInfo, 12)
    addStroke(creatorInfo, COLORS.Cyan, 0.55, 1)
    create("UIPadding", {
        PaddingLeft = UDim.new(0, 16),
        PaddingRight = UDim.new(0, 16),
    }, creatorInfo)
end

do
    local versionInfo = create("TextLabel", {
        LayoutOrder = 3,
        Size = UDim2.new(1, 0, 0, 64),
        BackgroundColor3 = COLORS.CyanDeep,
        BackgroundTransparency = 0.2,
        BorderSizePixel = 0,
        Text = "CURRENT VERSION\n" .. SCRIPT_VERSION,
        Font = Enum.Font.GothamBold,
        TextSize = 16,
        TextColor3 = COLORS.Text,
        TextWrapped = true,
        TextXAlignment = Enum.TextXAlignment.Left,
        TextYAlignment = Enum.TextYAlignment.Center,
    }, clientModules.pages.info)
    addCorner(versionInfo, 12)
    addStroke(versionInfo, COLORS.Cyan, 0.55, 1)
    create("UIPadding", {
        PaddingLeft = UDim.new(0, 16),
        PaddingRight = UDim.new(0, 16),
    }, versionInfo)
end

do
    local changelogInfo = create("TextLabel", {
        LayoutOrder = 4,
        Size = UDim2.new(1, 0, 0, 260),
        BackgroundColor3 = COLORS.CyanDeep,
        BackgroundTransparency = 0.28,
        BorderSizePixel = 0,
        Text = table.concat({
            "CHANGELOG / LATEST UPDATE",
            "",
            "• Reworked the Info page: it now contains only the creator, current version, and latest changelog.",
            "• Added local config file storage in the executor workspace under AppData\\Local.",
            "• Each config is saved as its own JSON file using the config name as the file name.",
            "• Configs now survive a full Roblox restart; save, load, rename, delete, and Auto Load are synchronized with the files.",
            "• Increased the main interface height for more comfortable Settings and config management.",
        }, "\n"),
        Font = Enum.Font.GothamMedium,
        TextSize = 13,
        TextColor3 = COLORS.MutedText,
        TextWrapped = true,
        TextXAlignment = Enum.TextXAlignment.Left,
        TextYAlignment = Enum.TextYAlignment.Top,
    }, clientModules.pages.info)
    addCorner(changelogInfo, 12)
    addStroke(changelogInfo, COLORS.Cyan, 0.72, 1)
    create("UIPadding", {
        PaddingTop = UDim.new(0, 14),
        PaddingBottom = UDim.new(0, 14),
        PaddingLeft = UDim.new(0, 16),
        PaddingRight = UDim.new(0, 16),
    }, changelogInfo)
end

createSectionLabel(localPage, "LOCAL  /  SPEED SETTINGS", 1)

speedBox = createInputRow(
    localPage,
    "Speed value, studs/s",
    tostring(DEFAULT_SPEED_BONUS),
    "Example: 16",
    2
)

clientModules.speedControl.standardMethodButton = clientModules.speedControl.createChoiceRow(
    localPage,
    "Speed method",
    "WalkSpeed",
    3
)
clientModules.speedControl.standardMethodButton.Parent.Visible = false
clientModules.speedControl.standardMethod = "WalkSpeed"

clientModules.speedControl.standardModeButton = clientModules.speedControl.createChoiceRow(
    localPage,
    "Speed calculation",
    clientModules.speedControl.getModeLabel(clientModules.speedControl.standardMode),
    4
)

jumpBox = createInputRow(
    localPage,
    "Jump bonus, studs/s",
    tostring(DEFAULT_JUMP_BONUS),
    "Example: 50",
    5
)

enforceIntegerTextBox(speedBox, MIN_SPEED_BONUS, MAX_SPEED_BONUS)
enforceIntegerTextBox(jumpBox, MIN_JUMP_BONUS, MAX_JUMP_BONUS)

clientModules.jumpBoost.standardToggleButton, clientModules.jumpBoost.standardToggleDot = createToggleRow(
    localPage,
    "Use Jump Boost",
    6
)

clientModules.characterTools.sharpMovementButton,
clientModules.characterTools.sharpMovementDot = createToggleRow(
    localPage,
    "Sharp Movement / Anti-Slide",
    7
)

delayBox = createInputRow(
    localPage,
    "Activation delay, seconds",
    "0",
    "Example: 3",
    8
)

durationBox = createInputRow(
    localPage,
    "Duration, seconds or inf",
    "inf",
    "inf or 10",
    9
)

clientModules.cooldown.standard.cooldownBox = createInputRow(
    localPage,
    "Cooldown time, seconds",
    "0",
    "Example: 5",
    10
)

delayToggleRow = create("Frame", {
    LayoutOrder = 11,
    Size = UDim2.new(1, 0, 0, 38),
    BackgroundColor3 = COLORS.CyanDeep,
    BackgroundTransparency = 0.2,
    BorderSizePixel = 0,
}, localPage)
addCorner(delayToggleRow, 12)
addStroke(delayToggleRow, COLORS.Cyan, 0.72, 1)

create("TextLabel", {
    Position = UDim2.fromOffset(14, 0),
    Size = UDim2.new(1, -86, 1, 0),
    BackgroundTransparency = 1,
    Text = "Use activation delay",
    Font = Enum.Font.GothamMedium,
    TextSize = 13,
    TextColor3 = COLORS.Text,
    TextXAlignment = Enum.TextXAlignment.Left,
}, delayToggleRow)

toggleButton = create("TextButton", {
    AnchorPoint = Vector2.new(1, 0.5),
    Position = UDim2.new(1, -11, 0.5, 0),
    Size = UDim2.fromOffset(58, 28),
    BackgroundColor3 = COLORS.Input,
    BorderSizePixel = 0,
    Text = "",
    AutoButtonColor = false,
}, delayToggleRow)
addCorner(toggleButton, 999)

toggleDot = create("Frame", {
    AnchorPoint = Vector2.new(0, 0.5),
    Position = UDim2.new(0, 4, 0.5, 0),
    Size = UDim2.fromOffset(20, 20),
    BackgroundColor3 = COLORS.MutedText,
    BorderSizePixel = 0,
}, toggleButton)
addCorner(toggleDot, 999)

clientModules.cooldown.standard.toggleButton, clientModules.cooldown.standard.toggleDot = createToggleRow(
    localPage,
    "Use cooldown",
    12
)

boostKeyButton = createKeybindRow(
    localPage,
    "Speed Boost hotkey",
    DEFAULT_BOOST_KEY.Name,
    13
)

statusLabel = create("TextLabel", {
    LayoutOrder = 14,
    Size = UDim2.new(1, 0, 0, 34),
    BackgroundTransparency = 1,
    Text = "Ready. Speed Boost is disabled.",
    Font = Enum.Font.GothamMedium,
    TextSize = 12,
    TextColor3 = COLORS.MutedText,
    TextWrapped = true,
    TextXAlignment = Enum.TextXAlignment.Left,
    TextYAlignment = Enum.TextYAlignment.Center,
}, localPage)

activateButton = create("TextButton", {
    LayoutOrder = 15,
    Size = UDim2.new(1, 0, 0, 38),
    BackgroundColor3 = COLORS.Cyan,
    BackgroundTransparency = 0.11,
    BorderSizePixel = 0,
    Text = "ACTIVATE SPEED BOOST",
    Font = Enum.Font.GothamBold,
    TextSize = 13,
    TextColor3 = COLORS.CyanDeep,
    AutoButtonColor = true,
    Active = true,
    Selectable = true,
    ZIndex = 10,
}, localPage)
addCorner(activateButton, 12)
addStroke(activateButton, Color3.new(1, 1, 1), 0.72, 1)

createSectionLabel(localPage, "LOCAL  /  CHARACTER ABILITIES", 16)

clientModules.characterTools.noclipButton, clientModules.characterTools.noclipDot = createToggleRow(
    localPage,
    "Noclip    •    N",
    17
)

clientModules.characterTools.infinityJumpButton, clientModules.characterTools.infinityJumpDot = createToggleRow(
    localPage,
    "Infinity Jump",
    18
)

clientModules.inventoryOrder.toggleButton, clientModules.inventoryOrder.toggleDot = createToggleRow(
    localPage,
    "Preserve Inventory Order",
    19
)
clientModules.inventoryOrder.toggleButton.Parent.Visible = false
clientModules.inventoryOrder.enabled = false

clientModules.infFlight.button = create("TextButton", {
    LayoutOrder = 20,
    Size = UDim2.new(1, 0, 0, 38),
    BackgroundColor3 = COLORS.CyanDark,
    BackgroundTransparency = 0.11,
    BorderSizePixel = 0,
    Text = "Inf Flight",
    Font = Enum.Font.GothamBold,
    TextSize = 13,
    TextColor3 = COLORS.Text,
    AutoButtonColor = true,
    Active = true,
    Selectable = true,
}, localPage)
addCorner(clientModules.infFlight.button, 12)
addStroke(clientModules.infFlight.button, COLORS.Cyan, 0.35, 1)

createSectionLabel(localPage, "LOCAL  /  FLIGHT", 21)

clientModules.flight.speedBox = createInputRow(
    localPage,
    "Flight speed, studs/s (1–200)",
    tostring(DEFAULT_FLIGHT_SPEED),
    "Example: 50",
    22
)
enforceIntegerTextBox(
    clientModules.flight.speedBox,
    MIN_FLIGHT_SPEED,
    MAX_FLIGHT_SPEED
)

clientModules.flight.sliderCard = create("Frame", {
    LayoutOrder = 23,
    Size = UDim2.new(1, 0, 0, 94),
    BackgroundColor3 = COLORS.Card,
    BackgroundTransparency = 0.16,
    BorderSizePixel = 0,
}, localPage)
addCorner(clientModules.flight.sliderCard, 9)
addStroke(clientModules.flight.sliderCard, COLORS.Border, 0.28, 1)

create("TextLabel", {
    Position = UDim2.fromOffset(14, 7),
    Size = UDim2.new(1, -24, 0, 24),
    BackgroundTransparency = 1,
    Text = "Flight speed (1 - 200)",
    Font = Enum.Font.GothamMedium,
    TextSize = 13,
    TextColor3 = COLORS.Text,
    TextXAlignment = Enum.TextXAlignment.Left,
}, clientModules.flight.sliderCard)

clientModules.flight.sliderTrack = create("Frame", {
    Position = UDim2.new(0, 16, 1, -29),
    Size = UDim2.new(1, -32, 0, 10),
    BackgroundColor3 = COLORS.Input,
    BorderSizePixel = 0,
    Active = true,
}, clientModules.flight.sliderCard)
addCorner(clientModules.flight.sliderTrack, 999)

clientModules.flight.sliderFill = create("Frame", {
    Size = UDim2.new(0, 0, 1, 0),
    BackgroundColor3 = COLORS.Cyan,
    BorderSizePixel = 0,
}, clientModules.flight.sliderTrack)
addCorner(clientModules.flight.sliderFill, 999)

clientModules.flight.sliderKnob = create("Frame", {
    AnchorPoint = Vector2.new(0.5, 0.5),
    Position = UDim2.new(0, 0, 0.5, 0),
    Size = UDim2.fromOffset(20, 20),
    BackgroundColor3 = COLORS.White,
    BorderSizePixel = 0,
    ZIndex = 2,
}, clientModules.flight.sliderTrack)
addCorner(clientModules.flight.sliderKnob, 999)

clientModules.flight.toggleButton = create("TextButton", {
    LayoutOrder = 24,
    Size = UDim2.new(1, 0, 0, 38),
    BackgroundColor3 = COLORS.CyanDark,
    BackgroundTransparency = 0.11,
    BorderSizePixel = 0,
    Text = "FLIGHT    •    F",
    Font = Enum.Font.GothamBold,
    TextSize = 13,
    TextColor3 = COLORS.Text,
    AutoButtonColor = true,
    Active = true,
    Selectable = true,
}, localPage)
addCorner(clientModules.flight.toggleButton, 12)
addStroke(clientModules.flight.toggleButton, COLORS.Cyan, 0.35, 1)

clientModules.flight.statusLabel = create("TextLabel", {
    LayoutOrder = 25,
    Size = UDim2.new(1, 0, 0, 54),
    BackgroundColor3 = COLORS.CyanDeep,
    BackgroundTransparency = 0.32,
    BorderSizePixel = 0,
    Text = "Flight disabled. Speed: 50 studs/s • WASD / Space / LeftControl.",
    Font = Enum.Font.GothamMedium,
    TextSize = 12,
    TextColor3 = COLORS.MutedText,
    TextWrapped = true,
    TextXAlignment = Enum.TextXAlignment.Left,
    TextYAlignment = Enum.TextYAlignment.Center,
}, localPage)
addCorner(clientModules.flight.statusLabel, 12)
create("UIPadding", {
    PaddingLeft = UDim.new(0, 14),
    PaddingRight = UDim.new(0, 14),
}, clientModules.flight.statusLabel)

addAbilityButton = create("TextButton", {
    LayoutOrder = 10000,
    Size = UDim2.new(1, 0, 0, 38),
    BackgroundColor3 = COLORS.CyanDark,
    BackgroundTransparency = 0.11,
    BorderSizePixel = 0,
    Text = "Add a new ability",
    Font = Enum.Font.GothamBold,
    TextSize = 13,
    TextColor3 = COLORS.Text,
    AutoButtonColor = true,
    Active = true,
    Selectable = true,
}, localPage)
addCorner(addAbilityButton, 12)
addStroke(addAbilityButton, COLORS.Cyan, 0.35, 1)

createSectionLabel(visualsPage, "VISUALS  /  CHARACTER ESP", 1)

espSurvivorsButton, espSurvivorsDot = createToggleRow(
    visualsPage,
    "ESP Survivors — blue fill",
    2
)

espExecutionersButton, espExecutionersDot = createToggleRow(
    visualsPage,
    "ESP Executioners — red fill",
    3
)

espDistanceButton, espDistanceDot = createToggleRow(
    visualsPage,
    "ESP Distance — studs",
    4
)

espTracersButton, espTracersDot = createToggleRow(
    visualsPage,
    "ESP Tracers — role color",
    5
)

espSurvivorInfoButton, espSurvivorInfoDot = createToggleRow(
    visualsPage,
    "ESP Survivor HP + status",
    6
)

espAbilitiesButton, espAbilitiesDot = createToggleRow(
    visualsPage,
    "ESP Abilities + cooldown",
    7
)

visualsStatusLabel = create("TextLabel", {
    LayoutOrder = 8,
    Size = UDim2.new(1, 0, 0, 48),
    BackgroundColor3 = COLORS.CyanDeep,
    BackgroundTransparency = 0.32,
    BorderSizePixel = 0,
    Text = "Searching Workspace for Survivors / EXE / Executioners...",
    Font = Enum.Font.GothamMedium,
    TextSize = 12,
    TextColor3 = COLORS.MutedText,
    TextWrapped = true,
    TextXAlignment = Enum.TextXAlignment.Left,
    TextYAlignment = Enum.TextYAlignment.Center,
}, visualsPage)
addCorner(visualsStatusLabel, 12)
create("UIPadding", {
    PaddingLeft = UDim.new(0, 14),
    PaddingRight = UDim.new(0, 14),
}, visualsStatusLabel)

visualsHint = create("TextLabel", {
    LayoutOrder = 9,
    Size = UDim2.new(1, 0, 0, 108),
    BackgroundColor3 = COLORS.CyanDeep,
    BackgroundTransparency = 0.32,
    BorderSizePixel = 0,
    Text = "ESP classifies characters only by recognized ability names. Survivors use blue; Executioners use scarlet. A name tag stays above each highlighted character and scales down with distance.",
    Font = Enum.Font.GothamMedium,
    TextSize = 12,
    TextColor3 = COLORS.MutedText,
    TextWrapped = true,
    TextXAlignment = Enum.TextXAlignment.Left,
}, visualsPage)
addCorner(visualsHint, 12)
create("UIPadding", {
    PaddingLeft = UDim.new(0, 14),
    PaddingRight = UDim.new(0, 14),
}, visualsHint)

do
    local boostTabsHost = create("Frame", {
        Size = UDim2.fromOffset(1, 1),
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        Visible = false,
        Active = false,
    }, visualsPage)

    clientModules.boostTabs.toggleButton, clientModules.boostTabs.toggleDot = createToggleRow(
        boostTabsHost,
        "Boost status",
        1
    )

    clientModules.boostTabs.hintLabel = create("TextLabel", {
        Size = UDim2.fromOffset(1, 1),
        Visible = false,
        BackgroundTransparency = 1,
        Text = "",
    }, boostTabsHost)

    clientModules.boostTabs.window = create("Frame", {
        Size = UDim2.fromOffset(1, 1),
        Visible = false,
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        Active = false,
    }, screenGui)

    clientModules.boostTabs.enabled = false
end

function clientModules.createActionButton(parent, textValue, position, size, backgroundColor)
    local button = create("TextButton", {
        Position = position,
        Size = size,
        BackgroundColor3 = backgroundColor or COLORS.CyanDark,
        BackgroundTransparency = 0.11,
        BorderSizePixel = 0,
        Text = textValue,
        Font = Enum.Font.GothamBold,
        TextSize = 12,
        TextColor3 = COLORS.Text,
        AutoButtonColor = true,
        Active = true,
        Selectable = true,
    }, parent)
    addCorner(button, 10)
    addStroke(button, COLORS.Cyan, 0.48, 1)
    return button
end

-- CAMERA: всё меняется только у локального игрока и его CurrentCamera.
createSectionLabel(clientModules.pages.camera, "CAMERA  /  VIEW SETTINGS", 1)
clientModules.camera.fovBox = createInputRow(
    clientModules.pages.camera,
    "Field of View (40–120)",
    tostring(clientModules.camera.fov),
    "Example: 80",
    2
)
clientModules.camera.zoomBox = createInputRow(
    clientModules.pages.camera,
    "Maximum zoom distance",
    tostring(clientModules.camera.maxZoom),
    "Example: 128",
    3
)
clientModules.camera.firstPersonButton, clientModules.camera.firstPersonDot = createToggleRow(
    clientModules.pages.camera,
    "Lock first-person view",
    4
)
clientModules.camera.buttonsRow = create("Frame", {
    LayoutOrder = 5,
    Size = UDim2.new(1, 0, 0, 38),
    BackgroundTransparency = 1,
    BorderSizePixel = 0,
}, clientModules.pages.camera)
clientModules.camera.applyButton = clientModules.createActionButton(
    clientModules.camera.buttonsRow,
    "APPLY CAMERA",
    UDim2.fromScale(0, 0),
    UDim2.new(0.49, 0, 1, 0),
    COLORS.CyanDark
)
clientModules.camera.resetButton = clientModules.createActionButton(
    clientModules.camera.buttonsRow,
    "RESET CAMERA",
    UDim2.new(0.51, 0, 0, 0),
    UDim2.new(0.49, 0, 1, 0),
    COLORS.Input
)
clientModules.camera.statusLabel = create("TextLabel", {
    LayoutOrder = 6,
    Size = UDim2.new(1, 0, 0, 62),
    BackgroundColor3 = COLORS.CyanDeep,
    BackgroundTransparency = 0.32,
    BorderSizePixel = 0,
    Text = "Camera settings have not been applied yet.",
    Font = Enum.Font.GothamMedium,
    TextSize = 12,
    TextColor3 = COLORS.MutedText,
    TextWrapped = true,
    TextXAlignment = Enum.TextXAlignment.Left,
    TextYAlignment = Enum.TextYAlignment.Center,
}, clientModules.pages.camera)
addCorner(clientModules.camera.statusLabel, 12)
create("UIPadding", {
    PaddingLeft = UDim.new(0, 14),
    PaddingRight = UDim.new(0, 14),
}, clientModules.camera.statusLabel)

-- PERFORMANCE: visible optimization and FPS controls.
createSectionLabel(clientModules.pages.performance, "PERFORMANCE  /  OPTIMIZATION", 1)

clientModules.performance.modeButton, clientModules.performance.modeDot = createToggleRow(
    clientModules.pages.performance,
    "Performance Mode",
    2
)

clientModules.performance.particlesButton, clientModules.performance.particlesDot = createToggleRow(
    clientModules.pages.performance,
    "Disable particles, Trails, and Beams",
    3
)

clientModules.performance.postEffectsButton, clientModules.performance.postEffectsDot = createToggleRow(
    clientModules.pages.performance,
    "Disable post-processing effects",
    4
)

clientModules.performance.shadowsButton, clientModules.performance.shadowsDot = createToggleRow(
    clientModules.pages.performance,
    "Disable global shadows",
    5
)

clientModules.performance.statusLabel = create("TextLabel", {
    LayoutOrder = 6,
    Size = UDim2.new(1, 0, 0, 62),
    BackgroundColor3 = COLORS.CyanDeep,
    BackgroundTransparency = 0.32,
    BorderSizePixel = 0,
    Text = "Optimization is disabled.",
    Font = Enum.Font.GothamMedium,
    TextSize = 12,
    TextColor3 = COLORS.MutedText,
    TextWrapped = true,
    TextXAlignment = Enum.TextXAlignment.Left,
    TextYAlignment = Enum.TextYAlignment.Center,
}, clientModules.pages.performance)
addCorner(clientModules.performance.statusLabel, 12)
create("UIPadding", {
    PaddingLeft = UDim.new(0, 14),
    PaddingRight = UDim.new(0, 14),
}, clientModules.performance.statusLabel)

createSectionLabel(clientModules.pages.performance, "PERFORMANCE  /  FPS LIMITER", 7)

clientModules.performance.fpsLimiterButton, clientModules.performance.fpsLimiterDot = createToggleRow(
    clientModules.pages.performance,
    "Enable FPS Limiter",
    8
)

clientModules.performance.fpsSliderCard = create("Frame", {
    LayoutOrder = 9,
    Size = UDim2.new(1, 0, 0, 94),
    BackgroundColor3 = COLORS.Card,
    BackgroundTransparency = 0.16,
    BorderSizePixel = 0,
}, clientModules.pages.performance)
addCorner(clientModules.performance.fpsSliderCard, 9)
addStroke(clientModules.performance.fpsSliderCard, COLORS.Border, 0.28, 1)

create("TextLabel", {
    Position = UDim2.fromOffset(14, 7),
    Size = UDim2.new(1, -178, 0, 34),
    BackgroundTransparency = 1,
    Text = "FPS limit (15 - 240)",
    Font = Enum.Font.GothamMedium,
    TextSize = 13,
    TextColor3 = COLORS.Text,
    TextXAlignment = Enum.TextXAlignment.Left,
}, clientModules.performance.fpsSliderCard)

clientModules.performance.fpsBox = create("TextBox", {
    AnchorPoint = Vector2.new(1, 0),
    Position = UDim2.new(1, -10, 0, 7),
    Size = UDim2.fromOffset(148, 34),
    BackgroundColor3 = COLORS.Input,
    BorderSizePixel = 0,
    ClearTextOnFocus = false,
    Text = tostring(clientModules.performance.fpsLimit),
    PlaceholderText = "60",
    PlaceholderColor3 = COLORS.MutedText,
    Font = Enum.Font.GothamMedium,
    TextSize = 14,
    TextColor3 = COLORS.Text,
    TextXAlignment = Enum.TextXAlignment.Center,
}, clientModules.performance.fpsSliderCard)
addCorner(clientModules.performance.fpsBox, 7)
addStroke(clientModules.performance.fpsBox, COLORS.Border, 0.22, 1)
enforceIntegerTextBox(
    clientModules.performance.fpsBox,
    clientModules.performance.fpsMin,
    clientModules.performance.fpsMax
)

clientModules.performance.fpsSliderTrack = create("Frame", {
    Position = UDim2.new(0, 16, 1, -29),
    Size = UDim2.new(1, -32, 0, 10),
    BackgroundColor3 = COLORS.Input,
    BorderSizePixel = 0,
    Active = true,
}, clientModules.performance.fpsSliderCard)
addCorner(clientModules.performance.fpsSliderTrack, 999)

clientModules.performance.fpsSliderFill = create("Frame", {
    Size = UDim2.new(0, 0, 1, 0),
    BackgroundColor3 = COLORS.Cyan,
    BorderSizePixel = 0,
}, clientModules.performance.fpsSliderTrack)
addCorner(clientModules.performance.fpsSliderFill, 999)

clientModules.performance.fpsSliderKnob = create("Frame", {
    AnchorPoint = Vector2.new(0.5, 0.5),
    Position = UDim2.new(0, 0, 0.5, 0),
    Size = UDim2.fromOffset(20, 20),
    BackgroundColor3 = COLORS.White,
    BorderSizePixel = 0,
}, clientModules.performance.fpsSliderTrack)
addCorner(clientModules.performance.fpsSliderKnob, 999)

clientModules.performance.fpsStatusLabel = create("TextLabel", {
    LayoutOrder = 10,
    Size = UDim2.new(1, 0, 0, 54),
    BackgroundColor3 = COLORS.CyanDeep,
    BackgroundTransparency = 0.32,
    BorderSizePixel = 0,
    Text = "FPS limiter is disabled.",
    Font = Enum.Font.GothamMedium,
    TextSize = 12,
    TextColor3 = COLORS.MutedText,
    TextWrapped = true,
    TextXAlignment = Enum.TextXAlignment.Left,
    TextYAlignment = Enum.TextYAlignment.Center,
}, clientModules.pages.performance)
addCorner(clientModules.performance.fpsStatusLabel, 12)
create("UIPadding", {
    PaddingLeft = UDim.new(0, 14),
    PaddingRight = UDim.new(0, 14),
}, clientModules.performance.fpsStatusLabel)

clientModules.performance.hintLabel = create("TextLabel", {
    LayoutOrder = 11,
    Size = UDim2.new(1, 0, 0, 84),
    BackgroundColor3 = COLORS.CyanDeep,
    BackgroundTransparency = 0.32,
    BorderSizePixel = 0,
    Text = "Performance Mode disables particles, post-processing, and global shadows locally. FPS Limiter uses setfpscap when the executor supports it.",
    Font = Enum.Font.GothamMedium,
    TextSize = 12,
    TextColor3 = COLORS.MutedText,
    TextWrapped = true,
    TextXAlignment = Enum.TextXAlignment.Left,
}, clientModules.pages.performance)
addCorner(clientModules.performance.hintLabel, 12)
create("UIPadding", {
    PaddingLeft = UDim.new(0, 14),
    PaddingRight = UDim.new(0, 14),
}, clientModules.performance.hintLabel)

-- HUD: локальный информационный оверлей.
createSectionLabel(clientModules.pages.hud, "HUD  /  INFORMATION", 1)
clientModules.hud.fpsButton, clientModules.hud.fpsDot = createToggleRow(
    clientModules.pages.hud,
    "Show FPS",
    2
)
clientModules.hud.coordinatesButton, clientModules.hud.coordinatesDot = createToggleRow(
    clientModules.pages.hud,
    "Show coordinates",
    3
)
clientModules.hud.speedButton, clientModules.hud.speedDot = createToggleRow(
    clientModules.pages.hud,
    "Show current speed",
    4
)
clientModules.hud.statusLabel = create("TextLabel", {
    LayoutOrder = 5,
    Size = UDim2.new(1, 0, 0, 50),
    BackgroundColor3 = COLORS.CyanDeep,
    BackgroundTransparency = 0.32,
    BorderSizePixel = 0,
    Text = "HUD disabled.",
    Font = Enum.Font.GothamMedium,
    TextSize = 12,
    TextColor3 = COLORS.MutedText,
    TextWrapped = true,
    TextXAlignment = Enum.TextXAlignment.Left,
    TextYAlignment = Enum.TextYAlignment.Center,
}, clientModules.pages.hud)
addCorner(clientModules.hud.statusLabel, 12)
create("UIPadding", {
    PaddingLeft = UDim.new(0, 14),
    PaddingRight = UDim.new(0, 14),
}, clientModules.hud.statusLabel)
clientModules.hud.overlay = create("TextLabel", {
    Name = "ClientInfoHUD",
    AnchorPoint = Vector2.new(0, 0),
    Position = UDim2.fromOffset(12, 12),
    Size = UDim2.fromOffset(260, 88),
    BackgroundColor3 = COLORS.Panel,
    BackgroundTransparency = 0.18,
    BorderSizePixel = 0,
    Visible = false,
    Text = "",
    Font = Enum.Font.Code,
    TextSize = 14,
    TextColor3 = COLORS.Text,
    TextWrapped = false,
    TextXAlignment = Enum.TextXAlignment.Left,
    TextYAlignment = Enum.TextYAlignment.Top,
    ZIndex = 50,
}, screenGui)
addCorner(clientModules.hud.overlay, 10)
addStroke(clientModules.hud.overlay, COLORS.Cyan, 0.35, 1)
create("UIPadding", {
    PaddingTop = UDim.new(0, 8),
    PaddingBottom = UDim.new(0, 8),
    PaddingLeft = UDim.new(0, 10),
    PaddingRight = UDim.new(0, 10),
}, clientModules.hud.overlay)


-- KEY LIST: all hotkeys in one place. Keep these references in a table instead of
-- creating many top-level locals; Luau has a 200-register limit for a chunk.
clientModules.keyList = clientModules.keyList or {}
clientModules.keyList.buttons = clientModules.keyList.buttons or {}
clientModules.keyList.abilityButtons = clientModules.keyList.abilityButtons or {}

createSectionLabel(clientModules.pages.keyList, "KEY LIST  /  ALL HOTKEYS", 1)
clientModules.keyList.hint = create("TextLabel", {
    LayoutOrder = 2,
    Size = UDim2.new(1, 0, 0, 52),
    BackgroundColor3 = COLORS.CyanDeep,
    BackgroundTransparency = 0.28,
    BorderSizePixel = 0,
    Text = "Click a key field, then press a new key. Escape cancels. Duplicate keys are blocked.",
    Font = Enum.Font.GothamMedium,
    TextSize = 12,
    TextColor3 = COLORS.MutedText,
    TextWrapped = true,
    TextXAlignment = Enum.TextXAlignment.Left,
    TextYAlignment = Enum.TextYAlignment.Center,
}, clientModules.pages.keyList)
addCorner(clientModules.keyList.hint, 12)
create("UIPadding", {
    PaddingLeft = UDim.new(0, 14),
    PaddingRight = UDim.new(0, 14),
}, clientModules.keyList.hint)

clientModules.keyList.buttons.Boost = createKeybindRow(clientModules.pages.keyList, "Enable Boost", DEFAULT_BOOST_KEY.Name, 3)
clientModules.keyList.buttons.Interface = createKeybindRow(clientModules.pages.keyList, "Hide / Show Interface", DEFAULT_INTERFACE_KEY.Name, 4)
clientModules.keyList.buttons.Noclip = createKeybindRow(clientModules.pages.keyList, "Enable Noclip", DEFAULT_NOCLIP_KEY.Name, 5)
clientModules.keyList.buttons.Flight = createKeybindRow(clientModules.pages.keyList, "Toggle Flight", DEFAULT_FLIGHT_KEY.Name, 6)
createSectionLabel(clientModules.pages.keyList, "ABILITY HOTKEYS", 14)
for index = 1, MAX_ABILITIES do
    clientModules.keyList.abilityButtons[index] = createKeybindRow(
        clientModules.pages.keyList,
        string.format("Ability %d", index),
        ABILITY_DEFAULT_KEYS[index].Name,
        14 + index
    )
end

clientModules.keyList.status = create("TextLabel", {
    LayoutOrder = 19,
    Size = UDim2.new(1, 0, 0, 42),
    BackgroundColor3 = COLORS.CyanDeep,
    BackgroundTransparency = 0.32,
    BorderSizePixel = 0,
    Text = "Key changes apply immediately for the current session.",
    Font = Enum.Font.GothamMedium,
    TextSize = 12,
    TextColor3 = COLORS.MutedText,
    TextWrapped = true,
    TextXAlignment = Enum.TextXAlignment.Left,
    TextYAlignment = Enum.TextYAlignment.Center,
}, clientModules.pages.keyList)
addCorner(clientModules.keyList.status, 12)
create("UIPadding", {
    PaddingLeft = UDim.new(0, 14),
    PaddingRight = UDim.new(0, 14),
}, clientModules.keyList.status)

clientModules.keyList.state = clientModules.keyList.state or {
    boostKey = DEFAULT_BOOST_KEY,
    interfaceKey = DEFAULT_INTERFACE_KEY,
    noclipKey = DEFAULT_NOCLIP_KEY,
    flightKey = DEFAULT_FLIGHT_KEY,
    bindingTarget = nil,
    bindingPreviousText = nil,
}


-- AUTO SELECT: автоматизирует только клиентское нажатие выбора персонажа.
createSectionLabel(clientModules.pages.autoSelect, "AUTO SELECT  /  CHARACTER SELECTION", 1)
clientModules.autoSelect.toggleButton, clientModules.autoSelect.toggleDot = createToggleRow(
    clientModules.pages.autoSelect,
    "Auto Select",
    2
)
clientModules.autoSelect.selectedLabel = create("TextLabel", {
    LayoutOrder = 3,
    Size = UDim2.new(1, 0, 0, 38),
    BackgroundColor3 = COLORS.CyanDeep,
    BackgroundTransparency = 0.22,
    BorderSizePixel = 0,
    Text = "Selected Character: None",
    Font = Enum.Font.GothamBold,
    TextSize = 13,
    TextColor3 = COLORS.Text,
    TextWrapped = true,
    TextXAlignment = Enum.TextXAlignment.Left,
    TextYAlignment = Enum.TextYAlignment.Center,
}, clientModules.pages.autoSelect)
addCorner(clientModules.autoSelect.selectedLabel, 12)
addStroke(clientModules.autoSelect.selectedLabel, COLORS.Cyan, 0.65, 1)
create("UIPadding", {
    PaddingLeft = UDim.new(0, 14),
    PaddingRight = UDim.new(0, 14),
}, clientModules.autoSelect.selectedLabel)

for index, characterInfo in ipairs(clientModules.autoSelect.characters) do
    local characterButton = create("TextButton", {
        LayoutOrder = 3 + index,
        Size = UDim2.new(1, 0, 0, 40),
        BackgroundColor3 = COLORS.Input,
        BackgroundTransparency = 0.16,
        BorderSizePixel = 0,
        Text = characterInfo.displayName,
        Font = Enum.Font.GothamBold,
        TextSize = 13,
        TextColor3 = COLORS.Text,
        AutoButtonColor = true,
        Active = true,
        Selectable = true,
    }, clientModules.pages.autoSelect)
    addCorner(characterButton, 10)
    addStroke(characterButton, COLORS.Cyan, 0.58, 1)
    clientModules.autoSelect.characterButtons[characterInfo.gameName] = characterButton
    characterButton.Activated:Connect(function()
        clientModules.autoSelect.selectCharacter(characterInfo.gameName, false)
    end)
end

clientModules.autoSelect.statusLabel = create("TextLabel", {
    LayoutOrder = 20,
    Size = UDim2.new(1, 0, 0, 68),
    BackgroundColor3 = COLORS.CyanDeep,
    BackgroundTransparency = 0.32,
    BorderSizePixel = 0,
    Text = "Auto Select is disabled. Choose a character from the list.",
    Font = Enum.Font.GothamMedium,
    TextSize = 12,
    TextColor3 = COLORS.MutedText,
    TextWrapped = true,
    TextXAlignment = Enum.TextXAlignment.Left,
    TextYAlignment = Enum.TextYAlignment.Center,
}, clientModules.pages.autoSelect)
addCorner(clientModules.autoSelect.statusLabel, 12)
create("UIPadding", {
    PaddingLeft = UDim.new(0, 14),
    PaddingRight = UDim.new(0, 14),
}, clientModules.autoSelect.statusLabel)

createSectionLabel(settingsPage, "SETTINGS  /  INTERFACE", 1)

interfaceKeyButton = createKeybindRow(
    settingsPage,
    "Hide / show interface",
    DEFAULT_INTERFACE_KEY.Name,
    2
)

settingsHint = create("TextLabel", {
    LayoutOrder = 3,
    Size = UDim2.new(1, 0, 0, 50),
    BackgroundColor3 = COLORS.CyanDeep,
    BackgroundTransparency = 0.32,
    BorderSizePixel = 0,
    Text = "Click a key field, then press the desired key. Escape cancels the change.",
    Font = Enum.Font.GothamMedium,
    TextSize = 12,
    TextColor3 = COLORS.MutedText,
    TextWrapped = true,
    TextXAlignment = Enum.TextXAlignment.Left,
}, settingsPage)
addCorner(settingsHint, 12)
create("UIPadding", {
    PaddingLeft = UDim.new(0, 14),
    PaddingRight = UDim.new(0, 14),
}, settingsHint)

clientModules.console.toggleButton, clientModules.console.toggleDot = createToggleRow(
    settingsPage,
    "Live Console",
    4
)

clientModules.console.hintLabel = create("TextLabel", {
    LayoutOrder = 5,
    Size = UDim2.new(1, 0, 0, 68),
    BackgroundColor3 = COLORS.CyanDeep,
    BackgroundTransparency = 0.32,
    BorderSizePixel = 0,
    Text = "When enabled, the live console shows only PulseCore-related diagnostics: internal Info, warnings, errors, feature events, and tagged Roblox Output generated by this script. Unrelated game logs are ignored.",
    Font = Enum.Font.GothamMedium,
    TextSize = 12,
    TextColor3 = COLORS.MutedText,
    TextWrapped = true,
    TextXAlignment = Enum.TextXAlignment.Left,
}, settingsPage)
addCorner(clientModules.console.hintLabel, 12)
create("UIPadding", {
    PaddingLeft = UDim.new(0, 14),
    PaddingRight = UDim.new(0, 14),
}, clientModules.console.hintLabel)

configManager = {}

createSectionLabel(settingsPage, "CONFIGS  /  SAVED PROFILES", 6)

configManager.configNameBox = createInputRow(
    settingsPage,
    "New config name",
    "Default",
    "Example: Main",
    7
)

configManager.configButtonsRow = create("Frame", {
    LayoutOrder = 8,
    Size = UDim2.new(1, 0, 0, 38),
    BackgroundTransparency = 1,
    BorderSizePixel = 0,
}, settingsPage)

function configManager.createConfigButton(parent, text, position, size, backgroundColor)
    local button = create("TextButton", {
        Position = position,
        Size = size,
        BackgroundColor3 = backgroundColor,
        BackgroundTransparency = 0.11,
        BorderSizePixel = 0,
        Text = text,
        Font = Enum.Font.GothamBold,
        TextSize = 12,
        TextColor3 = COLORS.Text,
        AutoButtonColor = true,
        Active = true,
        Selectable = true,
    }, parent)
    addCorner(button, 10)
    addStroke(button, COLORS.Cyan, 0.48, 1)
    return button
end

configManager.saveConfigButton = configManager.createConfigButton(
    configManager.configButtonsRow,
    "SAVE CONFIG",
    UDim2.fromScale(0, 0),
    UDim2.new(0.49, 0, 1, 0),
    COLORS.CyanDark
)

configManager.listConfigsButton = configManager.createConfigButton(
    configManager.configButtonsRow,
    "LIST CONFIGS",
    UDim2.new(0.51, 0, 0, 0),
    UDim2.new(0.49, 0, 1, 0),
    COLORS.CyanDark
)

configManager.configStatusLabel = create("TextLabel", {
    LayoutOrder = 9,
    Size = UDim2.new(1, 0, 0, 76),
    BackgroundColor3 = COLORS.CyanDeep,
    BackgroundTransparency = 0.32,
    BorderSizePixel = 0,
    Text = "No saved configs yet.",
    Font = Enum.Font.GothamMedium,
    TextSize = 12,
    TextColor3 = COLORS.MutedText,
    TextWrapped = true,
    TextXAlignment = Enum.TextXAlignment.Left,
    TextYAlignment = Enum.TextYAlignment.Center,
}, settingsPage)
addCorner(configManager.configStatusLabel, 12)
create("UIPadding", {
    PaddingLeft = UDim.new(0, 14),
    PaddingRight = UDim.new(0, 14),
}, configManager.configStatusLabel)

configManager.configManagerFrame = create("Frame", {
    LayoutOrder = 10,
    Size = UDim2.new(1, 0, 0, 0),
    BackgroundColor3 = COLORS.CyanDeep,
    BackgroundTransparency = 0.18,
    BorderSizePixel = 0,
    ClipsDescendants = true,
    Visible = false,
}, settingsPage)
addCorner(configManager.configManagerFrame, 12)
addStroke(configManager.configManagerFrame, COLORS.Cyan, 0.58, 1)

configManager.selectedConfigLabel = create("TextLabel", {
    Position = UDim2.fromOffset(12, 8),
    Size = UDim2.new(1, -24, 0, 26),
    BackgroundTransparency = 1,
    Text = "Selected config: none",
    Font = Enum.Font.GothamBold,
    TextSize = 12,
    TextColor3 = COLORS.Text,
    TextXAlignment = Enum.TextXAlignment.Left,
}, configManager.configManagerFrame)

configManager.configList = create("ScrollingFrame", {
    Position = UDim2.fromOffset(12, 40),
    Size = UDim2.new(1, -24, 0, 112),
    BackgroundColor3 = COLORS.Input,
    BackgroundTransparency = 0.12,
    BorderSizePixel = 0,
    CanvasSize = UDim2.fromOffset(0, 0),
    ScrollBarThickness = 4,
    ScrollBarImageColor3 = COLORS.Cyan,
    ScrollingDirection = Enum.ScrollingDirection.Y,
    Active = true,
    ClipsDescendants = true,
}, configManager.configManagerFrame)
addCorner(configManager.configList, 9)

create("UIPadding", {
    PaddingTop = UDim.new(0, 5),
    PaddingBottom = UDim.new(0, 5),
    PaddingLeft = UDim.new(0, 5),
    PaddingRight = UDim.new(0, 8),
}, configManager.configList)

configManager.configListLayout = create("UIListLayout", {
    FillDirection = Enum.FillDirection.Vertical,
    HorizontalAlignment = Enum.HorizontalAlignment.Left,
    SortOrder = Enum.SortOrder.LayoutOrder,
    Padding = UDim.new(0, 5),
}, configManager.configList)

configManager.configListLayout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
    configManager.configList.CanvasSize = UDim2.fromOffset(0, configManager.configListLayout.AbsoluteContentSize.Y + 10)
end)

configManager.renameConfigBox = create("TextBox", {
    Position = UDim2.fromOffset(12, 162),
    Size = UDim2.new(1, -24, 0, 38),
    BackgroundColor3 = COLORS.Input,
    BackgroundTransparency = 0.16,
    BorderSizePixel = 0,
    ClearTextOnFocus = false,
    Text = "",
    PlaceholderText = "New name for the selected config",
    PlaceholderColor3 = COLORS.MutedText,
    Font = Enum.Font.GothamMedium,
    TextSize = 13,
    TextColor3 = COLORS.Text,
    TextXAlignment = Enum.TextXAlignment.Center,
}, configManager.configManagerFrame)
addCorner(configManager.renameConfigBox, 9)
addStroke(configManager.renameConfigBox, COLORS.Cyan, 0.58, 1)

configManager.configActionsRow = create("Frame", {
    Position = UDim2.fromOffset(12, 210),
    Size = UDim2.new(1, -24, 0, 40),
    BackgroundTransparency = 1,
}, configManager.configManagerFrame)

configManager.deleteConfigButton = configManager.createConfigButton(
    configManager.configActionsRow,
    "DELETE",
    UDim2.fromScale(0, 0),
    UDim2.new(0.32, 0, 1, 0),
    COLORS.Red
)

configManager.editConfigButton = configManager.createConfigButton(
    configManager.configActionsRow,
    "EDIT",
    UDim2.new(0.34, 0, 0, 0),
    UDim2.new(0.32, 0, 1, 0),
    COLORS.CyanDark
)

configManager.loadConfigButton = configManager.createConfigButton(
    configManager.configActionsRow,
    "LOAD",
    UDim2.new(0.68, 0, 0, 0),
    UDim2.new(0.32, 0, 1, 0),
    COLORS.CyanDark
)

configManager.configAutoLoadRow = create("Frame", {
    Position = UDim2.fromOffset(12, 260),
    Size = UDim2.new(1, -24, 0, 40),
    BackgroundTransparency = 1,
}, configManager.configManagerFrame)

configManager.autoLoadConfigButton = configManager.createConfigButton(
    configManager.configAutoLoadRow,
    "AUTO LOAD",
    UDim2.fromScale(0, 0),
    UDim2.new(0.49, 0, 1, 0),
    COLORS.Green
)

configManager.disableAutoLoadButton = configManager.createConfigButton(
    configManager.configAutoLoadRow,
    "DISABLE AUTO LOAD",
    UDim2.new(0.51, 0, 0, 0),
    UDim2.new(0.49, 0, 1, 0),
    COLORS.CyanDark
)

delayEnabled = false
minimized = false
boostActive = false
boostPending = false
activationSerial = 0
activeBonus = DEFAULT_SPEED_BONUS
activeUntil = nil
activeOwner = nil
pendingOwner = nil
pendingBonus = nil
pendingDuration = nil
pendingUntil = nil
resumeStandardAfterAbility = false
standardResumeSnapshot = nil
abilities = {}
configManager.savedConfigs = {}
configManager.selectedConfigName = nil
configManager.autoLoadConfigName = nil
configManager.configListVisible = false
configManager.configListButtons = {}
movementConnection = nil
statusConnection = nil
boostedHumanoid = nil
baseWalkSpeed = nil
expectedWalkSpeed = nil
walkSpeedConnection = nil
applyingWalkSpeed = false
guiDestroyed = false
dragInputChangedConnection = nil
cameraConnection = nil
currentCameraChangedConnection = nil
globalInputConnection = nil

espSurvivorsEnabled = false
espExecutionersEnabled = false
espDistanceEnabled = false
espTracersEnabled = false
espSurvivorInfoEnabled = false
espAbilitiesEnabled = false
espInfoGui = nil
espInfoWindow = nil
espInfoScroll = nil
espInfoLayout = nil
espInfoRefreshConnection = nil
espInfoUpdateAccumulator = 0
espAbilityCacheAccumulator = 0
espAbilityCooldownCache = {}
trackedModels = {}
recordedESPContainers = {}
characterModelsFolder = nil
characterModelAddedConnection = nil
characterModelRemovedConnection = nil
characterFolderAncestryConnection = nil
localCharacterAddedConnection = nil
espWorkspaceAddedConnection = nil
espWorkspaceRemovingConnection = nil
espNameTagConnection = nil
espScanQueued = false
espScanSerial = 0


function setStatus(text, color)
    statusLabel.Text = text
    statusLabel.TextColor3 = color or COLORS.MutedText
    logPulseCoreStatus(text, color)
end

function setToggleVisual()
    local targetPosition
    local targetColor

    toggleButton.Text = ""

    if delayEnabled then
        toggleButton.BackgroundColor3 = COLORS.CyanDark
        targetPosition = UDim2.new(1, -24, 0.5, 0)
        targetColor = COLORS.Green
    else
        toggleButton.BackgroundColor3 = COLORS.Input
        targetPosition = UDim2.new(0, 4, 0.5, 0)
        targetColor = COLORS.MutedText
    end

    TweenService:Create(toggleDot, TweenInfo.new(0.16), {
        Position = targetPosition,
        BackgroundColor3 = targetColor,
    }):Play()
end

function setSwitchVisual(button, dot, enabled)
    local targetPosition
    local targetColor

    button.Text = ""

    if enabled then
        button.BackgroundColor3 = COLORS.CyanDark
        targetPosition = UDim2.new(1, -27, 0.5, 0)
        targetColor = COLORS.Green
    else
        button.BackgroundColor3 = COLORS.Input
        targetPosition = UDim2.new(0, 5, 0.5, 0)
        targetColor = COLORS.MutedText
    end

    TweenService:Create(dot, TweenInfo.new(0.16), {
        Position = targetPosition,
        BackgroundColor3 = targetColor,
    }):Play()
end

-- Centralized interface motion. The CanvasGroups keep the animations smooth
-- even though the UI contains many nested controls.
interfaceAnimationSerial = 0

function animateMainInterfaceVisibility(visible)
    interfaceAnimationSerial = interfaceAnimationSerial + 1
    local serial = interfaceAnimationSerial

    if visible then
        screenGui.Enabled = true
        mainFrame.Visible = true

        interfaceCanvasGroup.GroupTransparency = 1
        mainFrame.BackgroundTransparency = 1
        uiScale.Scale = 0.94

        local tweenInfo = TweenInfo.new(
            0.28,
            Enum.EasingStyle.Quint,
            Enum.EasingDirection.Out
        )

        TweenService:Create(interfaceCanvasGroup, tweenInfo, {
            GroupTransparency = 0,
        }):Play()

        TweenService:Create(mainFrame, tweenInfo, {
            BackgroundTransparency = 0.16,
        }):Play()

        TweenService:Create(uiScale, tweenInfo, {
            Scale = 1,
        }):Play()
    else
        local tweenInfo = TweenInfo.new(
            0.20,
            Enum.EasingStyle.Quint,
            Enum.EasingDirection.In
        )

        local groupTween = TweenService:Create(interfaceCanvasGroup, tweenInfo, {
            GroupTransparency = 1,
        })
        TweenService:Create(mainFrame, tweenInfo, {
            BackgroundTransparency = 1,
        }):Play()
        TweenService:Create(uiScale, tweenInfo, {
            Scale = 0.94,
        }):Play()

        groupTween:Play()

        task.spawn(function()
            groupTween.Completed:Wait()

            if serial == interfaceAnimationSerial and not guiDestroyed then
                screenGui.Enabled = false
                mainFrame.BackgroundTransparency = 0.16
                uiScale.Scale = 1
            end
        end)
    end
end


function clientModules.camera.parseNumber(textValue, minimum, maximum)
    local normalized = tostring(textValue or "")
    normalized = string.gsub(normalized, ",", ".")
    normalized = string.gsub(normalized, "%s+", "")
    local value = tonumber(normalized)

    if not value then
        return nil
    end

    return math.clamp(value, minimum, maximum)
end

function clientModules.camera.updateStatus(message, color)
    clientModules.camera.statusLabel.Text = message
    clientModules.camera.statusLabel.TextColor3 = color or COLORS.MutedText
end

function clientModules.camera.refreshVisuals()
    setSwitchVisual(
        clientModules.camera.firstPersonButton,
        clientModules.camera.firstPersonDot,
        clientModules.camera.firstPerson
    )
end

function clientModules.camera.applyToCurrentCamera()
    if not clientModules.camera.applied then
        return
    end

    local camera = workspace.CurrentCamera
    if camera then
        camera.FieldOfView = clientModules.camera.fov
    end
end

function clientModules.camera.applySettings(silent)
    local fov = clientModules.camera.parseNumber(clientModules.camera.fovBox.Text, 40, 120)
    local maxZoom = clientModules.camera.parseNumber(clientModules.camera.zoomBox.Text, 0.5, 1000)

    if not fov then
        clientModules.camera.updateStatus("Error: FOV must be a number from 40 to 120.", COLORS.Red)
        return false
    end

    if not maxZoom then
        clientModules.camera.updateStatus("Error: maximum zoom must be a number from 0.5 to 1000.", COLORS.Red)
        return false
    end

    clientModules.camera.fov = fov
    clientModules.camera.maxZoom = maxZoom
    clientModules.camera.fovBox.Text = tostring(math.floor(fov * 100 + 0.5) / 100)
    clientModules.camera.zoomBox.Text = tostring(math.floor(maxZoom * 100 + 0.5) / 100)
    clientModules.camera.applied = true

    localPlayer.CameraMaxZoomDistance = maxZoom
    localPlayer.CameraMode = clientModules.camera.firstPerson
        and Enum.CameraMode.LockFirstPerson
        or Enum.CameraMode.Classic
    clientModules.camera.refreshVisuals()

    if not silent then
        clientModules.camera.updateStatus(
            string.format(
                "Camera applied: FOV %.1f • Zoom %.1f • First Person: %s",
                fov,
                maxZoom,
                clientModules.camera.firstPerson and "yes" or "no"
            ),
            COLORS.Green
        )
    end

    return true
end

function clientModules.camera.resetSettings(silent)
    clientModules.camera.fov = clientModules.camera.defaultFov
    clientModules.camera.maxZoom = clientModules.camera.defaultMaxZoom
    clientModules.camera.firstPerson = clientModules.camera.defaultMode == Enum.CameraMode.LockFirstPerson
    clientModules.camera.fovBox.Text = tostring(clientModules.camera.fov)
    clientModules.camera.zoomBox.Text = tostring(clientModules.camera.maxZoom)
    clientModules.camera.applied = true

    local camera = workspace.CurrentCamera
    if camera then
        camera.FieldOfView = clientModules.camera.defaultFov
    end
    localPlayer.CameraMaxZoomDistance = clientModules.camera.defaultMaxZoom
    localPlayer.CameraMode = clientModules.camera.defaultMode
    clientModules.camera.refreshVisuals()

    if not silent then
        clientModules.camera.updateStatus("Camera settings restored.", COLORS.Green)
    end
end

function clientModules.camera.loadConfig(data)
    data = type(data) == "table" and data or {}
    clientModules.camera.fov = tonumber(data.fov) or clientModules.camera.defaultFov
    clientModules.camera.maxZoom = tonumber(data.maxZoom) or clientModules.camera.defaultMaxZoom
    clientModules.camera.firstPerson = data.firstPerson == true
    clientModules.camera.fovBox.Text = tostring(clientModules.camera.fov)
    clientModules.camera.zoomBox.Text = tostring(clientModules.camera.maxZoom)
    clientModules.camera.applySettings(true)
end

function clientModules.performance.updateModeVisual()
    clientModules.performance.modeEnabled =
        clientModules.performance.particlesDisabled
        and clientModules.performance.postEffectsDisabled
        and clientModules.performance.shadowsDisabled

    setSwitchVisual(
        clientModules.performance.modeButton,
        clientModules.performance.modeDot,
        clientModules.performance.modeEnabled
    )
end

function clientModules.performance.setModeEnabled(enabled, silent)
    enabled = enabled == true
    clientModules.performance.setParticlesDisabled(enabled, true)
    clientModules.performance.setPostEffectsDisabled(enabled, true)
    clientModules.performance.setShadowsDisabled(enabled, true)
    clientModules.performance.updateModeVisual()

    if not silent then
        clientModules.performance.updateStatus(
            enabled and "Performance Mode enabled." or "Performance Mode disabled."
        )
    end
end

function clientModules.performance.getFpsCapFunction()
    return type(setfpscap) == "function" and setfpscap or nil
end

function clientModules.performance.getCurrentFpsCap()
    if type(getfpscap) == "function" then
        local ok, value = pcall(getfpscap)
        if ok and tonumber(value) then
            return tonumber(value)
        end
    end
    return nil
end

function clientModules.performance.updateFpsSliderVisual()
    local minimum = clientModules.performance.fpsMin
    local maximum = clientModules.performance.fpsMax
    local value = math.clamp(
        tonumber(clientModules.performance.fpsLimit) or 60,
        minimum,
        maximum
    )
    local alpha = (value - minimum) / math.max(maximum - minimum, 1)

    if clientModules.performance.fpsSliderFill then
        clientModules.performance.fpsSliderFill.Size = UDim2.new(alpha, 0, 1, 0)
    end
    if clientModules.performance.fpsSliderKnob then
        clientModules.performance.fpsSliderKnob.Position = UDim2.new(alpha, 0, 0.5, 0)
    end
    if clientModules.performance.fpsBox
        and clientModules.performance.fpsBox.Text ~= tostring(math.floor(value)) then
        clientModules.performance.fpsBox.Text = tostring(math.floor(value))
    end
end

function clientModules.performance.updateFpsStatus(message, color)
    if not clientModules.performance.fpsStatusLabel then
        return
    end

    clientModules.performance.fpsStatusLabel.Text = message
        or (clientModules.performance.fpsLimiterEnabled
            and ("FPS limiter active: " .. tostring(clientModules.performance.fpsLimit) .. " FPS.")
            or "FPS limiter is disabled.")

    clientModules.performance.fpsStatusLabel.TextColor3 = color
        or (clientModules.performance.fpsLimiterEnabled and COLORS.Green or COLORS.MutedText)
end

function clientModules.performance.applyFpsLimit()
    if not clientModules.performance.fpsLimiterEnabled then
        return true
    end

    local setter = clientModules.performance.getFpsCapFunction()
    if not setter then
        clientModules.performance.fpsLimiterEnabled = false
        setSwitchVisual(
            clientModules.performance.fpsLimiterButton,
            clientModules.performance.fpsLimiterDot,
            false
        )
        clientModules.performance.updateFpsStatus(
            "FPS limiter is unavailable: setfpscap is not supported.",
            COLORS.Red
        )
        return false
    end

    local ok = pcall(setter, clientModules.performance.fpsLimit)
    if ok then
        clientModules.performance.updateFpsStatus()
        return true
    end

    clientModules.performance.updateFpsStatus("Failed to apply FPS limit.", COLORS.Red)
    return false
end

function clientModules.performance.setFpsLimit(value, silent)
    value = math.clamp(
        math.floor(tonumber(value) or clientModules.performance.fpsLimit),
        clientModules.performance.fpsMin,
        clientModules.performance.fpsMax
    )

    clientModules.performance.fpsLimit = value
    clientModules.performance.updateFpsSliderVisual()

    if clientModules.performance.fpsLimiterEnabled then
        clientModules.performance.applyFpsLimit()
    elseif not silent then
        clientModules.performance.updateFpsStatus(
            "FPS limit selected: " .. tostring(value) .. " FPS. Limiter is disabled.",
            COLORS.MutedText
        )
    end
end

function clientModules.performance.setFpsLimiterEnabled(enabled, silent)
    enabled = enabled == true

    if enabled and not clientModules.performance.getFpsCapFunction() then
        clientModules.performance.fpsLimiterEnabled = false
        setSwitchVisual(
            clientModules.performance.fpsLimiterButton,
            clientModules.performance.fpsLimiterDot,
            false
        )
        clientModules.performance.updateFpsStatus(
            "FPS limiter is unavailable: setfpscap is not supported.",
            COLORS.Red
        )
        return
    end

    if enabled and not clientModules.performance.fpsLimiterEnabled then
        clientModules.performance.fpsOriginalCap = clientModules.performance.getCurrentFpsCap()
    end

    clientModules.performance.fpsLimiterEnabled = enabled
    setSwitchVisual(
        clientModules.performance.fpsLimiterButton,
        clientModules.performance.fpsLimiterDot,
        enabled
    )

    if enabled then
        clientModules.performance.applyFpsLimit()
    else
        local setter = clientModules.performance.getFpsCapFunction()
        if setter then
            pcall(setter, tonumber(clientModules.performance.fpsOriginalCap) or 999)
        end
        clientModules.performance.fpsOriginalCap = nil

        if not silent then
            clientModules.performance.updateFpsStatus("FPS limiter disabled.", COLORS.MutedText)
        end
    end
end

function clientModules.performance.updateFpsFromPointer(pointerX)
    local track = clientModules.performance.fpsSliderTrack
    if not track or track.AbsoluteSize.X <= 0 then
        return
    end

    local alpha = math.clamp(
        (pointerX - track.AbsolutePosition.X) / track.AbsoluteSize.X,
        0,
        1
    )

    local value = clientModules.performance.fpsMin
        + (clientModules.performance.fpsMax - clientModules.performance.fpsMin) * alpha

    clientModules.performance.setFpsLimit(value, true)
end

function clientModules.performance.isParticleObject(instance)
    return instance:IsA("ParticleEmitter")
        or instance:IsA("Trail")
        or instance:IsA("Beam")
        or instance:IsA("Smoke")
        or instance:IsA("Fire")
        or instance:IsA("Sparkles")
end

function clientModules.performance.isPostEffect(instance)
    return instance:IsA("BloomEffect")
        or instance:IsA("BlurEffect")
        or instance:IsA("ColorCorrectionEffect")
        or instance:IsA("DepthOfFieldEffect")
        or instance:IsA("SunRaysEffect")
end

function clientModules.performance.applyParticleInstance(instance)
    if not clientModules.performance.particlesDisabled
        or not clientModules.performance.isParticleObject(instance) then
        return
    end

    if clientModules.performance.particleCache[instance] == nil then
        local ok, enabled = pcall(function()
            return instance.Enabled
        end)
        if ok then
            clientModules.performance.particleCache[instance] = { enabled = enabled }
        end
    end

    pcall(function()
        instance.Enabled = false
    end)
end

function clientModules.performance.applyPostEffectInstance(instance)
    if not clientModules.performance.postEffectsDisabled
        or not clientModules.performance.isPostEffect(instance) then
        return
    end

    if clientModules.performance.postEffectCache[instance] == nil then
        local ok, enabled = pcall(function()
            return instance.Enabled
        end)
        if ok then
            clientModules.performance.postEffectCache[instance] = { enabled = enabled }
        end
    end

    pcall(function()
        instance.Enabled = false
    end)
end

function clientModules.performance.updateDescendantConnection()
    local needed = clientModules.performance.particlesDisabled
        or clientModules.performance.postEffectsDisabled

    if needed and not clientModules.performance.descendantConnection then
        clientModules.performance.descendantConnection = game.DescendantAdded:Connect(function(instance)
            clientModules.performance.applyParticleInstance(instance)
            clientModules.performance.applyPostEffectInstance(instance)
        end)
    elseif not needed and clientModules.performance.descendantConnection then
        clientModules.performance.descendantConnection:Disconnect()
        clientModules.performance.descendantConnection = nil
    end
end

function clientModules.performance.updateStatus(message)
    local enabledNames = {}
    if clientModules.performance.particlesDisabled then
        table.insert(enabledNames, "particles")
    end
    if clientModules.performance.postEffectsDisabled then
        table.insert(enabledNames, "post-processing")
    end
    if clientModules.performance.shadowsDisabled then
        table.insert(enabledNames, "shadows")
    end

    clientModules.performance.statusLabel.Text = message
        or (#enabledNames > 0
            and ("Disabled locally: " .. table.concat(enabledNames, ", ") .. ".")
            or "Optimization is disabled.")
    clientModules.performance.statusLabel.TextColor3 = #enabledNames > 0 and COLORS.Green or COLORS.MutedText
end

function clientModules.performance.refreshVisuals()
    setSwitchVisual(
        clientModules.performance.particlesButton,
        clientModules.performance.particlesDot,
        clientModules.performance.particlesDisabled
    )
    setSwitchVisual(
        clientModules.performance.postEffectsButton,
        clientModules.performance.postEffectsDot,
        clientModules.performance.postEffectsDisabled
    )
    setSwitchVisual(
        clientModules.performance.shadowsButton,
        clientModules.performance.shadowsDot,
        clientModules.performance.shadowsDisabled
    )
    clientModules.performance.updateModeVisual()
    setSwitchVisual(
        clientModules.performance.fpsLimiterButton,
        clientModules.performance.fpsLimiterDot,
        clientModules.performance.fpsLimiterEnabled
    )
    clientModules.performance.updateFpsSliderVisual()
end

function clientModules.performance.setParticlesDisabled(enabled, silent)
    enabled = enabled == true
    if clientModules.performance.particlesDisabled == enabled then
        clientModules.performance.refreshVisuals()
        return
    end

    clientModules.performance.particlesDisabled = enabled
    if enabled then
        for _, instance in ipairs(game:GetDescendants()) do
            clientModules.performance.applyParticleInstance(instance)
        end
    else
        for instance, record in pairs(clientModules.performance.particleCache) do
            if instance and instance.Parent and record then
                pcall(function()
                    instance.Enabled = record.enabled
                end)
            end
        end
        table.clear(clientModules.performance.particleCache)
    end

    clientModules.performance.updateDescendantConnection()
    clientModules.performance.refreshVisuals()
    if not silent then
        clientModules.performance.updateStatus()
    end
end

function clientModules.performance.setPostEffectsDisabled(enabled, silent)
    enabled = enabled == true
    if clientModules.performance.postEffectsDisabled == enabled then
        clientModules.performance.refreshVisuals()
        return
    end

    clientModules.performance.postEffectsDisabled = enabled
    if enabled then
        for _, instance in ipairs(game:GetDescendants()) do
            clientModules.performance.applyPostEffectInstance(instance)
        end
    else
        for instance, record in pairs(clientModules.performance.postEffectCache) do
            if instance and instance.Parent and record then
                pcall(function()
                    instance.Enabled = record.enabled
                end)
            end
        end
        table.clear(clientModules.performance.postEffectCache)
    end

    clientModules.performance.updateDescendantConnection()
    clientModules.performance.refreshVisuals()
    if not silent then
        clientModules.performance.updateStatus()
    end
end

function clientModules.performance.setShadowsDisabled(enabled, silent)
    enabled = enabled == true
    local lighting = game:GetService("Lighting")

    if enabled and not clientModules.performance.shadowsDisabled then
        clientModules.performance.shadowOriginal = lighting.GlobalShadows
        lighting.GlobalShadows = false
    elseif not enabled and clientModules.performance.shadowsDisabled then
        if clientModules.performance.shadowOriginal ~= nil then
            lighting.GlobalShadows = clientModules.performance.shadowOriginal
        end
        clientModules.performance.shadowOriginal = nil
    end

    clientModules.performance.shadowsDisabled = enabled
    clientModules.performance.refreshVisuals()
    if not silent then
        clientModules.performance.updateStatus()
    end
end

function clientModules.performance.loadConfig(data)
    data = type(data) == "table" and data or {}
    clientModules.performance.setParticlesDisabled(data.particlesDisabled == true, true)
    clientModules.performance.setPostEffectsDisabled(data.postEffectsDisabled == true, true)
    clientModules.performance.setShadowsDisabled(data.shadowsDisabled == true, true)
    clientModules.performance.updateStatus()
end

function clientModules.hud.refreshVisuals()
    setSwitchVisual(clientModules.hud.fpsButton, clientModules.hud.fpsDot, clientModules.hud.showFps)
    setSwitchVisual(
        clientModules.hud.coordinatesButton,
        clientModules.hud.coordinatesDot,
        clientModules.hud.showCoordinates
    )
    setSwitchVisual(clientModules.hud.speedButton, clientModules.hud.speedDot, clientModules.hud.showSpeed)
end

function clientModules.hud.updateStatus()
    local enabledNames = {}
    if clientModules.hud.showFps then
        table.insert(enabledNames, "FPS")
    end
    if clientModules.hud.showCoordinates then
        table.insert(enabledNames, "coordinates")
    end
    if clientModules.hud.showSpeed then
        table.insert(enabledNames, "speed")
    end

    clientModules.hud.statusLabel.Text = #enabledNames > 0
        and ("HUD shows: " .. table.concat(enabledNames, ", ") .. ".")
        or "HUD disabled."
    clientModules.hud.statusLabel.TextColor3 = #enabledNames > 0 and COLORS.Green or COLORS.MutedText
end

function clientModules.hud.render(deltaTime)
    clientModules.hud.updateAccumulator = clientModules.hud.updateAccumulator + deltaTime
    clientModules.hud.fpsAccumulator = clientModules.hud.fpsAccumulator + deltaTime
    clientModules.hud.fpsFrames = clientModules.hud.fpsFrames + 1

    if clientModules.hud.updateAccumulator < 0.1 then
        return
    end

    local instantFps = clientModules.hud.fpsAccumulator > 0
        and (clientModules.hud.fpsFrames / clientModules.hud.fpsAccumulator)
        or 0
    clientModules.hud.currentFps = clientModules.hud.currentFps <= 0
        and instantFps
        or (clientModules.hud.currentFps * 0.75 + instantFps * 0.25)
    clientModules.hud.updateAccumulator = 0
    clientModules.hud.fpsAccumulator = 0
    clientModules.hud.fpsFrames = 0

    local lines = {}
    if clientModules.hud.showFps then
        table.insert(lines, string.format("FPS: %d", math.floor(clientModules.hud.currentFps + 0.5)))
    end

    local character = localPlayer.Character
    local rootPart = character and (character:FindFirstChild("HumanoidRootPart") or character.PrimaryPart)
    if rootPart and rootPart:IsA("BasePart") then
        if clientModules.hud.showCoordinates then
            local position = rootPart.Position
            table.insert(lines, string.format("XYZ: %.1f, %.1f, %.1f", position.X, position.Y, position.Z))
        end
        if clientModules.hud.showSpeed then
            local velocity = rootPart.AssemblyLinearVelocity
            local horizontalSpeed = Vector3.new(velocity.X, 0, velocity.Z).Magnitude
            table.insert(lines, string.format("Speed: %.1f studs/s", horizontalSpeed))
        end
    else
        if clientModules.hud.showCoordinates then
            table.insert(lines, "XYZ: character is not loaded")
        end
        if clientModules.hud.showSpeed then
            table.insert(lines, "Speed: character is not loaded")
        end
    end

    clientModules.hud.overlay.Text = table.concat(lines, "\n")
    clientModules.hud.overlay.Visible = #lines > 0
end

function clientModules.hud.updateConnectionState()
    local enabled = clientModules.hud.showFps
        or clientModules.hud.showCoordinates
        or clientModules.hud.showSpeed

    if enabled and not clientModules.hud.updateConnection then
        clientModules.hud.updateConnection = RunService.RenderStepped:Connect(clientModules.hud.render)
    elseif not enabled and clientModules.hud.updateConnection then
        clientModules.hud.updateConnection:Disconnect()
        clientModules.hud.updateConnection = nil
        clientModules.hud.overlay.Visible = false
        clientModules.hud.overlay.Text = ""
    end
end

function clientModules.hud.setOption(optionName, enabled, silent)
    if optionName == "fps" then
        clientModules.hud.showFps = enabled == true
    elseif optionName == "coordinates" then
        clientModules.hud.showCoordinates = enabled == true
    elseif optionName == "speed" then
        clientModules.hud.showSpeed = enabled == true
    end

    clientModules.hud.refreshVisuals()
    clientModules.hud.updateConnectionState()
    if not silent then
        clientModules.hud.updateStatus()
    end
end

function clientModules.hud.loadConfig(data)
    data = type(data) == "table" and data or {}
    clientModules.hud.showFps = data.showFps == true
    clientModules.hud.showCoordinates = data.showCoordinates == true
    clientModules.hud.showSpeed = data.showSpeed == true
    clientModules.hud.refreshVisuals()
    clientModules.hud.updateConnectionState()
    clientModules.hud.updateStatus()
end

function clientModules.autoSelect.normalize(value)
    local normalized = string.lower(tostring(value or ""))
    normalized = string.gsub(normalized, "[%s_%-%.]", "")
    return normalized
end

function clientModules.autoSelect.findCharacter(gameName)
    local target = clientModules.autoSelect.normalize(gameName)
    for _, characterInfo in ipairs(clientModules.autoSelect.characters) do
        if clientModules.autoSelect.normalize(characterInfo.gameName) == target then
            return characterInfo
        end
    end
    return nil
end

function clientModules.autoSelect.refreshVisuals()
    setSwitchVisual(
        clientModules.autoSelect.toggleButton,
        clientModules.autoSelect.toggleDot,
        clientModules.autoSelect.enabled
    )

    local selectedInfo = clientModules.autoSelect.findCharacter(clientModules.autoSelect.selectedCharacter)
    clientModules.autoSelect.selectedLabel.Text = "Selected Character: "
        .. (selectedInfo and selectedInfo.displayName or "None")

    for gameName, button in pairs(clientModules.autoSelect.characterButtons) do
        local selected = selectedInfo and gameName == selectedInfo.gameName
        button.BackgroundColor3 = selected and COLORS.Green or COLORS.Input
        button.TextColor3 = selected and COLORS.CyanDeep or COLORS.Text
    end
end

function clientModules.autoSelect.selectCharacter(gameName, silent)
    local characterInfo = clientModules.autoSelect.findCharacter(gameName)
    if not characterInfo then
        return false
    end

    clientModules.autoSelect.selectedCharacter = characterInfo.gameName
    clientModules.autoSelect.selectionSerial = clientModules.autoSelect.selectionSerial + 1
    clientModules.autoSelect.refreshVisuals()

    if not silent then
        clientModules.autoSelect.statusLabel.Text = "Selected character: " .. characterInfo.displayName .. "."
        clientModules.autoSelect.statusLabel.TextColor3 = COLORS.Green
    end

    -- Если экран выбора уже открыт, новый персонаж должен заменить предыдущую
    -- незавершённую попытку сразу, без ожидания следующего события ClientUI.
    if clientModules.autoSelect.enabled and clientModules.autoSelect.currentPayload then
        local payload = clientModules.autoSelect.currentPayload
        task.defer(function()
            clientModules.autoSelect.handleCharacterSelect(payload)
        end)
    end

    return true
end

function clientModules.autoSelect.setEnabled(enabled, silent)
    clientModules.autoSelect.enabled = enabled == true
    clientModules.autoSelect.selectionSerial = clientModules.autoSelect.selectionSerial + 1
    clientModules.autoSelect.refreshVisuals()

    if not silent then
        if clientModules.autoSelect.enabled then
            local selectedInfo = clientModules.autoSelect.findCharacter(clientModules.autoSelect.selectedCharacter)
            clientModules.autoSelect.statusLabel.Text = selectedInfo
                and ("Auto Select is enabled for " .. selectedInfo.displayName .. ".")
                or "Auto Select is enabled, but no character is selected."
            clientModules.autoSelect.statusLabel.TextColor3 = selectedInfo and COLORS.Green or COLORS.Yellow
        else
            clientModules.autoSelect.statusLabel.Text = "Auto Select is disabled."
            clientModules.autoSelect.statusLabel.TextColor3 = COLORS.MutedText
        end
    end

    -- Функцию можно включить уже после появления игрового меню выбора.
    -- В таком случае используем сохранённый актуальный payload.
    if clientModules.autoSelect.enabled
        and clientModules.autoSelect.selectedCharacter
        and clientModules.autoSelect.currentPayload then
        local payload = clientModules.autoSelect.currentPayload
        task.defer(function()
            clientModules.autoSelect.handleCharacterSelect(payload)
        end)
    end
end

function clientModules.autoSelect.handleCharacterSelect(payload)
    if not clientModules.autoSelect.enabled or not clientModules.autoSelect.selectedCharacter then
        return
    end

    if type(payload) ~= "table" or payload[1] ~= "CharSelect" then
        return
    end

    local availableCharacters = payload[3]
    if type(availableCharacters) ~= "table" then
        clientModules.autoSelect.statusLabel.Text = "The CharSelect event does not contain a character list."
        clientModules.autoSelect.statusLabel.TextColor3 = COLORS.Red
        return
    end

    local selectedInfo = clientModules.autoSelect.findCharacter(clientModules.autoSelect.selectedCharacter)
    if not selectedInfo then
        return
    end

    local exactGameName = nil
    for _, offeredName in ipairs(availableCharacters) do
        if clientModules.autoSelect.normalize(offeredName)
            == clientModules.autoSelect.normalize(selectedInfo.gameName) then
            exactGameName = tostring(offeredName)
            break
        end
    end

    if not exactGameName then
        clientModules.autoSelect.statusLabel.Text = selectedInfo.displayName
            .. " is not available in the current selection list."
        clientModules.autoSelect.statusLabel.TextColor3 = COLORS.Yellow
        return
    end

    clientModules.autoSelect.selectionSerial = clientModules.autoSelect.selectionSerial + 1
    local serial = clientModules.autoSelect.selectionSerial
    local selectedGameName = selectedInfo.gameName
    local expectedMapName = payload[4]

    clientModules.autoSelect.statusLabel.Text = "Waiting for the game selection screen: "
        .. selectedInfo.displayName .. "..."
    clientModules.autoSelect.statusLabel.TextColor3 = COLORS.Yellow

    task.spawn(function()
        -- В прикреплённой игре обработчик ClientUI сначала ждёт карту, затем
        -- проигрывает переходы и только после этого показывает SelectScreen.
        -- Старый вариант отправлял Voted через 0.45 секунды, то есть слишком рано.
        local deadline = time() + 15
        local selectScreenReady = false

        while time() < deadline do
            if guiDestroyed
                or serial ~= clientModules.autoSelect.selectionSerial
                or not clientModules.autoSelect.enabled
                or clientModules.autoSelect.selectedCharacter ~= selectedGameName then
                return
            end

            local gameUI = playerGui:FindFirstChild("GameUI")
            local charSelect = gameUI and gameUI:FindFirstChild("CharSelect")
            local selectContainer = charSelect and charSelect:FindFirstChild("Select")
            local selectScreen = selectContainer and selectContainer:FindFirstChild("SelectScreen")

            local mapReady = true
            if expectedMapName ~= nil then
                local selectMap = workspace:FindFirstChild("SelectMap")
                mapReady = selectMap ~= nil
                    and selectMap:FindFirstChild(tostring(expectedMapName)) ~= nil
            end

            if mapReady
                and charSelect
                and charSelect.Visible
                and selectScreen
                and selectScreen.Visible then
                selectScreenReady = true
                break
            end

            task.wait(0.1)
        end

        if not selectScreenReady then
            if serial == clientModules.autoSelect.selectionSerial then
                clientModules.autoSelect.statusLabel.Text = "The game selection screen did not become ready in time."
                clientModules.autoSelect.statusLabel.TextColor3 = COLORS.Red
            end
            return
        end

        -- Даём штатному LocalScript один кадр для создания обработчиков выбора.
        RunService.Heartbeat:Wait()

        if guiDestroyed
            or serial ~= clientModules.autoSelect.selectionSerial
            or not clientModules.autoSelect.enabled
            or clientModules.autoSelect.selectedCharacter ~= selectedGameName then
            return
        end

        local replicatedStorage = game:GetService("ReplicatedStorage")
        local takenFolder = replicatedStorage:FindFirstChild("Taken")
        local gameProperties = workspace:FindFirstChild("GameProperties")
        local characterLock = gameProperties and gameProperties:FindFirstChild("CharacterLOCK")

        if characterLock and characterLock.Value
            and takenFolder and takenFolder:FindFirstChild(exactGameName) then
            clientModules.autoSelect.statusLabel.Text = selectedInfo.displayName
                .. " is already taken by another player."
            clientModules.autoSelect.statusLabel.TextColor3 = COLORS.Red
            return
        end

        local remotes = replicatedStorage:FindFirstChild("Remotes")
        local votedRemote = remotes and remotes:FindFirstChild("Voted")
        if not votedRemote or not votedRemote:IsA("RemoteEvent") then
            clientModules.autoSelect.statusLabel.Text = "RemoteEvent Remotes.Voted was not found."
            clientModules.autoSelect.statusLabel.TextColor3 = COLORS.Red
            return
        end

        votedRemote:FireServer(exactGameName)
        clientModules.autoSelect.statusLabel.Text = "Automatically selected: "
            .. selectedInfo.displayName .. "."
        clientModules.autoSelect.statusLabel.TextColor3 = COLORS.Green
    end)
end

function clientModules.autoSelect.handleClientUI(payload)
    if type(payload) ~= "table" then
        return
    end

    if payload[1] == "CharSelect" then
        clientModules.autoSelect.currentPayload = payload
        clientModules.autoSelect.handleCharacterSelect(payload)
    elseif payload[1] == "TitleCard" then
        -- TitleCard означает завершение окна выбора. Старый payload больше
        -- нельзя использовать при последующем включении функции.
        clientModules.autoSelect.currentPayload = nil
        clientModules.autoSelect.selectionSerial = clientModules.autoSelect.selectionSerial + 1
    end
end

function clientModules.autoSelect.initialize()
    task.spawn(function()
        local replicatedStorage = game:GetService("ReplicatedStorage")
        local remotes = replicatedStorage:WaitForChild("Remotes", 15)
        local clientUI = remotes and remotes:WaitForChild("ClientUI", 15)

        if guiDestroyed then
            return
        end

        if not clientUI or not clientUI:IsA("RemoteEvent") then
            clientModules.autoSelect.statusLabel.Text = "RemoteEvent Remotes.ClientUI was not found."
            clientModules.autoSelect.statusLabel.TextColor3 = COLORS.Red
            return
        end

        if clientModules.autoSelect.connection then
            clientModules.autoSelect.connection:Disconnect()
        end

        clientModules.autoSelect.connection = clientUI.OnClientEvent:Connect(
            clientModules.autoSelect.handleClientUI
        )
    end)
end

function clientModules.autoSelect.loadConfig(data)
    data = type(data) == "table" and data or {}
    clientModules.autoSelect.selectedCharacter = nil
    if data.selectedCharacter then
        clientModules.autoSelect.selectCharacter(data.selectedCharacter, true)
    end
    clientModules.autoSelect.setEnabled(data.enabled == true, false)
end

function clientModules.autoSelect.shutdown()
    clientModules.autoSelect.selectionSerial = clientModules.autoSelect.selectionSerial + 1
    clientModules.autoSelect.currentPayload = nil
    if clientModules.autoSelect.connection then
        clientModules.autoSelect.connection:Disconnect()
        clientModules.autoSelect.connection = nil
    end
end

function clientModules.shutdown()
    clientModules.boostTabs.shutdown()
    if clientModules.infFlight and clientModules.infFlight.shutdown then
        clientModules.infFlight.shutdown()
    end
    if clientModules.flight and clientModules.flight.shutdown then
        clientModules.flight.shutdown()
    end
    if clientModules.characterTools and clientModules.characterTools.shutdown then
        clientModules.characterTools.shutdown()
    end
    if clientModules.inventoryOrder and clientModules.inventoryOrder.shutdown then
        clientModules.inventoryOrder.shutdown()
    end
    clientModules.performance.setFpsLimiterEnabled(false, true)
    if clientModules.performance.fpsSliderInputConnection then
        clientModules.performance.fpsSliderInputConnection:Disconnect()
        clientModules.performance.fpsSliderInputConnection = nil
    end
    clientModules.performance.fpsSliderDragging = false
    clientModules.performance.setParticlesDisabled(false, true)
    clientModules.performance.setPostEffectsDisabled(false, true)
    clientModules.performance.setShadowsDisabled(false, true)
    clientModules.hud.showFps = false
    clientModules.hud.showCoordinates = false
    clientModules.hud.showSpeed = false
    clientModules.hud.updateConnectionState()
    clientModules.autoSelect.shutdown()
    if clientModules.combat and clientModules.combat.shutdown then
        clientModules.combat.shutdown()
    end
end

function setAbilityDelayVisual(ability)
    if not ability or not ability.toggleButton or not ability.toggleDot then
        return
    end

    ability.toggleButton.Text = ""

    local enabled = ability.delayEnabled
    ability.toggleButton.BackgroundColor3 = enabled and COLORS.CyanDark or COLORS.Input

    TweenService:Create(ability.toggleDot, TweenInfo.new(0.16), {
        Position = enabled and UDim2.new(1, -24, 0.5, 0) or UDim2.new(0, 4, 0.5, 0),
        BackgroundColor3 = enabled and COLORS.Green or COLORS.MutedText,
    }):Play()
end

function setAbilityCooldownVisual(ability)
    if not ability or not ability.cooldownToggleButton or not ability.cooldownToggleDot then
        return
    end

    setSwitchVisual(
        ability.cooldownToggleButton,
        ability.cooldownToggleDot,
        ability.cooldownEnabled == true
    )
end

function setTabSelected(button, selected, instant)
    local tweenInfo = TweenInfo.new(
        instant and 0 or 0.22,
        Enum.EasingStyle.Quint,
        Enum.EasingDirection.Out
    )

    TweenService:Create(button, tweenInfo, {
        TextColor3 = selected and COLORS.Cyan or COLORS.MutedText,
    }):Play()
end

function clientModules.tabAnimation.moveSelection(button, instant)
    if not button then
        return
    end

    local duration = instant and 0 or 0.28
    local tweenInfo = TweenInfo.new(duration, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)

    TweenService:Create(clientModules.tabAnimation.selectionBackground, tweenInfo, {
        Position = button.Position,
        Size = button.Size,
    }):Play()

    TweenService:Create(clientModules.tabAnimation.selectionBar, tweenInfo, {
        Position = UDim2.fromOffset(0, button.Position.Y.Offset + math.floor(button.Size.Y.Offset / 2)),
    }):Play()
end

function selectTab(tabName)
    local pageByName = {
        Info = clientModules.pages.info,
        Local = localPage,
        Visuals = visualsPage,
        Combat = clientModules.pages.combat,
        Fun = clientModules.pages.fun,
        Performance = clientModules.pages.performance,
        AutoSelect = clientModules.pages.autoSelect,
        KeyList = clientModules.pages.keyList,
        Settings = settingsPage,
    }
    local buttonByName = {
        Info = clientModules.tabs.info,
        Local = localTab,
        Visuals = visualsTab,
        Combat = clientModules.tabs.combat,
        Fun = clientModules.tabs.fun,
        Performance = clientModules.tabs.performance,
        AutoSelect = clientModules.tabs.autoSelect,
        KeyList = clientModules.tabs.keyList,
        Settings = settingsTab,
    }
    local pageTitles = {
        Info = { "OVERVIEW", "Script information and quick overview" },
        Local = { "LOCAL", "Speed, jump and abilities" },
        Visuals = { "VISUALS", "ESP and on-screen status panels" },
        Combat = { "COMBAT", "Auto Aim and Block / Counter assistance" },
        Fun = { "FUN", "Place-specific utilities and client-side effects" },
        Performance = { "PERFORMANCE", "Optimization and FPS limiter" },
        AutoSelect = { "AUTO SELECT", "Automatic Survivor selection" },
        KeyList = { "KEY LIST", "All hotkeys in one place" },
        Settings = { "SETTINGS", "Interface, hotkeys, files and configurations" },
    }

    if ((
            tabName == "Combat"
            or tabName == "Fun"
        ) and not isSpecialTabsAllowed()) then
        return
    end

    local incomingPage = pageByName[tabName]
    local selectedButton = buttonByName[tabName]
    if not incomingPage or not selectedButton then
        return
    end

    local previousName = clientModules.tabAnimation.currentName
    local outgoingPage = clientModules.tabAnimation.currentPage
    local instant = previousName == nil

    setTabSelected(clientModules.tabs.info, tabName == "Info", instant)
    setTabSelected(localTab, tabName == "Local", instant)
    setTabSelected(visualsTab, tabName == "Visuals", instant)
    setTabSelected(clientModules.tabs.fun, tabName == "Fun", instant)
    setTabSelected(clientModules.tabs.performance, tabName == "Performance", instant)
    setTabSelected(clientModules.tabs.autoSelect, tabName == "AutoSelect", instant)
    setTabSelected(clientModules.tabs.keyList, tabName == "KeyList", instant)
    setTabSelected(settingsTab, tabName == "Settings", instant)
    clientModules.tabAnimation.moveSelection(selectedButton, instant)

    if previousName == tabName and outgoingPage == incomingPage then
        return
    end

    clientModules.tabAnimation.serial = clientModules.tabAnimation.serial + 1
    local serial = clientModules.tabAnimation.serial
    local previousOrder = clientModules.tabAnimation.order[previousName] or 0
    local nextOrder = clientModules.tabAnimation.order[tabName] or previousOrder
    local direction = nextOrder >= previousOrder and 1 or -1
    local pageTitle = pageTitles[tabName] or { string.upper(tostring(tabName)), "" }

    if instant or not outgoingPage then
        for _, page in pairs(pageByName) do
            local isIncoming = page == incomingPage
            page.Visible = isIncoming
            page.Position = UDim2.fromOffset(0, isIncoming and 64 or 78)
        end
        incomingPage.CanvasPosition = Vector2.new(0, 0)
        clientModules.header.title.Text = pageTitle[1]
        clientModules.header.subtitle.Text = pageTitle[2]
        clientModules.header.title.TextTransparency = 0
        clientModules.header.subtitle.TextTransparency = 0
    else
        incomingPage.Visible = true
        incomingPage.Position = UDim2.new(direction, 0, 0, 78)
        incomingPage.CanvasPosition = Vector2.new(0, 0)
        incomingPage.ScrollBarImageTransparency = 1

        TweenService:Create(clientModules.header.title, TweenInfo.new(0.10), {
            TextTransparency = 1,
            Position = UDim2.fromOffset(32 - direction * 10, 13),
        }):Play()
        TweenService:Create(clientModules.header.subtitle, TweenInfo.new(0.10), {
            TextTransparency = 1,
            Position = UDim2.fromOffset(32 - direction * 10, 43),
        }):Play()

        task.delay(0.10, function()
            if serial ~= clientModules.tabAnimation.serial or guiDestroyed then
                return
            end

            clientModules.header.title.Text = pageTitle[1]
            clientModules.header.subtitle.Text = pageTitle[2]
            clientModules.header.title.Position = UDim2.fromOffset(32 + direction * 10, 13)
            clientModules.header.subtitle.Position = UDim2.fromOffset(32 + direction * 10, 43)

            TweenService:Create(clientModules.header.title, TweenInfo.new(0.20, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), {
                TextTransparency = 0,
                Position = UDim2.fromOffset(32, 13),
            }):Play()
            TweenService:Create(clientModules.header.subtitle, TweenInfo.new(0.20, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), {
                TextTransparency = 0,
                Position = UDim2.fromOffset(32, 43),
            }):Play()
        end)

        local transitionInfo = TweenInfo.new(0.32, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
        TweenService:Create(outgoingPage, transitionInfo, {
            Position = UDim2.new(-direction, 0, 0, 78),
            ScrollBarImageTransparency = 1,
        }):Play()
        local incomingTween = TweenService:Create(incomingPage, transitionInfo, {
            Position = UDim2.fromOffset(0, 64),
            ScrollBarImageTransparency = 0.25,
        })
        incomingTween:Play()

        task.spawn(function()
            incomingTween.Completed:Wait()
            if serial ~= clientModules.tabAnimation.serial or guiDestroyed then
                return
            end

            for _, page in pairs(pageByName) do
                if page ~= incomingPage then
                    page.Visible = false
                    page.Position = UDim2.fromOffset(0, 78)
                    page.ScrollBarImageTransparency = 0.25
                end
            end
        end)
    end

    clientModules.tabAnimation.currentName = tabName
    clientModules.tabAnimation.currentPage = incomingPage
end

function relayoutSidebarTabs()
    local orderedTabs = {
        clientModules.tabs.info,
        localTab,
        visualsTab,
        clientModules.tabs.combat,
        clientModules.tabs.fun,
        clientModules.tabs.performance,
        clientModules.tabs.autoSelect,
        clientModules.tabs.keyList,
        settingsTab,
    }

    local y = 14

    for _, button in ipairs(orderedTabs) do
        if button then
            local visible = button.Visible

            if visible then
                button.Position = UDim2.fromOffset(12, y)
                y = y + 52
            end
        end
    end

    -- Keep the animated selection in sync with the compacted sidebar.
    local selectedName = clientModules.tabAnimation.currentName
    local selectedButton = selectedName and ({
        Info = clientModules.tabs.info,
        Local = localTab,
        Visuals = visualsTab,
        Combat = clientModules.tabs.combat,
        Fun = clientModules.tabs.fun,
        Performance = clientModules.tabs.performance,
        AutoSelect = clientModules.tabs.autoSelect,
        KeyList = clientModules.tabs.keyList,
        Settings = settingsTab,
    })[selectedName]

    if selectedButton and selectedButton.Visible then
        clientModules.tabAnimation.selectionBackground.Position = selectedButton.Position
        clientModules.tabAnimation.selectionBar.Position =
            UDim2.fromOffset(0, selectedButton.Position.Y.Offset + 23)
    end
end

function refreshSpecialTabsVisibility()
    local allowed = isSpecialTabsAllowed()

    clientModules.specialTabsAllowed = allowed

    clientModules.tabs.combat.Visible = allowed
    clientModules.tabs.fun.Visible = allowed

    -- Repack the sidebar so hidden special tabs do not leave empty slots.
    relayoutSidebarTabs()

    clientModules.pages.combat.Visible = allowed and clientModules.tabAnimation.currentName == "Combat"
    clientModules.pages.fun.Visible = allowed and clientModules.tabAnimation.currentName == "Fun"

    if not allowed
        and (
            clientModules.tabAnimation.currentName == "Combat"
            or clientModules.tabAnimation.currentName == "Fun"
        ) then
        selectTab("Info")
    end

    relayoutSidebarTabs()
end

function normalizeCharacterName(value)
    local normalized = string.lower(tostring(value or ""))
    normalized = string.gsub(normalized, "[%s_%-%.]", "")
    return normalized
end

function clientModules.infFlight.refreshVisuals()
    local button = clientModules.infFlight.button
    if not button then
        return
    end

    button.Text = "Inf Flight"
    button.BackgroundColor3 = clientModules.infFlight.enabled and COLORS.Green or COLORS.CyanDark
    button.TextColor3 = clientModules.infFlight.enabled and COLORS.CyanDeep or COLORS.Text
end

function clientModules.infFlight.isCharacterFlying(character, rootPart)
    if not clientModules.infFlight.enabled then
        return false
    end

    character = character or localPlayer.Character
    if not character or not character.Parent then
        return false
    end

    rootPart = rootPart
        or character:FindFirstChild("HumanoidRootPart")
        or character.PrimaryPart

    if not rootPart or not rootPart:IsA("BasePart") then
        return false
    end

    local animate = character:FindFirstChild("Animate")
    local animationState = animate and animate:GetAttribute("AnimationState")
    if string.lower(tostring(animationState or "")) == "flying" then
        return true
    end

    -- Silver/Fleetway create these two objects only while their flight is active.
    return rootPart:FindFirstChildOfClass("BodyVelocity") ~= nil
        and rootPart:FindFirstChildOfClass("BodyGyro") ~= nil
end

function clientModules.infFlight.clearLabelConnections()
    for _, connection in ipairs(clientModules.infFlight.labelConnections) do
        if connection then
            connection:Disconnect()
        end
    end

    clientModules.infFlight.labelConnections = {}
end

function clientModules.infFlight.removeKillTag(character)
    if not character then
        return
    end

    pcall(function()
        character:RemoveTag("Kill")
    end)
end

function clientModules.infFlight.lockText(label, serial)
    if not label or not label.Parent then
        return
    end

    pcall(function()
        label.Text = "inf"
    end)

    local connection = label:GetPropertyChangedSignal("Text"):Connect(function()
        if guiDestroyed
            or not clientModules.infFlight.enabled
            or serial ~= clientModules.infFlight.serial
            or not label.Parent then
            return
        end

        if label.Text ~= "inf" then
            label.Text = "inf"
        end
    end)

    table.insert(clientModules.infFlight.labelConnections, connection)
end

function clientModules.infFlight.applyCharacter(character, serial)
    if not character
        or serial ~= clientModules.infFlight.serial
        or not clientModules.infFlight.enabled then
        return
    end

    local rootPart = character:WaitForChild("HumanoidRootPart", 8)
    if not rootPart or serial ~= clientModules.infFlight.serial then
        return
    end

    local billboard = rootPart:WaitForChild("BillboardGui", 8)
    local frame = billboard and billboard:WaitForChild("Frame", 8)
    local amount = frame and frame:WaitForChild("Amount", 8)
    local maximum = frame and frame:WaitForChild("Maximum", 8)

    if not amount or not maximum or serial ~= clientModules.infFlight.serial then
        if clientModules.infFlight.enabled then
            setStatus("Inf Flight UI was not found on the current character.", COLORS.Yellow)
        end
        return
    end

    clientModules.infFlight.clearLabelConnections()
    clientModules.infFlight.lockText(amount, serial)
    clientModules.infFlight.lockText(maximum, serial)
    setStatus("Inf Flight enabled for " .. tostring(character:GetAttribute("Character") or "character") .. ".", COLORS.Green)
end

function clientModules.infFlight.runTagLoop(serial)
    while not guiDestroyed
        and clientModules.infFlight.enabled
        and serial == clientModules.infFlight.serial do
        local character = localPlayer.Character

        if character then
            pcall(function()
                character:AddTag("Kill")
            end)

            -- The game adds a large amount of flight energy on each tag event.
            -- Pulsing every frame is unnecessary and can interfere with movement scripts.
            task.wait(0.05)
            clientModules.infFlight.removeKillTag(character)
            task.wait(0.45)
        else
            task.wait(0.1)
        end
    end

    clientModules.infFlight.removeKillTag(localPlayer.Character)
end

function clientModules.infFlight.setEnabled(enabled, silent)
    enabled = enabled == true
    clientModules.infFlight.serial = clientModules.infFlight.serial + 1
    local serial = clientModules.infFlight.serial

    clientModules.infFlight.clearLabelConnections()
    clientModules.infFlight.removeKillTag(localPlayer.Character)
    clientModules.infFlight.enabled = enabled
    clientModules.infFlight.refreshVisuals()

    if not clientModules.infFlight.characterConnection then
        clientModules.infFlight.characterConnection = localPlayer.CharacterAdded:Connect(function(character)
            if clientModules.infFlight.enabled then
                local currentSerial = clientModules.infFlight.serial
                task.spawn(function()
                    clientModules.infFlight.applyCharacter(character, currentSerial)
                end)
            end
        end)
    end

    if enabled then
        local character = localPlayer.Character
        if character then
            task.spawn(function()
                clientModules.infFlight.applyCharacter(character, serial)
            end)
        end

        task.spawn(function()
            clientModules.infFlight.runTagLoop(serial)
        end)

        if not silent then
            setStatus("Inf Flight enabled. Works only for Silver and Fleetway.", COLORS.Green)
        end
    elseif not silent then
        setStatus("Inf Flight disabled.", COLORS.MutedText)
    end
end

function clientModules.infFlight.shutdown()
    clientModules.infFlight.setEnabled(false, true)

    if clientModules.infFlight.characterConnection then
        clientModules.infFlight.characterConnection:Disconnect()
        clientModules.infFlight.characterConnection = nil
    end
end

function clientModules.flight.getSpeed()
    local value = tonumber(clientModules.flight.speedBox and clientModules.flight.speedBox.Text)

    if not value then
        value = clientModules.flight.speed or DEFAULT_FLIGHT_SPEED
    end

    value = math.clamp(math.floor(value), MIN_FLIGHT_SPEED, MAX_FLIGHT_SPEED)
    clientModules.flight.speed = value

    if clientModules.flight.speedBox and clientModules.flight.speedBox.Parent then
        clientModules.flight.speedBox.Text = tostring(value)
    end

    return value
end

function clientModules.flight.updateSliderVisual()
    local track = clientModules.flight.sliderTrack
    if not track or track.AbsoluteSize.X <= 0 then
        return
    end

    local value = clientModules.flight.getSpeed()
    local alpha = (value - MIN_FLIGHT_SPEED)
        / math.max(MAX_FLIGHT_SPEED - MIN_FLIGHT_SPEED, 1)

    if clientModules.flight.sliderFill then
        clientModules.flight.sliderFill.Size = UDim2.new(alpha, 0, 1, 0)
    end

    if clientModules.flight.sliderKnob then
        clientModules.flight.sliderKnob.Position = UDim2.new(alpha, 0, 0.5, 0)
    end
end

function clientModules.flight.setSpeed(value, silent)
    value = tonumber(value)

    if not value then
        value = clientModules.flight.speed or DEFAULT_FLIGHT_SPEED
    end

    value = math.clamp(math.floor(value), MIN_FLIGHT_SPEED, MAX_FLIGHT_SPEED)
    clientModules.flight.speed = value

    if clientModules.flight.speedBox and clientModules.flight.speedBox.Parent then
        clientModules.flight.speedBox.Text = tostring(value)
    end

    clientModules.flight.updateSliderVisual()

    if not silent and clientModules.flight.statusLabel then
        clientModules.flight.statusLabel.Text = string.format(
            "Flight %s. Speed: %d studs/s.",
            clientModules.flight.enabled and "enabled" or "disabled",
            value
        )
        clientModules.flight.statusLabel.TextColor3 =
            clientModules.flight.enabled and COLORS.Green or COLORS.MutedText
    end
end

function clientModules.flight.updateSpeedFromPointer(pointerX)
    local track = clientModules.flight.sliderTrack
    if not track or track.AbsoluteSize.X <= 0 then
        return
    end

    local alpha = math.clamp(
        (pointerX - track.AbsolutePosition.X) / track.AbsoluteSize.X,
        0,
        1
    )

    local value = MIN_FLIGHT_SPEED
        + (MAX_FLIGHT_SPEED - MIN_FLIGHT_SPEED) * alpha

    clientModules.flight.setSpeed(value, true)
end

function clientModules.flight.refreshVisuals()
    local button = clientModules.flight.toggleButton
    if not button then
        return
    end

    local keyName = clientModules.keyList
        and clientModules.keyList.state
        and clientModules.keyList.state.flightKey
        and clientModules.keyList.state.flightKey.Name
        or DEFAULT_FLIGHT_KEY.Name

    button.Text = "FLIGHT    •    " .. keyName
    button.BackgroundColor3 = clientModules.flight.enabled and COLORS.Green or COLORS.CyanDark
    button.TextColor3 = clientModules.flight.enabled and COLORS.CyanDeep or COLORS.Text
end

function clientModules.flight.stopController()
    if clientModules.flight.renderConnection then
        clientModules.flight.renderConnection:Disconnect()
        clientModules.flight.renderConnection = nil
    end

    if clientModules.flight.diedConnection then
        clientModules.flight.diedConnection:Disconnect()
        clientModules.flight.diedConnection = nil
    end

    if clientModules.flight.bodyVelocity then
        clientModules.flight.bodyVelocity:Destroy()
        clientModules.flight.bodyVelocity = nil
    end

    if clientModules.flight.bodyGyro then
        clientModules.flight.bodyGyro:Destroy()
        clientModules.flight.bodyGyro = nil
    end

    local humanoid = clientModules.flight.controlledHumanoid

    if humanoid and humanoid.Parent then
        humanoid.PlatformStand = clientModules.flight.savedPlatformStand
        humanoid.AutoRotate = clientModules.flight.savedAutoRotate
    end

    clientModules.flight.controlledHumanoid = nil
end

function clientModules.flight.startController(character)
    clientModules.flight.stopController()

    if not character or not character.Parent or not clientModules.flight.enabled then
        return false
    end

    local humanoid = character:FindFirstChildOfClass("Humanoid")
    local rootPart = character:FindFirstChild("HumanoidRootPart")

    if not humanoid or not rootPart then
        clientModules.flight.enabled = false
        clientModules.flight.refreshVisuals()
        return false
    end

    clientModules.flight.savedPlatformStand = humanoid.PlatformStand
    clientModules.flight.savedAutoRotate = humanoid.AutoRotate
    clientModules.flight.controlledHumanoid = humanoid

    humanoid.PlatformStand = true
    humanoid.AutoRotate = false

    local bodyGyro = Instance.new("BodyGyro")
    bodyGyro.Name = "PulseCoreFlightGyro"
    bodyGyro.P = 90000
    bodyGyro.D = 1000
    bodyGyro.MaxTorque = Vector3.new(9e9, 9e9, 9e9)
    bodyGyro.CFrame = rootPart.CFrame
    bodyGyro.Parent = rootPart

    local bodyVelocity = Instance.new("BodyVelocity")
    bodyVelocity.Name = "PulseCoreFlightVelocity"
    bodyVelocity.P = 9000
    bodyVelocity.MaxForce = Vector3.new(9e9, 9e9, 9e9)
    bodyVelocity.Velocity = Vector3.zero
    bodyVelocity.Parent = rootPart

    clientModules.flight.bodyGyro = bodyGyro
    clientModules.flight.bodyVelocity = bodyVelocity

    clientModules.flight.diedConnection = humanoid.Died:Connect(function()
        if clientModules.flight.enabled then
            clientModules.flight.setEnabled(false, false)
        end
    end)

    clientModules.flight.renderConnection = RunService.RenderStepped:Connect(function()
        if not clientModules.flight.enabled
            or not character.Parent
            or humanoid.Health <= 0
            or not rootPart.Parent
            or not bodyVelocity.Parent
            or not bodyGyro.Parent then
            return
        end

        local camera = workspace.CurrentCamera
        if not camera then
            return
        end

        local direction = Vector3.zero

        if UserInputService:IsKeyDown(Enum.KeyCode.W) then
            direction = direction + camera.CFrame.LookVector
        end
        if UserInputService:IsKeyDown(Enum.KeyCode.S) then
            direction = direction - camera.CFrame.LookVector
        end
        if UserInputService:IsKeyDown(Enum.KeyCode.D) then
            direction = direction + camera.CFrame.RightVector
        end
        if UserInputService:IsKeyDown(Enum.KeyCode.A) then
            direction = direction - camera.CFrame.RightVector
        end
        if UserInputService:IsKeyDown(Enum.KeyCode.Space) then
            direction = direction + Vector3.yAxis
        end
        if UserInputService:IsKeyDown(Enum.KeyCode.LeftControl) then
            direction = direction - Vector3.yAxis
        end

        -- Gamepad / touch movement can still come through Humanoid.MoveDirection.
        if direction.Magnitude <= 0.001 and humanoid.MoveDirection.Magnitude > 0.001 then
            direction = humanoid.MoveDirection
        end

        if direction.Magnitude > 0.001 then
            direction = direction.Unit * clientModules.flight.getSpeed()
        else
            direction = Vector3.zero
        end

        bodyVelocity.Velocity = direction
        bodyGyro.CFrame = camera.CFrame
    end)

    clientModules.flight.refreshVisuals()
    clientModules.flight.statusLabel.Text = string.format(
        "Flight enabled. Speed: %d studs/s • WASD / Space / LeftControl.",
        clientModules.flight.getSpeed()
    )
    clientModules.flight.statusLabel.TextColor3 = COLORS.Green

    return true
end

function clientModules.flight.setEnabled(enabled, silent)
    enabled = enabled == true
    clientModules.flight.stopController()
    clientModules.flight.enabled = enabled

    if not clientModules.flight.characterConnection then
        clientModules.flight.characterConnection = localPlayer.CharacterAdded:Connect(function(character)
            if clientModules.flight.enabled then
                task.defer(function()
                    clientModules.flight.startController(character)
                end)
            end
        end)
    end

    if enabled then
        local character = localPlayer.Character
        if character then
            clientModules.flight.startController(character)
        end
    elseif not silent and clientModules.flight.statusLabel then
        clientModules.flight.statusLabel.Text = "Flight disabled."
        clientModules.flight.statusLabel.TextColor3 = COLORS.MutedText
    end

    clientModules.flight.refreshVisuals()

    if enabled and not silent and clientModules.flight.statusLabel then
        clientModules.flight.statusLabel.Text = string.format(
            "Flight enabled. Speed: %d studs/s • WASD / Space / LeftControl.",
            clientModules.flight.getSpeed()
        )
        clientModules.flight.statusLabel.TextColor3 = COLORS.Green
    end
end

function clientModules.flight.shutdown()
    clientModules.flight.setEnabled(false, true)

    if clientModules.flight.characterConnection then
        clientModules.flight.characterConnection:Disconnect()
        clientModules.flight.characterConnection = nil
    end

    if clientModules.flight.sliderInputConnection then
        clientModules.flight.sliderInputConnection:Disconnect()
        clientModules.flight.sliderInputConnection = nil
    end
end

-- ============================================================================
-- PulseCore ESP: MODEL-NAME MODE
-- ============================================================================
-- The ESP does NOT depend on folders such as Players / Survivors / EXE.
-- It searches every Model in Workspace and classifies it by its exact
-- normalized model name.
--
-- Survivors:
--   Sonic, Tails, Knuckles, Eggman, Amy, Cream, Blaze, Silver, Metal Sonic
--
-- Executioners:
--   2011X, Kolossos, Tripwire, Fleetway, MSS
--
-- Temporary mode: classification uses ONLY the normalized model name.
-- ============================================================================

-- ESP classification mode: ability markers only.
-- Internal aliases below are based on the supplied game's .rbxl structure.
ESP_MODEL_ROLE_NAMES = {
    sonic = "Survivor",
    tails = "Survivor",
    knuckles = "Survivor",
    eggman = "Survivor",
    amy = "Survivor",
    cream = "Survivor",
    blaze = "Survivor",
    silver = "Survivor",
    metalsonic = "Survivor",

    ["2011x"] = "Executioner",
    kolossos = "Executioner",
    tripwire = "Executioner",
    fleetway = "Executioner",
    mss = "Executioner",
}

-- ESP classification is ability-name-only.
function normalizeESPModelName(name)
    -- Normalize model names case-insensitively and ignore punctuation.
    return string.lower(tostring(name or "")):gsub("[^%w]+", "")
end

function getESPGroupByModelName(name)
    return ESP_MODEL_ROLE_NAMES[normalizeESPModelName(name)]
end

-- Keep the old function name for compatibility with any existing PulseCore
-- code, but now it classifies MODEL NAMES rather than folder names.
function normalizeESPContainerName(name)
    return normalizeESPModelName(name)
end

function getESPGroupByName(name)
    return getESPGroupByModelName(name)
end

function isLocalCharacterModel(model)
    if not model or not model:IsA("Model") then
        return false
    end

    if model == localPlayer.Character then
        return true
    end

    -- Roblox can expose the same player character through another container.
    local okPlayer, owner = pcall(function()
        return Players:GetPlayerFromCharacter(model)
    end)

    if okPlayer and owner == localPlayer then
        return true
    end

    -- Some custom character systems clone Player.Character into Workspace.Players
    -- without registering it through Players:GetPlayerFromCharacter().
    if model.Name == localPlayer.Name then
        return true
    end

    local localUserId = tostring(localPlayer.UserId)

    for _, attributeName in ipairs({"UserId", "PlayerUserId", "UserID"}) do
        local value = model:GetAttribute(attributeName)
        if value ~= nil and tostring(value) == localUserId then
            return true
        end
    end

    -- Custom games sometimes keep an ObjectValue pointing back to the Player.
    for _, descendant in ipairs(model:GetDescendants()) do
        if descendant:IsA("ObjectValue") and descendant.Value == localPlayer then
            return true
        end
    end

    return false
end

function getESPRootPart(model)
    if not model then
        return nil
    end

    local root = model:FindFirstChild("HumanoidRootPart", true)
        or model:FindFirstChild("UpperTorso", true)
        or model:FindFirstChild("Torso", true)
        or model:FindFirstChild("Head", true)

    if root and root:IsA("BasePart") then
        return root
    end

    for _, descendant in ipairs(model:GetDescendants()) do
        if descendant:IsA("BasePart") then
            return descendant
        end
    end

    return nil
end

function getESPHumanoid(model)
    if not model then
        return nil
    end

    local humanoid = model:FindFirstChildOfClass("Humanoid")
    if humanoid then
        return humanoid
    end

    for _, descendant in ipairs(model:GetDescendants()) do
        if descendant:IsA("Humanoid") then
            return descendant
        end
    end

    return nil
end

function isESPModelDead(model)
    if not model or not model.Parent then
        return true
    end

    local humanoid = getESPHumanoid(model)

    if humanoid and humanoid.Health <= 0 then
        return true
    end

    local deadAttributeNames = {
        "Dead",
        "IsDead",
        "Died",
        "Eliminated",
    }

    for _, attributeName in ipairs(deadAttributeNames) do
        local value = model:GetAttribute(attributeName)

        if value == true or (type(value) == "string" and string.lower(value) == "dead") then
            return true
        end
    end

    for _, descendant in ipairs(model:GetDescendants()) do
        if descendant:IsA("BoolValue") then
            local normalized = normalizeESPModelName(descendant.Name)

            if (
                normalized == "dead"
                or normalized == "isdead"
                or normalized == "died"
                or normalized == "eliminated"
            ) and descendant.Value
            then
                return true
            end
        elseif descendant:IsA("StringValue") then
            local normalized = normalizeESPModelName(descendant.Name)
            local value = string.lower(tostring(descendant.Value or ""))

            if (
                normalized == "status"
                or normalized == "state"
                or normalized == "playerstatus"
                or normalized == "survivorstatus"
            ) and value:find("dead", 1, true)
            then
                return true
            end
        end
    end

    return false
end

function getESPStatusText(model)
    if isESPModelDead(model) then
        return "Dead"
    end

    local statusNames = {
        "Status",
        "State",
        "PlayerStatus",
        "SurvivorStatus",
        "CharacterStatus",
    }

    for _, attributeName in ipairs(statusNames) do
        local value = model:GetAttribute(attributeName)

        if type(value) == "string" and value ~= "" then
            return value
        end
    end

    for _, descendant in ipairs(model:GetDescendants()) do
        if descendant:IsA("StringValue") then
            local normalized = normalizeESPModelName(descendant.Name)

            if (
                normalized == "status"
                or normalized == "state"
                or normalized == "playerstatus"
                or normalized == "survivorstatus"
                or normalized == "characterstatus"
            ) and descendant.Value ~= ""
            then
                return tostring(descendant.Value)
            end
        end
    end

    local humanoid = getESPHumanoid(model)

    if humanoid then
        local stateName = humanoid:GetState().Name

        if stateName ~= "Running"
            and stateName ~= "RunningNoPhysics"
            and stateName ~= "GettingUp"
            and stateName ~= "Standing"
        then
            return stateName
        end
    end

    return "Alive"
end

function getESPHealthText(model)
    local humanoid = getESPHumanoid(model)

    if not humanoid then
        return "HP: ?"
    end

    return string.format(
        "HP: %.0f / %.0f",
        math.max(0, humanoid.Health),
        math.max(0, humanoid.MaxHealth)
    )
end

ESP_DISPLAY_ABILITY_SETS = {
    Sonic = {
        { label = "Drop Dash", markers = {"dropdash"} },
        { label = "Peelout", markers = {"peelout"} },
    },
    Tails = {
        { label = "Laser Canon", markers = {"lasercanon", "lasercannon", "canon"} },
        { label = "Glide", markers = {"glide"} },
    },
    Knuckles = {
        { label = "Punch", markers = {"punch"} },
        { label = "Counter", markers = {"counter"} },
    },
    Eggman = {
        { label = "Jetpack Boost", markers = {"jetpackboost", "jetpack"} },
        { label = "Energy Shield", markers = {"energyshield"} },
    },
    Amy = {
        { label = "Hammer Throw", markers = {"hammerthrow", "hammer"} },
        { label = "Reroll", markers = {"reroll"} },
    },
    Cream = {
        { label = "Heal", markers = {"heal", "healloop"} },
        { label = "Dash", markers = {"dash"} },
    },
    Blaze = {
        { label = "Sol Flame", markers = {"flamestart", "flameloop", "flameend"} },
        { label = "Burning Javelin", markers = {"float"} },
    },
    Silver = {
        { label = "Rock", markers = {"aim", "rocksr", "rocks", "rock"} },
        { label = "Suspension", markers = {"timereversal", "timereversall"} },
    },
    ["Metal Sonic"] = {
        { label = "Destructive Charge", markers = {"destructivecharge", "desturctivecharge", "dashstart"} },
        { label = "Self Repair", markers = {"selfrepair"} },
    },
    Tripwire = {
        { label = "Brighter Day", markers = {"brighterday"} },
        { label = "Reachout", markers = {"reachout"} },
    },
    Fleetway = {
        { label = "Lasers of Destrucation", markers = {"lasersofdestrucation", "lasersofdestruction"} },
        { label = "Chaos Dash", markers = {"chaosdash", "chargedash"} },
        { label = "Fateful Drain", markers = {"fatefuldrain"} },
        { label = "Burst", markers = {"burst"} },
    },
    ["2011x"] = {
        { label = "Charge", markers = {"charge"} },
        { label = "God's Trickery", markers = {"godstrickery"} },
        { label = "Invisibility", markers = {"invisibility", "invisiblity", "invis"} },
        { label = "Rage Mode", markers = {"ragemode", "rage"} },
    },
    Kolossos = {
        { label = "Grab", markers = {"grab"} },
        { label = "Block", markers = {"block"} },
    },
}

function getESPCharacterAbilityNames(characterName)
    return ESP_DISPLAY_ABILITY_SETS[characterName] or {}
end

function getESPAbilityCooldownInfo(model, abilityDefinition)
    if not model or not abilityDefinition then
        return nil, false
    end

    local cache = espAbilityCooldownCache[model]
    if not cache then
        return nil, false
    end

    local remaining = 0
    local cooldownWithoutTimer = false

    for _, marker in ipairs(abilityDefinition.markers or {}) do
        local key = normalizeESPMarkerName(marker)
        local value = cache[key]

        if type(value) == "number" then
            local seconds = value - time()

            if seconds > remaining then
                remaining = seconds
            end
        elseif value == true then
            cooldownWithoutTimer = true
        end
    end

    if remaining > 0 then
        return remaining, true
    end

    if cooldownWithoutTimer then
        return nil, true
    end

    return 0, false
end

function formatESPAbilityState(abilityName, remaining, cooldownActive)
    if cooldownActive then
        if remaining and remaining > 0 then
            return abilityName .. "  |  CD " .. string.format("%.1fs", remaining)
        end

        return abilityName .. "  |  CD"
    end

    return abilityName .. "  |  READY"
end

function refreshESPInfoWindow()
    if not (espInfoGui and espInfoWindow and espInfoScroll) then
        return
    end

    for _, child in ipairs(espInfoScroll:GetChildren()) do
        if child:IsA("TextLabel") then
            child:Destroy()
        end
    end

    local localRoot = getESPRootPart(localPlayer.Character)
    local ordered = {}

    for model, record in pairs(trackedModels) do
        if model
            and model.Parent
            and record
            and not isESPModelDead(model)
        then
            table.insert(ordered, {
                model = model,
                record = record,
            })
        end
    end

    table.sort(ordered, function(left, right)
        return string.lower(left.record.displayName or left.model.Name)
            < string.lower(right.record.displayName or right.model.Name)
    end)

    if #ordered == 0 then
        addESPInfoEntry(
            "No living tracked characters.",
            COLORS.MutedText,
            1
        )
        return
    end

    for index, item in ipairs(ordered) do
        local model = item.model
        local record = item.record
        local root = getESPRootPart(model)
        local lines = {
            record.displayName .. "  [" .. record.group .. "]",
        }

        if espDistanceEnabled and localRoot and root then
            local distance = (localRoot.Position - root.Position).Magnitude
            table.insert(lines, string.format("Distance: %.1f studs", distance))
        end

        if record.group == "Survivor" and espSurvivorInfoEnabled then
            table.insert(lines, getESPHealthText(model))
            table.insert(lines, "Status: " .. getESPStatusText(model))
        end

        if espAbilitiesEnabled then
            local abilityDefinitions = getESPCharacterAbilityNames(record.displayName)

            if #abilityDefinitions > 0 then
                table.insert(lines, "")

                for _, abilityDefinition in ipairs(abilityDefinitions) do
                    local remaining, cooldownActive =
                        getESPAbilityCooldownInfo(model, abilityDefinition)

                    table.insert(
                        lines,
                        formatESPAbilityState(
                            abilityDefinition.label,
                            remaining,
                            cooldownActive
                        )
                    )
                end
            end
        end

        addESPInfoEntry(
            table.concat(lines, "\n"),
            record.group == "Executioner" and COLORS.ESPRed or COLORS.ESPBlue,
            index
        )
    end
end

function refreshESPAbilityCooldownCache()
    table.clear(espAbilityCooldownCache)

    local now = time()

    for model, record in pairs(trackedModels) do
        if model
            and model.Parent
            and record
            and not isESPModelDead(model)
        then
            local characterAbilities = getESPCharacterAbilityNames(record.displayName)
            local modelCache = {}
            local markerSet = {}

            for _, abilityDefinition in ipairs(characterAbilities) do
                for _, marker in ipairs(abilityDefinition.markers or {}) do
                    markerSet[normalizeESPMarkerName(marker)] = true
                end
            end

            -- Exactly one descendant walk per tracked model per refresh.
            for _, object in ipairs(model:GetDescendants()) do
                local objectName = normalizeESPMarkerName(object.Name)
                local objectAbilityMarkers = {}

                for marker in pairs(markerSet) do
                    if objectName == marker
                        or objectName:find(marker, 1, true)
                    then
                        table.insert(objectAbilityMarkers, marker)
                    end
                end

                for attributeName, attributeValue in pairs(object:GetAttributes()) do
                    local key = normalizeESPMarkerName(attributeName)

                    local isCooldownKey =
                        key == "cooldown"
                        or key == "cd"
                        or key:find("cooldown", 1, true) ~= nil
                        or key:find("remaining", 1, true) ~= nil

                    if isCooldownKey then
                        local targets = objectAbilityMarkers

                        if #targets == 0 then
                            for marker in pairs(markerSet) do
                                if key:find(marker, 1, true) then
                                    table.insert(targets, marker)
                                end
                            end
                        end

                        if type(attributeValue) == "number" then
                            local number = tonumber(attributeValue)
                            local cooldownUntil

                            if number and number > 0 then
                                if number > now + 1 then
                                    cooldownUntil = number
                                else
                                    cooldownUntil = now + number
                                end
                            end

                            if cooldownUntil then
                                if #targets == 0 then
                                    for marker in pairs(markerSet) do
                                        modelCache[marker] = math.max(
                                            modelCache[marker] or 0,
                                            cooldownUntil
                                        )
                                    end
                                else
                                    for _, marker in ipairs(targets) do
                                        modelCache[marker] = math.max(
                                            modelCache[marker] or 0,
                                            cooldownUntil
                                        )
                                    end
                                end
                            end
                        elseif attributeValue == true then
                            if #targets == 0 then
                                for marker in pairs(markerSet) do
                                    modelCache[marker] = true
                                end
                            else
                                for _, marker in ipairs(targets) do
                                    modelCache[marker] = true
                                end
                            end
                        end
                    end
                end

                for _, child in ipairs(object:GetChildren()) do
                    local childName = normalizeESPMarkerName(child.Name)

                    if childName == "cooldown"
                        or childName == "cd"
                        or childName:find("cooldown", 1, true)
                        or childName:find("remaining", 1, true)
                    then
                        local number = nil

                        if child:IsA("NumberValue") or child:IsA("IntValue") then
                            number = tonumber(child.Value)
                        end

                        if number then
                            local cooldownUntil

                            if number > 0 then
                                if number > now + 1 then
                                    cooldownUntil = number
                                else
                                    cooldownUntil = now + number
                                end
                            end

                            if cooldownUntil then
                                if #objectAbilityMarkers == 0 then
                                    for marker in pairs(markerSet) do
                                        modelCache[marker] = math.max(
                                            modelCache[marker] or 0,
                                            cooldownUntil
                                        )
                                    end
                                else
                                    for _, marker in ipairs(objectAbilityMarkers) do
                                        modelCache[marker] = math.max(
                                            modelCache[marker] or 0,
                                            cooldownUntil
                                        )
                                    end
                                end
                            end
                        elseif child:IsA("BoolValue") and child.Value then
                            if #objectAbilityMarkers == 0 then
                                for marker in pairs(markerSet) do
                                    modelCache[marker] = true
                                end
                            else
                                for _, marker in ipairs(objectAbilityMarkers) do
                                    modelCache[marker] = true
                                end
                            end
                        end
                    end
                end
            end

            espAbilityCooldownCache[model] = modelCache
        end
    end
end

function startESPInfoWindow()
    if not (espDistanceEnabled or espSurvivorInfoEnabled or espAbilitiesEnabled) then
        destroyESPInfoWindow()
        return
    end

    createESPInfoWindow()

    if espInfoRefreshConnection then
        espInfoRefreshConnection:Disconnect()
    end

    espInfoUpdateAccumulator = 0
    espAbilityCacheAccumulator = 0
    espInfoRefreshConnection = RunService.Heartbeat:Connect(function(deltaTime)
        if guiDestroyed then
            return
        end

        if not (espDistanceEnabled or espSurvivorInfoEnabled or espAbilitiesEnabled) then
            destroyESPInfoWindow()
            return
        end

        espInfoUpdateAccumulator = espInfoUpdateAccumulator + deltaTime
        espAbilityCacheAccumulator = espAbilityCacheAccumulator + deltaTime

        if espAbilityCacheAccumulator >= 1 then
            espAbilityCacheAccumulator = 0

            if espAbilitiesEnabled then
                refreshESPAbilityCooldownCache()
            end
        end

        if espInfoUpdateAccumulator >= 0.25 then
            espInfoUpdateAccumulator = 0
            refreshESPInfoWindow()
        end
    end)

    if espAbilitiesEnabled then
        refreshESPAbilityCooldownCache()
    end

    refreshESPInfoWindow()
end

function destroyESPInfoWindow()
    if espInfoRefreshConnection then
        espInfoRefreshConnection:Disconnect()
        espInfoRefreshConnection = nil
    end

    if espInfoGui then
        pcall(function()
            espInfoGui:Destroy()
        end)
    end

    espInfoGui = nil
    espInfoWindow = nil
    espInfoScroll = nil
    espInfoLayout = nil
    table.clear(espAbilityCooldownCache)
end

function createESPInfoWindow()
    if espInfoGui and espInfoGui.Parent then
        return
    end

    destroyESPInfoWindow()

    espInfoGui = Instance.new("ScreenGui")
    espInfoGui.Name = "PulseCoreESPInfoUI"
    espInfoGui.ResetOnSpawn = false
    espInfoGui.IgnoreGuiInset = true
    espInfoGui.DisplayOrder = 1200
    espInfoGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    espInfoGui.Parent = playerGui

    espInfoWindow = Instance.new("Frame")
    espInfoWindow.Name = "ESPInfoWindow"
    espInfoWindow.AnchorPoint = Vector2.new(0, 0)
    espInfoWindow.Position = UDim2.new(0, 18, 0, 84)
    espInfoWindow.Size = UDim2.fromOffset(360, 430)
    espInfoWindow.BackgroundColor3 = COLORS.Panel
    espInfoWindow.BackgroundTransparency = 0.10
    espInfoWindow.BorderSizePixel = 0
    espInfoWindow.Active = true
    espInfoWindow.Parent = espInfoGui
    addCorner(espInfoWindow, 12)
    addStroke(espInfoWindow, COLORS.Border, 0.18, 1)

    local title = Instance.new("TextLabel")
    title.Size = UDim2.new(1, -20, 0, 30)
    title.Position = UDim2.fromOffset(10, 8)
    title.BackgroundTransparency = 1
    title.Text = "ESP INFO"
    title.Font = Enum.Font.GothamBold
    title.TextSize = 16
    title.TextColor3 = COLORS.Text
    title.TextXAlignment = Enum.TextXAlignment.Left
    title.Parent = espInfoWindow

    local subtitle = Instance.new("TextLabel")
    subtitle.Size = UDim2.new(1, -20, 0, 18)
    subtitle.Position = UDim2.fromOffset(10, 34)
    subtitle.BackgroundTransparency = 1
    subtitle.Text = "Distance / HP / Status / Abilities"
    subtitle.Font = Enum.Font.GothamMedium
    subtitle.TextSize = 10
    subtitle.TextColor3 = COLORS.MutedText
    subtitle.TextXAlignment = Enum.TextXAlignment.Left
    subtitle.Parent = espInfoWindow

    espInfoScroll = Instance.new("ScrollingFrame")
    espInfoScroll.Name = "Players"
    espInfoScroll.Position = UDim2.fromOffset(8, 58)
    espInfoScroll.Size = UDim2.new(1, -16, 1, -66)
    espInfoScroll.BackgroundTransparency = 1
    espInfoScroll.BorderSizePixel = 0
    espInfoScroll.ScrollBarThickness = 4
    espInfoScroll.CanvasSize = UDim2.fromOffset(0, 0)
    espInfoScroll.Parent = espInfoWindow

    espInfoLayout = Instance.new("UIListLayout")
    espInfoLayout.Padding = UDim.new(0, 6)
    espInfoLayout.SortOrder = Enum.SortOrder.LayoutOrder
    espInfoLayout.Parent = espInfoScroll

    espInfoLayout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
        if espInfoScroll and espInfoScroll.Parent then
            espInfoScroll.CanvasSize = UDim2.fromOffset(
                0,
                espInfoLayout.AbsoluteContentSize.Y + 8
            )
        end
    end)
end

function addESPInfoEntry(text, color, layoutOrder)
    local card = Instance.new("TextLabel")
    card.LayoutOrder = layoutOrder
    card.Size = UDim2.new(1, -4, 0, 20)
    card.AutomaticSize = Enum.AutomaticSize.Y
    card.MinimumSize = Vector2.new(0, 20)
    card.BackgroundColor3 = COLORS.CyanDeep
    card.BackgroundTransparency = 0.22
    card.BorderSizePixel = 0
    card.Text = text
    card.Font = Enum.Font.GothamMedium
    card.TextSize = 11
    card.TextColor3 = color or COLORS.Text
    card.TextWrapped = true
    card.TextXAlignment = Enum.TextXAlignment.Left
    card.TextYAlignment = Enum.TextYAlignment.Top
    card.Parent = espInfoScroll
    addCorner(card, 8)
    create("UIPadding", {
        PaddingLeft = UDim.new(0, 8),
        PaddingRight = UDim.new(0, 8),
        PaddingTop = UDim.new(0, 6),
        PaddingBottom = UDim.new(0, 6),
    }, card)
    return card
end

function formatESPAbilityState(abilityName, remaining)
    if remaining and remaining > 0 then
        return abilityName .. "  |  CD " .. string.format("%.1fs", remaining)
    end

    return abilityName .. "  |  READY"
end

function refreshESPInfoWindow()
    if not (espInfoGui and espInfoWindow and espInfoScroll) then
        return
    end

    for _, child in ipairs(espInfoScroll:GetChildren()) do
        if child:IsA("TextLabel") then
            child:Destroy()
        end
    end

    local localRoot = getESPRootPart(localPlayer.Character)
    local ordered = {}

    for model, record in pairs(trackedModels) do
        if model
            and model.Parent
            and record
            and not isESPModelDead(model)
        then
            table.insert(ordered, {
                model = model,
                record = record,
            })
        end
    end

    table.sort(ordered, function(left, right)
        return string.lower(left.record.displayName or left.model.Name)
            < string.lower(right.record.displayName or right.model.Name)
    end)

    if #ordered == 0 then
        addESPInfoEntry(
            "No living tracked characters.",
            COLORS.MutedText,
            1
        )
        return
    end

    for index, item in ipairs(ordered) do
        local model = item.model
        local record = item.record
        local root = getESPRootPart(model)
        local lines = {
            record.displayName .. "  [" .. record.group .. "]",
        }

        if espDistanceEnabled and localRoot and root then
            local distance = (localRoot.Position - root.Position).Magnitude
            table.insert(lines, string.format("Distance: %.1f studs", distance))
        end

        if record.group == "Survivor" and espSurvivorInfoEnabled then
            table.insert(lines, getESPHealthText(model))
            table.insert(lines, "Status: " .. getESPStatusText(model))
        end

        if espAbilitiesEnabled then
            local abilityNames = getESPCharacterAbilityNames(record.displayName)

            if #abilityNames > 0 then
                table.insert(lines, "")

                for _, abilityName in ipairs(abilityNames) do
                    local normalized = normalizeESPMarkerName(abilityName)
                    local remaining = espAbilityCooldownCache[model]
                        and espAbilityCooldownCache[model][normalized]
                        or 0

                    table.insert(
                        lines,
                        formatESPAbilityState(abilityName, remaining)
                    )
                end
            end
        end

        addESPInfoEntry(
            table.concat(lines, "\n"),
            record.group == "Executioner" and COLORS.ESPRed or COLORS.ESPBlue,
            index
        )
    end
end

function refreshESPAbilityCooldownCache()
    table.clear(espAbilityCooldownCache)

    for model, record in pairs(trackedModels) do
        if model
            and model.Parent
            and record
            and not isESPModelDead(model)
        then
            local characterAbilities = getESPCharacterAbilityNames(record.displayName)
            local modelCache = {}

            -- One descendant scan per tracked model per refresh, instead of
            -- scanning the whole model separately for every ability every frame.
            local objects = {model}
            for _, descendant in ipairs(model:GetDescendants()) do
                table.insert(objects, descendant)
            end

            local function takeNumber(value)
                local number = tonumber(value)
                if not number then
                    return nil
                end

                if number > time() + 1 then
                    return math.max(0, number - time())
                end

                return math.max(0, number)
            end

            local function inspect(object, objectAbility)
                if not object then
                    return
                end

                for attributeName, attributeValue in pairs(object:GetAttributes()) do
                    local key = normalizeESPMarkerName(attributeName)
                    local number = type(attributeValue) == "number"
                        and takeNumber(attributeValue)
                        or nil

                    if number and number > 0 then
                        for _, abilityName in ipairs(characterAbilities) do
                            local normalized = normalizeESPMarkerName(abilityName)

                            if key == "cooldown"
                                or key == "cd"
                                or key:find("cooldown", 1, true)
                            then
                                if not objectAbility or objectAbility == normalized then
                                    modelCache[normalized] = math.max(
                                        modelCache[normalized] or 0,
                                        number
                                    )
                                end
                            elseif key:find(normalized, 1, true)
                                and (key:find("remaining", 1, true)
                                    or key:find("cooldown", 1, true)
                                    or key:find("cd", 1, true))
                            then
                                modelCache[normalized] = math.max(
                                    modelCache[normalized] or 0,
                                    number
                                )
                            end
                        end
                    end
                end

                local objectName = normalizeESPMarkerName(object.Name)
                for _, abilityName in ipairs(characterAbilities) do
                    local normalized = normalizeESPMarkerName(abilityName)

                    if objectName == normalized
                        or objectName:find(normalized, 1, true)
                    then
                        objectAbility = normalized
                        break
                    end
                end

                if objectAbility then
                    for _, child in ipairs(object:GetChildren()) do
                        local childName = normalizeESPMarkerName(child.Name)

                        if childName == "cooldown"
                            or childName == "cd"
                            or childName:find("cooldown", 1, true)
                            or childName:find("remaining", 1, true)
                        then
                            local number = nil
                            if child:IsA("NumberValue") or child:IsA("IntValue") then
                                number = tonumber(child.Value)
                            end

                            if number then
                                local remaining = takeNumber(number)

                                if remaining and remaining > 0 then
                                    modelCache[objectAbility] = math.max(
                                        modelCache[objectAbility] or 0,
                                        remaining
                                    )
                                end
                            end
                        end
                    end
                end
            end

            for _, object in ipairs(objects) do
                inspect(object, nil)
            end

            espAbilityCooldownCache[model] = modelCache
        end
    end
end

function startESPInfoWindow()
    if not (espDistanceEnabled or espSurvivorInfoEnabled or espAbilitiesEnabled) then
        destroyESPInfoWindow()
        return
    end

    createESPInfoWindow()

    if espInfoRefreshConnection then
        espInfoRefreshConnection:Disconnect()
    end

    espInfoUpdateAccumulator = 0
    espInfoRefreshConnection = RunService.Heartbeat:Connect(function(deltaTime)
        if guiDestroyed then
            return
        end

        if not (espDistanceEnabled or espSurvivorInfoEnabled or espAbilitiesEnabled) then
            destroyESPInfoWindow()
            return
        end

        espInfoUpdateAccumulator = espInfoUpdateAccumulator + deltaTime

        -- Distance can move every frame, but the expensive ability/status scan
        -- is intentionally limited to this 0.5-second update cadence.
        if espInfoUpdateAccumulator < 0.5 then
            if espDistanceEnabled then
                refreshESPInfoWindow()
            end
            return
        end

        espInfoUpdateAccumulator = 0
        refreshESPAbilityCooldownCache()
        refreshESPInfoWindow()
    end)

    refreshESPAbilityCooldownCache()
    refreshESPInfoWindow()
end

function getOrCreateESPInfoTag(model, record)
    local tag = record.infoTag

    local adornee = record.infoTagAdornee

    if not adornee
        or not adornee.Parent
        or not adornee:IsDescendantOf(model)
    then
        adornee = getESPRootPart(model)
        record.infoTagAdornee = adornee
    end

    if not adornee then
        return nil
    end

    if tag and tag.Parent and tag:IsA("BillboardGui") then
        tag.Adornee = adornee
        return tag
    end

    if tag then
        pcall(function()
            tag:Destroy()
        end)
    end

    tag = Instance.new("BillboardGui")
    tag.Name = ESP_HIGHLIGHT_NAME .. "_Info"
    tag.Adornee = adornee
    tag.AlwaysOnTop = true
    tag.MaxDistance = 0
    tag.Size = UDim2.fromOffset(330, 190)
    tag.StudsOffset = Vector3.new(0, -2.2, 0)
    tag.Parent = screenGui

    local label = Instance.new("TextLabel")
    label.Name = "TextLabel"
    label.BackgroundColor3 = COLORS.Panel
    label.BackgroundTransparency = 0.25
    label.BorderSizePixel = 0
    label.Size = UDim2.fromScale(1, 1)
    label.Font = Enum.Font.GothamMedium
    label.TextSize = 12
    label.TextColor3 = COLORS.Text
    label.TextStrokeColor3 = Color3.new(0, 0, 0)
    label.TextStrokeTransparency = 0.45
    label.TextWrapped = false
    label.TextXAlignment = Enum.TextXAlignment.Left
    label.TextYAlignment = Enum.TextYAlignment.Top
    label.Parent = tag
    addCorner(label, 8)
    create("UIPadding", {
        PaddingLeft = UDim.new(0, 8),
        PaddingRight = UDim.new(0, 8),
        PaddingTop = UDim.new(0, 6),
        PaddingBottom = UDim.new(0, 6),
    }, label)

    record.infoTag = tag
    return tag
end

function updateESPInfoTags()
    local camera = workspace.CurrentCamera
    if not camera then
        return
    end

    local localCharacter = localPlayer.Character
    local localRoot = getESPRootPart(localCharacter)

    for model, record in pairs(trackedModels) do
        if model
            and model.Parent
            and record
        then
            if isESPModelDead(model) then
                continue
            end

            local shouldShowInfo = espDistanceEnabled
                or (record.group == "Survivor" and espSurvivorInfoEnabled)
                or espAbilitiesEnabled

            if not shouldShowInfo then
                if record.infoTag then
                    record.infoTag.Enabled = false
                end
                continue
            end

            local tag = getOrCreateESPInfoTag(model, record)

            if not tag then
                continue
            end

            local adornee = record.infoTagAdornee
            local lines = {record.displayName}

            if espDistanceEnabled and localRoot and adornee then
                local studs = (localRoot.Position - adornee.Position).Magnitude
                table.insert(lines, string.format("Distance: %.1f studs", studs))
            end

            if record.group == "Survivor" and espSurvivorInfoEnabled then
                table.insert(lines, getESPHealthText(model))
                table.insert(lines, "Status: " .. getESPStatusText(model))
            end

            if espAbilitiesEnabled then
                local abilityLines = getESPAbilityDisplayLines(
                    model,
                    record.displayName
                )

                if #abilityLines > 0 then
                    table.insert(lines, "Abilities:")

                    for _, abilityLine in ipairs(abilityLines) do
                        table.insert(lines, abilityLine)
                    end
                end
            end

            tag.TextLabel.Text = table.concat(lines, "\n")
            tag.TextLabel.TextColor3 =
                record.group == "Executioner" and COLORS.ESPRed or COLORS.ESPBlue
            tag.Enabled = true

            local distance = (camera.CFrame.Position - adornee.Position).Magnitude
            tag.TextLabel.TextSize = math.clamp(1200 / math.max(distance, 1), 8, 13)
        end
    end
end

function getOrCreateESPTracer(model, record)
    local tracer = record.tracer

    if tracer and tracer.Parent then
        return tracer
    end

    tracer = Instance.new("Frame")
    tracer.Name = ESP_HIGHLIGHT_NAME .. "_Tracer"
    tracer.AnchorPoint = Vector2.new(0, 0.5)
    tracer.BorderSizePixel = 0
    tracer.BackgroundColor3 =
        record.group == "Executioner" and COLORS.ESPRed or COLORS.ESPBlue
    tracer.BackgroundTransparency = 0.08
    tracer.Size = UDim2.fromOffset(0, 2)
    tracer.Visible = false
    tracer.ZIndex = 1
    tracer.Parent = screenGui

    record.tracer = tracer
    return tracer
end

function updateESPTracers()
    local camera = workspace.CurrentCamera
    if not camera then
        return
    end

    local viewport = camera.ViewportSize
    local origin = Vector2.new(viewport.X * 0.5, viewport.Y - 8)
    local localCharacter = localPlayer.Character

    for model, record in pairs(trackedModels) do
        local tracer = record.tracer

        if espTracersEnabled and model and model.Parent and not isESPModelDead(model) then
            local root = getESPRootPart(model)
            local screenPoint, onScreen = root
                and camera:WorldToViewportPoint(root.Position)
                or nil

            if tracer and tracer.Parent or (root and screenPoint) then
                tracer = getOrCreateESPTracer(model, record)
            end

            if tracer and root and onScreen and screenPoint.Z > 0 then
                local target = Vector2.new(screenPoint.X, screenPoint.Y)
                local delta = target - origin
                local length = delta.Magnitude

                tracer.Position = UDim2.fromOffset(origin.X, origin.Y)
                tracer.Size = UDim2.fromOffset(length, 2)
                tracer.Rotation = math.deg(math.atan2(delta.Y, delta.X))
                tracer.BackgroundColor3 =
                    record.group == "Executioner" and COLORS.ESPRed or COLORS.ESPBlue
                tracer.Visible = true
            elseif tracer then
                tracer.Visible = false
            end
        elseif tracer then
            tracer.Visible = false
        end
    end
end

function getOrCreateESPNameTag(model, record, displayName, group)
    local label = record.nameTag

    if label and label.Parent and label:IsA("BillboardGui") then
        label.TextLabel.Text = displayName
        label.TextLabel.TextColor3 =
            group == "Executioner" and COLORS.ESPRed or COLORS.ESPBlue
        return label
    end

    if label then
        pcall(function()
            label:Destroy()
        end)
        record.nameTag = nil
    end

    local adornee = model:FindFirstChild("Head", true)
        or model:FindFirstChild("HumanoidRootPart", true)
        or model:FindFirstChild("UpperTorso", true)
        or model:FindFirstChild("Torso", true)

    if not adornee or not adornee:IsA("BasePart") then
        for _, descendant in ipairs(model:GetDescendants()) do
            if descendant:IsA("BasePart") then
                adornee = descendant
                break
            end
        end
    end

    if not adornee then
        return nil
    end

    local billboard = Instance.new("BillboardGui")
    billboard.Name = ESP_HIGHLIGHT_NAME .. "_NameTag"
    billboard.Adornee = adornee
    billboard.AlwaysOnTop = true
    billboard.MaxDistance = 0
    billboard.Size = UDim2.fromOffset(220, 40)
    billboard.StudsOffset = Vector3.new(0, 3.2, 0)
    billboard.Parent = screenGui

    local textLabel = Instance.new("TextLabel")
    textLabel.Name = "TextLabel"
    textLabel.BackgroundTransparency = 1
    textLabel.Size = UDim2.fromScale(1, 1)
    textLabel.Text = displayName
    textLabel.Font = Enum.Font.GothamBold
    textLabel.TextSize = 18
    textLabel.TextColor3 =
        group == "Executioner" and COLORS.ESPRed or COLORS.ESPBlue
    textLabel.TextStrokeColor3 = Color3.new(0, 0, 0)
    textLabel.TextStrokeTransparency = 0.2
    textLabel.TextWrapped = true
    textLabel.TextXAlignment = Enum.TextXAlignment.Center
    textLabel.TextYAlignment = Enum.TextYAlignment.Center
    textLabel.Parent = billboard

    record.nameTag = billboard
    record.nameTagAdornee = adornee
    return billboard
end

function updateESPNameTags()
    local camera = workspace.CurrentCamera
    if not camera then
        return
    end

    local cameraPosition = camera.CFrame.Position

    for model, record in pairs(trackedModels) do
        if model
            and model.Parent
            and record
            and record.nameTag
            and record.nameTag.Parent
        then
            local adornee = record.nameTagAdornee

            if not adornee
                or not adornee.Parent
                or not adornee:IsDescendantOf(model)
            then
                adornee = model:FindFirstChild("Head", true)
                    or model:FindFirstChild("HumanoidRootPart", true)
                    or model:FindFirstChild("UpperTorso", true)
                    or model:FindFirstChild("Torso", true)

                if adornee and adornee:IsA("BasePart") then
                    record.nameTagAdornee = adornee
                    record.nameTag.Adornee = adornee
                end
            end

            if adornee and adornee:IsA("BasePart") then
                local distance = (cameraPosition - adornee.Position).Magnitude
                local textSize = math.clamp(1800 / math.max(distance, 1), 8, 18)
                record.nameTag.TextLabel.TextSize = textSize
                record.nameTag.TextLabel.TextColor3 =
                    record.group == "Executioner" and COLORS.ESPRed or COLORS.ESPBlue
            end
        end
    end
end

function updateVisualsStatus()
    local trackedCount = 0
    local survivorCount = 0
    local executionerCount = 0

    for model, record in pairs(trackedModels) do
        if model and model.Parent and record then
            trackedCount = trackedCount + 1
            if record.group == "Survivor" then
                survivorCount = survivorCount + 1
            elseif record.group == "Executioner" then
                executionerCount = executionerCount + 1
            end
        end
    end

    visualsStatusLabel.Text = string.format(
        "Models: %d  •  Survivors: %d  •  Executioners: %d\nMatching models by recognized ability names anywhere in Workspace",
        trackedCount,
        survivorCount,
        executionerCount
    )
end

function getOrCreateESPHighlight(model, record)
    local highlight = record.highlight

    if highlight and highlight.Parent and highlight:IsA("Highlight") then
        return highlight
    end

    if highlight then
        pcall(function()
            highlight:Destroy()
        end)
        record.highlight = nil
    end

    -- A dedicated local folder keeps ESP objects separate from game models.
    local highlightFolder = workspace:FindFirstChild("PulseCoreESPHighlights")
    if not highlightFolder then
        highlightFolder = Instance.new("Folder")
        highlightFolder.Name = "PulseCoreESPHighlights"
        highlightFolder.Parent = workspace
    end

    local safeId = model:GetDebugId()
    local objectName = ESP_HIGHLIGHT_NAME .. "_" .. safeId
    local existing = highlightFolder:FindFirstChild(objectName)

    if existing and existing:IsA("Highlight") then
        highlight = existing
    else
        if existing then
            existing:Destroy()
        end

        highlight = Instance.new("Highlight")
        highlight.Name = objectName
        highlight.Parent = highlightFolder
    end

    highlight.Adornee = model
    highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
    highlight.FillTransparency = 0.45
    highlight.OutlineTransparency = 0
    highlight.OutlineColor = COLORS.White

    record.highlight = highlight
    return highlight
end

function unregisterCharacterModel(model, destroyHighlight)
    local record = trackedModels[model]
    if not record then
        return
    end

    if destroyHighlight and record.highlight and record.highlight.Parent then
        pcall(function()
            record.highlight:Destroy()
        end)
    end

    if record.nameTag and record.nameTag.Parent then
        pcall(function()
            record.nameTag:Destroy()
        end)
    end

    if record.infoTag and record.infoTag.Parent then
        pcall(function()
            record.infoTag:Destroy()
        end)
    end

    if record.tracer and record.tracer.Parent then
        pcall(function()
            record.tracer:Destroy()
        end)
    end

    trackedModels[model] = nil
end

function refreshAllTrackedModels()
    for model, record in pairs(trackedModels) do
        if not model or not model.Parent then
            if record and record.highlight and record.highlight.Parent then
                pcall(function()
                    record.highlight:Destroy()
                end)
            end

            if record and record.nameTag and record.nameTag.Parent then
                pcall(function()
                    record.nameTag:Destroy()
                end)
            end

            if record and record.infoTag and record.infoTag.Parent then
                pcall(function()
                    record.infoTag:Destroy()
                end)
            end

            if record and record.tracer and record.tracer.Parent then
                pcall(function()
                    record.tracer:Destroy()
                end)
            end

            trackedModels[model] = nil
        elseif record and isESPModelDead(model) then
            unregisterCharacterModel(model, true)
        elseif record then
            local group = record.group
            local espColor = group == "Survivor" and COLORS.ESPBlue or COLORS.ESPRed
            local enabled = group == "Survivor"
                and espSurvivorsEnabled
                or group == "Executioner"
                and espExecutionersEnabled

            local highlight = record.highlight
            if highlight and highlight.Parent and highlight:IsA("Highlight") then
                highlight.FillColor = espColor
                highlight.OutlineColor = espColor
                highlight.Enabled = enabled
            end

            local nameTag = record.nameTag
            if nameTag and nameTag.Parent then
                nameTag.Enabled = enabled
                nameTag.TextLabel.TextColor3 = espColor
            end
        end
    end
end

function registerCharacterModel(model, group, displayName)
    if not model or not model:IsA("Model") or isLocalCharacterModel(model) then
        return
    end

    if isESPModelDead(model) then
        return
    end

    if group ~= "Survivor" and group ~= "Executioner" then
        return
    end

    local record = trackedModels[model]
    if not record then
        record = {
            model = model,
            group = group,
            displayName = displayName or "Unknown",
            highlight = nil,
            nameTag = nil,
            nameTagAdornee = nil,
            infoTag = nil,
            infoTagAdornee = nil,
            tracer = nil,
        }
        trackedModels[model] = record
    else
        record.group = group
        record.displayName = displayName or record.displayName or model.Name
    end

    local espColor = group == "Survivor" and COLORS.ESPBlue or COLORS.ESPRed
    local highlight = getOrCreateESPHighlight(model, record)

    highlight.FillColor = espColor
    highlight.FillTransparency = 0.45
    highlight.OutlineColor = espColor
    highlight.OutlineTransparency = 0

    local nameTag = getOrCreateESPNameTag(
        model,
        record,
        record.displayName,
        group
    )

    if nameTag then
        nameTag.Enabled = group == "Survivor"
            and espSurvivorsEnabled
            or group == "Executioner"
            and espExecutionersEnabled
    end

    highlight.Enabled = group == "Survivor"
        and espSurvivorsEnabled
        or group == "Executioner"
        and espExecutionersEnabled
end

function getESPScanRoot()
    return workspace
end

ESP_ABILITY_ROLE_NAMES = {
    -- Executioners
    step = "Executioner",
    brighterday = "Executioner",
    reachout = "Executioner",
    chaosdash = "Executioner",
    fatefuldrain = "Executioner",
    lasersofdestrucation = "Executioner",
    lasersofdestruction = "Executioner",
    burst = "Executioner",
    charge = "Executioner",
    godstrickery = "Executioner",
    invisiblity = "Executioner",
    invisibility = "Executioner",
    ragemode = "Executioner",
    grab = "Executioner",
    block = "Executioner",
    indicator = "Executioner",

    -- Survivors
    dropdash = "Survivor",
    peelout = "Survivor",
    lasercanon = "Survivor",
    lasercannon = "Survivor",
    glide = "Survivor",
    punch = "Survivor",
    counter = "Survivor",
    jetpackboost = "Survivor",
    energyshield = "Survivor",
    hammer = "Survivor",
    hammerthrow = "Survivor",
    reroll = "Survivor",
    heal = "Survivor",
    dash = "Survivor",
    summon = "Survivor",
    healloop = "Survivor",
    destructivecharge = "Survivor",
    desturctivecharge = "Survivor",
    selfrepair = "Survivor",
    rock = "Survivor",
    timereversall = "Survivor",
    timereversal = "Survivor",
    roundhousekick = "Survivor",

    -- Internal ability markers confirmed from the supplied .rbxl.
    canon = "Survivor",
    jetpack = "Survivor",
    rage = "Executioner",
    invis = "Executioner",
    chargerun = "Executioner",
    impalerun = "Executioner",
    chargewarn = "Executioner",
    killold = "Executioner",

    -- Stable animation markers from the supplied rbxl.
    dodge1 = "Survivor",
    dodge2 = "Survivor",
    dodge3 = "Survivor",
    brake = "Survivor",
    strangledr = "Survivor",
    focus = "Survivor",
    dashstart = "Survivor",
    flamestart = "Survivor",
    flameloop = "Survivor",
    flameend = "Survivor",
}

ESP_ABILITY_CHARACTER_NAMES = {
    -- Executioners
    step = "Tripwire",
    brighterday = "Tripwire",
    reachout = "Tripwire",
    chaosdash = "Fleetway",
    fatefuldrain = "Fleetway",
    lasersofdestrucation = "Fleetway",
    lasersofdestruction = "Fleetway",
    burst = "Fleetway",
    charge = "2011x",
    godstrickery = "2011x",
    invisiblity = "2011x",
    invisibility = "2011x",
    ragemode = "2011x",
    grab = "Kolossos",
    block = "Kolossos",
    indicator = "Kolossos",

    -- Survivors
    dropdash = "Sonic",
    peelout = "Sonic",
    lasercanon = "Tails",
    lasercannon = "Tails",
    glide = "Tails",
    punch = "Knuckles",
    counter = "Knuckles",
    jetpackboost = "Eggman",
    energyshield = "Eggman",
    hammer = "Amy",
    hammerthrow = "Amy",
    reroll = "Amy",
    heal = "Cream",
    dash = "Cream",
    summon = "Cream",
    healloop = "Cream",
    destructivecharge = "Metal Sonic",
    desturctivecharge = "Metal Sonic",
    selfrepair = "Metal Sonic",
    rock = "Silver",
    timereversall = "Silver",
    timereversal = "Silver",
    roundhousekick = "Blaze",

    -- Internal ability markers confirmed from the supplied .rbxl.
    canon = "Tails",
    jetpack = "Eggman",
    rage = "2011x",
    invis = "2011x",
    chargerun = "Kolossos",
    impalerun = "Kolossos",
    chargewarn = "Kolossos",
    killold = "Kolossos",
    dodge1 = "Sonic",
    dodge2 = "Sonic",
    dodge3 = "Sonic",
    brake = "Sonic",
    strangledr = "Tails",
    focus = "Knuckles",
    dashstart = "Metal Sonic",
    flamestart = "Blaze",
    flameloop = "Blaze",
    flameend = "Blaze",
}

ESP_CHARACTER_ABILITY_SETS = {
    -- Stable internal markers observed in the supplied rbxl character templates.
    Tripwire = {"step", "brighterday", "reachout"},
    Fleetway = {"chargedash", "missdash", "grabhold", "toss"},
    ["2011x"] = {"rage", "invis", "godstrickery", "invisiblity", "invisibility", "ragemode"},
    Kolossos = {"chargerun", "impalerun", "chargewarn", "block", "killold"},

    Sonic = {"dodge1", "dodge2", "dodge3", "brake"},
    Tails = {"strangledr"},
    Knuckles = {"focus"},
    Eggman = {"jetpack"},
    Amy = {"hammer"},
    Cream = {"summon", "healloop"},
    ["Metal Sonic"] = {"dashstart"},
    Silver = {"aim", "rocksr", "rocks"},
    Blaze = {"flamestart", "float", "flameloop", "flameend"},
}

-- These markers occur on several different character templates and therefore
-- must never identify a character by themselves.
ESP_GENERIC_ABILITY_NAMES = {
    canon = true,
    peelout = true,
    glide = true,
    charge = true,
    dash = true,
    flying = true,
    strangled = true,
}

function normalizeESPModelName(name)
    return string.lower(tostring(name or "")):gsub("[^%w]+", "")
end

function normalizeESPMarkerName(name)
    return normalizeESPModelName(name)
end

function getESPGroupByModelName(name)
    return ESP_MODEL_ROLE_NAMES[normalizeESPModelName(name)]
end

function getESPGroupByAbilityName(name)
    return ESP_ABILITY_ROLE_NAMES[normalizeESPMarkerName(name)]
end

function getESPCharacterNameByAbility(name)
    return ESP_ABILITY_CHARACTER_NAMES[normalizeESPMarkerName(name)]
end

function normalizeESPContainerName(name)
    return normalizeESPModelName(name)
end

function getESPGroupByName(name)
    return getESPGroupByModelName(name)
end

function isLocalCharacterModel(model)
    return model == localPlayer.Character
end

function getESPDisplayName(model, inferredName)
    return inferredName or "Unknown"
end

function isESPAbilityNameCandidate(instance)
    if not instance then
        return false
    end

    -- Physical/visual objects are not considered ability-name objects.
    if instance:IsA("BasePart")
        or instance:IsA("Attachment")
        or instance:IsA("Decal")
        or instance:IsA("Texture")
        or instance:IsA("ParticleEmitter")
        or instance:IsA("Beam")
        or instance:IsA("Trail")
        or instance:IsA("Smoke")
        or instance:IsA("Fire")
        or instance:IsA("Sparkles")
        or instance:IsA("Sound")
    then
        return false
    end

    -- Animation objects in Animate.Anims are valid ability markers for this game.

    return true
end

function getESPAbilityClassification(model)
    if not model or not model:IsA("Model") then
        return nil, nil
    end

    local found = {}

    local function processValue(value)
        local normalized = normalizeESPMarkerName(value)

        if ESP_ABILITY_ROLE_NAMES[normalized] then
            found[normalized] = true
        end
    end

    local function processCandidateName(instance)
        if not instance then
            return
        end

        -- First test the exact normalized name against the known ability table.
        -- Some real ability markers (for example Tripwire's Reachout) are
        -- stored as Sounds, so their class cannot be used as a blanket filter.
        local normalized = normalizeESPMarkerName(instance.Name)
        if ESP_ABILITY_ROLE_NAMES[normalized] then
            found[normalized] = true
            return
        end

        -- Unknown physical/visual objects are ignored to avoid false positives
        -- such as a Sound named Rock being mistaken for Silver's ability.
        if instance:IsA("Sound")
            or instance:IsA("BasePart")
            or instance:IsA("Attachment")
            or instance:IsA("Decal")
            or instance:IsA("Texture")
            or instance:IsA("ParticleEmitter")
            or instance:IsA("Beam")
            or instance:IsA("Trail")
            or instance:IsA("Smoke")
            or instance:IsA("Fire")
            or instance:IsA("Sparkles")
        then
            return
        end
    end

    -- Scan the character's Animate/Anims tree, where the rbxl shows the
    -- character-specific move markers actually live.
    local animate = model:FindFirstChild("Animate")
    local anims = animate and animate:FindFirstChild("Anims")

    if anims then
        for _, descendant in ipairs(anims:GetDescendants()) do
            processCandidateName(descendant)

            if descendant:IsA("StringValue") then
                processValue(descendant.Value)
            end

            for _, value in pairs(descendant:GetAttributes()) do
                if type(value) == "string" then
                    processValue(value)
                end
            end
        end
    end

    -- Some characters expose their current ability marker directly on the
    -- character root (for example Amy/Hammer, Eggman/jetpack, 2011x/Rage).
    for _, child in ipairs(model:GetChildren()) do
        if child:IsA("Model")
            or child:IsA("Folder")
            or child:IsA("NumberValue")
            or child:IsA("StringValue")
        then
            processCandidateName(child)

            if child:IsA("StringValue") then
                processValue(child.Value)
            end

            for _, value in pairs(child:GetAttributes()) do
                if type(value) == "string" then
                    processValue(value)
                end
            end
        end
    end

    for _, value in pairs(model:GetAttributes()) do
        if type(value) == "string" then
            processValue(value)
        end
    end

    -- Generic markers are intentionally not character evidence.
    for genericName in pairs(ESP_GENERIC_ABILITY_NAMES) do
        found[genericName] = nil
    end

    -- The supplied rbxl stores Tripwire under TailsDoll and uses the
    -- CustomAnimation/Glorbwire set. Several Glorbwire animations have unique
    -- asset IDs, so the IDs are a stronger signal than inherited Sonic names.
    local tripwireAnimationIds = {
        ["79953933012214"] = true, -- Glorbwire Default Idle
        ["85598394392380"] = true, -- Glorbwire Default Run/Walk
        ["132547926723713"] = true, -- Glorbwire Jump
        ["80215516605216"] = true, -- Glorbwire Kill
    }

    local customAnimation = model:FindFirstChild("CustomAnimation")
    if customAnimation then
        for _, descendant in ipairs(customAnimation:GetDescendants()) do
            local normalized = normalizeESPMarkerName(descendant.Name)

            if normalized == "glorbwire" or normalized == "deadglorbwire" then
                return "Executioner", "Tripwire"
            end
        end
    end

    for _, descendant in ipairs(model:GetDescendants()) do
        if descendant:IsA("Animation") then
            local animationId = tostring(descendant.AnimationId):match("%d+")
            if animationId and tripwireAnimationIds[animationId] then
                return "Executioner", "Tripwire"
            end
        end
    end

    -- Tripwire can inherit Sonic animation markers such as dodge/brake.
    -- Its own ability markers must therefore win before the normal score pass.
    if found.step or found.brighterday or found.reachout then
        return "Executioner", "Tripwire"
    end

    -- Fleetway can also inherit Sonic markers. Its actual ability names are
    -- stored in ESP_ABILITY_CHARACTER_NAMES, so use those as direct evidence.
    if found.chaosdash
        or found.fatefuldrain
        or found.lasersofdestrucation
        or found.lasersofdestruction
        or found.burst
    then
        return "Executioner", "Fleetway"
    end

    local scores = {}
    local hasExecutionerEvidence = false

    for characterName, abilities in pairs(ESP_CHARACTER_ABILITY_SETS) do
        local score = 0

        for _, abilityName in ipairs(abilities) do
            if found[abilityName] then
                score = score + 1
            end
        end

        scores[characterName] = score

        if (
            characterName == "Tripwire"
            or characterName == "Fleetway"
            or characterName == "2011x"
            or characterName == "Kolossos"
        ) and score > 0 then
            hasExecutionerEvidence = true
        end
    end

    -- Skins can inherit survivor animations. Once a real executioner marker
    -- exists, survivor animation matches must not override the executioner.
    if hasExecutionerEvidence then
        for characterName in pairs(scores) do
            if characterName ~= "Tripwire"
                and characterName ~= "Fleetway"
                and characterName ~= "2011x"
                and characterName ~= "Kolossos"
            then
                scores[characterName] = 0
            end
        end
    end

    local bestName = nil
    local bestScore = 0
    local tied = false

    for characterName, score in pairs(scores) do
        if score > bestScore then
            bestName = characterName
            bestScore = score
            tied = false
        elseif score > 0 and score == bestScore then
            tied = true
        end
    end

    if not bestName or bestScore <= 0 or tied then
        return nil, nil
    end

    local executioners = {
        Tripwire = true,
        Fleetway = true,
        ["2011x"] = true,
        Kolossos = true,
    }

    return executioners[bestName] and "Executioner" or "Survivor", bestName
end
function isESPExecutionerModel(model)
    local role = getESPAbilityClassification(model)
    return role == "Executioner"
end

function isDirectWorkspacePlayersModel(model)
    local playersFolder = workspace:FindFirstChild("Players")
    return playersFolder ~= nil
        and model ~= nil
        and model:IsA("Model")
        and model.Parent == playersFolder
end

function getESPGroupForModel(model)
    if not model or not model:IsA("Model") or isLocalCharacterModel(model) then
        return nil, nil
    end

    -- The character model's username/name is intentionally ignored.
    -- Classification is based only on recognized ability markers.
    local group, displayName = getESPAbilityClassification(model)

    if not group then
        return nil, nil
    end

    return group, displayName or "Unknown"
end
function scanESPContainers()
    if guiDestroyed then
        return
    end

    local validModels = {}

    -- First scan the game's player-model container. This is the important
    -- path for skins whose model names differ from their base character.
    local playersFolder = workspace:FindFirstChild("Players")

    if playersFolder then
        for _, model in ipairs(playersFolder:GetChildren()) do
            if model:IsA("Model") and not isLocalCharacterModel(model) then
                if isESPModelDead(model) then
                    continue
                end

                local group, displayName = getESPGroupForModel(model)

                if group then
                    validModels[model] = {
                        group = group,
                        displayName = displayName or model.Name,
                    }
                end
            end
        end
    end

    -- Also scan actual Player characters in case the game uses Player.Character
    -- directly instead of a Workspace.Players model.
    for _, player in ipairs(Players:GetPlayers()) do
        if player ~= localPlayer then
            local character = player.Character

            if character and character:IsA("Model") then
                if isESPModelDead(character) then
                    continue
                end

                local group, displayName = getESPGroupForModel(character)

                if group then
                    validModels[character] = {
                        group = group,
                        displayName = displayName or "Unknown",
                    }
                end
            end
        end
    end

    -- Also scan Workspace for top-level character models that are not
    -- exposed through Player.Character or Workspace.Players.
    for _, instance in ipairs(workspace:GetChildren()) do
        if instance:IsA("Model") and not isLocalCharacterModel(instance) then
            if isESPModelDead(instance) then
                continue
            end

            local group, displayName = getESPGroupForModel(instance)

            if group then
                validModels[instance] = {
                    group = group,
                    displayName = displayName or instance.Name,
                }
            end
        end
    end

    for model, info in pairs(validModels) do
        registerCharacterModel(
            model,
            info.group,
            info.displayName
        )
    end

    local modelsToRemove = {}

    for model in pairs(trackedModels) do
        if not model
            or not model.Parent
            or not validModels[model]
            or not model:IsDescendantOf(workspace)
        then
            table.insert(modelsToRemove, model)
        end
    end

    for _, model in ipairs(modelsToRemove) do
        unregisterCharacterModel(model, true)
    end

    updateVisualsStatus()
end

function scheduleESPScan(delayTime)
    if guiDestroyed or espScanQueued then
        return
    end

    espScanQueued = true
    espScanSerial = espScanSerial + 1
    local serial = espScanSerial

    task.delay(delayTime or 0.15, function()
        if guiDestroyed or serial ~= espScanSerial then
            return
        end

        espScanQueued = false
        scanESPContainers()
    end)
end

function initializeESP()
    if espWorkspaceAddedConnection then
        espWorkspaceAddedConnection:Disconnect()
        espWorkspaceAddedConnection = nil
    end

    if espWorkspaceRemovingConnection then
        espWorkspaceRemovingConnection:Disconnect()
        espWorkspaceRemovingConnection = nil
    end

    if localCharacterAddedConnection then
        localCharacterAddedConnection:Disconnect()
        localCharacterAddedConnection = nil
    end

    espScanSerial = espScanSerial + 1
    espScanQueued = false

    if espNameTagConnection then
        espNameTagConnection:Disconnect()
        espNameTagConnection = nil
    end

    espNameTagConnection = RunService.RenderStepped:Connect(function()
        if guiDestroyed then
            return
        end

        updateESPNameTags()
    end)

    -- A new model can appear anywhere in Workspace, so no folder-specific
    -- condition is used here.
    espWorkspaceAddedConnection = workspace.DescendantAdded:Connect(function(instance)
        if guiDestroyed then
            return
        end

        if instance:IsA("Model")
            and (
                instance.Parent == workspace
                or instance.Parent == workspace:FindFirstChild("Players")
            )
        then
            scheduleESPScan(0.15)
        end
    end)

    espWorkspaceRemovingConnection = workspace.DescendantRemoving:Connect(function(instance)
        if guiDestroyed then
            return
        end

        if trackedModels[instance] then
            unregisterCharacterModel(instance, true)
        end

        if instance:IsA("Model") then
            scheduleESPScan(0.15)
        end
    end)

    localCharacterAddedConnection = localPlayer.CharacterAdded:Connect(function()
        scheduleESPScan(0.05)
    end)

    scanESPContainers()
    startESPInfoWindow()
    
    if espNameTagConnection then
        espNameTagConnection:Disconnect()
        espNameTagConnection = nil
    end

    espNameTagConnection = RunService.RenderStepped:Connect(function()
        if guiDestroyed then
            return
        end

        if espSurvivorsEnabled or espExecutionersEnabled then
            refreshAllTrackedModels()
            updateESPNameTags()
            updateESPTracers()
        end
    end)

end

function shutdownESP()
    destroyESPInfoWindow()

    if espNameTagConnection then
        espNameTagConnection:Disconnect()
        espNameTagConnection = nil
    end

    if espWorkspaceAddedConnection then
        espWorkspaceAddedConnection:Disconnect()
        espWorkspaceAddedConnection = nil
    end

    if espWorkspaceRemovingConnection then
        espWorkspaceRemovingConnection:Disconnect()
        espWorkspaceRemovingConnection = nil
    end

    if localCharacterAddedConnection then
        localCharacterAddedConnection:Disconnect()
        localCharacterAddedConnection = nil
    end

    espScanSerial = espScanSerial + 1
    espScanQueued = false

    local modelsToRemove = {}
    for model in pairs(trackedModels) do
        table.insert(modelsToRemove, model)
    end

    for _, model in ipairs(modelsToRemove) do
        unregisterCharacterModel(model, true)
    end

    table.clear(recordedESPContainers)

    local highlightFolder = workspace:FindFirstChild("PulseCoreESPHighlights")
    if highlightFolder then
        pcall(function()
            highlightFolder:Destroy()
        end)
    end

    updateVisualsStatus()
end

function normalizeNumberText(text)
    -- string.gsub возвращает два значения: строку и количество замен.
    -- Сохраняем результат в переменную, чтобы tonumber не получил
    -- количество замен как второй аргумент (основание системы счисления).
    local normalized = string.gsub(text, ",", ".")
    normalized = string.gsub(normalized, "%s+", "")
    return normalized
end

function parsePositiveNumber(text, minimum, maximum)
    local numberValue = tonumber(normalizeNumberText(text))

    if not numberValue then
        return nil
    end

    return math.clamp(numberValue, minimum, maximum)
end

function parseDuration(text)
    local normalized = string.lower(normalizeNumberText(text))

    if normalized == "inf" or normalized == "infinity" or normalized == "∞" then
        return nil
    end

    local numberValue = tonumber(normalized)

    if not numberValue or numberValue <= 0 then
        return false
    end

    return math.clamp(numberValue, 0.05, 86400)
end

function formatNumber(numberValue)
    return string.format("%.2f", numberValue):gsub("%.?0+$", "")
end

function getCharacterParts()
    local character = localPlayer.Character

    if not character or not character.Parent then
        return nil, nil, nil
    end

    local humanoid = character:FindFirstChildOfClass("Humanoid")
    local rootPart = character:FindFirstChild("HumanoidRootPart") or character.PrimaryPart

    if not humanoid or not rootPart or not rootPart:IsA("BasePart") then
        return nil, nil, nil
    end

    return character, humanoid, rootPart
end

function clientModules.characterTools.isAbilityNoclipActive()
    return boostActive
        and type(activeOwner) == "table"
        and activeOwner.deleted ~= true
        and activeOwner.noclipEnabled == true
end

function clientModules.characterTools.isAbilityInfinityJumpActive()
    return boostActive
        and type(activeOwner) == "table"
        and activeOwner.deleted ~= true
        and activeOwner.infinityJumpEnabled == true
end

function clientModules.characterTools.shouldNoclip()
    return clientModules.characterTools.noclipEnabled
        or clientModules.characterTools.isAbilityNoclipActive()
end

function clientModules.characterTools.shouldInfinityJump()
    return clientModules.characterTools.infinityJumpEnabled
        or clientModules.characterTools.isAbilityInfinityJumpActive()
end

function clientModules.characterTools.isAbilitySharpMovementActive()
    return boostActive
        and type(activeOwner) == "table"
        and activeOwner.deleted ~= true
        and activeOwner.sharpMovementEnabled == true
end

function clientModules.characterTools.isStandardSharpMovementActive()
    return boostActive
        and activeOwner == "Standard"
        and clientModules.characterTools.sharpMovementEnabled == true
end

function clientModules.characterTools.shouldUseSharpMovement()
    return clientModules.characterTools.isStandardSharpMovementActive()
        or clientModules.characterTools.isAbilitySharpMovementActive()
end

function clientModules.characterTools.setSharpMovementEnabled(enabled, silent)
    clientModules.characterTools.sharpMovementEnabled = enabled == true

    setSwitchVisual(
        clientModules.characterTools.sharpMovementButton,
        clientModules.characterTools.sharpMovementDot,
        clientModules.characterTools.sharpMovementEnabled
    )

    if not silent then
        setStatus(
            clientModules.characterTools.sharpMovementEnabled
                and "Sharp Movement enabled for Standard Boost."
                or "Sharp Movement disabled for Standard Boost.",
            clientModules.characterTools.sharpMovementEnabled and COLORS.Green or COLORS.MutedText
        )
    end
end

function clientModules.speedControl.applyVelocity(humanoid, rootPart)
    if clientModules.speedControl.activeMethod ~= "Velocity"
        or clientModules.infFlight.enabled
        or clientModules.flight.enabled
        or not humanoid
        or humanoid.Health <= 0
        or not rootPart
        or not rootPart:IsA("BasePart")
        or rootPart.Anchored then
        return
    end

    local moveDirection = humanoid.MoveDirection
    local horizontalDirection = Vector3.new(moveDirection.X, 0, moveDirection.Z)

    if horizontalDirection.Magnitude <= 0.001 then
        return
    end

    local velocity = rootPart.AssemblyLinearVelocity
    local currentHorizontal = Vector3.new(velocity.X, 0, velocity.Z)
    local currentSpeed = currentHorizontal.Magnitude
    local targetSpeed = math.max(tonumber(expectedWalkSpeed) or 0, 0)

    -- Never clamp, cancel or redirect motion that is already faster than the
    -- boost target. This preserves the game's own dash / slide / knockback.
    if currentSpeed >= targetSpeed - 0.01 then
        return
    end

    local addSpeed = targetSpeed - currentSpeed
    local newHorizontal = currentHorizontal + horizontalDirection.Unit * addSpeed

    rootPart.AssemblyLinearVelocity = Vector3.new(
        newHorizontal.X,
        velocity.Y,
        newHorizontal.Z
    )
end

function clientModules.characterTools.applySharpMovement()
    if not clientModules.characterTools.shouldUseSharpMovement() then
        return
    end

    -- Inf Flight already owns velocity; do not fight its controller.
    if clientModules.infFlight.enabled or clientModules.flight.enabled then
        return
    end

    local character, humanoid, rootPart = getCharacterParts()
    if not character
        or not humanoid
        or humanoid.Health <= 0
        or not rootPart
        or rootPart.Anchored then
        return
    end

    local moveDirection = humanoid.MoveDirection
    local velocity = rootPart.AssemblyLinearVelocity
    local horizontalDirection = Vector3.new(moveDirection.X, 0, moveDirection.Z)
    local grounded = humanoid.FloorMaterial ~= Enum.Material.Air

    local targetSpeed = tonumber(expectedWalkSpeed)
        or tonumber(humanoid.WalkSpeed)
        or 0

    targetSpeed = math.max(targetSpeed, 0)

    if horizontalDirection.Magnitude > 0.001 then
        horizontalDirection = horizontalDirection.Unit
        local horizontalVelocity = horizontalDirection * targetSpeed

        -- Keep Y unchanged so jumps and falls keep their vertical motion.
        rootPart.AssemblyLinearVelocity = Vector3.new(
            horizontalVelocity.X,
            velocity.Y,
            horizontalVelocity.Z
        )
    elseif grounded then
        -- No ground input means no leftover horizontal slide.
        rootPart.AssemblyLinearVelocity = Vector3.new(
            0,
            velocity.Y,
            0
        )
    end
end

function clientModules.characterTools.restoreNoclip()
    for part, originalCanCollide in pairs(clientModules.characterTools.noclipStates) do
        if part and part.Parent then
            pcall(function()
                part.CanCollide = originalCanCollide
            end)
        end
    end
    table.clear(clientModules.characterTools.noclipStates)
end

function clientModules.characterTools.rebuildNoclipParts(character)
    clientModules.characterTools.noclipCharacter = character
    table.clear(clientModules.characterTools.noclipParts)

    if not character then
        return
    end

    for _, descendant in ipairs(character:GetDescendants()) do
        if descendant:IsA("BasePart") then
            table.insert(clientModules.characterTools.noclipParts, descendant)
        end
    end
end

function clientModules.characterTools.applyNoclip()
    if not clientModules.characterTools.shouldNoclip() then
        return
    end

    local character = localPlayer.Character
    if not character or character ~= clientModules.characterTools.noclipCharacter then
        clientModules.characterTools.rebuildNoclipParts(character)
    end

    for _, descendant in ipairs(clientModules.characterTools.noclipParts) do
        if descendant and descendant.Parent and descendant:IsA("BasePart") then
            if clientModules.characterTools.noclipStates[descendant] == nil then
                clientModules.characterTools.noclipStates[descendant] = descendant.CanCollide
            end
            if descendant.CanCollide then
                descendant.CanCollide = false
            end
        end
    end
end

function clientModules.characterTools.refreshVisuals()
    if clientModules.characterTools.noclipButton then
        setSwitchVisual(
            clientModules.characterTools.noclipButton,
            clientModules.characterTools.noclipDot,
            clientModules.characterTools.noclipEnabled
        )
    end
    if clientModules.characterTools.infinityJumpButton then
        setSwitchVisual(
            clientModules.characterTools.infinityJumpButton,
            clientModules.characterTools.infinityJumpDot,
            clientModules.characterTools.infinityJumpEnabled
        )
    end
end

function clientModules.characterTools.setNoclipEnabled(enabled, silent)
    clientModules.characterTools.noclipEnabled = enabled == true

    if not clientModules.characterTools.noclipEnabled
        and not clientModules.characterTools.isAbilityNoclipActive() then
        clientModules.characterTools.restoreNoclip()
        table.clear(clientModules.characterTools.noclipParts)
        clientModules.characterTools.noclipCharacter = nil
    end

    if clientModules.characterTools.noclipEnabled or clientModules.characterTools.isAbilityNoclipActive() then
        if not clientModules.characterTools.noclipConnection then
            clientModules.characterTools.noclipConnection = RunService.Stepped:Connect(function()
                if not guiDestroyed then
                    clientModules.characterTools.applyNoclip()
                end
            end)
        end
        if not clientModules.characterTools.noclipCharacterConnection then
            clientModules.characterTools.noclipCharacterConnection = localPlayer.CharacterAdded:Connect(function(character)
                clientModules.characterTools.rebuildNoclipParts(character)
                clientModules.characterTools.restoreNoclip()
                clientModules.characterTools.applyNoclip()
            end)
        end
        clientModules.characterTools.rebuildNoclipParts(localPlayer.Character)
        clientModules.characterTools.applyNoclip()
    elseif clientModules.characterTools.noclipConnection then
        clientModules.characterTools.noclipConnection:Disconnect()
        clientModules.characterTools.noclipConnection = nil
        if clientModules.characterTools.noclipCharacterConnection then
            clientModules.characterTools.noclipCharacterConnection:Disconnect()
            clientModules.characterTools.noclipCharacterConnection = nil
        end
    end

    clientModules.characterTools.refreshVisuals()

    if not silent then
        setStatus(
            clientModules.characterTools.noclipEnabled and "Noclip enabled." or "Noclip disabled.",
            clientModules.characterTools.noclipEnabled and COLORS.Green or COLORS.MutedText
        )
    end
end

function clientModules.characterTools.setInfinityJumpEnabled(enabled, silent)
    clientModules.characterTools.infinityJumpEnabled = enabled == true
    clientModules.characterTools.refreshVisuals()

    if not silent then
        setStatus(
            clientModules.characterTools.infinityJumpEnabled and "Infinity Jump enabled." or "Infinity Jump disabled.",
            clientModules.characterTools.infinityJumpEnabled and COLORS.Green or COLORS.MutedText
        )
    end
end

function clientModules.characterTools.performInfinityJump()
    if not clientModules.characterTools.shouldInfinityJump() then
        return
    end

    local character, humanoid, rootPart = getCharacterParts()
    if not character or humanoid.Health <= 0 then
        return
    end

    local jumpVelocity = 50
    pcall(function()
        if humanoid.UseJumpPower then
            jumpVelocity = math.max(0, humanoid.JumpPower)
        else
            jumpVelocity = math.sqrt(math.max(0, 2 * workspace.Gravity * humanoid.JumpHeight))
        end
    end)

    humanoid.Jump = true
    pcall(function()
        humanoid:ChangeState(Enum.HumanoidStateType.Jumping)
    end)

    if rootPart and not rootPart.Anchored then
        local velocity = rootPart.AssemblyLinearVelocity
        rootPart.AssemblyLinearVelocity = Vector3.new(
            velocity.X,
            math.max(velocity.Y, jumpVelocity),
            velocity.Z
        )
    end
end


function getBackpack()
    return localPlayer:FindFirstChildOfClass("Backpack") or localPlayer:FindFirstChild("Backpack")
end

function clientModules.inventoryOrder.capture()
    if clientModules.inventoryOrder.restoring then
        return
    end

    local names = {}
    local backpack = getBackpack()

    if backpack then
        for _, child in ipairs(backpack:GetChildren()) do
            if child:IsA("Tool") then
                table.insert(names, child.Name)
            end
        end
    end

    -- An equipped Tool is parented to Character. Keep it in the snapshot as well.
    -- If it is not already represented, append it so it is not lost after respawn.
    local character = localPlayer.Character
    if character then
        for _, child in ipairs(character:GetChildren()) do
            if child:IsA("Tool") then
                local represented = false
                for _, savedName in ipairs(names) do
                    if savedName == child.Name then
                        represented = true
                        break
                    end
                end
                if not represented then
                    table.insert(names, child.Name)
                end
            end
        end
    end

    if #names > 0 then
        clientModules.inventoryOrder.savedNames = names
    end
end

function clientModules.inventoryOrder.restore()
    if not clientModules.inventoryOrder.enabled
        or clientModules.inventoryOrder.restoring
        or #clientModules.inventoryOrder.savedNames == 0
        or guiDestroyed then
        return
    end

    local backpack = getBackpack()
    if not backpack then
        return
    end

    local tools = {}
    for _, child in ipairs(backpack:GetChildren()) do
        if child:IsA("Tool") then
            table.insert(tools, child)
        end
    end

    if #tools <= 1 then
        return
    end

    local ordered = {}
    local used = setmetatable({}, { __mode = "k" })

    -- Match duplicate tool names one-by-one in their saved slot order.
    for _, savedName in ipairs(clientModules.inventoryOrder.savedNames) do
        for _, tool in ipairs(tools) do
            if not used[tool] and tool.Name == savedName then
                used[tool] = true
                table.insert(ordered, tool)
                break
            end
        end
    end

    -- Keep newly granted / unknown tools after the restored slots.
    for _, tool in ipairs(tools) do
        if not used[tool] then
            table.insert(ordered, tool)
        end
    end

    if #ordered ~= #tools then
        return
    end

    clientModules.inventoryOrder.restoring = true

    -- Roblox's default Backpack hotbar follows Tool insertion order.
    -- Temporarily remove the Tools locally, then add them back in the saved order.
    local tempFolder = Instance.new("Folder")
    tempFolder.Name = "PulseCoreInventoryReorderTemp"
    tempFolder.Parent = localPlayer

    local ok = pcall(function()
        for _, tool in ipairs(ordered) do
            tool.Parent = tempFolder
        end
        for _, tool in ipairs(ordered) do
            tool.Parent = backpack
        end
    end)

    tempFolder:Destroy()
    clientModules.inventoryOrder.restoring = false

    if ok then
        clientModules.inventoryOrder.capture()
    end
end

function clientModules.inventoryOrder.scheduleRestore()
    clientModules.inventoryOrder.restoreSerial = clientModules.inventoryOrder.restoreSerial + 1
    local serial = clientModules.inventoryOrder.restoreSerial

    -- Games often give Tools in several waves after respawn. Retry a few times.
    for _, delaySeconds in ipairs({0.8, 1.8, 3.5, 5.5}) do
        task.delay(delaySeconds, function()
            if guiDestroyed
                or not clientModules.inventoryOrder.enabled
                or serial ~= clientModules.inventoryOrder.restoreSerial then
                return
            end
            clientModules.inventoryOrder.restore()
        end)
    end
end

function clientModules.inventoryOrder.bindCharacter(character)
    if clientModules.inventoryOrder.deathConnection then
        clientModules.inventoryOrder.deathConnection:Disconnect()
        clientModules.inventoryOrder.deathConnection = nil
    end

    if not character then
        return
    end

    local humanoid = character:FindFirstChildOfClass("Humanoid")
        or character:WaitForChild("Humanoid", 5)

    if humanoid then
        clientModules.inventoryOrder.deathConnection = humanoid.Died:Connect(function()
            if clientModules.inventoryOrder.enabled then
                clientModules.inventoryOrder.capture()
            end
        end)
    end
end

function clientModules.inventoryOrder.refreshVisuals()
    if clientModules.inventoryOrder.toggleButton then
        setSwitchVisual(
            clientModules.inventoryOrder.toggleButton,
            clientModules.inventoryOrder.toggleDot,
            clientModules.inventoryOrder.enabled
        )
    end
end

function clientModules.inventoryOrder.setEnabled(enabled, silent)
    clientModules.inventoryOrder.enabled = enabled == true
    clientModules.inventoryOrder.restoreSerial = clientModules.inventoryOrder.restoreSerial + 1

    if clientModules.inventoryOrder.enabled then
        clientModules.inventoryOrder.capture()
        clientModules.inventoryOrder.bindCharacter(localPlayer.Character)

        if not clientModules.inventoryOrder.characterConnection then
            clientModules.inventoryOrder.characterConnection = localPlayer.CharacterAdded:Connect(function(character)
                clientModules.inventoryOrder.bindCharacter(character)
                clientModules.inventoryOrder.scheduleRestore()
            end)
        end

        local backpack = getBackpack()
        if backpack and not clientModules.inventoryOrder.backpackAddedConnection then
            clientModules.inventoryOrder.backpackAddedConnection = backpack.ChildAdded:Connect(function(child)
                if clientModules.inventoryOrder.enabled
                    and child:IsA("Tool")
                    and not clientModules.inventoryOrder.restoring then
                    -- Late-granted Tools get another restore attempt after the grant settles.
                    task.delay(0.35, function()
                        if clientModules.inventoryOrder.enabled and not guiDestroyed then
                            clientModules.inventoryOrder.restore()
                        end
                    end)
                end
            end)
        end
    else
        if clientModules.inventoryOrder.characterConnection then
            clientModules.inventoryOrder.characterConnection:Disconnect()
            clientModules.inventoryOrder.characterConnection = nil
        end
        if clientModules.inventoryOrder.deathConnection then
            clientModules.inventoryOrder.deathConnection:Disconnect()
            clientModules.inventoryOrder.deathConnection = nil
        end
        if clientModules.inventoryOrder.backpackAddedConnection then
            clientModules.inventoryOrder.backpackAddedConnection:Disconnect()
            clientModules.inventoryOrder.backpackAddedConnection = nil
        end
    end

    clientModules.inventoryOrder.refreshVisuals()

    if not silent then
        setStatus(
            clientModules.inventoryOrder.enabled
                and "Inventory order preservation enabled."
                or "Inventory order preservation disabled.",
            clientModules.inventoryOrder.enabled and COLORS.Green or COLORS.MutedText
        )
    end
end

function clientModules.inventoryOrder.shutdown()
    clientModules.inventoryOrder.setEnabled(false, true)
    clientModules.inventoryOrder.savedNames = {}
end

function clientModules.characterTools.initialize()
    clientModules.inventoryOrder.refreshVisuals()

    if not clientModules.characterTools.jumpConnection then
        clientModules.characterTools.jumpConnection = UserInputService.JumpRequest:Connect(function()
            if not guiDestroyed then
                clientModules.characterTools.performInfinityJump()
            end
        end)
    end

    if not clientModules.characterTools.sharpMovementConnection then
        clientModules.characterTools.sharpMovementConnection = RunService.Heartbeat:Connect(function()
            if not guiDestroyed then
                clientModules.characterTools.applySharpMovement()
            end
        end)
    end
end

function clientModules.characterTools.shutdown()
    clientModules.characterTools.noclipEnabled = false
    clientModules.characterTools.infinityJumpEnabled = false
    clientModules.characterTools.sharpMovementEnabled = false
    if clientModules.characterTools.noclipConnection then
        clientModules.characterTools.noclipConnection:Disconnect()
        clientModules.characterTools.noclipConnection = nil
    end
    if clientModules.characterTools.noclipCharacterConnection then
        clientModules.characterTools.noclipCharacterConnection:Disconnect()
        clientModules.characterTools.noclipCharacterConnection = nil
    end
    table.clear(clientModules.characterTools.noclipParts)
    clientModules.characterTools.noclipCharacter = nil
    if clientModules.characterTools.jumpConnection then
        clientModules.characterTools.jumpConnection:Disconnect()
        clientModules.characterTools.jumpConnection = nil
    end
    if clientModules.characterTools.sharpMovementConnection then
        clientModules.characterTools.sharpMovementConnection:Disconnect()
        clientModules.characterTools.sharpMovementConnection = nil
    end
    clientModules.characterTools.restoreNoclip()
end

function stopStatusUpdater()
    if statusConnection then
        statusConnection:Disconnect()
        statusConnection = nil
    end
end

function nearlyEqual(a, b)
    return math.abs(a - b) <= 0.001
end

function clientModules.animationLock.isMovementTrack(track)
    if not track then
        return false
    end

    local animation = track.Animation
    local combinedName = string.lower(
        tostring(track.Name or "") .. " " .. tostring(animation and animation.Name or "")
    )

    -- Core is also used by idle, jump, fall, emote, and other non-locomotion
    -- tracks. Treating every Core track as movement makes all of them speed up.
    local excludedNames = {
        "idle", "jump", "fall", "climb", "swim", "emote", "dance",
        "sit", "tool", "attack", "hit", "hurt", "death", "die", "fly",
    }

    for _, excludedName in ipairs(excludedNames) do
        if string.find(combinedName, excludedName, 1, true) then
            return false
        end
    end

    local hasMovementName = string.find(combinedName, "walk", 1, true) ~= nil
        or string.find(combinedName, "run", 1, true) ~= nil
        or string.find(combinedName, "sprint", 1, true) ~= nil
        or string.find(combinedName, "jog", 1, true) ~= nil
        or string.find(combinedName, "move", 1, true) ~= nil

    return hasMovementName or track.Priority == Enum.AnimationPriority.Movement
end

function clientModules.animationLock.disconnect()
    if clientModules.animationLock.renderConnection then
        clientModules.animationLock.renderConnection:Disconnect()
        clientModules.animationLock.renderConnection = nil
    end

    if clientModules.animationLock.animationPlayedConnection then
        clientModules.animationLock.animationPlayedConnection:Disconnect()
        clientModules.animationLock.animationPlayedConnection = nil
    end

    -- Restore the exact playback speed that existed before the Boost touched the track.
    for track, record in pairs(clientModules.animationLock.tracks) do
        local neutralSpeed = record and tonumber(record.neutralSpeed) or 1

        if track and track.IsPlaying then
            pcall(function()
                track:AdjustSpeed(neutralSpeed)
            end)
        end
    end

    clientModules.animationLock.humanoid = nil
    clientModules.animationLock.animator = nil
    clientModules.animationLock.tracks = setmetatable({}, { __mode = "k" })
end

function clientModules.animationLock.getBoostAnimationSpeed()
    -- Match movement animation speed to the WalkSpeed multiplier.
    -- A cap keeps animations readable even when a very large boost is selected.
    local normalSpeed = tonumber(baseWalkSpeed) or 16
    local boostedSpeed = tonumber(expectedWalkSpeed) or normalSpeed

    if normalSpeed <= 0.001 then
        normalSpeed = 16
    end

    -- Set mode may intentionally choose a value below the base WalkSpeed.
    return math.clamp(boostedSpeed / normalSpeed, 0.1, 4)
end

function clientModules.animationLock.getNeutralSpeed(track)
    local speed = track and tonumber(track.Speed) or nil
    return speed and speed > 0.001 and speed or 1
end

function clientModules.animationLock.getTrackBoostedSpeed(track, fallbackNeutralSpeed)
    local record = clientModules.animationLock.tracks[track]
    local neutralSpeed = record and tonumber(record.neutralSpeed)
        or tonumber(fallbackNeutralSpeed)
        or clientModules.animationLock.getNeutralSpeed(track)

    return neutralSpeed * clientModules.animationLock.getBoostAnimationSpeed()
end

function clientModules.animationLock.captureTrack(track, neutralSpeed, speedAlreadyBoosted)
    if not clientModules.animationLock.isMovementTrack(track)
        or clientModules.animationLock.tracks[track] ~= nil then
        return clientModules.animationLock.tracks[track]
    end

    neutralSpeed = tonumber(neutralSpeed)
        or clientModules.animationLock.getNeutralSpeed(track)

    if speedAlreadyBoosted then
        local multiplier = clientModules.animationLock.getBoostAnimationSpeed()
        if multiplier > 0.001 then
            neutralSpeed = neutralSpeed / multiplier
        end
    end

    local record = {
        neutralSpeed = math.max(neutralSpeed, 0.001),
    }
    clientModules.animationLock.tracks[track] = record
    return record
end

function clientModules.animationLock.attach(humanoid)
    clientModules.animationLock.disconnect()

    if not humanoid or not humanoid.Parent then
        return
    end

    local animator = humanoid:FindFirstChildOfClass("Animator")
    if not animator then
        animator = humanoid:FindFirstChild("Animator")
    end
    if not animator then
        return
    end

    clientModules.animationLock.humanoid = humanoid
    clientModules.animationLock.animator = animator

    -- Capture currently playing movement tracks before WalkSpeed is boosted.
    for _, track in ipairs(animator:GetPlayingAnimationTracks()) do
        clientModules.animationLock.captureTrack(track, nil, false)
    end

    clientModules.animationLock.animationPlayedConnection = animator.AnimationPlayed:Connect(function(track)
        task.defer(function()
            if guiDestroyed
                or not boostActive
                or humanoid ~= clientModules.animationLock.humanoid
                or not track then
                return
            end

            clientModules.animationLock.captureTrack(track, nil, true)
        end)
    end)

    clientModules.animationLock.renderConnection = RunService.RenderStepped:Connect(function()
        if guiDestroyed
            or not boostActive
            or humanoid ~= boostedHumanoid
            or animator ~= clientModules.animationLock.animator then
            return
        end

        for _, track in ipairs(animator:GetPlayingAnimationTracks()) do
            clientModules.animationLock.captureTrack(track, nil, true)
        end

        for track in pairs(clientModules.animationLock.tracks) do
            if track and track.IsPlaying then
                pcall(function()
                    local targetSpeed = clientModules.animationLock.getTrackBoostedSpeed(track)
                    if math.abs((tonumber(track.Speed) or targetSpeed) - targetSpeed) > 0.01 then
                        track:AdjustSpeed(targetSpeed)
                    end
                end)
            end
        end
    end)
end

function disconnectWalkSpeedWatcher()
    if walkSpeedConnection then
        walkSpeedConnection:Disconnect()
        walkSpeedConnection = nil
    end
end

function setWalkSpeedSafely(humanoid, value)
    if not humanoid or not humanoid.Parent then
        return
    end

    applyingWalkSpeed = true
    humanoid.WalkSpeed = value
    applyingWalkSpeed = false
end

function applyBoostedWalkSpeed()
    if not boostedHumanoid
        or not boostedHumanoid.Parent
        or baseWalkSpeed == nil then
        return
    end

    expectedWalkSpeed = clientModules.speedControl.calculateTarget(
        baseWalkSpeed,
        activeBonus,
        clientModules.speedControl.activeMode
    )

    if clientModules.speedControl.activeMethod ~= "WalkSpeed" then
        return
    end

    if not nearlyEqual(boostedHumanoid.WalkSpeed, expectedWalkSpeed) then
        setWalkSpeedSafely(boostedHumanoid, expectedWalkSpeed)
    end
end

function attachBoostToHumanoid(humanoid)
    disconnectWalkSpeedWatcher()

    boostedHumanoid = humanoid
    baseWalkSpeed = humanoid.WalkSpeed
    expectedWalkSpeed = clientModules.speedControl.calculateTarget(
        baseWalkSpeed,
        activeBonus,
        clientModules.speedControl.activeMode
    )
    clientModules.animationLock.attach(humanoid)

    if clientModules.speedControl.activeMethod ~= "WalkSpeed" then
        return
    end

    walkSpeedConnection = humanoid:GetPropertyChangedSignal("WalkSpeed"):Connect(function()
        if not boostActive
            or humanoid ~= boostedHumanoid
            or applyingWalkSpeed then
            return
        end

        local currentWalkSpeed = humanoid.WalkSpeed

        if expectedWalkSpeed and nearlyEqual(currentWalkSpeed, expectedWalkSpeed) then
            return
        end

        -- Внешнее значение считаем новой стандартной скоростью.
        baseWalkSpeed = currentWalkSpeed
        applyBoostedWalkSpeed()
    end)

    applyBoostedWalkSpeed()
end

function restoreWalkSpeed()
    disconnectWalkSpeedWatcher()
    clientModules.animationLock.disconnect()

    if clientModules.speedControl.activeMethod == "WalkSpeed"
        and boostedHumanoid
        and boostedHumanoid.Parent
        and baseWalkSpeed ~= nil then
        setWalkSpeedSafely(boostedHumanoid, baseWalkSpeed)
    end

    boostedHumanoid = nil
    baseWalkSpeed = nil
    expectedWalkSpeed = nil
    applyingWalkSpeed = false
end

function clientModules.jumpBoost.disconnect()
    if clientModules.jumpBoost.stateConnection then
        clientModules.jumpBoost.stateConnection:Disconnect()
        clientModules.jumpBoost.stateConnection = nil
    end

    clientModules.jumpBoost.humanoid = nil
    clientModules.jumpBoost.rootPart = nil
    clientModules.jumpBoost.lastJumpAt = 0
end

function clientModules.jumpBoost.apply(rootPart)
    local jumpBonus = tonumber(clientModules.jumpBoost.activeBonus) or 0

    if not boostActive
        or jumpBonus <= 0
        or not rootPart
        or not rootPart.Parent
        or not rootPart:IsA("BasePart") then
        return
    end

    local velocity = rootPart.AssemblyLinearVelocity
    rootPart.AssemblyLinearVelocity = Vector3.new(
        velocity.X,
        velocity.Y + jumpBonus,
        velocity.Z
    )
end

function clientModules.jumpBoost.attach(humanoid, rootPart)
    clientModules.jumpBoost.disconnect()

    if not humanoid or not humanoid.Parent or not rootPart or not rootPart.Parent then
        return
    end

    clientModules.jumpBoost.humanoid = humanoid
    clientModules.jumpBoost.rootPart = rootPart

    clientModules.jumpBoost.stateConnection = humanoid.StateChanged:Connect(function(_, newState)
        if newState ~= Enum.HumanoidStateType.Jumping
            or not boostActive
            or humanoid ~= clientModules.jumpBoost.humanoid then
            return
        end

        local now = os.clock()
        if now - (clientModules.jumpBoost.lastJumpAt or 0) < 0.1 then
            return
        end
        clientModules.jumpBoost.lastJumpAt = now

        task.defer(function()
            RunService.PostSimulation:Wait()

            if not boostActive
                or humanoid ~= clientModules.jumpBoost.humanoid
                or humanoid.Health <= 0 then
                return
            end

            local _, currentHumanoid, currentRootPart = getCharacterParts()
            if currentHumanoid ~= humanoid or not currentRootPart then
                return
            end

            clientModules.jumpBoost.apply(currentRootPart)
        end)
    end)
end

function isAbilityOwner(owner)
    return type(owner) == "table" and owner.isSpeedAbility == true
end

function ownerName(owner)
    if owner == "Standard" then
        return "Standard Boost"
    end

    if isAbilityOwner(owner) then
        local abilityName = owner.name or string.format("Ability %d", owner.index or 1)
        return string.format("%s [%s]", abilityName, owner.key.Name)
    end

    return "Speed Boost"
end

function clientModules.boostTabs.formatSeconds(seconds, infiniteWhenNil)
    if seconds == nil and infiniteWhenNil then
        return "inf"
    end

    return string.format("%.1fs", math.max(tonumber(seconds) or 0, 0))
end

function clientModules.boostTabs.update()
    if not clientModules.boostTabs.contentLabel then
        return
    end

    local entries = {}
    local now = time()

    local function addOwner(owner)
        local record = clientModules.cooldown.getRecord(owner)
        local name = ownerName(owner)

        if boostPending and pendingOwner == owner then
            local delayRemaining = pendingUntil and math.max(pendingUntil - now, 0) or 0
            local durationText = clientModules.boostTabs.formatSeconds(pendingDuration, true)
            local cooldownSeconds = 0

            if record and record.pendingCooldownEnabled == true then
                cooldownSeconds = tonumber(record.pendingCooldownSeconds) or 0
            end

            table.insert(entries, string.format(
                "[DELAY] %s\n  %s / %s | activation: %.1fs | duration: %s | cooldown: %.1fs",
                name,
                clientModules.speedControl.pendingMethod or "WalkSpeed",
                clientModules.speedControl.getModeLabel(clientModules.speedControl.pendingMode),
                delayRemaining,
                durationText,
                cooldownSeconds
            ))
            return
        end

        if boostActive and activeOwner == owner then
            local durationRemaining = activeUntil and math.max(activeUntil - now, 0) or nil
            local durationText = clientModules.boostTabs.formatSeconds(durationRemaining, true)
            local cooldownText = "off"

            if record and record.cooldownArmed == true then
                cooldownText = clientModules.boostTabs.formatSeconds(record.activeCooldownSeconds, false) .. " after stop"
            end

            table.insert(entries, string.format(
                "[ACTIVE] %s\n  %s / %s | duration: %s | delay: complete | cooldown: %s",
                name,
                clientModules.speedControl.activeMethod,
                clientModules.speedControl.getModeLabel(clientModules.speedControl.activeMode),
                durationText,
                cooldownText
            ))
            return
        end

        local cooldownRemaining = clientModules.cooldown.getRemaining(owner)
        if cooldownRemaining > 0 then
            table.insert(entries, string.format(
                "[COOLDOWN] %s\n  remaining: %.1fs",
                name,
                cooldownRemaining
            ))
        end
    end

    addOwner("Standard")
    for _, ability in ipairs(abilities) do
        if not ability.deleted then
            addOwner(ability)
        end
    end

    if #entries == 0 then
        clientModules.boostTabs.contentLabel.Text = "No active boosts, delays, or cooldowns."
        clientModules.boostTabs.contentLabel.TextColor3 = COLORS.MutedText
    else
        clientModules.boostTabs.contentLabel.Text = table.concat(entries, "\n\n")
        clientModules.boostTabs.contentLabel.TextColor3 = COLORS.Text
    end
end

function clientModules.boostTabs.refreshVisuals()
    if clientModules.boostTabs.toggleButton and clientModules.boostTabs.toggleDot then
        setSwitchVisual(
            clientModules.boostTabs.toggleButton,
            clientModules.boostTabs.toggleDot,
            clientModules.boostTabs.enabled
        )
    end

    if clientModules.boostTabs.window then
        clientModules.boostTabs.window.Visible = clientModules.boostTabs.enabled
    end
end

function clientModules.boostTabs.setEnabled(enabled, silent)
    clientModules.boostTabs.enabled = enabled == true
    clientModules.boostTabs.refreshVisuals()

    if clientModules.boostTabs.enabled then
        clientModules.boostTabs.update()

        if not clientModules.boostTabs.updateConnection then
            clientModules.boostTabs.updateAccumulator = 0
            clientModules.boostTabs.updateConnection = RunService.Heartbeat:Connect(function(deltaTime)
                clientModules.boostTabs.updateAccumulator = clientModules.boostTabs.updateAccumulator + deltaTime

                if clientModules.boostTabs.updateAccumulator >= 0.1 then
                    clientModules.boostTabs.updateAccumulator = 0
                    clientModules.boostTabs.update()
                end
            end)
        end
    elseif clientModules.boostTabs.updateConnection then
        clientModules.boostTabs.updateConnection:Disconnect()
        clientModules.boostTabs.updateConnection = nil
    end

    if not silent then
        visualsStatusLabel.Text = clientModules.boostTabs.enabled
            and "Boost Tabs window enabled."
            or "Boost Tabs window disabled."
        visualsStatusLabel.TextColor3 = clientModules.boostTabs.enabled and COLORS.Green or COLORS.MutedText
    end
end

function clientModules.boostTabs.shutdown()
    if clientModules.boostTabs.updateConnection then
        clientModules.boostTabs.updateConnection:Disconnect()
        clientModules.boostTabs.updateConnection = nil
    end
end

function setOwnerStatus(owner, text, color)
    if isAbilityOwner(owner) and owner.statusLabel then
        owner.statusLabel.Text = text
        owner.statusLabel.TextColor3 = color or COLORS.MutedText
        logPulseCoreStatus((owner.name or ("Ability " .. tostring(owner.index or "?"))) .. ": " .. tostring(text or ""), color)
    else
        setStatus(text, color)
    end
end

function ownerIsRunning(owner)
    return (boostActive and activeOwner == owner)
        or (boostPending and pendingOwner == owner)
end

function updateAbilityButton(ability)
    if not ability or not ability.activateButton then
        return
    end

    local abilityName = ability.name or string.format("Ability %d", ability.index or 1)

    if ownerIsRunning(ability) then
        ability.activateButton.Text = string.format("STOP %s", abilityName)
        ability.activateButton.BackgroundColor3 = COLORS.Red
        ability.activateButton.TextColor3 = COLORS.White
    else
        local cooldownRemaining = clientModules.cooldown.getRemaining(ability)
        if cooldownRemaining > 0 then
            ability.activateButton.Text = string.format("COOLDOWN %s: %.1f sec.", abilityName, cooldownRemaining)
            ability.activateButton.BackgroundColor3 = COLORS.Input
            ability.activateButton.TextColor3 = COLORS.Yellow
        else
            ability.activateButton.Text = string.format("ACTIVATE %s [%s]", abilityName, ability.key.Name)
            ability.activateButton.BackgroundColor3 = COLORS.Cyan
            ability.activateButton.TextColor3 = COLORS.CyanDeep
        end
    end
end

function updateActivateButton()
    if ownerIsRunning("Standard") then
        activateButton.Text = "STOP SPEED BOOST"
        activateButton.BackgroundColor3 = COLORS.Red
        activateButton.TextColor3 = COLORS.White
    else
        local cooldownRemaining = clientModules.cooldown.getRemaining("Standard")
        if cooldownRemaining > 0 then
            activateButton.Text = string.format("COOLDOWN SPEED BOOST: %.1f sec.", cooldownRemaining)
            activateButton.BackgroundColor3 = COLORS.Input
            activateButton.TextColor3 = COLORS.Yellow
        else
            activateButton.Text = "ACTIVATE SPEED BOOST"
            activateButton.BackgroundColor3 = COLORS.Cyan
            activateButton.TextColor3 = COLORS.CyanDeep
        end
    end
end

function updateAllBoostButtons()
    updateActivateButton()

    for _, ability in ipairs(abilities) do
        updateAbilityButton(ability)
    end
end

function clientModules.cooldown.getRecord(owner)
    if owner == "Standard" then
        return clientModules.cooldown.standard
    end

    if isAbilityOwner(owner) then
        return owner
    end

    return nil
end

function clientModules.cooldown.getRemaining(owner)
    local record = clientModules.cooldown.getRecord(owner)
    if not record or record.cooldownEnabled ~= true then
        return 0
    end

    return math.max((record.cooldownUntil or 0) - time(), 0)
end

function clientModules.cooldown.isBlocked(owner)
    local remaining = clientModules.cooldown.getRemaining(owner)
    if remaining <= 0 then
        return false
    end

    setOwnerStatus(
        owner,
        string.format("%s: cooldown, %.1f sec. remaining.", ownerName(owner), remaining),
        COLORS.Yellow
    )
    updateAllBoostButtons()
    return true
end

function clientModules.cooldown.arm(owner, config)
    local record = clientModules.cooldown.getRecord(owner)
    if not record then
        return
    end

    if config.skipCooldownArm then
        return
    end

    record.cooldownArmed = config.cooldownEnabled == true and (config.cooldownSeconds or 0) > 0
    record.activeCooldownSeconds = record.cooldownArmed and config.cooldownSeconds or 0
    record.pendingCooldownEnabled = nil
    record.pendingCooldownSeconds = nil
end

function clientModules.cooldown.start(owner)
    local record = clientModules.cooldown.getRecord(owner)
    if not record or not record.cooldownArmed then
        return
    end

    local seconds = math.max(tonumber(record.activeCooldownSeconds) or 0, 0)
    record.cooldownArmed = false
    record.activeCooldownSeconds = 0

    if seconds <= 0 then
        return
    end

    record.cooldownUntil = time() + seconds
    record.cooldownSerial = (record.cooldownSerial or 0) + 1
    local serial = record.cooldownSerial
    updateAllBoostButtons()

    task.delay(seconds, function()
        if guiDestroyed or record.cooldownSerial ~= serial then
            return
        end

        record.cooldownUntil = 0
        updateAllBoostButtons()
        setOwnerStatus(owner, ownerName(owner) .. ": cooldown finished.", COLORS.Green)
    end)
end

function clientModules.cooldown.clearArm(owner)
    local record = clientModules.cooldown.getRecord(owner)
    if not record then
        return
    end

    record.cooldownArmed = false
    record.activeCooldownSeconds = 0
    record.pendingCooldownEnabled = nil
    record.pendingCooldownSeconds = nil
end

function clientModules.cooldown.resetRecord(record)
    if not record then
        return
    end

    record.cooldownUntil = 0
    record.cooldownArmed = false
    record.activeCooldownSeconds = 0
    record.pendingCooldownEnabled = nil
    record.pendingCooldownSeconds = nil
    record.cooldownSerial = (record.cooldownSerial or 0) + 1
end

function clientModules.cooldown.resetAll()
    clientModules.cooldown.resetRecord(clientModules.cooldown.standard)
    for _, ability in ipairs(abilities) do
        clientModules.cooldown.resetRecord(ability)
    end
    updateAllBoostButtons()
end

resumeStandardBoost = nil

function stopBoost(message, options)
    options = options or {}

    local stoppedOwner = activeOwner or pendingOwner

    activationSerial = activationSerial + 1
    boostActive = false
    boostPending = false
    activeUntil = nil
    activeOwner = nil
    pendingOwner = nil
    pendingBonus = nil
    clientModules.speedControl.pendingMethod = nil
    clientModules.speedControl.pendingMode = nil
    clientModules.jumpBoost.pendingBonus = nil
    pendingDuration = nil
    pendingUntil = nil

    if movementConnection then
        movementConnection:Disconnect()
        movementConnection = nil
    end

    clientModules.jumpBoost.disconnect()
    clientModules.jumpBoost.activeBonus = 0
    clientModules.jumpBoost.pendingBonus = nil
    restoreWalkSpeed()
    stopStatusUpdater()

    if options.preserveCooldownArm then
        -- Standard Boost временно приостановлен способностью; его cooldown начнётся после окончательного отключения.
    elseif options.suppressCooldown then
        clientModules.cooldown.clearArm(stoppedOwner)
    else
        clientModules.cooldown.start(stoppedOwner)
    end

    updateAllBoostButtons()

    if stoppedOwner then
        setOwnerStatus(stoppedOwner, message or (ownerName(stoppedOwner) .. " disabled."), COLORS.MutedText)
    else
        setStatus(message or "Speed Boost disabled.", COLORS.MutedText)
    end

    if isAbilityOwner(stoppedOwner)
        and resumeStandardAfterAbility
        and standardResumeSnapshot
        and not options.suppressStandardResume
        and not guiDestroyed then
        local snapshot = standardResumeSnapshot
        resumeStandardAfterAbility = false
        standardResumeSnapshot = nil

        task.defer(function()
            if not guiDestroyed then
                resumeStandardBoost(snapshot)
            end
        end)
    elseif not options.preserveStandardResume and stoppedOwner == "Standard" then
        resumeStandardAfterAbility = false
        standardResumeSnapshot = nil
    end
end

function startStatusUpdater(serial, owner)
    stopStatusUpdater()

    local updateAccumulator = 0
    statusConnection = RunService.Heartbeat:Connect(function(deltaTime)
        if serial ~= activationSerial
            or not boostActive
            or activeOwner ~= owner then
            return
        end

        updateAccumulator = updateAccumulator + deltaTime

        if updateAccumulator < 0.1 then
            return
        end

        updateAccumulator = 0

        local baseSpeed = baseWalkSpeed or 0
        local totalSpeed = expectedWalkSpeed or clientModules.speedControl.calculateTarget(
            baseSpeed,
            activeBonus,
            clientModules.speedControl.activeMode
        )
        local prefix = ownerName(owner)

        if activeUntil then
            local remaining = math.max(activeUntil - time(), 0)
            setOwnerStatus(
                owner,
                string.format(
                    "%s: %s / %s • base %.1f • value %.1f • target %.1f • jump +%.1f • %.1f sec. remaining.",
                    prefix,
                    clientModules.speedControl.activeMethod,
                    clientModules.speedControl.getModeLabel(clientModules.speedControl.activeMode),
                    baseSpeed,
                    activeBonus,
                    totalSpeed,
                    clientModules.jumpBoost.activeBonus or 0,
                    remaining
                ),
                COLORS.Green
            )
        else
            setOwnerStatus(
                owner,
                string.format(
                    "%s: %s / %s • base %.1f • value %.1f • target %.1f • jump +%.1f • duration inf.",
                    prefix,
                    clientModules.speedControl.activeMethod,
                    clientModules.speedControl.getModeLabel(clientModules.speedControl.activeMode),
                    baseSpeed,
                    activeBonus,
                    totalSpeed,
                    clientModules.jumpBoost.activeBonus or 0
                ),
                COLORS.Green
            )
        end
    end)
end

function beginBoost(config, serial, owner)
    if serial ~= activationSerial or guiDestroyed then
        return
    end

    local speedBonus = config.speedBonus
    local jumpBonus = config.jumpBoostEnabled == true and (config.jumpBonus or 0) or 0
    local duration = config.duration
    local character, humanoid, rootPart = getCharacterParts()

    if not character then
        stopBoost("Character is not loaded yet.")
        setOwnerStatus(owner, "Character is not loaded yet.", COLORS.Red)
        return
    end

    if rootPart.Anchored then
        stopBoost("HumanoidRootPart is anchored. Speed Boost cannot be applied.")
        setOwnerStatus(owner, "HumanoidRootPart is anchored. Speed Boost cannot be applied.", COLORS.Red)
        return
    end

    clientModules.cooldown.arm(owner, config)
    activeBonus = speedBonus
    clientModules.speedControl.activeMethod =
        clientModules.speedControl.normalizeMethod(config.speedMethod)
    clientModules.speedControl.activeMode =
        clientModules.speedControl.normalizeMode(config.speedMode)
    clientModules.jumpBoost.activeBonus = jumpBonus
    boostPending = false
    pendingOwner = nil
    pendingBonus = nil
    clientModules.speedControl.pendingMethod = nil
    clientModules.speedControl.pendingMode = nil
    clientModules.jumpBoost.pendingBonus = nil
    pendingDuration = nil
    pendingUntil = nil
    boostActive = true
    activeOwner = owner
    activeUntil = duration and (time() + duration) or nil

    attachBoostToHumanoid(humanoid)
    clientModules.jumpBoost.attach(humanoid, rootPart)

    updateAllBoostButtons()
    setOwnerStatus(
        owner,
        string.format(
            "%s enabled: %s / %s • base %.1f • value %.1f • target %.1f studs/s • Jump Boost: %s.",
            ownerName(owner),
            clientModules.speedControl.activeMethod,
            clientModules.speedControl.getModeLabel(clientModules.speedControl.activeMode),
            baseWalkSpeed or 0,
            activeBonus,
            expectedWalkSpeed or 0,
            config.jumpBoostEnabled == true
                and string.format("+%.1f studs/s", clientModules.jumpBoost.activeBonus or 0)
                or "off"
        ),
        COLORS.Green
    )

    movementConnection = RunService.Heartbeat:Connect(function(deltaTime)
        if serial ~= activationSerial
            or not boostActive
            or activeOwner ~= owner then
            return
        end

        local currentCharacter, currentHumanoid, currentRootPart = getCharacterParts()

        if not currentCharacter or not currentHumanoid or not currentRootPart then
            return
        end

        if currentHumanoid ~= boostedHumanoid then
            clientModules.jumpBoost.disconnect()
            restoreWalkSpeed()
            attachBoostToHumanoid(currentHumanoid)
            clientModules.jumpBoost.attach(currentHumanoid, currentRootPart)
            return
        end

        if currentHumanoid.Health <= 0 or applyingWalkSpeed then
            return
        end

        if clientModules.speedControl.activeMethod == "Velocity" then
            baseWalkSpeed = currentHumanoid.WalkSpeed
            applyBoostedWalkSpeed()
            clientModules.speedControl.applyVelocity(currentHumanoid, currentRootPart)
        else
            local currentWalkSpeed = currentHumanoid.WalkSpeed

            if expectedWalkSpeed
                and not nearlyEqual(currentWalkSpeed, expectedWalkSpeed) then
                baseWalkSpeed = currentWalkSpeed
                applyBoostedWalkSpeed()
            end
        end

    end)

    startStatusUpdater(serial, owner)

    if duration then
        task.delay(duration, function()
            if serial == activationSerial
                and boostActive
                and activeOwner == owner then
                stopBoost(ownerName(owner) .. ": duration ended.")
            end
        end)
    end
end

function readBoostConfig(owner, speedInput, speedMethod, speedMode, jumpInput, jumpBoostEnabled, delayInput, durationInput, cooldownInput, cooldownEnabled)
    local speedBonus = parsePositiveNumber(
        speedInput.Text,
        MIN_SPEED_BONUS,
        MAX_SPEED_BONUS
    )
    local jumpBonus = 0
    if jumpBoostEnabled then
        jumpBonus = parsePositiveNumber(
            jumpInput and jumpInput.Text or "0",
            MIN_JUMP_BONUS,
            MAX_JUMP_BONUS
        )
    end
    local delaySeconds = parsePositiveNumber(delayInput.Text, 0, 3600)
    local duration = parseDuration(durationInput.Text)
    local cooldownSeconds = 0

    if cooldownEnabled then
        cooldownSeconds = parsePositiveNumber(cooldownInput and cooldownInput.Text or "0", 0, 86400)
        if cooldownSeconds == nil then
            setOwnerStatus(owner, "Error: cooldown must be a number from 0 to 86400 seconds.", COLORS.Red)
            return nil
        end
    end

    if not speedBonus then
        setOwnerStatus(owner, "Error: speed value must be a number from 1 to 200 studs/s.", COLORS.Red)
        return nil
    end

    if jumpBoostEnabled and jumpBonus == nil then
        setOwnerStatus(owner, "Error: jump bonus must be a number from 0 to 200 studs/s.", COLORS.Red)
        return nil
    end

    if not delaySeconds then
        setOwnerStatus(owner, "Error: delay must be a number from 0 to 3600.", COLORS.Red)
        return nil
    end

    if duration == false then
        setOwnerStatus(owner, "Error: duration must be greater than 0 or equal to inf.", COLORS.Red)
        return nil
    end

    speedInput.Text = formatNumber(speedBonus)
    if jumpInput and jumpBoostEnabled then
        jumpInput.Text = formatNumber(jumpBonus)
    end
    delayInput.Text = formatNumber(delaySeconds)
    durationInput.Text = duration == nil and "inf" or formatNumber(duration)
    if cooldownInput and cooldownEnabled then
        cooldownInput.Text = formatNumber(cooldownSeconds)
    end

    return {
        speedBonus = speedBonus,
        speedMethod = clientModules.speedControl.normalizeMethod(speedMethod),
        speedMode = clientModules.speedControl.normalizeMode(speedMode),
        jumpBonus = jumpBoostEnabled and jumpBonus or 0,
        jumpBoostEnabled = jumpBoostEnabled == true,
        delaySeconds = delaySeconds,
        duration = duration,
        cooldownEnabled = cooldownEnabled == true,
        cooldownSeconds = cooldownSeconds,
    }
end

function scheduleBoost(owner, config, useDelay)
    activationSerial = activationSerial + 1
    local serial = activationSerial
    local cooldownRecord = clientModules.cooldown.getRecord(owner)

    if cooldownRecord then
        cooldownRecord.pendingCooldownEnabled = config.cooldownEnabled == true
        cooldownRecord.pendingCooldownSeconds = config.cooldownSeconds or 0
    end

    if useDelay and config.delaySeconds > 0 then
        boostPending = true
        pendingOwner = owner
        pendingBonus = config.speedBonus
        clientModules.speedControl.pendingMethod = config.speedMethod
        clientModules.speedControl.pendingMode = config.speedMode
        clientModules.jumpBoost.pendingBonus = config.jumpBonus or 0
        pendingDuration = config.duration
        pendingUntil = time() + config.delaySeconds
        activeOwner = nil
        updateAllBoostButtons()
        setOwnerStatus(
            owner,
            string.format("%s will activate in %.1f sec.", ownerName(owner), config.delaySeconds),
            COLORS.Yellow
        )

        task.delay(config.delaySeconds, function()
            if serial == activationSerial
                and boostPending
                and pendingOwner == owner then
                beginBoost(config, serial, owner)
            end
        end)
    else
        pendingOwner = owner
        pendingUntil = nil
        clientModules.speedControl.pendingMethod = config.speedMethod
        clientModules.speedControl.pendingMode = config.speedMode
        clientModules.jumpBoost.pendingBonus = config.jumpBonus or 0
        beginBoost(config, serial, owner)
    end
end

function captureStandardResumeSnapshot()
    if boostActive and activeOwner == "Standard" then
        local remainingDuration = nil

        if activeUntil then
            remainingDuration = math.max(activeUntil - time(), 0)

            if remainingDuration <= 0.01 then
                return nil
            end
        end

        local cooldownRecord = clientModules.cooldown.standard
        return {
            speedBonus = activeBonus,
            speedMethod = clientModules.speedControl.activeMethod,
            speedMode = clientModules.speedControl.activeMode,
            jumpBonus = clientModules.jumpBoost.activeBonus or 0,
            jumpBoostEnabled = (clientModules.jumpBoost.activeBonus or 0) > 0,
            duration = remainingDuration,
            cooldownEnabled = cooldownRecord.cooldownEnabled == true,
            cooldownSeconds = cooldownRecord.activeCooldownSeconds or 0,
            cooldownWasArmed = cooldownRecord.cooldownArmed == true,
        }
    end

    if boostPending and pendingOwner == "Standard" then
        local cooldownRecord = clientModules.cooldown.standard
        return {
            speedBonus = pendingBonus or DEFAULT_SPEED_BONUS,
            speedMethod = clientModules.speedControl.pendingMethod or "WalkSpeed",
            speedMode = clientModules.speedControl.pendingMode or "Add",
            jumpBonus = clientModules.jumpBoost.pendingBonus or 0,
            jumpBoostEnabled = (clientModules.jumpBoost.pendingBonus or 0) > 0,
            duration = pendingDuration,
            cooldownEnabled = cooldownRecord.pendingCooldownEnabled == true,
            cooldownSeconds = cooldownRecord.pendingCooldownSeconds or 0,
            cooldownWasArmed = false,
        }
    end

    return nil
end

resumeStandardBoost = function(snapshot)
    if guiDestroyed or not snapshot or boostActive or boostPending then
        return
    end

    if snapshot.duration and snapshot.duration <= 0.01 then
        setStatus("Standard Boost was not restored because its duration ended.", COLORS.MutedText)
        return
    end

    setStatus("Ability disabled. Restoring Standard Boost...", COLORS.Yellow)

    scheduleBoost("Standard", {
        speedBonus = snapshot.speedBonus,
        speedMethod = snapshot.speedMethod,
        speedMode = snapshot.speedMode,
        jumpBonus = snapshot.jumpBonus or 0,
        jumpBoostEnabled = snapshot.jumpBoostEnabled == true,
        delaySeconds = 0,
        duration = snapshot.duration,
        cooldownEnabled = snapshot.cooldownEnabled == true,
        cooldownSeconds = snapshot.cooldownSeconds or 0,
        skipCooldownArm = snapshot.cooldownWasArmed == true,
    }, false)
end

function requestBoost()
    setStatus("Checking Standard Boost settings...", COLORS.Yellow)

    if ownerIsRunning("Standard") then
        resumeStandardAfterAbility = false
        standardResumeSnapshot = nil
        stopBoost("Standard Boost disabled.")
        return
    end

    if clientModules.cooldown.isBlocked("Standard") then
        return
    end

    local config = readBoostConfig(
        "Standard",
        speedBox,
        clientModules.speedControl.standardMethod,
        clientModules.speedControl.standardMode,
        jumpBox,
        clientModules.jumpBoost.standardEnabled,
        delayBox,
        durationBox,
        clientModules.cooldown.standard.cooldownBox,
        clientModules.cooldown.standard.cooldownEnabled
    )

    if not config then
        return
    end

    if boostActive or boostPending then
        -- Явное включение стандартного буста отменяет текущую способность.
        resumeStandardAfterAbility = false
        standardResumeSnapshot = nil
        stopBoost("Current ability disabled.", {
            suppressStandardResume = true,
            preserveStandardResume = false,
        })
    end

    scheduleBoost("Standard", config, delayEnabled)
end

function requestAbilityBoost(ability)
    if not ability then
        return
    end

    setOwnerStatus(ability, "Checking ability settings...", COLORS.Yellow)

    if ownerIsRunning(ability) then
        stopBoost(ownerName(ability) .. " disabled.")
        return
    end

    if clientModules.cooldown.isBlocked(ability) then
        return
    end

    local config = readBoostConfig(
        ability,
        ability.speedBox,
        ability.speedMethod,
        ability.speedMode,
        ability.jumpBox,
        ability.jumpBoostEnabled,
        ability.delayBox,
        ability.durationBox,
        ability.cooldownBox,
        ability.cooldownEnabled
    )

    if not config then
        return
    end

    if ownerIsRunning("Standard") then
        local snapshot = captureStandardResumeSnapshot()

        if snapshot then
            resumeStandardAfterAbility = true
            standardResumeSnapshot = snapshot
        end

        stopBoost("Standard Boost was temporarily disabled by the ability.", {
            suppressStandardResume = true,
            preserveStandardResume = true,
            preserveCooldownArm = true,
        })
    elseif boostActive or boostPending then
        -- Переключение между способностями не включает стандартный буст между ними.
        stopBoost("Previous ability disabled.", {
            suppressStandardResume = true,
            preserveStandardResume = true,
        })
    end

    scheduleBoost(ability, config, ability.delayEnabled)
end

function safeRequestStandardBoost()
    local now = os.clock()

    if now - (activateButton:GetAttribute("LastActivation") or 0) < 0.15 then
        return
    end

    activateButton:SetAttribute("LastActivation", now)

    local ok, errorMessage = pcall(requestBoost)

    if not ok then
        logPulseCoreError("Standard Boost error:\n" .. tostring(errorMessage))
        warn("[Speed Boost] Standard Boost error:\n" .. tostring(errorMessage))
        setStatus("Activation error: " .. tostring(errorMessage), COLORS.Red)
    end
end

function safeRequestAbility(ability)
    local now = os.clock()

    if now - (ability.lastActivation or 0) < 0.15 then
        return
    end

    ability.lastActivation = now

    local ok, errorMessage = pcall(requestAbilityBoost, ability)

    if not ok then
        logPulseCoreError("Ability error:\n" .. tostring(errorMessage))
        warn("[Speed Boost] Ability error:\n" .. tostring(errorMessage))
        setOwnerStatus(ability, "Activation error: " .. tostring(errorMessage), COLORS.Red)
    end
end

function getBindingButton(target)
    if target == "Boost" then
        return clientModules.keyList.buttons.Boost or boostKeyButton
    end

    if target == "Interface" then
        return clientModules.keyList.buttons.Interface or interfaceKeyButton
    end

    if target == "Noclip" then return clientModules.keyList.buttons.Noclip end
    if target == "Flight" then return clientModules.keyList.buttons.Flight end
    if isAbilityOwner(target) then
        return clientModules.keyList.abilityButtons[target.index] or target.keyButton
    end

    return nil
end

function getBindingKey(target)
    if target == "Boost" then return clientModules.keyList.state.boostKey end
    if target == "Interface" then return clientModules.keyList.state.interfaceKey end
    if target == "Noclip" then return clientModules.keyList.state.noclipKey end
    if target == "Flight" then return clientModules.keyList.state.flightKey end
    if isAbilityOwner(target) then
        return target.key
    end

    return Enum.KeyCode.Unknown
end

function keyIsUsedByOther(newKey, target)
    local entries = {
        {"Boost", clientModules.keyList.state.boostKey},
        {"Interface", clientModules.keyList.state.interfaceKey},
        {"Noclip", clientModules.keyList.state.noclipKey},
        {"Flight", clientModules.keyList.state.flightKey},
    }

    for _, entry in ipairs(entries) do
        if entry[1] ~= target and entry[2] == newKey then
            return entry[1]
        end
    end

    for _, ability in ipairs(abilities) do
        if ability ~= target and ability.key == newKey then
            return ability.name or string.format("ability %d", ability.index)
        end
    end

    return nil
end

function finishBinding(newKey)
    local target = clientModules.keyList.state.bindingTarget
    clientModules.keyList.state.bindingTarget = nil

    if not target then
        return
    end

    local button = getBindingButton(target)
    local previousKey = getBindingKey(target)

    if newKey == Enum.KeyCode.Escape then
        if button then
            button.Text = clientModules.keyList.state.bindingPreviousText or previousKey.Name
        end

        clientModules.keyList.state.bindingPreviousText = nil
        setOwnerStatus(isAbilityOwner(target) and target or "Standard", "Key change cancelled.", COLORS.MutedText)
        return
    end

    local usedBy = keyIsUsedByOther(newKey, target)

    if usedBy then
        if button then
            button.Text = previousKey.Name
        end

        clientModules.keyList.state.bindingPreviousText = nil
        setOwnerStatus(
            isAbilityOwner(target) and target or "Standard",
            "This key is already used for " .. usedBy .. ".",
            COLORS.Red
        )
        return
    end

    if target == "Boost" then
        clientModules.keyList.state.boostKey = newKey
        boostKeyButton.Text = newKey.Name
        clientModules.keyList.buttons.Boost.Text = newKey.Name
        setStatus("Speed Boost key changed to " .. newKey.Name .. ".", COLORS.Green)
    elseif target == "Interface" then
        clientModules.keyList.state.interfaceKey = newKey
        interfaceKeyButton.Text = newKey.Name
        clientModules.keyList.buttons.Interface.Text = newKey.Name
        setStatus("Interface key changed to " .. newKey.Name .. ".", COLORS.Green)
    elseif target == "Noclip" then
        clientModules.keyList.state.noclipKey = newKey
        clientModules.keyList.buttons.Noclip.Text = newKey.Name
    elseif target == "Flight" then
        clientModules.keyList.state.flightKey = newKey
        clientModules.keyList.buttons.Flight.Text = newKey.Name
        clientModules.flight.refreshVisuals()
        setStatus("Flight key changed to " .. newKey.Name .. ".", COLORS.Green)
    elseif isAbilityOwner(target) then
        target.key = newKey
        target.keyButton.Text = newKey.Name
        if clientModules.keyList.abilityButtons[target.index] then
            clientModules.keyList.abilityButtons[target.index].Text = newKey.Name
        end
        updateAbilityButton(target)
        setOwnerStatus(target, "Ability key changed to " .. newKey.Name .. ".", COLORS.Green)
    end

    if clientModules.keyList.status then
        clientModules.keyList.status.Text = "Changed " .. (isAbilityOwner(target) and target.name or tostring(target)) .. " to " .. newKey.Name .. "."
        clientModules.keyList.status.TextColor3 = COLORS.Green
    end

    clientModules.keyList.state.bindingPreviousText = nil
end

function beginBinding(target)
    if clientModules.keyList.state.bindingTarget then
        return
    end

    local button = getBindingButton(target)

    if not button then
        return
    end

    clientModules.keyList.state.bindingTarget = target
    clientModules.keyList.state.bindingPreviousText = button.Text
    button.Text = "Press any key..."
end

clientModules.abilityUI = clientModules.abilityUI or {}

function clientModules.abilityUI.createAbilityStatus(layoutOrder)
    return create("TextLabel", {
        LayoutOrder = layoutOrder,
        Size = UDim2.new(1, 0, 0, 40),
        BackgroundTransparency = 1,
        Text = "Ability ready.",
        Font = Enum.Font.GothamMedium,
        TextSize = 12,
        TextColor3 = COLORS.MutedText,
        TextWrapped = true,
        TextXAlignment = Enum.TextXAlignment.Left,
        TextYAlignment = Enum.TextYAlignment.Center,
    }, localPage)
end

function clientModules.abilityUI.trimText(value)
    local text = tostring(value or "")
    text = string.gsub(text, "^%s+", "")
    text = string.gsub(text, "%s+$", "")
    return text
end

function clientModules.abilityUI.clampTextLength(text, maximumLength)
    if utf8.len(text) and utf8.len(text) > maximumLength then
        local byteIndex = utf8.offset(text, maximumLength + 1)

        if byteIndex then
            return string.sub(text, 1, byteIndex - 1)
        end
    end

    return text
end

function clientModules.abilityUI.updateAddAbilityButton()
    local maximumReached = #abilities >= MAX_ABILITIES

    addAbilityButton.Text = maximumReached and "Maximum abilities: 4" or "Add a new ability"
    addAbilityButton.Active = not maximumReached
    addAbilityButton.Selectable = not maximumReached
    addAbilityButton.AutoButtonColor = not maximumReached
    addAbilityButton.BackgroundColor3 = maximumReached and COLORS.Input or COLORS.CyanDark
    addAbilityButton.TextColor3 = maximumReached and COLORS.MutedText or COLORS.Text
end

function clientModules.abilityUI.findAbilitySlot(preferredSlot)
    local usedSlots = {}

    for _, ability in ipairs(abilities) do
        usedSlots[ability.slot or ability.index] = true
    end

    if type(preferredSlot) == "number"
        and preferredSlot >= 1
        and preferredSlot <= MAX_ABILITIES
        and not usedSlots[preferredSlot] then
        return preferredSlot
    end

    for slot = 1, MAX_ABILITIES do
        if not usedSlots[slot] then
            return slot
        end
    end

    return nil
end

function clientModules.abilityUI.keyCodeFromName(keyName, fallback)
    if type(keyName) == "string" then
        local ok, result = pcall(function()
            return Enum.KeyCode[keyName]
        end)

        if ok and result and result ~= Enum.KeyCode.Unknown then
            return result
        end
    end

    return fallback
end

function clientModules.abilityUI.createAbilityHeader(ability, layoutOrder)
    local row = create("Frame", {
        LayoutOrder = layoutOrder,
        Size = UDim2.new(1, 0, 0, 52),
        BackgroundColor3 = COLORS.CyanDeep,
        BackgroundTransparency = 0.16,
        BorderSizePixel = 0,
    }, localPage)
    addCorner(row, 12)
    addStroke(row, COLORS.Cyan, 0.58, 1)

    local nameBox = create("TextBox", {
        AnchorPoint = Vector2.new(0, 0.5),
        Position = UDim2.new(0, 10, 0.5, 0),
        Size = UDim2.new(1, -166, 0, 34),
        BackgroundColor3 = COLORS.Input,
        BackgroundTransparency = 0.04,
        BorderSizePixel = 0,
        ClearTextOnFocus = false,
        Text = ability.name,
        PlaceholderText = "Ability name",
        PlaceholderColor3 = COLORS.MutedText,
        Font = Enum.Font.GothamBold,
        TextSize = 13,
        TextColor3 = COLORS.Text,
        TextXAlignment = Enum.TextXAlignment.Left,
    }, row)
    addCorner(nameBox, 9)
    addStroke(nameBox, COLORS.Cyan, 0.55, 1)
    create("UIPadding", {
        PaddingLeft = UDim.new(0, 10),
        PaddingRight = UDim.new(0, 10),
    }, nameBox)

    local deleteButton = create("TextButton", {
        AnchorPoint = Vector2.new(1, 0.5),
        Position = UDim2.new(1, -10, 0.5, 0),
        Size = UDim2.fromOffset(136, 34),
        BackgroundColor3 = COLORS.Red,
        BackgroundTransparency = 0.11,
        BorderSizePixel = 0,
        Text = "Delete Ability",
        Font = Enum.Font.GothamBold,
        TextSize = 11,
        TextColor3 = COLORS.White,
        AutoButtonColor = true,
        Active = true,
        Selectable = true,
    }, row)
    addCorner(deleteButton, 9)

    return row, nameBox, deleteButton
end

function clientModules.abilityUI.destroyAbilityUI(ability)
    if not ability then
        return
    end

    for _, object in ipairs(ability.uiObjects or {}) do
        if object and object.Parent then
            object:Destroy()
        end
    end

    ability.uiObjects = {}
end

function clientModules.abilityUI.removeAbilityFromList(ability)
    for index, item in ipairs(abilities) do
        if item == ability then
            table.remove(abilities, index)
            return true
        end
    end

    return false
end

clientModules.abilityUI.deleteAbility = nil
clientModules.abilityUI.addNewAbility = nil

function clientModules.abilityUI.renameAbility(ability, newName, silent)
    if not ability or ability.deleted then
        return
    end

    local fallbackName = string.format("Ability %d", ability.slot or ability.index or 1)
    local cleanedName = clientModules.abilityUI.clampTextLength(clientModules.abilityUI.trimText(newName), MAX_CONFIG_NAME_LENGTH)

    if cleanedName == "" then
        cleanedName = fallbackName
    end

    ability.name = cleanedName

    if ability.nameBox then
        ability.nameBox.Text = cleanedName
    end

    updateAbilityButton(ability)

    if not silent then
        setOwnerStatus(ability, "Name changed to '" .. cleanedName .. "'.", COLORS.Green)
    end
end

clientModules.abilityUI.deleteAbility = function(ability, options)
    options = options or {}

    if not ability or ability.deleted then
        return
    end

    local displayName = ability.name or string.format("Ability %d", ability.index or 1)

    if clientModules.keyList.state.bindingTarget == ability then
        clientModules.keyList.state.bindingTarget = nil
        clientModules.keyList.state.bindingPreviousText = nil
    end

    if ownerIsRunning(ability) and not options.skipStop then
        stopBoost(displayName .. " deleted.", {
            suppressStandardResume = options.suppressStandardResume == true,
            preserveStandardResume = false,
        })
    end

    clientModules.cooldown.resetRecord(ability)
    ability.deleted = true
    clientModules.abilityUI.removeAbilityFromList(ability)
    clientModules.abilityUI.destroyAbilityUI(ability)
    clientModules.abilityUI.updateAddAbilityButton()

    if clientModules.keyList.abilityButtons[ability.index] then
        clientModules.keyList.abilityButtons[ability.index].Text = ABILITY_DEFAULT_KEYS[ability.index].Name
        clientModules.keyList.abilityButtons[ability.index].TextColor3 = COLORS.MutedText
    end

    if not options.silent then
        setStatus("Deleted ability '" .. displayName .. "'.", COLORS.Green)
    end
end

clientModules.abilityUI.addNewAbility = function(configData, options)
    options = options or {}

    if #abilities >= MAX_ABILITIES then
        clientModules.abilityUI.updateAddAbilityButton()
        return nil
    end

    configData = type(configData) == "table" and configData or {}

    local slot = clientModules.abilityUI.findAbilitySlot(tonumber(configData.slot))

    if not slot then
        clientModules.abilityUI.updateAddAbilityButton()
        return nil
    end

    local defaultKey = ABILITY_DEFAULT_KEYS[slot]
    local configuredKey = clientModules.abilityUI.keyCodeFromName(configData.key, defaultKey)
    local baseOrder = 30 + (slot - 1) * 17
    local defaultName = string.format("Ability %d", slot)

    local ability = {
        isSpeedAbility = true,
        index = slot,
        slot = slot,
        name = defaultName,
        key = configuredKey,
        speedMethod = "WalkSpeed",
        speedMode = clientModules.speedControl.normalizeMode(configData.speedMode),
        delayEnabled = configData.delayEnabled == true,
        cooldownEnabled = configData.cooldownEnabled == true,
        jumpBoostEnabled = configData.jumpBoostEnabled == nil
            and tonumber(configData.jump or 0) ~= 0
            or configData.jumpBoostEnabled == true,
        noclipEnabled = configData.noclipEnabled == true,
        infinityJumpEnabled = configData.infinityJumpEnabled == true,
        sharpMovementEnabled = configData.sharpMovementEnabled == true,
        cooldownUntil = 0,
        cooldownArmed = false,
        activeCooldownSeconds = 0,
        cooldownSerial = 0,
        lastActivation = 0,
        uiObjects = {},
    }

    ability.headerRow, ability.nameBox, ability.deleteButton = clientModules.abilityUI.createAbilityHeader(ability, baseOrder)
    if clientModules.keyList.abilityButtons[slot] then
        clientModules.keyList.abilityButtons[slot].Text = ability.key.Name
        clientModules.keyList.abilityButtons[slot].TextColor3 = COLORS.Text
    end

    ability.speedBox = createInputRow(
        localPage,
        "Ability speed value, studs/s",
        tostring(configData.speed or DEFAULT_SPEED_BONUS),
        "Example: 16",
        baseOrder + 1
    )

    ability.speedMethodButton = clientModules.speedControl.createChoiceRow(
        localPage,
        "Ability speed method",
        clientModules.speedControl.getMethodLabel(ability.speedMethod),
        baseOrder + 2
    )

    ability.speedModeButton = clientModules.speedControl.createChoiceRow(
        localPage,
        "Ability speed calculation",
        clientModules.speedControl.getModeLabel(ability.speedMode),
        baseOrder + 3
    )

    local jumpDefaultValue = configData.jump
    if jumpDefaultValue == nil then
        jumpDefaultValue = options.silent and 0 or DEFAULT_JUMP_BONUS
    end

    ability.jumpBox = createInputRow(
        localPage,
        "Ability jump bonus, studs/s",
        tostring(jumpDefaultValue),
        "Example: 50",
        baseOrder + 4
    )

    enforceIntegerTextBox(ability.speedBox, MIN_SPEED_BONUS, MAX_SPEED_BONUS)
    enforceIntegerTextBox(ability.jumpBox, MIN_JUMP_BONUS, MAX_JUMP_BONUS)

    ability.jumpBoostToggleButton, ability.jumpBoostToggleDot = createToggleRow(
        localPage,
        "Use Jump Boost",
        baseOrder + 5
    )

    ability.sharpMovementButton, ability.sharpMovementDot = createToggleRow(
        localPage,
        "Sharp Movement / Anti-Slide",
        baseOrder + 6
    )

    ability.delayBox = createInputRow(
        localPage,
        "Activation delay, seconds",
        tostring(configData.delay or "0"),
        "Example: 3",
        baseOrder + 7
    )

    ability.durationBox = createInputRow(
        localPage,
        "Duration, seconds or inf",
        tostring(configData.duration or "inf"),
        "inf or 10",
        baseOrder + 8
    )

    ability.cooldownBox = createInputRow(
        localPage,
        "Ability cooldown, seconds",
        tostring(configData.cooldown or "0"),
        "Example: 5",
        baseOrder + 9
    )

    ability.toggleButton, ability.toggleDot = createToggleRow(
        localPage,
        "Use ability activation delay",
        baseOrder + 10
    )

    ability.cooldownToggleButton, ability.cooldownToggleDot = createToggleRow(
        localPage,
        "Use cooldown",
        baseOrder + 11
    )

    ability.noclipButton, ability.noclipDot = createToggleRow(
        localPage,
        "Noclip while this Ability is active",
        baseOrder + 12
    )

    ability.infinityJumpButton, ability.infinityJumpDot = createToggleRow(
        localPage,
        "Infinity Jump while this Ability is active",
        baseOrder + 13
    )

    ability.keyButton = createKeybindRow(
        localPage,
        "Ability hotkey",
        configuredKey.Name,
        baseOrder + 14
    )

    ability.statusLabel = clientModules.abilityUI.createAbilityStatus(baseOrder + 15)

    ability.activateButton = create("TextButton", {
        LayoutOrder = baseOrder + 16,
        Size = UDim2.new(1, 0, 0, 38),
        BackgroundColor3 = COLORS.Cyan,
        BackgroundTransparency = 0.11,
        BorderSizePixel = 0,
        Text = "",
        Font = Enum.Font.GothamBold,
        TextSize = 13,
        TextColor3 = COLORS.CyanDeep,
        AutoButtonColor = true,
        Active = true,
        Selectable = true,
    }, localPage)
    addCorner(ability.activateButton, 12)
    addStroke(ability.activateButton, COLORS.White, 0.72, 1)

    ability.uiObjects = {
        ability.headerRow,
        ability.speedBox.Parent,
        ability.speedMethodButton.Parent,
        ability.speedModeButton.Parent,
        ability.jumpBox.Parent,
        ability.jumpBoostToggleButton.Parent,
        ability.sharpMovementButton.Parent,
        ability.delayBox.Parent,
        ability.durationBox.Parent,
        ability.cooldownBox.Parent,
        ability.toggleButton.Parent,
        ability.cooldownToggleButton.Parent,
        ability.noclipButton.Parent,
        ability.infinityJumpButton.Parent,
        ability.keyButton.Parent,
        ability.statusLabel,
        ability.activateButton,
    }

    table.insert(abilities, ability)
    table.sort(abilities, function(left, right)
        return (left.slot or left.index) < (right.slot or right.index)
    end)

    clientModules.abilityUI.renameAbility(ability, configData.name or defaultName, true)

    ability.nameBox.FocusLost:Connect(function()
        clientModules.abilityUI.renameAbility(ability, ability.nameBox.Text, false)
    end)

    ability.deleteButton.Activated:Connect(function()
        clientModules.abilityUI.deleteAbility(ability)
    end)

    ability.speedMethod = "WalkSpeed"
    ability.speedMethodButton.Text = "WalkSpeed"
    ability.speedMethodButton.Parent.Visible = false

    ability.speedMethodButton.Activated:Connect(function()
        ability.speedMethod = "WalkSpeed"
        ability.speedMethodButton.Text = "WalkSpeed"
    end)

    ability.speedModeButton.Activated:Connect(function()
        ability.speedMode = ability.speedMode == "Add" and "Set" or "Add"
        ability.speedModeButton.Text = clientModules.speedControl.getModeLabel(ability.speedMode)
    end)

    ability.toggleButton.Activated:Connect(function()
        ability.delayEnabled = not ability.delayEnabled
        setAbilityDelayVisual(ability)
    end)

    ability.cooldownToggleButton.Activated:Connect(function()
        ability.cooldownEnabled = not ability.cooldownEnabled
        if not ability.cooldownEnabled then
            clientModules.cooldown.resetRecord(ability)
            updateAbilityButton(ability)
        end
        setAbilityCooldownVisual(ability)
    end)

    ability.jumpBoostToggleButton.Activated:Connect(function()
        ability.jumpBoostEnabled = not ability.jumpBoostEnabled
        setSwitchVisual(ability.jumpBoostToggleButton, ability.jumpBoostToggleDot, ability.jumpBoostEnabled)
    end)

    ability.sharpMovementButton.Activated:Connect(function()
        ability.sharpMovementEnabled = not ability.sharpMovementEnabled
        setSwitchVisual(
            ability.sharpMovementButton,
            ability.sharpMovementDot,
            ability.sharpMovementEnabled
        )
    end)

    ability.noclipButton.Activated:Connect(function()
        ability.noclipEnabled = not ability.noclipEnabled
        setSwitchVisual(ability.noclipButton, ability.noclipDot, ability.noclipEnabled)
    end)

    ability.infinityJumpButton.Activated:Connect(function()
        ability.infinityJumpEnabled = not ability.infinityJumpEnabled
        setSwitchVisual(ability.infinityJumpButton, ability.infinityJumpDot, ability.infinityJumpEnabled)
    end)

    ability.keyButton.Activated:Connect(function()
        beginBinding(ability)
    end)

    ability.activateButton.Activated:Connect(function()
        safeRequestAbility(ability)
    end)

    setAbilityDelayVisual(ability)
    setAbilityCooldownVisual(ability)
    setSwitchVisual(ability.jumpBoostToggleButton, ability.jumpBoostToggleDot, ability.jumpBoostEnabled)
    setSwitchVisual(
        ability.sharpMovementButton,
        ability.sharpMovementDot,
        ability.sharpMovementEnabled
    )
    setSwitchVisual(ability.noclipButton, ability.noclipDot, ability.noclipEnabled)
    setSwitchVisual(ability.infinityJumpButton, ability.infinityJumpDot, ability.infinityJumpEnabled)
    updateAbilityButton(ability)
    clientModules.abilityUI.updateAddAbilityButton()

    if not options.silent then
        setStatus(
            string.format("Added ability '%s'. Key: %s.", ability.name, configuredKey.Name),
            COLORS.Green
        )
    end

    return ability
end

function configManager.normalizeConfigName(text)
    local configName = clientModules.abilityUI.clampTextLength(
        clientModules.abilityUI.trimText(text),
        MAX_CONFIG_NAME_LENGTH
    )

    if configName == "" then
        return nil
    end

    if configName == "." or configName == ".."
        or configName:find('[<>:"/\\|?*]')
        or configName:match("[%. ]$")
        or isReservedWindowsConfigName(configName) then
        return nil
    end

    return configName
end

function configManager.getConfigName()
    local configName = configManager.normalizeConfigName(configManager.configNameBox.Text)

    if not configName then
        configManager.configStatusLabel.Text = "Error: enter a config name."
        configManager.configStatusLabel.TextColor3 = COLORS.Red
        return nil
    end

    configManager.configNameBox.Text = configName
    return configName
end

function configManager.getSortedConfigNames()
    local names = {}

    for name in pairs(configManager.savedConfigs) do
        table.insert(names, name)
    end

    table.sort(names, function(left, right)
        return string.lower(left) < string.lower(right)
    end)

    return names
end

function configManager.countSavedConfigs()
    local count = 0

    for _ in pairs(configManager.savedConfigs) do
        count = count + 1
    end

    return count
end

function configManager.updateConfigStatus(message, color)
    local count = configManager.countSavedConfigs()
    local autoLoadText = configManager.autoLoadConfigName or "disabled"
    local selectedText = configManager.selectedConfigName or "none"

    configManager.configStatusLabel.Text = (message and (message .. "\n") or "")
        .. string.format(
            "Saved: %d  •  Selected: %s  •  Auto Load: %s",
            count,
            selectedText,
            autoLoadText
        )
    configManager.configStatusLabel.TextColor3 = color or COLORS.MutedText
end

function configManager.persistConfigs()
    local storageReady, storageError = initializePulseCoreConfigPath()
    if not storageReady then
        configManager.updateConfigStatus(
            storageError or "Config storage is unavailable.",
            COLORS.Red
        )
        return false
    end

    local writeFileApi = getPulseCoreFileApi("writefile")
    local deleteFileApi = getPulseCoreFileApi("delfile")
    local listFilesApi = getPulseCoreFileApi("listfiles")

    local wroteAll = true
    local configNames = {}

    for name, configData in pairs(configManager.savedConfigs) do
        table.insert(configNames, name)

        local filePath = getPulseCoreConfigFilePath(name)

        local ok, encodedOrError = pcall(function()
            return HttpService:JSONEncode(configData)
        end)

        if not ok then
            configManager.updateConfigStatus(
                "Config encoding error: " .. tostring(encodedOrError),
                COLORS.Red
            )
            wroteAll = false
            break
        end

        local saved, saveError = pcall(function()
            writeFileApi(filePath, encodedOrError)
        end)

        if not saved then
            configManager.updateConfigStatus(
                "Config save error: " .. tostring(saveError),
                COLORS.Red
            )
            wroteAll = false
            break
        end
    end

    if not wroteAll then
        return false
    end

    table.sort(configNames)

    if CONFIG_INDEX_FILE then
        local indexOk, indexData = pcall(function()
            return HttpService:JSONEncode(configNames)
        end)

        if not indexOk then
            configManager.updateConfigStatus(
                "Config index encoding error: " .. tostring(indexData),
                COLORS.Red
            )
            return false
        end

        local indexSaved, indexError = pcall(function()
            writeFileApi(CONFIG_INDEX_FILE, indexData)
        end)

        if not indexSaved then
            configManager.updateConfigStatus(
                "Config index save error: " .. tostring(indexError),
                COLORS.Red
            )
            return false
        end
    end

    -- Optional cleanup for executors that expose directory enumeration/deletion.
    if listFilesApi and deleteFileApi then
        local listedOk, files = pcall(listFilesApi, CONFIG_ROOT_PATH)

        if listedOk and type(files) == "table" then
            local activeFiles = {}

            for _, name in ipairs(configNames) do
                activeFiles[name .. CONFIG_FILE_EXTENSION] = true
            end

            if CONFIG_INDEX_FILE then
                local indexName = tostring(CONFIG_INDEX_FILE):match("[^\\/]+$")
                if indexName then
                    activeFiles[indexName] = true
                end
            end

            for _, filePath in ipairs(files) do
                local fileName = tostring(filePath):match("[^\\/]+$")
                if fileName
                    and fileName:sub(-#CONFIG_FILE_EXTENSION) == CONFIG_FILE_EXTENSION
                    and not activeFiles[fileName] then
                    pcall(deleteFileApi, filePath)
                end
            end
        end
    end

    return true
end

function configManager.persistAutoLoadConfig()
    local storageReady, storageError = initializePulseCoreConfigPath()
    if not storageReady then
        configManager.updateConfigStatus(
            storageError or "Config storage is unavailable.",
            COLORS.Red
        )
        return false
    end

    local writeFileApi = getPulseCoreFileApi("writefile")
    local isFileApi = getPulseCoreFileApi("isfile")
    local deleteFileApi = getPulseCoreFileApi("delfile")

    if not configManager.autoLoadConfigName then
        local deleted = true
        if isFileApi and isFileApi(CONFIG_AUTOLOAD_FILE) then
            deleted = pcall(deleteFileApi, CONFIG_AUTOLOAD_FILE)
        end
        return deleted == true
    end

    local saved, saveError = pcall(function()
        writeFileApi(CONFIG_AUTOLOAD_FILE, configManager.autoLoadConfigName)
    end)

    if not saved then
        configManager.updateConfigStatus(
            "Auto Load save error: " .. tostring(saveError),
            COLORS.Red
        )
        return false
    end

    return true
end

function configManager.loadStoredConfigs()
    configManager.savedConfigs = {}
    configManager.autoLoadConfigName = nil

    local readFileApi = getPulseCoreFileApi("readfile")
    local isFileApi = getPulseCoreFileApi("isfile")
    local listFilesApi = getPulseCoreFileApi("listfiles")

    local fileStorageReady, storageError = initializePulseCoreConfigPath()

    if fileStorageReady then
        local loadedFromIndex = false

        if CONFIG_INDEX_FILE then
            local indexExists = true

            if isFileApi then
                indexExists = false
                pcall(function()
                    indexExists = isFileApi(CONFIG_INDEX_FILE)
                end)
            end

            if indexExists then
                local readOk, encodedIndex = pcall(readFileApi, CONFIG_INDEX_FILE)

                if readOk and type(encodedIndex) == "string" and encodedIndex ~= "" then
                    local decodeOk, decodedIndex = pcall(function()
                        return HttpService:JSONDecode(encodedIndex)
                    end)

                    if decodeOk and type(decodedIndex) == "table" then
                        loadedFromIndex = true

                        for _, configName in ipairs(decodedIndex) do
                            if type(configName) == "string" and configName ~= "" then
                                local filePath = getPulseCoreConfigFilePath(configName)
                                local readConfigOk, encodedConfig = pcall(readFileApi, filePath)

                                if readConfigOk and type(encodedConfig) == "string" and encodedConfig ~= "" then
                                    local decodeConfigOk, decodedConfig = pcall(function()
                                        return HttpService:JSONDecode(encodedConfig)
                                    end)

                                    if decodeConfigOk and type(decodedConfig) == "table" then
                                        configManager.savedConfigs[configName] = decodedConfig
                                    end
                                end
                            end
                        end
                    end
                end
            end
        end

        -- Fallback for executors that expose listfiles but have no manifest yet.
        if not loadedFromIndex and listFilesApi then
            local listedOk, files = pcall(listFilesApi, CONFIG_ROOT_PATH)

            if listedOk and type(files) == "table" then
                for _, filePath in ipairs(files) do
                    local fileName = tostring(filePath):match("[^\\/]+$")

                    if fileName
                        and fileName:sub(-#CONFIG_FILE_EXTENSION) == CONFIG_FILE_EXTENSION
                        and fileName ~= "ConfigIndex" .. CONFIG_FILE_EXTENSION
                    then
                        local configName = fileName:sub(1, -#CONFIG_FILE_EXTENSION - 1)

                        local readOk, encoded = pcall(readFileApi, filePath)
                        if readOk and type(encoded) == "string" and encoded ~= "" then
                            local decodeOk, decoded = pcall(function()
                                return HttpService:JSONDecode(encoded)
                            end)

                            if decodeOk and type(decoded) == "table" then
                                configManager.savedConfigs[configName] = decoded
                            end
                        end
                    end
                end
            end
        end

        if CONFIG_AUTOLOAD_FILE then
            local autoLoadExists = true

            if type(isfile) == "function" then
                autoLoadExists = false
                pcall(function()
                    autoLoadExists = isFileApi(CONFIG_AUTOLOAD_FILE)
                end)
            end

            if autoLoadExists then
                local readOk, storedAutoLoad = pcall(readFileApi, CONFIG_AUTOLOAD_FILE)

                if readOk then
                    storedAutoLoad = clientModules.abilityUI.trimText(tostring(storedAutoLoad or ""))

                    if storedAutoLoad ~= ""
                        and type(configManager.savedConfigs[storedAutoLoad]) == "table"
                    then
                        configManager.autoLoadConfigName = storedAutoLoad
                    end
                end
            end
        end

        -- One-time migration from the old LocalPlayer attribute storage.
        if configManager.countSavedConfigs() == 0 then
            local legacyEncoded = localPlayer:GetAttribute(CONFIG_ATTRIBUTE_NAME)

            if type(legacyEncoded) == "string" and legacyEncoded ~= "" then
                local legacyOk, legacyDecoded = pcall(function()
                    return HttpService:JSONDecode(legacyEncoded)
                end)

                if legacyOk and type(legacyDecoded) == "table" then
                    configManager.savedConfigs = legacyDecoded
                    configManager.persistConfigs()

                    local legacyAuto = localPlayer:GetAttribute(AUTO_LOAD_ATTRIBUTE_NAME)

                    if type(legacyAuto) == "string"
                        and type(configManager.savedConfigs[legacyAuto]) == "table"
                    then
                        configManager.autoLoadConfigName = legacyAuto
                        configManager.persistAutoLoadConfig()
                    end
                end
            end
        end

        local pathMessage = CONFIG_PATH_FALLBACK
            and "Executor workspace path: "
            or "Local AppData path: "

        configManager.updateConfigStatus(
            "Configs loaded from local files.\\n"
                .. pathMessage
                .. tostring(CONFIG_ROOT_PATH),
            COLORS.Green
        )
        return
    end

    configManager.updateConfigStatus(
        storageError or "Config storage is unavailable.",
        COLORS.Red
    )
end

function configManager.setConfigManagerButtonState(button, enabled, enabledColor)
    button.Active = enabled
    button.Selectable = enabled
    button.AutoButtonColor = enabled
    button.BackgroundColor3 = enabled and enabledColor or COLORS.Input
    button.BackgroundTransparency = enabled and 0.03 or 0.42
    button.TextColor3 = enabled and COLORS.Text or COLORS.MutedText
end

function configManager.updateConfigManagerSelection()
    local hasSelection = configManager.selectedConfigName ~= nil
        and type(configManager.savedConfigs[configManager.selectedConfigName]) == "table"

    if hasSelection then
        configManager.selectedConfigLabel.Text = "Selected config: " .. configManager.selectedConfigName
        configManager.renameConfigBox.Text = configManager.selectedConfigName
    else
        configManager.selectedConfigName = nil
        configManager.selectedConfigLabel.Text = "Selected config: none"
        configManager.renameConfigBox.Text = ""
    end

    configManager.setConfigManagerButtonState(configManager.deleteConfigButton, hasSelection, COLORS.Red)
    configManager.setConfigManagerButtonState(configManager.editConfigButton, hasSelection, COLORS.CyanDark)
    configManager.setConfigManagerButtonState(configManager.loadConfigButton, hasSelection, COLORS.CyanDark)
    configManager.setConfigManagerButtonState(configManager.autoLoadConfigButton, hasSelection, COLORS.Green)
    configManager.setConfigManagerButtonState(
        configManager.disableAutoLoadButton,
        hasSelection and configManager.autoLoadConfigName == configManager.selectedConfigName,
        COLORS.CyanDark
    )
end

function configManager.refreshConfigList()
    for _, button in ipairs(configManager.configListButtons) do
        if button and button.Parent then
            button:Destroy()
        end
    end
    table.clear(configManager.configListButtons)

    local names = configManager.getSortedConfigNames()

    if configManager.selectedConfigName and not configManager.savedConfigs[configManager.selectedConfigName] then
        configManager.selectedConfigName = nil
    end

    if not configManager.selectedConfigName and #names > 0 then
        configManager.selectedConfigName = names[1]
    end

    for index, name in ipairs(names) do
        local isSelected = name == configManager.selectedConfigName
        local isAutoLoad = name == configManager.autoLoadConfigName
        local button = create("TextButton", {
            LayoutOrder = index,
            Size = UDim2.new(1, -4, 0, 34),
            BackgroundColor3 = isSelected and COLORS.Cyan or COLORS.CyanDeep,
            BackgroundTransparency = isSelected and 0.05 or 0.18,
            BorderSizePixel = 0,
            Text = name .. (isAutoLoad and "  [AUTO]" or ""),
            Font = Enum.Font.GothamBold,
            TextSize = 12,
            TextColor3 = isSelected and COLORS.CyanDeep or COLORS.Text,
            TextXAlignment = Enum.TextXAlignment.Left,
            AutoButtonColor = true,
        }, configManager.configList)
        addCorner(button, 8)
        create("UIPadding", {
            PaddingLeft = UDim.new(0, 10),
            PaddingRight = UDim.new(0, 10),
        }, button)

        button.Activated:Connect(function()
            configManager.selectedConfigName = name
            configManager.refreshConfigList()
            configManager.updateConfigStatus("Selected config '" .. name .. "'.", COLORS.Green)
        end)

        table.insert(configManager.configListButtons, button)
    end

    configManager.updateConfigManagerSelection()
end

function configManager.setConfigListVisible(visible)
    local shouldShow = visible == true
    configManager.configListVisible = shouldShow
    configManager.listConfigsButton.Text = shouldShow and "HIDE CONFIGS" or "LIST CONFIGS"

    configManager.configPanelAnimationSerial = (configManager.configPanelAnimationSerial or 0) + 1
    local serial = configManager.configPanelAnimationSerial

    if shouldShow then
        configManager.configManagerFrame.Visible = true
        configManager.configManagerFrame.Size = UDim2.new(1, 0, 0, 0)

        if configManager.configList then
            configManager.configList.CanvasPosition = Vector2.new(0, 0)
        end

        configManager.refreshConfigList()

        local tween = TweenService:Create(
            configManager.configManagerFrame,
            TweenInfo.new(0.28, Enum.EasingStyle.Quint, Enum.EasingDirection.Out),
            { Size = UDim2.new(1, 0, 0, 312) }
        )
        tween:Play()
    else
        local tween = TweenService:Create(
            configManager.configManagerFrame,
            TweenInfo.new(0.22, Enum.EasingStyle.Quint, Enum.EasingDirection.In),
            { Size = UDim2.new(1, 0, 0, 0) }
        )
        tween:Play()

        task.spawn(function()
            tween.Completed:Wait()
            if serial == configManager.configPanelAnimationSerial
                and not configManager.configListVisible then
                configManager.configManagerFrame.Visible = false
            end
        end)
    end
end

function configManager.captureCurrentConfig()
    local abilityConfigs = {}

    for _, ability in ipairs(abilities) do
        table.insert(abilityConfigs, {
            slot = ability.slot or ability.index,
            name = ability.name,
            key = ability.key.Name,
            speed = ability.speedBox.Text,
            speedMethod = "WalkSpeed",
            speedMode = ability.speedMode,
            jump = ability.jumpBox.Text,
            jumpBoostEnabled = ability.jumpBoostEnabled == true,
            delay = ability.delayBox.Text,
            duration = ability.durationBox.Text,
            cooldown = ability.cooldownBox.Text,
            delayEnabled = ability.delayEnabled,
            cooldownEnabled = ability.cooldownEnabled,
            noclipEnabled = ability.noclipEnabled == true,
            infinityJumpEnabled = ability.infinityJumpEnabled == true,
            sharpMovementEnabled = ability.sharpMovementEnabled == true,
        })
    end

    table.sort(abilityConfigs, function(left, right)
        return (left.slot or 0) < (right.slot or 0)
    end)

    return {
        version = 14,
        standard = {
            speed = speedBox.Text,
            speedMethod = "WalkSpeed",
            speedMode = clientModules.speedControl.standardMode,
            jump = jumpBox.Text,
            jumpBoostEnabled = clientModules.jumpBoost.standardEnabled == true,
            sharpMovementEnabled = clientModules.characterTools.sharpMovementEnabled == true,
            delay = delayBox.Text,
            duration = durationBox.Text,
            cooldown = clientModules.cooldown.standard.cooldownBox.Text,
            delayEnabled = delayEnabled,
            cooldownEnabled = clientModules.cooldown.standard.cooldownEnabled,
            key = clientModules.keyList.state.boostKey.Name,
        },
        interfaceKey = clientModules.keyList.state.interfaceKey.Name,
        localTools = {
            noclip = clientModules.characterTools.noclipEnabled,
            infinityJump = clientModules.characterTools.infinityJumpEnabled,
            flightSpeed = clientModules.flight.getSpeed(),
            flightKey = clientModules.keyList.state.flightKey.Name,
        },
        visuals = {
            survivors = espSurvivorsEnabled,
            executioners = espExecutionersEnabled,
            distance = espDistanceEnabled,
            tracers = espTracersEnabled,
            survivorInfo = espSurvivorInfoEnabled,
            abilities = espAbilitiesEnabled,
            tabs = clientModules.boostTabs.enabled,
        },
        client = {
            autoSelect = {
                enabled = clientModules.autoSelect.enabled,
                selectedCharacter = clientModules.autoSelect.selectedCharacter,
            },
        },
        abilities = abilityConfigs,
    }
end

function configManager.clearAbilitiesForConfigLoad()
    local copy = {}

    for _, ability in ipairs(abilities) do
        table.insert(copy, ability)
    end

    for _, ability in ipairs(copy) do
        clientModules.abilityUI.deleteAbility(ability, {
            silent = true,
            skipStop = true,
            suppressStandardResume = true,
        })
    end
end

function configManager.saveCurrentConfig()
    local configName = configManager.getConfigName()

    if not configName then
        return
    end

    configManager.savedConfigs[configName] = configManager.captureCurrentConfig()
    configManager.selectedConfigName = configName

    if configManager.persistConfigs() then
        configManager.refreshConfigList()
        configManager.updateConfigStatus("Config '" .. configName .. "' saved.", COLORS.Green)
    end
end

function configManager.loadConfigByName(configName, options)
    options = options or {}

    if not configName or type(configManager.savedConfigs[configName]) ~= "table" then
        configManager.updateConfigStatus("Config not found.", COLORS.Red)
        return false
    end

    local configData = configManager.savedConfigs[configName]
    resumeStandardAfterAbility = false
    standardResumeSnapshot = nil

    if boostActive or boostPending then
        stopBoost("Speed Boost disabled before loading the config.", {
            suppressStandardResume = true,
            preserveStandardResume = false,
            suppressCooldown = true,
        })
    end

    configManager.clearAbilitiesForConfigLoad()

    local standard = type(configData.standard) == "table" and configData.standard or {}
    speedBox.Text = tostring(standard.speed or DEFAULT_SPEED_BONUS)
    clientModules.speedControl.standardMethod =
        clientModules.speedControl.normalizeMethod(standard.speedMethod)
    clientModules.speedControl.standardMode =
        clientModules.speedControl.normalizeMode(standard.speedMode)
    clientModules.speedControl.standardMethodButton.Text =
        clientModules.speedControl.getMethodLabel(clientModules.speedControl.standardMethod)
    clientModules.speedControl.standardModeButton.Text =
        clientModules.speedControl.getModeLabel(clientModules.speedControl.standardMode)
    jumpBox.Text = tostring(standard.jump ~= nil and standard.jump or 0)
    if standard.jumpBoostEnabled == nil then
        clientModules.jumpBoost.standardEnabled = tonumber(standard.jump or 0) ~= 0
    else
        clientModules.jumpBoost.standardEnabled = standard.jumpBoostEnabled == true
    end

    clientModules.characterTools.setSharpMovementEnabled(
        standard.sharpMovementEnabled == true,
        true
    )

    delayBox.Text = tostring(standard.delay or "0")
    durationBox.Text = tostring(standard.duration or "inf")
    clientModules.cooldown.standard.cooldownBox.Text = tostring(standard.cooldown or "0")
    delayEnabled = standard.delayEnabled == true
    clientModules.cooldown.standard.cooldownEnabled = standard.cooldownEnabled == true
    clientModules.keyList.state.boostKey = clientModules.abilityUI.keyCodeFromName(standard.key, DEFAULT_BOOST_KEY)
    boostKeyButton.Text = clientModules.keyList.state.boostKey.Name
    clientModules.keyList.buttons.Boost.Text = clientModules.keyList.state.boostKey.Name

    clientModules.keyList.state.interfaceKey = clientModules.abilityUI.keyCodeFromName(configData.interfaceKey, DEFAULT_INTERFACE_KEY)
    interfaceKeyButton.Text = clientModules.keyList.state.interfaceKey.Name
    clientModules.keyList.buttons.Interface.Text = clientModules.keyList.state.interfaceKey.Name

    local localToolsConfig = type(configData.localTools) == "table" and configData.localTools or {}
    clientModules.characterTools.setNoclipEnabled(localToolsConfig.noclip == true, true)
    clientModules.characterTools.setInfinityJumpEnabled(localToolsConfig.infinityJump == true, true)

    clientModules.flight.setEnabled(false, true)
    clientModules.flight.setSpeed(
        tonumber(localToolsConfig.flightSpeed) or DEFAULT_FLIGHT_SPEED,
        true
    )
    clientModules.keyList.state.flightKey =
        clientModules.abilityUI.keyCodeFromName(
            localToolsConfig.flightKey,
            DEFAULT_FLIGHT_KEY
        )
    clientModules.keyList.buttons.Flight.Text = clientModules.keyList.state.flightKey.Name
    clientModules.flight.refreshVisuals()

    local visuals = type(configData.visuals) == "table" and configData.visuals or {}
    espSurvivorsEnabled = visuals.survivors == true
    espExecutionersEnabled = visuals.executioners == true
    espDistanceEnabled = visuals.distance == true
    espTracersEnabled = visuals.tracers == true
    espSurvivorInfoEnabled = visuals.survivorInfo == true
    espAbilitiesEnabled = visuals.abilities == true
    clientModules.boostTabs.setEnabled(false, true)

    local clientConfig = type(configData.client) == "table" and configData.client or {}
    clientModules.autoSelect.loadConfig(clientConfig.autoSelect)

    local abilityConfigs = type(configData.abilities) == "table" and configData.abilities or {}
    table.sort(abilityConfigs, function(left, right)
        return tonumber(left.slot or 0) < tonumber(right.slot or 0)
    end)

    for _, abilityConfig in ipairs(abilityConfigs) do
        if #abilities >= MAX_ABILITIES then
            break
        end

        clientModules.abilityUI.addNewAbility(abilityConfig, { silent = true })
        local latestAbility = abilities[#abilities]
        if latestAbility then
            latestAbility.speedMethod = "WalkSpeed"
            latestAbility.speedMethodButton.Text = "WalkSpeed"
            latestAbility.speedMethodButton.Parent.Visible = false
        end
    end

    clientModules.cooldown.resetAll()
    setToggleVisual()
    setSwitchVisual(
        clientModules.jumpBoost.standardToggleButton,
        clientModules.jumpBoost.standardToggleDot,
        clientModules.jumpBoost.standardEnabled
    )
    setSwitchVisual(
        clientModules.cooldown.standard.toggleButton,
        clientModules.cooldown.standard.toggleDot,
        clientModules.cooldown.standard.cooldownEnabled
    )
    setSwitchVisual(espSurvivorsButton, espSurvivorsDot, espSurvivorsEnabled)
    setSwitchVisual(espExecutionersButton, espExecutionersDot, espExecutionersEnabled)
    clientModules.characterTools.refreshVisuals()
    clientModules.boostTabs.refreshVisuals()
    clientModules.boostTabs.update()
    refreshAllTrackedModels()
    updateAllBoostButtons()
    clientModules.abilityUI.updateAddAbilityButton()

    configManager.selectedConfigName = configName
    configManager.configNameBox.Text = configName
    configManager.refreshConfigList()

    local message = options.auto
        and ("Automatically loaded config '" .. configName .. "'.")
        or ("Config '" .. configName .. "' loaded.")
    configManager.updateConfigStatus(message, COLORS.Green)
    setStatus("Settings loaded from config '" .. configName .. "'.", COLORS.Green)
    return true
end

function configManager.loadSelectedConfig()
    if not configManager.selectedConfigName then
        configManager.updateConfigStatus("Select a config from the list first.", COLORS.Red)
        return
    end

    configManager.loadConfigByName(configManager.selectedConfigName)
end

function configManager.deleteSelectedConfig()
    if not configManager.selectedConfigName or not configManager.savedConfigs[configManager.selectedConfigName] then
        configManager.updateConfigStatus("Select a config from the list first.", COLORS.Red)
        return
    end

    local deletedName = configManager.selectedConfigName
    configManager.savedConfigs[deletedName] = nil

    if configManager.autoLoadConfigName == deletedName then
        configManager.autoLoadConfigName = nil
        configManager.persistAutoLoadConfig()
    end

    configManager.selectedConfigName = nil

    if configManager.persistConfigs() then
        configManager.refreshConfigList()
        configManager.updateConfigStatus("Config '" .. deletedName .. "' deleted.", COLORS.Green)
    end
end

function configManager.editSelectedConfig()
    if not configManager.selectedConfigName or not configManager.savedConfigs[configManager.selectedConfigName] then
        configManager.updateConfigStatus("Select a config from the list first.", COLORS.Red)
        return
    end

    local newName = configManager.normalizeConfigName(configManager.renameConfigBox.Text)
    if not newName then
        configManager.updateConfigStatus("Error: enter a new config name.", COLORS.Red)
        return
    end

    local oldName = configManager.selectedConfigName
    if newName == oldName then
        configManager.updateConfigStatus("The config name was not changed.", COLORS.MutedText)
        return
    end

    if configManager.savedConfigs[newName] then
        configManager.updateConfigStatus("Config '" .. newName .. "' already exists.", COLORS.Red)
        return
    end

    configManager.savedConfigs[newName] = configManager.savedConfigs[oldName]
    configManager.savedConfigs[oldName] = nil
    configManager.selectedConfigName = newName
    configManager.configNameBox.Text = newName

    if configManager.autoLoadConfigName == oldName then
        configManager.autoLoadConfigName = newName
        configManager.persistAutoLoadConfig()
    end

    if configManager.persistConfigs() then
        configManager.refreshConfigList()
        configManager.updateConfigStatus(
            "Config '" .. oldName .. "' renamed to '" .. newName .. "'.",
            COLORS.Green
        )
    end
end

function configManager.enableSelectedConfigAutoLoad()
    if not configManager.selectedConfigName or not configManager.savedConfigs[configManager.selectedConfigName] then
        configManager.updateConfigStatus("Select a config from the list first.", COLORS.Red)
        return
    end

    configManager.autoLoadConfigName = configManager.selectedConfigName

    if configManager.persistAutoLoadConfig() then
        configManager.refreshConfigList()
        configManager.updateConfigStatus(
            "Auto Load enabled for '" .. configManager.selectedConfigName .. "'.",
            COLORS.Green
        )
    end
end

function configManager.disableSelectedConfigAutoLoad()
    if not configManager.selectedConfigName or not configManager.savedConfigs[configManager.selectedConfigName] then
        configManager.updateConfigStatus("Select a config from the list first.", COLORS.Red)
        return
    end

    if configManager.autoLoadConfigName ~= configManager.selectedConfigName then
        configManager.updateConfigStatus(
            "For config '" .. configManager.selectedConfigName .. "', Auto Load is not enabled.",
            COLORS.MutedText
        )
        return
    end

    configManager.autoLoadConfigName = nil

    if configManager.persistAutoLoadConfig() then
        configManager.refreshConfigList()
        configManager.updateConfigStatus("Auto Load disabled.", COLORS.Green)
    end
end

clientModules.tabs.info.Activated:Connect(function()
    selectTab("Info")
end)

localTab.Activated:Connect(function()
    selectTab("Local")
end)

visualsTab.Activated:Connect(function()
    selectTab("Visuals")
end)

clientModules.tabs.fun.Activated:Connect(function()
    selectTab("Fun")
end)

clientModules.tabs.performance.Activated:Connect(function()
    selectTab("Performance")
end)

clientModules.tabs.autoSelect.Activated:Connect(function()
    selectTab("AutoSelect")
end)

clientModules.tabs.keyList.Activated:Connect(function()
    selectTab("KeyList")
end)

settingsTab.Activated:Connect(function()
    selectTab("Settings")
end)

clientModules.keyList.buttons.Boost.Activated:Connect(function() beginBinding("Boost") end)
clientModules.keyList.buttons.Interface.Activated:Connect(function() beginBinding("Interface") end)
clientModules.keyList.buttons.Noclip.Activated:Connect(function() beginBinding("Noclip") end)
clientModules.keyList.buttons.Flight.Activated:Connect(function() beginBinding("Flight") end)
for index = 1, MAX_ABILITIES do
    clientModules.keyList.abilityButtons[index].Activated:Connect(function()
        for _, ability in ipairs(abilities) do
            if ability.index == index then
                beginBinding(ability)
                return
            end
        end
        clientModules.keyList.status.Text = string.format("Ability %d is not created yet.", index)
        clientModules.keyList.status.TextColor3 = COLORS.MutedText
    end)
end

clientModules.speedControl.standardMethodButton.Activated:Connect(function()
    clientModules.speedControl.standardMethod = "WalkSpeed"
    clientModules.speedControl.standardMethodButton.Text = "WalkSpeed"
end)

clientModules.speedControl.standardModeButton.Activated:Connect(function()
    clientModules.speedControl.standardMode =
        clientModules.speedControl.standardMode == "Add" and "Set" or "Add"
    clientModules.speedControl.standardModeButton.Text =
        clientModules.speedControl.getModeLabel(clientModules.speedControl.standardMode)
end)

toggleButton.Activated:Connect(function()
    delayEnabled = not delayEnabled
    setToggleVisual()
end)

clientModules.jumpBoost.standardToggleButton.Activated:Connect(function()
    clientModules.jumpBoost.standardEnabled = not clientModules.jumpBoost.standardEnabled
    setSwitchVisual(
        clientModules.jumpBoost.standardToggleButton,
        clientModules.jumpBoost.standardToggleDot,
        clientModules.jumpBoost.standardEnabled
    )
end)

clientModules.characterTools.sharpMovementButton.Activated:Connect(function()
    clientModules.characterTools.setSharpMovementEnabled(
        not clientModules.characterTools.sharpMovementEnabled,
        false
    )
end)

clientModules.cooldown.standard.toggleButton.Activated:Connect(function()
    clientModules.cooldown.standard.cooldownEnabled = not clientModules.cooldown.standard.cooldownEnabled
    if not clientModules.cooldown.standard.cooldownEnabled then
        clientModules.cooldown.resetRecord(clientModules.cooldown.standard)
        updateActivateButton()
    end
    setSwitchVisual(
        clientModules.cooldown.standard.toggleButton,
        clientModules.cooldown.standard.toggleDot,
        clientModules.cooldown.standard.cooldownEnabled
    )
end)


clientModules.characterTools.noclipButton.Activated:Connect(function()
    clientModules.characterTools.setNoclipEnabled(
        not clientModules.characterTools.noclipEnabled,
        false
    )
end)

clientModules.characterTools.infinityJumpButton.Activated:Connect(function()
    clientModules.characterTools.setInfinityJumpEnabled(
        not clientModules.characterTools.infinityJumpEnabled,
        false
    )
end)

clientModules.inventoryOrder.toggleButton.Activated:Connect(function()
    clientModules.inventoryOrder.enabled = false
    clientModules.inventoryOrder.setEnabled(false, true)
end)

clientModules.infFlight.button.Activated:Connect(function()
    clientModules.infFlight.setEnabled(not clientModules.infFlight.enabled, false)
end)

clientModules.flight.toggleButton.Activated:Connect(function()
    clientModules.flight.setEnabled(not clientModules.flight.enabled, false)
end)

clientModules.flight.speedBox.FocusLost:Connect(function()
    clientModules.flight.setSpeed(clientModules.flight.speedBox.Text, false)
end)

clientModules.flight.sliderTrack.InputBegan:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1
        or input.UserInputType == Enum.UserInputType.Touch then
        clientModules.flight.sliderDragging = true
        clientModules.flight.updateSpeedFromPointer(input.Position.X)
    end
end)

clientModules.flight.sliderTrack.InputEnded:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1
        or input.UserInputType == Enum.UserInputType.Touch then
        clientModules.flight.sliderDragging = false
    end
end)

clientModules.flight.sliderInputConnection = UserInputService.InputChanged:Connect(function(input)
    if not clientModules.flight.sliderDragging then
        return
    end

    if input.UserInputType == Enum.UserInputType.MouseMovement
        or input.UserInputType == Enum.UserInputType.Touch then
        clientModules.flight.updateSpeedFromPointer(input.Position.X)
    end
end)

clientModules.autoSelect.toggleButton.Activated:Connect(function()
    clientModules.autoSelect.setEnabled(not clientModules.autoSelect.enabled, false)
end)

clientModules.performance.modeButton.Activated:Connect(function()
    clientModules.performance.setModeEnabled(
        not clientModules.performance.modeEnabled,
        false
    )
end)

clientModules.performance.particlesButton.Activated:Connect(function()
    clientModules.performance.setParticlesDisabled(
        not clientModules.performance.particlesDisabled,
        false
    )
end)

clientModules.performance.postEffectsButton.Activated:Connect(function()
    clientModules.performance.setPostEffectsDisabled(
        not clientModules.performance.postEffectsDisabled,
        false
    )
end)

clientModules.performance.shadowsButton.Activated:Connect(function()
    clientModules.performance.setShadowsDisabled(
        not clientModules.performance.shadowsDisabled,
        false
    )
end)

clientModules.performance.fpsLimiterButton.Activated:Connect(function()
    clientModules.performance.setFpsLimiterEnabled(
        not clientModules.performance.fpsLimiterEnabled,
        false
    )
end)

clientModules.performance.fpsBox.FocusLost:Connect(function()
    clientModules.performance.setFpsLimit(
        tonumber(clientModules.performance.fpsBox.Text) or clientModules.performance.fpsLimit,
        false
    )
end)

clientModules.performance.fpsSliderTrack.InputBegan:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1
        or input.UserInputType == Enum.UserInputType.Touch then
        clientModules.performance.fpsSliderDragging = true
        clientModules.performance.updateFpsFromPointer(input.Position.X)
    end
end)

clientModules.performance.fpsSliderTrack.InputEnded:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1
        or input.UserInputType == Enum.UserInputType.Touch then
        clientModules.performance.fpsSliderDragging = false
    end
end)

clientModules.performance.fpsSliderInputConnection = UserInputService.InputChanged:Connect(function(input)
    if not clientModules.performance.fpsSliderDragging then
        return
    end

    if input.UserInputType == Enum.UserInputType.MouseMovement
        or input.UserInputType == Enum.UserInputType.Touch then
        clientModules.performance.updateFpsFromPointer(input.Position.X)
    end
end)

espSurvivorsButton.Activated:Connect(function()
    espSurvivorsEnabled = not espSurvivorsEnabled
    setSwitchVisual(espSurvivorsButton, espSurvivorsDot, espSurvivorsEnabled)
    if espSurvivorsEnabled or espExecutionersEnabled then
        initializeESP()
    else
        shutdownESP()
    end
    refreshAllTrackedModels()
end)

espDistanceButton.Activated:Connect(function()
    espDistanceEnabled = not espDistanceEnabled
    setSwitchVisual(espDistanceButton, espDistanceDot, espDistanceEnabled)
    startESPInfoWindow()
end)

espTracersButton.Activated:Connect(function()
    espTracersEnabled = not espTracersEnabled
    setSwitchVisual(espTracersButton, espTracersDot, espTracersEnabled)
    if espSurvivorsEnabled or espExecutionersEnabled then
        initializeESP()
    end
end)

espSurvivorInfoButton.Activated:Connect(function()
    espSurvivorInfoEnabled = not espSurvivorInfoEnabled
    setSwitchVisual(espSurvivorInfoButton, espSurvivorInfoDot, espSurvivorInfoEnabled)
    startESPInfoWindow()
end)

espAbilitiesButton.Activated:Connect(function()
    espAbilitiesEnabled = not espAbilitiesEnabled
    setSwitchVisual(espAbilitiesButton, espAbilitiesDot, espAbilitiesEnabled)
    startESPInfoWindow()
end)

clientModules.boostTabs.toggleButton.Activated:Connect(function()
    clientModules.boostTabs.enabled = false
    clientModules.boostTabs.setEnabled(false, true)
end)

espExecutionersButton.Activated:Connect(function()
    espExecutionersEnabled = not espExecutionersEnabled
    -- Сама подсветка Executioners остаётся красной, но активный переключатель зелёный.
    setSwitchVisual(espExecutionersButton, espExecutionersDot, espExecutionersEnabled)
    if espSurvivorsEnabled or espExecutionersEnabled then
        initializeESP()
    else
        shutdownESP()
    end
    refreshAllTrackedModels()
end)

activateButton.Activated:Connect(safeRequestStandardBoost)
clientModules.tabs.combat.Activated:Connect(function()
    selectTab("Combat")
end)

clientModules.tabs.fun.Activated:Connect(function()
    selectTab("Fun")
end)

clientModules.combat.autoAimButton.Activated:Connect(function()
    clientModules.combat.setAutoAimEnabled(
        not clientModules.combat.autoAimEnabled,
        false
    )
end)

clientModules.combat.autoCounterButton.Activated:Connect(function()
    clientModules.combat.setAutoCounterEnabled(
        not clientModules.combat.autoCounterEnabled,
        false
    )
end)

clientModules.combat.showTargetButton.Activated:Connect(function()
    clientModules.combat.showTarget = not clientModules.combat.showTarget
    clientModules.combat.updateVisuals()
end)

clientModules.combat.aimSmoothnessBox.FocusLost:Connect(function()
    local value = tonumber(string.gsub(clientModules.combat.aimSmoothnessBox.Text, ",", "."))
    if not value then
        value = 0.28
    end

    clientModules.combat.aimSmoothness = math.clamp(value, 0.02, 1)
    clientModules.combat.aimSmoothnessBox.Text = tostring(clientModules.combat.aimSmoothness)
end)

clientModules.fun.spinButton.Activated:Connect(function()
    clientModules.fun.setSpinEnabled(
        not clientModules.fun.spinEnabled,
        false
    )
end)

clientModules.fun.spectateButton.Activated:Connect(function()
    clientModules.fun.setSpectateEnabled(
        not clientModules.fun.spectateEnabled,
        false
    )
end)

clientModules.fun.characterLockButton.Activated:Connect(function()
    local value = clientModules.fun.characterLockValue

    if not value or not value.Parent then
        value = clientModules.fun.findFirstByName("CharacterLOCK", "BoolValue")
        clientModules.fun.characterLockValue = value
    end

    local enabled = value and not value.Value or true
    clientModules.fun.setCharacterLockEnabled(enabled, false)
end)

clientModules.fun.sitButton.Activated:Connect(function()
    clientModules.fun.forceSit(false)
end)

clientModules.fun.standButton.Activated:Connect(function()
    clientModules.fun.forceStand(false)
end)

boostKeyButton.Activated:Connect(function()
    beginBinding("Boost")
end)
interfaceKeyButton.Activated:Connect(function()
    beginBinding("Interface")
end)
addAbilityButton.Activated:Connect(function()
    clientModules.abilityUI.addNewAbility()
end)

configManager.saveConfigButton.Activated:Connect(configManager.saveCurrentConfig)
configManager.listConfigsButton.Activated:Connect(function()
    configManager.setConfigListVisible(not configManager.configListVisible)
end)
configManager.loadConfigButton.Activated:Connect(configManager.loadSelectedConfig)
configManager.deleteConfigButton.Activated:Connect(configManager.deleteSelectedConfig)
configManager.editConfigButton.Activated:Connect(configManager.editSelectedConfig)
configManager.autoLoadConfigButton.Activated:Connect(configManager.enableSelectedConfigAutoLoad)
configManager.disableAutoLoadButton.Activated:Connect(configManager.disableSelectedConfigAutoLoad)

function shutdownMainScript(reason)
    if guiDestroyed then
        return
    end

    guiDestroyed = true

    if clientModules.console.attributeConnection then
        clientModules.console.attributeConnection:Disconnect()
        clientModules.console.attributeConnection = nil
    end
    destroyLiveConsoleMode()

    resumeStandardAfterAbility = false
    standardResumeSnapshot = nil
    stopBoost(reason or "Interface closed.", {
        suppressStandardResume = true,
        suppressCooldown = true,
    })
    shutdownESP()
    destroyESPInfoWindow()
    clientModules.fun.shutdown()
    clientModules.shutdown()

    if dragInputChangedConnection then
        dragInputChangedConnection:Disconnect()
        dragInputChangedConnection = nil
    end

    if cameraConnection then
        cameraConnection:Disconnect()
        cameraConnection = nil
    end

    if currentCameraChangedConnection then
        currentCameraChangedConnection:Disconnect()
        currentCameraChangedConnection = nil
    end

    if globalInputConnection then
        globalInputConnection:Disconnect()
        globalInputConnection = nil
    end

    if clientModules.screenGuiAncestryConnection then
        clientModules.screenGuiAncestryConnection:Disconnect()
        clientModules.screenGuiAncestryConnection = nil
    end

    if screenGui and screenGui.Parent then
        if interfaceCanvasGroup and mainFrame and uiScale then
            interfaceAnimationSerial = interfaceAnimationSerial + 1

            interfaceCanvasGroup.GroupTransparency = 0
            mainFrame.BackgroundTransparency = 0.16
            uiScale.Scale = 1

            local closeTween = TweenService:Create(
                interfaceCanvasGroup,
                TweenInfo.new(0.20, Enum.EasingStyle.Quint, Enum.EasingDirection.In),
                { GroupTransparency = 1 }
            )
            local backgroundTween = TweenService:Create(
                mainFrame,
                TweenInfo.new(0.20, Enum.EasingStyle.Quint, Enum.EasingDirection.In),
                { BackgroundTransparency = 1 }
            )
            local scaleTween = TweenService:Create(
                uiScale,
                TweenInfo.new(0.20, Enum.EasingStyle.Quint, Enum.EasingDirection.In),
                { Scale = 0.94 }
            )

            closeTween:Play()
            backgroundTween:Play()
            scaleTween:Play()

            task.spawn(function()
                closeTween.Completed:Wait()
                if screenGui and screenGui.Parent then
                    screenGui:Destroy()
                end
            end)
        else
            screenGui:Destroy()
        end
    end
end

-- Destroying the old ScreenGui is how a later script run replaces this UI.
-- Treat that as a full shutdown so the old run cannot retain hotkeys, loops,
-- character modifiers, or cached visual effects in the background.
clientModules.screenGuiAncestryConnection = screenGui.AncestryChanged:Connect(function(_, parent)
    if parent == nil and not guiDestroyed then
        shutdownMainScript("Interface was replaced or removed.")
    end
end)

function clientModules.console.refreshModeState()
    local enabled = localPlayer:GetAttribute(CONSOLE_MODE_ATTRIBUTE_NAME) == true

    setSwitchVisual(
        clientModules.console.toggleButton,
        clientModules.console.toggleDot,
        enabled
    )

    if enabled then
        clientModules.console.hintLabel.Text = "Live Console enabled — PulseCore diagnostics only."
        clientModules.console.hintLabel.TextColor3 = COLORS.Green
        runLiveConsoleMode()
    else
        clientModules.console.hintLabel.Text = "Live Console is disabled. Enable it to view PulseCore diagnostics, warnings, errors, and feature events."
        clientModules.console.hintLabel.TextColor3 = COLORS.MutedText
        destroyLiveConsoleMode()
    end
end

clientModules.console.toggleButton.Activated:Connect(function()
    local enabled = localPlayer:GetAttribute(CONSOLE_MODE_ATTRIBUTE_NAME) == true
    localPlayer:SetAttribute(CONSOLE_MODE_ATTRIBUTE_NAME, not enabled)
end)

clientModules.console.attributeConnection =
    localPlayer:GetAttributeChangedSignal(CONSOLE_MODE_ATTRIBUTE_NAME):Connect(function()
        if not guiDestroyed then
            clientModules.console.refreshModeState()
        end
    end)

minimizeAnimationSerial = 0

minimizeButton.Activated:Connect(function()
    minimized = not minimized
    minimizeButton.Text = minimized and "+" or "−"

    minimizeAnimationSerial = minimizeAnimationSerial + 1
    local serial = minimizeAnimationSerial
    local duration = 0.26

    if not minimized then
        bodyFrame.Visible = true
        bodyCanvasGroup.GroupTransparency = 1
    end

    local sizeTween = TweenService:Create(
        mainFrame,
        TweenInfo.new(duration, Enum.EasingStyle.Quint, Enum.EasingDirection.Out),
        { Size = minimized and minimizedSize or expandedSize }
    )

    local bodyTween = TweenService:Create(
        bodyCanvasGroup,
        TweenInfo.new(
            minimized and 0.16 or 0.24,
            Enum.EasingStyle.Quint,
            minimized and Enum.EasingDirection.In or Enum.EasingDirection.Out
        ),
        { GroupTransparency = minimized and 1 or 0 }
    )

    sizeTween:Play()
    bodyTween:Play()

    if minimized then
        task.spawn(function()
            sizeTween.Completed:Wait()

            if serial == minimizeAnimationSerial and minimized and not guiDestroyed then
                bodyFrame.Visible = false
            end
        end)
    end
end)

closeButton.Activated:Connect(function()
    shutdownMainScript("Interface closed.")
end)

-- Перетаскивание окна мышью или касанием.
do
    local dragging = false
    local dragInput = nil
    local dragStart = nil
    local startPosition = nil

    topBar.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1
            or input.UserInputType == Enum.UserInputType.Touch then
            dragging = true
            dragStart = input.Position
            startPosition = mainFrame.Position

            input.Changed:Connect(function()
                if input.UserInputState == Enum.UserInputState.End then
                    dragging = false
                end
            end)
        end
    end)

    topBar.InputChanged:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseMovement
            or input.UserInputType == Enum.UserInputType.Touch then
            dragInput = input
        end
    end)

    dragInputChangedConnection = UserInputService.InputChanged:Connect(function(input)
        if input == dragInput and dragging and dragStart and startPosition then
            local delta = input.Position - dragStart

            mainFrame.Position = UDim2.new(
                startPosition.X.Scale,
                startPosition.X.Offset + delta.X,
                startPosition.Y.Scale,
                startPosition.Y.Offset + delta.Y
            )
        end
    end)
end

-- Глобальные горячие клавиши продолжают работать, даже когда ScreenGui скрыт.
globalInputConnection = UserInputService.InputBegan:Connect(function(input, gameProcessedEvent)
    if guiDestroyed or input.UserInputType ~= Enum.UserInputType.Keyboard then
        return
    end


    -- Во время назначения клавиши принимаем нажатие даже из выбранного GUI-элемента.
    if clientModules.keyList.state.bindingTarget then
        if input.KeyCode ~= Enum.KeyCode.Unknown then
            finishBinding(input.KeyCode)
        end
        return
    end

    -- Не используем нажатие повторно, если его уже обработал Roblox/CoreGui
    -- или пользователь активирует выбранную GUI-кнопку с клавиатуры.
    if gameProcessedEvent or game:GetService("GuiService").SelectedObject ~= nil then
        return
    end

    -- Не срабатываем, пока пользователь печатает число или сообщение в чате.
    if UserInputService:GetFocusedTextBox() then
        return
    end

    if input.KeyCode == clientModules.keyList.state.interfaceKey then
        animateMainInterfaceVisibility(not screenGui.Enabled)
        return
    elseif input.KeyCode == clientModules.keyList.state.noclipKey then
        clientModules.characterTools.setNoclipEnabled(
            not clientModules.characterTools.noclipEnabled,
            false
        )
        return
    elseif input.KeyCode == clientModules.keyList.state.flightKey then
        clientModules.flight.setEnabled(not clientModules.flight.enabled, false)
        return
    end

    if input.KeyCode == clientModules.keyList.state.boostKey then
        safeRequestStandardBoost()
        return
    end

    for _, ability in ipairs(abilities) do
        if input.KeyCode == ability.key then
            safeRequestAbility(ability)
            return
        end
    end
end)

function updateScale()
    local camera = workspace.CurrentCamera

    if not camera then
        return
    end

    local viewport = camera.ViewportSize
    local widthScale = viewport.X / 1020
    local heightScale = viewport.Y / 660
    uiScale.Scale = math.clamp(math.min(widthScale, heightScale), 0.56, 1)
end

function connectCameraScale()
    if cameraConnection then
        cameraConnection:Disconnect()
        cameraConnection = nil
    end

    local camera = workspace.CurrentCamera

    if camera then
        cameraConnection = camera:GetPropertyChangedSignal("ViewportSize"):Connect(updateScale)
    end

    updateScale()
end

interfaceInitialized = false

clientModules.speedControl.standardMethod = "WalkSpeed"
clientModules.inventoryOrder.enabled = false
clientModules.boostTabs.enabled = false
if clientModules.boostTabs.window then
    clientModules.boostTabs.window.Visible = false
end

function initializeMainInterface()
    if interfaceInitialized or guiDestroyed then
        return
    end

    interfaceInitialized = true
    currentCameraChangedConnection = workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(connectCameraScale)
    connectCameraScale()
    configManager.loadStoredConfigs()
    clientModules.speedControl.standardMethod = "WalkSpeed"
    clientModules.inventoryOrder.setEnabled(false, true)
    clientModules.boostTabs.setEnabled(false, true)
    configManager.refreshConfigList()
    if configManager.autoLoadConfigName and configManager.savedConfigs[configManager.autoLoadConfigName] then
        configManager.loadConfigByName(configManager.autoLoadConfigName, { auto = true })
    end
    clientModules.abilityUI.updateAddAbilityButton()
    refreshSpecialTabsVisibility()
    selectTab("Info")
    setToggleVisual()
    setSwitchVisual(
        clientModules.jumpBoost.standardToggleButton,
        clientModules.jumpBoost.standardToggleDot,
        clientModules.jumpBoost.standardEnabled
    )
    setSwitchVisual(
        clientModules.cooldown.standard.toggleButton,
        clientModules.cooldown.standard.toggleDot,
        clientModules.cooldown.standard.cooldownEnabled
    )
    setSwitchVisual(espSurvivorsButton, espSurvivorsDot, espSurvivorsEnabled)
    setSwitchVisual(espExecutionersButton, espExecutionersDot, espExecutionersEnabled)
    setSwitchVisual(espDistanceButton, espDistanceDot, espDistanceEnabled)
    setSwitchVisual(espTracersButton, espTracersDot, espTracersEnabled)
    setSwitchVisual(espSurvivorInfoButton, espSurvivorInfoDot, espSurvivorInfoEnabled)
    setSwitchVisual(espAbilitiesButton, espAbilitiesDot, espAbilitiesEnabled)
    clientModules.boostTabs.refreshVisuals()
    clientModules.boostTabs.update()
    clientModules.infFlight.refreshVisuals()
    clientModules.flight.setSpeed(clientModules.flight.speed or DEFAULT_FLIGHT_SPEED, true)
    clientModules.flight.updateSliderVisual()
    clientModules.flight.refreshVisuals()
    clientModules.characterTools.refreshVisuals()
    clientModules.characterTools.initialize()
    clientModules.characterTools.setSharpMovementEnabled(
        clientModules.characterTools.sharpMovementEnabled,
        true
    )
    clientModules.console.refreshModeState()
    if isSpecialTabsAllowed() then
        clientModules.combat.initialize()
    else
        clientModules.combat.shutdown()
    end

    clientModules.fun.refreshInfo()
    clientModules.performance.refreshVisuals()
    clientModules.performance.updateStatus()
    clientModules.performance.updateFpsStatus()
    clientModules.autoSelect.refreshVisuals()
    clientModules.autoSelect.initialize()
    updateActivateButton()
    if espSurvivorsEnabled or espExecutionersEnabled then
        initializeESP()
    else
        shutdownESP()
    end
end

-- Показываем интерфейс до тяжёлой инициализации, чтобы UI успел отрисоваться
-- даже если отдельная функция настройки опционального модуля выдаст ошибку.
mainFrame.Visible = true

-- Первый запуск также использует ту же плавную анимацию, что и горячая клавиша.
interfaceCanvasGroup.GroupTransparency = 1
mainFrame.BackgroundTransparency = 1
uiScale.Scale = 0.94
animateMainInterfaceVisibility(true)

task.defer(function()
    if not guiDestroyed and mainFrame.Parent then
        local ok, err = pcall(initializeMainInterface)
        if not ok then
            logPulseCoreError("Initialization error: " .. tostring(err))
            warn("[PulseCore] Initialization error: " .. tostring(err))
            pcall(function()
                if clientModules and clientModules.header and clientModules.header.subtitle then
                    clientModules.header.subtitle.Text = "Initialization error: " .. tostring(err)
                    clientModules.header.subtitle.TextColor3 = COLORS.Red
                end
            end)
        end
    end
end)
