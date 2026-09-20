SCRIPT_VERSION = "2026.09.11"

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

-- Fatal-error safety system. The notification is created BEFORE the main
-- interface starts so it can still be displayed when the main runtime is
-- already in a broken state.  It lives in a separate GUI container.
criticalState = {
    active = false,
    notificationGui = nil,
    notificationFrame = nil,
    notificationSerial = 0,
    errorConnection = nil,
}

criticalStopCodes = {
    INIT_FAILURE = true,
    RUNTIME_FAILURE = true,
    UI_FAILURE = true,
    EVENT_FAILURE = true,
    STATE_FAILURE = true,
    DATA_FAILURE = true,
    MODULE_FAILURE = true,
    TEST_FAILURE = true,
}

function normalizeCriticalStopCode(code)
    code = tostring(code or "RUNTIME_FAILURE"):upper():gsub("[^A-Z0-9_%-]", "_")
    if not criticalStopCodes[code] then
        return "RUNTIME_FAILURE"
    end
    return code
end

function getCriticalGuiParent()
    -- Prefer executor GUI root when available.  In normal LocalScript/Studio
    -- environments we safely fall back to PlayerGui.
    local ok, hui = pcall(function()
        if type(gethui) == "function" then
            return gethui()
        end
        return nil
    end)
    if ok and hui then
        return hui
    end
    return playerGui
end

function buildCriticalNotification()
    if criticalState.notificationGui and criticalState.notificationGui.Parent
        and criticalState.notificationFrame and criticalState.notificationFrame.Parent then
        return
    end

    pcall(function()
        if criticalState.notificationGui then
            criticalState.notificationGui:Destroy()
        end
    end)

    local parent = getCriticalGuiParent()

    local gui = Instance.new("ScreenGui")
    gui.Name = "PulseCoreCriticalNotificationUI"
    gui.ResetOnSpawn = false
    gui.IgnoreGuiInset = false
    gui.DisplayOrder = 1000000
    gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    gui.Enabled = true
    gui.Parent = parent
    criticalState.notificationGui = gui

    local frame = Instance.new("Frame")
    frame.Name = "CriticalError"
    frame.AnchorPoint = Vector2.new(1, 1)
    frame.Position = UDim2.new(1, 430, 1, -18)
    frame.Size = UDim2.fromOffset(410, 126)
    frame.BackgroundColor3 = COLORS.Panel
    frame.BackgroundTransparency = 0.06
    frame.BorderSizePixel = 0
    frame.Active = true
    frame.Visible = false
    frame.Parent = gui
    criticalState.notificationFrame = frame
    addCorner(frame, 14)
    addStroke(frame, COLORS.Red, 0.10, 1.4)

    create("UIGradient", {
        Rotation = 18,
        Color = ColorSequence.new({
            ColorSequenceKeypoint.new(0, Color3.fromRGB(31, 18, 18)),
            ColorSequenceKeypoint.new(0.55, Color3.fromRGB(14, 14, 14)),
            ColorSequenceKeypoint.new(1, Color3.fromRGB(8, 8, 8)),
        }),
    }, frame)

    create("TextLabel", {
        Position = UDim2.fromOffset(18, 13),
        Size = UDim2.new(1, -36, 0, 27),
        BackgroundTransparency = 1,
        Text = "PULSECORE  /  CRITICAL ERROR",
        Font = Enum.Font.GothamBold,
        TextSize = 14,
        TextColor3 = COLORS.Red,
        TextXAlignment = Enum.TextXAlignment.Left,
        ZIndex = 3,
    }, frame)

    create("TextLabel", {
        Position = UDim2.fromOffset(18, 40),
        Size = UDim2.new(1, -36, 0, 43),
        BackgroundTransparency = 1,
        Text = "A critical error occurred while PulseCore was running.\nPulseCore cannot safely continue and has been stopped.",
        Font = Enum.Font.GothamMedium,
        TextSize = 12,
        TextColor3 = COLORS.Text,
        TextWrapped = true,
        TextXAlignment = Enum.TextXAlignment.Left,
        TextYAlignment = Enum.TextYAlignment.Center,
        ZIndex = 3,
    }, frame)

    create("TextLabel", {
        Position = UDim2.fromOffset(18, 88),
        Size = UDim2.new(1, -36, 0, 24),
        BackgroundTransparency = 1,
        Name = "StopCode",
        Text = "Stop Code: RUNTIME_FAILURE",
        Font = Enum.Font.Code,
        TextSize = 12,
        TextColor3 = COLORS.MutedText,
        TextXAlignment = Enum.TextXAlignment.Left,
        ZIndex = 3,
    }, frame)
end

function destroyCriticalNotification()
    if criticalState.notificationGui and criticalState.notificationGui.Parent then
        pcall(function()
            criticalState.notificationGui:Destroy()
        end)
    end
    criticalState.notificationGui = nil
    criticalState.notificationFrame = nil
end

function showCriticalNotification(stopCode)
    stopCode = normalizeCriticalStopCode(stopCode)
    buildCriticalNotification()

    local gui = criticalState.notificationGui
    local frame = criticalState.notificationFrame
    if not gui or not frame or not gui.Parent or not frame.Parent then
        return false
    end

    criticalState.notificationSerial = criticalState.notificationSerial + 1
    local serial = criticalState.notificationSerial

    local stopLabel = frame:FindFirstChild("StopCode")
    if stopLabel then
        stopLabel.Text = "Stop Code: " .. stopCode
    end

    pcall(function()
        frame.Visible = false
        frame.Position = UDim2.new(1, 430, 1, -18)
    end)

    frame.Visible = true

    -- Do not use a timer that starts before the entrance animation finishes.
    -- Five seconds are counted only after the notification is fully visible.
    local tweenIn = TweenService:Create(
        frame,
        TweenInfo.new(0.55, Enum.EasingStyle.Quint, Enum.EasingDirection.Out),
        { Position = UDim2.new(1, -18, 1, -18) }
    )
    tweenIn:Play()

    tweenIn.Completed:Connect(function()
        if serial ~= criticalState.notificationSerial
            or frame ~= criticalState.notificationFrame
            or not frame.Parent then
            return
        end

        task.delay(5, function()
            if serial ~= criticalState.notificationSerial
                or frame ~= criticalState.notificationFrame
                or not frame.Parent then
                return
            end

            local tweenOut = TweenService:Create(
                frame,
                TweenInfo.new(0.48, Enum.EasingStyle.Quint, Enum.EasingDirection.In),
                { Position = UDim2.new(1, 430, 1, -18) }
            )
            tweenOut:Play()
            tweenOut.Completed:Connect(function()
                if serial ~= criticalState.notificationSerial
                    or frame ~= criticalState.notificationFrame then
                    return
                end
                frame.Visible = false
            end)
        end)
    end)

    return true
end

-- Prepare the notification while PulseCore is healthy. If a later function
-- crashes, the error handler only has to reveal this already-created GUI.
buildCriticalNotification()

function freezeCriticalInterface()
    -- The interface must become completely non-interactive during the fatal
    -- 2-second safety window: no scrolling, buttons, toggles, dragging, or
    -- hotkeys may be able to change state.
    if not screenGui or not screenGui.Parent then
        return
    end

    local overlay = screenGui:FindFirstChild("CriticalFreezeOverlay")
    if not overlay then
        overlay = Instance.new("TextButton")
        overlay.Name = "CriticalFreezeOverlay"
        overlay.Size = UDim2.fromScale(1, 1)
        overlay.Position = UDim2.fromScale(0, 0)
        overlay.BackgroundTransparency = 1
        overlay.BorderSizePixel = 0
        overlay.Text = ""
        overlay.AutoButtonColor = false
        overlay.Active = true
        overlay.Selectable = false
        overlay.ZIndex = 100000
        overlay.Modal = true
        overlay.Parent = screenGui
    end
    overlay.Visible = true

    -- Disable scrolling and direct interaction on every existing control.
    pcall(function()
        for _, obj in ipairs(screenGui:GetDescendants()) do
            if obj ~= overlay and obj:IsA("ScrollingFrame") then
                obj.ScrollingEnabled = false
            end
            if obj ~= overlay and obj:IsA("GuiButton") then
                obj.Active = false
                obj.Selectable = false
            elseif obj ~= overlay and obj:IsA("TextBox") then
                obj.Active = false
                obj.Selectable = false
            end
        end
    end)
end

function criticalShutdown(stopCode, reason)
    if criticalState.active then
        return
    end

    criticalState.active = true
    stopCode = normalizeCriticalStopCode(stopCode)
    reason = tostring(reason or "Critical runtime failure.")

    -- Freeze all UI interaction immediately. The main interface remains visible
    -- but becomes completely non-interactive for the full 2-second fatal window.
    freezeCriticalInterface()

    -- Freeze the PulseCore shutdown transition briefly so the failure state is
    -- visible/consistent for 2 seconds before anything is removed.
    task.wait(2)

    -- Stop accepting further critical callbacks before shutting down modules.
    if criticalState.errorConnection then
        pcall(function()
            criticalState.errorConnection:Disconnect()
        end)
        criticalState.errorConnection = nil
    end

    -- Let the regular shutdown path perform its normal cleanup. If something
    -- inside that cleanup is itself broken, the fallback still tears down the
    -- visible GUI and the main event connections.
    criticalStopInProgress = true
    local shutdownOk, shutdownError = pcall(function()
        if shutdownMainScript then
            shutdownMainScript("Critical error: " .. stopCode)
        end
    end)

    if not shutdownOk then
        warn("[PulseCore] Critical shutdown fallback: " .. tostring(shutdownError))
    end

    guiDestroyed = true

    if globalInputConnection then
        pcall(function() globalInputConnection:Disconnect() end)
        globalInputConnection = nil
    end
    if dragInputChangedConnection then
        pcall(function() dragInputChangedConnection:Disconnect() end)
        dragInputChangedConnection = nil
    end
    if cameraConnection then
        pcall(function() cameraConnection:Disconnect() end)
        cameraConnection = nil
    end
    if currentCameraChangedConnection then
        pcall(function() currentCameraChangedConnection:Disconnect() end)
        currentCameraChangedConnection = nil
    end
    if screenGui and screenGui.Parent then
        pcall(function() screenGui:Destroy() end)
    end

    print("[PulseCore] CRITICAL STOP: " .. stopCode .. " | " .. reason)

    -- The main script has now been destroyed. Wait another 1 second so the
    -- notification starts exactly 3 seconds after the critical error begins.
    task.wait(1)

    -- Rebuild the independent notification if PlayerGui/gethui was touched by
    -- the shutdown path.
    pcall(buildCriticalNotification)
    local shown = false
    local ok = pcall(function()
        shown = showCriticalNotification(stopCode)
    end)
    if not ok or not shown then
        -- Last-resort retry outside the main shutdown stack.
        task.defer(function()
            pcall(buildCriticalNotification)
            pcall(showCriticalNotification, stopCode)
        end)
    end
end

function installCriticalErrorMonitor()
    local ok, context = pcall(function()
        return game:GetService("ScriptContext")
    end)
    if not ok or not context then
        return
    end

    local sourceScript = nil
    pcall(function()
        if typeof(script) == "Instance" then
            sourceScript = script
        end
    end)

    criticalState.errorConnection = context.Error:Connect(function(message, stackTrace, erroredScript)
        if criticalState.active then
            return
        end

        local text = tostring(message or "")
        local trace = tostring(stackTrace or "")
        local belongsToPulseCore = false

        if sourceScript and erroredScript == sourceScript then
            belongsToPulseCore = true
        elseif string.find(text, "[PulseCore", 1, true)
            or string.find(text, "PulseCore", 1, true)
            or string.find(trace, "PulseCore", 1, true) then
            belongsToPulseCore = true
        end

        if belongsToPulseCore then
            criticalShutdown("RUNTIME_FAILURE", text)
        end
    end)
end

installCriticalErrorMonitor()

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

    if liveConsoleState.gui and liveConsoleState.gui.Parent then
        liveConsoleState.gui:Destroy()
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

expandedSize = UDim2.fromOffset(820, 520)
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
clientModules.tabs.performance = createTabButton("PerformanceTab", "PERFORMANCE", 170)
clientModules.tabs.autoSelect = createTabButton("AutoSelectTab", "AUTO", 222)
clientModules.tabs.keyList = createTabButton("KeyListTab", "KEY LIST", 274)
settingsTab = createTabButton("SettingsTab", "SETTINGS", 326)

clientModules.tabAnimation = {
    currentName = nil,
    currentPage = nil,
    serial = 0,
    order = {
        Info = 1,
        Local = 2,
        Visuals = 3,
        Performance = 4,
        AutoSelect = 5,
        KeyList = 6,
        Settings = 7,
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
    Text = "Script information and quick overview",
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
    local scriptInfo = create("TextLabel", {
        LayoutOrder = 2,
        Size = UDim2.new(1, 0, 0, 116),
        BackgroundColor3 = COLORS.CyanDeep,
        BackgroundTransparency = 0.2,
        BorderSizePixel = 0,
        Text = "PulseCore  •  Client Tools\nVersion: " .. SCRIPT_VERSION .. "\nType: Roblox LocalScript",
        Font = Enum.Font.GothamMedium,
        TextSize = 14,
        TextColor3 = COLORS.Text,
        TextWrapped = true,
        TextXAlignment = Enum.TextXAlignment.Left,
        TextYAlignment = Enum.TextYAlignment.Center,
    }, clientModules.pages.info)
    addCorner(scriptInfo, 12)
    addStroke(scriptInfo, COLORS.Cyan, 0.55, 1)
    create("UIPadding", {
        PaddingLeft = UDim.new(0, 16),
        PaddingRight = UDim.new(0, 16),
    }, scriptInfo)
end

do
    local featuresInfo = create("TextLabel", {
        LayoutOrder = 3,
        Size = UDim2.new(1, 0, 0, 188),
        BackgroundColor3 = COLORS.CyanDeep,
        BackgroundTransparency = 0.28,
        BorderSizePixel = 0,
        Text = "MAIN FEATURES\n• WalkSpeed speed method with Increase and Set calculation modes\n• Optional AssemblyLinearVelocity Jump Boost for Local and every Ability\n• Up to four custom Abilities with delay, duration, cooldown, and hotkeys\n• Survivor / Executioner ESP overlay\n• Auto Select, Inf Flight, Noclip, Infinity Jump, live console mode, and session configs",
        Font = Enum.Font.GothamMedium,
        TextSize = 13,
        TextColor3 = COLORS.MutedText,
        TextWrapped = true,
        TextXAlignment = Enum.TextXAlignment.Left,
        TextYAlignment = Enum.TextYAlignment.Top,
    }, clientModules.pages.info)
    addCorner(featuresInfo, 12)
    create("UIPadding", {
        PaddingTop = UDim.new(0, 14),
        PaddingBottom = UDim.new(0, 14),
        PaddingLeft = UDim.new(0, 16),
        PaddingRight = UDim.new(0, 16),
    }, featuresInfo)
end

do
    local controlsInfo = create("TextLabel", {
        LayoutOrder = 4,
        Size = UDim2.new(1, 0, 0, 128),
        BackgroundColor3 = COLORS.CyanDeep,
        BackgroundTransparency = 0.28,
        BorderSizePixel = 0,
        Text = "DEFAULT CONTROLS\nR — activate / stop Standard Boost\nV — hide / show the interface\nF — toggle Flight\nN — toggle Noclip\nE, Q, Z, C — default Ability hotkeys\nAll main hotkeys can be changed in KEY LIST.",
        Font = Enum.Font.GothamMedium,
        TextSize = 13,
        TextColor3 = COLORS.MutedText,
        TextWrapped = true,
        TextXAlignment = Enum.TextXAlignment.Left,
        TextYAlignment = Enum.TextYAlignment.Top,
    }, clientModules.pages.info)
    addCorner(controlsInfo, 12)
    create("UIPadding", {
        PaddingTop = UDim.new(0, 14),
        PaddingBottom = UDim.new(0, 14),
        PaddingLeft = UDim.new(0, 16),
        PaddingRight = UDim.new(0, 16),
    }, controlsInfo)
end

do
    local notesInfo = create("TextLabel", {
        LayoutOrder = 5,
        Size = UDim2.new(1, 0, 0, 118),
        BackgroundColor3 = COLORS.CyanDeep,
        BackgroundTransparency = 0.28,
        BorderSizePixel = 0,
        Text = "NOTES\nConfigs are stored on LocalPlayer for the current game session.\nInf Flight is intended for Silver and Fleetway.\nConsole mode persists only while you stay in the same game session.\nThe Info page always opens when this script starts.",
        Font = Enum.Font.GothamMedium,
        TextSize = 13,
        TextColor3 = COLORS.MutedText,
        TextWrapped = true,
        TextXAlignment = Enum.TextXAlignment.Left,
        TextYAlignment = Enum.TextYAlignment.Top,
    }, clientModules.pages.info)
    addCorner(notesInfo, 12)
    create("UIPadding", {
        PaddingTop = UDim.new(0, 14),
        PaddingBottom = UDim.new(0, 14),
        PaddingLeft = UDim.new(0, 16),
        PaddingRight = UDim.new(0, 16),
    }, notesInfo)
end

do
    local changelogText = table.concat({
        "CHANGELOG / UPDATE HISTORY",
        "Current update — " .. SCRIPT_VERSION,
        "• Improved ESP discovery: any Model under Survivors, EXE, or Executioners is tracked regardless of container class or Humanoid timing.",
        "• Fixed Velocity Boost so it no longer overwrites faster dash/slide/knockback motion from the game.",
        "• Fixed movement animation tracks restarting at an already-boosted playback rate.",
        "• Kept the original InputBegan hotkey path for maximum executor/game compatibility while retaining gameProcessedEvent and GUI-focus protection.",
        "• Fixed cleanup on external UI destruction so repeated script launches do not leave old input and frame connections running.",
        "• Fixed the Inf Flight button so it can both enable and disable the feature.",
        "• Fixed the initial page offset and corrected Speed / Jump validation messages to the actual 200 limit.",
        "• Added WalkSpeed with Increase and Set calculation modes for Standard Boost and every Ability.",
        "• Speed and Jump Boost are limited to 200; their input fields accept digits only.",
        "• Added a separate Local Flight with F hotkey, camera-relative movement, and configurable speed up to 200.",
        "• Speed Boost now accelerates movement animations proportionally to movement speed, capped at 4x.",
        "• Added Sharp Movement / Anti-Slide for Standard Boost and every custom Ability; ground sliding is cancelled and air direction can be redirected instantly.",
        "• Added N as the default Local Noclip toggle hotkey.",
        "• Previous animation lock behavior used a fixed 1.0 playback rate while Speed Boost was active.",
        "• Added a separate Use Jump Boost switch for Standard Boost and every custom Ability.",
        "• Movement animation playback is now synchronized with the active Speed Boost.",
        "• Script version format changed to YYYY.MM.DD and now represents the date of the latest update.",
        "",
        "Previous updates",
        "• Added the original additive Speed Boost with delay, duration, hotkey, and up to four custom Abilities.",
        "• Added cooldown support to Standard Boost and every Ability.",
        "• Added session config management: save, list, select, edit, delete, load, and auto-load.",
        "• Added Survivor / Executioner ESP and character-model caching.",
        "• Added Auto Select with Sonic, Tails, Knuckles, Eggman, Amy, Cream, Blaze, Silver, and Metal Sonic.",
        "• Fixed Auto Select so it waits for the real character-select screen before voting.",
        "• Fixed hotkeys so Roblox UI keyboard activation does not also trigger Speed Boost.",
        "• Removed the old Performance and HUD pages and converted the interface to English.",
        "• Added movement guard experiments for sliding / sudden dashes, then removed them completely.",
        "• Added Inf Flight for Silver / Fleetway and fixed its interaction with movement speed.",
        "• Added Jump Boost through AssemblyLinearVelocity and removed the old Camera page.",
        "• Added the startup Info page and the Visuals / Tabs live boost-status overlay.",
        "• Redesigned the interface with the current purple translucent style and animated tab transitions.",
        "• Added and later removed the Key System so the main interface opens immediately.",
        "• Added live Console mode for the current game session.",
        "• Added Local and per-Ability Noclip / Infinity Jump controls.",
    }, "\n")

    local changelogInfo = create("TextLabel", {
        LayoutOrder = 6,
        Size = UDim2.new(1, 0, 0, 620),
        BackgroundColor3 = COLORS.CyanDeep,
        BackgroundTransparency = 0.28,
        BorderSizePixel = 0,
        Text = changelogText,
        Font = Enum.Font.GothamMedium,
        TextSize = 12,
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
    "ESP Survivors — green fill",
    2
)

espExecutionersButton, espExecutionersDot = createToggleRow(
    visualsPage,
    "ESP Executioners — red fill",
    3
)

visualsStatusLabel = create("TextLabel", {
    LayoutOrder = 4,
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
    LayoutOrder = 5,
    Size = UDim2.new(1, 0, 0, 92),
    BackgroundColor3 = COLORS.CyanDeep,
    BackgroundTransparency = 0.32,
    BorderSizePixel = 0,
    Text = "ESP scans all workspace descendants and highlights Models under Survivors (green) or EXE / Executioners (red). Container class, Character attributes, and character names are not required.",
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

createSectionLabel(visualsPage, "VISUALS  /  BOOST TABS", 6)
clientModules.boostTabs.toggleButton, clientModules.boostTabs.toggleDot = createToggleRow(
    visualsPage,
    "Tabs — show boost status window",
    7
)
clientModules.boostTabs.toggleButton.Parent.Visible = false
clientModules.boostTabs.enabled = false

clientModules.boostTabs.hintLabel = create("TextLabel", {
    LayoutOrder = 8,
    Size = UDim2.new(1, 0, 0, 70),
    BackgroundColor3 = COLORS.CyanDeep,
    BackgroundTransparency = 0.32,
    BorderSizePixel = 0,
    Text = "Shows a window on the left side of the screen with active boosts, activation delay, remaining duration, and cooldown.",
    Font = Enum.Font.GothamMedium,
    TextSize = 12,
    TextColor3 = COLORS.MutedText,
    TextWrapped = true,
    TextXAlignment = Enum.TextXAlignment.Left,
    TextYAlignment = Enum.TextYAlignment.Center,
}, visualsPage)
addCorner(clientModules.boostTabs.hintLabel, 12)
create("UIPadding", {
    PaddingLeft = UDim.new(0, 14),
    PaddingRight = UDim.new(0, 14),
}, clientModules.boostTabs.hintLabel)

clientModules.boostTabs.window = create("Frame", {
    Name = "BoostTabsWindow",
    AnchorPoint = Vector2.new(0, 0.5),
    Position = UDim2.new(0, 14, 0.5, 0),
    Size = UDim2.fromOffset(270, 340),
    BackgroundColor3 = COLORS.Panel,
    BackgroundTransparency = 0.12,
    BorderSizePixel = 0,
    Visible = false,
    Active = false,
    ZIndex = 60,
}, screenGui)
addCorner(clientModules.boostTabs.window, 14)
addStroke(clientModules.boostTabs.window, COLORS.Cyan, 0.2, 1.4)

clientModules.boostTabs.titleLabel = create("TextLabel", {
    Position = UDim2.fromOffset(14, 8),
    Size = UDim2.new(1, -28, 0, 30),
    BackgroundTransparency = 1,
    Text = "BOOST TABS",
    Font = Enum.Font.GothamBold,
    TextSize = 15,
    TextColor3 = COLORS.Text,
    TextXAlignment = Enum.TextXAlignment.Left,
    ZIndex = 61,
}, clientModules.boostTabs.window)

clientModules.boostTabs.contentLabel = create("TextLabel", {
    Position = UDim2.fromOffset(14, 43),
    Size = UDim2.new(1, -28, 1, -55),
    BackgroundColor3 = COLORS.CyanDeep,
    BackgroundTransparency = 0.22,
    BorderSizePixel = 0,
    Text = "No active boosts, delays, or cooldowns.",
    Font = Enum.Font.Code,
    TextSize = 12,
    TextColor3 = COLORS.MutedText,
    TextWrapped = true,
    TextXAlignment = Enum.TextXAlignment.Left,
    TextYAlignment = Enum.TextYAlignment.Top,
    ZIndex = 61,
}, clientModules.boostTabs.window)
addCorner(clientModules.boostTabs.contentLabel, 10)
create("UIPadding", {
    PaddingTop = UDim.new(0, 10),
    PaddingBottom = UDim.new(0, 10),
    PaddingLeft = UDim.new(0, 10),
    PaddingRight = UDim.new(0, 10),
}, clientModules.boostTabs.contentLabel)

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

clientModules.criticalTest = {}
clientModules.criticalTest.button = create("TextButton", {
    LayoutOrder = 6,
    Size = UDim2.new(1, 0, 0, 42),
    BackgroundColor3 = Color3.fromRGB(55, 24, 28),
    BackgroundTransparency = 0.05,
    BorderSizePixel = 0,
    Text = "TEST CRITICAL ERROR",
    Font = Enum.Font.GothamBold,
    TextSize = 12,
    TextColor3 = COLORS.Text,
    AutoButtonColor = true,
    Active = true,
    Selectable = true,
}, settingsPage)
addCorner(clientModules.criticalTest.button, 10)
addStroke(clientModules.criticalTest.button, COLORS.Red, 0.18, 1)

clientModules.criticalTest.hint = create("TextLabel", {
    LayoutOrder = 7,
    Size = UDim2.new(1, 0, 0, 50),
    BackgroundColor3 = COLORS.CyanDeep,
    BackgroundTransparency = 0.32,
    BorderSizePixel = 0,
    Text = "Test only: intentionally raises a critical error and immediately disables PulseCore. The notification remains visible for 5 seconds.",
    Font = Enum.Font.GothamMedium,
    TextSize = 11,
    TextColor3 = COLORS.MutedText,
    TextWrapped = true,
    TextXAlignment = Enum.TextXAlignment.Left,
    TextYAlignment = Enum.TextYAlignment.Center,
}, settingsPage)
addCorner(clientModules.criticalTest.hint, 12)
create("UIPadding", {
    PaddingLeft = UDim.new(0, 14),
    PaddingRight = UDim.new(0, 14),
}, clientModules.criticalTest.hint)

configManager = {}

--==================================================
-- PERSONALIZATION
--==================================================

clientModules.personalization = clientModules.personalization or {}

clientModules.personalization.themes = {
    { name = "Graphite", accent = Color3.fromRGB(210, 210, 210), dark = Color3.fromRGB(68, 68, 68), deep = Color3.fromRGB(18, 18, 18) },
    { name = "Purple", accent = Color3.fromRGB(190, 145, 255), dark = Color3.fromRGB(86, 48, 125), deep = Color3.fromRGB(30, 18, 43) },
    { name = "Blue", accent = Color3.fromRGB(120, 180, 255), dark = Color3.fromRGB(36, 78, 125), deep = Color3.fromRGB(13, 24, 40) },
    { name = "Red", accent = Color3.fromRGB(255, 120, 130), dark = Color3.fromRGB(126, 43, 53), deep = Color3.fromRGB(39, 12, 16) },
    { name = "Green", accent = Color3.fromRGB(120, 225, 170), dark = Color3.fromRGB(39, 111, 75), deep = Color3.fromRGB(12, 36, 24) },
}

clientModules.personalization.themeIndex = 1
clientModules.personalization.transparency = 0.16
clientModules.personalization.baseColors = {}
for key, value in pairs(COLORS) do
    clientModules.personalization.baseColors[key] = value
end

local function personalizationColorEqual(a, b)
    return typeof(a) == "Color3"
        and typeof(b) == "Color3"
        and math.abs(a.R - b.R) < 0.002
        and math.abs(a.G - b.G) < 0.002
        and math.abs(a.B - b.B) < 0.002
end

function clientModules.personalization.applyTheme(index)
    local theme = clientModules.personalization.themes[index]
    if not theme then return end

    clientModules.personalization.themeIndex = index
    COLORS.Cyan = theme.accent
    COLORS.CyanDark = theme.dark
    COLORS.CyanDeep = theme.deep
    COLORS.Panel = theme.deep
    COLORS.Sidebar = theme.deep
    COLORS.Topbar = theme.deep
    COLORS.Card = theme.deep:Lerp(Color3.new(1, 1, 1), 0.025)
    COLORS.Input = theme.deep:Lerp(Color3.new(0, 0, 0), 0.16)
    COLORS.Border = theme.dark:Lerp(Color3.new(1, 1, 1), 0.08)

    if screenGui and screenGui.Parent then
        for _, object in ipairs(screenGui:GetDescendants()) do
            if object:IsA("GuiObject") then
                local background = object.BackgroundColor3
                for key, base in pairs(clientModules.personalization.baseColors) do
                    if personalizationColorEqual(background, base) then
                        if COLORS[key] then
                            object.BackgroundColor3 = COLORS[key]
                        end
                        break
                    end
                end

                if object:IsA("TextLabel") or object:IsA("TextButton") or object:IsA("TextBox") then
                    if personalizationColorEqual(object.TextColor3, clientModules.personalization.baseColors.Cyan) then
                        object.TextColor3 = COLORS.Cyan
                    elseif personalizationColorEqual(object.TextColor3, clientModules.personalization.baseColors.Text) then
                        object.TextColor3 = COLORS.Text
                    elseif personalizationColorEqual(object.TextColor3, clientModules.personalization.baseColors.MutedText) then
                        object.TextColor3 = COLORS.MutedText
                    end
                end
            elseif object:IsA("UIStroke") then
                if personalizationColorEqual(object.Color, clientModules.personalization.baseColors.Cyan) then
                    object.Color = COLORS.Cyan
                elseif personalizationColorEqual(object.Color, clientModules.personalization.baseColors.Border) then
                    object.Color = COLORS.Border
                end
            end
        end
    end

    if mainFrame and mainFrame.Parent then
        mainFrame.BackgroundTransparency = clientModules.personalization.transparency
    end
    if topBar and topBar.Parent then
        topBar.BackgroundTransparency = math.clamp(clientModules.personalization.transparency - 0.03, 0, 0.8)
    end
    if sidebar and sidebar.Parent then
        sidebar.BackgroundTransparency = math.clamp(clientModules.personalization.transparency + 0.02, 0, 0.8)
    end

    if clientModules.personalization.themeButton then
        clientModules.personalization.themeButton.Text =
            "INTERFACE COLOR  •  " .. theme.name
    end
end

function clientModules.personalization.setTransparency(value)
    local number = tonumber(value)
    if not number then return false end

    clientModules.personalization.transparency = math.clamp(number, 0.05, 0.45)

    if mainFrame and mainFrame.Parent then
        mainFrame.BackgroundTransparency = clientModules.personalization.transparency
    end
    if topBar and topBar.Parent then
        topBar.BackgroundTransparency = math.clamp(clientModules.personalization.transparency - 0.03, 0, 0.8)
    end
    if sidebar and sidebar.Parent then
        sidebar.BackgroundTransparency = math.clamp(clientModules.personalization.transparency + 0.02, 0, 0.8)
    end

    return true
end

createSectionLabel(settingsPage, "SETTINGS  /  PERSONALIZATION", 8)

clientModules.personalization.themeButton = clientModules.createActionButton(
    settingsPage,
    "INTERFACE COLOR  •  Graphite",
    UDim2.new(),
    UDim2.new(1, 0, 0, 40),
    COLORS.CyanDark
)
clientModules.personalization.themeButton.LayoutOrder = 8

clientModules.personalization.transparencyBox = createInputRow(
    settingsPage,
    "Interface transparency (0.05–0.45)",
    "0.16",
    "Example: 0.16",
    9
)

clientModules.personalization.themeButton.Activated:Connect(function()
    local nextIndex = clientModules.personalization.themeIndex + 1
    if nextIndex > #clientModules.personalization.themes then nextIndex = 1 end
    clientModules.personalization.applyTheme(nextIndex)
end)

clientModules.personalization.transparencyBox.FocusLost:Connect(function()
    if clientModules.personalization.setTransparency(clientModules.personalization.transparencyBox.Text) then
        clientModules.personalization.transparencyBox.Text =
            string.format("%.2f", clientModules.personalization.transparency)
    end
end)

clientModules.personalization.applyTheme(1)


createSectionLabel(settingsPage, "CONFIGS  /  SAVED PROFILES", 11)

configManager.configNameBox = createInputRow(
    settingsPage,
    "New config name",
    "Default",
    "Example: Main",
    11
)

configManager.configButtonsRow = create("Frame", {
    LayoutOrder = 12,
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
    LayoutOrder = 13,
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
    LayoutOrder = 14,
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
criticalStopInProgress = false
dragInputChangedConnection = nil
cameraConnection = nil
currentCameraChangedConnection = nil
globalInputConnection = nil

espSurvivorsEnabled = false
espExecutionersEnabled = false
trackedModels = {}
recordedESPContainers = {}
characterModelsFolder = nil
characterModelAddedConnection = nil
characterModelRemovedConnection = nil
characterFolderAncestryConnection = nil
localCharacterAddedConnection = nil
espWorkspaceAddedConnection = nil
espWorkspaceRemovingConnection = nil
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
        Performance = clientModules.pages.performance,
        AutoSelect = clientModules.pages.autoSelect,
        KeyList = clientModules.pages.keyList,
        Settings = settingsPage,
    }
    local buttonByName = {
        Info = clientModules.tabs.info,
        Local = localTab,
        Visuals = visualsTab,
        Performance = clientModules.tabs.performance,
        AutoSelect = clientModules.tabs.autoSelect,
        KeyList = clientModules.tabs.keyList,
        Settings = settingsTab,
    }
    local pageTitles = {
        Info = { "OVERVIEW", "Script information and quick overview" },
        Local = { "LOCAL", "Speed, jump and abilities" },
        Visuals = { "VISUALS", "ESP and on-screen status panels" },
        Performance = { "PERFORMANCE", "Optimization and FPS limiter" },
        AutoSelect = { "AUTO SELECT", "Automatic Survivor selection" },
        KeyList = { "KEY LIST", "All hotkeys in one place" },
        Settings = { "SETTINGS", "Interface, hotkeys and configurations" },
    }

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
-- ============================================================================

ESP_MODEL_ROLE_NAMES = {
    -- Survivors
    sonic = "Survivor",
    tails = "Survivor",
    knuckles = "Survivor",
    eggman = "Survivor",
    amy = "Survivor",
    cream = "Survivor",
    blaze = "Survivor",
    silver = "Survivor",
    metalsonic = "Survivor",

    -- Executioners
    ["2011x"] = "Executioner",
    kolossos = "Executioner",
    tripwire = "Executioner",
    fleetway = "Executioner",
    mss = "Executioner",
}

function normalizeESPModelName(name)
    -- Case-insensitive and ignores spaces, hyphens, underscores, slashes,
    -- and other punctuation. This makes "Metal Sonic" -> "metalsonic".
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
    return model == localPlayer.Character
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
        "Models: %d  •  Survivors: %d  •  Executioners: %d\nMatching models by name anywhere in Workspace",
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

    trackedModels[model] = nil
end

function refreshAllTrackedModels()
    for model, record in pairs(trackedModels) do
        if not model or not model.Parent then
            trackedModels[model] = nil
        elseif record then
            local group = record.group
            local highlight = record.highlight

            if highlight and highlight.Parent and highlight:IsA("Highlight") then
                highlight.FillColor =
                    group == "Survivor" and COLORS.Green or COLORS.Red

                if group == "Survivor" then
                    highlight.Enabled = espSurvivorsEnabled
                elseif group == "Executioner" then
                    highlight.Enabled = espExecutionersEnabled
                else
                    highlight.Enabled = false
                end
            end
        end
    end
end

function registerCharacterModel(model, group)
    if not model or not model:IsA("Model") or isLocalCharacterModel(model) then
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
            highlight = nil,
        }
        trackedModels[model] = record
    else
        record.group = group
    end

    local highlight = getOrCreateESPHighlight(model, record)
    highlight.FillColor = group == "Survivor" and COLORS.Green or COLORS.Red
    highlight.FillTransparency = 0.45
    highlight.OutlineColor = COLORS.White
    highlight.OutlineTransparency = 0

    if group == "Survivor" then
        highlight.Enabled = espSurvivorsEnabled
    else
        highlight.Enabled = espExecutionersEnabled
    end
end

function getESPScanRoot()
    return workspace
end

function scanESPContainers()
    if guiDestroyed then
        return
    end

    local validModels = {}

    -- Search EVERY Workspace descendant. Folder placement is irrelevant.
    for _, instance in ipairs(workspace:GetDescendants()) do
        if instance:IsA("Model") and not isLocalCharacterModel(instance) then
            local group = getESPGroupByModelName(instance.Name)
            if group then
                validModels[instance] = group
            end
        end
    end

    -- Register all currently matching models.
    for model, group in pairs(validModels) do
        registerCharacterModel(model, group)
    end

    -- Remove models that were renamed, moved out, destroyed, or otherwise
    -- stopped matching the configured list.
    local modelsToRemove = {}
    for model in pairs(trackedModels) do
        if not model
            or not model.Parent
            or not validModels[model]
            or not model:IsDescendantOf(workspace) then
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

    -- A new model can appear anywhere in Workspace, so no folder-specific
    -- condition is used here.
    espWorkspaceAddedConnection = workspace.DescendantAdded:Connect(function(instance)
        if guiDestroyed then
            return
        end

        if instance:IsA("Model") or getESPGroupByModelName(instance.Name) then
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

        if instance:IsA("Model") or getESPGroupByModelName(instance.Name) then
            scheduleESPScan(0.15)
        end
    end)

    localCharacterAddedConnection = localPlayer.CharacterAdded:Connect(function()
        scheduleESPScan(0.05)
    end)

    scanESPContainers()
end

function shutdownESP()
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
    setSwitchVisual(
        clientModules.boostTabs.toggleButton,
        clientModules.boostTabs.toggleDot,
        clientModules.boostTabs.enabled
    )

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
    local configName = clientModules.abilityUI.clampTextLength(clientModules.abilityUI.trimText(text), MAX_CONFIG_NAME_LENGTH)

    if configName == "" then
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
    local ok, encodedOrError = pcall(function()
        return HttpService:JSONEncode(configManager.savedConfigs)
    end)

    if not ok then
        configManager.updateConfigStatus("Config encoding error: " .. tostring(encodedOrError), COLORS.Red)
        return false
    end

    local saved, saveError = pcall(function()
        localPlayer:SetAttribute(CONFIG_ATTRIBUTE_NAME, encodedOrError)
    end)

    if not saved then
        configManager.updateConfigStatus("Config save error: " .. tostring(saveError), COLORS.Red)
        return false
    end

    return true
end

function configManager.persistAutoLoadConfig()
    local saved, saveError = pcall(function()
        localPlayer:SetAttribute(AUTO_LOAD_ATTRIBUTE_NAME, configManager.autoLoadConfigName)
    end)

    if not saved then
        configManager.updateConfigStatus("Auto Load save error: " .. tostring(saveError), COLORS.Red)
        return false
    end

    return true
end

function configManager.loadStoredConfigs()
    local encoded = localPlayer:GetAttribute(CONFIG_ATTRIBUTE_NAME)

    if type(encoded) ~= "string" or encoded == "" then
        configManager.savedConfigs = {}
    else
        local ok, decoded = pcall(function()
            return HttpService:JSONDecode(encoded)
        end)

        if ok and type(decoded) == "table" then
            configManager.savedConfigs = decoded
        else
            configManager.savedConfigs = {}
            configManager.updateConfigStatus("Unable to read saved configs.", COLORS.Red)
        end
    end

    local storedAutoLoad = localPlayer:GetAttribute(AUTO_LOAD_ATTRIBUTE_NAME)
    if type(storedAutoLoad) == "string"
        and storedAutoLoad ~= ""
        and type(configManager.savedConfigs[storedAutoLoad]) == "table" then
        configManager.autoLoadConfigName = storedAutoLoad
    else
        configManager.autoLoadConfigName = nil
        pcall(function()
            localPlayer:SetAttribute(AUTO_LOAD_ATTRIBUTE_NAME, nil)
        end)
    end

    configManager.updateConfigStatus("Configs loaded from LocalPlayer.", COLORS.Green)
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
    configManager.configListVisible = visible == true
    configManager.configManagerFrame.Visible = configManager.configListVisible
    configManager.configManagerFrame.Size = configManager.configListVisible
        and UDim2.new(1, 0, 0, 312)
        or UDim2.new(1, 0, 0, 0)
    configManager.listConfigsButton.Text = configManager.configListVisible and "HIDE CONFIGS" or "LIST CONFIGS"

    if configManager.configListVisible then
        configManager.refreshConfigList()
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
        version = 13,
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
boostKeyButton.Activated:Connect(function()
    beginBinding("Boost")
end)
interfaceKeyButton.Activated:Connect(function()
    beginBinding("Interface")
end)
addAbilityButton.Activated:Connect(function()
    clientModules.abilityUI.addNewAbility()
end)

clientModules.criticalTest.button.Activated:Connect(function()
    if criticalState.active then
        return
    end

    -- The intentional error is caught by the ScriptContext monitor. A pcall
    -- fallback keeps the test functional in executors that do not expose it.
    local ok = pcall(function()
        error("[PulseCore TEST] Intentional critical failure.")
    end)
    if not ok and not criticalState.active then
        criticalShutdown("TEST_FAILURE", "Intentional critical failure requested from Settings.")
    end
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
    if guiDestroyed and not criticalStopInProgress then
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
        screenGui:Destroy()
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
    if criticalState.active then return end
    local enabled = localPlayer:GetAttribute(CONSOLE_MODE_ATTRIBUTE_NAME) == true
    localPlayer:SetAttribute(CONSOLE_MODE_ATTRIBUTE_NAME, not enabled)
end)

clientModules.console.attributeConnection =
    localPlayer:GetAttributeChangedSignal(CONSOLE_MODE_ATTRIBUTE_NAME):Connect(function()
        if not guiDestroyed then
            clientModules.console.refreshModeState()
        end
    end)

minimizeButton.Activated:Connect(function()
    if criticalState.active then return end
    minimized = not minimized
    minimizeButton.Text = minimized and "+" or "−"

    if not minimized then
        bodyFrame.Visible = true
    end

    local tween = TweenService:Create(
        mainFrame,
        TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
        { Size = minimized and minimizedSize or expandedSize }
    )

    tween:Play()

    if minimized then
        local completedConnection
        completedConnection = tween.Completed:Connect(function()
            completedConnection:Disconnect()

            if minimized and not guiDestroyed then
                bodyFrame.Visible = false
            end
        end)
    end
end)

closeButton.Activated:Connect(function()
    if criticalState.active then return end
    shutdownMainScript("Interface closed.")
end)

-- Перетаскивание окна мышью или касанием.
do
    local dragging = false
    local dragInput = nil
    local dragStart = nil
    local startPosition = nil

    topBar.InputBegan:Connect(function(input)
        if criticalState.active then return end
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
        if criticalState.active then return end
        if input.UserInputType == Enum.UserInputType.MouseMovement
            or input.UserInputType == Enum.UserInputType.Touch then
            dragInput = input
        end
    end)

    dragInputChangedConnection = UserInputService.InputChanged:Connect(function(input)
        if criticalState.active then return end
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
    if criticalState.active then
        return
    end
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
        screenGui.Enabled = not screenGui.Enabled
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
    configManager.refreshConfigList()
    if configManager.autoLoadConfigName and configManager.savedConfigs[configManager.autoLoadConfigName] then
        configManager.loadConfigByName(configManager.autoLoadConfigName, { auto = true })
    end
    clientModules.abilityUI.updateAddAbilityButton()
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
task.defer(function()
    if not guiDestroyed and mainFrame.Parent then
        local ok, err = pcall(initializeMainInterface)
        if not ok then
            logPulseCoreError("Initialization error: " .. tostring(err))
            warn("[PulseCore] Initialization error: " .. tostring(err))
            criticalShutdown("INIT_FAILURE", tostring(err))
        end
    end
end)