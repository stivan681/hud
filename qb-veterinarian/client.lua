local QBCore = exports['qb-core']:GetCoreObject()

local isOnDuty = false
local receptionistPed = nil
local ActiveCases = {}
local nearbyCase = nil

-- Utility
local function DebugPrint(msg)
    if Config.Debug then
        print(('[qb-veterinarian] %s'):format(msg))
    end
end

local function LoadModel(model)
    local hash = type(model) == 'string' and joaat(model) or model
    if not IsModelInCdimage(hash) then return false end
    if not HasModelLoaded(hash) then
        RequestModel(hash)
        while not HasModelLoaded(hash) do
            Wait(10)
        end
    end
    return hash
end

local function LoadAnimDict(dict)
    if not HasAnimDictLoaded(dict) then
        RequestAnimDict(dict)
        while not HasAnimDictLoaded(dict) do
            Wait(10)
        end
    end
end

local function DrawText3D(coords, text)
    local onScreen, _x, _y = World3dToScreen2d(coords.x, coords.y, coords.z)
    local px, py, pz = table.unpack(GetGameplayCamCoords())
    local dist = #(vector3(px, py, pz) - coords)

    if onScreen then
        SetTextScale(0.32, 0.32)
        SetTextFont(4)
        SetTextOutline()
        SetTextCentre(true)
        BeginTextCommandDisplayText('STRING')
        AddTextComponentSubstringPlayerName(text)
        EndTextCommandDisplayText(_x, _y)

        local factor = (string.len(text)) / 270
        DrawRect(_x, _y + 0.0125, 0.015 + factor, 0.03, 0, 0, 0, 120)
    end
end

-- Reception ped spawn
local function SpawnReceptionist()
    local pedHash = LoadModel(Config.ClockIn.pedModel)
    if not pedHash then return end
    local coords = Config.ClockIn.coords
    receptionistPed = CreatePed(4, pedHash, coords.x, coords.y, coords.z - 1.0, Config.ClockIn.heading, false, true)
    SetEntityInvincible(receptionistPed, true)
    SetBlockingOfNonTemporaryEvents(receptionistPed, true)
    FreezeEntityPosition(receptionistPed, true)
    if Config.ClockIn.pedScenario then
        TaskStartScenarioInPlace(receptionistPed, Config.ClockIn.pedScenario, 0, true)
    end
    SetModelAsNoLongerNeeded(pedHash)
end

-- Duty handling
RegisterNetEvent('qb-vet:client:setDuty', function(state)
    isOnDuty = state
end)

local function HandleClockIn()
    local ped = PlayerPedId()
    local coords = GetEntityCoords(ped)
    local receptionCoords = Config.ClockIn.coords
    local dist = #(coords - receptionCoords)
    if dist < 2.0 then
        DrawText3D(receptionCoords + vector3(0.0, 0.0, 1.0), isOnDuty and Config.Text.ClockOut or Config.Text.ClockIn)
        if dist < 1.5 and IsControlJustReleased(0, 38) then -- E key
            TriggerServerEvent('qb-vet:server:toggleDuty')
        end
    end
end

-- Case interactions
RegisterNetEvent('qb-vet:client:createCase', function(caseId, caseData, waitingConfig)
    DebugPrint(('Spawning case %s on client'):format(caseId))

    local npcHash = LoadModel('a_m_y_business_01')
    local animalHash = LoadModel(caseData.animal.model)
    if not npcHash or not animalHash then
        DebugPrint('Failed to load NPC or animal model')
        return
    end

    local spawn = waitingConfig.npcSpawn
    local ped = CreatePed(4, npcHash, spawn.x, spawn.y, spawn.z - 1.0, spawn.w, true, true)
    SetEntityAsMissionEntity(ped, true, true)
    SetBlockingOfNonTemporaryEvents(ped, true)
    SetPedCanRagdoll(ped, false)

    local animal = CreatePed(28, animalHash, spawn.x + waitingConfig.animalOffset.x, spawn.y + waitingConfig.animalOffset.y, spawn.z, spawn.w, true, true)
    SetEntityAsMissionEntity(animal, true, true)
    SetBlockingOfNonTemporaryEvents(animal, true)

    local reception = waitingConfig.reception
    TaskGoStraightToCoord(ped, reception.x, reception.y, reception.z, 1.0, -1, reception.w, 0.1)
    TaskFollowToOffsetOfEntity(animal, ped, waitingConfig.animalOffset.x, waitingConfig.animalOffset.y, waitingConfig.animalOffset.z, 1.5, -1, 1.5, true)

    SetModelAsNoLongerNeeded(npcHash)
    SetModelAsNoLongerNeeded(animalHash)

    -- Sit the NPC and animal after walking for a bit
    CreateThread(function()
        Wait(5000)
        if DoesEntityExist(ped) then
            ClearPedTasks(ped)
            TaskStartScenarioInPlace(ped, waitingConfig.sitScenario or 'WORLD_HUMAN_STAND_IMPATIENT', 0, true)
        end
        if DoesEntityExist(animal) then
            ClearPedTasks(animal)
            local scenario = waitingConfig.animalSitScenario[caseData.animal.type] or 'WORLD_DOG_SITTING'
            TaskStartScenarioInPlace(animal, scenario, 0, true)
        end
    end)

    local pedNet = NetworkGetNetworkIdFromEntity(ped)
    local animalNet = NetworkGetNetworkIdFromEntity(animal)
    SetNetworkIdExistsOnAllMachines(pedNet, true)
    SetNetworkIdCanMigrate(pedNet, true)
    SetNetworkIdExistsOnAllMachines(animalNet, true)
    SetNetworkIdCanMigrate(animalNet, true)

    TriggerServerEvent('qb-vet:server:caseSpawned', caseId, pedNet, animalNet)
end)

RegisterNetEvent('qb-vet:client:syncCase', function(caseId, caseData, pedNetId, animalNetId)
    ActiveCases[caseId] = {
        data = caseData,
        pedNet = pedNetId,
        animalNet = animalNetId,
        busy = false,
        correct = false,
        inProgress = false
    }
end)

RegisterNetEvent('qb-vet:client:updateCaseCount', function(count)
    DebugPrint(('Active cases: %s'):format(count))
end)

RegisterNetEvent('qb-vet:client:cleanupCase', function(caseId)
    local case = ActiveCases[caseId]
    if case then
        local ped = NetToPed(case.pedNet or 0)
        local animal = NetToPed(case.animalNet or 0)
        if DoesEntityExist(ped) and NetworkHasControlOfEntity(ped) then
            DeletePed(ped)
        end
        if DoesEntityExist(animal) and NetworkHasControlOfEntity(animal) then
            DeletePed(animal)
        end
        ActiveCases[caseId] = nil
    end
end)

RegisterNetEvent('qb-vet:client:completeCase', function(caseId, correct)
    local case = ActiveCases[caseId]
    if not case then return end
    local ped = NetToPed(case.pedNet or 0)
    local animal = NetToPed(case.animalNet or 0)
    if DoesEntityExist(ped) then
        TaskWanderStandard(ped, 10.0, 10)
    end
    if DoesEntityExist(animal) then
        TaskWanderStandard(animal, 10.0, 10)
    end
    SetTimeout(8000, function()
        if DoesEntityExist(ped) then DeletePed(ped) end
        if DoesEntityExist(animal) then DeletePed(animal) end
    end)
    ActiveCases[caseId] = nil
end)

-- Diagnosis interaction
RegisterNetEvent('qb-vet:client:openDiagnosis', function(caseId, caseData)
    if ActiveCases[caseId] then
        ActiveCases[caseId].data = caseData
    end

    local menu = {
        {
            header = 'Patient Intake',
            txt = caseData.description,
            isMenuHeader = true
        }
    }

    for index, option in ipairs(caseData.diagnoses) do
        menu[#menu + 1] = {
            header = ('Diagnosis #%s'):format(index),
            txt = option.label,
            params = {
                event = 'qb-vet:client:selectDiagnosis',
                args = {
                    caseId = caseId,
                    choice = index
                }
            }
        }
    end

    exports['qb-menu']:openMenu(menu)
end)

RegisterNetEvent('qb-vet:client:selectDiagnosis', function(data)
    local caseId = data.caseId
    local choice = data.choice
    TriggerServerEvent('qb-vet:server:submitDiagnosis', caseId, choice)
end)

RegisterNetEvent('qb-vet:client:startTreatment', function(caseId, treatmentType, isCorrect, animalType)
    local treatment = Config.Treatments[treatmentType]
    if not treatment then
        DebugPrint(('Missing treatment definition for %s'):format(treatmentType))
        TriggerServerEvent('qb-vet:server:finishTreatment', caseId)
        return
    end

    if ActiveCases[caseId] then
        ActiveCases[caseId].inProgress = true
    end

    local ped = PlayerPedId()
    TaskTurnPedToFaceEntity(ped, NetToPed(ActiveCases[caseId] and ActiveCases[caseId].animalNet or 0), 1000)
    Wait(1000)

    LoadAnimDict(treatment.playerAnim.dict)
    TaskPlayAnim(ped, treatment.playerAnim.dict, treatment.playerAnim.anim, 8.0, -8.0, treatment.duration, 1, 0, false, false, false)

    local progressLabel = treatment.label
    QBCore.Functions.Progressbar('qb-vet-treatment', progressLabel, treatment.duration, false, true, {
        disableMovement = true,
        disableCarMovement = true,
        disableMouse = false,
        disableCombat = true
    }, {}, {}, {}, function() -- Done
        ClearPedTasks(ped)
        local case = ActiveCases[caseId]
        if case then
            local animal = NetToPed(case.animalNet or 0)
            if DoesEntityExist(animal) then
                local animData = treatment.animalAnims[animalType]
                if animData then
                    LoadAnimDict(animData.dict)
                    TaskPlayAnim(animal, animData.dict, animData.anim, 4.0, -4.0, 2500, 1, 0, false, false, false)
                end
                PlayAnimalVocal(animalType, animal)
            end
        end
        TriggerServerEvent('qb-vet:server:finishTreatment', caseId)
    end, function() -- Cancel
        ClearPedTasks(ped)
        TriggerServerEvent('qb-vet:server:finishTreatment', caseId)
    end)
end)

function PlayAnimalVocal(animalType, entity)
    if animalType == 'dog' then
        PlayAmbientSpeech1(entity, 'BARK', 'SPEECH_PARAMS_FORCE_NORMAL')
    elseif animalType == 'cat' then
        PlayAmbientSpeech1(entity, 'MEOW', 'SPEECH_PARAMS_FORCE_NORMAL')
    elseif animalType == 'cow' then
        PlayAmbientSpeech1(entity, 'COW', 'SPEECH_PARAMS_FORCE_NORMAL')
    elseif animalType == 'bird' then
        PlayAmbientSpeech1(entity, 'PARROT_SQUAWK', 'SPEECH_PARAMS_FORCE_NORMAL')
    end
end

-- Interaction tick
CreateThread(function()
    SpawnReceptionist()
    while true do
        Wait(0)
        HandleClockIn()

        if not isOnDuty then
            goto continue
        end

        local ped = PlayerPedId()
        local coords = GetEntityCoords(ped)
        local closestCaseId = nil
        local closestCaseDist = 999.0

        for caseId, case in pairs(ActiveCases) do
            local npc = NetToPed(case.pedNet or 0)
            if DoesEntityExist(npc) then
                local npcCoords = GetEntityCoords(npc)
                local dist = #(coords - npcCoords)
                if dist < 10.0 and dist < closestCaseDist then
                    closestCaseId = caseId
                    closestCaseDist = dist
                end
            end
        end

        if closestCaseId and closestCaseDist < 2.0 then
            local case = ActiveCases[closestCaseId]
            local npc = NetToPed(case.pedNet or 0)
            if DoesEntityExist(npc) then
                local npcCoords = GetEntityCoords(npc)
                DrawText3D(npcCoords + vector3(0.0, 0.0, 1.0), Config.Text.Examine)
                if closestCaseDist < 1.5 and IsControlJustReleased(0, 38) then
                    TriggerServerEvent('qb-vet:server:takeCase', closestCaseId)
                end
            end
        end

        ::continue::
    end
end)

-- Cleanup on resource stop for ped
AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    if DoesEntityExist(receptionistPed) then
        DeletePed(receptionistPed)
    end
    for _, case in pairs(ActiveCases) do
        local ped = NetToPed(case.pedNet or 0)
        local animal = NetToPed(case.animalNet or 0)
        if DoesEntityExist(ped) then DeletePed(ped) end
        if DoesEntityExist(animal) then DeletePed(animal) end
    end
end)
