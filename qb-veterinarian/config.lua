Config = {}

-- General resource settings
Config.JobName = 'vet' -- Set this to the job name defined in your shared/jobs.lua if you want to restrict duty usage
Config.UseJobRequirement = false -- If true, only players with Config.JobName can clock in
Config.Debug = false -- Toggle helpful debug prints

-- Duty / clinic setup
Config.ClockIn = {
    coords = vec3(355.62, -584.73, 28.79), -- Reception desk
    heading = 67.58,
    pedModel = 's_f_y_scrubs_01', -- Receptionist model
    pedScenario = 'WORLD_HUMAN_CLIPBOARD'
}

Config.WaitingArea = {
    npcSpawn = vec4(345.92, -577.89, 28.79, 158.48), -- Where the client NPC spawns
    animalOffset = vec3(0.7, 0.0, 0.0), -- Offset for the animal to stand relative to the owner while walking
    reception = vec4(352.88, -584.69, 28.79, 158.48), -- The point the NPC walks to
    sitScenario = 'PROP_HUMAN_SEAT_CHAIR', -- Scenario played while the NPC waits
    animalSitScenario = {
        dog = 'WORLD_DOG_SITTING',
        cat = 'WORLD_CAT_SLEEPING_GROUND',
        cow = 'WORLD_COW_GRAZING',
        bird = 'WORLD_PARROT_STAND_WAIT'
    }
}

-- Case spawn timing
Config.SpawnIntervalMinutes = 5 -- How many minutes between potential case spawns
Config.MaxConcurrentCases = 2 -- Prevents more than this many cases from being active simultaneously

-- Payment setup
Config.Payment = {
    Min = 200,
    Max = 500,
    WrongPenalty = 0.5 -- 50% pay if the diagnosis is incorrect
}

Config.Reputation = {
    Default = 0,
    CorrectReward = 5, -- Base reputation reward for successful treatment
    WrongPenalty = -2, -- Reputation lost when the wrong treatment is performed
    TierBonuses = { -- Additional rep on success based on case tier index
        [1] = 0,
        [2] = 2,
        [3] = 5
    }
}

-- Treatment animation settings
Config.Treatments = {
    petting = {
        label = 'Comfort the animal',
        duration = 4500,
        playerAnim = { dict = 'creatures@rottweiler@tricks@', anim = 'petting_franklin' },
        animalAnims = {
            dog = { dict = 'creatures@rottweiler@amb@world_dog_sitting@base', anim = 'base' },
            cat = { dict = 'creatures@cat@amb@world_cat_sleeping_ground@base', anim = 'base' },
            cow = { dict = 'creatures@cow@move', anim = 'idle_turn_l_loop' },
            bird = { dict = 'creatures@parrot@amb@idle', anim = 'idle_a' }
        }
    },
    injection = {
        label = 'Administer injection',
        duration = 6000,
        playerAnim = { dict = 'missheistdockssetup1clipboard@base', anim = 'base' },
        animalAnims = {
            dog = { dict = 'creatures@rottweiler@tricks@', anim = 'sit_loop' },
            cat = { dict = 'creatures@cat@amb@world_cat_sleeping_ground@enter', anim = 'enter' },
            cow = { dict = 'creatures@cow@action@cow', anim = 'cow_react_escape' },
            bird = { dict = 'creatures@parrot@amb@idle', anim = 'idle_c' }
        }
    },
    bandage = {
        label = 'Apply bandage',
        duration = 5500,
        playerAnim = { dict = 'amb@medic@standing@tendtodead@idle_a', anim = 'idle_a' },
        animalAnims = {
            dog = { dict = 'creatures@rottweiler@amb@world_dog_sitting@enter', anim = 'enter' },
            cat = { dict = 'creatures@cat@amb@world_cat_sleeping_ground@exit', anim = 'exit' },
            cow = { dict = 'creatures@cow@base', anim = 'base_idle' },
            bird = { dict = 'creatures@parrot@amb@idle', anim = 'idle_b' }
        }
    }
}

-- Case definitions broken into tiers unlocked by reputation
Config.CaseTiers = {
    {
        minRep = 0,
        cases = {
            {
                description = 'My dog keeps coughing and seems tired.',
                animal = { model = 'a_c_shepherd', type = 'dog' },
                diagnoses = {
                    { label = 'Kennel cough - prescribe rest and medicine', treatment = 'injection', correct = true },
                    { label = 'It is just hungry, give food', treatment = 'petting', correct = false },
                    { label = 'Suggest a walk in the park', treatment = 'petting', correct = false }
                }
            },
            {
                description = 'My cat cut her paw on something sharp.',
                animal = { model = 'a_c_cat_01', type = 'cat' },
                diagnoses = {
                    { label = 'Clean the wound and apply a bandage', treatment = 'bandage', correct = true },
                    { label = 'Give the cat a bath', treatment = 'petting', correct = false },
                    { label = 'Nothing is wrong, send them home', treatment = 'petting', correct = false }
                }
            }
        }
    },
    {
        minRep = 25,
        cases = {
            {
                description = 'Our dairy cow has stopped eating today.',
                animal = { model = 'a_c_cow', type = 'cow' },
                diagnoses = {
                    { label = 'Treat for stomach bloating', treatment = 'injection', correct = true },
                    { label = 'Recommend more hay immediately', treatment = 'petting', correct = false },
                    { label = 'Suggest extra water only', treatment = 'bandage', correct = false }
                }
            },
            {
                description = 'This dog sprained its leg while running.',
                animal = { model = 'a_c_husky', type = 'dog' },
                diagnoses = {
                    { label = 'Wrap the leg with a supportive bandage', treatment = 'bandage', correct = true },
                    { label = 'Give the dog treats', treatment = 'petting', correct = false },
                    { label = 'Recommend a grooming session', treatment = 'petting', correct = false }
                }
            }
        }
    },
    {
        minRep = 60,
        cases = {
            {
                description = 'A rare parrot is refusing to eat and looks weak.',
                animal = { model = 'a_c_chickenhawk', type = 'bird' },
                diagnoses = {
                    { label = 'Administer vitamins and observe closely', treatment = 'injection', correct = true },
                    { label = 'Let it fly freely outside', treatment = 'petting', correct = false },
                    { label = 'Provide a seed snack only', treatment = 'petting', correct = false }
                }
            },
            {
                description = 'Emergency surgery follow-up for a cat with stitches.',
                animal = { model = 'a_c_cat_01', type = 'cat' },
                diagnoses = {
                    { label = 'Check stitches and re-bandage carefully', treatment = 'bandage', correct = true },
                    { label = 'Give the cat milk', treatment = 'petting', correct = false },
                    { label = 'Let the cat lick the wound clean', treatment = 'petting', correct = false }
                }
            }
        }
    }
}

-- Utility localization text
Config.Text = {
    ClockIn = '[E] Clock In as Veterinarian',
    ClockOut = '[E] Clock Out of Veterinarian Duty',
    Examine = '[E] Examine Patient',
    Busy = 'Another veterinarian is already helping this patient.',
    NoCases = 'There are currently no patients waiting.',
    StartedDuty = 'You are now on veterinarian duty.',
    StoppedDuty = 'You clocked out of veterinarian duty.',
    WrongJob = 'Only licensed veterinarians can clock in here!',
    TreatmentSuccess = 'Treatment complete! Great work.',
    TreatmentFail = 'Treatment complete but the pet did not improve much.'
}
