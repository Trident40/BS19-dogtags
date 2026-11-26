DogTagConfig = {}

-- Enable verbose server console logs for drops, pickups, anti-farm checks & payouts
DogTagConfig.Debug = true

-- Prevent friendly-fire farming inside the same BS19 faction
DogTagConfig.BlockSameFactionTags = true

-- Cooldown (minutes) before the same killer can earn another paid tag from the same victim
DogTagConfig.SameVictimCooldownMinutes = 30

-- Minutes a physical dog tag drop stays on the ground before despawning
DogTagConfig.TagDespawnMinutes = 10

-- Bonus cash added per kill on the victim's active killstreak (capped by MaxKillstreakBonus)
DogTagConfig.KillstreakBonusPerKill = 350
DogTagConfig.MaxKillstreakBonus = 5000

-- Nemesis system: if a victim has previously eliminated you >= NemesisThreshold times,
-- claiming their tag marks it as a NEMESIS trophy and multiplies payout by NemesisMultiplier!
DogTagConfig.NemesisThreshold = 2
DogTagConfig.NemesisMultiplier = 1.50

-- Percentage of Fence cash-in automatically deposited to the seller's bs_faction_banks treasury (0 to disable)
DogTagConfig.FactionBankCutPercent = 20

-- Control key to pick up dropped tags & cash in at Fence terminals (38 = E)
DogTagConfig.InteractKey = 38

-- =============================================================================
-- DOG TAG RARITY TIERS (Scaled by victim's living survival streak or killstreak)
-- Ordered from highest to lowest; first matching tier wins.
-- =============================================================================
DogTagConfig.Tiers = {
    {
        id = 'OBSIDIAN',
        label = 'Apex Hunter',
        minAliveMinutes = 300,
        minKillstreak = 5,
        baseValue = 7500,
        color = { 168, 85, 247 } -- Obsidian Violet
    },
    {
        id = 'GOLD',
        label = 'Veteran',
        minAliveMinutes = 120,
        minKillstreak = 3,
        baseValue = 3500,
        color = { 245, 158, 11 } -- Tactical Amber Gold
    },
    {
        id = 'SILVER',
        label = 'Scavenger',
        minAliveMinutes = 30,
        minKillstreak = 1,
        baseValue = 1500,
        color = { 203, 213, 225 } -- Brushed Steel Silver
    },
    {
        id = 'BRONZE',
        label = 'Rookie',
        minAliveMinutes = 0,
        minKillstreak = 0,
        baseValue = 500,
        color = { 180, 83, 9 } -- Weathered Bronze
    }
}

-- =============================================================================
-- BLACK MARKET FENCE DROP-OFF LOCATIONS (Cash in carried Dog Tags)
-- =============================================================================
DogTagConfig.Fences = {
    {
        id = 'sandy_fence',
        label = 'Sandy Shores Scrap Fence',
        coords = vector3(1961.4, 3741.8, 32.3),
        radius = 3.0
    },
    {
        id = 'cypress_fence',
        label = 'Cypress Flats Dock Fence',
        coords = vector3(712.8, -969.4, 30.4),
        radius = 3.0
    },
    {
        id = 'paleto_fence',
        label = 'Paleto Alley Tag Broker',
        coords = vector3(-156.2, 6328.9, 31.6),
        radius = 3.0
    }
}
