--==========================================================================
--  BLOC AJOUTE : persistance et chargement des scripts compagnons.
--
--  Ce fichier est le point d'entree. Le lien a coller dans Solara est :
--      loadstring(game:HttpGet(
--          "https://raw.githubusercontent.com/rayzox-akpl/teste2/main/kronax_new.lua"))()
--
--  Il se remet en file d'attente pour survivre a un changement de serveur,
--  puis il charge auto_start.lua (saut de cinematique + StartDungeon) et
--  auto_retry.lua (20 clics sur RetryBtn + relance + H). Ces deux-la sont
--  les blocs de h_kronax.lua sortis dans leurs propres fichiers.
--==========================================================================

local REPO = "https://raw.githubusercontent.com/rayzox-akpl/teste2/main/"

do
    --  ANTI-DOUBLON STRICT
    --
    --  Le farm publie sa fonction d'arret dans _G.StopCurrentFarm des qu'il
    --  demarre, et la remet a nil quand il s'arrete. Elle fait donc office
    --  de verrou sans qu'on ait rien a ajouter : tant qu'elle existe, une
    --  instance tourne.
    --
    --  Si on charge par-dessus, on refuse et on ne touche a rien. Pas de
    --  remplacement, pas de tentative d'arret : l'instance en place continue
    --  et reste la seule. C'est ce qui empeche l'empilement observe au bout
    --  de quelques donjons.
    --
    --  Pour repartir proprement : la touche B, ou _G.StopCurrentFarm().
    if typeof(_G.StopCurrentFarm) == "function" then
        warn("[kronax] une instance tourne deja -- CE CHARGEMENT EST IGNORE")
        warn("[kronax] pour la remplacer : appuie sur B, puis relance")
        return
    end

    _G.KronaxGeneration = (_G.KronaxGeneration or 0) + 1
    print("[kronax] ======== GENERATION " .. _G.KronaxGeneration
        .. " -- aucune autre instance ========")

    --  Persistance : au changement de serveur, on se recharge.
    if queue_on_teleport then
        pcall(queue_on_teleport,
            'loadstring(game:HttpGet("' .. REPO .. 'kronax_new.lua"))()')
    end

    --  GitHub renvoie "404: Not Found" avec un code de succes : on teste
    --  donc le contenu, sinon loadstring recoit du HTML et renvoie nil.
    local function charger(fichier)
        local url = REPO .. fichier .. "?v=" .. tostring(tick())
        local ok, source = pcall(function() return game:HttpGet(url) end)
        if not ok or type(source) ~= "string" or #source < 40
            or source:sub(1, 3) == "404" then
            warn("[kronax] introuvable : " .. url)
            return
        end
        local fn, err = loadstring(source, "@" .. fichier)
        if not fn then
            warn("[kronax] compilation : " .. fichier .. " -> " .. tostring(err))
            return
        end
        local runOk, runErr = pcall(fn)
        if runOk then
            print("[kronax] " .. fichier .. " charge")
        else
            warn("[kronax] execution : " .. fichier .. " -> " .. tostring(runErr))
        end
    end

    task.spawn(function()
        --  auto_start ne sert QU'AU tout premier lancement : il saute la
        --  cinematique et appelle StartDungeon. Apres un retry, la run est
        --  deja partie, et le rappeler enverrait un second StartDungeon en
        --  plein combat. C'est ce qui detraquait le deplacement du farm.
        if _G.AutoStartDone then
            print("[kronax] auto_start deja fait, on ne le recharge pas")
        else
            charger("auto_start.lua")
        end
        task.wait(0.5)
        charger("auto_retry.lua")
    end)
end

--==========================================================================
--  KRONAX MINIGUN v1 -- base Kronax v0.41, maintien 60 s / pause 2 s
--
--  Ciblage :
--    1. orbite courte autour de Kronax ;
--    2. tout destructible de 1 k a 10 M PV devient la cible du minigun, sans
--       relacher le clic : reliques a 5 M ET mini RecursiveRelics a 4 M,
--       quel que soit leur nom ou leur dossier ;
--    3. au-dessus de 10 M PV (999999999) c'est une sentinelle de fin de
--       combat : jamais ciblee, retour immediat sur Kronax ;
--    4. esquive des telegraphes et points d'impact reellement localises.
--
--  Trois voies de detection complementaires :
--    - les 4 emplacements fixes du dossier Crystals (reliques) ;
--    - workspace.DescendantAdded pour tout ce que le jeu cree en combat ;
--    - un balayage borne de l'arene pour les objets simplement rallumes.
--  B ou le bouton ARRETER coupe tout et ecrit le journal.
--==========================================================================

if not game:IsLoaded() then
    local loadDeadline = os.clock() + 120
    repeat task.wait(0.25) until game:IsLoaded() or os.clock() >= loadDeadline
    if not game:IsLoaded() then
        warn("[Kronax test] chargement incomplet apres 120 s -> arret")
        return
    end
end

--  Bloc d'origine neutralise : l'en-tete ci-dessus refuse deja tout
--  chargement en double. Si on arrivait ici avec une instance vivante, il
--  l'arreterait, ce qui reintroduirait exactement le remplacement qu'on
--  veut eviter.
--
-- if typeof(_G.StopCurrentFarm) == "function" then
--     pcall(_G.StopCurrentFarm, "remplace_par_kronax_test")
--     task.wait(0.2)
-- end

local CONFIG = {
    BOSS_NAME = "kronax",
    PLAYER_SCAN_INTERVAL = 1.0,
    PLAYER_ALERT_RADIUS = 600,

    -- Profil beaucoup plus compact que Viltron (190 / 160).
    -- Valeurs du run v0.20, celui qui a tue le boss. A ne pas toucher sans
    -- une raison prouvee : le rayon a ete change deux fois sur des theories
    -- fausses (nova permanente, puis vitesse), les deux invalidees en test.
    ORBIT_RADIUS       = 58,
    ORBIT_LINEAR_SPEED = 58,
    HOLD_HEIGHT        = 55,
    -- Limite mesuree directement en jeu : les degats d'altitude commencent a
    -- 120 studs AU-DESSUS DU SOL. Le plafond est donc mesure depuis le sol et
    -- non depuis le pivot de Kronax, qui flotte et se deplace : 68 studs
    -- au-dessus du boss ne veut rien dire tant qu'on ignore ou est le boss.
    ALTITUDE_LIMIT     = 120,
    -- Limite demandee : ne jamais depasser 115 studs reels au-dessus du sol.
    ALTITUDE_MARGIN    = 5,
    HOLD_HEIGHT_MAX    = 68,
    HEIGHT_STEP        = 12,
    MIN_HORIZONTAL_DISTANCE = 54,
    MOVE_RESPONSE      = 26,
    -- Profil instantane du run gagnant : aucune bride 200/350 studs/s.
    DODGE_RESPONSE     = 120,

    -- Le timer de 60 s continue pendant les reprises apres un coup.
    MINIGUN_BURST_DURATION = 60,
    MINIGUN_REHOLD_DELAY = 2,
    MINIGUN_HIT_SETTLE = 0.15,
    MINIGUN_VERIFY_GRACE = 0.35,
    EQUIP_WAIT = 1.2,
    ATTACK_REASSERT_INTERVAL = 0.45,
    SHOT_EFFECT       = "WaterExplosion",

    -- Les noms exacts seront confirmes par le premier test.
    -- Le premier test a confirme le nom de l'objectif chronometre :
    -- "You didn't destroy the Recursive Relic on time...".
    CRYSTAL_KEYWORDS = {"crystal", "cristal", "recursive relic"},
    -- Noms plausibles pour les petits cristaux au sol du Corrupted : ils ne
    -- sont pas ranges dans le dossier Crystals et leur nom reste inconnu.
    MINI_CRYSTAL_KEYWORDS = {"crystal", "cristal", "relic", "shard", "fragment",
        "spike", "pillar", "shrine", "totem", "rune", "orb", "node", "core",
        "obelisk", "prism", "geode", "cluster"},
    CRYSTAL_SCAN_RADIUS = 500,
    FALLBACK_TARGET_RADIUS = 260,
    -- Rayon d'arene mesure depuis le centre estime par les 4 reliques : les
    -- petits cristaux tombent au sol partout dans la salle, pas autour du boss.
    ARENA_RADIUS = 420,
    -- Cadre de MOUVEMENT, independant du rayon de detection ci-dessus.
    -- MESURE, journal du run Heroic : les telegraphes Warning sont poses par
    -- le SERVEUR, jamais par le joueur, donc leur nuage donne l'etendue reelle
    -- du sol. Sur 32 telegraphes : X de -602.4 a -262.3 (+/-170.1 du centre)
    -- et Z de -293.7 a -4.5 (+/-179.0 du centre). Il y a donc du sol jouable
    -- jusqu'a 179 studs en Z. L'ancienne valeur de 115 en Z n'a jamais ete
    -- mesuree : elle reprenait par erreur le plafond d'ALTITUDE de 115 studs.
    -- Consequence prouvee : 13 traces sur 27 etaient collees a la limite Z=110
    -- et 10 sur 27 a la limite X=170, soit la moitie du combat passee contre
    -- un mur qui n'existe pas. Or l'esquive Heroic repose sur un mouvement
    -- continu : un joueur plaque contre une limite artificielle ne peut plus
    -- bouger, et TemporalTear verrouille sa position.
    -- On applique donc le rayon donne par la mesure en jeu du joueur (arene de
    -- 400 studs de diametre, 350 studs sans mur, soit 175 de rayon) sur les
    -- DEUX axes, avec les 5 studs de marge interieure habituels.
    -- CYLINDRE, pas rectangle. Mesure du joueur en jeu : l'arene est un
    -- cylindre de 400 studs de diametre, 350 sans mur, soit 175 de rayon.
    -- Le cadre rectangulaire precedent avait ses coins a 175*V2 = 247 studs,
    -- soit 72 studs DANS le mur. MESURE journaux Heroic v0.32/v0.33 : le
    -- joueur passait 29 a 35 % du combat au-dela de 175 studs, jusqu'a 226,
    -- et la vue y etait bouchee 50 a 53 % du temps -- contre 0 a 4 % a
    -- l'interieur du cylindre. Le minigun ne tirait donc pas pendant un tiers
    -- du combat, ce qui allongeait le combat et donc l'exposition.
    MOVEMENT_ARENA_RADIUS = 175,
    MOVEMENT_ARENA_INSET = 5,
    -- Le point vise ne se pose jamais pile sur le bord : un clamp par axe
    -- ecrasait des dizaines de candidats sur le meme coin et le joueur y
    -- stagnait, or rester immobile est ce qui fait encaisser les coups.
    MOVEMENT_ARENA_SOFT = 0.97,
    MOVEMENT_ARENA_EDGE_SAMPLES = 8,
    CRYSTAL_SUCCESS_WINDOW = 10,
    CANDIDATE_POLL_INTERVAL = 0.20,
    -- Une variation visuelle breve (ex. ajout/retrait de BodyPosition) annonce
    -- l'activation mais ne prouve PAS que la relique est cassee. Les journaux
    -- ont montre des retours sur Kronax apres seulement 0.4-0.6 s, avant que
    -- les tirs aient pu atteindre les 5 M PV. Sans valeur de vie repliquee, on
    -- garde donc la cible jusqu'a quatre explosions et un vrai temps de focus.
    CRYSTAL_VISUAL_MIN_SHOTS = 4,
    CRYSTAL_VISUAL_MIN_FOCUS = 2.8,
    -- Les reliques normales observees ont 5 000 000 PV, les mini
    -- RecursiveRelics au sol 4 000 000. Regle unique demandee : tout destructible
    -- jusqu'a 10 M est casse, au-dessus c'est une sentinelle a vie infinie
    -- (999999999) qu'il ne faut jamais toucher -> focus Kronax.
    CRYSTAL_MAX_TARGET_HEALTH = 10000000,
    -- Plancher anti-decor : un objet a 1 ou 100 PV n'est pas un objectif.
    CRYSTAL_MIN_TARGET_HEALTH = 1000,
    -- Filet de securite : une cible tenue aussi longtemps sans lui avoir
    -- retire un seul PV est incassable. On l'abandonne et on reprend Kronax
    -- plutot que de perdre la course. Les reliques a 5 M tombaient en 4 a 7 s.
    CRYSTAL_STUCK_TIMEOUT = 15,
    -- Approche rapprochee reservee aux petits cristaux au sol.
    MINI_APPROACH_DISTANCE = 16,
    MINI_APPROACH_HEIGHT   = 8,
    MINI_CONTACT_HEIGHT    = 5,
    -- Au-dela de cet ecart on se teleporte au lieu de glisser.
    MINI_TELEPORT_DISTANCE = 5,
    -- Le tir a distance suffit la plupart du temps. On ne se teleporte que si
    -- le cristal tient encore apres ce delai de visee : c'est le signe qu'un
    -- mur bloque la ligne de tir.
    MINI_TELEPORT_DELAY = 5.0,
    DYNAMIC_CRYSTAL_SETTLE_DELAY = 0.06,
    -- Le dossier confirme des mini cristaux est minuscule : ce controle direct
    -- retrouve un enfant insere/recycle meme si DescendantAdded a ete manque.
    RECURSIVE_RELIC_POLL_INTERVAL = 0.25,
    -- Balayage incremental borne : retrouve un cristal recycle sur place, sans
    -- jamais parcourir toute la map d'un coup.
    ARENA_SWEEP_INTERVAL = 0.80,
    ARENA_SWEEP_BUDGET = 220,
    -- Journal de decouverte plafonne : sert a identifier la vraie signature
    -- si un petit cristal passe encore au travers, sans noyer le fichier.
    DISCOVERY_LOG_MAX = 40,

    -- Esquive generique prudente : seulement les dangers localisables.
    WARNING_KEYWORDS = {"warning", "telegraph", "danger", "indicator", "aoe"},
    WARNING_DEFAULT_RADIUS = 18,
    WARNING_RADIUS_MAX = 160,
    WARNING_LIFETIME = 2.5,
    -- Rayon mesure des telegraphes au sol : parts de 56 studs de diametre.
    HAZARD_DEFAULT_RADIUS = 28,
    -- Rayon d'une goutte de FlashForwardRain : le serveur donne les 40
    -- positions exactes, chacune telegraphiee par une part de 56 studs.
    RAIN_DROP_RADIUS = 28,
    RAIN_MAX_DROPS = 40,
    -- MESURE v0.32, journal Heroic : les 40 gouttes tombent DANS L'ORDRE DES
    -- INDEX, une toutes les 0.559 s, soit 21.8 s de pluie. Le champ
    -- DelayBetween=0.045 envoye par le serveur est faux d'un facteur 12 : il
    -- donnait 1.8 s de pluie. Le script creait donc les 40 zones d'un coup
    -- avec 1.1 a 2.9 s de vie, et n'avait plus AUCUNE zone en memoire des la
    -- 3e seconde alors que les gouttes continuaient pendant 19 s. C'est
    -- l'origine des degats "venus de nulle part" : 4 coups sur 6 du run.
    RAIN_DROP_INTERVAL = 0.56,
    -- Chaque zone est armee ce delai avant sa goutte, et dure ce total.
    RAIN_DROP_LEAD = 1.20,
    RAIN_DROP_WINDOW = 2.00,
    HAZARD_RADIUS_MAX = 160,
    -- MESURE v0.33 : ChronoShockwave n'est PAS un coup unique. Detonation a
    -- lancer + ChargeUp(3 s), puis une salve qui frappe TOUTES LES 0.515 s.
    -- Journal Heroic v0.33, detonation a 38.86 : degats a +1.03, +1.55, +2.06
    -- et +2.58 s, soit les ticks 2, 3, 4 et 5 pile sur la grille.
    -- Journal Heroic v0.32, detonation a 37.69 : ticks 1, 2, 5 et 6.
    -- Journal Corrupted (le record) : detonation a 41.90, AUCUN degat -- le
    -- joueur etait simplement hors des 140 studs. Le record tenait a ca.
    -- 4 ticks x 4515 = 18 060 degats sur 22 076 PV : 82 % de la barre en 2 s.
    -- C'etait la seule capacite volontairement non esquivee, reste d'un test.
    SHOCKWAVE_LINGER = 4.50,
    HAZARD_LIFETIME = 2.2,
    -- Des degats ont ete pris a bord=-2, +1 et +3 : le script tolerait de
    -- raser le bord des zones. Marges elargies.
    HAZARD_TRIGGER_MARGIN = 14,
    HAZARD_ESCAPE_MARGIN = 22,
    -- Le run v0.25 a prouve que TimelineDestruction ne se limite pas au
    -- cercle de 30 studs suppose jusque-la : plusieurs impacts sont arrives
    -- apres un passage a 42-46 studs de son axe/cible. On protege donc un
    -- couloir de 60 studs entre Kronax et le point vise.
    TIMELINE_CORRIDOR_RADIUS = 60,
    -- Le payload annonce LingerDuration=1.5 s. Le verrou ajoute 0.25 s de
    -- marge et interdit le retour premature a l'orbite (v0.25 sortait apres
    -- 0.65 s, puis recevait encore un tick a +1.07 s).
    TIMELINE_DODGE_HOLD = 1.75,
    TIMELINE_LINGER_MARGIN = 0.25,
    -- MESURE v0.34 + v0.35 : 6 coups sur les 13 des deux runs sont tombes
    -- alors que le joueur etait REELLEMENT dans un couloir Timeline (4.9 a
    -- 36.9 studs de l'axe, rayon 60). Age de ces couloirs au moment du coup :
    -- 2.18 / 2.53 / 2.72 / 2.80 / 2.82 / 2.85 s. Or le script les supprimait
    -- a 2.00 s. Les six coups sont tombes dans la fenetre entre ma peremption
    -- et la vraie. LingerDuration=1.5 ne compte que la trainee finale : le
    -- projectile doit d'abord PARCOURIR le couloir (92 a 246 studs observes,
    -- ProjectileSpeedMultiplier=3), d'ou une duree totale bien plus longue.
    -- 3.50 laisse 0.65 s de marge sur le pire cas mesure.
    CORRIDOR_LIFETIME = 3.50,
    DODGE_RADIUS_EXTRA = 20,
    DODGE_RADIUS_MAX = 170,
    -- Hauteurs d'esquive mesurees depuis le SOL, pas depuis Kronax qui flotte
    -- environ 39 studs plus haut. 120 reste le seuil de degats mesure en jeu
    -- et 115 le plafond dur du script (ALTITUDE_MARGIN), mais les paliers
    -- d'esquive n'y montent plus : demande explicite du joueur, meme bande de
    -- 24 a 88 pour le Corrupted que pour le Heroic. Le palier a 115 se posait
    -- pile sur le plafond, sans marge, et le ping-pong 8 <-> 115 n'a jamais
    -- evite un seul coup.
    DODGE_ALTITUDES = {24, 40, 56, 72, 88},
    DODGE_LOCAL_RADII = {32, 58, 86},
    DODGE_LOCAL_DIRECTIONS = 12,
    DODGE_CLEARANCE_SCORE_CAP = 30,
    DODGE_TRAVEL_SCORE_WEIGHT = 1.0,
    DODGE_MIN_HOLD = 0.65,
    DODGE_RELEASE_MARGIN = 16,
    DODGE_REPLAN_INTERVAL = 0.10,
    DODGE_CANDIDATE_COUNT = 20,
    TARGETED_BURST_RATIO = 0.15,
    TARGETED_BURST_SECONDS = 0.70,

    -- Profil reserve a Dungeon=HeroicTimeRaid. Le mouvement principal est une
    -- trajectoire O(1) mise a jour chaque frame; le solveur couteux ne sert que
    -- lorsqu'une vraie zone dure coupe cette trajectoire.
    -- La courbe avance moins vite que le joueur : cette marge lui permet de
    -- rejoindre proprement sa tangente apres un detour, au lieu de couper la
    -- salle en poursuivant un waypoint impossible a rattraper.
    HEROIC_PATH_SPEED = 120,
    HEROIC_TARGET_PATH_SPEED = 150,
    -- SUPPRIME en v0.32 : HEROIC_TRACK_SPEED / TARGET_SPEED / ESCAPE_SPEED.
    -- La bride de vitesse a ete mesuree nuisible (voir la branche de
    -- deplacement). Les deux vitesses ci-dessus ne brident rien : elles font
    -- avancer le POINT VISE le long de l'ellipse, le joueur y saute d'un bloc.
    HEROIC_THRONE_RADIUS_X = 48,
    HEROIC_THRONE_RADIUS_Z = 32,
    HEROIC_START_RAMP = 0.75,
    HEROIC_DEPARTURE_BLEND_START = 12,
    HEROIC_DEPARTURE_BLEND_END = 90,
    HEROIC_ANCHOR_RESPONSE = 3.5,
    HEROIC_ARENA_EDGE_MARGIN = 10,
    HEROIC_ALTITUDE_BASE = 56,
    HEROIC_ALTITUDE_AMPLITUDE = 24,
    HEROIC_ALTITUDE_FREQUENCY = 0.70,
    HEROIC_DODGE_ALTITUDES = {24, 40, 56, 72, 88},
    HEROIC_DODGE_LOCAL_RADII = {48, 88, 124},
    HEROIC_DODGE_LOCAL_DIRECTIONS = 10,
    HEROIC_TEMPORAL_HOLD = 0.80,
    -- PLANCHER DE DEPLACEMENT (v0.37). MESURE sur 4 runs du meme script :
    -- deplacement median entre deux lancers de TemporalTear = 82 et 81 studs
    -- sur les deux runs GAGNES, 54 sur le run PERDU. Trois des six coups de
    -- ce run sont tombes a 8, 8 et 11 studs du point verrouille. Tout le reste
    -- etait identique : boucle de rendu a 1.010 s, densite de dangers 6, vue
    -- bouchee 1 %, cadence du boss identique. La seule variable qui bouge est
    -- le deplacement. Quand il stagne, TemporalTear nous trouve.
    -- Ce plancher ne force RIEN d'autre qu'un saut de phase sur l'ellipse :
    -- toutes les verifications qui suivent (pointSafe, movementPathSafe,
    -- cylindre, plafond d'altitude, esquives) s'appliquent ensuite normalement.
    MIN_TRAVEL_WINDOW = 0.60,
    MIN_TRAVEL_DISTANCE = 60,
    TRAVEL_KICK_ANGLE = 1.90,
    TRAVEL_KICK_COOLDOWN = 0.45,
    HEROIC_FLASH_HOLD = 1.20,

    TRACE_PERIOD = 1.0,
    MESSAGE_SCAN_INTERVAL = 1.50,
    LOG_WRITE_PERIOD = 3.0,
    LOG_MAX_LINES = 3000,
    LOG_FILE = "logs/kronax/kronax_minigun_log.txt",
    VERBOSE_DIAGNOSTICS = false,
    -- Vidage du payload d'AbilityFired, une fois par type de capacite. Le
    -- rayon et la duree des zones ne sont AUCUNEMENT mesures aujourd'hui :
    -- payloadRadius n'a jamais trouve Radius/AOERadius/HitboxRadius/Width/
    -- Size et retombe sur 24 studs pour tout. Il faut voir les vrais champs.
    LOG_ABILITY_PAYLOAD = true,
}

local Players           = game:GetService("Players")
local RunService        = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService  = game:GetService("UserInputService")
local VIM               = game:GetService("VirtualInputManager")

local player = Players.LocalPlayer
local character = player.Character or player.CharacterAdded:Wait()
local humanoid = character:WaitForChild("Humanoid")
local root = character:WaitForChild("HumanoidRootPart")

local running = true
local connections = {}
local characterConnections = {}
local bossConnections = {}
local crystalConnections = {}

local characterParts = {}
local oldCollision = {}
local partAdded = nil
local partRemoved = nil

local boss = nil
local bossHumanoid = nil
local bossLastHealth = nil
local bossSeenAt = 0

local weaponName = nil
local equipping = false
local mouseHeld = nil
local holdStartedAt = 0
local shotSeenThisHold = false
local lastShotEffect = 0
local cooldownUntil = 0
local minigun = {
    burstUntil = nil, restartAt = nil, nextEquip = 0, nextArm = 0,
    missingSince = nil, tool = nil, deactivated = nil, releasing = false,
    stunMessages = setmetatable({}, {__mode = "k"}), nextMessageScan = 0,
    stunUntil = 0,
}
local reholdCount = 0
local lastAttackAssert = -math.huge
local lastAttackTarget = nil

local orbitAngle = 0
local holdHeight = CONFIG.HOLD_HEIGHT
local sightClear = true
local sightBlocker = nil
local lastSightCheck = 0
local lastHeightChange = 0
local activeDodgeLabel = nil
local activeDodgeUntil = 0
local targetedBurstUntil = 0
local timelineDodgeUntil = 0
local heroicState = {
    mode = false,
    motionPhase = 0,
    targetedUntil = 0,
    targetedLabel = nil,
    anchorBlend = 0,
    anchor = nil,
    radiusX = CONFIG.HEROIC_THRONE_RADIUS_X,
    radiusZ = CONFIG.HEROIC_THRONE_RADIUS_Z,
    losGoal = nil,
    losGoalUntil = 0,
}

local crystals = {}
local crystalSerial = 0
local activeCrystal = nil
local activeTarget = nil
local crystalStats = {seen = 0, destroyed = 0, missed = 0, ignored = 0}
local crystalCandidates = {}
local crystalRoomCenter = nil
local watchedCrystalFolders = setmetatable({}, {__mode = "k"})
local ignoredCrystals = setmetatable({}, {__mode = "k"})
local dynamicCrystalWatched = setmetatable({}, {__mode = "k"})
local dynamicCrystalPending = setmetatable({}, {__mode = "k"})
local discoverySeen = setmetatable({}, {__mode = "k"})
local discoveryLogged = 0
local miniCrystalCount = 0
local sweepChildIndex = 1

local hazards = {}
local recentAbilities = {}
local abilityCounts = {}
local warningParts = setmetatable({}, {__mode = "k"})
local damageBuckets = {}
local timelineCasts = {}
local motionSamples = {}
local messageState = {}
local ui = nil
local bossInitialPosition = nil
local usingRoomCenter = false
local cachedDodgeGoal = nil
local cachedDodgeGoalUntil = 0

local startedAt = os.clock()
local logLines = {}
local logDirty = false
local lastLogWrite = 0
local lastTrace = 0

local function stamp(text)
    return string.format("[%7.2f] %s", os.clock() - startedAt, text)
end

local function pushLine(text)
    logLines[#logLines + 1] = text
    if #logLines > CONFIG.LOG_MAX_LINES then table.remove(logLines, 1) end
    logDirty = true
end

local function say(formatText, ...)
    local ok, text = pcall(string.format, formatText, ...)
    text = ok and text or tostring(formatText)
    print("[Kronax test] " .. text)
    pushLine(stamp(text))
end

local function writeLog(force)
    if not logDirty then return end
    local now = os.clock()
    if not force and now - lastLogWrite < CONFIG.LOG_WRITE_PERIOD then return end
    lastLogWrite = now
    logDirty = false
    if typeof(writefile) == "function" then
        pcall(writefile, CONFIG.LOG_FILE, table.concat(logLines, "\n"))
    end
end

if typeof(makefolder) == "function" then
    pcall(makefolder, "logs")
    pcall(makefolder, "logs/kronax")
end

local function connect(signal, callback, list)
    local connection = signal:Connect(callback)
    local targetList = list or connections
    targetList[#targetList + 1] = connection
    return connection
end

local function disconnectList(list)
    for _, connection in ipairs(list) do
        pcall(function() connection:Disconnect() end)
    end
    table.clear(list)
end

local function describe(value, depth)
    local kind = typeof(value)
    if kind == "Instance" then return value.ClassName .. ":" .. value.Name end
    if kind == "Vector3" then
        return string.format("V3(%.1f,%.1f,%.1f)", value.X, value.Y, value.Z)
    end
    if kind == "CFrame" then
        local p = value.Position
        return string.format("CF(%.1f,%.1f,%.1f)", p.X, p.Y, p.Z)
    end
    if kind == "Color3" then
        return string.format("RGB(%d,%d,%d)", value.R * 255, value.G * 255, value.B * 255)
    end
    if kind == "table" then
        if depth <= 0 then return "{...}" end
        local parts = {}
        for key, item in pairs(value) do
            parts[#parts + 1] = tostring(key) .. "=" .. describe(item, depth - 1)
            if #parts >= 40 then
                parts[#parts + 1] = "..."
                break
            end
        end
        return "{" .. table.concat(parts, ", ") .. "}"
    end
    return tostring(value)
end

local function attributesOf(object)
    local parts = {}
    for name, value in pairs(object:GetAttributes()) do
        parts[#parts + 1] = name .. "=" .. describe(value, 1)
        if #parts >= 20 then
            parts[#parts + 1] = "..."
            break
        end
    end
    return #parts > 0 and (" attrs={" .. table.concat(parts, ",") .. "}") or ""
end

local function flatDistance(a, b)
    return ((a - b) * Vector3.new(1, 0, 1)).Magnitude
end

local function flatSegmentDistance(point, segmentStart, segmentEnd)
    local direction = (segmentEnd - segmentStart) * Vector3.new(1, 0, 1)
    local offset = (point - segmentStart) * Vector3.new(1, 0, 1)
    local lengthSquared = direction:Dot(direction)
    if lengthSquared <= 0.0001 then return offset.Magnitude end
    local alpha = math.clamp(offset:Dot(direction) / lengthSquared, 0, 1)
    return (offset - direction * alpha).Magnitude
end

local function segmentDistance3D(point, segmentStart, segmentEnd)
    local direction = segmentEnd - segmentStart
    local lengthSquared = direction:Dot(direction)
    if lengthSquared <= 0.0001 then return (point - segmentStart).Magnitude end
    local alpha = math.clamp((point - segmentStart):Dot(direction)
        / lengthSquared, 0, 1)
    return (point - (segmentStart + direction * alpha)).Magnitude
end

local function flatCross(ax, az, bx, bz)
    return ax * bz - az * bx
end

local function flatSegmentsDistance(a, b, c, d)
    local rx, rz = b.X - a.X, b.Z - a.Z
    local sx, sz = d.X - c.X, d.Z - c.Z
    local qx, qz = c.X - a.X, c.Z - a.Z
    local denominator = flatCross(rx, rz, sx, sz)
    if math.abs(denominator) > 0.0001 then
        local t = flatCross(qx, qz, sx, sz) / denominator
        local u = flatCross(qx, qz, rx, rz) / denominator
        if t >= 0 and t <= 1 and u >= 0 and u <= 1 then return 0 end
    end
    return math.min(
        flatSegmentDistance(a, c, d), flatSegmentDistance(b, c, d),
        flatSegmentDistance(c, a, b), flatSegmentDistance(d, a, b))
end

local function recordMotionSample(at, position)
    motionSamples[#motionSamples + 1] = {at = at, pos = position}
    local oldest = at - 1.6
    while #motionSamples > 0
        and (motionSamples[1].at < oldest or #motionSamples > 120) do
        table.remove(motionSamples, 1)
    end
end

local function logTimelineEvidence(at, position)
    for index = #timelineCasts, 1, -1 do
        local cast = timelineCasts[index]
        local age = at - cast.at
        if age > 2.2 then
            table.remove(timelineCasts, index)
        elseif age >= 0 then
            local currentTarget = flatDistance(position, cast.target)
            local currentLine = flatSegmentDistance(position,
                cast.origin, cast.target)
            local minTarget = currentTarget
            local minLine = currentLine
            local minCrossing = math.huge
            local maxStep = 0
            local samples = 0
            local previous = nil
            for _, sample in ipairs(motionSamples) do
                if sample.at >= cast.at - 0.03 and sample.at <= at + 0.03 then
                    samples += 1
                    minTarget = math.min(minTarget,
                        flatDistance(sample.pos, cast.target))
                    minLine = math.min(minLine,
                        flatSegmentDistance(sample.pos, cast.origin, cast.target))
                    if previous then
                        maxStep = math.max(maxStep,
                            flatDistance(previous.pos, sample.pos))
                        minTarget = math.min(minTarget,
                            flatSegmentDistance(cast.target,
                                previous.pos, sample.pos))
                        minCrossing = math.min(minCrossing,
                            flatSegmentsDistance(previous.pos, sample.pos,
                                cast.origin, cast.target))
                    end
                    previous = sample
                end
            end
            if minCrossing == math.huge then minCrossing = currentLine end
            say("PREUVE TIMELINE #%d : age=%.3f cibleAct=%.1f axeAct=%.1f"
                    .. " minCible=%.1f minAxe=%.1f croisement=%.1f"
                    .. " pasMax=%.1f echantillons=%d",
                cast.id, age, currentTarget, currentLine,
                minTarget, minLine, minCrossing, maxStep, samples)
        end
    end
end

local function pivotOf(object)
    if not object or not object.Parent then return nil end
    if object:IsA("BasePart") then return object.Position end
    if object:IsA("Model") then
        local part = object:FindFirstChild("HumanoidRootPart")
            or object.PrimaryPart
            or object:FindFirstChild("Head")
            or object:FindFirstChildWhichIsA("BasePart", true)
        if part then return part.Position end
        local ok, cf = pcall(object.GetPivot, object)
        if ok then return cf.Position end
    end
    return nil
end

local function tapKey(key, virtualKey)
    local ok = pcall(function()
        VIM:SendKeyEvent(true, key, false, game)
        task.wait(0.08)
        VIM:SendKeyEvent(false, key, false, game)
    end)
    if ok then return true end
    if typeof(keypress) ~= "function" then return false end
    return pcall(function()
        keypress(virtualKey)
        task.wait(0.08)
        keyrelease(virtualKey)
    end)
end

local function releaseAttack()
    minigun.releasing = true
    if typeof(mouseHeld) == "table" then
        pcall(function()
            VIM:SendMouseButtonEvent(mouseHeld.x, mouseHeld.y, 0, false, game, 0)
        end)
    elseif mouseHeld == "executor" and typeof(mouse1release) == "function" then
        pcall(mouse1release)
    end
    mouseHeld = nil
    lastAttackAssert = -math.huge
    minigun.releasing = false
end

local function holdAttack()
    if not running or humanoid.Health <= 0 then return false end
    local camera = workspace.CurrentCamera
    if not camera then return false end
    local now = os.clock()
    if mouseHeld and now - lastAttackAssert < CONFIG.ATTACK_REASSERT_INTERVAL then
        return true
    end
    local x = camera.ViewportSize.X / 2
    local y = camera.ViewportSize.Y / 2
    pcall(function() VIM:SendMouseMoveEvent(x, y, game) end)
    if typeof(mouseHeld) == "table" then
        local ok = pcall(function()
            VIM:SendMouseButtonEvent(x, y, 0, true, game, 0)
        end)
        if ok then
            mouseHeld = {x = x, y = y}
            lastAttackAssert = now
            return true
        end
    elseif mouseHeld == "executor" and typeof(mouse1press) == "function" then
        if pcall(mouse1press) then
            lastAttackAssert = now
            return true
        end
    end
    local ok = pcall(function()
        VIM:SendMouseButtonEvent(x, y, 0, true, game, 0)
    end)
    if ok then
        mouseHeld = {x = x, y = y}
        lastAttackAssert = now
        return true
    end
    if typeof(mouse1press) == "function" and pcall(mouse1press) then
        mouseHeld = "executor"
        lastAttackAssert = now
        return true
    end
    return false
end

local function equippedTool()
    if not character or not character.Parent then return nil end
    return character:FindFirstChildOfClass("Tool")
end

local function describeWeapon(tool)
    say("OUTIL MINIGUN DETECTE : %s%s", tool.Name, attributesOf(tool))
end

-- Verifier le vrai outil transforme : H envoye ne prouve pas son activation.
local function weaponEquipped()
    local tool = equippedTool()
    if not tool then return false end
    local name = tool.Name:lower():gsub("[^%w]", "")
    return name == "watergun" or name:find("minigun", 1, true) ~= nil
end

local function equipWeapon()
    if not running or humanoid.Health <= 0 then return false end
    if weaponEquipped() then return true end
    local now = os.clock()
    if now < minigun.nextEquip then return false end
    minigun.nextEquip = now + CONFIG.EQUIP_WAIT
    releaseAttack()
    tapKey(Enum.KeyCode.One, 0x31)
    return running and weaponEquipped()
end

function minigun.interrupt(reason)
    if not running or minigun.releasing or not mouseHeld then return end
    minigun.restartAt = os.clock() + CONFIG.MINIGUN_HIT_SETTLE
    releaseAttack()
    say("MINIGUN INTERROMPU : %s -> reprise apres liberation du controle", reason)
end

function minigun.watchTool(tool)
    if minigun.tool == tool then return end
    if minigun.deactivated then minigun.deactivated:Disconnect() end
    minigun.tool, minigun.deactivated = tool, nil
    if tool then
        describeWeapon(tool)
        minigun.deactivated = tool.Deactivated:Connect(function()
            minigun.interrupt("outil desactive")
        end)
    end
end

local function bossPosition()
    return pivotOf(boss)
end

local function bossAlive()
    return boss ~= nil and boss.Parent ~= nil
        and bossHumanoid ~= nil and bossHumanoid.Health > 0
end

local function matchingBoss(model)
    if not model or not model:IsA("Model") then return false end
    if not string.find(string.lower(model.Name), CONFIG.BOSS_NAME, 1, true) then
        return false
    end
    local targetHumanoid = model:FindFirstChildOfClass("Humanoid")
    if not targetHumanoid or targetHumanoid.Health <= 0 then return false end

    -- Le hub contient KronaxTimeMachine et KronaxCutscene avec 100 PV. Ce ne
    -- sont pas des boss : un vrai Kronax observe porte Boss=true, Base=TimeBoss
    -- et/ou un Dungeon de la famille TimeRaid.
    local dungeon = string.lower(tostring(model:GetAttribute("Dungeon") or ""))
    return model:GetAttribute("Boss") == true
        or model:GetAttribute("Base") == "TimeBoss"
        or string.find(dungeon, "timeraid", 1, true) ~= nil
end

local function findBoss()
    for _, folderName in ipairs({"Mobs", "Enemies", "Enemy", "NPCs", "Monsters"}) do
        local folder = workspace:FindFirstChild(folderName)
        if folder then
            for _, model in ipairs(folder:GetDescendants()) do
                if matchingBoss(model) then return model end
            end
        end
    end
    for _, model in ipairs(workspace:GetDescendants()) do
        if matchingBoss(model) then return model end
    end
    return nil
end

local function loweredHasAny(text, keywords)
    text = string.lower(text)
    for _, keyword in ipairs(keywords) do
        if string.find(text, keyword, 1, true) then return true end
    end
    return false
end

local HEALTH_NAMES = {Health = true, HP = true, HitPoints = true, Durability = true}
-- pairs() n'a pas d'ordre garanti : la liste ordonnee evite de lire une
-- "Durability" de decor avant la vraie "Health" du cristal.
local HEALTH_NAME_ORDER = {"Health", "HP", "HitPoints", "Durability"}

local function arenaCenter()
    -- Les 4 reliques donnent un centre stable; le boss se deplace beaucoup et
    -- ferait sortir du rayon un petit cristal tombe a l'autre bout de la salle.
    return crystalRoomCenter or pivotOf(boss)
end

local function numberChildValue(object, name)
    local child = object:FindFirstChild(name)
    if child and (child:IsA("NumberValue") or child:IsA("IntValue")) then
        return child.Value, child
    end
    return nil, nil
end

-- Sonde rapide : attributs, Humanoid direct, valeurs enfants directes.
-- Aucune descente recursive -> utilisable sur des centaines d'objets par
-- balayage sans faire chuter les FPS.
local function quickHealth(object)
    if not object or not object.Parent then return nil, nil, nil end
    for _, name in ipairs(HEALTH_NAME_ORDER) do
        local attribute = object:GetAttribute(name)
        if typeof(attribute) == "number" then
            local maximum = object:GetAttribute("MaxHealth")
            return attribute, typeof(maximum) == "number" and maximum or nil, nil
        end
    end
    if object:IsA("Model") then
        local hum = object:FindFirstChildOfClass("Humanoid")
        if hum then return hum.Health, hum.MaxHealth, hum end
    end
    local maximum = numberChildValue(object, "MaxHealth")
    for _, name in ipairs(HEALTH_NAME_ORDER) do
        local value, source = numberChildValue(object, name)
        if value ~= nil then return value, maximum, source end
    end
    return nil, nil, nil
end

-- Sonde complete : la recherche recursive n'est payee que pour un objet deja
-- retenu comme cible potentielle.
local function crystalHealth(object)
    if not object or not object.Parent then return nil, nil, nil end
    local value, maximum, source = quickHealth(object)
    if value ~= nil then return value, maximum, source end
    for _, name in ipairs(HEALTH_NAME_ORDER) do
        local child = object:FindFirstChild(name, true)
        if child and (child:IsA("NumberValue") or child:IsA("IntValue")) then
            local maxChild = object:FindFirstChild("MaxHealth", true)
            local deepMax = maxChild
                and (maxChild:IsA("NumberValue") or maxChild:IsA("IntValue"))
                and maxChild.Value or nil
            return child.Value, deepMax, child
        end
    end
    return nil, nil, nil
end

local function untargetableHealthValue(value)
    if typeof(value) ~= "number" or value <= 0 then return false end
    return value > CONFIG.CRYSTAL_MAX_TARGET_HEALTH
end

local function untargetableCrystalHealth(health, maxHealth)
    return untargetableHealthValue(health) or untargetableHealthValue(maxHealth)
end

local function crystalRootFrom(object)
    -- Le jeu range les Recursive Relics sous TimeRaidDungeon.Crystals.
    -- On prend l'enfant direct de ce dossier comme cible, meme si son nom
    -- futur n'inclut ni "crystal" ni "relic".
    local current = object
    for _ = 1, 10 do
        if not current or current == workspace then break end
        local parent = current.Parent
        local parentIsCrystalFolder = parent and parent:IsA("Folder")
            and (string.lower(parent.Name) == "crystals"
                or loweredHasAny(parent.Name, CONFIG.CRYSTAL_KEYWORDS))
        if parentIsCrystalFolder
            and (current:IsA("Model") or current:IsA("BasePart")) then
            return current, "dossier de cristaux"
        end
        current = parent
    end

    current = object
    local namedPart = nil
    for _ = 1, 7 do
        if not current or current == workspace then break end
        if (current:IsA("Model") or current:IsA("BasePart"))
            and loweredHasAny(current.Name, CONFIG.CRYSTAL_KEYWORDS) then
            if current:IsA("Model") then return current, "nom" end
            namedPart = namedPart or current
        end
        current = current.Parent
    end
    return namedPart, namedPart and "nom" or nil
end

local function crystalAimPart(object)
    if not object or not object.Parent then return nil end
    if object:IsA("BasePart") then return object end
    if not object:IsA("Model") then return nil end

    local best = object.PrimaryPart
    local bestScore = best and 10000 or -math.huge
    for _, part in ipairs(object:GetDescendants()) do
        if part:IsA("BasePart") then
            local name = string.lower(part.Name)
            local score = part.Size.Magnitude
            if string.find(name, "hitbox", 1, true) then
                score += 9000
            elseif string.find(name, "core", 1, true)
                or string.find(name, "center", 1, true)
                or string.find(name, "centre", 1, true)
                or name == "root" or name == "main" then
                score += 5000
            end
            if part.Transparency < 0.98 then score += 100 end
            local queryable = true
            pcall(function() queryable = part.CanQuery end)
            if queryable then score += 50 end
            if score > bestScore then
                best, bestScore = part, score
            end
        end
    end
    return best
end

local function damageableRootFrom(object)
    local current = object
    for _ = 1, 8 do
        if not current or current == workspace then break end
        if current:IsA("Model") then
            local health = crystalHealth(current)
            if health ~= nil then return current end
        elseif current:IsA("BasePart") then
            local health = crystalHealth(current)
            if health ~= nil then return current end
        end
        current = current.Parent
    end
    return nil
end

local function belongsToPlayer(object)
    -- Les esprits invoques ne sont pas ranges dans le Character : ils vivent
    -- directement sous Workspace avec une vraie vie, ce qui les faisait passer
    -- pour des mini-cristaux. Mender expose exactement Owner + SpiritType.
    -- On filtre cette signature et rien de plus afin de conserver la detection
    -- generique des RecursiveRelics, dont le nom/dossier peut changer.
    local current = object
    for _ = 1, 8 do
        if not current or current == workspace then break end
        if current:IsA("Model")
            and current:GetAttribute("Owner") ~= nil
            and current:GetAttribute("SpiritType") ~= nil then
            if not discoverySeen[current] then
                discoverySeen[current] = true
                say("INVOCATION ALLIEE IGNOREE : %s Owner=%s SpiritType=%s",
                    current:GetFullName(), tostring(current:GetAttribute("Owner")),
                    tostring(current:GetAttribute("SpiritType")))
            end
            return true
        end
        current = current.Parent
    end

    for _, otherPlayer in ipairs(Players:GetPlayers()) do
        local otherCharacter = otherPlayer.Character
        if otherCharacter and (object == otherCharacter
            or object:IsDescendantOf(otherCharacter)) then
            return true
        end
    end
    return false
end

local function crystalAlive(object, info)
    if not object or not object.Parent then return false end
    -- Filet pour une invocation dont Owner/SpiritType seraient repliques apres
    -- son apparition : elle sort de la selection au tour suivant.
    if belongsToPlayer(object) then return false end
    if ignoredCrystals[object] then return false end
    info = info or crystals[object]
    if info and (info.finished or info.ignored) then return false end
    if info and info.lastHealth ~= nil then return info.lastHealth > 0 end
    local health = crystalHealth(object)
    return health == nil or health > 0
end

local function selectCrystal()
    local best = nil
    local bestPriority = -math.huge
    local bestDistance = math.huge
    for object, info in pairs(crystals) do
        if crystalAlive(object, info) then
            local pos = pivotOf(object)
            local distance = pos and root and (pos - root.Position).Magnitude or math.huge
            if info.priority > bestPriority
                or (info.priority == bestPriority and distance < bestDistance) then
                best, bestPriority, bestDistance = object, info.priority, distance
            end
        end
    end
    if best ~= activeCrystal then
        activeCrystal = best
        if best then
            local info = crystals[best]
            info.acquiredAt = info.acquiredAt or os.clock()
            say("PRIORITE OBJECTIF #%d : %s (acquis en %.3f s)",
                info.id, best:GetFullName(), info.acquiredAt - info.spawnedAt)
        else
            say("plus aucun objectif prioritaire actif -> retour sur Kronax")
        end
    end
    return best
end

local function finishCrystal(object, reason)
    local info = crystals[object]
    if not info or info.finished then return end
    info.finished = true
    local elapsed = os.clock() - info.spawnedAt
    local health = crystalHealth(object)
    local fastFocusedDisappearance = reason == "disparu/detruit"
        and info.acquiredAt ~= nil and elapsed <= CONFIG.CRYSTAL_SUCCESS_WINDOW
    if reason == "PV a zero" or reason == "desactivee/cassee"
        or health == 0 or fastFocusedDisappearance then
        crystalStats.destroyed += 1
    else
        crystalStats.missed += 1
    end
    say("OBJECTIF #%d FIN : %s apres %.3f s, premier tir=%s",
        info.id, reason, elapsed,
        info.firstShotAt and string.format("%.3f s", info.firstShotAt - info.spawnedAt)
            or "non observe")
    if activeCrystal == object then
        activeCrystal = nil
        task.defer(selectCrystal)
    end
end

local function ignoreHighHealthCrystal(object, health, maxHealth, reason)
    if not object or ignoredCrystals[object] then return end
    ignoredCrystals[object] = true
    crystalStats.ignored += 1

    local candidate = crystalCandidates[object]
    if candidate then
        candidate.active = false
        candidate.ignored = true
        candidate.inactiveSince = nil
    end

    local info = crystals[object]
    if info and not info.finished then
        info.finished = true
        info.ignored = true
        -- Il avait ete compte comme objectif attaquable avant de recevoir sa
        -- valeur au-dessus du seuil : on le retire du bilan des vraies reliques.
        crystalStats.seen = math.max(0, crystalStats.seen - 1)
    end
    say("CRISTAL >10M IGNORE : %s vie=%s/%s raison=%s -> FOCUS KRONAX",
        object:GetFullName(),
        health and string.format("%.0f", health) or "?",
        maxHealth and string.format("%.0f", maxHealth) or "?",
        tostring(reason))
    if activeCrystal == object then
        activeCrystal = nil
        task.defer(selectCrystal)
    end
end

local function bindCrystalHealth(object, info)
    if info.healthBound then return end
    local health, maxHealth, source = crystalHealth(object)
    info.lastHealth = health
    info.lastMaxHealth = maxHealth
    if health ~= nil then
        say("OBJECTIF #%d vie initiale : %.0f%s", info.id, health,
            maxHealth and string.format("/%.0f", maxHealth) or "")
    end
    if source and source:IsA("Humanoid") then
        info.healthBound = true
        connect(source.HealthChanged, function(value)
            if not running or info.finished then return end
            if untargetableCrystalHealth(value, source.MaxHealth) then
                ignoreHighHealthCrystal(object, value, source.MaxHealth,
                    "changement Humanoid")
                return
            end
            if info.lastHealth and value < info.lastHealth then
                info.damageSeen = true
                say("OBJECTIF #%d DEGATS : -%.0f, reste %.0f", info.id,
                    info.lastHealth - value, value)
            end
            info.lastHealth = value
            if value <= 0 then finishCrystal(object, "PV a zero") end
        end, crystalConnections)
        connect(source:GetPropertyChangedSignal("MaxHealth"), function()
            if not running or info.finished then return end
            info.lastMaxHealth = source.MaxHealth
            if untargetableCrystalHealth(source.Health, source.MaxHealth) then
                ignoreHighHealthCrystal(object, source.Health, source.MaxHealth,
                    "MaxHealth Humanoid")
            end
        end, crystalConnections)
    elseif source and (source:IsA("NumberValue") or source:IsA("IntValue")) then
        info.healthBound = true
        connect(source:GetPropertyChangedSignal("Value"), function()
            local value = source.Value
            if untargetableCrystalHealth(value, nil) then
                ignoreHighHealthCrystal(object, value, nil,
                    "changement NumberValue")
                return
            end
            if info.lastHealth and value < info.lastHealth then
                info.damageSeen = true
                say("OBJECTIF #%d DEGATS : -%.0f, reste %.0f", info.id,
                    info.lastHealth - value, value)
            end
            info.lastHealth = value
            if value <= 0 then finishCrystal(object, "PV a zero") end
        end, crystalConnections)
    elseif not info.attributeBound then
        info.attributeBound = true
        connect(object.AttributeChanged, function(name)
            if not HEALTH_NAMES[name] and name ~= "MaxHealth" then return end
            local value, maximum = crystalHealth(object)
            if untargetableCrystalHealth(value, maximum) then
                ignoreHighHealthCrystal(object, value, maximum,
                    "attribut " .. tostring(name))
                return
            end
            if typeof(value) ~= "number" then return end
            if info.lastHealth and value < info.lastHealth then
                info.damageSeen = true
                say("OBJECTIF #%d DEGATS : -%.0f, reste %.0f", info.id,
                    info.lastHealth - value, value)
            end
            info.lastHealth = value
            info.lastMaxHealth = maximum
            if value <= 0 then finishCrystal(object, "PV a zero") end
        end, crystalConnections)
    end
end

local function registerCrystal(object, spawnedNow, allowFallback)
    local explicitObject, explicitMode = crystalRootFrom(object)
    local explicit = explicitObject ~= nil
    object = explicitObject or (allowFallback and damageableRootFrom(object) or nil)
    if not object or belongsToPlayer(object) then return end
    local existing = crystals[object]
    if existing and not existing.finished then return existing end
    if existing and existing.finished then crystals[object] = nil end
    if boss and (object == boss or object:IsDescendantOf(boss)) then return end
    local loweredName = string.lower(object.Name)
    if string.find(loweredName, CONFIG.BOSS_NAME, 1, true)
        or object:GetAttribute("Boss") == true then
        return
    end
    local inEffects = object:FindFirstAncestor("Effects") ~= nil
    if not explicit and inEffects then return end

    local pos = pivotOf(object)
    -- Mesure depuis le centre de la salle quand il est connu : un petit
    -- cristal tombe a l'oppose du boss reste dans l'arene et doit etre casse.
    local centre = arenaCenter()
    local maxDistance = explicit and CONFIG.CRYSTAL_SCAN_RADIUS
        or (crystalRoomCenter and CONFIG.ARENA_RADIUS
            or CONFIG.FALLBACK_TARGET_RADIUS)
    if pos and centre and (pos - centre).Magnitude > maxDistance then return end

    -- Un decor ancien simplement nomme Crystal ne doit pas voler la visee.
    -- Une apparition observee en direct est acceptee meme sans PV repliques ;
    -- lors d'un scan initial, il faut un vrai indicateur de vie.
    local health, maxHealth = crystalHealth(object)
    if untargetableCrystalHealth(health, maxHealth) then
        ignoreHighHealthCrystal(object, health, maxHealth, "apparition")
        return
    end
    if health ~= nil and health <= 0 then return end
    if not explicit and (not bossAlive() or health == nil or health <= 0) then return end
    if explicit and not spawnedNow and health == nil then return end
    -- Hors des dossiers de cristaux confirmes, un simple nom ne suffit pas :
    -- le petit cristal doit aussi exposer une vraie valeur de vie.
    if explicitMode == "nom" and health == nil then return end
    if explicit and health == nil and inEffects
        and loweredHasAny(object.Name, {"effect", "particle", "glow", "beam", "aura"}) then
        return
    end

    crystalSerial += 1
    crystalStats.seen += 1
    local info = {
        id = crystalSerial,
        spawnedAt = os.clock(),
        finished = false,
        explicit = explicit,
        priority = explicit and 100 or (spawnedNow and 50 or 10),
        aimPart = crystalAimPart(object),
        shotEffects = 0,
    }
    crystals[object] = info
    local targetHumanoid = object:IsA("Model")
        and object:FindFirstChildOfClass("Humanoid") or nil
    say("OBJECTIF #%d SPAWN : %s [%s] mode=%s display=%s%s pos=%s", info.id,
        object:GetFullName(), object.ClassName,
        explicit and explicitMode or "nouveau modele attaquable",
        targetHumanoid and targetHumanoid.DisplayName or "-", attributesOf(object),
        pos and describe(pos, 1) or "?")
    if info.aimPart then
        say("OBJECTIF #%d POINT VISE : %s pos=%s taille=%s", info.id,
            info.aimPart:GetFullName(), describe(info.aimPart.Position, 1),
            describe(info.aimPart.Size, 1))
    end
    bindCrystalHealth(object, info)
    connect(object.DescendantAdded, function(child)
        if info.finished then return end
        if not info.healthBound
            and (child:IsA("Humanoid") or HEALTH_NAMES[child.Name]) then
            bindCrystalHealth(object, info)
        end
        if child:IsA("BasePart") then
            local aimPart = crystalAimPart(object)
            if aimPart and aimPart ~= info.aimPart then
                info.aimPart = aimPart
                say("OBJECTIF #%d NOUVEAU POINT VISE : %s pos=%s", info.id,
                    aimPart:GetFullName(), describe(aimPart.Position, 1))
            end
        end
    end, crystalConnections)
    connect(object.AncestryChanged, function(_, parent)
        if not parent then finishCrystal(object, "disparu/detruit") end
    end, crystalConnections)
    selectCrystal()
    return info
end

local function crystalCandidateSignature(object)
    local health, maxHealth = crystalHealth(object)
    local signature = {
        descendants = 0,
        visibleParts = 0,
        queryParts = 0,
        enabledEffects = 0,
        health = health,
        maxHealth = maxHealth,
        attributes = "",
        visualState = "",
    }
    local attributeParts = {}
    local visualParts = {}
    local function collectAttributes(item)
        for name, value in pairs(item:GetAttributes()) do
            attributeParts[#attributeParts + 1] = item.Name .. "." .. name
                .. "=" .. tostring(value)
        end
    end
    collectAttributes(object)
    for _, child in ipairs(object:GetDescendants()) do
        signature.descendants += 1
        collectAttributes(child)
        if child:IsA("BasePart") then
            if child.Transparency < 0.98 then signature.visibleParts += 1 end
            local queryable = true
            pcall(function() queryable = child.CanQuery end)
            if queryable then signature.queryParts += 1 end
            visualParts[#visualParts + 1] = string.format("%s:%.3f:%s:%s:%s",
                child.Name, child.Transparency, tostring(child.Color),
                tostring(child.Material), tostring(queryable))
        elseif child:IsA("ParticleEmitter") or child:IsA("Beam")
            or child:IsA("Trail") or child:IsA("Light") then
            local enabled = false
            pcall(function() enabled = child.Enabled end)
            if enabled then signature.enabledEffects += 1 end
            visualParts[#visualParts + 1] = child.ClassName .. ":"
                .. child.Name .. ":" .. tostring(enabled)
        end
    end
    table.sort(attributeParts)
    table.sort(visualParts)
    signature.attributes = table.concat(attributeParts, "|")
    signature.visualState = table.concat(visualParts, "|")
    return signature
end

local function candidateChanged(current, baseline)
    if not current or not baseline then return false end
    -- Une relique ne devient un objectif que lorsque le jeu lui pose sa vie
    -- (Health=5M observe en jeu). Sans vie repliquee, un changement visuel ne
    -- prouve rien : le jeu ajoute puis retire un BodyPosition aux cristaux
    -- dormants, ce qui faisait passer un decor inerte pour un objectif
    -- prioritaire (priorite 100) et volait la visee a Kronax pendant des
    -- secondes. Pas de vie -> pas d'activation.
    if current.health == nil then return false end
    return current.health > 0
end

local function evaluateCrystalCandidate(object, reason)
    local candidate = crystalCandidates[object]
    if not candidate or not object.Parent then return end
    local now = os.clock()
    local signature = crystalCandidateSignature(object)

    -- Le chargement de la salle ajoute notamment OriginalThickness aux quatre
    -- modeles avant l'apparition de Kronax. Ce n'est pas une activation. Tant
    -- que le boss n'est pas vivant, on absorbe ces changements dans la base au
    -- lieu de fabriquer quatre faux objectifs.
    if not bossAlive() then
        candidate.baseline = signature
        candidate.active = false
        candidate.inactiveSince = nil
        return
    end

    if untargetableCrystalHealth(signature.health, signature.maxHealth) then
        ignoreHighHealthCrystal(object, signature.health, signature.maxHealth,
            reason)
        return
    elseif candidate.ignored then
        -- Le meme emplacement peut etre reutilise plus tard pour une vraie
        -- relique : on ne retire la blacklist qu'une fois la vie redescendue.
        candidate.ignored = false
        ignoredCrystals[object] = nil
        candidate.baseline = signature
        if signature.health == nil or signature.health <= 0 then return end
    end
    local changed = candidateChanged(signature, candidate.baseline)
    local info = crystals[object]

    if not candidate.active and changed then
        info = registerCrystal(object, true)
        if info then
            candidate.active = true
            candidate.activatedAt = now
            candidate.inactiveSince = nil
            say("RELIQUE ACTIVE : %s raison=%s visible=%d effets=%d descendants=%d",
                object:GetFullName(), tostring(reason), signature.visibleParts,
                signature.enabledEffects, signature.descendants)
        end
    elseif candidate.active then
        if signature.health ~= nil and signature.health <= 0 then
            finishCrystal(object, "PV a zero")
            candidate.active = false
            candidate.inactiveSince = nil
        elseif changed then
            candidate.inactiveSince = nil
        else
            candidate.inactiveSince = candidate.inactiveSince or now
            local focusedFor = info and info.firstShotAt
                and now - info.firstShotAt or 0
            local enoughShots = info
                and info.shotEffects >= CONFIG.CRYSTAL_VISUAL_MIN_SHOTS
            local focusConfirmed = enoughShots
                and focusedFor >= CONFIG.CRYSTAL_VISUAL_MIN_FOCUS
            if now - candidate.inactiveSince >= 0.20 and focusConfirmed then
                finishCrystal(object, "desactivee/cassee")
                candidate.active = false
                candidate.inactiveSince = nil
            elseif now - candidate.inactiveSince >= 0.20
                and info and not info.visualHoldLogged then
                info.visualHoldLogged = true
                say("OBJECTIF #%d RESTE PRIORITAIRE : signal visuel termine mais"
                        .. " destruction non prouvee (%d/%d tirs, focus %.1f/%.1f s)",
                    info.id, info.shotEffects, CONFIG.CRYSTAL_VISUAL_MIN_SHOTS,
                    focusedFor, CONFIG.CRYSTAL_VISUAL_MIN_FOCUS)
            end
        end
    elseif info and not info.finished then
        candidate.active = true
        candidate.activatedAt = now
    end
end

local function bindCrystalCandidateObject(candidate, object)
    if candidate.bound[object] then return end
    candidate.bound[object] = true
    connect(object.AttributeChanged, function(name)
        if running then
            task.defer(evaluateCrystalCandidate,
                candidate.object, "attribut " .. tostring(name))
        end
    end)
    if object:IsA("BasePart") then
        connect(object:GetPropertyChangedSignal("Transparency"), function()
            if running then
                task.defer(evaluateCrystalCandidate,
                    candidate.object, "visibilite " .. object.Name)
            end
        end)
        pcall(function()
            connect(object:GetPropertyChangedSignal("CanQuery"), function()
                if running then
                    task.defer(evaluateCrystalCandidate,
                        candidate.object, "CanQuery " .. object.Name)
                end
            end)
        end)
    elseif object:IsA("ParticleEmitter") or object:IsA("Beam")
        or object:IsA("Trail") or object:IsA("Light") then
        pcall(function()
            connect(object:GetPropertyChangedSignal("Enabled"), function()
                if running then
                    task.defer(evaluateCrystalCandidate,
                        candidate.object, "effet " .. object.Name)
                end
            end)
        end)
    elseif object:IsA("NumberValue") or object:IsA("IntValue") then
        connect(object:GetPropertyChangedSignal("Value"), function()
            if running then
                task.defer(evaluateCrystalCandidate,
                    candidate.object, "valeur " .. object.Name)
            end
        end)
    end
end

local function watchCrystalCandidate(object, index)
    if not object or crystalCandidates[object] then return end
    local candidate = {
        object = object,
        baseline = crystalCandidateSignature(object),
        active = false,
        bound = {},
        inactiveSince = nil,
    }
    crystalCandidates[object] = candidate
    bindCrystalCandidateObject(candidate, object)
    for _, child in ipairs(object:GetDescendants()) do
        bindCrystalCandidateObject(candidate, child)
    end
    connect(object.DescendantAdded, function(child)
        bindCrystalCandidateObject(candidate, child)
        task.defer(evaluateCrystalCandidate, object,
            "ajout " .. child.ClassName .. ":" .. child.Name)
    end)
    connect(object.DescendantRemoving, function(child)
        task.delay(0.05, evaluateCrystalCandidate, object,
            "retrait " .. child.ClassName .. ":" .. child.Name)
    end)
    local base = candidate.baseline
    say("CRISTAL CANDIDAT[%d] : %s visible=%d effets=%d descendants=%d",
        index, object:GetFullName(), base.visibleParts,
        base.enabledEffects, base.descendants)
end

local function refreshCrystalCandidates()
    for object in pairs(crystalCandidates) do
        evaluateCrystalCandidate(object, "surveillance")
    end
end

local function watchCrystalFolder(folder)
    if not folder or watchedCrystalFolders[folder] then return false end
    watchedCrystalFolders[folder] = true
    local centres = {}
    local children = folder:GetChildren()
    say("DOSSIER CRYSTALS : %s contient %d enfant(s)",
        folder:GetFullName(), #children)
    for index, child in ipairs(children) do
        if child:IsA("Model") or child:IsA("BasePart") then
            watchCrystalCandidate(child, index)
            local pos = pivotOf(child)
            if pos then centres[#centres + 1] = pos end
        end
    end
    connect(folder.ChildAdded, function(child)
        if not running then return end
        if child:IsA("Model") or child:IsA("BasePart") then
            watchCrystalCandidate(child, #folder:GetChildren())
            task.defer(evaluateCrystalCandidate, child,
                "nouvel emplacement")
        end
    end)
    if #centres > 0 then
        local total = Vector3.zero
        for _, pos in ipairs(centres) do total += pos end
        crystalRoomCenter = total / #centres
        say("CENTRE SALLE ESTIME PAR LES CRISTAUX : %s", describe(crystalRoomCenter, 1))
    end
    return true
end

--=====================================================================
--  Petits cristaux au sol du Corrupted
--
--  Regle unique demandee : tout destructible de l'arene dont la vie tient
--  sous 10 M est un objectif, quels que soient son nom, son dossier et sa
--  classe -- les reliques a 5 M comme les mini RecursiveRelics a 4 M. Au-dessus de
--  10 M c'est une sentinelle a vie infinie (999999999) : jamais touchee,
--  retour immediat sur Kronax.
--=====================================================================

local function inArena(object)
    local pos = pivotOf(object)
    local centre = arenaCenter()
    -- Sans position ou sans centre connu, on ne bloque pas la detection.
    if not pos or not centre then return true end
    return (pos - centre).Magnitude <= CONFIG.ARENA_RADIUS
end

local function isBossPart(object)
    if boss and (object == boss or object:IsDescendantOf(boss)) then return true end
    if object:GetAttribute("Boss") == true then return true end
    -- Porter "kronax" dans son nom ne suffit pas : un cristal de la salle peut
    -- reprendre le nom du boss. Seul un modele avec Humanoid est le boss.
    if not string.find(string.lower(object.Name), CONFIG.BOSS_NAME, 1, true) then
        return false
    end
    return object:IsA("Model")
        and object:FindFirstChildOfClass("Humanoid") ~= nil
end

-- "cible" : a casser. "sentinelle" : vie hors plafond, a ignorer.
-- nil : pas encore un objectif (dormant, decor, vie absente).
local function destructibleVerdict(health, maxHealth)
    if typeof(health) ~= "number" then return nil end
    if untargetableCrystalHealth(health, maxHealth) then return "sentinelle" end
    if health < CONFIG.CRYSTAL_MIN_TARGET_HEALTH then return nil end
    return "cible"
end

-- Journal de decouverte plafonne : si un petit cristal echappe encore a la
-- detection, le fichier montrera quand meme ce que le jeu a expose.
local function noteDiscovery(object, health, maxHealth, verdict, reason)
    if discoveryLogged >= CONFIG.DISCOVERY_LOG_MAX then return end
    if discoverySeen[object] then return end
    discoverySeen[object] = true
    discoveryLogged += 1
    say("DESTRUCTIBLE VU (%s) : %s [%s] vie=%s/%s%s via %s", verdict,
        object:GetFullName(), object.ClassName,
        health and string.format("%.0f", health) or "?",
        maxHealth and string.format("%.0f", maxHealth) or "?",
        attributesOf(object), tostring(reason))
end

local function acceptDestructible(object, reason, explicit)
    if not object or not object.Parent then return nil end
    local known = crystals[object]
    if known and not known.finished then return known end
    if ignoredCrystals[object] then return nil end
    if isBossPart(object) or belongsToPlayer(object) then return nil end
    if object:FindFirstAncestor("Effects") then return nil end

    local health, maxHealth = crystalHealth(object)
    local verdict = destructibleVerdict(health, maxHealth)
    if verdict == "sentinelle" then
        ignoreHighHealthCrystal(object, health, maxHealth, tostring(reason))
        return nil
    end
    if verdict ~= "cible" then
        if health ~= nil then
            noteDiscovery(object, health, maxHealth, "dormant/hors seuil", reason)
        end
        if not explicit then return nil end
    end
    if not explicit and not inArena(object) then
        noteDiscovery(object, health, maxHealth, "hors arene", reason)
        return nil
    end

    local info = registerCrystal(object, true, true)
    if info and not explicit then
        -- Petit cristal au sol : approche rapprochee au lieu de l'orbite.
        info.mini = true
    end
    if not info then
        -- Un destructible valide refuse par registerCrystal : c'est exactement
        -- le cas qui a fait rater les petits cristaux. On le trace une fois.
        if verdict == "cible" then
            noteDiscovery(object, health, maxHealth, "refuse a l'enregistrement",
                reason)
        end
        return nil
    end
    if not explicit then
        miniCrystalCount += 1
        say("MINI CRISTAL DETECTE : objectif #%d vie=%.0f/%s %s via %s",
            info.id, health,
            maxHealth and string.format("%.0f", maxHealth) or "?",
            object:GetFullName(), tostring(reason))
    end
    return info
end

local function queueDynamicCrystal(rootObject, reason)
    if not rootObject or not rootObject.Parent then return end
    local explicitRoot = crystalRootFrom(rootObject)
    -- L'appelant fournit deja un Model ou une BasePart : inutile de repayer
    -- une remontee d'ancetres avec sonde de vie profonde a chaque spawn.
    local resolved = explicitRoot or rootObject
    if not resolved or not resolved.Parent then return end

    -- Un des quatre emplacements fixes : la machine a candidats s'en occupe.
    if crystalCandidates[resolved] then
        task.defer(evaluateCrystalCandidate, resolved, reason)
        return
    end
    local known = crystals[resolved]
    if known and not known.finished then return end
    if ignoredCrystals[resolved] then return end
    if dynamicCrystalPending[resolved] then return end
    dynamicCrystalPending[resolved] = true
    -- Le modele est souvent parente avant de recevoir sa vie : on laisse
    -- passer une image avant de juger.
    task.delay(CONFIG.DYNAMIC_CRYSTAL_SETTLE_DELAY, function()
        dynamicCrystalPending[resolved] = nil
        if not running then return end
        acceptDestructible(resolved, reason, explicitRoot ~= nil)
    end)
end

local watchedRootCount = 0

local function watchDynamicCrystalRoot(rootObject, reason)
    if not rootObject or not rootObject.Parent then return end
    if rootObject:FindFirstAncestor("Effects") then return end
    if belongsToPlayer(rootObject) then return end
    if not dynamicCrystalWatched[rootObject]
        -- Plafond de securite : au-dela, l'objet est quand meme juge une fois,
        -- mais sans laisser de connexion permanente derriere lui.
        and watchedRootCount < 600 then
        dynamicCrystalWatched[rootObject] = true
        watchedRootCount += 1
        connect(rootObject.AttributeChanged, function(name)
            if HEALTH_NAMES[name] or name == "MaxHealth" then
                queueDynamicCrystal(rootObject,
                    "attribut dynamique " .. tostring(name))
            end
        end)
        if rootObject:IsA("Model") then
            connect(rootObject.DescendantAdded, function(child)
                if child:IsA("Humanoid") or HEALTH_NAMES[child.Name]
                    or child.Name == "MaxHealth" then
                    queueDynamicCrystal(rootObject, "vie ajoutee " .. child.Name)
                end
            end)
        end
    end
    queueDynamicCrystal(rootObject, reason)
end

local function considerDynamicCrystal(object)
    if not running or not object then return end
    -- Filtre de classe en tout premier : workspace.DescendantAdded tire des
    -- milliers de fois par combat, presque toujours pour des particules, des
    -- attachements ou des soudures. Rien d'autre ne doit couter avant ce tri.
    local isModel = object:IsA("Model")
    local isPart = not isModel and object:IsA("BasePart")
    if not isModel and not isPart then
        local isHealthValue = object:IsA("Humanoid")
            or ((object:IsA("NumberValue") or object:IsA("IntValue"))
                and (HEALTH_NAMES[object.Name] or object.Name == "MaxHealth"))
        if not isHealthValue then return end
        if object:FindFirstAncestor("Effects") then return end
        local rootObject = object:FindFirstAncestorOfClass("Model")
            or (object.Parent and object.Parent:IsA("BasePart") and object.Parent or nil)
        if rootObject then
            watchDynamicCrystalRoot(rootObject,
                "vie ajoutee " .. object.ClassName .. ":" .. object.Name)
        end
        return
    end
    if object:FindFirstAncestor("Effects") then return end

    local explicitRoot = crystalRootFrom(object)
    if explicitRoot then
        watchDynamicCrystalRoot(explicitRoot,
            "spawn " .. object.ClassName .. ":" .. object.Name)
        return
    end

    if isModel then
        -- Un petit cristal au sol arrive comme un modele quelconque : ni le
        -- dossier Crystals, ni un nom connu. On le surveille et c'est sa vie
        -- qui decidera s'il devient un objectif.
        watchDynamicCrystalRoot(object, "spawn Model:" .. object.Name)
        return
    end

    -- Une part isolee n'est retenue que si elle porte deja une vie ou un nom
    -- plausible, sinon chaque debris ferait travailler le script.
    if quickHealth(object) ~= nil
        or loweredHasAny(object.Name, CONFIG.MINI_CRYSTAL_KEYWORDS) then
        watchDynamicCrystalRoot(object, "spawn BasePart:" .. object.Name)
    end
end

--  Balayage incremental de l'arene ------------------------------------------
--  Couvre le cas ou le jeu ne cree rien : il rallume un modele deja pose au
--  sol. Budget fixe par passe -> cout constant, aucun GetDescendants global.

local sweepQueue = {}

local function arenaContainers()
    local containers = {}
    local seen = {}
    local function add(object)
        if object and not seen[object] and object.Name ~= "Effects" then
            seen[object] = true
            containers[#containers + 1] = object
        end
    end
    local map = workspace:FindFirstChild("Map")
    local dungeon = map and map:FindFirstChild("TimeRaidDungeon")
    if dungeon then
        add(dungeon)
        -- Deuxieme niveau : le jeu range souvent les objets de phase dans un
        -- sous-dossier du donjon.
        for _, child in ipairs(dungeon:GetChildren()) do
            if child:IsA("Folder") or child:IsA("Model") then add(child) end
        end
    end
    for _, name in ipairs({"Crystals", "Objects", "Interactables", "Debris",
        "Runtime", "Temp", "Mobs"}) do
        add(workspace:FindFirstChild(name))
    end
    add(workspace)
    return containers
end

local function refillSweepQueue()
    table.clear(sweepQueue)
    for _, container in ipairs(arenaContainers()) do
        if container.Parent or container == workspace then
            for _, child in ipairs(container:GetChildren()) do
                if child:IsA("Model") or child:IsA("BasePart") then
                    sweepQueue[#sweepQueue + 1] = child
                end
            end
        end
    end
    sweepChildIndex = 1
end

local function inspectSweepEntry(object)
    if not object.Parent then return end
    if crystalCandidates[object] or ignoredCrystals[object] then return end
    local known = crystals[object]
    if known and not known.finished then return end
    -- Sonde rapide uniquement : pas de descente recursive dans le balayage.
    local health, maxHealth = quickHealth(object)
    if health == nil then return end
    if destructibleVerdict(health, maxHealth) == nil then return end
    acceptDestructible(object, "balayage arene", false)
end

local function sweepArena()
    -- La file n'est reconstruite qu'une fois le cycle termine : reconstruire
    -- en cours de route remettrait l'index a 1 et les derniers objets ne
    -- seraient jamais inspectes.
    if #sweepQueue == 0 or sweepChildIndex > #sweepQueue then
        refillSweepQueue()
    end
    -- Budget adaptatif : un cycle complet tient toujours en quatre passes,
    -- meme si la salle contient beaucoup d'objets.
    local budget = math.max(CONFIG.ARENA_SWEEP_BUDGET,
        math.ceil(#sweepQueue / 4))
    while budget > 0 and sweepChildIndex <= #sweepQueue do
        inspectSweepEntry(sweepQueue[sweepChildIndex])
        sweepChildIndex += 1
        budget -= 1
    end
end

local function dropStuckTarget()
    local object = activeCrystal
    if not object then return end
    local info = crystals[object]
    if not info or info.finished or info.damageSeen then return end
    local since = info.acquiredAt or info.spawnedAt
    if os.clock() - since < CONFIG.CRYSTAL_STUCK_TIMEOUT then return end

    -- Les quatre modeles fixes sont reutilises plusieurs fois pendant le
    -- combat. Les blacklister ici rendrait leur prochaine vraie activation
    -- invisible. On termine seulement cette tentative et on reprend une base
    -- propre; un futur Health/BodyPosition pourra les reactiver normalement.
    local candidate = crystalCandidates[object]
    if candidate then
        candidate.active = false
        candidate.activatedAt = nil
        candidate.inactiveSince = nil
        candidate.baseline = crystalCandidateSignature(object)
        ignoredCrystals[object] = nil
        say("OBJECTIF #%d RELACHE SANS BLACKLIST : emplacement fixe reutilisable",
            info.id)
        finishCrystal(object, "aucun degat, emplacement conserve")
        return
    end

    -- Incassable en pratique : ne jamais rester bloque dessus.
    ignoredCrystals[object] = true
    say("OBJECTIF #%d ABANDONNE : aucun degat en %.0f s -> FOCUS KRONAX (%s)",
        info.id, CONFIG.CRYSTAL_STUCK_TIMEOUT, object:GetFullName())
    finishCrystal(object, "aucun degat, abandonne")
end

local function hookDynamicCrystals()
    -- Aucun dump : seuls les nouveaux objets plausibles declenchent une
    -- analyse differee, et le balayage complete ce que l'evenement rate.
    connect(workspace.DescendantAdded, considerDynamicCrystal)
    say("mini cristaux : detection dynamique + balayage arene actifs")
end

local function scanCrystals()
    -- Chemin confirme en jeu : evite de materialiser toute la liste des
    -- descendants de Workspace au lancement et lors des nouvelles difficultes.
    local map = workspace:FindFirstChild("Map")
    local dungeon = map and map:FindFirstChild("TimeRaidDungeon")
    local folder = dungeon and dungeon:FindFirstChild("Crystals")
    if folder then return watchCrystalFolder(folder) end

    -- Repli natif si le dossier n'est pas encore range au chemin habituel.
    folder = workspace:FindFirstChild("Crystals", true)
    return folder and watchCrystalFolder(folder) or false
end

local function combatTarget()
    -- La cible ne change que sur un evenement de relique ou sa fin. Evite les
    -- recherches recursives dans les quatre modeles a chaque RenderStepped.
    local crystal = activeCrystal
    local info = crystal and crystals[crystal] or nil
    if not crystalAlive(crystal, info) then crystal = selectCrystal() end
    if crystal then return crystal end
    return bossAlive() and boss or nil
end

local function aimPosition(target)
    target = target or combatTarget()
    local info = target and crystals[target] or nil
    local part = info and info.aimPart or nil
    if part and part.Parent and (part == target or part:IsDescendantOf(target)) then
        return part.Position
    end
    return pivotOf(target) or bossPosition()
end

local function recentAbilityText()
    local now = os.clock()
    for index = #recentAbilities, 1, -1 do
        local entry = recentAbilities[index]
        if now - entry.at <= 6 then
            return string.format(" apres %s (+%.2fs, annonce %.0f)",
                entry.name, now - entry.at, entry.damage)
        end
    end
    return ""
end

local function watchBoss(model)
    disconnectList(bossConnections)
    boss = model
    bossHumanoid = model and model:FindFirstChildOfClass("Humanoid") or nil
    if not bossHumanoid then return end
    bossLastHealth = bossHumanoid.Health
    bossSeenAt = os.clock()
    bossInitialPosition = pivotOf(model)
    local dungeonName = string.lower(tostring(model:GetAttribute("Dungeon") or ""))
    local corrupted = string.find(string.lower(model.Name), "corrupted", 1, true)
        ~= nil or string.find(dungeonName, "corr", 1, true) ~= nil
    heroicState.mode = not corrupted and (dungeonName == "heroictimeraid"
        or bossHumanoid.MaxHealth >= 190000000)
    heroicState.motionPhase = orbitAngle
    heroicState.targetedUntil = 0
    heroicState.targetedLabel = nil
    heroicState.anchorBlend = 0
    heroicState.anchor = nil
    heroicState.radiusX = CONFIG.HEROIC_THRONE_RADIUS_X
    heroicState.radiusZ = CONFIG.HEROIC_THRONE_RADIUS_Z
    heroicState.losGoal = nil
    heroicState.losGoalUntil = 0
    heroicState.travelKickAt = 0
    heroicState.travelKicks = 0
    say("BOSS DETECTE : %s, %.0f/%.0f PV%s", model.Name,
        bossHumanoid.Health, bossHumanoid.MaxHealth, attributesOf(model))
    say("PROFIL MOUVEMENT : %s",
        heroicState.mode and "HEROIC CONTINU" or "CORRUPTED CLASSIQUE")

    connect(bossHumanoid.HealthChanged, function(health)
        if not running then return end
        if bossLastHealth and health < bossLastHealth then
            say("BOSS DEGATS : -%.0f, reste %.0f/%.0f, cible=%s",
                bossLastHealth - health, health, bossHumanoid.MaxHealth,
                activeCrystal and ("OBJECTIF #" .. crystals[activeCrystal].id) or "KRONAX")
        end
        bossLastHealth = health
        if health <= 0 then
            say("=== KRONAX TERMINE en %.2f s ===", os.clock() - bossSeenAt)
            releaseAttack()
            writeLog(true)
        end
    end, bossConnections)

    if CONFIG.VERBOSE_DIAGNOSTICS then
        connect(model.AttributeChanged, function(name)
            say("boss.%s = %s", name, describe(model:GetAttribute(name), 2))
        end, bossConnections)
        connect(model.DescendantAdded, function(object)
            if object:IsA("Animation") then
                say("boss animation ajoutee : %s id=%s", object.Name, object.AnimationId)
            end
        end, bossConnections)
        local animator = bossHumanoid:FindFirstChildOfClass("Animator")
            or bossHumanoid:WaitForChild("Animator", 3)
        if animator then
            connect(animator.AnimationPlayed, function(track)
                local animation = track.Animation
                say("ANIMATION KRONAX : %s id=%s longueur=%.2f vitesse=%.2f",
                    track.Name, animation and animation.AnimationId or "?",
                    track.Length, track.Speed)
            end, bossConnections)
        end
    end
end

local sightParams = RaycastParams.new()
pcall(function() sightParams.FilterType = Enum.RaycastFilterType.Exclude end)
pcall(function() sightParams.IgnoreWater = true end)

--  Plafond d'altitude ------------------------------------------------------
--  Le jeu applique des degats au-dessus de 120 studs DE HAUTEUR REELLE
--  (mesure en jeu). Se referer au pivot de Kronax ne suffit pas : il flotte
--  et se deplace, donc "68 studs au-dessus du boss" ne dit rien sur
--  l'altitude reelle. On mesure le sol de la salle par rayon vers le bas.

local floorParams = RaycastParams.new()
pcall(function() floorParams.FilterType = Enum.RaycastFilterType.Exclude end)
pcall(function() floorParams.IgnoreWater = true end)

local cachedFloorY = nil
local cachedFloorAt = -math.huge

local function arenaFloorY()
    local now = os.clock()
    if cachedFloorY and now - cachedFloorAt < 2 then return cachedFloorY end

    -- Origine preferee : le centre de la salle. Le sol de l'arene est plat, et
    -- tirer depuis le joueur risquerait de tomber dans un trou ou sur un decor
    -- suspendu et de fausser l'altitude.
    local from = crystalRoomCenter
        and Vector3.new(crystalRoomCenter.X, crystalRoomCenter.Y + 50,
            crystalRoomCenter.Z)
        or (root and root.Position) or pivotOf(boss)
    if not from then return cachedFloorY end
    local ignored = {character}
    local effects = workspace:FindFirstChild("Effects")
    if effects then ignored[#ignored + 1] = effects end
    local mobs = workspace:FindFirstChild("Mobs")
    if mobs then ignored[#ignored + 1] = mobs end
    floorParams.FilterDescendantsInstances = ignored
    local hit = workspace:Raycast(from, Vector3.new(0, -600, 0), floorParams)
    if hit then
        cachedFloorY = hit.Position.Y
        cachedFloorAt = now
        return cachedFloorY
    end

    -- Repli sans rayon : la base des reliques repose sur le sol de la salle.
    if crystalRoomCenter and not cachedFloorY then
        cachedFloorY = crystalRoomCenter.Y - 25
        cachedFloorAt = now
    end
    return cachedFloorY
end

-- Altitude maximale autorisee, en coordonnee monde.
local function altitudeCeilingY()
    local floor = arenaFloorY()
    if not floor then return nil end
    return floor + CONFIG.ALTITUDE_LIMIT - CONFIG.ALTITUDE_MARGIN
end

local function checkSight(from, target)
    local ignored = {character}
    if boss then ignored[#ignored + 1] = boss end
    if activeCrystal then ignored[#ignored + 1] = activeCrystal end
    local effects = workspace:FindFirstChild("Effects")
    if effects then ignored[#ignored + 1] = effects end
    local mobs = workspace:FindFirstChild("Mobs")
    if mobs then ignored[#ignored + 1] = mobs end
    sightParams.FilterDescendantsInstances = ignored
    local result = workspace:Raycast(from, target - from, sightParams)
    return result and result.Instance or nil
end

local function restoreNoclip()
    for part, value in pairs(oldCollision) do
        if part.Parent then part.CanCollide = value end
    end
    table.clear(characterParts)
    table.clear(oldCollision)
end

local function trackCharacterParts()
    if partAdded then partAdded:Disconnect() end
    if partRemoved then partRemoved:Disconnect() end
    restoreNoclip()
    local function add(object)
        if not object:IsA("BasePart") or characterParts[object] then return end
        characterParts[object] = true
        oldCollision[object] = object.CanCollide
        object.CanCollide = false
    end
    for _, object in ipairs(character:GetDescendants()) do add(object) end
    partAdded = character.DescendantAdded:Connect(add)
    partRemoved = character.DescendantRemoving:Connect(function(object)
        characterParts[object] = nil
        oldCollision[object] = nil
    end)
end

local IMPACT_KEYS = {
    {"TargetPosition", true},
    {"Goal", true},
    {"EndPosition", false},
    {"Pivot", false},
    {"Position", true},
}

local function impactPoint(data)
    for _, entry in ipairs(IMPACT_KEYS) do
        local value = data[entry[1]]
        local point = nil
        if typeof(value) == "Vector3" then point = value end
        if typeof(value) == "CFrame" then point = value.Position end
        if point then
            local duration = tonumber(data.Duration)
            if not duration or duration <= 0 then
                duration = entry[2] and CONFIG.HAZARD_LIFETIME or 1.0
            end
            return point, math.clamp(duration, 0.35, 8.0), entry[1]
        end
    end
    return nil, 0, nil
end

--  Profils reels des capacites ----------------------------------------------
--  Tires des payloads du serveur releves en combat et des degats observes.
--  Avant, TOUTES les zones valaient 24 studs / 2.2 s : des chiffres inventes
--  dont dependait chaque decision d'esquive.
local ABILITY_PROFILES = {
    -- WarningRadius=140 annonce par le serveur, ChargeUp=3 s.
    chronoshockwave = {radius = 140, lifetime = 1.5},
    -- Nova centree sur Kronax (payload sans TargetPosition, seulement Pivot),
    -- ChargeUp=1 s. Des degats ont ete pris a 84 studs du boss : 24 etait
    -- tres sous-estime.
    timestreamdecay = {radius = 95, lifetime = 1.4},
    -- LingerDuration=1.5 s et HitInterval=0.25 s : l'effet tape en continu.
    -- Le rayon de 60 est une enveloppe de securite issue des passages touches
    -- a 42-46 studs lors du run v0.25 ; la geometrie est un couloir, ajoute
    -- plus bas entre ModelPosition et TargetPosition.
    timelinedestruction = {
        radius = CONFIG.TIMELINE_CORRIDOR_RADIUS,
        lifetime = 2.0,
        source = "profil securise v0.26",
    },
    temporaltear = {radius = 30, lifetime = 2.2},
    -- ChargeUp=0.25 s et projectile x4 : il faut s'ecarter des la detection.
    flashforward = {radius = 30, lifetime = 1.0},
}

local function abilityProfile(name)
    return ABILITY_PROFILES[string.lower(tostring(name))]
end

local function payloadRadius(data, name)
    -- 1. Ce que le serveur annonce explicitement.
    for _, key in ipairs({"Radius", "AOERadius", "HitboxRadius",
        "WarningRadius", "Width"}) do
        local value = tonumber(data[key])
        if value and value > 0 then
            return math.clamp(value, 6, CONFIG.HAZARD_RADIUS_MAX), key
        end
    end
    local size = data.Size
    if typeof(size) == "Vector3" then
        return math.clamp(math.max(size.X, size.Z) / 2, 6,
            CONFIG.HAZARD_RADIUS_MAX), "Size"
    end
    -- 2. Le profil mesure pour cette capacite.
    local profile = abilityProfile(name)
    if profile then return profile.radius, profile.source or "profil mesure" end
    -- 3. Faute de mieux : le rayon reel des telegraphes au sol (56 studs de
    --    diametre releves dans le journal), et non plus une valeur inventee.
    return CONFIG.HAZARD_DEFAULT_RADIUS, "telegraphe mesure"
end

local SPATIAL_HAZARDS = {
    timelinedestruction = "hard",
    -- v0.32 : TemporalTear repasse en "hard", donc esquivee AUSSI en Heroic.
    -- Le classement "follower" partait d'un fait exact (le serveur verrouille
    -- la position au lancer, on ne peut pas fuir le coup en cours) mais d'une
    -- conclusion fausse. MESURE : le saut d'esquive ne sauve pas du coup en
    -- cours, il eloigne du lancer SUIVANT. Corrupted, zone esquivee :
    -- impact= median 80 studs, 2 coups sur 36 lancers. Heroic, zone ignoree :
    -- impact= 47/30/66/59/88/5, et le 5 a tue. On rend donc au Heroic les
    -- memes sauts que ceux qui ont fait le record en Corrupted.
    temporaltear = "hard",
    -- FlashForward balaie tout le segment Kronax -> cible. Contrairement a
    -- TemporalTear, ce n'est pas seulement un ancien point laisse derriere le
    -- joueur : son couloir doit rester actif dans le solveur Heroic.
    flashforward = "hard",
}

local function addHazard(label, position, radius, lifetime, source, part,
        segmentStart)
    if typeof(position) ~= "Vector3" then return end
    local loweredLabel = string.lower(tostring(label))
    local spatialKind = SPATIAL_HAZARDS[loweredLabel]
    local hazard = {
        label = label,
        pos = position,
        radius = math.clamp(radius or CONFIG.HAZARD_DEFAULT_RADIUS, 4,
            CONFIG.HAZARD_RADIUS_MAX),
        expires = os.clock() + (lifetime or CONFIG.HAZARD_LIFETIME),
        source = source,
        part = part,
        segmentStart = typeof(segmentStart) == "Vector3" and segmentStart or nil,
        -- Ces attaques visent la position 3D exacte du joueur. Les traiter
        -- comme des colonnes X/Z infinies supprimait toute esquive verticale.
        spatial = spatialKind ~= nil,
        follower = spatialKind == "follower",
        engaged = false,
    }
    hazards[#hazards + 1] = hazard
    -- Une seule pluie ajoute 40 zones : un plafond a 60 evincait les dangers
    -- encore actifs juste apres.
    if #hazards > 140 then table.remove(hazards, 1) end
    return hazard
end

local function ignoreForHeroicFlow(hazard, heroicFlow)
    if not heroicFlow then return false end
    -- TemporalTear verrouille une ancienne position : la tangente continue est
    -- sa vraie esquive. En revanche, un Warning visuel inconnu reste une preuve
    -- de danger et ne doit jamais etre neutralise globalement.
    return hazard.follower
end

local function hazardDistance(position, hazard)
    if hazard.segmentStart then
        if hazard.spatial then
            return segmentDistance3D(position, hazard.segmentStart, hazard.pos)
        end
        return flatSegmentDistance(position, hazard.segmentStart, hazard.pos)
    end
    if hazard.spatial then return (position - hazard.pos).Magnitude end
    return flatDistance(position, hazard.pos)
end

local function hazardEdge(position, hazard)
    return hazardDistance(position, hazard) - hazard.radius
end

local function warningPart(object)
    if object:IsA("BasePart") then
        local current = object
        for _ = 1, 5 do
            if not current then break end
            if loweredHasAny(current.Name, CONFIG.WARNING_KEYWORDS) then
                return object
            end
            current = current.Parent
        end
    end
    if (object:IsA("Model") or object:IsA("Folder"))
        and loweredHasAny(object.Name, CONFIG.WARNING_KEYWORDS) then
        return object:FindFirstChildWhichIsA("BasePart", true)
    end
    return nil
end

local function registerWarning(object)
    local part = warningPart(object)
    if not part then return end
    if warningParts[part] then return end
    warningParts[part] = true
    local radius = math.max(part.Size.X, part.Size.Z) / 2
    if radius < 2 then radius = CONFIG.WARNING_DEFAULT_RADIUS end
    radius = math.min(radius, CONFIG.WARNING_RADIUS_MAX)
    addHazard("telegraphe " .. object.Name, part.Position, radius,
        CONFIG.WARNING_LIFETIME, "effect", part)
    say("TELEGRAPHE : %s pos=%s taille=%s rayon prudent=%.0f",
        object:GetFullName(), describe(part.Position, 1), describe(part.Size, 1), radius)
end

local function observeEffect(object)
    if not running then return end
    local warningRelated = loweredHasAny(object.Name, CONFIG.WARNING_KEYWORDS)
    if not warningRelated and object:IsA("BasePart") then
        local current = object.Parent
        for _ = 1, 5 do
            if not current then break end
            if loweredHasAny(current.Name, CONFIG.WARNING_KEYWORDS) then
                warningRelated = true
                break
            end
            current = current.Parent
        end
    end
    if warningRelated then
        task.defer(registerWarning, object)
    end
    if object.Name == CONFIG.SHOT_EFFECT and mouseHeld then
        lastShotEffect = os.clock()
        if not shotSeenThisHold then
            shotSeenThisHold = true
            say("effet de tir observe pendant le maintien du minigun")
        end
        if activeCrystal and crystals[activeCrystal] then
            local info = crystals[activeCrystal]
            info.shotEffects += 1
            if not info.firstShotAt then
                info.firstShotAt = os.clock()
                say("OBJECTIF #%d : premier tir confirme %.3f s apres spawn",
                    info.id, info.firstShotAt - info.spawnedAt)
            end
            local impact = pivotOf(object)
            local targetPos = aimPosition()
            if info.shotEffects <= 3 or info.shotEffects % 5 == 0 then
                say("OBJECTIF #%d IMPACT #%d : pos=%s ecart_cible=%s", info.id,
                    info.shotEffects, impact and describe(impact, 1) or "?",
                    impact and targetPos
                        and string.format("%.1f", (impact - targetPos).Magnitude) or "?")
            end
        end
    end
end

local function hookEffects()
    local effects = workspace:FindFirstChild("Effects")
        or workspace:WaitForChild("Effects", 15)
    if not effects then
        say("(!) workspace.Effects absent : telegraphes non observes")
        return
    end
    connect(effects.DescendantAdded, observeEffect)
    say("workspace.Effects branche uniquement pour les nouveaux tirs/telegraphes")
end

local function hookAbilities()
    local ok, remote = pcall(function()
        return ReplicatedStorage:WaitForChild("ReplicatedStorage", 15)
            :WaitForChild("Packages", 10):WaitForChild("Knit", 10)
            :WaitForChild("Services", 10):WaitForChild("AttackService", 10)
            :WaitForChild("RE", 10):WaitForChild("AbilityFired", 10)
    end)
    if not ok or not remote then
        say("(!) AbilityFired introuvable : telegraphes visuels seulement")
        return
    end

    connect(remote.OnClientEvent, function(data)
        if not running or typeof(data) ~= "table" then return end
        local model = data.Model
        local fromBoss = model ~= nil and (model == boss
            or (typeof(model) == "Instance"
                and string.find(string.lower(model.Name), CONFIG.BOSS_NAME, 1, true)))
        if not fromBoss then return end

        local name = data.AbilityName
        if typeof(name) == "Instance" then name = name.Name end
        name = tostring(name)
        local loweredName = string.lower(name)
        local isChronoShockwave = loweredName == "chronoshockwave"
        local isTimeline = loweredName == "timelinedestruction"
        local isTemporalTear = loweredName == "temporaltear"
        local isFlashForward = loweredName == "flashforward"
        local damage = tonumber(data.Damage) or 0
        local impact, lifetime, impactKey = impactPoint(data)
        local origin = data.ModelPosition
        if typeof(origin) ~= "Vector3" then origin = pivotOf(model) end
        local impactDistance = root and impact and flatDistance(root.Position, impact) or nil
        local originDistance = root and origin and flatDistance(root.Position, origin) or nil
        local abilityAt = os.clock()

        if heroicState.mode and (isTemporalTear or isFlashForward) then
            local hold = isTemporalTear and CONFIG.HEROIC_TEMPORAL_HOLD
                or CONFIG.HEROIC_FLASH_HOLD
            heroicState.targetedUntil = math.max(
                heroicState.targetedUntil, abilityAt + hold)
            heroicState.targetedLabel = name
            cachedDodgeGoal = nil
            cachedDodgeGoalUntil = 0
            say("MOUVEMENT HEROIC CONTINU : %s, tangente maintenue %.2f s",
                name, hold)
        end

        abilityCounts[name] = (abilityCounts[name] or 0) + 1
        recentAbilities[#recentAbilities + 1] = {
            at = abilityAt, name = name, damage = damage, impact = impact,
        }
        if #recentAbilities > 30 then table.remove(recentAbilities, 1) end

        say("CAPACITE #%d %s : degats annonces=%.0f distLanceur=%s impact=%s via=%s",
            abilityCounts[name], name, damage,
            originDistance and string.format("%.0f", originDistance) or "?",
            impactDistance and string.format("%.0f", impactDistance) or "-",
            impactKey or "-")
        if isTimeline
            and typeof(origin) == "Vector3" and typeof(impact) == "Vector3" then
            timelineCasts[#timelineCasts + 1] = {
                id = abilityCounts[name], at = abilityAt,
                origin = origin, target = impact,
            }
            if #timelineCasts > 12 then table.remove(timelineCasts, 1) end
            say("SONDE TIMELINE #%d : origine=%s cible=%s joueur=%s"
                    .. " charge=%s projectileX=%s linger=%s intervalle=%s",
                abilityCounts[name], describe(origin, 1), describe(impact, 1),
                root and describe(root.Position, 1) or "?",
                tostring(data.ChargeUp), tostring(data.ProjectileSpeedMultiplier),
                tostring(data.LingerDuration), tostring(data.HitInterval))
        end
        -- Une seule ligne par TYPE de capacite (6 au total sur un combat).
        -- C'est la seule facon de savoir si le jeu envoie un rayon et une
        -- duree : sans ca le script se rabat sur 24 studs / 2.2 s inventes.
        if CONFIG.LOG_ABILITY_PAYLOAD and abilityCounts[name] == 1 then
            local payload = describe(data, 4)
            if #payload > 2400 then payload = payload:sub(1, 2400) .. "..." end
            say("PAYLOAD COMPLET %s = %s", name, payload)
        end

        if isChronoShockwave then
            -- Zone posee tout de suite : les 3 s de ChargeUp sont justement
            -- le temps dont on dispose pour sortir des 140 studs. Une seconde
            -- zone est recentree a la detonation, au cas ou Kronax se serait
            -- deplace pendant la charge.
            local chargeUp = tonumber(data.ChargeUp) or 3
            local radius = tonumber(data.WarningRadius) or 140
            local centreOfBlast = typeof(origin) == "Vector3" and origin
                or pivotOf(model)
            if centreOfBlast then
                addHazard(name, centreOfBlast, radius,
                    chargeUp + CONFIG.SHOCKWAVE_LINGER, "shockwave", nil)
            end
            task.delay(chargeUp, function()
                if not running then return end
                local at = bossPosition() or centreOfBlast
                if at then
                    addHazard(name, at, radius, CONFIG.SHOCKWAVE_LINGER,
                        "shockwave", nil)
                end
            end)
            say("ONDE CHRONOSHOCKWAVE : rayon %.0f, detonation dans %.2f s,"
                    .. " puis salve de %.2f s a 0.515 s par tick -- ESQUIVEE",
                radius, chargeUp, CONFIG.SHOCKWAVE_LINGER)
        elseif typeof(data.RainPositions) == "table" and damage > 0 then
            -- Le serveur envoie les positions exactes des 40 gouttes. Les
            -- resumer en UNE zone de 160 studs autour du centre couvrait
            -- toute la salle et rendait l'esquive impossible : plus aucun
            -- point sur n'existait. On enregistre chaque impact reel, ce qui
            -- laisse le script se faufiler entre les gouttes.
            local drops = 0
            for index = 1, CONFIG.RAIN_MAX_DROPS do
                local point = data.RainPositions[index]
                if typeof(point) == "Vector3" then
                    drops += 1
                    -- La goutte N tombe a INTERVAL x (N-1) apres le lancer.
                    -- Sa zone est donc ARMEE juste avant, puis retiree juste
                    -- apres : au lieu de 40 zones mortes en 3 s, il y en a
                    -- environ 4 vivantes au bon endroit au bon moment,
                    -- pendant toute la duree reelle de la pluie.
                    local armAt = math.max(0,
                        CONFIG.RAIN_DROP_INTERVAL * (index - 1)
                            - CONFIG.RAIN_DROP_LEAD)
                    task.delay(armAt, function()
                        if not running then return end
                        addHazard(name, point, CONFIG.RAIN_DROP_RADIUS,
                            CONFIG.RAIN_DROP_WINDOW, "rain", nil)
                    end)
                end
            end
            if drops > 0 then
                say("PLUIE %s : %d gouttes programmees, rayon %d chacune,"
                        .. " une toutes les %.2f s soit %.1f s de pluie"
                        .. " (DelayBetween serveur=%s ignore, mesure fausse)",
                    name, drops, CONFIG.RAIN_DROP_RADIUS,
                    CONFIG.RAIN_DROP_INTERVAL,
                    CONFIG.RAIN_DROP_INTERVAL * (drops - 1),
                    tostring(data.DelayBetween))
            elseif impact then
                local radius, radiusSource = payloadRadius(data, name)
                addHazard(name, impact, radius, lifetime, "ability", nil)
                say("ZONE CAPACITE %s : rayon=%.0f (%s), duree=%.2f s, pos=%s",
                    name, radius, radiusSource, lifetime, describe(impact, 1))
            end
        elseif damage > 0 and impact then
            local radius, radiusSource = payloadRadius(data, name)
            local profile = abilityProfile(name)
            if profile and profile.lifetime then lifetime = profile.lifetime end
            if isTimeline then
                -- Un champ Radius/Width plus petit dans une autre variante ne
                -- doit jamais annuler l'enveloppe validee par le run v0.25.
                if radius < CONFIG.TIMELINE_CORRIDOR_RADIUS then
                    radius = CONFIG.TIMELINE_CORRIDOR_RADIUS
                    radiusSource = radiusSource .. " + plancher v0.26"
                end
                local linger = tonumber(data.LingerDuration) or 0
                local dodgeHold = math.max(CONFIG.TIMELINE_DODGE_HOLD,
                    linger + CONFIG.TIMELINE_LINGER_MARGIN)
                lifetime = math.max(lifetime, dodgeHold,
                    CONFIG.CORRIDOR_LIFETIME)
                cachedDodgeGoal = nil
                cachedDodgeGoalUntil = 0
                addHazard(name, impact, radius, lifetime,
                    "timeline-corridor", nil, origin)
                -- La ZONE vit desormais 3.50 s, mais le VERROU reste a 1.75 s.
                -- Les lier aurait bloque le script en mode esquive en
                -- permanence (Timeline part toutes les 1.05 s), alors que
                -- l'orbite n'a encaisse aucun coup du run v0.34.
                local lockUntil = abilityAt + dodgeHold
                timelineDodgeUntil = math.max(timelineDodgeUntil, lockUntil)
                activeDodgeUntil = math.max(activeDodgeUntil,
                    timelineDodgeUntil)
                say("COULOIR TIMELINE #%d : rayon=%.0f (%s), duree=%.2f s"
                        .. ", verrou=%.2f s, origine=%s, cible=%s",
                    abilityCounts[name], radius, radiusSource, lifetime,
                    lockUntil - abilityAt, describe(origin, 1), describe(impact, 1))
            elseif isFlashForward and typeof(origin) == "Vector3" then
                -- Meme mecanique de projectile (ProjectileSpeedMultiplier=4) :
                -- le couloir reste dangereux bien apres les 2.20 s modelisees.
                -- Coup a 27.10 du run v0.35 : 31.6 studs de l'axe d'un couloir
                -- age de 2.88 s, deja supprime depuis 0.68 s.
                lifetime = math.max(lifetime, CONFIG.CORRIDOR_LIFETIME)
                addHazard(name, impact, radius, lifetime,
                    "flash-corridor", nil, origin)
                say("COULOIR CAPACITE %s : rayon=%.0f (%s), duree=%.2f s"
                        .. ", origine=%s, cible=%s",
                    name, radius, radiusSource, lifetime,
                    describe(origin, 1), describe(impact, 1))
            else
                addHazard(name, impact, radius, lifetime, "ability", nil)
                say("ZONE CAPACITE %s : rayon=%.0f (%s), duree=%.2f s, pos=%s",
                    name, radius, radiusSource, lifetime, describe(impact, 1))
            end
        elseif damage >= humanoid.MaxHealth * CONFIG.TARGETED_BURST_RATIO
            and (data.Target == character or data.Target == player) then
            targetedBurstUntil = math.max(targetedBurstUntil,
                os.clock() + CONFIG.TARGETED_BURST_SECONDS)
            orbitAngle += math.pi * 0.70
            say("ESQUIVE REFLEXE : %s cible le joueur sans point d'impact", name)
        end
    end)
    say("AbilityFired branche pour Kronax")
end

local function guiObjectActuallyVisible(object)
    if not object.Visible or object.TextTransparency >= 0.98 then return false end
    local current = object.Parent
    while current and current ~= player do
        if current:IsA("GuiObject") and not current.Visible then return false end
        if current:IsA("CanvasGroup") and current.GroupTransparency >= 0.98 then
            return false
        end
        current = current.Parent
    end
    return true
end

local function interestingMessage(label)
    if not label:IsA("TextLabel") and not label:IsA("TextButton") then return false end
    local text = label.Text
    if text == "" then return false end
    if label:FindFirstAncestor("MessagesUI") then return true end
    return loweredHasAny(text, {"kronax", "crystal", "cristal", "destroy", "break", "second", "time"})
end

local function scanMessages()
    local playerGui = player:FindFirstChild("PlayerGui")
    if not playerGui then return end
    local now = os.clock()
    for _, label in ipairs(playerGui:GetDescendants()) do
        if (not ui or not label:IsDescendantOf(ui))
            and interestingMessage(label) and guiObjectActuallyVisible(label) then
            local text = string.gsub(label.Text, "[%s\r\n]+", " ")
            local state = messageState[label]
            if not state or state.text ~= text then
                if not state or now - state.at >= 0.75
                    or loweredHasAny(text, CONFIG.CRYSTAL_KEYWORDS) then
                    say("MESSAGE UI : %s", text)
                    messageState[label] = {text = text, at = now}
                end
            end
        end
    end
end

local function nearestHazard(position, heroicFlow)
    local now = os.clock()
    local nearest = nil
    local nearestEdge = math.huge
    for index = #hazards, 1, -1 do
        local hazard = hazards[index]
        if hazard.part and hazard.part.Parent then hazard.pos = hazard.part.Position end
        if hazard.expires <= now or (hazard.part and not hazard.part.Parent) then
            table.remove(hazards, index)
        elseif not ignoreForHeroicFlow(hazard, heroicFlow) then
            local edge = hazardEdge(position, hazard)
            if edge < nearestEdge then nearest, nearestEdge = hazard, edge end
        end
    end
    return nearest, nearestEdge
end

local function pointSafe(point, heroicFlow)
    for _, hazard in ipairs(hazards) do
        if not ignoreForHeroicFlow(hazard, heroicFlow) then
            local threshold = hazard.radius + CONFIG.HAZARD_ESCAPE_MARGIN
            if hazardDistance(point, hazard) < threshold then return false end
        end
    end
    return true
end

-- Le rayon de detection des cristaux doit rester large (420). Ce rectangle ne
-- borne que les destinations du joueur. Il est centre sur la moyenne stable
-- des quatre reliques fixes, jamais sur Kronax qui se deplace pendant le run.
-- Rentree RADIALE dans le cylindre : le cap du point est conserve, donc deux
-- points exterieurs differents donnent deux points interieurs differents.
-- Le facteur SOFT garantit qu'on ne se pose jamais exactement sur le bord.
local function cylinderPoint(point, heroic, shrink)
    if not crystalRoomCenter then return point end
    local limit = CONFIG.MOVEMENT_ARENA_RADIUS - CONFIG.MOVEMENT_ARENA_INSET
    if heroic then limit = limit - CONFIG.HEROIC_ARENA_EDGE_MARGIN end
    limit = math.max(0, limit - (shrink or 0))
    local dx = point.X - crystalRoomCenter.X
    local dz = point.Z - crystalRoomCenter.Z
    local distance = math.sqrt(dx * dx + dz * dz)
    if distance <= limit then return point end
    local scale = limit * CONFIG.MOVEMENT_ARENA_SOFT / math.max(distance, 0.001)
    return Vector3.new(crystalRoomCenter.X + dx * scale, point.Y,
        crystalRoomCenter.Z + dz * scale)
end

local function clampToMovementArena(point)
    return cylinderPoint(point, false)
end

-- Le cadre absolu garde 5 studs sur la mesure des murs. Le Heroic travaille
-- encore 10 studs plus a l'interieur : les detours rapides ne placent ainsi ni
-- le joueur ni la ligne du minigun dans le mur, meme avec le noclip.
function heroicState.clampArena(point)
    return cylinderPoint(point, true)
end

local function insideMovementArena(point)
    if not crystalRoomCenter then return true end
    return flatDistance(point, crystalRoomCenter)
        <= CONFIG.MOVEMENT_ARENA_RADIUS - CONFIG.MOVEMENT_ARENA_INSET + 0.01
end

-- Un point d'arrivee sur ne suffit pas avec les grands Lerp de l'esquive :
-- le trajet lui-meme ne doit traverser ni un cercle ni le couloir Timeline.
-- Si le joueur commence deja dans un danger, une trajectoire qui en sort et
-- s'en eloigne est autorisee ; passer plus profond avant de ressortir ne l'est
-- pas.
local function movementPathSafe(from, destination, heroicFlow)
    for _, hazard in ipairs(hazards) do
        if ignoreForHeroicFlow(hazard, heroicFlow) then continue end
        local threshold = hazard.radius + CONFIG.HAZARD_ESCAPE_MARGIN
        local startDistance = hazardDistance(from, hazard)
        local endDistance = hazardDistance(destination, hazard)
        if endDistance < threshold then return false end

        if startDistance < threshold then
            local early = from + (destination - from) * 0.15
            if endDistance <= startDistance
                or hazardDistance(early, hazard) + 0.5 < startDistance then
                return false
            end
        else
            local crossing
            if hazard.spatial then
                -- Le mouvement et le danger sont 3D. Un echantillonnage tous
                -- les ~18 studs suffit face au plus petit seuil de 52 studs et
                -- evite de rejeter une descente sure a cause de sa projection X/Z.
                crossing = math.huge
                local span = (destination - from).Magnitude
                local steps = math.clamp(math.ceil(span / 18), 3, 18)
                for step = 0, steps do
                    local point = from + (destination - from) * (step / steps)
                    crossing = math.min(crossing, hazardDistance(point, hazard))
                end
            elseif hazard.segmentStart then
                crossing = flatSegmentsDistance(from, destination,
                    hazard.segmentStart, hazard.pos)
            else
                crossing = flatSegmentDistance(hazard.pos, from, destination)
            end
            if crossing < threshold then return false end
        end
    end
    return true
end

--  Approche des petits cristaux ---------------------------------------------
--  Les RecursiveRelics font 12 x 17 studs et reposent a 9 studs du sol,
--  parfois encastres dans un mur. Les tirer depuis l'orbite, a ~94 studs de
--  haut, ratait : ecarts de 78 et 114 studs releves, et les tirs partaient
--  sur Kronax. On se place donc juste a cote, du cote degage.

local function miniApproachGoal(aim)
    local best = nil
    local bestBlocked = nil
    local height = CONFIG.MINI_APPROACH_HEIGHT
    local distance = CONFIG.MINI_APPROACH_DISTANCE

    -- Huit cotes autour du cristal, puis la verticale : le premier point avec
    -- une ligne de tir degagee et hors danger gagne.
    for step = 0, 7 do
        local angle = (math.pi * 2 / 8) * step
        local point = clampToMovementArena(aim + Vector3.new(
            math.cos(angle) * distance, height, math.sin(angle) * distance))
        local blocked = checkSight(point, aim) ~= nil
        if not blocked and pointSafe(point) then return point, "cote degage" end
        if not blocked and not best then best = point end
        if not bestBlocked then bestBlocked = point end
    end

    local above = clampToMovementArena(aim + Vector3.new(0, distance, 0))
    if checkSight(above, aim) == nil and pointSafe(above) then
        return above, "au-dessus"
    end
    if best then return best, "cote degage (dans un danger)" end

    -- Encastre de tous les cotes : on se colle au cristal. Le noclip permet
    -- d'entrer dans le mur, et a bout portant le tir ne peut plus rater.
    return clampToMovementArena(aim
        + Vector3.new(0, CONFIG.MINI_CONTACT_HEIGHT, 0)), "au contact"
end

local function baseOrbitGoal(centre, radius, height, angle)
    return centre + Vector3.new(math.cos(angle) * radius, height,
        math.sin(angle) * radius)
end

function heroicState.updateOrbit(centre, delta)
    if not crystalRoomCenter then
        heroicState.anchorBlend = 1
        heroicState.anchor = centre
        heroicState.radiusX = CONFIG.ORBIT_RADIUS
        heroicState.radiusZ = CONFIG.ORBIT_RADIUS
        return
    end

    local departure = bossInitialPosition
        and flatDistance(centre, bossInitialPosition)
        or CONFIG.HEROIC_DEPARTURE_BLEND_END
    local targetBlend = math.clamp(
        (departure - CONFIG.HEROIC_DEPARTURE_BLEND_START)
            / math.max(1, CONFIG.HEROIC_DEPARTURE_BLEND_END
                - CONFIG.HEROIC_DEPARTURE_BLEND_START),
        0, 1)
    local response = 1 - math.exp(-CONFIG.HEROIC_ANCHOR_RESPONSE * delta)
    heroicState.anchorBlend += (targetBlend - heroicState.anchorBlend) * response
    local blend = heroicState.anchorBlend
    heroicState.radiusX = CONFIG.HEROIC_THRONE_RADIUS_X
        + (CONFIG.ORBIT_RADIUS - CONFIG.HEROIC_THRONE_RADIUS_X) * blend
    heroicState.radiusZ = CONFIG.HEROIC_THRONE_RADIUS_Z
        + (CONFIG.ORBIT_RADIUS - CONFIG.HEROIC_THRONE_RADIUS_Z) * blend

    local rawX = crystalRoomCenter.X + (centre.X - crystalRoomCenter.X) * blend
    local rawZ = crystalRoomCenter.Z + (centre.Z - crystalRoomCenter.Z) * blend
    -- L'ellipse entiere doit tenir dans le cylindre : on borne donc l'ancre
    -- au rayon utile MOINS le grand rayon de l'ellipse.
    local anchor = cylinderPoint(Vector3.new(rawX, centre.Y, rawZ), true,
        math.max(heroicState.radiusX, heroicState.radiusZ))
    heroicState.anchor = Vector3.new(anchor.X, centre.Y, anchor.Z)
end

function heroicState.orbitPoint(angle, worldY, scale)
    local anchor = heroicState.anchor
    if not anchor then return nil end
    local radiusScale = scale or 1
    return Vector3.new(
        anchor.X + math.cos(angle) * heroicState.radiusX * radiusScale,
        worldY,
        anchor.Z + math.sin(angle) * heroicState.radiusZ * radiusScale)
end

local function safeOrbitGoal(centre, preferred, aim, keepMoving, heroicFlow)
    local now = os.clock()
    if cachedDodgeGoal and now < cachedDodgeGoalUntil
        and (not keepMoving
            or (not root or (cachedDodgeGoal - root.Position).Magnitude > 10))
        and insideMovementArena(cachedDodgeGoal)
        and pointSafe(cachedDodgeGoal, heroicFlow)
        and (not root
            or movementPathSafe(root.Position, cachedDodgeGoal, heroicFlow)) then
        return cachedDodgeGoal
    end

    local radii = {30, CONFIG.ORBIT_RADIUS,
        CONFIG.ORBIT_RADIUS + CONFIG.DODGE_RADIUS_EXTRA, 110}
    local largeFlatHazard = false
    for _, hazard in ipairs(hazards) do
        if not ignoreForHeroicFlow(hazard, heroicFlow) then
            local effectiveRadius = hazard.radius + CONFIG.HAZARD_ESCAPE_MARGIN
            if effectiveRadius
                > CONFIG.ORBIT_RADIUS + CONFIG.DODGE_RADIUS_EXTRA then
                if not hazard.spatial then largeFlatHazard = true end
                local centreGap = hazardDistance(centre, hazard)
                local needed = effectiveRadius - centreGap + 8
                radii[#radii + 1] = math.clamp(needed,
                    CONFIG.ORBIT_RADIUS + CONFIG.DODGE_RADIUS_EXTRA,
                    CONFIG.DODGE_RADIUS_MAX)
            end
        end
    end
    if largeFlatHazard then radii[#radii + 1] = CONFIG.DODGE_RADIUS_MAX end
    local floor = arenaFloorY()
    local dodgeAltitudes = heroicFlow and CONFIG.HEROIC_DODGE_ALTITUDES
        or CONFIG.DODGE_ALTITUDES
    local localRadii = heroicFlow and CONFIG.HEROIC_DODGE_LOCAL_RADII
        or CONFIG.DODGE_LOCAL_RADII
    local localDirections = heroicFlow and CONFIG.HEROIC_DODGE_LOCAL_DIRECTIONS
        or CONFIG.DODGE_LOCAL_DIRECTIONS
    local dodgeYs = {}
    for _, altitude in ipairs(dodgeAltitudes) do
        -- Le sol est normalement connu avant le combat via les quatre reliques.
        -- Le repli conserve des hauteurs utilisables si le rayon n'a pas repondu.
        dodgeYs[#dodgeYs + 1] = floor and (floor + altitude)
            or (centre.Y + altitude)
    end
    local candidates = {}
    -- MESURE v0.34 : un candidat hors cylindre etait RABATTU sur le bord.
    -- Des dizaines de candidats differents atterrissaient donc sur le meme
    -- cercle de rayon 155.2, qui devenait un aimant : 67 % du combat passe en
    -- ESQUIVE a un rayon median de 155, et 6 coups sur 7 encaisses a 155.2
    -- pile. Au bord, la moitie des directions de fuite est perdue, le
    -- deplacement net s'effondre, et TemporalTear passe : 9 lancers sur 25
    -- avec impact <= 19 studs contre 2 sur 36 dans le run Corrupted record.
    -- On ne garde donc que les points DEJA interieurs. Le bord reste
    -- atteignable, mais seulement si un vrai candidat s'y trouve.
    local function addCandidate(point)
        local bounded = heroicFlow and heroicState.clampArena(point)
            or clampToMovementArena(point)
        if (bounded - point).Magnitude > 0.01 then return end
        candidates[#candidates + 1] = bounded
    end
    addCandidate(preferred)
    if crystalRoomCenter then
        for _, worldY in ipairs(dodgeYs) do
            addCandidate(Vector3.new(crystalRoomCenter.X,
                worldY, crystalRoomCenter.Z))
        end
    end
    for step = 0, CONFIG.DODGE_CANDIDATE_COUNT - 1 do
        local radius = radii[step % #radii + 1]
        local worldY = dodgeYs[math.floor(step / #radii) % #dodgeYs + 1]
        local angle = orbitAngle
            + step * math.pi * 2 / CONFIG.DODGE_CANDIDATE_COUNT
        local point = baseOrbitGoal(centre, radius, 0, angle)
        addCandidate(Vector3.new(point.X, worldY, point.Z))
    end

    -- Vrai maillage local : chaque rayon et chaque direction sont testes a
    -- CHAQUE altitude. Les trois rayons Heroic couvrent un petit ecart, une
    -- sortie normale et une grande AoE au sol sans sauter directement au mur.
    if root then
        for step = 0, localDirections - 1 do
            local angle = orbitAngle
                + step * math.pi * 2 / localDirections
            for _, radius in ipairs(localRadii) do
                for _, worldY in ipairs(dodgeYs) do
                    addCandidate(Vector3.new(
                        root.Position.X + math.cos(angle) * radius,
                        worldY,
                        root.Position.Z + math.sin(angle) * radius))
                end
            end
        end
    end

    -- Le perimetre est un dernier recours reserve aux grosses AoE AU SOL.
    -- Timeline/Temporal/Flash n'ajoutent plus jamais les coins 170/110.
    if largeFlatHazard then
        if crystalRoomCenter then
            -- Perimetre = cercle, plus les quatre cotes d'un rectangle dont
            -- les coins tombaient dans le mur.
            local rim = CONFIG.MOVEMENT_ARENA_RADIUS
                - CONFIG.MOVEMENT_ARENA_INSET
            local sampleCount = math.max(4,
                CONFIG.MOVEMENT_ARENA_EDGE_SAMPLES * 2)
            for step = 0, sampleCount - 1 do
                local angle = math.pi * 2 * step / sampleCount
                local worldY = dodgeYs[step % #dodgeYs + 1]
                addCandidate(Vector3.new(
                    crystalRoomCenter.X + math.cos(angle) * rim,
                    worldY,
                    crystalRoomCenter.Z + math.sin(angle) * rim))
            end
        else
            -- Avant que les quatre reliques ne soient chargees, conserver le
            -- repli circulaire historique. Il sera borne des que le centre est
            -- disponible, normalement avant le debut du combat.
            for step = 0, CONFIG.DODGE_CANDIDATE_COUNT - 1 do
                local angle = orbitAngle
                    + step * math.pi * 2 / CONFIG.DODGE_CANDIDATE_COUNT
                local worldY = dodgeYs[step % #dodgeYs + 1]
                local point = baseOrbitGoal(centre,
                    CONFIG.DODGE_RADIUS_MAX, 0, angle)
                addCandidate(Vector3.new(point.X, worldY, point.Z))
            end
        end
    end

    local ranked = {}
    local improving = {}
    local fallback = {}
    local function clearanceAt(point)
        local clearance = math.huge
        for _, hazard in ipairs(hazards) do
            if not ignoreForHeroicFlow(hazard, heroicFlow) then
                clearance = math.min(clearance, hazardEdge(point, hazard))
            end
        end
        return clearance == math.huge and 100 or clearance
    end
    local currentClearance = root and clearanceAt(root.Position) or 100
    for _, point in ipairs(candidates) do
        local clearance = clearanceAt(point)
        local travel = root and (point - root.Position).Magnitude or 0
        fallback[#fallback + 1] = {
            point = point, clearance = clearance, travel = travel,
        }
        if insideMovementArena(point) and pointSafe(point, heroicFlow)
            and (not root
                or movementPathSafe(root.Position, point, heroicFlow)) then
            -- Une fois la marge necessaire obtenue, rester proche vaut mieux
            -- que gagner encore 100 studs et sauter au coin oppose du cadre.
            local score = math.min(clearance,
                CONFIG.DODGE_CLEARANCE_SCORE_CAP) * 0.35
                - travel * CONFIG.DODGE_TRAVEL_SCORE_WEIGHT
            ranked[#ranked + 1] = {point = point, score = score}
        elseif insideMovementArena(point) and root
            and clearance > currentClearance + 1 then
            local early = root.Position + (point - root.Position) * 0.15
            if clearanceAt(early) + 0.5 >= currentClearance then
                improving[#improving + 1] = {
                    point = point,
                    score = clearance * 2 - travel * 0.05,
                }
            end
        end
    end
    table.sort(ranked, function(a, b) return a.score > b.score end)
    table.sort(improving, function(a, b) return a.score > b.score end)
    table.sort(fallback, function(a, b)
        if a.clearance == b.clearance then return a.travel < b.travel end
        return a.clearance > b.clearance
    end)

    local best = nil
    for index = 1, math.min(8, #ranked) do
        local point = ranked[index].point
        if not aim or checkSight(point, aim) == nil then
            best = point
            break
        end
    end
    -- La survie prime sur la ligne de tir si aucun des meilleurs points n'a
    -- les deux. Le clic et la visee restent maintenus et reprendront des que
    -- le prochain recalcul retrouve une ligne libre.
    if not best and ranked[1] then best = ranked[1].point end
    -- Empilement exceptionnel sans trajet totalement sur : progresser vers
    -- le point qui augmente la marge, ou a defaut vers le meilleur point de
    -- l'anneau. Ne jamais retomber sur preferred a 58 studs, connu dangereux.
    -- Si la position courante est deja sure, ne pas la quitter par un trajet
    -- que movementPathSafe vient precisement de refuser.
    local rootInArena = root and insideMovementArena(root.Position) or false
    local rootIsSafe = rootInArena
        and pointSafe(root.Position, heroicFlow) or false
    if not best and rootIsSafe and not keepMoving then best = root.Position end
    if not best and improving[1] then best = improving[1].point end
    if not best and fallback[1]
        and fallback[1].clearance > currentClearance then
        best = fallback[1].point
    end
    -- Si un ancien mouvement nous a deja laisse hors du cadre, ne jamais y
    -- rester faute de meilleur point : rentrer vers le meilleur candidat borne.
    if not best and not rootInArena and fallback[1] then
        best = fallback[1].point
    end
    if not best and keepMoving and pointSafe(preferred, heroicFlow)
        and (not root
            or movementPathSafe(root.Position, preferred, heroicFlow)) then
        best = preferred
    end
    -- Si l'empilement de zones refuse la courbe principale mais que la position
    -- courante est saine, essayer un court pas tangent avant l'ultime attente.
    if not best and keepMoving and rootIsSafe and root then
        local phase = heroicFlow and heroicState.motionPhase or orbitAngle
        local tangent = heroicFlow and heroicState.clampArena(Vector3.new(
            root.Position.X - math.sin(phase) * 18,
            preferred.Y,
            root.Position.Z + math.cos(phase) * 18))
            or clampToMovementArena(Vector3.new(
                root.Position.X - math.sin(phase) * 18,
                preferred.Y,
                root.Position.Z + math.cos(phase) * 18))
        if pointSafe(tangent, heroicFlow)
            and movementPathSafe(root.Position, tangent, heroicFlow) then
            best = tangent
        end
    end
    if not best and root then best = root.Position end
    cachedDodgeGoal = best
    cachedDodgeGoalUntil = now + (keepMoving and 0.08
        or CONFIG.DODGE_REPLAN_INTERVAL)
    return best
end

local function enforceMinimumHorizontalDistance(goal, centre)
    local offset = (goal - centre) * Vector3.new(1, 0, 1)
    if offset.Magnitude >= CONFIG.MIN_HORIZONTAL_DISTANCE then return goal end
    local fallbackAngle = heroicState.mode and heroicState.motionPhase or orbitAngle
    local direction = offset.Magnitude > 1 and offset.Unit
        or Vector3.new(math.cos(fallbackAngle), 0, math.sin(fallbackAngle))
    return Vector3.new(
        centre.X + direction.X * CONFIG.MIN_HORIZONTAL_DISTANCE,
        goal.Y,
        centre.Z + direction.Z * CONFIG.MIN_HORIZONTAL_DISTANCE)
end

-- Quand la cible est derriere un element de decor, continuer vers l'avant sur
-- la meme courbe et tester quelques angles proches. Le clic reste maintenu : on
-- change seulement de cote/hauteur jusqu'a retrouver une ligne de tir.
function heroicState.sightGoal(preferred, aim)
    if not root or not sightBlocker or not heroicState.anchor then return preferred end
    local now = os.clock()
    if heroicState.losGoal and now < heroicState.losGoalUntil then
        return heroicState.losGoal
    end
    local worldY = preferred.Y
    local floor = arenaFloorY()
    if floor then
        worldY = math.max(worldY, floor + math.min(
            CONFIG.HEROIC_DODGE_ALTITUDES[#CONFIG.HEROIC_DODGE_ALTITUDES],
            holdHeight + 12))
    end
    for step = 0, 5 do
        local candidate = step == 0
            and Vector3.new(preferred.X, worldY, preferred.Z)
            or heroicState.orbitPoint(heroicState.motionPhase + step * 0.32, worldY)
        if candidate then
            candidate = heroicState.clampArena(
                enforceMinimumHorizontalDistance(candidate, bossPosition() or aim))
            if checkSight(candidate, aim) == nil and pointSafe(candidate, true)
                and movementPathSafe(root.Position, candidate, true) then
                heroicState.losGoal = candidate
                heroicState.losGoalUntil = now + 0.12
                return candidate
            end
        end
    end
    heroicState.losGoal = nil
    heroicState.losGoalUntil = 0
    return preferred
end

local function bindCharacterSignals()
    disconnectList(characterConnections)
    local lastHealth = humanoid.Health
    connect(humanoid.HealthChanged, function(health)
        if not running then return end
        if health < lastHealth then
            minigun.interrupt("degats recus")
            local lost = lastHealth - health
            local rounded = tostring(math.floor(lost + 0.5))
            damageBuckets[rounded] = (damageBuckets[rounded] or 0) + 1
            local centre = bossPosition()
            local hazard, edge = nil, nil
            if root then hazard, edge = nearestHazard(root.Position) end
            local floor = arenaFloorY()
            local altitude = floor and root and (root.Position.Y - floor) or nil
            local overCeiling = altitude ~= nil
                and altitude > CONFIG.ALTITUDE_LIMIT - CONFIG.ALTITUDE_MARGIN
            say("DEGATS JOUEUR : -%.0f, reste %.0f/%.0f, distBoss=%s, altSol=%s%s%s%s",
                lost, health, humanoid.MaxHealth,
                centre and string.format("%.0f", (root.Position - centre).Magnitude) or "?",
                altitude and string.format("%.0f", altitude) or "?",
                overCeiling and " (!) AU-DESSUS DU PLAFOND" or "",
                hazard and string.format(", danger=%s bord=%+.0f", hazard.label, edge) or "",
                recentAbilityText())
            -- MESURE, aucun effet sur le comportement. Le champ "apres X"
            -- de la ligne ci-dessus ne nomme que la DERNIERE capacite lancee :
            -- il ne prouve rien sur la source du coup, et c'est lui qui a fait
            -- croire que TemporalTear frappait a bord=+35. Ces deux lignes
            -- donnent la distance signee a TOUTES les zones actives et la
            -- fenetre complete des lancers. C'est la seule facon de mesurer
            -- les vrais rayons au lieu de continuer a les inventer.
            if root then
                local rows = {}
                for _, zone in ipairs(hazards) do
                    local zoneEdge = hazardEdge(root.Position, zone)
                    rows[#rows + 1] = {
                        edge = zoneEdge,
                        text = string.format("%s bord=%+.0f r=%.0f",
                            zone.label, zoneEdge, zone.radius),
                    }
                end
                table.sort(rows, function(a, b) return a.edge < b.edge end)
                local shown = {}
                for index = 1, math.min(6, #rows) do
                    shown[#shown + 1] = rows[index].text
                end
                say("  ZONES ACTIVES AU COUP (%d) : %s", #rows,
                    #shown > 0 and table.concat(shown, " | ") or "aucune")
                say("  POSITION JOUEUR AU COUP : %s | Kronax : %s",
                    describe(root.Position, 1),
                    centre and describe(centre, 1) or "?")
            end
            local window = {}
            for index = #recentAbilities, 1, -1 do
                local entry = recentAbilities[index]
                local age = os.clock() - entry.at
                if age > 2.5 then break end
                window[#window + 1] = string.format("%s(+%.2fs)",
                    entry.name, age)
            end
            say("  LANCERS 2.5 s AVANT LE COUP : %s",
                #window > 0 and table.concat(window, " ") or "aucun")
            if root then
                local damageAt = os.clock()
                recordMotionSample(damageAt, root.Position)
                logTimelineEvidence(damageAt, root.Position)
            end
        elseif health > lastHealth and humanoid.MaxHealth > 0
            and lastHealth <= humanoid.MaxHealth * 0.40 then
            -- Sonde Mender sans spam : la regeneration ordinaire arrive par
            -- petits pas. On ne journalise qu'un vrai bond de vie a bas PV.
            local gained = health - lastHealth
            local meaningfulHeal = math.max(500, humanoid.MaxHealth * 0.02)
            if gained >= meaningfulHeal then
                say("SOIN IMPORTANT A BAS PV : +%.0f, %.0f -> %.0f/%.0f (Mender possible)",
                    gained, lastHealth, health, humanoid.MaxHealth)
            end
        end
        lastHealth = health
    end, characterConnections)

    connect(humanoid.Died, function()
        say("=== MORT DU JOUEUR ===")
        releaseAttack()
        writeLog(true)
    end, characterConnections)
end

local guiParent
pcall(function() guiParent = gethui and gethui() or game:GetService("CoreGui") end)
guiParent = guiParent or player:WaitForChild("PlayerGui")

local oldUi = guiParent:FindFirstChild("KronaxTestUI")
if oldUi then oldUi:Destroy() end

ui = Instance.new("ScreenGui")
ui.Name = "KronaxTestUI"
ui.ResetOnSpawn = false
ui.ZIndexBehavior = Enum.ZIndexBehavior.Global
ui.Parent = guiParent

local frame = Instance.new("Frame")
frame.Size = UDim2.new(0, 355, 0, 126)
frame.Position = UDim2.new(0, 12, 0, 120)
frame.BackgroundColor3 = Color3.fromRGB(10, 14, 24)
frame.BackgroundTransparency = 0.14
frame.ZIndex = 999999990
frame.Parent = ui
Instance.new("UICorner").Parent = frame

local statusLabel = Instance.new("TextLabel")
statusLabel.Size = UDim2.new(1, -12, 0, 92)
statusLabel.Position = UDim2.new(0, 6, 0, 4)
statusLabel.BackgroundTransparency = 1
statusLabel.TextColor3 = Color3.fromRGB(145, 220, 255)
statusLabel.Font = Enum.Font.Code
statusLabel.TextSize = 13
statusLabel.TextXAlignment = Enum.TextXAlignment.Left
statusLabel.TextYAlignment = Enum.TextYAlignment.Top
statusLabel.ZIndex = 999999991
statusLabel.Parent = frame

local stopButton = Instance.new("TextButton")
stopButton.Size = UDim2.new(0, 170, 0, 25)
stopButton.Position = UDim2.new(0, 6, 1, -29)
stopButton.BackgroundColor3 = Color3.fromRGB(195, 48, 48)
stopButton.TextColor3 = Color3.new(1, 1, 1)
stopButton.Font = Enum.Font.SourceSansBold
stopButton.TextSize = 15
stopButton.Text = "ARRETER (B)"
stopButton.ZIndex = 999999991
stopButton.Parent = frame
Instance.new("UICorner").Parent = stopButton

local function summary()
    local abilityParts = {}
    for name, count in pairs(abilityCounts) do
        abilityParts[#abilityParts + 1] = name .. "=" .. count
    end
    table.sort(abilityParts)
    local damageParts = {}
    for amount, count in pairs(damageBuckets) do
        damageParts[#damageParts + 1] = "-" .. amount .. "x" .. count
    end
    table.sort(damageParts)
    local unresolved = math.max(0,
        crystalStats.seen - crystalStats.destroyed - crystalStats.missed)
    say("RESUME OBJECTIFS : attaquables=%d detruits=%d disparus/non-confirmes=%d"
            .. " cristaux_sup10M_ignores=%d encore actifs=%d mini_detectes=%d",
        crystalStats.seen, crystalStats.destroyed, crystalStats.missed,
        crystalStats.ignored, unresolved, miniCrystalCount)
    say("RESUME CAPACITES : %s", #abilityParts > 0 and table.concat(abilityParts, ", ") or "aucune")
    say("RESUME DEGATS : %s", #damageParts > 0 and table.concat(damageParts, ", ") or "aucun")
end

local function stop(reason)
    if not running then return end
    running = false
    releaseAttack()
    minigun.watchTool(nil)
    disconnectList(characterConnections)
    disconnectList(bossConnections)
    disconnectList(crystalConnections)
    disconnectList(connections)
    if partAdded then pcall(function() partAdded:Disconnect() end) end
    if partRemoved then pcall(function() partRemoved:Disconnect() end) end
    restoreNoclip()
    summary()
    say("=== ARRET : %s ===", tostring(reason))
    writeLog(true)
    if ui then ui:Destroy() end
    if _G.StopCurrentFarm == stop then _G.StopCurrentFarm = nil end
end

_G.StopCurrentFarm = stop
connect(stopButton.MouseButton1Click, function() stop("bouton") end)
connect(UserInputService.InputBegan, function(input, processed)
    if not processed and input.KeyCode == Enum.KeyCode.B then stop("touche B") end
end)

pcall(function()
    connect(player.OnTeleport, function(state)
        if state == Enum.TeleportState.Started
            or state == Enum.TeleportState.InProgress then
            stop("teleport")
        end
    end)
end)

-- Garde principal : il vit dans le vrai farm. L'Autoexec conserve seulement
-- sa propre couche de securite autour de Start/Retry. L'un ou l'autre appelle
-- le meme arret complet pour couper les deux scripts.
task.spawn(function()
    while running do
        local playerRoot = root
        if playerRoot and playerRoot.Parent then
            for _, other in ipairs(Players:GetPlayers()) do
                if other ~= player and other.Name ~= CONFIG.PLAYER_IGNORE_NAME then
                    local otherCharacter = other.Character
                    local otherRoot = otherCharacter
                        and otherCharacter:FindFirstChild("HumanoidRootPart")
                    if otherRoot then
                        local distance = (playerRoot.Position - otherRoot.Position).Magnitude
                        if distance <= CONFIG.PLAYER_ALERT_RADIUS then
                            local reason = ("joueur proche : %s a %d studs")
                                :format(other.Name, math.floor(distance))
                            warn("[Kronax test] " .. reason .. " -> ARRET COMPLET")
                            local stopAutoexec = _G.StopKronaxAutoexec
                            if typeof(stopAutoexec) == "function" then
                                pcall(stopAutoexec, reason)
                            end
                            if running then stop(reason) end
                            return
                        end
                    end
                end
            end
        end
        task.wait(CONFIG.PLAYER_SCAN_INTERVAL)
    end
end)

-- Le premier scan s'execute avant la suite de l'initialisation. S'il vient de
-- declencher l'arret, ne pas creer de nouvelles connexions apres leur nettoyage.
task.wait()
if not running then return end

connect(player.CharacterAdded, function(newCharacter)
    if not running then return end
    releaseAttack()
    restoreNoclip()
    character = newCharacter
    humanoid = character:WaitForChild("Humanoid")
    root = character:WaitForChild("HumanoidRootPart")
    weaponName = nil
    equipping = false
    holdStartedAt = 0
    shotSeenThisHold = false
    lastShotEffect = 0
    cooldownUntil = 0
    minigun.watchTool(nil)
    minigun.burstUntil, minigun.restartAt = nil, nil
    minigun.nextEquip, minigun.nextArm = 0, 0
    minigun.missingSince, minigun.stunUntil = nil, 0
    minigun.stunMessages = setmetatable({}, {__mode = "k"})
    lastAttackTarget = nil
    activeDodgeLabel = nil
    activeDodgeUntil = 0
    targetedBurstUntil = 0
    timelineDodgeUntil = 0
    heroicState.targetedUntil = 0
    heroicState.targetedLabel = nil
    cachedDodgeGoal = nil
    cachedDodgeGoalUntil = 0
    trackCharacterParts()
    bindCharacterSignals()
    say("RESPAWN -> re-equipement du minigun")
    task.delay(0.1, function() if running then equipWeapon() end end)
end)

trackCharacterParts()
bindCharacterSignals()

-- Le minigun est deja equipe au lancement : activation H unique, tout de suite.
task.wait(0.10)
if running and humanoid.Health > 0 then
    local hSent = tapKey(Enum.KeyCode.H, 0x48)
    say("MINIGUN : H initial envoye une seule fois (%s)",
        hSent and "OK" or "ECHEC")
end

task.spawn(hookEffects)
task.spawn(hookAbilities)
task.spawn(hookDynamicCrystals)

task.spawn(function()
    -- Surveillance directe du dossier confirme des mini cristaux. Tout reste
    -- dans cette tache afin de ne pas consommer de registres locaux globaux :
    -- kronax_farm est deja proche de la limite Luau de 200.
    local watchedFolder = nil
    while running do
        local mapContent = workspace:FindFirstChild("MapContent")
        local folder = mapContent and mapContent:FindFirstChild("RecursiveRelics")
        if folder and folder ~= watchedFolder then
            watchedFolder = folder
            local function watchChild(child, reason)
                if child:IsA("Model") or child:IsA("BasePart") then
                    watchDynamicCrystalRoot(child, reason)
                end
            end
            for _, child in ipairs(folder:GetChildren()) do
                watchChild(child, "present dans RecursiveRelics")
            end
            connect(folder.ChildAdded, function(child)
                watchChild(child, "ajout direct dans RecursiveRelics")
            end)
            say("DOSSIER MINI CRISTAUX SURVEILLE : %s (%d enfant(s))",
                folder:GetFullName(), #folder:GetChildren())
        end
        if folder then
            for _, child in ipairs(folder:GetChildren()) do
                if child:IsA("Model") or child:IsA("BasePart") then
                    -- Deduplique et sort aussitot si deja connu ou >10 M.
                    queueDynamicCrystal(child, "controle direct RecursiveRelics")
                end
            end
        end
        task.wait(CONFIG.RECURSIVE_RELIC_POLL_INTERVAL)
    end
end)

task.spawn(function()
    while running do
        for part in pairs(characterParts) do
            if part.Parent and part.CanCollide then part.CanCollide = false end
        end
        task.wait(0.50)
    end
end)

task.spawn(function()
    local crystalFolderReady = scanCrystals()
    while running do
        if not crystalFolderReady then
            crystalFolderReady = scanCrystals()
        end
        refreshCrystalCandidates()
        task.wait(CONFIG.CANDIDATE_POLL_INTERVAL)
    end
end)

task.spawn(function()
    -- Premiere passe immediate : un petit cristal deja pose au sol au moment
    -- de l'injection est trouve sans attendre.
    while running do
        sweepArena()
        dropStuckTarget()
        task.wait(CONFIG.ARENA_SWEEP_INTERVAL)
    end
end)

task.spawn(function()
    while running do
        scanMessages()
        task.wait(CONFIG.MESSAGE_SCAN_INTERVAL)
    end
end)

task.spawn(function()
    while running do
        writeLog(false)
        task.wait(CONFIG.LOG_WRITE_PERIOD)
    end
end)

function minigun.blocked(now)
    local blocked = root and root.Anchored or false
    for _, object in ipairs({character, humanoid}) do
        for _, name in ipairs({"Stunned", "Status_Stunned", "Status_Stun"}) do
            local value = object:FindFirstChild(name)
            if object:GetAttribute(name) == true
                or (value and value:IsA("BoolValue") and value.Value) then
                blocked = true
            end
        end
    end
    -- Petit dossier de notifications uniquement, au plus quatre fois/s.
    if now >= minigun.nextMessageScan then
        minigun.nextMessageScan = now + 0.25
        local gui = player:FindFirstChild("PlayerGui")
        local messages = gui and gui:FindFirstChild("MessagesUI")
        local frame = messages and messages:FindFirstChild("Frame")
        if frame then
            for _, label in ipairs(frame:GetDescendants()) do
                if label:IsA("TextLabel") then
                    local rejected = guiObjectActuallyVisible(label)
                        and label.Text:lower():find("cannot use move while stunned", 1, true) ~= nil
                    if rejected and not minigun.stunMessages[label] then
                        minigun.stunUntil = now + 0.5
                        minigun.interrupt("message stun")
                    end
                    minigun.stunMessages[label] = rejected
                end
            end
        end
    end
    return blocked or now < minigun.stunUntil
end

function minigun.tick(now, desiredTarget, inCombat)
    if not running then return end
    if humanoid.Health <= 0 or not inCombat then
        releaseAttack()
        minigun.burstUntil, minigun.restartAt = nil, nil
        return
    end

    -- Prioritaire, meme en cas de stun, de perte d'outil ou de cible.
    if minigun.burstUntil and now >= minigun.burstUntil then
        releaseAttack()
        minigun.burstUntil, minigun.restartAt = nil, nil
        cooldownUntil = os.clock() + CONFIG.MINIGUN_REHOLD_DELAY
        local healed = tapKey(Enum.KeyCode.C, 0x43)
        say("MINIGUN : fin des 60 s -> pause 2 s, C soin %s", healed and "envoye" or "ECHEC")
        return
    end

    if minigun.blocked(now) then
        minigun.interrupt("stun/controle bloque")
        minigun.restartAt = math.max(minigun.restartAt or 0, now + CONFIG.MINIGUN_HIT_SETTLE)
        return
    end
    if now < cooldownUntil or now < (minigun.restartAt or 0) then return end

    local tool = equippedTool()
    local name = tool and tool.Name:lower():gsub("[^%w]", "") or ""
    local ready = name:find("minigun", 1, true) ~= nil
    if not ready then
        minigun.missingSince = minigun.missingSince or now
        if now - minigun.missingSince < CONFIG.MINIGUN_VERIFY_GRACE then return end
        minigun.interrupt("minigun absent/non active")
        minigun.watchTool(nil)
        if not desiredTarget then return end
        equipWeapon()
        return
    end
    minigun.missingSince = nil
    minigun.watchTool(tool)
    if not desiredTarget then return end
    if mouseHeld then
        holdAttack()
    elseif holdAttack() then
        local resumed = minigun.burstUntil ~= nil
        minigun.burstUntil = minigun.burstUntil or (os.clock() + CONFIG.MINIGUN_BURST_DURATION)
        minigun.restartAt = nil
        reholdCount += 1
        holdStartedAt, lastShotEffect, shotSeenThisHold = os.clock(), os.clock(), false
        say("MINIGUN HOLD #%d : %s, %.2f s restantes", reholdCount,
            resumed and "reprise" or "nouvelle rafale", minigun.burstUntil - os.clock())
    end
end

task.spawn(function()
    task.wait(0.05)
    while running do
        local inCombat = bossAlive()
        local desiredTarget = inCombat and combatTarget() or nil
        if desiredTarget ~= lastAttackTarget then
            lastAttackTarget = desiredTarget
            say("CHANGEMENT CIBLE SANS RELACHER -> %s", desiredTarget
                and desiredTarget:GetFullName() or "aucune cible")
        end
        minigun.tick(os.clock(), desiredTarget, inCombat)
        task.wait(0.08)
    end
end)

task.spawn(function()
    while running do
        if not bossAlive() then
            local found = findBoss()
            if found and found ~= boss then watchBoss(found) end
        end
        combatTarget()
        task.wait(0.75)
    end
end)

local movementAccumulator = 0
local lastUiUpdate = 0
connect(RunService.RenderStepped, function(dt)
    if not running or not root or not root.Parent then return end
    movementAccumulator += math.min(dt, 0.1)
    if movementAccumulator < 1 / 60 then return end
    local delta = movementAccumulator
    movementAccumulator = 0
    root.AssemblyLinearVelocity = Vector3.zero

    local target = combatTarget()
    local centre = bossPosition()
    local aim = aimPosition(target)
    if not centre or not aim then return end
    if target ~= activeTarget then
        activeTarget = target
        say("VISEE -> %s", target and target:GetFullName() or "aucune")
    end

    local camera = workspace.CurrentCamera
    if camera then camera.CFrame = CFrame.new(camera.CFrame.Position, aim) end

    local now = os.clock()
    local miniInfo = activeCrystal and crystals[activeCrystal] or nil
    -- L'approche rapprochee ne se declenche qu'apres MINI_TELEPORT_DELAY de
    -- visee infructueuse : si le cristal tient encore, c'est qu'un mur coupe
    -- la ligne de tir. Avant ce delai, orbite normale et tir a distance.
    local miniTarget = miniInfo ~= nil and miniInfo.mini == true
        and target == activeCrystal
        and now - (miniInfo.acquiredAt or miniInfo.spawnedAt)
            >= CONFIG.MINI_TELEPORT_DELAY
    if now - lastSightCheck >= 0.18 then
        lastSightCheck = now
        sightBlocker = checkSight(root.Position, aim)
        sightClear = sightBlocker == nil
        -- Monter ne sert a rien vers un petit cristal pose au sol : c'est
        -- l'approche rapprochee qui debloque la ligne de tir.
        if miniTarget then
            holdHeight = CONFIG.HOLD_HEIGHT
        elseif sightBlocker and now - lastHeightChange >= 0.7 then
            lastHeightChange = now
            if holdHeight < CONFIG.HOLD_HEIGHT_MAX then
                holdHeight = math.min(CONFIG.HOLD_HEIGHT_MAX,
                    holdHeight + CONFIG.HEIGHT_STEP)
                say("vue bouchee vers %s par %s -> hauteur %d",
                    activeCrystal and "OBJECTIF" or "KRONAX", sightBlocker.Name, holdHeight)
            end
        elseif sightClear and holdHeight > CONFIG.HOLD_HEIGHT then
            holdHeight = math.max(CONFIG.HOLD_HEIGHT, holdHeight - CONFIG.HEIGHT_STEP)
        end
    end

    orbitAngle += (CONFIG.ORBIT_LINEAR_SPEED / CONFIG.ORBIT_RADIUS) * delta
    local bossAtThrone = crystalRoomCenter and bossInitialPosition
        and flatDistance(centre, bossInitialPosition) <= 22
    local nearThrone = bossAtThrone and now - bossSeenAt <= 4.0
    local preferred
    if heroicState.mode then
        local targetedMotion = now < heroicState.targetedUntil
        heroicState.updateOrbit(centre, delta)
        local pathSpeed = targetedMotion and CONFIG.HEROIC_TARGET_PATH_SPEED
            or CONFIG.HEROIC_PATH_SPEED
        local referenceRadius = (heroicState.radiusX + heroicState.radiusZ) / 2
        heroicState.motionPhase += pathSpeed / referenceRadius * delta
        -- Plancher de deplacement : si le joueur n'a pas parcouru
        -- MIN_TRAVEL_DISTANCE en ligne droite sur la derniere fenetre, la
        -- trajectoire vise un autre secteur de l'ellipse. Le seuil est
        -- volontairement bas (les runs gagnes tournaient bien au-dessus) :
        -- c'est un filet anti-stagnation, pas un forcage permanent.
        if now >= (heroicState.travelKickAt or 0) then
            local windowStart = now - CONFIG.MIN_TRAVEL_WINDOW
            local reference = nil
            for index = #motionSamples, 1, -1 do
                if motionSamples[index].at <= windowStart then
                    reference = motionSamples[index].pos
                    break
                end
            end
            if reference and (root.Position - reference).Magnitude
                < CONFIG.MIN_TRAVEL_DISTANCE then
                heroicState.motionPhase += CONFIG.TRAVEL_KICK_ANGLE
                heroicState.travelKickAt = now + CONFIG.TRAVEL_KICK_COOLDOWN
                heroicState.travelKicks = (heroicState.travelKicks or 0) + 1
            end
        end
        local floor = arenaFloorY()
        local altitude = CONFIG.HEROIC_ALTITUDE_BASE
            + CONFIG.HEROIC_ALTITUDE_AMPLITUDE
                * math.sin(heroicState.motionPhase
                    * CONFIG.HEROIC_ALTITUDE_FREQUENCY)
        local worldY = floor and (floor + altitude)
            or (centre.Y + CONFIG.HOLD_HEIGHT)

        local ramp = math.clamp((now - bossSeenAt)
            / CONFIG.HEROIC_START_RAMP, 0.12, 1)
        preferred = heroicState.orbitPoint(heroicState.motionPhase, worldY, ramp)
        preferred = heroicState.clampArena(
            enforceMinimumHorizontalDistance(preferred, centre))
        if heroicState.anchorBlend < 0.95 and not usingRoomCenter then
            usingRoomCenter = true
            say("DEPART HEROIC MOBILE : ellipse centrale, transition progressive")
        elseif heroicState.anchorBlend >= 0.95 and usingRoomCenter then
            usingRoomCenter = false
            say("Kronax avance -> ancre Heroic raccordee sans saut")
        end
    elseif nearThrone then
        preferred = Vector3.new(crystalRoomCenter.X,
            centre.Y + holdHeight, crystalRoomCenter.Z)
        if not usingRoomCenter then
            usingRoomCenter = true
            say("DEPART AU CENTRE DE LA SALLE pendant que Kronax reste au trone")
        end
    else
        preferred = baseOrbitGoal(centre, CONFIG.ORBIT_RADIUS,
            holdHeight, orbitAngle)
        preferred = enforceMinimumHorizontalDistance(preferred, centre)
        if usingRoomCenter then
            usingRoomCenter = false
            say("Kronax avance -> debut de l'orbite courte")
        end
        if sightBlocker and crystalRoomCenter then
            local middle = Vector3.new(crystalRoomCenter.X,
                centre.Y + holdHeight, crystalRoomCenter.Z)
            if pointSafe(middle) and checkSight(middle, aim) == nil then
                preferred = middle
            end
        end
    end

    -- Une cible cachee ne doit plus faire tirer le minigun dans un mur en Heroic.
    -- On avance sur la courbe vers le premier cote offrant une ligne libre.
    if heroicState.mode and not miniTarget and sightBlocker then
        preferred = heroicState.sightGoal(preferred, aim)
    end

    -- Petit cristal actif : on abandonne l'orbite autour de Kronax et on se
    -- place a cote de lui. La distance minimale au boss ne s'applique pas,
    -- le cristal peut tres bien etre a ses pieds.
    local miniReason = nil
    if miniTarget then
        preferred, miniReason = miniApproachGoal(aim)
    end
    -- Garde-fou commun : meme l'approche d'un mini-cristal encastre reste
    -- dans le rectangle de l'arene. La cible, elle, reste visee ou qu'elle soit.
    local heroicFlow = heroicState.mode and not miniTarget
    preferred = heroicFlow and heroicState.clampArena(preferred)
        or clampToMovementArena(preferred)
    local miniDestinationSafe = miniTarget and pointSafe(preferred) or false
    -- Nettoie la liste puis choisit le danger qui doit reellement piloter le
    -- profil. Tear garde la tangente; Flash et les Warning reels restent evites.
    local nearest, edge = nearestHazard(root.Position, heroicFlow)
    local enteredDanger = nearest and edge <= CONFIG.HAZARD_TRIGGER_MARGIN
    if enteredDanger then
        activeDodgeUntil = math.max(activeDodgeUntil,
            now + CONFIG.DODGE_MIN_HOLD)
    elseif activeDodgeLabel and nearest and edge <= CONFIG.DODGE_RELEASE_MARGIN then
        -- Hysteresis : une fois sorti du centre du danger, on garde le point
        -- sur jusqu'a avoir une vraie marge ou jusqu'a disparition de la zone.
        activeDodgeUntil = math.max(activeDodgeUntil, now + 0.12)
    end
    local holdingDodge = activeDodgeLabel ~= nil and now < activeDodgeUntil
    local timelineLocked = now < timelineDodgeUntil
    local unsafeMiniGoal = miniTarget and not miniDestinationSafe
    local mustDodge = enteredDanger or holdingDodge or timelineLocked
        or unsafeMiniGoal
    local goal = preferred
    local response = CONFIG.MOVE_RESPONSE

    if mustDodge or now < targetedBurstUntil then
        -- Apres les 5 s reglementaires, un point rapproche du mini-cristal
        -- qui est deja hors de TOUS les dangers est lui-meme un point
        -- d'esquive valide. Cela permet le TP pendant une longue rafale
        -- Timeline sans sacrifier le cristal. Sinon l'esquive reste prioritaire.
        if miniDestinationSafe then
            goal = preferred
        elseif heroicFlow
            and pointSafe(preferred, true)
            and movementPathSafe(root.Position, preferred, true) then
            -- La trajectoire Heroic avance chaque frame : si elle est deja
            -- sure, la conserver evite un waypoint fixe et un nouvel arret.
            goal = preferred
        else
            local safe = safeOrbitGoal(centre, preferred, aim,
                heroicFlow or timelineLocked, heroicFlow)
            if safe then
                goal = safe
            end
        end
        response = CONFIG.DODGE_RESPONSE
        local label = enteredDanger and nearest.label
            or (timelineLocked and "TimelineDestruction verrouillee")
            or (unsafeMiniGoal and "danger pres OBJECTIF")
            or activeDodgeLabel or "attaque ciblee"
        if label ~= activeDodgeLabel then
            activeDodgeLabel = label
            say("ESQUIVE -> %s (bord danger=%s)", label,
                edge and string.format("%+.0f", edge) or "?")
        end
    elseif heroicFlow then
        -- Meme sans danger sous les pieds, ne jamais attendre un point fixe.
        -- Si la tangente croise une vraie zone, le solveur choisit un court
        -- detour local puis rend la main a la trajectoire continue.
        if not pointSafe(preferred, true)
            or not movementPathSafe(root.Position, preferred, true) then
            local safe = safeOrbitGoal(centre, preferred, aim, true, true)
            if safe then
                goal = safe
            end
        end
        if activeDodgeLabel then
            say("FIN ESQUIVE %s -> mouvement Heroic continu", activeDodgeLabel)
            activeDodgeLabel = nil
            activeDodgeUntil = 0
            cachedDodgeGoal = nil
            cachedDodgeGoalUntil = 0
        end
    elseif activeDodgeLabel then
        say("FIN ESQUIVE %s -> orbite courte", activeDodgeLabel)
        activeDodgeLabel = nil
        activeDodgeUntil = 0
        cachedDodgeGoal = nil
        cachedDodgeGoalUntil = 0
    end

    -- 115 reste la limite physique absolue. Le profil Heroic travaille en
    -- pratique entre 32 et 80, et ses replis locaux entre 24 et 88.
    local maximumSafeY = centre.Y + CONFIG.HOLD_HEIGHT_MAX
    local ceilingY = altitudeCeilingY()
    local usingDodgeVolume = heroicFlow or mustDodge
        or now < targetedBurstUntil
    if usingDodgeVolume and ceilingY then
        maximumSafeY = ceilingY
    elseif ceilingY and ceilingY < maximumSafeY then
        maximumSafeY = ceilingY
    end
    if goal.Y > maximumSafeY then
        goal = Vector3.new(goal.X, maximumSafeY, goal.Z)
    end
    -- Derniere garantie, appliquee a toutes les branches de mouvement.
    goal = heroicFlow and heroicState.clampArena(goal) or clampToMovementArena(goal)

    local lookAt = aim
    if (lookAt - goal).Magnitude < 1 then lookAt = goal + root.CFrame.LookVector end
    if miniTarget and miniDestinationSafe
        and (root.Position - goal).Magnitude > CONFIG.MINI_TELEPORT_DISTANCE then
        -- Teleportation immediate vers un point valide par pointSafe. Elle
        -- peut donc servir simultanement d'approche et d'esquive apres 5 s,
        -- mais n'a jamais lieu si la destination touche un danger actif.
        root.CFrame = CFrame.new(goal, lookAt)
        if miniInfo and miniInfo.teleportReason ~= miniReason then
            miniInfo.teleportReason = miniReason
            local actualDistance = flatDistance(goal, aim)
            say("TP OBJECTIF #%d : a %d studs du petit cristal (%s)",
                miniInfo.id, math.floor(actualDistance + 0.5), tostring(miniReason))
        end
    else
        -- Deplacement instantane, identique au Corrupted. MESURE v0.31 :
        -- la bride 160/190/230 studs/s laissait le joueur DANS la zone au
        -- moment du coup (bord -24, -10, +7) alors que le Lerp instantane le
        -- placait a +26 et +35 studs. TemporalTear verrouille la position au
        -- lancer et frappe 0.05 s plus tard : seul un deplacement d'un bloc
        -- sort de la zone a temps. La bride est donc supprimee.
        root.CFrame = root.CFrame:Lerp(CFrame.new(goal, lookAt),
            1 - math.exp(-response * delta))
    end
    recordMotionSample(now, root.Position)

    if now - lastTrace >= CONFIG.TRACE_PERIOD then
        lastTrace = now
        local hpPercent = humanoid.MaxHealth > 0
            and humanoid.Health / humanoid.MaxHealth * 100 or 0
        local info = activeCrystal and crystals[activeCrystal] or nil
        local floor = arenaFloorY()
        local arenaX = crystalRoomCenter
            and math.abs(root.Position.X - crystalRoomCenter.X) or nil
        local arenaZ = crystalRoomCenter
            and math.abs(root.Position.Z - crystalRoomCenter.Z) or nil
        local traceState = activeDodgeLabel and "ESQUIVE"
            or (heroicState.mode and now < heroicState.targetedUntil
                and "TANGENTE")
            or (heroicState.mode and "MOBILE") or "ORBITE"
        pushLine(stamp(string.format(
            "trace etat=%-8s cible=%-12s dist3D=%-4.0f horiz=%-4.0f haut=%-4.0f"
                .. " altSol=%-4s arenaXZ=%s/%s vue=%-7s PV=%3.0f%% dangers=%d"
                .. " sauts=%d hold=%s",
            traceState,
            info and ("OBJECTIF#" .. info.id) or "KRONAX",
            (root.Position - centre).Magnitude,
            flatDistance(root.Position, centre), root.Position.Y - centre.Y,
            floor and string.format("%.0f", root.Position.Y - floor) or "?",
            arenaX and string.format("%.0f", arenaX) or "?",
            arenaZ and string.format("%.0f", arenaZ) or "?",
            sightClear and "libre" or "BOUCHEE", hpPercent,
            #hazards, heroicState.travelKicks or 0,
            mouseHeld and "OUI" or "non")))
    end

    if now - lastUiUpdate >= 0.20 then
        lastUiUpdate = now
        local bossPercent = bossHumanoid and bossHumanoid.MaxHealth > 0
            and bossHumanoid.Health / bossHumanoid.MaxHealth * 100 or 0
        local info = activeCrystal and crystals[activeCrystal] or nil
        statusLabel.Text = string.format(
            "%s   Boss %.1f%%\n%s   PV joueur %.0f%%\n"
                .. "Orbite %.0f / haut %.0f / %s\n"
                .. "Objectifs %d vus / %d detruits / %d ignores\nLog : %s",
            boss and boss.Name or "recherche de Kronax", bossPercent,
            info and ("PRIORITE OBJECTIF #" .. info.id)
                or (activeDodgeLabel and ("ESQUIVE " .. activeDodgeLabel)
                    or (heroicState.mode and now < heroicState.targetedUntil
                        and ("TANGENTE "
                            .. tostring(heroicState.targetedLabel))
                        or "Cible : Kronax")),
            humanoid.MaxHealth > 0 and humanoid.Health / humanoid.MaxHealth * 100 or 0,
            flatDistance(root.Position, centre), root.Position.Y - centre.Y,
            sightClear and "vue libre" or "VUE BOUCHEE",
            crystalStats.seen, crystalStats.destroyed, crystalStats.ignored,
            CONFIG.LOG_FILE)
    end
end)

say("LANCE -- KRONAX MINIGUN v1 / base v0.41")
say("minigun deja equipe : H initial une seule fois, maintien 60 s / pause 2 s, surveillance toutes les 0.08 s")
say("C soin conserve une fois pendant la pause de 2 s, jamais lors des reprises apres un coup")
say("orbite : rayon %d (hors nova TimestreamDecay), vitesse %d studs/s, hauteur %d",
    CONFIG.ORBIT_RADIUS, CONFIG.ORBIT_LINEAR_SPEED, CONFIG.HOLD_HEIGHT)
say("objectifs : tout destructible de %.0f a %.0f PV est casse (reliques 5 M"
        .. " et mini RecursiveRelics au sol 4 M)",
    CONFIG.CRYSTAL_MIN_TARGET_HEALTH, CONFIG.CRYSTAL_MAX_TARGET_HEALTH)
say("NOUVEAU v0.40 : une relique sans PV visibles reste prioritaire apres la fin"
        .. " du signal visuel; retour sur Kronax seulement apres %d tirs et %.1f s"
        .. " de focus", CONFIG.CRYSTAL_VISUAL_MIN_SHOTS,
    CONFIG.CRYSTAL_VISUAL_MIN_FOCUS)
say("NOUVEAU v0.40 : MapContent.RecursiveRelics controle directement toutes les"
        .. " %.2f s, sans balayage global", CONFIG.RECURSIVE_RELIC_POLL_INTERVAL)
say("NOUVEAU v0.41 : changements de chargement avant Kronax absorbes;"
        .. " OriginalThickness ne peut plus activer une relique")
say("NOUVEAU v0.41 : un emplacement fixe bloque est relache sans blacklist et"
        .. " reste reutilisable a sa prochaine vraie activation")
say("sentinelles : au-dessus de 10 M PV (999999999) jamais touchees -> focus Kronax")
say("invocations alliees : modeles Owner + SpiritType ignores (Mender jamais vise)")
say("mini cristaux : nom libre, dossier libre; rayon d'arene %d studs",
    CONFIG.ARENA_RADIUS)
say("CADRE MOUVEMENT : CYLINDRE de rayon %d studs centre sur les 4 reliques"
        .. " (marge interieure %d, Heroic %d de plus)",
    CONFIG.MOVEMENT_ARENA_RADIUS, CONFIG.MOVEMENT_ARENA_INSET,
    CONFIG.HEROIC_ARENA_EDGE_MARGIN)
say("NOUVEAU v0.37 : plancher de deplacement %d studs sur %.2f s, relance"
        .. " de trajectoire max toutes les %.2f s. Mesure : 82 et 81 studs de"
        .. " deplacement median sur les runs gagnes, 54 sur le run perdu.",
    CONFIG.MIN_TRAVEL_DISTANCE, CONFIG.MIN_TRAVEL_WINDOW,
    CONFIG.TRAVEL_KICK_COOLDOWN)
say("CONSERVE v0.36 : couloirs Timeline/Flash portes a %.2f s (6 coups"
        .. " sur 13 des runs v0.34-v0.35 pris dans un couloir age de 2.18 a"
        .. " 2.85 s, supprime a 2.00 s par le script)", CONFIG.CORRIDOR_LIFETIME)
say("CONSERVE v0.35 : les candidats d'esquive hors cylindre sont"
        .. " rejetes au lieu d'etre rabattus sur le bord (67 %% du run v0.34"
        .. " passe a rayon 155, 6 coups sur 7 pris exactement la)")
say("RAPPEL v0.34 : le cadre rectangulaire avait ses coins a %d studs,"
        .. " soit %d studs dans le mur. Journaux v0.32/v0.33 : 29 a 35 %% du"
        .. " combat passe au-dela de 175 studs, vue bouchee 50 %% du temps"
        .. " la-bas contre 0 a 4 %% dans le cylindre.",
    math.floor(CONFIG.MOVEMENT_ARENA_RADIUS * math.sqrt(2)),
    math.floor(CONFIG.MOVEMENT_ARENA_RADIUS * (math.sqrt(2) - 1)))
say("MESURE AUX DEGATS : distance signee a TOUTES les zones actives + fenetre"
        .. " de 2.5 s des lancers (le champ \"apres X\" ne nommait que le"
        .. " dernier lancer et n'a jamais prouve la source d'un coup)")
say("esquives Heroic : maillage local %d directions x %d rayons x %d hauteurs;"
        .. " perimetre reserve aux grosses AoE au sol",
    CONFIG.HEROIC_DODGE_LOCAL_DIRECTIONS, #CONFIG.HEROIC_DODGE_LOCAL_RADII,
    #CONFIG.HEROIC_DODGE_ALTITUDES)
say("VOLUME HEROIC : altitudes SOL %d a %d studs; attaques ciblees"
        .. " calculees en 3D",
    CONFIG.HEROIC_DODGE_ALTITUDES[1],
    CONFIG.HEROIC_DODGE_ALTITUDES[#CONFIG.HEROIC_DODGE_ALTITUDES])
say("VOLUME CORRUPTED : altitudes SOL %d a %d studs, bande alignee sur le"
        .. " Heroic (le palier a 115 se posait pile sur le plafond)",
    CONFIG.DODGE_ALTITUDES[1],
    CONFIG.DODGE_ALTITUDES[#CONFIG.DODGE_ALTITUDES])
say("ALTITUDE : limite mesuree %d studs au-dessus du SOL; plafond du script"
        .. " %d studs (marge %d), mesure par rayon vers le bas",
    CONFIG.ALTITUDE_LIMIT, CONFIG.ALTITUDE_LIMIT - CONFIG.ALTITUDE_MARGIN,
    CONFIG.ALTITUDE_MARGIN)
say("petits cristaux : TP a %d studs seulement apres %.0f s de visee sans kill",
    CONFIG.MINI_APPROACH_DISTANCE, CONFIG.MINI_TELEPORT_DELAY)
say("MESURE : payload complet une fois par type de capacite (rayons reels)")
say("MESURE TIMELINE : trajectoire joueur gardee en memoire; preuve ecrite seulement aux degats")
say("PROFIL HEROIC : courbe %d/%d studs/s, altitude lisse %d +/- %d;"
        .. " DEPLACEMENT INSTANTANE comme le Corrupted (bride supprimee)",
    CONFIG.HEROIC_PATH_SPEED, CONFIG.HEROIC_TARGET_PATH_SPEED,
    CONFIG.HEROIC_ALTITUDE_BASE, CONFIG.HEROIC_ALTITUDE_AMPLITUDE)
say("CADRE HEROIC : marge supplementaire %d studs contre les murs; transition"
        .. " trone -> boss progressive",
    CONFIG.HEROIC_ARENA_EDGE_MARGIN)
say("TIMELINE v0.37 : capsule 3D rayon %d, verrou minimum %.2f s, clic maintenu",
    CONFIG.TIMELINE_CORRIDOR_RADIUS, CONFIG.TIMELINE_DODGE_HOLD)
say("ESQUIVES : ChronoShockwave 140 DESORMAIS ESQUIVEE (salve de %.1f s"
        .. " a 0.515 s par tick apres 3 s de charge), nova"
        .. " TimestreamDecay %d, pluie en %d impacts programmes",
    CONFIG.SHOCKWAVE_LINGER, ABILITY_PROFILES.timestreamdecay.radius,
    CONFIG.RAIN_MAX_DROPS)
say("marges d'esquive : declenchement a %d studs du bord, sortie a %d",
    CONFIG.HAZARD_TRIGGER_MARGIN, CONFIG.HAZARD_ESCAPE_MARGIN)
say("orbite %d studs de haut, plafond relatif a Kronax %d studs",
    CONFIG.HOLD_HEIGHT, CONFIG.HOLD_HEIGHT_MAX)
say("profil performance : sonde de vie rapide, balayage borne a %d objets"
        .. " toutes les %.2f s, esquives en cache",
    CONFIG.ARENA_SWEEP_BUDGET, CONFIG.ARENA_SWEEP_INTERVAL)
say("journal leger : aucun dump de particules/animations")
say("journal : %s | arret d'urgence : B", CONFIG.LOG_FILE)
say("session PlaceId=%s JobId=%s", tostring(game.PlaceId), tostring(game.JobId))
writeLog(true)
