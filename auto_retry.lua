-- ==========================================================
--  AUTO RETRY  --  relance du donjon a la fin.
--  Copie exacte du bloc de h_kronax.lua : 20 tentatives a une
--  par seconde sur RetryBtn, puis StartDungeon, puis H.
--  Se declenche des que le bouton apparait, une seule fois par
--  fin de run.
-- ==========================================================

if _G.AutoRetryRunning then
    print("[RETRY] deja actif")
    return
end
_G.AutoRetryRunning = true

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local GuiService = game:GetService("GuiService")
local VirtualInputManager = game:GetService("VirtualInputManager")

repeat task.wait() until Players.LocalPlayer
local player = Players.LocalPlayer

local RETRY_ATTEMPTS = 20
local RETRY_INTERVAL = 1

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

local retryRunning = false

local function retryDungeon20Times()
    if retryRunning then return end
    retryRunning = true

    print("[RETRY] FIN DE RUN -> 20 tentatives, 1 par seconde")

    for attempt = 1, RETRY_ATTEMPTS do
        local retryBtn = findRetryBtn()

        if retryBtn then
            print("[RETRY] Tentative " .. attempt .. "/" .. RETRY_ATTEMPTS)
            clickRetry(retryBtn)
        else
            print("[RETRY] Tentative " .. attempt .. "/" .. RETRY_ATTEMPTS
                .. " : RetryBtn absent")
        end

        if attempt < RETRY_ATTEMPTS then
            task.wait(RETRY_INTERVAL)
        end
    end

    -- Apres les 20 tentatives, on lance explicitement la nouvelle run.
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

    -- H une seule fois quand la nouvelle run a commence.
    task.wait(0.5)
    pressHOnce()
    print("[RETRY] H appuye")

    retryRunning = false
end

--====================================================
-- SURVEILLANCE : front montant du bouton
-- Une seule relance par fin de run, jamais deux en parallele.
--====================================================
task.spawn(function()
    local wasVisible = false
    while _G.AutoRetryRunning do
        task.wait(1)
        local visible = findRetryBtn() ~= nil
        if visible and not wasVisible then
            retryDungeon20Times()
        end
        wasVisible = visible
    end
end)

_G.StopAutoRetry = function()
    _G.AutoRetryRunning = false
    print("[RETRY] arret")
end

print("[RETRY] pret, surveillance de RetryBtn")
