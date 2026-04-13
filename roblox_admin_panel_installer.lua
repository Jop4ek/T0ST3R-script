local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local StarterPlayer = game:GetService("StarterPlayer")

local ADMIN_USER_IDS = {
    12345678,
}

local REMOTE_NAME = "AdminPanelRemote"
local SERVER_SCRIPT_NAME = "AdminPanelServer"
local CLIENT_SCRIPT_NAME = "AdminPanelClient"

local function idsToLiteral(ids)
    local parts = {}
    for _, id in ipairs(ids) do
        table.insert(parts, tostring(id))
    end
    return table.concat(parts, ", ")
end

local idsLiteral = idsToLiteral(ADMIN_USER_IDS)

local serverSource = [===[
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local REMOTE_NAME = "__REMOTE_NAME__"
local ADMIN_USER_IDS = {__ADMIN_IDS__}

local remote = ReplicatedStorage:WaitForChild(REMOTE_NAME)
local adminLookup = {}

for _, userId in ipairs(ADMIN_USER_IDS) do
    adminLookup[userId] = true
end

local function isAdmin(player)
    return player and adminLookup[player.UserId] == true
end

local function notify(player, message, success)
    remote:FireClient(player, "Notify", {
        text = message,
        success = success ~= false,
    })
end

local function getHumanoid(player)
    if not player or not player.Character then
        return nil
    end

    return player.Character:FindFirstChildOfClass("Humanoid")
end

local function getRoot(player)
    if not player or not player.Character then
        return nil
    end

    return player.Character:FindFirstChild("HumanoidRootPart")
end

local function sendPlayerList(player)
    local list = {}

    for _, other in ipairs(Players:GetPlayers()) do
        table.insert(list, {
            name = other.Name,
            displayName = other.DisplayName,
            userId = other.UserId,
        })
    end

    table.sort(list, function(a, b)
        return a.name:lower() < b.name:lower()
    end)

    remote:FireClient(player, "PlayerList", list)
end

local function refreshAdmins()
    for _, player in ipairs(Players:GetPlayers()) do
        if isAdmin(player) then
            sendPlayerList(player)
        end
    end
end

local function findPlayer(query)
    if typeof(query) ~= "string" then
        return nil
    end

    query = query:lower():gsub("^%s+", ""):gsub("%s+$", "")
    if query == "" then
        return nil
    end

    for _, player in ipairs(Players:GetPlayers()) do
        if player.Name:lower() == query or player.DisplayName:lower() == query then
            return player
        end
    end

    for _, player in ipairs(Players:GetPlayers()) do
        if player.Name:lower():sub(1, #query) == query or player.DisplayName:lower():sub(1, #query) == query then
            return player
        end
    end

    return nil
end

local function ensureCharacter(player)
    local character = player.Character or player.CharacterAdded:Wait()
    local humanoid = character:FindFirstChildOfClass("Humanoid") or character:WaitForChild("Humanoid", 5)
    local root = character:FindFirstChild("HumanoidRootPart") or character:WaitForChild("HumanoidRootPart", 5)

    if not humanoid or not root then
        return nil, nil
    end

    return humanoid, root
end

remote.OnServerEvent:Connect(function(player, action, payload)
    if not isAdmin(player) then
        player:Kick("Unauthorized admin panel usage.")
        return
    end

    if action == "ListPlayers" then
        sendPlayerList(player)
        return
    end

    if typeof(payload) ~= "table" then
        payload = {}
    end

    local target = findPlayer(payload.target or "")

    if action == "Kick" then
        if not target then
            notify(player, "Target player not found.", false)
            return
        end

        local reason = tostring(payload.reason or "Removed by an admin.")
        notify(player, "Kicked " .. target.Name .. ".", true)
        target:Kick(reason)
        sendPlayerList(player)
        return
    end

    if not target then
        notify(player, "Target player not found.", false)
        return
    end

    if action == "Kill" then
        local humanoid = getHumanoid(target)
        if not humanoid then
            notify(player, "Target has no humanoid.", false)
            return
        end

        humanoid.Health = 0
        notify(player, "Killed " .. target.Name .. ".", true)
        return
    end

    if action == "Heal" then
        local humanoid = getHumanoid(target)
        if not humanoid then
            notify(player, "Target has no humanoid.", false)
            return
        end

        humanoid.Health = humanoid.MaxHealth
        notify(player, "Healed " .. target.Name .. ".", true)
        return
    end

    if action == "Respawn" then
        target:LoadCharacter()
        notify(player, "Respawned " .. target.Name .. ".", true)
        return
    end

    if action == "Freeze" or action == "Unfreeze" then
        local root = getRoot(target)
        if not root then
            notify(player, "Target has no root part.", false)
            return
        end

        root.Anchored = action == "Freeze"
        notify(player, (action == "Freeze" and "Froze " or "Unfroze ") .. target.Name .. ".", true)
        return
    end

    if action == "Bring" then
        local _, adminRoot = ensureCharacter(player)
        local _, targetRoot = ensureCharacter(target)

        if not adminRoot or not targetRoot then
            notify(player, "Could not move that player right now.", false)
            return
        end

        targetRoot.CFrame = adminRoot.CFrame * CFrame.new(4, 0, 0)
        notify(player, "Brought " .. target.Name .. ".", true)
        return
    end

    if action == "Goto" then
        local _, adminRoot = ensureCharacter(player)
        local _, targetRoot = ensureCharacter(target)

        if not adminRoot or not targetRoot then
            notify(player, "Could not teleport right now.", false)
            return
        end

        adminRoot.CFrame = targetRoot.CFrame * CFrame.new(0, 0, 4)
        notify(player, "Teleported to " .. target.Name .. ".", true)
        return
    end

    if action == "SetSpeed" then
        local humanoid = getHumanoid(target)
        if not humanoid then
            notify(player, "Target has no humanoid.", false)
            return
        end

        local speed = math.clamp(tonumber(payload.value) or 16, 0, 150)
        humanoid.WalkSpeed = speed
        notify(player, "Set " .. target.Name .. "'s speed to " .. math.floor(speed + 0.5) .. ".", true)
        return
    end

    if action == "SetJump" then
        local humanoid = getHumanoid(target)
        if not humanoid then
            notify(player, "Target has no humanoid.", false)
            return
        end

        local jumpPower = math.clamp(tonumber(payload.value) or 50, 0, 200)
        humanoid.UseJumpPower = true
        humanoid.JumpPower = jumpPower
        notify(player, "Set " .. target.Name .. "'s jump to " .. math.floor(jumpPower + 0.5) .. ".", true)
        return
    end

    notify(player, "Unknown action: " .. tostring(action), false)
end)

Players.PlayerAdded:Connect(function(player)
    if isAdmin(player) then
        player.CharacterAdded:Connect(function()
            task.delay(1, function()
                if player.Parent then
                    sendPlayerList(player)
                end
            end)
        end)
    end

    task.delay(1, refreshAdmins)
end)

Players.PlayerRemoving:Connect(function()
    task.delay(0.25, refreshAdmins)
end)
]===]

local clientSource = [===[
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local LOCAL_PLAYER = Players.LocalPlayer
local REMOTE_NAME = "__REMOTE_NAME__"
local ADMIN_USER_IDS = {__ADMIN_IDS__}

local adminLookup = {}
for _, userId in ipairs(ADMIN_USER_IDS) do
    adminLookup[userId] = true
end

if not adminLookup[LOCAL_PLAYER.UserId] then
    return
end

local remote = ReplicatedStorage:WaitForChild(REMOTE_NAME)

local gui = Instance.new("ScreenGui")
gui.Name = "NebulaAdminPanel"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.Parent = LOCAL_PLAYER:WaitForChild("PlayerGui")

local shadow = Instance.new("Frame")
shadow.Name = "Shadow"
shadow.Size = UDim2.fromOffset(770, 520)
shadow.Position = UDim2.new(0.5, -375, 0.5, -245)
shadow.BackgroundColor3 = Color3.fromRGB(5, 8, 16)
shadow.BackgroundTransparency = 0.35
shadow.BorderSizePixel = 0
shadow.Parent = gui

local shadowCorner = Instance.new("UICorner")
shadowCorner.CornerRadius = UDim.new(0, 24)
shadowCorner.Parent = shadow

local main = Instance.new("Frame")
main.Name = "Main"
main.Size = UDim2.fromOffset(750, 500)
main.Position = UDim2.new(0.5, -375, 0.5, -250)
main.BackgroundColor3 = Color3.fromRGB(15, 20, 33)
main.BorderSizePixel = 0
main.Parent = gui

local mainCorner = Instance.new("UICorner")
mainCorner.CornerRadius = UDim.new(0, 22)
mainCorner.Parent = main

local mainStroke = Instance.new("UIStroke")
mainStroke.Color = Color3.fromRGB(78, 97, 155)
mainStroke.Transparency = 0.15
mainStroke.Thickness = 1.4
mainStroke.Parent = main

local gradient = Instance.new("UIGradient")
gradient.Color = ColorSequence.new({
    ColorSequenceKeypoint.new(0, Color3.fromRGB(24, 32, 52)),
    ColorSequenceKeypoint.new(0.45, Color3.fromRGB(16, 22, 37)),
    ColorSequenceKeypoint.new(1, Color3.fromRGB(11, 15, 28)),
})
gradient.Rotation = 90
gradient.Parent = main

local header = Instance.new("Frame")
header.Name = "Header"
header.Size = UDim2.new(1, -24, 0, 64)
header.Position = UDim2.fromOffset(12, 12)
header.BackgroundColor3 = Color3.fromRGB(26, 34, 56)
header.BackgroundTransparency = 0.12
header.BorderSizePixel = 0
header.Parent = main

local headerCorner = Instance.new("UICorner")
headerCorner.CornerRadius = UDim.new(0, 18)
headerCorner.Parent = header

local headerGradient = Instance.new("UIGradient")
headerGradient.Color = ColorSequence.new({
    ColorSequenceKeypoint.new(0, Color3.fromRGB(45, 66, 110)),
    ColorSequenceKeypoint.new(1, Color3.fromRGB(24, 33, 56)),
})
headerGradient.Rotation = 0
headerGradient.Parent = header

local title = Instance.new("TextLabel")
title.Size = UDim2.new(0.5, 0, 0, 28)
title.Position = UDim2.fromOffset(18, 10)
title.BackgroundTransparency = 1
title.Font = Enum.Font.GothamBold
title.Text = "Nebula Admin Panel"
title.TextColor3 = Color3.fromRGB(240, 245, 255)
title.TextSize = 24
title.TextXAlignment = Enum.TextXAlignment.Left
title.Parent = header

local subtitle = Instance.new("TextLabel")
subtitle.Size = UDim2.new(0.7, 0, 0, 18)
subtitle.Position = UDim2.fromOffset(18, 36)
subtitle.BackgroundTransparency = 1
subtitle.Font = Enum.Font.Gotham
subtitle.Text = "Single-window tools for moderation and movement. Toggle with RightControl."
subtitle.TextColor3 = Color3.fromRGB(176, 191, 224)
subtitle.TextSize = 12
subtitle.TextXAlignment = Enum.TextXAlignment.Left
subtitle.Parent = header

local closeButton = Instance.new("TextButton")
closeButton.Size = UDim2.fromOffset(34, 34)
closeButton.Position = UDim2.new(1, -46, 0.5, -17)
closeButton.BackgroundColor3 = Color3.fromRGB(205, 74, 92)
closeButton.AutoButtonColor = false
closeButton.BorderSizePixel = 0
closeButton.Font = Enum.Font.GothamBold
closeButton.Text = "X"
closeButton.TextColor3 = Color3.fromRGB(255, 255, 255)
closeButton.TextSize = 14
closeButton.Parent = header

local closeCorner = Instance.new("UICorner")
closeCorner.CornerRadius = UDim.new(0, 12)
closeCorner.Parent = closeButton

local left = Instance.new("Frame")
left.Size = UDim2.fromOffset(348, 398)
left.Position = UDim2.fromOffset(18, 92)
left.BackgroundColor3 = Color3.fromRGB(19, 25, 40)
left.BackgroundTransparency = 0.06
left.BorderSizePixel = 0
left.Parent = main

local leftCorner = Instance.new("UICorner")
leftCorner.CornerRadius = UDim.new(0, 18)
leftCorner.Parent = left

local right = Instance.new("Frame")
right.Size = UDim2.fromOffset(348, 398)
right.Position = UDim2.fromOffset(384, 92)
right.BackgroundColor3 = Color3.fromRGB(19, 25, 40)
right.BackgroundTransparency = 0.06
right.BorderSizePixel = 0
right.Parent = main

local rightCorner = Instance.new("UICorner")
rightCorner.CornerRadius = UDim.new(0, 18)
rightCorner.Parent = right

local function makeLabel(parent, text, x, y)
    local label = Instance.new("TextLabel")
    label.BackgroundTransparency = 1
    label.Position = UDim2.fromOffset(x, y)
    label.Size = UDim2.new(1, -24, 0, 18)
    label.Font = Enum.Font.GothamSemibold
    label.Text = text
    label.TextColor3 = Color3.fromRGB(220, 229, 247)
    label.TextSize = 13
    label.TextXAlignment = Enum.TextXAlignment.Left
    label.Parent = parent
    return label
end

local function makeInput(parent, placeholder, x, y, width)
    local box = Instance.new("TextBox")
    box.Size = UDim2.fromOffset(width, 36)
    box.Position = UDim2.fromOffset(x, y)
    box.BackgroundColor3 = Color3.fromRGB(29, 37, 57)
    box.BorderSizePixel = 0
    box.PlaceholderText = placeholder
    box.Text = ""
    box.TextColor3 = Color3.fromRGB(241, 245, 255)
    box.PlaceholderColor3 = Color3.fromRGB(126, 141, 179)
    box.Font = Enum.Font.Gotham
    box.TextSize = 14
    box.ClearTextOnFocus = false
    box.Parent = parent

    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, 12)
    corner.Parent = box

    local padding = Instance.new("UIPadding")
    padding.PaddingLeft = UDim.new(0, 12)
    padding.PaddingRight = UDim.new(0, 12)
    padding.Parent = box

    return box
end

local function makeButton(parent, text, x, y, width, color)
    local button = Instance.new("TextButton")
    button.Size = UDim2.fromOffset(width, 42)
    button.Position = UDim2.fromOffset(x, y)
    button.BackgroundColor3 = color
    button.AutoButtonColor = false
    button.BorderSizePixel = 0
    button.Font = Enum.Font.GothamSemibold
    button.Text = text
    button.TextColor3 = Color3.fromRGB(250, 252, 255)
    button.TextSize = 13
    button.Parent = parent

    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, 12)
    corner.Parent = button

    button.MouseEnter:Connect(function()
        TweenService:Create(button, TweenInfo.new(0.12), {
            BackgroundColor3 = color:Lerp(Color3.new(1, 1, 1), 0.08),
        }):Play()
    end)

    button.MouseLeave:Connect(function()
        TweenService:Create(button, TweenInfo.new(0.12), {
            BackgroundColor3 = color,
        }):Play()
    end)

    return button
end

makeLabel(left, "Target Player", 16, 16)
local targetBox = makeInput(left, "Player name or display name", 16, 38, 316)

makeLabel(left, "Reason", 16, 84)
local reasonBox = makeInput(left, "Kick reason (optional)", 16, 106, 316)

makeLabel(left, "Value", 16, 152)
local valueBox = makeInput(left, "Used for speed/jump", 16, 174, 316)

local statusBar = Instance.new("TextLabel")
statusBar.Size = UDim2.new(1, -32, 0, 44)
statusBar.Position = UDim2.fromOffset(16, 334)
statusBar.BackgroundColor3 = Color3.fromRGB(24, 31, 49)
statusBar.BorderSizePixel = 0
statusBar.Font = Enum.Font.Gotham
statusBar.Text = "Ready."
statusBar.TextColor3 = Color3.fromRGB(201, 213, 240)
statusBar.TextSize = 13
statusBar.TextXAlignment = Enum.TextXAlignment.Left
statusBar.Parent = left

local statusCorner = Instance.new("UICorner")
statusCorner.CornerRadius = UDim.new(0, 12)
statusCorner.Parent = statusBar

local statusPadding = Instance.new("UIPadding")
statusPadding.PaddingLeft = UDim.new(0, 12)
statusPadding.Parent = statusBar

makeLabel(right, "Actions", 16, 16)

local kickButton = makeButton(right, "Kick", 16, 42, 100, Color3.fromRGB(204, 83, 94))
local killButton = makeButton(right, "Kill", 124, 42, 100, Color3.fromRGB(170, 69, 82))
local healButton = makeButton(right, "Heal", 232, 42, 100, Color3.fromRGB(67, 160, 123))

local respawnButton = makeButton(right, "Respawn", 16, 92, 100, Color3.fromRGB(84, 120, 206))
local freezeButton = makeButton(right, "Freeze", 124, 92, 100, Color3.fromRGB(120, 104, 194))
local unfreezeButton = makeButton(right, "Unfreeze", 232, 92, 100, Color3.fromRGB(100, 135, 210))

local bringButton = makeButton(right, "Bring", 16, 142, 100, Color3.fromRGB(219, 142, 74))
local gotoButton = makeButton(right, "Goto", 124, 142, 100, Color3.fromRGB(235, 172, 72))
local refreshButton = makeButton(right, "Refresh", 232, 142, 100, Color3.fromRGB(60, 129, 188))

local speedButton = makeButton(right, "Set Speed", 16, 192, 154, Color3.fromRGB(80, 145, 208))
local jumpButton = makeButton(right, "Set Jump", 178, 192, 154, Color3.fromRGB(93, 121, 225))

local flyButton = makeButton(right, "Fly: Off", 16, 242, 154, Color3.fromRGB(88, 164, 124))
local noclipButton = makeButton(right, "Noclip: Off", 178, 242, 154, Color3.fromRGB(121, 116, 210))

makeLabel(right, "Players", 16, 296)

local listHolder = Instance.new("Frame")
listHolder.Size = UDim2.new(1, -32, 0, 74)
listHolder.Position = UDim2.fromOffset(16, 318)
listHolder.BackgroundColor3 = Color3.fromRGB(24, 31, 49)
listHolder.BorderSizePixel = 0
listHolder.Parent = right

local listCorner = Instance.new("UICorner")
listCorner.CornerRadius = UDim.new(0, 12)
listCorner.Parent = listHolder

local list = Instance.new("ScrollingFrame")
list.Size = UDim2.new(1, -10, 1, -10)
list.Position = UDim2.fromOffset(5, 5)
list.BackgroundTransparency = 1
list.BorderSizePixel = 0
list.CanvasSize = UDim2.new()
list.ScrollBarThickness = 4
list.ScrollBarImageColor3 = Color3.fromRGB(103, 123, 181)
list.Parent = listHolder

local listLayout = Instance.new("UIListLayout")
listLayout.FillDirection = Enum.FillDirection.Horizontal
listLayout.Padding = UDim.new(0, 8)
listLayout.Parent = list

listLayout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
    list.CanvasSize = UDim2.fromOffset(listLayout.AbsoluteContentSize.X + 8, 0)
end)

local function setStatus(text, success)
    statusBar.Text = text
    statusBar.TextColor3 = success == false and Color3.fromRGB(255, 163, 163) or Color3.fromRGB(201, 213, 240)
end

local function getPayload()
    return {
        target = targetBox.Text,
        reason = reasonBox.Text,
        value = valueBox.Text,
    }
end

local function send(action)
    remote:FireServer(action, getPayload())
end

kickButton.MouseButton1Click:Connect(function()
    send("Kick")
end)

killButton.MouseButton1Click:Connect(function()
    send("Kill")
end)

healButton.MouseButton1Click:Connect(function()
    send("Heal")
end)

respawnButton.MouseButton1Click:Connect(function()
    send("Respawn")
end)

freezeButton.MouseButton1Click:Connect(function()
    send("Freeze")
end)

unfreezeButton.MouseButton1Click:Connect(function()
    send("Unfreeze")
end)

bringButton.MouseButton1Click:Connect(function()
    send("Bring")
end)

gotoButton.MouseButton1Click:Connect(function()
    send("Goto")
end)

refreshButton.MouseButton1Click:Connect(function()
    remote:FireServer("ListPlayers")
end)

speedButton.MouseButton1Click:Connect(function()
    send("SetSpeed")
end)

jumpButton.MouseButton1Click:Connect(function()
    send("SetJump")
end)

local function rebuildPlayerList(playersList)
    for _, child in ipairs(list:GetChildren()) do
        if child:IsA("TextButton") then
            child:Destroy()
        end
    end

    for _, entry in ipairs(playersList) do
        local button = Instance.new("TextButton")
        button.Size = UDim2.fromOffset(124, 30)
        button.BackgroundColor3 = Color3.fromRGB(42, 54, 84)
        button.BorderSizePixel = 0
        button.AutoButtonColor = false
        button.Font = Enum.Font.Gotham
        button.TextSize = 12
        button.TextColor3 = Color3.fromRGB(241, 245, 255)
        button.Text = entry.name
        button.Parent = list

        local corner = Instance.new("UICorner")
        corner.CornerRadius = UDim.new(0, 10)
        corner.Parent = button

        button.MouseButton1Click:Connect(function()
            targetBox.Text = entry.name
            setStatus("Selected " .. entry.name .. ".", true)
        end)
    end
end

local dragging = false
local dragStart
local startPosition

header.InputBegan:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 then
        dragging = true
        dragStart = input.Position
        startPosition = main.Position
    end
end)

header.InputEnded:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 then
        dragging = false
    end
end)

UserInputService.InputChanged:Connect(function(input)
    if dragging and input.UserInputType == Enum.UserInputType.MouseMovement then
        local delta = input.Position - dragStart
        main.Position = UDim2.new(
            startPosition.X.Scale,
            startPosition.X.Offset + delta.X,
            startPosition.Y.Scale,
            startPosition.Y.Offset + delta.Y
        )
        shadow.Position = UDim2.new(
            main.Position.X.Scale,
            main.Position.X.Offset + 5,
            main.Position.Y.Scale,
            main.Position.Y.Offset + 5
        )
    end
end)

closeButton.MouseButton1Click:Connect(function()
    gui.Enabled = false
end)

UserInputService.InputBegan:Connect(function(input, gameProcessed)
    if gameProcessed then
        return
    end

    if input.KeyCode == Enum.KeyCode.RightControl then
        gui.Enabled = not gui.Enabled
    end
end)

local flyEnabled = false
local noclipEnabled = false
local flyConnection
local noclipConnection

local movement = {
    W = false,
    A = false,
    S = false,
    D = false,
    Up = false,
    Down = false,
}

local function getCharacter()
    return LOCAL_PLAYER.Character or LOCAL_PLAYER.CharacterAdded:Wait()
end

local function setButtonState(button, enabled, onText, offText, onColor, offColor)
    button.Text = enabled and onText or offText
    button.BackgroundColor3 = enabled and onColor or offColor
end

local function stopFly()
    flyEnabled = false

    if flyConnection then
        flyConnection:Disconnect()
        flyConnection = nil
    end

    local character = LOCAL_PLAYER.Character
    if character then
        local root = character:FindFirstChild("HumanoidRootPart")
        local humanoid = character:FindFirstChildOfClass("Humanoid")

        if humanoid then
            humanoid.PlatformStand = false
        end

        if root then
            local velocity = root:FindFirstChild("AdminFlyVelocity")
            local gyro = root:FindFirstChild("AdminFlyGyro")

            if velocity then
                velocity:Destroy()
            end

            if gyro then
                gyro:Destroy()
            end
        end
    end

    setButtonState(
        flyButton,
        false,
        "Fly: On",
        "Fly: Off",
        Color3.fromRGB(64, 186, 116),
        Color3.fromRGB(88, 164, 124)
    )
    setStatus("Fly disabled.", true)
end

local function startFly()
    local character = getCharacter()
    local humanoid = character:FindFirstChildOfClass("Humanoid")
    local root = character:FindFirstChild("HumanoidRootPart")

    if not humanoid or not root then
        setStatus("Your character is not ready yet.", false)
        return
    end

    flyEnabled = true
    humanoid.PlatformStand = true

    local bodyVelocity = Instance.new("BodyVelocity")
    bodyVelocity.Name = "AdminFlyVelocity"
    bodyVelocity.MaxForce = Vector3.new(100000, 100000, 100000)
    bodyVelocity.Velocity = Vector3.zero
    bodyVelocity.Parent = root

    local bodyGyro = Instance.new("BodyGyro")
    bodyGyro.Name = "AdminFlyGyro"
    bodyGyro.MaxTorque = Vector3.new(100000, 100000, 100000)
    bodyGyro.P = 9000
    bodyGyro.CFrame = workspace.CurrentCamera.CFrame
    bodyGyro.Parent = root

    flyConnection = RunService.RenderStepped:Connect(function()
        if not flyEnabled or not root.Parent then
            stopFly()
            return
        end

        local camera = workspace.CurrentCamera
        local direction = Vector3.zero
        local speed = 70

        if movement.W then
            direction += camera.CFrame.LookVector
        end
        if movement.S then
            direction -= camera.CFrame.LookVector
        end
        if movement.A then
            direction -= camera.CFrame.RightVector
        end
        if movement.D then
            direction += camera.CFrame.RightVector
        end
        if movement.Up then
            direction += Vector3.new(0, 1, 0)
        end
        if movement.Down then
            direction -= Vector3.new(0, 1, 0)
        end

        if direction.Magnitude > 0 then
            direction = direction.Unit
        end

        bodyVelocity.Velocity = direction * speed
        bodyGyro.CFrame = camera.CFrame
    end)

    setButtonState(
        flyButton,
        true,
        "Fly: On",
        "Fly: Off",
        Color3.fromRGB(64, 186, 116),
        Color3.fromRGB(88, 164, 124)
    )
    setStatus("Fly enabled. Use WASD, Space, and LeftShift.", true)
end

local function stopNoclip()
    noclipEnabled = false

    if noclipConnection then
        noclipConnection:Disconnect()
        noclipConnection = nil
    end

    setButtonState(
        noclipButton,
        false,
        "Noclip: On",
        "Noclip: Off",
        Color3.fromRGB(149, 109, 228),
        Color3.fromRGB(121, 116, 210)
    )
    setStatus("Noclip disabled.", true)
end

local function startNoclip()
    noclipEnabled = true
    noclipConnection = RunService.Stepped:Connect(function()
        local character = LOCAL_PLAYER.Character
        if not character then
            return
        end

        for _, part in ipairs(character:GetDescendants()) do
            if part:IsA("BasePart") then
                part.CanCollide = false
            end
        end
    end)

    setButtonState(
        noclipButton,
        true,
        "Noclip: On",
        "Noclip: Off",
        Color3.fromRGB(149, 109, 228),
        Color3.fromRGB(121, 116, 210)
    )
    setStatus("Noclip enabled.", true)
end

flyButton.MouseButton1Click:Connect(function()
    if flyEnabled then
        stopFly()
    else
        startFly()
    end
end)

noclipButton.MouseButton1Click:Connect(function()
    if noclipEnabled then
        stopNoclip()
    else
        startNoclip()
    end
end)

UserInputService.InputBegan:Connect(function(input, gameProcessed)
    if gameProcessed then
        return
    end

    if input.KeyCode == Enum.KeyCode.W then
        movement.W = true
    elseif input.KeyCode == Enum.KeyCode.A then
        movement.A = true
    elseif input.KeyCode == Enum.KeyCode.S then
        movement.S = true
    elseif input.KeyCode == Enum.KeyCode.D then
        movement.D = true
    elseif input.KeyCode == Enum.KeyCode.Space then
        movement.Up = true
    elseif input.KeyCode == Enum.KeyCode.LeftShift then
        movement.Down = true
    end
end)

UserInputService.InputEnded:Connect(function(input)
    if input.KeyCode == Enum.KeyCode.W then
        movement.W = false
    elseif input.KeyCode == Enum.KeyCode.A then
        movement.A = false
    elseif input.KeyCode == Enum.KeyCode.S then
        movement.S = false
    elseif input.KeyCode == Enum.KeyCode.D then
        movement.D = false
    elseif input.KeyCode == Enum.KeyCode.Space then
        movement.Up = false
    elseif input.KeyCode == Enum.KeyCode.LeftShift then
        movement.Down = false
    end
end)

LOCAL_PLAYER.CharacterAdded:Connect(function()
    task.delay(1, function()
        if flyEnabled then
            stopFly()
            startFly()
        end
        if noclipEnabled then
            stopNoclip()
            startNoclip()
        end
    end)
end)

remote.OnClientEvent:Connect(function(kind, data)
    if kind == "Notify" then
        setStatus(data.text or "Done.", data.success)
    elseif kind == "PlayerList" then
        rebuildPlayerList(data or {})
    end
end)

remote:FireServer("ListPlayers")
setStatus("Panel loaded. Pick a player to begin.", true)
]===]

serverSource = serverSource:gsub("__ADMIN_IDS__", idsLiteral):gsub("__REMOTE_NAME__", REMOTE_NAME)
clientSource = clientSource:gsub("__ADMIN_IDS__", idsLiteral):gsub("__REMOTE_NAME__", REMOTE_NAME)

local existingRemote = ReplicatedStorage:FindFirstChild(REMOTE_NAME)
if existingRemote then
    existingRemote:Destroy()
end

local existingServer = ServerScriptService:FindFirstChild(SERVER_SCRIPT_NAME)
if existingServer then
    existingServer:Destroy()
end

local starterPlayerScripts = StarterPlayer:WaitForChild("StarterPlayerScripts")
local existingClient = starterPlayerScripts:FindFirstChild(CLIENT_SCRIPT_NAME)
if existingClient then
    existingClient:Destroy()
end

local remote = Instance.new("RemoteEvent")
remote.Name = REMOTE_NAME
remote.Parent = ReplicatedStorage

local serverScript = Instance.new("Script")
serverScript.Name = SERVER_SCRIPT_NAME
serverScript.Source = serverSource
serverScript.Parent = ServerScriptService

local clientScript = Instance.new("LocalScript")
clientScript.Name = CLIENT_SCRIPT_NAME
clientScript.Source = clientSource
clientScript.Parent = starterPlayerScripts

print("Nebula Admin Panel installed.")
print("Remember to replace the placeholder user IDs in ADMIN_USER_IDS before publishing.")
