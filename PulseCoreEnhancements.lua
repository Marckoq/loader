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
local activeToken = 0

local function parseDurationValue(value)
    if value==nil then
        return nil
    end

    if value==math.huge then
        return math.huge
    end

    local text=tostring(value)
    if text:lower():find("inf",1,true) then
        return math.huge
    end

    local n=tonumber(value)
    if n and n>0 and n<86400 then
        return n
    end

    local seconds=text:match("([%d%.]+)%s*[sS]")
    n=tonumber(seconds)
    if n and n>0 and n<86400 then
        return n
    end

    return nil
end

local function resolveAbilityDuration(info)
    local roots={info.button,info.nameBox,info.button and info.button.Parent}

    for _,root in ipairs(roots) do
        if root then
            for _,key in ipairs({
                "Duration",
                "AbilityDuration",
                "ActiveDuration",
                "AbilityTime",
                "DurationSeconds",
                "DurationTime",
            }) do
                local value=root:GetAttribute(key)
                local parsed=parseDurationValue(value)
                if parsed then
                    return parsed
                end
            end
        end
    end

    for _,root in ipairs(roots) do
        if root then
            local objects=root:GetDescendants()
            for i=1,math.min(#objects,200) do
                local obj=objects[i]
                local key=tostring(obj.Name or ""):lower()

                if key:find("duration",1,true) or key:find("activetime",1,true) then
                    if obj:IsA("ValueBase") then
                        local parsed=parseDurationValue(obj.Value)
                        if parsed then
                            return parsed
                        end
                    elseif obj:IsA("TextLabel") or obj:IsA("TextBox") then
                        local parsed=parseDurationValue(obj.Text)
                        if parsed then
                            return parsed
                        end
                    end
                end
            end
        end
    end

    return nil
end

local function stopNotificationForToken(sg,token)
    if token~=activeToken then
        return
    end

    if currentNotification~=sg then
        return
    end

    local frame=sg:FindFirstChild("Notification")
    if not frame then
        closeNotification(false)
        return
    end

    closeNotification(true)
end

local function showAbilityNotification(info,durationSeconds)
    closeNotification(false)

    local name=cleanName(info.nameBox and info.nameBox.Text or info.button.Text)
    if name=="" then
        name="Ability"
    end

    activeToken=activeToken+1
    local token=activeToken
    local startedAt=os.clock()

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
    scale.Parent=sg

    local frame=Instance.new("Frame")
    frame.Name="Notification"
    frame.AnchorPoint=Vector2.new(1,1)
    frame.Position=UDim2.new(1,360,1,-18)
    frame.Size=UDim2.fromOffset(340,104)
    frame.BackgroundColor3=Color3.fromRGB(9,9,9)
    frame.BackgroundTransparency=1
    frame.BorderSizePixel=0
    frame.ClipsDescendants=true
    frame.Parent=sg

    local corner=Instance.new("UICorner")
    corner.CornerRadius=UDim.new(0,12)
    corner.Parent=frame

    local stroke=Instance.new("UIStroke")
    stroke.Color=Color3.fromRGB(95,95,95)
    stroke.Thickness=1
    stroke.Transparency=1
    stroke.Parent=frame

    local title=Instance.new("TextLabel")
    title.Position=UDim2.fromOffset(15,9)
    title.Size=UDim2.new(1,-58,0,22)
    title.BackgroundTransparency=1
    title.Text="PulseCore"
    title.Font=Enum.Font.GothamBold
    title.TextSize=17
    title.TextColor3=Color3.fromRGB(255,255,255)
    title.TextTransparency=1
    title.TextXAlignment=Enum.TextXAlignment.Left
    title.Parent=frame

    local close=Instance.new("TextButton")
    close.AnchorPoint=Vector2.new(1,0)
    close.Position=UDim2.new(1,-9,0,7)
    close.Size=UDim2.fromOffset(26,26)
    close.BackgroundTransparency=1
    close.BorderSizePixel=0
    close.Text="X"
    close.Font=Enum.Font.GothamBold
    close.TextSize=16
    close.TextColor3=Color3.fromRGB(205,205,205)
    close.TextTransparency=1
    close.Parent=frame
    close.Activated:Connect(function()
        closeNotification(true)
    end)

    local separator=Instance.new("Frame")
    separator.Position=UDim2.fromOffset(15,32)
    separator.Size=UDim2.new(1,-30,0,1)
    separator.BackgroundColor3=Color3.fromRGB(90,90,90)
    separator.BackgroundTransparency=1
    separator.BorderSizePixel=0
    separator.Parent=frame

    local ability=Instance.new("TextLabel")
    ability.Position=UDim2.fromOffset(15,40)
    ability.Size=UDim2.new(1,-30,0,20)
    ability.BackgroundTransparency=1
    ability.Text='Ability "'..name..'" is activated'
    ability.Font=Enum.Font.GothamMedium
    ability.TextSize=13
    ability.TextColor3=Color3.fromRGB(235,235,235)
    ability.TextTransparency=1
    ability.TextWrapped=true
    ability.TextXAlignment=Enum.TextXAlignment.Left
    ability.Parent=frame

    local durationLabel=Instance.new("TextLabel")
    durationLabel.Position=UDim2.fromOffset(15,63)
    durationLabel.Size=UDim2.new(1,-30,0,22)
    durationLabel.BackgroundTransparency=1
    durationLabel.Text=durationSeconds==math.huge
        and "Duration: Inf"
        or durationSeconds
            and ("Duration: "..string.format("%.1f",durationSeconds))
            or "Duration: N/A"
    durationLabel.Font=Enum.Font.GothamMedium
    durationLabel.TextSize=13
    durationLabel.TextColor3=Color3.fromRGB(185,185,185)
    durationLabel.TextTransparency=1
    durationLabel.TextXAlignment=Enum.TextXAlignment.Left
    durationLabel.Parent=frame

    local progressBack=Instance.new("Frame")
    progressBack.Name="ProgressBackground"
    progressBack.Position=UDim2.new(0,12,1,-8)
    progressBack.Size=UDim2.new(1,-24,0,4)
    progressBack.BackgroundColor3=Color3.fromRGB(48,48,48)
    progressBack.BackgroundTransparency=1
    progressBack.BorderSizePixel=0
    progressBack.ClipsDescendants=true
    progressBack.Parent=frame

    local progress=Instance.new("Frame")
    progress.Name="Progress"
    progress.Size=UDim2.fromScale(1,1)
    progress.BackgroundColor3=Color3.fromRGB(175,175,175)
    progress.BorderSizePixel=0
    progress.Parent=progressBack

    local pcorner=Instance.new("UICorner")
    pcorner.CornerRadius=UDim.new(0,999)
    pcorner.Parent=progress

    local camera=workspace.CurrentCamera
    if camera then
        local function updateScale()
            local v=camera.ViewportSize
            scale.Scale=math.clamp(math.min(v.X,v.Y)/430,0.72,1)
        end

        updateScale()

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

    TweenService:Create(title,intro,{TextTransparency=0}):Play()
    TweenService:Create(close,intro,{TextTransparency=0}):Play()
    TweenService:Create(ability,intro,{TextTransparency=0}):Play()
    TweenService:Create(durationLabel,intro,{TextTransparency=0}):Play()
    TweenService:Create(separator,intro,{BackgroundTransparency=0}):Play()
    TweenService:Create(progressBack,intro,{BackgroundTransparency=0}):Play()
    TweenService:Create(stroke,intro,{Transparency=0.05}):Play()

    if durationSeconds and durationSeconds~=math.huge and durationSeconds>0 then
        TweenService:Create(
            progress,
            TweenInfo.new(durationSeconds,Enum.EasingStyle.Linear),
            {Size=UDim2.new(0,0,1,0)}
        ):Play()

        task.spawn(function()
            durationLabel.Text="Duration: "..string.format("%.1f",durationSeconds)

            while currentNotification==sg and token==activeToken and sg.Parent do
                local remaining=math.max(0,durationSeconds-(os.clock()-startedAt))
                durationLabel.Text="Duration: "..string.format("%.1f",remaining)

                if remaining<=0 then
                    durationLabel.Text="Duration: 0.0"
                    task.wait(0.05)

                    if currentNotification==sg and token==activeToken and sg.Parent then
                        closeNotification(true)
                    end

                    break
                end

                task.wait(0.05)
            end
        end)
    elseif durationSeconds==math.huge then
        durationLabel.Text="Duration: Inf"
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
            local d=resolveAbilityDuration(info)

            if not d and name~="" then
                d=learnedDurations[name]
            end

            activeStarts[button]=os.clock()
            showAbilityNotification(info,d)
        elseif wasActive and not isActive then
            local info=findAbilityInfo(button) or {button=button}
            local name=cleanName(info.nameBox and info.nameBox.Text or button.Text)
            local started=activeStarts[button]

            if started then
                local observed=os.clock()-started
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

localPage.DescendantAdded:Connect(function(obj)
    task.defer(function()
        if obj:IsA("GuiButton") then
            hookAbilityButton(obj)
        end
        scanAbilityButtons()
    end)
end)

