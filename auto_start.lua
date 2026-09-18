-- ==========================================================
--  AUTO START  --  appuie sur le bouton "Commencer" au debut du donjon.
--
--  Role unique : cliquer ce bouton. Il ne lance rien d'autre, ne gere ni
--  le combat ni la fin de run. C'est kronax_new.lua qui s'occupe du reste,
--  et auto_retry.lua qui clique Retry a la fin.
--
--  Il n'agit QUE si _G.RunState.phase vaut "attente", c'est-a-dire quand
--  le bouton est reellement affiche. Des qu'il a clique il passe la phase
--  a "demarrage" et se tait : impossible qu'il se redeclenche avant le
--  prochain donjon.
-- ==========================================================

if _G.AutoStartRunning then
    print("[start] deja actif")
    return
end
_G.AutoStartRunning = true

local CONFIG = {
    ATTEMPTS     = 20,     -- comme le retry de h_kronax
    ATTEMPT_GAP  = 1.0,    -- une tentative par seconde
    FIRST_DELAY  = 1.0,    -- laisse le bouton finir son animation

    --  Noms possibles du bouton. Le journal dira lequel a repondu, et
    --  listera les autres boutons visibles si aucun ne correspond.
    NAMES = {"StartBtn", "StartButton", "Start", "BeginBtn", "Begin",
        "PlayBtn", "Play", "ReadyBtn", "Ready", "Commencer"},

    --  Repli, uniquement si aucun bouton n'est trouve apres toutes les
    --  tentatives. C'est l'appel que fait h_kronax.lua ligne 775.
    FALLBACK_REMOTE = true,
    REMOTE_PATH = "ReplicatedStorage.Packages.Knit.Services.DungeonService.RF.StartDungeon",

    SCAN_PERIOD  = 0.5,
    LIST_BUTTONS = true,   -- inventaire si le bouton reste introuvable
}

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local GuiService = game:GetService("GuiService")
local VIM = game:GetService("VirtualInputManager")
local player = Players.LocalPlayer

local running, busy, cycles = true, false, 0

local function say(format, ...)
    local ok, text = pcall(string.format, format, ...)
    print("[start] " .. (ok and text or tostring(format)))
end

local function state() return _G.RunState end

local function findStartBtn()
    local S = state()
    if S and S.startButton then return S.startButton() end
    local gui = player:FindFirstChild("PlayerGui")
    if not gui then return nil end
    for _, name in ipairs(CONFIG.NAMES) do
        local found = gui:FindFirstChild(name, true)
        if found and found:IsA("GuiButton") and found.Visible then
            return found, name
        end
    end
    return nil
end

--  Meme methode que h_kronax pour le retry : signaux d'abord, vrai clic
--  souris ensuite. Certains boutons ne branchent que Activated.
local function clickButton(button)
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

local function callRemote()
    local node = ReplicatedStorage
    for part in string.gmatch(CONFIG.REMOTE_PATH, "[^%.]+") do
        node = node and node:FindFirstChild(part)
        if not node then return false, "chemin introuvable a " .. part end
    end
    local ok = pcall(function() return node:InvokeServer() end)
    return ok, ok and "StartDungeon envoye" or "InvokeServer refuse"
end

--  Quand le bouton reste introuvable, on liste ce qui est affiche : c'est
--  la seule facon de trouver son vrai nom sans deviner.
local function listButtons()
    if not CONFIG.LIST_BUTTONS then return end
    local gui = player:FindFirstChild("PlayerGui")
    if not gui then return end
    say("boutons visibles a l'ecran :")
    local shown = 0
    for _, descendant in ipairs(gui:GetDescendants()) do
        if descendant:IsA("GuiButton") and descendant.Visible then
            shown = shown + 1
            if shown <= 25 then
                local text = descendant:IsA("TextButton")
                    and descendant.Text or "(image)"
                say("    %-20s \"%s\"  %s", descendant.Name, text,
                    descendant:GetFullName())
            end
        end
    end
    if shown == 0 then say("    aucun") end
end

--====================================================
--  Un cycle : on annonce "demarrage" AVANT de cliquer, ce qui interdit
--  tout second cycle en parallele.
--====================================================
local function startCycle()
    if busy then return end
    busy = true
    cycles = cycles + 1

    local S = state()
    if S then S.set("demarrage", "auto_start clique Commencer") end
    say("cycle %d : bouton Commencer detecte", cycles)
    task.wait(CONFIG.FIRST_DELAY)

    local clicked = false
    for attempt = 1, CONFIG.ATTEMPTS do
        if not running then break end
        if S and S.inDungeon() then
            say("donjon demarre apres %d tentative(s)", attempt - 1)
            clicked = true
            break
        end

        local button, name = findStartBtn()
        if button then
            clickButton(button)
            clicked = true
            if attempt <= 3 then
                say("  tentative %d : clic sur %s", attempt, tostring(name))
            end
            if not findStartBtn() then
                say("  bouton parti apres %d tentative(s)", attempt)
                break
            end
        else
            if attempt == 1 then
                say("  bouton introuvable parmi : %s",
                    table.concat(CONFIG.NAMES, ", "))
                listButtons()
            end
        end

        if attempt < CONFIG.ATTEMPTS then task.wait(CONFIG.ATTEMPT_GAP) end
    end

    if not clicked and CONFIG.FALLBACK_REMOTE then
        local _, how = callRemote()
        say("aucun bouton clique -- repli sur le remote : %s", how)
    end

    busy = false
end

task.spawn(function()
    while running do
        task.wait(CONFIG.SCAN_PERIOD)
        local S = state()
        if not S then
            if findStartBtn() and not busy then task.spawn(startCycle) end
        elseif S.phase == "attente" and not busy then
            task.spawn(startCycle)
        end
    end
end)

_G.StopAutoStart = function(reason)
    running = false
    _G.AutoStartRunning = false
    say("arret : %s", tostring(reason or "manuel"))
end

say("pret. Clique Commencer uniquement depuis l'etat \"attente\".")
