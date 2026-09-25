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

local function getHumanoid()
    local character=player.Character
    return character and character:FindFirstChildOfClass("Humanoid")
end

local noJumpCooldown=true
local jumpConnection
local jumpHeartbeat
local queuedJump=false
local lastHumanoid=nil
local lastGrounded=true

local function getHumanoid()
    local character=player.Character
    return character and character:FindFirstChildOfClass("Humanoid")
end

local function grounded(humanoid)
    return humanoid
        and humanoid.Health>0
        and humanoid.FloorMaterial~=Enum.Material.Air
end

local function performQueuedJump(humanoid)
    if not noJumpCooldown or not humanoid or humanoid.Health<=0 then
        return
    end

    if not grounded(humanoid) then
        return
    end

    queuedJump=false
    humanoid.Jump=true
end

jumpConnection=UIS.JumpRequest:Connect(function()
    if not noJumpCooldown then
        return
    end

    local humanoid=getHumanoid()
    if not humanoid then
        return
    end

    if grounded(humanoid) then
        -- Let Roblox perform the first jump normally.
        lastGrounded=true
        return
    end

    -- A second jump request made while airborne is queued and will
    -- execute immediately after landing, removing the jump cooldown
    -- without creating a second jump from a single input.
    queuedJump=true
    lastGrounded=false
end)

jumpHeartbeat=RunService.Heartbeat:Connect(function()
    if not noJumpCooldown then
        queuedJump=false
        return
    end

    local humanoid=getHumanoid()
    if not humanoid then
        queuedJump=false
        return
    end

    if humanoid~=lastHumanoid then
        lastHumanoid=humanoid
        lastGrounded=grounded(humanoid)
        queuedJump=false
    end

    local isGrounded=grounded(humanoid)

    if isGrounded and not lastGrounded and queuedJump then
        performQueuedJump(humanoid)
    end

    lastGrounded=isGrounded
end)

local oldToggle=localPage:FindFirstChild("PulseCoreNoJumpCooldown",true)
if oldToggle then
    oldToggle:Destroy()
end

local row=Instance.new("Frame")
row.Name="PulseCoreNoJumpCooldown"
row.LayoutOrder=0
row.Size=UDim2.new(1,0,0,50)
row.BackgroundColor3=Color3.fromRGB(30,30,30)
row.BackgroundTransparency=0.16
row.BorderSizePixel=0
row.Parent=localPage

local rowCorner=Instance.new("UICorner")
rowCorner.CornerRadius=UDim.new(0,9)
rowCorner.Parent=row

local rowStroke=Instance.new("UIStroke")
rowStroke.Color=Color3.fromRGB(70,70,70)
rowStroke.Transparency=0.28
rowStroke.Thickness=1
rowStroke.Parent=row

local label=Instance.new("TextLabel")
label.Position=UDim2.fromOffset(14,0)
label.Size=UDim2.new(1,-100,1,0)
label.BackgroundTransparency=1
label.Text="No Jump Cooldown"
label.Font=Enum.Font.GothamMedium
label.TextSize=13
label.TextColor3=Color3.fromRGB(235,235,235)
label.TextWrapped=true
label.TextXAlignment=Enum.TextXAlignment.Left
label.Parent=row

local toggle=Instance.new("TextButton")
toggle.AnchorPoint=Vector2.new(1,0.5)
toggle.Position=UDim2.new(1,-11,0.5,0)
toggle.Size=UDim2.fromOffset(58,30)
toggle.BackgroundColor3=Color3.fromRGB(38,38,38)
toggle.BorderSizePixel=0
toggle.Text=""
toggle.AutoButtonColor=false
toggle.Parent=row

local toggleCorner=Instance.new("UICorner")
toggleCorner.CornerRadius=UDim.new(0,999)
toggleCorner.Parent=toggle

local dot=Instance.new("Frame")
dot.AnchorPoint=Vector2.new(0,0.5)
dot.Position=UDim2.new(1,-27,0.5,0)
dot.Size=UDim2.fromOffset(22,22)
dot.BackgroundColor3=Color3.fromRGB(225,245,255)
dot.BorderSizePixel=0
dot.Parent=toggle

local dotCorner=Instance.new("UICorner")
dotCorner.CornerRadius=UDim.new(0,999)
dotCorner.Parent=dot

local function refreshToggle()
    toggle.BackgroundColor3=noJumpCooldown
        and Color3.fromRGB(20,95,135)
        or Color3.fromRGB(38,38,38)

    dot.BackgroundColor3=noJumpCooldown
        and Color3.fromRGB(225,245,255)
        or Color3.fromRGB(135,135,135)

    TweenService:Create(
        dot,
        TweenInfo.new(0.14,Enum.EasingStyle.Quad,Enum.EasingDirection.Out),
        {Position=noJumpCooldown
            and UDim2.new(1,-27,0.5,0)
            or UDim2.new(0,5,0.5,0)}
    ):Play()
end

toggle.Activated:Connect(function()
    noJumpCooldown=not noJumpCooldown
    queuedJump=false
    refreshToggle()
end)

local function findAbilityByButton(button)
    local order=tonumber(button.LayoutOrder)
    if not order then
        return nil
    end

    local base=order-16
    local nameBox
    local delayBox
    local durationBox

    for _,obj in ipairs(localPage:GetChildren()) do
        if obj:IsA("GuiObject") then
            local childOrder=tonumber(obj.LayoutOrder)
            if childOrder==base then
                nameBox=obj:FindFirstChildWhichIsA("TextBox",true)
            elseif childOrder==base+7 then
                delayBox=obj:FindFirstChildWhichIsA("TextBox",true)
            elseif childOrder==base+8 then
                durationBox=obj:FindFirstChildWhichIsA("TextBox",true)
            end
        end
    end

    return {
        button=button,
        nameBox=nameBox,
        delayBox=delayBox,
        durationBox=durationBox,
    }
end

local currentNotification

local function closeNotification()
    if currentNotification then
        pcall(function()
            currentNotification:Destroy()
        end)
        currentNotification=nil
    end
end

local function cleanName(value)
    value=tostring(value or "")
    value=value:gsub("^%s+",""):gsub("%s+$","")
    value=value:gsub("^ACTIVATE%s+","")
    value=value:gsub("^STOP%s+","")
    value=value:gsub("^COOLDOWN%s+","")
    value=value:gsub("%s*%[[^%]]*%]%s*$","")
    value=value:gsub("%s*:%s*[%d%.]+%s*sec%.?$","")
    return value
end

local function showNotification(info)
    closeNotification()

    local name=cleanName(info.nameBox and info.nameBox.Text or info.button.Text)
    if name=="" then
        name="Ability"
    end

    local delayValue=tostring(info.delayBox and info.delayBox.Text or "")
    local durationValue=tostring(info.durationBox and info.durationBox.Text or "")
    local delayNumber=tonumber(delayValue)
    local durationNumber=tonumber(durationValue)

    local delayText=(delayNumber and delayNumber>0)
        and string.format("%.1fs",delayNumber)
        or "N/A"

    local durationText
    if durationValue:lower()=="inf" then
        durationText="N/A"
    elseif durationNumber and durationNumber>0 then
        durationText=string.format("%.1fs",durationNumber)
    else
        durationText="N/A"
    end

    local sg=Instance.new("ScreenGui")
    sg.Name="PulseCoreAbilityNotification"
    sg.ResetOnSpawn=false
    sg.IgnoreGuiInset=true
    sg.DisplayOrder=3000
    sg.ZIndexBehavior=Enum.ZIndexBehavior.Sibling
    sg.Parent=playerGui
    currentNotification=sg

    local scale=Instance.new("UIScale")
    scale.Scale=0.9
    scale.Parent=sg

    local camera=workspace.CurrentCamera

    local frame=Instance.new("Frame")
    frame.AnchorPoint=Vector2.new(1,0)
    frame.Position=UDim2.new(1,-18,0,18)
    frame.Size=UDim2.fromOffset(320,116)
    frame.BackgroundColor3=Color3.fromRGB(0,0,0)
    frame.BackgroundTransparency=0.2
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
    stroke.Transparency=0.05
    stroke.Parent=frame

    local title=Instance.new("TextLabel")
    title.Position=UDim2.fromOffset(14,9)
    title.Size=UDim2.new(1,-56,0,22)
    title.BackgroundTransparency=1
    title.Text="PulseCore"
    title.Font=Enum.Font.GothamBold
    title.TextSize=18
    title.TextColor3=Color3.fromRGB(255,255,255)
    title.TextXAlignment=Enum.TextXAlignment.Left
    title.ZIndex=2
    title.Parent=frame

    local close=Instance.new("TextButton")
    close.AnchorPoint=Vector2.new(1,0)
    close.Position=UDim2.new(1,-8,0,7)
    close.Size=UDim2.fromOffset(28,28)
    close.BackgroundTransparency=1
    close.BorderSizePixel=0
    close.Text="×"
    close.Font=Enum.Font.GothamBold
    close.TextSize=20
    close.TextColor3=Color3.fromRGB(205,205,205)
    close.ZIndex=3
    close.Parent=frame
    close.Activated:Connect(closeNotification)

    local ability=Instance.new("TextLabel")
    ability.Position=UDim2.fromOffset(14,34)
    ability.Size=UDim2.new(1,-28,0,24)
    ability.BackgroundTransparency=1
    ability.Text="Ability \"" .. name .. "\" is activated"
    ability.Font=Enum.Font.GothamMedium
    ability.TextSize=13
    ability.TextColor3=Color3.fromRGB(235,235,235)
    ability.TextWrapped=true
    ability.TextXAlignment=Enum.TextXAlignment.Left
    ability.ZIndex=2
    ability.Parent=frame

    local details=Instance.new("TextLabel")
    details.Position=UDim2.fromOffset(14,59)
    details.Size=UDim2.new(1,-28,0,34)
    details.BackgroundTransparency=1
    details.Text=string.format("Duration: %s\nDelay: %s",durationText,delayText)
    details.Font=Enum.Font.Gotham
    details.TextSize=12
    details.TextColor3=Color3.fromRGB(185,185,185)
    details.TextWrapped=true
    details.TextXAlignment=Enum.TextXAlignment.Left
    details.ZIndex=2
    details.Parent=frame

    local progressBack=Instance.new("Frame")
    progressBack.Position=UDim2.new(0,10,1,-9)
    progressBack.Size=UDim2.new(1,-20,0,3)
    progressBack.BackgroundColor3=Color3.fromRGB(48,48,48)
    progressBack.BorderSizePixel=0
    progressBack.ClipsDescendants=true
    progressBack.ZIndex=2
    progressBack.Parent=frame

    local progress=Instance.new("Frame")
    progress.Size=UDim2.fromScale(1,1)
    progress.BackgroundColor3=Color3.fromRGB(175,175,175)
    progress.BorderSizePixel=0
    progress.ZIndex=3
    progress.Parent=progressBack

    local progressCorner=Instance.new("UICorner")
    progressCorner.CornerRadius=UDim.new(0,999)
    progressCorner.Parent=progress

    local closed=false
    local function destroy()
        if closed then
            return
        end
        closed=true
        if currentNotification==sg then
            currentNotification=nil
        end
        pcall(function()
            sg:Destroy()
        end)
    end

    close.Activated:Connect(destroy)

    local function updateScale()
        if not camera then
            return
        end
        local v=camera.ViewportSize
        scale.Scale=math.clamp(math.min(v.X,v.Y)/430,0.72,0.95)
    end

    updateScale()
    if camera then
        camera:GetPropertyChangedSignal("ViewportSize"):Connect(function()
            if not closed then
                updateScale()
            end
        end)
    end

    if durationNumber and durationNumber>0 then
        local tween=TweenService:Create(
            progress,
            TweenInfo.new(durationNumber,Enum.EasingStyle.Linear,Enum.EasingDirection.Out),
            {Size=UDim2.fromScale(0,1)}
        )
        tween:Play()

        task.delay(durationNumber,function()
            if not closed then
                destroy()
            end
        end)
    end
end

local function hookButton(button)
    if not button:IsA("GuiButton") or button:GetAttribute("PulseCoreAbilityNotificationHooked") then
        return
    end

    local text=tostring(button.Text or "")
    if text:sub(1,9)~="ACTIVATE " and text:sub(1,5)~="STOP " and text:sub(1,9)~="COOLDOWN " then
        return
    end

    if text:find("SPEED BOOST",1,true) then
        return
    end

    button:SetAttribute("PulseCoreAbilityNotificationHooked",true)

    button.Activated:Connect(function()
        task.defer(function()
            if not button.Parent then
                closeNotification()
                return
            end

            local currentText=tostring(button.Text or "")
            if currentText:sub(1,5)=="STOP " then
                showNotification(findAbilityByButton(button) or {button=button})
            elseif currentText:sub(1,9)=="ACTIVATE " or currentText:sub(1,9)=="COOLDOWN " then
                closeNotification()
            end
        end)
    end)
end

local function scan()
    for _,obj in ipairs(localPage:GetDescendants()) do
        if obj:IsA("GuiButton") then
            hookButton(obj)
        end
    end
end

scan()

localPage.DescendantAdded:Connect(function(obj)
    task.defer(function()
        if obj:IsA("GuiButton") then
            hookButton(obj)
        end
        scan()
    end)
end)

RunService.Heartbeat:Connect(function()
    if currentNotification then
        if not currentNotification.Parent then
            currentNotification=nil
            return
        end

        local active=false
        for _,obj in ipairs(localPage:GetDescendants()) do
            if obj:IsA("GuiButton") and obj:GetAttribute("PulseCoreAbilityNotificationHooked") then
                if tostring(obj.Text or ""):sub(1,5)=="STOP " then
                    active=true
                    break
                end
            end
        end

        if not active then
            closeNotification()
        end
    end
end)
