-- ==========================================================
--  AUTO START  --  demarrage du donjon.
--  Copie exacte du bloc de h_kronax.lua : saut de cinematique
--  puis StartDungeon. Rien d'autre.
-- ==========================================================

--  Remplacement, pas refus. Avant, un second chargement s'arretait net et
--  l'ancienne instance continuait de tourner en fond : deux boucles en
--  parallele, et des comportements incoherents au relancement.
--
--  Le jeton est la vraie protection : chaque instance garde le sien, et
--  toute boucle s'arrete des qu'il ne correspond plus au jeton global.
--  Meme si l'ancienne met une seconde a mourir, elle ne fera plus rien.
if typeof(_G.StopAutoStart) == "function" then
    pcall(_G.StopAutoStart)
    task.wait(0.1)
end

_G.AutoStartToken = (_G.AutoStartToken or 0) + 1
local MON_JETON = _G.AutoStartToken
_G.AutoStartRunning = true

local function actif()
    return _G.AutoStartRunning and _G.AutoStartToken == MON_JETON
end

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
repeat task.wait() until Players.LocalPlayer

local SKIP_DELAY    = 6   -- attente avant le premier appel
local SKIP_COUNT    = 5   -- nombre d'appels
local SKIP_INTERVAL = 1   -- intervalle entre les appels
local START_DELAY   = 5   -- attente avant StartDungeon

--====================================================
-- SAUT DE CINEMATIQUE
-- Pas de H ici : kronax_new.lua l'envoie deja de son cote, et deux
-- appuis se annuleraient en repassant l'arme en forme normale.
--====================================================
task.spawn(function()
    if SKIP_DELAY > 0 then task.wait(SKIP_DELAY) end
    if not actif() then return end

    for i = 1, SKIP_COUNT do
        if not actif() then return end
        local ok = pcall(function()
            ReplicatedStorage.ReplicatedStorage.Packages.Knit.Services
                .DungeonService.RF.VoteSkipCutscene:InvokeServer()
        end)
        print("[SKIP] VoteSkipCutscene " .. i .. "/" .. SKIP_COUNT
            .. (ok and "" or " (echec)"))
        if i < SKIP_COUNT then task.wait(SKIP_INTERVAL) end
    end

    print("[SKIP] Termine")
end)

--====================================================
-- LANCEMENT DU DONJON
--====================================================
task.spawn(function()
    task.wait(START_DELAY)
    if not actif() then return end

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

    print("[START] StartDungeon appele")
end)

_G.StopAutoStart = function()
    if _G.AutoStartToken == MON_JETON then
        _G.AutoStartRunning = false
    end
    print("[START] arret (jeton " .. MON_JETON .. ")")
end

print("[START] lance, jeton " .. MON_JETON)
