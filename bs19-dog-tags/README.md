# BS19 - Survivor Dog Tags

> **Standalone Stamped Survivor Dog Tags, Survival-Streak Bounty Scaling, Nemesis Rivalry Tracking & Black Market Fence Cash-Ins for BeyondSurvival (BS19)**
> **Developed by Trident40**

![FiveM](https://img.shields.io/badge/FiveM-Cerulean%20%7C%20Lua%205.4-f59e0b?style=for-the-badge)
![BS19](https://img.shields.io/badge/BeyondSurvival-Arcainex%2Fbs19-dc2626?style=for-the-badge)
![Database](https://img.shields.io/badge/Database-oxmysql%20%7C%20MariaDB-0d9488?style=for-the-badge)
![Standalone](https://img.shields.io/badge/Mode-Zero--Edit%20Standalone-16a34a?style=for-the-badge)

---

## Overview

**BS19 - Survivor Dog Tags** (`bs19-dog-tags`) is a standalone, zero-edit FiveM expansion built natively for **BeyondSurvival (`Arcainex/bs19`)**. Every survivor automatically carries a live stamped dog tag whose rarity and cash value scale with how long they have survived and their active PvP killstreak.

Eliminate a rival survivor to drop their stamped tag on the ground, loot it with `[E]`, and haul your trophies to one of **3 Black Market Fence drop-offs** for cash + an optional automatic cut into `bs_faction_banks`.

### Key Highlights
- **Zero Edits to Core BS19 Files** — Resolves active survivors & factions natively via `exports.bs_core:GetPlayer(src)` (with `bs_users` + `bs_characters` fallback) and `bs_faction_members` / `bs_faction_registry` / `bs_faction_banks`.
- **Auto-Bootstrapping SQL (`oxmysql`)** — Automatically creates `bs_dog_tags`, `bs_dog_tag_streaks`, and `bs_dog_tag_nemesis` on first startup.
- **Survival-Streak & Killstreak Scaling** — Staying alive longer makes your tag worth far more (from `BRONZE $500` up to `OBSIDIAN $7,500` + `+$350` per active killstreak).
- **Nemesis Rivalry System** — If a rival eliminates you 2+ times, settling the score drops a crimson **NEMESIS** trophy worth **1.5x** payout and announces the payback server-wide.
- **Friendly Tag Reclaim** — If a teammate from the same faction (or the victim themselves) reaches the dropped tag first, they **reclaim** it and deny enemy hunters the payout.
- **Built-In Anti-Farm Protections** — Blocks same-faction friendly-fire farming and enforces a configurable 30-minute per-victim cooldown.

---

## Dog Tag Rarity Tiers & Payouts

| Tier | Rank Label | Alive Streak Req | OR Killstreak Req | Base Payout | Killstreak Bonus |
| :--- | :--- | :---: | :---: | :---: | :---: |
| `BRONZE` | **Rookie** | `0+ min` | `0` | `$500` | `+$350/kill` |
| `SILVER` | **Scavenger** | `30+ min` | `1+` | `$1,500` | `+$350/kill` |
| `GOLD` | **Veteran** | `120+ min` | `3+` | `$3,500` | `+$350/kill` |
| `OBSIDIAN` | **Apex Hunter** | `300+ min` | `5+` | `$7,500` | `+$350/kill` |

> **Nemesis Multiplier:** Killing a rival who has previously eliminated you `2+` times multiplies the total tag payout by **`1.50x`**.

---

## Black Market Fence Locations

| Fence ID | Location | Coordinates |
| :--- | :--- | :--- |
| `sandy_fence` | **Sandy Shores Scrap Fence** | `1961.4, 3741.8, 32.3` |
| `cypress_fence` | **Cypress Flats Dock Fence** | `712.8, -969.4, 30.4` |
| `paleto_fence` | **Paleto Alley Tag Broker** | `-156.2, 6328.9, 31.6` |

---

## Step-by-Step Installation

1. Copy `bs19-dog-tags/` into your FiveM server's `resources/[local]/` directory.
2. *(Optional)* Customize tiers, cooldowns, Fence coords, or `FactionBankCutPercent` in `config.lua`.
3. Add `ensure bs19-dog-tags` to `server.cfg` **after** `oxmysql` and `[beyond]`:

```cfg
ensure oxmysql
ensure [beyond]
ensure bs19-dog-tags
```

*(Optional)* Grant staff ACE permission to reset Dog Tag records:

```cfg
add_ace group.admin command.dogtagreset allow
```

4. Restart your server (or run `refresh` then `ensure bs19-dog-tags`). Tables auto-create on first boot!

---

## Commands & Server Exports

### Commands
| Command | Access | Description |
| :--- | :--- | :--- |
| `[E]` (on dropped tag) | Everyone | Collects a rival tag as a trophy or reclaims a friendly faction tag. |
| `[E]` (at Fence blip) | Everyone | Cashes in all carried Dog Tags for cash (+ optional faction treasury cut). |
| `/dogtags` | Everyone | Displays your current living tag tier/value, streak, and carried trophies. |
| `/tagboard` | Everyone | Shows the Top 5 Wasteland Tag Hunters on the server. |
| `dogtagreset [charId|all]` | Console / ACE Admin | Resets one character or all Dog Tag & Nemesis records. |

### Public Server Exports
```lua
-- Check a player's current living tag value & tier
local info = exports['bs19-dog-tags']:GetPlayerTagValue(src)
-- => { tier = 'GOLD', label = 'Veteran', value = 4550, aliveMinutes = 145, killstreak = 3 }

-- Check whether two characters are Nemesis rivals
local isNem, kills = exports['bs19-dog-tags']:IsNemesis(killerCharId, victimCharId)

-- Fetch carried uncashed tags or top hunters
local tags = exports['bs19-dog-tags']:GetCarriedTags(src)
local top5 = exports['bs19-dog-tags']:GetTopHunters(5)
```

---

## Credits

- **BS19 - Survivor Dog Tags** — **Developed by Trident40**
- Built natively for **BeyondSurvival (`Arcainex/bs19`)**
