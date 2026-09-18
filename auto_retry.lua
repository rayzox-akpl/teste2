-- ==========================================================
--  AUTO RETRY  --  relance du donjon, UNIQUEMENT quand le boss est mort.
--
--  C'est le declencheur de h_kronax.lua : retryDungeon20Times() y est
--  appele sur bossDead, pas sur l'apparition de RetryBtn. Ma version
--  precedente surveillait le bouton, or il existe dans l'interface meme
--  cache : la relance partait en plein combat et cassait la run.
--
--  Ici : on suit le boss, et on n'agit qu'a la transition vivant -> mort.
--  Ensuite 20 clics a une par seconde, StartDungeon, puis H.
-- ==========================================================

--  Remplacement, pas refus. Le jeton garantit qu'une ancienne boucle
--  encore vivante s'arrete d'elle-meme au tour suivant, au lieu de
--  cliquer en meme temps que la nouvelle.
if typeof(_G.StopAutoRetry) == "function" then
    pcall(_G.StopAutoRetry)
    task.wait(0.1)
end

_G.AutoRetryToken = (_G.AutoRetryToken or 0) + 1
local MON_JETON = _G.AutoRetryToken
_G.AutoRetryRunning = true

local function actif()
    return _G.AutoRetryRunning and _G.AutoRetryToken == MON_JETON
end

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local GuiService = game:GetService("GuiService")
local VirtualInputManager = game:GetService("VirtualInputManager")

repeat task.wait() until Players.LocalPlayer
local player = Players.LocalPlayer

local RETRY_ATTEMPTS = 20
local RETRY_INTERVAL = 1
local WATCH_PERIOD   = 0.5

--  Reconnaissance du boss. Un nom qui correspond suffit; sinon on accepte
--  tout Humanoid tres resistant, ce qui couvre les boss non listes.
local BOSS_NAMES      = {"kronax", "viltron"}
local BOSS_MIN_HEALTH = 20000000
--  Au-dela, c'est une valeur sentinelle (mob a ne pas toucher), pas un boss.
local SENTINEL_HEALTH = 1e11

--====================================================
-- RECHERCHE DU BOSS
--====================================================
local function isCloneContainer(model)
    -- Le jeu depose une copie du boss dans Workspace.Effects a sa mort.
    -- Si on la prenait pour le boss, on ne verrait jamais sa mort.
    local ancestor = model.Parent
    while ancestor and ancestor ~= workspace do
        if ancestor.Name == "Effects" or ancestor.Name == "Debris" then
            return true
        end
        ancestor = ancestor.Parent
    end
    return false
end

local function looksLikeBoss(model, humanoid)
    if humanoid.MaxHealth >= SENTINEL_HEALTH then return false end
    local label = humanoid.DisplayName
    if label == nil or label:match("^%s*$") then label = model.Name end
    label = label:lower()
    for _, word in ipairs(BOSS_NAMES) do
        if label:find(word, 1, true) then return true end
    end
    if model:GetAttribute("Boss") == true then return true end
    if model:GetAttribute("Base") == "Boss" then return true end
    return humanoid.MaxHealth >= BOSS_MIN_HEALTH
end

local function findBoss()
    local containers = {workspace:FindFirstChild("Mobs"), workspace}
    for _, container in ipairs(containers) do
        if container then
            for _, model in ipairs(container:GetChildren()) do
                if model:IsA("Model") and not Players:GetPlayerFromCharacter(model)
                    and not isCloneContainer(model) then
                    local humanoid = model:FindFirstChildOfClass("Humanoid")
                    if humanoid and looksLikeBoss(model, humanoid) then
                        return model, humanoid
                    end
                end
            end
        end
    end
    return nil
end

--====================================================
-- BOUTON DE FIN
--====================================================
local function visible(object)
    if not object:IsA("GuiObject") then return false end
    if not object.Visible then return false end
    local ancestor = object.Parent
    while ancestor do
        if ancestor:IsA("ScreenGui") then return ancestor.Enabled end
        if ancestor:IsA("GuiObject") and not ancestor.Visible then
            return false
        end
        ancestor = ancestor.Parent
    end
    return false
end

local function findRetryBtn()
    local gui = player:FindFirstChild("PlayerGui")
    if not gui then return nil end

    local dungeonComplete = gui:FindFirstChild("DungeonComplete")
    if dungeonComplete then
        local main = dungeonComplete:FindFirstChild("Main")
        local endButtons = main and main:FindFirstChild("EndGameButtons")
        local btn = endButtons and endButtons:FindFirstChild("RetryBtn")
        if btn then return btn end
    end

    return gui:FindFirstChild("RetryBtn", true)
end

local function clickRetry(btn)
    local inset = GuiService:GetGuiInset()
    local pos = btn.AbsolutePosition
    local size = btn.AbsoluteSize
    local x = pos.X + size.X / 2
    local y = pos.Y + size.Y / 2 + inset.Y

    VirtualInputManager:SendMouseMoveEvent(x, y, game)
    task.wait(0.05)
    VirtualInputManager:SendMouseButtonEvent(x, y, 0, true, game, 0)
    task.wait(0.05)
    VirtualInputManager:SendMouseButtonEvent(x, y, 0, false, game, 0)

    pcall(function()
        for _, conn in ipairs(getconnections(btn.Activated)) do
            conn:Fire()
        end
    end)
    pcall(function()
        for _, conn in ipairs(getconnections(btn.MouseButton1Click)) do
            conn:Fire()
        end
    end)
    pcall(function() firesignal(btn.Activated) end)
    pcall(function() firesignal(btn.MouseButton1Click) end)
end

local function pressHOnce()
    pcall(function()
        VirtualInputManager:SendKeyEvent(true, Enum.KeyCode.H, false, game)
        task.wait(0.05)
        VirtualInputManager:SendKeyEvent(false, Enum.KeyCode.H, false, game)
    end)
end

--====================================================
-- SEQUENCE DE RELANCE
--====================================================
local retryRunning = false

local function retryDungeon20Times()
    if retryRunning then return end
    retryRunning = true

    print("[RETRY] BOSS MORT -> 20 tentatives, 1 par seconde")

    for attempt = 1, RETRY_ATTEMPTS do
        if not actif() then
            print("[RETRY] instance remplacee, sequence abandonnee")
            retryRunning = false
            return
        end
        local retryBtn = findRetryBtn()

        -- On ne clique que si le bouton est reellement affiche : il existe
        -- dans l'interface en permanence, meme pendant le combat.
        if retryBtn and visible(retryBtn) then
            print("[RETRY] Tentative " .. attempt .. "/" .. RETRY_ATTEMPTS)
            clickRetry(retryBtn)
        else
            print("[RETRY] Tentative " .. attempt .. "/" .. RETRY_ATTEMPTS
                .. " : RetryBtn pas encore affiche")
        end

        if attempt < RETRY_ATTEMPTS then
            task.wait(RETRY_INTERVAL)
        end
    end

    task.wait(0.5)

    pcall(function()
        ReplicatedStorage:WaitForChild("ReplicatedStorage")
            :WaitForChild("Packages")
            :WaitForChild("Knit")
            :WaitForChild("Services")
            :WaitForChild("DungeonService")
            :WaitForChild("RF")
            :WaitForChild("StartDungeon")
            :InvokeServer()
    end)
    print("[RETRY] StartDungeon appele")

    task.wait(3)
    task.wait(0.5)
    pressHOnce()
    print("[RETRY] H appuye")

    retryRunning = false
end

--====================================================
-- SURVEILLANCE DU BOSS
-- On ne s'arme qu'apres avoir vu le boss VIVANT. La relance part a la
-- transition vivant -> mort, une seule fois, puis il faut revoir un boss
-- vivant pour se rearmer.
--====================================================
task.spawn(function()
    local armed = false
    local lastName = nil

    while actif() do
        task.wait(WATCH_PERIOD)

        local ok = pcall(function()
            local boss, humanoid = findBoss()

            if boss and humanoid and humanoid.Health > 0 then
                if not armed then
                    armed = true
                    lastName = boss.Name
                    print("[RETRY] boss en vue : " .. tostring(lastName)
                        .. " (" .. math.floor(humanoid.MaxHealth) .. " PV)"
                        .. " -- surveillance armee")
                end

            elseif armed then
                -- Plus de boss vivant alors qu'on en avait un : il est mort.
                armed = false
                print("[RETRY] " .. tostring(lastName) .. " n'est plus la")
                retryDungeon20Times()
            end
        end)
        if not ok then task.wait(1) end
    end
end)

_G.StopAutoRetry = function()
    if _G.AutoRetryToken == MON_JETON then
        _G.AutoRetryRunning = false
    end
    print("[RETRY] arret (jeton " .. MON_JETON .. ")")
end

print("[RETRY] pret, jeton " .. MON_JETON
    .. " : relance seulement a la mort du boss")
