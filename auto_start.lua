-- ==========================================================
--  AUTO START  --  demarrage du donjon.
--  Copie exacte du bloc de h_kronax.lua : saut de cinematique
--  puis StartDungeon. Rien d'autre.
-- ==========================================================

if _G.AutoStartRunning then
    print("[START] deja actif")
    return
end
_G.AutoStartRunning = true

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

    for i = 1, SKIP_COUNT do
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
    _G.AutoStartRunning = false
    print("[START] arret")
end
