local QBCore = exports['qb-core']:GetCoreObject()

local ActiveCases = {}
local ClockedInPlayers = {}
local PlayerReputation = {}
local caseIdCounter = 0

local function DebugPrint(msg)
    if Config.Debug then
        print(('[qb-veterinarian] %s'):format(msg))
    end
end

local function GenerateCaseId()
    caseIdCounter = caseIdCounter + 1
    if caseIdCounter > 9999 then
        caseIdCounter = 1
    end
    return caseIdCounter
end

local function GetPlayerReputation(src)
    local player = QBCore.Functions.GetPlayer(src)
    if not player then return Config.Reputation.Default end
    local cid = player.PlayerData.citizenid
    if not PlayerReputation[cid] then
        local rep = player.PlayerData.metadata['vetrep'] or Config.Reputation.Default
        PlayerReputation[cid] = rep
    end
    return PlayerReputation[cid]
end

local function SavePlayerReputation(src, amount)
    local player = QBCore.Functions.GetPlayer(src)
    if not player then return end
    local cid = player.PlayerData.citizenid
    PlayerReputation[cid] = amount
    player.Functions.SetMetaData('vetrep', amount)
end

local function PickCaseForReputation(rep)
    local tierToUse = nil
    for tierIndex = #Config.CaseTiers, 1, -1 do
        local tier = Config.CaseTiers[tierIndex]
        if rep >= tier.minRep then
            tierToUse = { index = tierIndex, data = tier }
            break
        end
    end

    if not tierToUse then
        tierToUse = { index = 1, data = Config.CaseTiers[1] }
    end

    local cases = tierToUse.data.cases
    local caseInfo = cases[math.random(#cases)]

    -- Build a clean copy with extra helpers so we do not modify the config directly
    local diagnoses = {}
    local correctIndex = nil
    for i, option in ipairs(caseInfo.diagnoses) do
        diagnoses[i] = {
            label = option.label,
            treatment = option.treatment,
            correct = option.correct and true or false
        }
        if option.correct then
            correctIndex = i
        end
    end

    return {
        tierIndex = tierToUse.index,
        description = caseInfo.description,
        animal = caseInfo.animal,
        diagnoses = diagnoses,
        correctIndex = correctIndex
    }
end

local function BroadcastClockedInCount()
    TriggerClientEvent('qb-vet:client:updateCaseCount', -1, table.count(ActiveCases))
end

local function CreateNewCase()
    if table.count(ActiveCases) >= Config.MaxConcurrentCases then
        DebugPrint('Max concurrent cases reached, skipping spawn')
        return
    end

    local totalClockedIn = 0
    local highestRep = 0
    local ownerSource = nil

    for src, state in pairs(ClockedInPlayers) do
        if state then
            totalClockedIn = totalClockedIn + 1
            local rep = GetPlayerReputation(src)
            if rep >= highestRep then
                highestRep = rep
                ownerSource = src
            end
        end
    end

    if totalClockedIn == 0 or not ownerSource then
        DebugPrint('No veterinarians on duty, skipping case creation')
        return
    end

    local caseId = GenerateCaseId()
    local caseData = PickCaseForReputation(highestRep)

    ActiveCases[caseId] = {
        owner = ownerSource,
        case = caseData,
        busy = false,
        pedNetId = nil,
        animalNetId = nil,
        currentPlayer = nil,
        reward = 0,
        repGain = 0,
        correct = false,
        tierIndex = caseData.tierIndex
    }

    DebugPrint(('Created new case %s (tier %s)'):format(caseId, caseData.tierIndex))

    TriggerClientEvent('qb-vet:client:createCase', ownerSource, caseId, caseData, Config.WaitingArea)
end

local function CleanupCase(caseId)
    local case = ActiveCases[caseId]
    if not case then return end

    TriggerClientEvent('qb-vet:client:cleanupCase', -1, caseId)
    ActiveCases[caseId] = nil
    BroadcastClockedInCount()
end

-- Duty management
RegisterNetEvent('qb-vet:server:toggleDuty', function()
    local src = source
    local player = QBCore.Functions.GetPlayer(src)
    if not player then return end

    if Config.UseJobRequirement and player.PlayerData.job.name ~= Config.JobName then
        TriggerClientEvent('QBCore:Notify', src, Config.Text.WrongJob, 'error')
        return
    end

    ClockedInPlayers[src] = not ClockedInPlayers[src]

    if ClockedInPlayers[src] then
        TriggerClientEvent('qb-vet:client:setDuty', src, true)
        TriggerClientEvent('QBCore:Notify', src, Config.Text.StartedDuty, 'success')
    else
        TriggerClientEvent('qb-vet:client:setDuty', src, false)
        TriggerClientEvent('QBCore:Notify', src, Config.Text.StoppedDuty, 'primary')
    end

    BroadcastClockedInCount()
end)

-- Receive spawned entities from case owner
RegisterNetEvent('qb-vet:server:caseSpawned', function(caseId, pedNetId, animalNetId)
    local src = source
    local case = ActiveCases[caseId]
    if not case or case.owner ~= src then
        DebugPrint(('Invalid case spawn data from %s'):format(src))
        return
    end

    case.pedNetId = pedNetId
    case.animalNetId = animalNetId

    TriggerClientEvent('qb-vet:client:syncCase', -1, caseId, case.case, pedNetId, animalNetId)
    BroadcastClockedInCount()
end)

RegisterNetEvent('qb-vet:server:takeCase', function(caseId)
    local src = source
    local case = ActiveCases[caseId]
    if not case then
        TriggerClientEvent('QBCore:Notify', src, Config.Text.NoCases, 'error')
        return
    end

    if case.busy and case.currentPlayer ~= src then
        TriggerClientEvent('QBCore:Notify', src, Config.Text.Busy, 'error')
        return
    end

    case.busy = true
    case.currentPlayer = src
    TriggerClientEvent('qb-vet:client:openDiagnosis', src, caseId, case.case)
end)

RegisterNetEvent('qb-vet:server:submitDiagnosis', function(caseId, choiceIndex)
    local src = source
    local case = ActiveCases[caseId]
    if not case or case.currentPlayer ~= src then
        return
    end

    local selection = case.case.diagnoses[choiceIndex]
    if not selection then return end

    local isCorrect = choiceIndex == case.case.correctIndex

    local reward = math.random(Config.Payment.Min, Config.Payment.Max)
    if not isCorrect then
        reward = math.floor(reward * Config.Payment.WrongPenalty)
    end

    local rep = GetPlayerReputation(src)
    local repChange = isCorrect and (Config.Reputation.CorrectReward + (Config.Reputation.TierBonuses[case.tierIndex] or 0)) or Config.Reputation.WrongPenalty
    local newRep = math.max(0, rep + repChange)

    case.reward = reward
    case.repGain = repChange
    case.correct = isCorrect
    case.pendingTreatment = true

    TriggerClientEvent('qb-vet:client:startTreatment', src, caseId, selection.treatment, isCorrect, case.case.animal.type)

    if not isCorrect then
        TriggerClientEvent('QBCore:Notify', src, Config.Text.TreatmentFail, 'error', 4500)
    else
        TriggerClientEvent('QBCore:Notify', src, Config.Text.TreatmentSuccess, 'success', 4500)
    end

    SavePlayerReputation(src, newRep)
end)

RegisterNetEvent('qb-vet:server:finishTreatment', function(caseId)
    local src = source
    local case = ActiveCases[caseId]
    if not case or case.currentPlayer ~= src or not case.pendingTreatment then
        return
    end

    local player = QBCore.Functions.GetPlayer(src)
    if not player then return end

    player.Functions.AddMoney('bank', case.reward, 'vet-treatment')
    TriggerClientEvent('QBCore:Notify', src, ('You received $%s for the treatment.'):format(case.reward), 'success')

    case.pendingTreatment = false
    case.completed = true

    TriggerClientEvent('qb-vet:client:completeCase', -1, caseId, case.correct)
    CleanupCase(caseId)
end)

-- Player state events
AddEventHandler('playerDropped', function()
    local src = source
    ClockedInPlayers[src] = nil
    for id, case in pairs(ActiveCases) do
        if case.owner == src then
            CleanupCase(id)
        elseif case.currentPlayer == src then
            case.busy = false
            case.currentPlayer = nil
        end
    end
end)

RegisterNetEvent('QBCore:Server:PlayerLoaded', function(player)
    local cid = player.PlayerData.citizenid
    PlayerReputation[cid] = player.PlayerData.metadata['vetrep'] or Config.Reputation.Default
end)

RegisterNetEvent('QBCore:Server:OnPlayerUnload', function(cid)
    PlayerReputation[cid] = nil
end)

-- Automatic case creation loop
CreateThread(function()
    local interval = math.floor(Config.SpawnIntervalMinutes * 60000)
    if interval < 60000 then
        interval = 60000
    end

    while true do
        Wait(interval)
        CreateNewCase()
    end
end)

QBCore.Functions.CreateCallback('qb-vet:server:getReputation', function(source, cb)
    local rep = GetPlayerReputation(source)
    cb(rep)
end)

-- Utility function to count entries in a table without # (since non-array)
function table.count(tbl)
    local count = 0
    for _ in pairs(tbl) do count = count + 1 end
    return count
end
