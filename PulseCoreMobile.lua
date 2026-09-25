-- PulseCore Mobile
-- Mobile-only wrapper for the same PulseCore feature set.
-- It loads the current PulseCore.lua and replaces the sidebar interaction with
-- a touch-first scroll surface that also preserves tab activation.

local _httpUrl = "https://raw.githubusercontent.com/Marckoq/loader/main/PulseCore.lua"

local _load = loadstring or load
if type(_load) ~= "function" then
    error("PulseCore Mobile requires loadstring/load support.", 0)
end

local _ok, _src = pcall(function()
    return game:HttpGet(_httpUrl)
end)
if not _ok or type(_src) ~= "string" or #_src == 0 then
    error("PulseCore Mobile failed to download PulseCore.lua.", 0)
end

local _fn, _err = _load(_src, "@PulseCoreMobile")
if not _fn then
    error(_err or "PulseCore Mobile failed to load PulseCore.lua.", 0)
end

local _result = _fn()

task.defer(function()
    pcall(function()
        local Players = game:GetService("Players")
        local UIS = game:GetService("UserInputService")
        local player = Players.LocalPlayer
        local playerGui = player and player:FindFirstChildOfClass("PlayerGui")
        local gui = playerGui and playerGui:FindFirstChild("AssemblySpeedBoostUI")
        local main = gui and gui:FindFirstChild("MainFrame")
        local sidebar = main and main:FindFirstChild("Sidebar")

        if not (gui and main and sidebar) then
            return
        end

        if sidebar:GetAttribute("PulseCoreMobileReady") then
            return
        end
        sidebar:SetAttribute("PulseCoreMobileReady", true)

        gui.IgnoreGuiInset = true
        main.AnchorPoint = Vector2.new(0.5, 0.5)
        main.Position = UDim2.fromScale(0.5, 0.5)

        local uiScale = gui:FindFirstChildOfClass("UIScale")
        if uiScale then
            uiScale.Scale = 1
        end

        local contentScale = main:FindFirstChild("PulseCoreMobileContentScale")
        if not contentScale then
            contentScale = Instance.new("UIScale")
            contentScale.Name = "PulseCoreMobileContentScale"
            contentScale.Scale = 0.9
            contentScale.Parent = main
        else
            contentScale.Scale = 0.9
        end

        local function applyMobilePanelSize()
            local camera = workspace.CurrentCamera
            if not camera then
                return
            end

            local viewport = camera.ViewportSize
            local side = math.min(viewport.X, viewport.Y) - 24
            side = math.clamp(side, 300, 400)

            main.Size = UDim2.fromOffset(side, side)
        end

        applyMobilePanelSize()

        do
            local camera = workspace.CurrentCamera
            if camera then
                camera:GetPropertyChangedSignal("ViewportSize"):Connect(applyMobilePanelSize)
            end
        end

        local mobileSidebar = Instance.new("Frame")
        mobileSidebar.Name = "PulseCoreMobileSidebar"
        mobileSidebar.Position = sidebar.Position
        mobileSidebar.Size = sidebar.Size
        mobileSidebar.BackgroundColor3 = sidebar.BackgroundColor3
        mobileSidebar.BackgroundTransparency = sidebar.BackgroundTransparency
        mobileSidebar.BorderSizePixel = 0
        mobileSidebar.ClipsDescendants = true
        mobileSidebar.ZIndex = sidebar.ZIndex + 1
        mobileSidebar.Parent = sidebar.Parent

        local scroller = Instance.new("ScrollingFrame")
        scroller.Name = "TabScroller"
        scroller.Position = UDim2.fromOffset(0, 0)
        scroller.Size = UDim2.new(1, 0, 1, 0)
        scroller.BackgroundTransparency = 1
        scroller.BorderSizePixel = 0
        scroller.CanvasSize = UDim2.fromOffset(0, 560)
        scroller.ScrollingDirection = Enum.ScrollingDirection.Y
        scroller.ScrollingEnabled = false
        scroller.Active = true
        scroller.ScrollBarThickness = 0
        scroller.ClipsDescendants = true
        scroller.ZIndex = 2
        scroller.Parent = mobileSidebar

        local content = Instance.new("Frame")
        content.Name = "TabContent"
        content.Position = UDim2.fromOffset(0, 0)
        content.Size = UDim2.new(1, 0, 0, 560)
        content.BackgroundTransparency = 1
        content.BorderSizePixel = 0
        content.ClipsDescendants = false
        content.ZIndex = 3
        content.Parent = scroller

        local moveNames = {
            "InfoTab", "LocalTab", "VisualsTab", "CustomTab", "CombatTab",
            "FunTab", "PerformanceTab", "AutoSelectTab", "KeyListTab",
            "SettingsTab", "AnimatedTabBackground", "AnimatedTabBar"
        }

        for _, name in ipairs(moveNames) do
            local obj = sidebar:FindFirstChild(name)
            if obj then
                obj.Parent = content
            end
        end

        sidebar.Visible = false

        local maxBottom = 0
        for _, obj in ipairs(content:GetChildren()) do
            if obj:IsA("GuiObject") then
                local y = obj.Position.Y.Offset
                local h = obj.Size.Y.Offset
                local bottom = y + h
                if bottom > maxBottom then
                    maxBottom = bottom
                end
            end
        end

        local visibleHeight = math.max(1, scroller.AbsoluteSize.Y)
        local canvasHeight = math.max(560, maxBottom + 24, visibleHeight + 1)
        content.Size = UDim2.new(1, 0, 0, canvasHeight)
        scroller.CanvasSize = UDim2.fromOffset(0, canvasHeight)

        local capture = Instance.new("TextButton")
        capture.Name = "TouchCapture"
        capture.Position = UDim2.fromOffset(0, 0)
        capture.Size = UDim2.new(1, 0, 1, 0)
        capture.BackgroundTransparency = 1
        capture.BorderSizePixel = 0
        capture.Text = ""
        capture.AutoButtonColor = false
        capture.Active = true
        capture.Selectable = false
        capture.ZIndex = 100
        capture.Parent = mobileSidebar

        local dragging = false
        local moved = false
        local startY = 0
        local startCanvasY = 0
        local activeTouch = nil
        local dragThreshold = 10

        local function maxScroll()
            return math.max(0, scroller.CanvasSize.Y.Offset - scroller.AbsoluteSize.Y)
        end

        local function pointInside(guiObject, point)
            local pos = guiObject.AbsolutePosition
            local size = guiObject.AbsoluteSize
            return point.X >= pos.X
                and point.X <= pos.X + size.X
                and point.Y >= pos.Y
                and point.Y <= pos.Y + size.Y
        end

        local function activateTabAt(point)
            if moved then
                return
            end

            local best = nil
            local bestArea = nil

            for _, obj in ipairs(content:GetChildren()) do
                if obj:IsA("GuiButton") and obj.Visible and pointInside(obj, point) then
                    local area = obj.AbsoluteSize.X * obj.AbsoluteSize.Y
                    if not best or area < bestArea then
                        best = obj
                        bestArea = area
                    end
                end
            end

            if best then
                pcall(function()
                    best:Activate()
                end)
            end
        end

        capture.InputBegan:Connect(function(input)
            if input.UserInputType ~= Enum.UserInputType.Touch then
                return
            end

            activeTouch = input
            dragging = true
            moved = false
            startY = input.Position.Y
            startCanvasY = scroller.CanvasPosition.Y
        end)

        UIS.InputChanged:Connect(function(input)
            if not dragging or input ~= activeTouch then
                return
            end

            local deltaY = input.Position.Y - startY
            if math.abs(deltaY) >= dragThreshold then
                moved = true
            end

            local nextY = math.clamp(startCanvasY - deltaY, 0, maxScroll())
            if nextY ~= scroller.CanvasPosition.Y then
                scroller.CanvasPosition = Vector2.new(0, nextY)
            end
        end)

        UIS.InputEnded:Connect(function(input)
            if input.UserInputType ~= Enum.UserInputType.Touch or input ~= activeTouch then
                return
            end

            local releasePoint = input.Position
            local wasMoved = moved

            activeTouch = nil
            dragging = false
            moved = false

            if not wasMoved then
                activateTabAt(releasePoint)
            end
        end)

        scroller:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
            local h = math.max(1, scroller.AbsoluteSize.Y)
            scroller.CanvasSize = UDim2.fromOffset(0, math.max(canvasHeight, h + 1))
        end)

        task.defer(function()
            pcall(function()
                local camera = workspace.CurrentCamera
                if not camera then
                    return
                end

                local function applyMobileFrame()
                    local v = camera.ViewportSize
                    if UIS.TouchEnabled and math.min(v.X, v.Y) < 1000 then
                        gui.IgnoreGuiInset = true
                        main.AnchorPoint = Vector2.new(0.5, 0.5)
                        main.Position = UDim2.fromScale(0.5, 0.5)
                        local side = math.min(v.X, v.Y) - 24
                        side = math.clamp(side, 300, 400)
                        main.Size = UDim2.fromOffset(side, side)
                        if uiScale then
                            uiScale.Scale = 1
                        end
                        local contentScale = main:FindFirstChild("PulseCoreMobileContentScale")
                        if contentScale then
                            contentScale.Scale = 0.9
                        end
                    end
                end

                applyMobileFrame()
                camera:GetPropertyChangedSignal("ViewportSize"):Connect(applyMobileFrame)
            end)
        end)
    end)
end)

return _result
