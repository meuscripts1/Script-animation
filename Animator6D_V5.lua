--//====================================================\\--
--||          Animator6D Pro V5 - R6 Respawn Fix       ||--
--||       Mantém o Animator funcionando após morte    ||--
--\\====================================================//--

if getgenv().Animator6DLoadedPro then
    return
end

getgenv().Animator6DLoadedPro = true

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer

--====================================================--
-- CHARACTER ATUAL
--====================================================--

local character = player.Character or player.CharacterAdded:Wait()
local hum = character:WaitForChild("Humanoid")

--====================================================--
-- CACHE
--====================================================--

local LocalAssetCache = {}
local fullModel = nil

pcall(function()
    fullModel = game:GetObjects("rbxassetid://107495486817639")[1]

    if fullModel then
        fullModel.Parent = workspace
    end
end)

local function LoadLocalAsset(id)
    id = tostring(id):gsub("^rbxassetid://", "")

    if LocalAssetCache[id] then
        return LocalAssetCache[id]
    end

    local found = fullModel and fullModel:FindFirstChild(id, true)

    if found then
        LocalAssetCache[id] = found
        return found
    end

    local ok, obj = pcall(function()
        return game:GetObjects("rbxassetid://" .. id)[1]
    end)

    if ok and obj then
        LocalAssetCache[id] = obj
        return obj
    end

    warn("[Animator6D] Falha ao carregar animação:", id)

    return nil
end

--====================================================--
-- R6 MAP
--====================================================--

local R6Map = {
    ["Head"] = "Neck",
    ["Torso"] = "RootJoint",
    ["Right Arm"] = "Right Shoulder",
    ["Left Arm"] = "Left Shoulder",
    ["Right Leg"] = "Right Hip",
    ["Left Leg"] = "Left Hip"
}

--====================================================--
-- KEYFRAME PARSER
--====================================================--

local function ConvertToTable(kfs)

    if not (
        kfs
        and typeof(kfs) == "Instance"
        and kfs:IsA("KeyframeSequence")
    ) then

        if typeof(kfs) == "Instance" then

            for _, obj in ipairs(kfs:GetDescendants()) do

                if obj:IsA("KeyframeSequence") then
                    kfs = obj
                    break
                end

            end

        end

    end

    assert(
        kfs
        and typeof(kfs) == "Instance"
        and kfs:IsA("KeyframeSequence"),
        "Expected KeyframeSequence"
    )

    local seq = {}

    for _, frame in ipairs(kfs:GetKeyframes()) do

        local entry = {
            Time = frame.Time,
            Data = {}
        }

        for _, pose in ipairs(frame:GetDescendants()) do

            if pose:IsA("Pose") and pose.Weight > 0 then

                entry.Data[pose.Name] = {
                    CFrame = pose.CFrame
                }

            end

        end

        table.insert(seq, entry)

    end

    table.sort(seq, function(a, b)
        return a.Time < b.Time
    end)

    return seq, kfs.Loop
end

--====================================================--
-- MOTOR MAP
--====================================================--

local function BuildMotorMap(rig)

    local map = {}
    local lower = {}

    for _, m in ipairs(rig:GetDescendants()) do

        if m:IsA("Motor6D") then

            map[m.Name] = m
            lower[string.lower(m.Name)] = m

        end

    end

    return map, lower
end

local function FindMotor(poseName, map, lower)

    local match = R6Map[poseName] or poseName

    return map[match]
        or lower[string.lower(match)]
end

--====================================================--
-- ANIM PLAYER
--====================================================--

local AnimPlayer = {}
AnimPlayer.__index = AnimPlayer

function AnimPlayer.new(rig, kfs)

    local self = setmetatable({}, AnimPlayer)

    self.rig = rig
    self.seq, self.looped = ConvertToTable(kfs)

    self.map, self.lower = BuildMotorMap(rig)

    self.time = 0
    self.playing = false
    self.speed = 1
    self.conn = nil

    self.length = 0

    if self.seq and #self.seq > 0 then
        self.length = self.seq[#self.seq].Time
    end

    self.savedC0 = {}

    for _, m in pairs(self.map) do
        self.savedC0[m] = m.C0
    end

    return self
end

function AnimPlayer:Play(speed, loop)

    if self.playing then
        return
    end

    self.playing = true
    self.speed = speed or 1
    self.looped = (loop == nil) and true or loop
    self.time = 0

    self.conn = RunService.Heartbeat:Connect(function(dt)

        if not self.playing then
            return
        end

        -- Se o personagem morreu/desapareceu,
        -- para esse Animator antigo.
        if not self.rig
            or not self.rig.Parent
            or not self.rig:FindFirstChild("Humanoid") then

            self:Stop(true)
            return
        end

        self.time += dt * self.speed

        if self.length > 0 and self.time > self.length then

            if self.looped then
                self.time = self.time % self.length
            else
                self:Stop(true)
                return
            end

        end

        if not self.seq or #self.seq == 0 then
            return
        end

        local prev = self.seq[1]

        for i = 1, #self.seq do

            if self.seq[i].Time <= self.time then
                prev = self.seq[i]
            else
                break
            end

        end

        for joint, data in pairs(prev.Data) do

            local motor = FindMotor(
                joint,
                self.map,
                self.lower
            )

            if motor then

                pcall(function()

                    if motor.Parent then

                        motor.C0 =
                            self.savedC0[motor]
                            * data.CFrame

                    end

                end)

            end

        end

    end)

end

function AnimPlayer:Stop(restore)

    self.playing = false

    if self.conn then
        self.conn:Disconnect()
        self.conn = nil
    end

    if restore then

        for motor, origC0 in pairs(self.savedC0) do

            pcall(function()

                if motor.Parent then
                    motor.C0 = origC0
                end

            end)

        end

    else

        for _, m in pairs(self.map) do

            pcall(function()

                if m.Parent then
                    m.Transform = CFrame.new()
                end

            end)

        end

    end

end

--====================================================--
-- DEFAULT ANIMATIONS
--====================================================--

local function disableDefaultAnimations(char, humanoid)

    if not char or not humanoid then
        return
    end

    pcall(function()

        for _, track in ipairs(
            humanoid:GetPlayingAnimationTracks()
        ) do

            track:Stop(0)

        end

    end)

    local animScript = char:FindFirstChild("Animate")

    if animScript then
        animScript.Disabled = true
    end

    local animator =
        humanoid:FindFirstChildOfClass("Animator")

    if animator then

        pcall(function()
            animator:Destroy()
        end)

    end

end

--====================================================--
-- STOP ANIMATOR ATUAL
--====================================================--

local function StopCurrentAnimator()

    if getgenv().currentAnimator6D then

        pcall(function()
            getgenv().currentAnimator6D:Stop(true)
        end)

        getgenv().currentAnimator6D = nil

    end

end

--====================================================--
-- CHARACTER RESPAWN
--====================================================--

player.CharacterAdded:Connect(function(newCharacter)

    -- Primeiro mata o Animator antigo
    StopCurrentAnimator()

    -- Atualiza referências
    character = newCharacter

    hum = newCharacter:WaitForChild("Humanoid")

    -- Pequena espera para o R6 terminar de montar
    task.wait(0.15)

    -- Garante que o personagem novo também tenha
    -- as animações padrão desativadas.
    disableDefaultAnimations(
        character,
        hum
    )

    warn("[Animator6D] Novo Character detectado. Animator rearmado.")

end)

--====================================================--
-- INTERFACE GLOBAL
--====================================================--

getgenv().Animator6D = function(idOrInstance, speed, looped)

    -- SEMPRE pega o Character atual
    local currentCharacter =
        player.Character

    if not currentCharacter then
        return
    end

    local currentHumanoid =
        currentCharacter:FindFirstChildOfClass("Humanoid")

    if not currentHumanoid then
        return
    end

    -- Atualiza as referências
    character = currentCharacter
    hum = currentHumanoid

    local kfs

    if typeof(idOrInstance) == "Instance" then

        if idOrInstance:IsA("KeyframeSequence") then
            kfs = idOrInstance
        else
            kfs =
                idOrInstance:FindFirstChildOfClass(
                    "KeyframeSequence"
                )
        end

    else

        local asset =
            LoadLocalAsset(idOrInstance)

        if asset then

            kfs =
                asset:FindFirstChildOfClass(
                    "KeyframeSequence"
                )
                or asset

        end

    end

    if not kfs then

        warn(
            "[Animator6D] Não conseguiu carregar:",
            idOrInstance
        )

        return
    end

    -- Para a animação anterior
    StopCurrentAnimator()

    -- Desliga as animações padrão
    disableDefaultAnimations(
        currentCharacter,
        currentHumanoid
    )

    -- Cria Animator novo usando o Character ATUAL
    local anim =
        AnimPlayer.new(
            currentCharacter,
            kfs
        )

    getgenv().currentAnimator6D = anim

    anim:Play(
        speed or 1,
        looped
    )

end

--====================================================--
-- STOP GLOBAL
--====================================================--

getgenv().Animator6DStop = function()

    StopCurrentAnimator()

end

--====================================================--
-- NOTIFY
--====================================================--

warn("[Animator6D Pro V5] Respawn system loaded")

pcall(function()

    game:GetService("StarterGui"):SetCore(
        "SendNotification",
        {
            Title = "Animator6D Pro V5",
            Text = "Respawn Fix carregado!",
            Duration = 5
        }
    )

end)
