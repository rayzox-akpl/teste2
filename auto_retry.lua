-- ==========================================================
--  AUTO RETRY  --  clique le bouton de fin, une seule fois par cycle.
--
--  Il n'agit QUE si _G.RunState.phase vaut "fin", c'est-a-dire quand le
--  RetryBtn est reellement affiche. Des qu'il a commence, il passe la
--  phase a "relance" et ne reclique plus : la machine a etats du loader la
--  remettra a "fin" si le bouton est toujours la au bout de 25 s, ou a
--  "donjon" quand les mobs de la nouvelle run arrivent.
--
--  Role unique : cliquer Retry. Il ne relance pas la run et n'envoie pas
--  H. C'est auto_start.lua qui appuiera sur Commencer juste apres, et
--  kronax_new.lua qui gere l'arme et le combat.
--
--  Methode reprise de h_kronax.lua : 20 tentatives, une par seconde,
--  Activated ET MouseButton1Click, plus un vrai clic souris.
-- ==========================================================

if _G.AutoRetryRunning then
    print("[retry] deja actif")
    return
end
_G.AutoRetryRunning = true

local CONFIG = {
    ATTEMPTS      = 20,    -- comme h_kronax
    ATTEMPT_GAP   = 1.0,   -- exactement une par seconde
    FIRST_DELAY   = 1.0,   -- laisse l'ecran de fin s'afficher

    SCAN_PERIOD   = 0.5,
}

local Players = game:GetService("Players")
local GuiService = game:GetService("GuiService")
local VIM = game:GetService("VirtualInputManager")
local player = Players.LocalPlayer

local running = true
local busy = false
local cycles = 0

local function say(format, ...)
    local ok, text = pcall(string.format, format, ...)
    print("[retry] " .. (ok and text or tostring(format)))
end

local function state()
    return _G.RunState
end

--  Meme recherche que h_kronax : chemin exact, puis repli recursif.
local function findRetryBtn()
    local S = state()
    if S and S.retryButton then return S.retryButton() end
    local gui = player:FindFirstChild("PlayerGui")
    if not gui then return nil end
    local complete = gui:FindFirstChild("DungeonComplete")
    if complete then
        local main = complete:FindFirstChild("Main")
        local buttons = main and main:FindFirstChild("EndGameButtons")
        local button = buttons and buttons:FindFirstChild("RetryBtn")
        if button then return button end
    end
    return gui:FindFirstChild("RetryBtn", true)
end

local function clickRetry(button)
    pcall(function()
        local inset = GuiService:GetGuiInset()
        local position, size = button.AbsolutePosition, button.AbsoluteSize
        local x = position.X + size.X / 2
        local y = position.Y + size.Y / 2 + inset.Y
        VIM:SendMouseMoveEvent(x, y, game)
        task.wait(0.05)
        VIM:SendMouseButtonEvent(x, y, 0, true, game, 0)
        task.wait(0.05)
        VIM:SendMouseButtonEvent(x, y, 0, false, game, 0)
    end)
    if typeof(getconnections) == "function" then
        for _, signal in ipairs({button.Activated, button.MouseButton1Click}) do
            pcall(function()
                for _, connection in ipairs(getconnections(signal)) do
                    connection:Fire()
                end
            end)
        end
    end
    if typeof(firesignal) == "function" then
        pcall(firesignal, button.Activated)
        pcall(firesignal, button.MouseButton1Click)
    end
end

--====================================================
--  Un cycle de relance
--====================================================
local function retryCycle()
    if busy then return end
    busy = true
    cycles = cycles + 1

    local S = state()
    if S then S.set("relance", "auto_retry prend la main") end
    say("cycle %d : fin de run detectee", cycles)
    task.wait(CONFIG.FIRST_DELAY)

    for attempt = 1, CONFIG.ATTEMPTS do
        if not running then break end
        local button = findRetryBtn()
        if not button then
            say("  tentative %d : RetryBtn absent", attempt)
        else
            clickRetry(button)
            if attempt <= 3 then
                say("  tentative %d : clic envoye", attempt)
            end
        end
        -- Le bouton a disparu : c'est gagne.
        if not findRetryBtn() then
            say("  RetryBtn parti apres %d tentative(s)", attempt)
            break
        end
        if attempt < CONFIG.ATTEMPTS then task.wait(CONFIG.ATTEMPT_GAP) end
    end

    -- On s'arrete la. auto_start prendra le relais des que le bouton
    -- Commencer apparaitra, et kronax enverra H de son cote.
    busy = false
end

--====================================================
--  Boucle
--====================================================
task.spawn(function()
    while running do
        task.wait(CONFIG.SCAN_PERIOD)
        local S = state()
        if not S then
            -- Sans le loader : on se contente du front montant du bouton.
            if findRetryBtn() and not busy then
                task.spawn(retryCycle)
            end
        elseif S.phase == "fin" and not busy then
            task.spawn(retryCycle)
        end
    end
end)

_G.StopAutoRetry = function(reason)
    running = false
    _G.AutoRetryRunning = false
    say("arret : %s", tostring(reason or "manuel"))
end

say("pret. Clique uniquement depuis l'etat \"fin\".")
