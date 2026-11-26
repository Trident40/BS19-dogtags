<p align="center">
  <img src="assets/BS19-Dogtags-Logo.jpg" alt="BS19 - Survivor Dog Tags" width="260" />
</p>

<h1 align="center">BS19 - Survivor Dog Tags</h1>

<p align="center">
  <strong>BS19-Expansion Stamped Survivor Dog Tags, Survival-Streak Bounties, Nemesis Tracking & Black Market Fence Cash-Ins for BeyondSurvival (BS19)</strong><br />
  <sub>Developed by <strong>Trident40</strong></sub>
</p>

<p align="center">
  <img src="https://img.shields.io/badge/FiveM-Cerulean%20%7C%20Lua%205.4-f59e0b?style=for-the-badge" alt="FiveM Cerulean Lua 5.4" />
  <img src="https://img.shields.io/badge/BeyondSurvival-Arcainex%2Fbs19-dc2626?style=for-the-badge" alt="BeyondSurvival BS19" />
  <img src="https://img.shields.io/badge/Database-oxmysql%20%7C%20MariaDB-0d9488?style=for-the-badge" alt="oxmysql MariaDB" />
  <img src="https://img.shields.io/badge/Install-Zero--Edit%20Standalone-16a34a?style=for-the-badge" alt="Zero-Edit Standalone" />
</p>

---

## Overview

**BS19 - Survivor Dog Tags** (`bs19-dog-tags`) is a lightweight, zero-edit standalone FiveM expansion built natively for **BeyondSurvival (`Arcainex/bs19`)**.

Every survivor carries a live stamped dog tag whose rarity tier and cash payout climb the longer they stay alive and the more PvP eliminations they rack up. When a rival drops in PvP (on foot or by vehicle), their glowing tag hits the ground—giving enemy hunters a reason to push the body and squadmates a chance to reclaim it before it's cashed in at a **Black Market Fence**.

---

## Features

- **Zero Core File Edits** — Resolves active survivors and factions directly via `exports.bs_core:GetPlayer(src)` (with `NULL`-safe `bs_users` / `bs_characters` fallback) plus native `bs_faction_members`, `bs_faction_registry`, and `bs_faction_banks` tables.
- **Auto-Bootstrapping SQL** — Automatically creates `bs_dog_tags`, `bs_dog_tag_streaks`, and `bs_dog_tag_nemesis` on first startup via `oxmysql` (manual `sql/dog_tags.sql` also included).
- **4-Tier Survival & Killstreak Scaling** — Tags scale automatically from **Bronze ($500)** up to **Obsidian ($7,500)**, plus **+$350 per active killstreak** (up to `$5,000` bonus).
- **Nemesis Rivalry System (`1.5x`)** — If a rival eliminates you `2+` times, settling the score drops a crimson **NEMESIS** tag worth **1.5x payout**, broadcasts the payback server-wide, and resets their rivalry tally cleanly.
- **Friendly Tag Reclaim** — Same-faction teammates (or the victim) can rush the dropped tag and press `[E]` to **reclaim** it, denying enemy hunters the payout.
- **Black Market Fence Cash-Ins + Faction Treasury Cut** — Haul carried tags to **3 Fence drop-offs** across San Andreas. Faction members automatically route **20%** straight into `bs_faction_banks` (configurable; Lone Wolves keep 100%).
- **Exploit-Hardened Server Logic** — Includes same-faction friendly-fire blocking, 30-minute per-victim anti-farm cooldowns, async double-cash-in mutex locks, server-authoritative drop coordinates, 450m combat range validation, and 0-flicker 3D tier-colored markers.

---

## Dog Tag Rarity Tiers

| Tier | Rank | Alive Streak Req | OR Killstreak Req | Base Value | Killstreak Bonus |
| :--- | :--- | :---: | :---: | :---: | :---: |
| `BRONZE` | **Rookie** | `0+ min` | `0` | `$500` | `+$350 / kill` |
| `SILVER` | **Scavenger** | `30+ min` | `1+` | `$1,500` | `+$350 / kill` |
| `GOLD` | **Veteran** | `120+ min` | `3+` | `$3,500` | `+$350 / kill` |
| `OBSIDIAN` | **Apex Hunter** | `300+ min` | `5+` | `$7,500` | `+$350 / kill` |

> **Nemesis Bonus:** Eliminating a rival who previously killed you `2+` times applies a **`1.50x`** multiplier to the total tag payout.

---

## Black Market Fence Locations

| Fence ID | Location | Coordinates |
| :--- | :--- | :--- |
| `sandy_fence` | **Sandy Shores Scrap Fence** | `1961.4, 3741.8, 32.3` |
| `cypress_fence` | **Cypress Flats Dock Fence** | `712.8, -969.4, 30.4` |
| `paleto_fence` | **Paleto Alley Tag Broker** | `-156.2, 6328.9, 31.6` |

---

## Installation

1. Download and drop the `bs19-dog-tags` folder into your server's `resources/[local]/` directory.
2. *(Optional)* Adjust tier thresholds, cooldowns, Fence coordinates, or `FactionBankCutPercent` in `config.lua`.
3. Add the resource to your `server.cfg` **after** `oxmysql` and `[beyond]`:

```cfg
ensure oxmysql
ensure [beyond]
ensure bs19-dog-tags
```

4. *(Optional)* Grant staff ACE access to reset tag records:

```cfg
add_ace group.admin command.dogtagreset allow
```

5. Restart your server (or run `refresh` and `ensure bs19-dog-tags`). All SQL tables auto-initialize on boot.

---

## Commands & Server Exports

### Commands

| Command / Key | Access | Description |
| :--- | :--- | :--- |
| `[E]` on dropped tag | Everyone | Loot an enemy survivor's tag or reclaim a friendly squadmate's tag |
| `[E]` at Fence blip | Everyone | Cash in all carried tags (routes optional % cut to `bs_faction_banks`) |
| `/dogtags` | Everyone | View your live tag tier/value, survival streak, and carried trophies |
| `/tagboard` | Everyone | View the Top 5 Wasteland Tag Hunters by total earnings |
| `dogtagreset [charId\|all]` | Console / ACE | Wipe one character or all tags, streaks, active drops, and Nemesis rows |

### Server Exports

```lua
-- Get a survivor's current living tag tier, value & streak
local tagInfo = exports['bs19-dog-tags']:GetPlayerTagValue(src)

-- Get all carried uncashed tags for a player
local carried = exports['bs19-dog-tags']:GetCarriedTags(src)

-- Check Nemesis rivalry status between two characters
local isNemesis, priorKills = exports['bs19-dog-tags']:IsNemesis(killerCharId, victimCharId)

-- Fetch top tag hunters leaderboard
local topHunters = exports['bs19-dog-tags']:GetTopHunters(5)
```

---

## Credits

- **BS19 - Survivor Dog Tags** — Developed by **Trident40**
- Built natively for **BeyondSurvival (`Arcainex/bs19`)**
