-- ==========================================================
--  CHARGEUR  --  c'est le SEUL lien a coller dans Solara.
--
--  Il charge les trois scripts dans l'ordre et leur donne une machine a
--  etats commune, _G.RunState, pour qu'ils ne se marchent pas dessus :
--
--    attente  --(auto_start clique Commencer)-->  demarrage
--       ^                                             |
--       |                                          (mobs)
--       |                                             v
--      fin  <--(RetryBtn)--  donjon  <-- kronax fait le reste
--       |
--       +--(auto_retry clique Retry)--> relance --> attente
--
--  Repartition : auto_start appuie sur Commencer au debut du donjon,
--  auto_retry appuie sur Retry a la fin, kronax s'occupe du combat.
--  Chacun n'agit que dans SA phase, et passe la main des qu'il a agi :
--  il ne peut donc pas se redeclencher avant le prochain cycle.
-- ==========================================================

local REPO = "https://raw.githubusercontent.com/rayzox-akpl/teste/main/"

local FILES = {
    kronax = "kronax_new.lua",     -- message__10 renomme
    start  = "auto_start.lua",
    retry  = "auto_retry.lua",
}

--  Le nouveau Kronax se coupe des qu'un joueur passe a moins de 600 studs,
--  ce qui arrive systematiquement au lobby entre deux runs. On corrige la
--  condition a la volee, sans avoir a modifier le fichier sur le depot :
--  la garde ne s'applique plus que si on est reellement en donjon.
local PATCH_KRONAX_LOBBY = true

--====================================================
--  Anti double chargement
--====================================================
if _G.RunLoaderActive then
    warn("[loader] deja charge, relance ignoree")
    return
end
_G.RunLoaderActive = true

if queue_on_teleport then
    queue_on_teleport('loadstring(game:HttpGet("' .. REPO .. 'loader.lua"))()')
end

local Players = game:GetService("Players")
local player = Players.LocalPlayer

--====================================================
--  MACHINE A ETATS PARTAGEE
--  Un seul detecteur, lu par les deux autres scripts. Ils ne decident
--  jamais eux-memes de l'etat, ils se contentent d'agir quand c'est leur
--  tour : c'est ce qui evite qu'ils se declenchent en boucle.
--====================================================
local State = _G.RunState or {}
_G.RunState = State

State.phase       = State.phase or "lobby"
State.since       = os.clock()
State.runs        = State.runs or 0
State.startedAt   = State.startedAt or os.clock()

--  Delais au-dela desquels on considere qu'une action a echoue et qu'il
--  faut laisser le script concerne recommencer.
State.START_TIMEOUT = 25    -- "demarrage" sans mobs au bout de 25 s
State.RETRY_TIMEOUT = 25    -- "relance" sans mobs au bout de 25 s

function State.set(phase, reason)
    if State.phase == phase then return end
    print(string.format("[etat] %s -> %s  (%s)", State.phase, phase,
        tostring(reason)))
    State.phase = phase
    State.since = os.clock()
end

function State.elapsed()
    return os.clock() - State.since
end

--  Vrai quand le donjon tourne : des mobs existent vraiment.
function State.inDungeon()
    local mobs = workspace:FindFirstChild("Mobs")
    return mobs ~= nil and #mobs:GetChildren() > 0
end

--  Bouton "Commencer" du debut de donjon. Noms possibles : on prend le
--  premier GuiButton visible qui correspond. Complete la liste si le tien
--  porte un autre nom, le journal d'auto_start te le dira.
State.START_NAMES = {"StartBtn", "StartButton", "Start", "BeginBtn",
    "Begin", "PlayBtn", "Play", "ReadyBtn", "Ready", "Commencer"}

function State.startButton()
    local gui = player:FindFirstChild("PlayerGui")
    if not gui then return nil end
    for _, name in ipairs(State.START_NAMES) do
        local found = gui:FindFirstChild(name, true)
        if found and found:IsA("GuiButton") and found.Visible then
            return found, name
        end
    end
    return nil
end

--  Chemin exact releve dans h_kronax.lua, avec repli recursif.
function State.retryButton()
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

--  Le detecteur. Il ne clique rien, il ne fait qu'observer et decider.
task.spawn(function()
    while _G.RunLoaderActive do
        task.wait(0.5)
        local ok = pcall(function()
            local inDungeon = State.inDungeon()
            local ended = State.retryButton() ~= nil
            local canStart = State.startButton() ~= nil
            local phase = State.phase

            if ended then
                -- L'ecran de fin prime sur tout le reste.
                if phase == "relance" then
                    if State.elapsed() > State.RETRY_TIMEOUT then
                        State.set("fin", "relance sans effet, on recommence")
                    end
                elseif phase ~= "fin" then
                    State.set("fin", "RetryBtn apparu")
                end

            elseif inDungeon then
                if phase ~= "donjon" then
                    State.runs = State.runs + 1
                    State.set("donjon", "mobs presents, run " .. State.runs)
                end

            elseif canStart then
                -- Bouton Commencer affiche : c'est a auto_start de jouer.
                if phase == "demarrage" then
                    if State.elapsed() > State.START_TIMEOUT then
                        State.set("attente", "Commencer sans effet")
                    end
                elseif phase ~= "attente" then
                    State.set("attente", "bouton Commencer affiche")
                end

            else
                -- Ni mobs, ni fin, ni bouton : entre deux.
                if phase == "demarrage" or phase == "relance" then
                    if State.elapsed() > State.START_TIMEOUT then
                        State.set("lobby", "action sans effet")
                    end
                elseif phase ~= "lobby" then
                    State.set("lobby", "rien a l'ecran")
                end
            end
        end)
        if not ok then task.wait(1) end
    end
end)

--====================================================
--  CHARGEMENT DES SCRIPTS
--====================================================
local function fetch(file)
    local url = REPO .. file .. "?v=" .. tostring(tick())
    local ok, source = pcall(function() return game:HttpGet(url) end)
    if not ok or type(source) ~= "string" or #source < 20 then
        warn("[loader] telechargement echoue : " .. file)
        return nil
    end
    return source
end

local function run(file, source, label)
    local fn, err = loadstring(source, "@" .. file)
    if not fn then
        warn("[loader] compilation : " .. file .. " -> " .. tostring(err))
        return false
    end
    local ok, runErr = pcall(fn)
    if not ok then
        warn("[loader] execution : " .. file .. " -> " .. tostring(runErr))
        return false
    end
    print("[loader] " .. (label or file) .. " lance")
    return true
end

--  Correction du Kronax appliquee sur la source, avant compilation.
local function patchKronax(source)
    if not PATCH_KRONAX_LOBBY then return source, false end
    local needle = "if distance <= CONFIG.PLAYER_ALERT_RADIUS then"
    local replacement = "if distance <= CONFIG.PLAYER_ALERT_RADIUS "
        .. "and workspace:FindFirstChild(\"Mobs\") then"
    local patched, count = string.gsub(source, needle, replacement, 1)
    if count == 1 then
        print("[loader] Kronax : garde des 600 studs limitee au donjon")
        return patched, true
    end
    warn("[loader] Kronax : ligne de garde introuvable, fichier non modifie")
    return source, false
end

task.spawn(function()
    -- Kronax d'abord : c'est lui qui doit etre pret quand la run demarre.
    local source = fetch(FILES.kronax)
    if source then
        source = patchKronax(source)
        run(FILES.kronax, source, "Kronax")
    end
    task.wait(0.5)

    local startSource = fetch(FILES.start)
    if startSource then run(FILES.start, startSource, "AutoStart") end
    task.wait(0.5)

    local retrySource = fetch(FILES.retry)
    if retrySource then run(FILES.retry, retrySource, "AutoRetry") end

    print("[loader] pret. Etat : " .. State.phase)
end)

--====================================================
--  ARRET GLOBAL
--====================================================
_G.StopAll = function(reason)
    print("[loader] arret global : " .. tostring(reason or "manuel"))
    for _, name in ipairs({"StopAutoStart", "StopAutoRetry",
        "StopCurrentFarm"}) do
        if typeof(_G[name]) == "function" then
            pcall(_G[name], "arret global")
        end
    end
    _G.RunLoaderActive = false
end

game:GetService("UserInputService").InputBegan:Connect(function(input, gp)
    if not gp and input.KeyCode == Enum.KeyCode.F9 then
        _G.StopAll("touche F9")
    end
end)

print("[loader] chargement en cours -- F9 pour tout arreter")
