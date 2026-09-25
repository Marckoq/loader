local Players=game:GetService("Players")
local UIS=game:GetService("UserInputService")
local RunService=game:GetService("RunService")
local TweenService=game:GetService("TweenService")

local player=Players.LocalPlayer
local playerGui=player and player:FindFirstChildOfClass("PlayerGui")

if not playerGui then
    return
end

local function waitForGui()
    local gui=playerGui:FindFirstChild("AssemblySpeedBoostUI",true)
    for _=1,60 do
        if gui and gui.Parent then
            return gui
        end
        task.wait(0.1)
        gui=playerGui:FindFirstChild("AssemblySpeedBoostUI",true)
    end
    return gui
end

local gui=waitForGui()
if not gui then
    return
end

local localPage=gui:FindFirstChild("LocalPage",true)
if not localPage then
    return
end

local currentNotification
local currentOwnerButton

local function closeNotification()
    if currentNotification then
        pcall(function()
            currentNotification:Destroy()
        end)
        currentNotification=nil
    end
    currentOwnerButton=nil
end

local function cleanName(value)
    value=tostring(value or "")
    value=value:gsub("^%s+",""):gsub("%s+$","")
    value=value:gsub("^ACTIVATE%s+","")
    value=value:gsub("^STOP%s+","")
    value=value:gsub("^COOLDOWN%s+","")
    value=value:gsub("%s*%[[^%]]*%]%s*$","")
    return value
end

local function findAbilityInfo(button)
    local order=tonumber(button.LayoutOrder)
    if not order then
        return nil
    end

    local base=order-16
    local info={
        button=button,
        nameBox=nil,
    }

    for _,obj in ipairs(localPage:GetChildren()) do
        if obj:IsA("GuiObject") then
            local childOrder=tonumber(obj.LayoutOrder)
            if childOrder==base then
                info.nameBox=obj:FindFirstChildWhichIsA("TextBox",true)
                break
            end
        end
    end

    return info
end


local learnedDurations = {}
local activeStarts = {}

local function readPositiveNumber(value)
    local n = tonumber(value)
    if n and n > 0 and n < 86400 then
        return n
    end
    return nil
end

local function resolveAbilityDuration(info)
    local roots = {
        info.button,
        info.nameBox,
        info.button and info.button.Parent,
    }

    local attributeNames = {
        "Duration",
        "AbilityDuration",
        "ActiveDuration",
        "AbilityTime",
        "DurationSeconds",
        "DurationTime",
    }

    for _, root in ipairs(roots) do
        if root then
            for _, name in ipairs(attributeNames) do
                local value = root:GetAttribute(name)
                local n = readPositiveNumber(value)
                if n then
                    return n
                end
            end
        end
    end

    for _, root in ipairs(roots) do
        if root then
            for _, obj in ipairs(root:GetDescendants()) do
                if obj:IsA("NumberValue") or obj:IsA("IntValue") then
                    local key = tostring(obj.Name):lower()
                    if key:find("duration",1,true) or key:find("activetime",1,true) then
                        local n = readPositiveNumber(obj.Value)
                        if n then
                            return n
                        end
                    end
                elseif obj:IsA("StringValue") then
                    local key = tostring(obj.Name):lower()
                    if key:find("duration",1,true) or key:find("activetime",1,true) then
                        local n = tonumber(tostring(obj.Value):match("(%d+%.?%d*)"))
                        n = readPositiveNumber(n)
                        if n then
                            return n
                        end
                    end
                elseif obj:IsA("TextLabel") or obj:IsA("TextBox") then
                    local key = tostring(obj.Name):lower()
                    if key:find("duration",1,true) or key:find("timer",1,true) then
                        local n = tonumber(tostring(obj.Text or ""):match("(%d+%.?%d*)"))
                        n = readPositiveNumber(n)
                        if n then
                            return n
                        end
                    end
                end
            end
        end
    end

    return nil
end

local function animateNotificationOut(sg, frame, labels, stroke, durationBackground)
    if not sg or not frame or sg.Parent == nil then
        return
    end

    local info = TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.In)

    TweenService:Create(frame,info,{
        Position=UDim2.new(1,360,1,-18),
        BackgroundTransparency=1,
    }):Play()

    for _, label in ipairs(labels) do
        if label and label.Parent then
            TweenService:Create(label,info,{TextTransparency=1}):Play()
        end
    end

    if stroke and stroke.Parent then
        TweenService:Create(stroke,info,{Transparency=1}):Play()
    end

    if durationBackground and durationBackground.Parent then
        TweenService:Create(durationBackground,info,{BackgroundTransparency=1}):Play()
    end

    task.delay(0.2,function()
        pcall(function()
            sg:Destroy()
        end)
    end)
end

local function closeNotification(animated)
    if not currentNotification then
        currentOwnerButton=nil
        return
    end

    local sg=currentNotification
    currentNotification=nil
    currentOwnerButton=nil

    local frame=sg:FindFirstChild("Notification")
    if not animated or not frame then
        pcall(function()
            sg:Destroy()
        end)
        return
    end

    local stroke=frame:FindFirstChildOfClass("UIStroke")
    local durationBackground=frame:FindFirstChild("ProgressBackground")
    local labels={}

    for _, obj in ipairs(frame:GetChildren()) do
        if obj:IsA("TextLabel") or obj:IsA("TextButton") then
            labels[#labels+1]=obj
        end
    end

    animateNotificationOut(sg,frame,labels,stroke,durationBackground)
end

local function showAbilityNotification(info, durationSeconds)
    closeNotification(false)

    local name=cleanName(info.nameBox and info.nameBox.Text or info.button.Text)
    if name=="" then
        name="Ability"
    end

    local sg=Instance.new("ScreenGui")
    sg.Name="PulseCoreAbilityNotification"
    sg.ResetOnSpawn=false
    sg.IgnoreGuiInset=true
    sg.DisplayOrder=3000
    sg.ZIndexBehavior=Enum.ZIndexBehavior.Sibling
    sg.Parent=playerGui

    currentNotification=sg
    currentOwnerButton=info.button

    local scale=Instance.new("UIScale")
    scale.Name="DeviceScale"
    scale.Parent=sg

    local frame=Instance.new("Frame")
    frame.Name="Notification"
    frame.AnchorPoint=Vector2.new(1,1)
    frame.Position=UDim2.new(1,360,1,-18)
    frame.Size=UDim2.fromOffset(320,92)
    frame.BackgroundColor3=Color3.fromRGB(0,0,0)
    frame.BackgroundTransparency=1
    frame.BorderSizePixel=0
    frame.ClipsDescendants=true
    frame.ZIndex=1
    frame.Parent=sg

    local corner=Instance.new("UICorner")
    corner.CornerRadius=UDim.new(0,10)
    corner.Parent=frame

    local stroke=Instance.new("UIStroke")
    stroke.Color=Color3.fromRGB(125,125,125)
    stroke.Thickness=1.5
    stroke.Transparency=1
    stroke.Parent=frame

    local title=Instance.new("TextLabel")
    title.Position=UDim2.fromOffset(14,8)
    title.Size=UDim2.new(1,-56,0,22)
    title.BackgroundTransparency=1
    title.Text="PulseCore"
    title.Font=Enum.Font.GothamBold
    title.TextSize=18
    title.TextColor3=Color3.fromRGB(255,255,255)
    title.TextTransparency=1
    title.TextXAlignment=Enum.TextXAlignment.Left
    title.ZIndex=2
    title.Parent=frame

    local close=Instance.new("TextButton")
    close.AnchorPoint=Vector2.new(1,0)
    close.Position=UDim2.new(1,-8,0,6)
    close.Size=UDim2.fromOffset(28,28)
    close.BackgroundTransparency=1
    close.BorderSizePixel=0
    close.Text="X"
    close.Font=Enum.Font.GothamBold
    close.TextSize=16
    close.TextColor3=Color3.fromRGB(205,205,205)
    close.TextTransparency=1
    close.ZIndex=3
    close.Parent=frame
    close.Activated:Connect(function()
        closeNotification(true)
    end)

    local separator=Instance.new("Frame")
    separator.Position=UDim2.fromOffset(14,31)
    separator.Size=UDim2.new(1,-28,0,1)
    separator.BackgroundColor3=Color3.fromRGB(90,90,90)
    separator.BackgroundTransparency=1
    separator.BorderSizePixel=0
    separator.ZIndex=2
    separator.Parent=frame

    local ability=Instance.new("TextLabel")
    ability.Position=UDim2.fromOffset(14,37)
    ability.Size=UDim2.new(1,-28,0,20)
    ability.BackgroundTransparency=1
    ability.Text='Ability "'..name..'" is activated'
    ability.Font=Enum.Font.GothamMedium
    ability.TextSize=13
    ability.TextColor3=Color3.fromRGB(235,235,235)
    ability.TextTransparency=1
    ability.TextWrapped=true
    ability.TextXAlignment=Enum.TextXAlignment.Left
    ability.ZIndex=2
    ability.Parent=frame

    local duration=Instance.new("TextLabel")
    duration.Position=UDim2.fromOffset(14,58)
    duration.Size=UDim2.new(1,-28,0,20)
    duration.BackgroundTransparency=1
    duration.Text="Duration: N/A"
    duration.Font=Enum.Font.Gotham
    duration.TextSize=12
    duration.TextColor3=Color3.fromRGB(185,185,185)
    duration.TextTransparency=1
    duration.TextXAlignment=Enum.TextXAlignment.Left
    duration.ZIndex=2
    duration.Parent=frame

    local progressBack=Instance.new("Frame")
    progressBack.Name="ProgressBackground"
    progressBack.Position=UDim2.new(0,10,1,-8)
    progressBack.Size=UDim2.new(1,-20,0,3)
    progressBack.BackgroundColor3=Color3.fromRGB(48,48,48)
    progressBack.BackgroundTransparency=1
    progressBack.BorderSizePixel=0
    progressBack.ClipsDescendants=true
    progressBack.ZIndex=2
    progressBack.Parent=frame

    local progress=Instance.new("Frame")
    progress.Name="Progress"
    progress.Size=UDim2.fromScale(1,1)
    progress.BackgroundColor3=Color3.fromRGB(175,175,175)
    progress.BorderSizePixel=0
    progress.ZIndex=3
    progress.Parent=progressBack

    local progressCorner=Instance.new("UICorner")
    progressCorner.CornerRadius=UDim.new(0,999)
    progressCorner.Parent=progress

    local function updateScale()
        local camera=workspace.CurrentCamera
        if not camera or not sg.Parent then
            return
        end

        local v=camera.ViewportSize
        scale.Scale=math.clamp(math.min(v.X,v.Y)/430,0.72,0.95)
    end

    updateScale()

    local camera=workspace.CurrentCamera
    if camera then
        camera:GetPropertyChangedSignal("ViewportSize"):Connect(function()
            if currentNotification==sg then
                updateScale()
            end
        end)
    end

    local intro=TweenInfo.new(0.22,Enum.EasingStyle.Quart,Enum.EasingDirection.Out)

    TweenService:Create(frame,intro,{
        Position=UDim2.new(1,-18,1,-18),
        BackgroundTransparency=0.2,
    }):Play()

    for _, obj in ipairs({title,close,separator,ability,duration,progressBack}) do
        if obj:IsA("TextLabel") or obj:IsA("TextButton") then
            TweenService:Create(obj,intro,{TextTransparency=0}):Play()
        else
            TweenService:Create(obj,intro,{BackgroundTransparency=0}):Play()
        end
    end

    TweenService:Create(stroke,intro,{Transparency=0.05}):Play()

    if durationSeconds and durationSeconds>0 then
        TweenService:Create(
            progress,
            TweenInfo.new(durationSeconds,Enum.EasingStyle.Linear,Enum.EasingDirection.Out),
            {Size=UDim2.new(0,0,1,0)}
        ):Play()
    end
end

local function isAbilityButton(button)
    if not button:IsA("GuiButton") then
        return false
    end

    if button:GetAttribute("PulseCoreAbilityNotificationHooked") then
        return true
    end

    local text=tostring(button.Text or "")
    if text:sub(1,9)=="ACTIVATE " or text:sub(1,5)=="STOP " or text:sub(1,9)=="COOLDOWN " then
        return not text:find("SPEED BOOST",1,true)
    end

    local order=tonumber(button.LayoutOrder)
    if order then
        local slotOffset=(order-46)%17
        return slotOffset==0
    end

    return false
end

local function hookAbilityButton(button)
    if not button:IsA("GuiButton") or button:GetAttribute("PulseCoreAbilityNotificationHooked") then
        return
    end

    if not isAbilityButton(button) then
        return
    end

    button:SetAttribute("PulseCoreAbilityNotificationHooked",true)

    local previousText=tostring(button.Text or "")

    button:GetPropertyChangedSignal("Text"):Connect(function()
        local newText=tostring(button.Text or "")
        local wasActive=previousText:sub(1,5)=="STOP "
        local isActive=newText:sub(1,5)=="STOP "

        if isActive and not wasActive then
            local info=findAbilityInfo(button) or {button=button}
            local name=cleanName(info.nameBox and info.nameBox.Text or button.Text)
            local resolvedDuration=resolveAbilityDuration(info)

            if not resolvedDuration and name~="" then
                resolvedDuration=learnedDurations[name]
            end

            activeStarts[button]=os.clock()
            showAbilityNotification(info,resolvedDuration)
        elseif wasActive and not isActive then
            local info=findAbilityInfo(button) or {button=button}
            local name=cleanName(info.nameBox and info.nameBox.Text or button.Text)
            local startedAt=activeStarts[button]

            if startedAt then
                local observed=os.clock()-startedAt
                if observed>0.05 and observed<86400 and name~="" then
                    learnedDurations[name]=observed
                end
            end

            activeStarts[button]=nil

            if currentOwnerButton==button then
                closeNotification(true)
            end
        end

        previousText=newText
    end)

    button.Destroying:Connect(function()
        activeStarts[button]=nil
        if currentOwnerButton==button then
            closeNotification(true)
        end
    end)
end

local function scanAbilityButtons()
    for _,obj in ipairs(localPage:GetDescendants()) do
        if obj:IsA("GuiButton") then
            hookAbilityButton(obj)
        end
    end
end

scanAbilityButtons()

task.defer(function()
    pcall(function()
        local noJumpEnabled=true
        local toggleConnection

        local function getHumanoid()
            local character=player.Character
            return character and character:FindFirstChildOfClass("Humanoid")
        end

        local function refreshNoJumpState(row)
            local toggle=row and row:FindFirstChild("Toggle",true)
            if not toggle or not toggle:IsA("GuiButton") then
                return
            end

            local c=toggle.BackgroundColor3
            noJumpEnabled=(c.R>0.05 and c.G>0.25 and c.B>0.35)

            if toggleConnection then
                toggleConnection:Disconnect()
            end

            toggleConnection=toggle.Activated:Connect(function()
                noJumpEnabled=not noJumpEnabled
            end)
        end

        local function allowJump()
            if not noJumpEnabled then
                return
            end

            local humanoid=getHumanoid()
            if not humanoid or humanoid.Health<=0 then
                return
            end

            pcall(function()
                humanoid:SetStateEnabled(Enum.HumanoidStateType.Jumping,true)
                humanoid.Jump=true
            end)
        end

        UIS.JumpRequest:Connect(allowJump)

        player.CharacterAdded:Connect(function(character)
            task.defer(function()
                local humanoid=character:FindFirstChildOfClass("Humanoid")
                    or character:WaitForChild("Humanoid",5)

                if humanoid and noJumpEnabled then
                    pcall(function()
                        humanoid:SetStateEnabled(Enum.HumanoidStateType.Jumping,true)
                    end)
                end
            end)
        end)

        for _=1,100 do
            local row=localPage:FindFirstChild("PulseCoreNoJumpCooldown",true)
            if row then
                refreshNoJumpState(row)
                break
            end
            task.wait(0.1)
        end
    end)
end)

localPage.DescendantAdded:Connect(function(obj)
    task.defer(function()
        if obj:IsA("GuiButton") then
            hookAbilityButton(obj)
        end
        scanAbilityButtons()
    end)
end)

