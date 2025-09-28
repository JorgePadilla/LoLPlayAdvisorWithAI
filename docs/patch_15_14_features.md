# Patch 15.14 Features and ROFL File Data

## Overview
Patch 15.14 is the current League of Legends patch that this application supports. This document outlines the specific data fields and features available in ROFL files from this patch.

## Patch Information
- **Patch Number**: 15.14
- **Full Version**: 15.14.695.3589 (example)
- **Release Date**: Current patch (as of application development)

## ROFL File Structure for Patch 15.14

### Header Information
The ROFL file header contains basic file metadata:
- **Magic Header**: "RIOT" (6 bytes)
- **Signature Length**: Variable
- **File Structure**: Contains metadata offset, payload offset, and file length information

### Metadata Fields Available

#### Game Information
- `gameId` - Unique identifier for the match
- `gameDuration` - Game length in seconds
- `gameVersion` - Full patch version (e.g., "15.14.695.3589")
- `gameMode` - Game type (Classic, ARAM, etc.)
- `mapId` - Map identifier (11 = Summoner's Rift)
- `queueId` - Queue type (420 = Ranked Solo/Duo, 450 = ARAM, etc.)

#### Player Statistics
- `participants` - Array of player data including:
  - `summonerName` - Player's summoner name
  - `championId` - Champion ID
  - `championName` - Champion name
  - `teamId` - Team ID (100 = Blue, 200 = Red)
  - `individualPosition` - Player's role/position
  - `kills`, `deaths`, `assists` - KDA statistics
  - `champLevel` - Champion level at game end
  - `goldEarned` - Total gold earned
  - `totalDamageDealtToChampions` - Damage dealt to champions

#### Team Information
- `teams` - Array of team data:
  - `teamId` - Team identifier
  - `win` - Win/loss status
  - `firstBlood`, `firstTower`, `firstDragon`, `firstBaron` - Objective firsts
  - `towerKills`, `dragonKills`, `baronKills` - Objective counts

### Advanced Statistics (via AccurateRoflParser)

#### Detailed Player Metrics
- `TIME_PLAYED` - Exact game duration in seconds
- `SKIN` - Champion skin used
- `RIOT_ID_GAME_NAME` - Riot ID game name
- `RIOT_ID_TAG_LINE` - Riot ID tag line
- `CHAMPIONS_KILLED` - Champion kills
- `NUM_DEATHS` - Death count
- `ASSISTS` - Assist count
- `GOLD_EARNED` - Gold earned
- `MINIONS_KILLED` - Minion kills (CS)
- `VISION_SCORE` - Vision score
- `TOTAL_DAMAGE_DEALT_TO_CHAMPIONS` - Damage to champions
- `WIN` - Win status ("Win"/"Fail")
- `LEVEL` - Champion level
- `INDIVIDUAL_POSITION` - Player position
- `TEAM` - Team ID

#### Item Information
- `ITEM0` through `ITEM6` - Item IDs in each slot
- `ITEMS_PURCHASED` - Total items purchased

## Patch-Specific Features

### Item Database
Patch 15.14 includes the following notable items:
- **Legendary Items**: Trinity Force, Infinity Edge, Rapid Firecannon, etc.
- **Mythic Items**: Divine Sunderer, Luden's Companion, etc.
- **Consumables**: Health Potions, Refillable Potion
- **Trinkets**: Stealth Ward

### Champion Data
- Champion images available via Data Dragon CDN
- Champion names and IDs mapped correctly
- Position data includes modern role assignments

### Game Mode Support
- **Ranked Solo/Duo** (Queue ID: 420)
- **Ranked Flex** (Queue ID: 440)
- **Normal Draft** (Queue ID: 400)
- **Normal Blind** (Queue ID: 430)
- **ARAM** (Queue ID: 450)

## Data Extraction Methods

### Multiple Parser Strategies
The application uses several parsing strategies to handle different ROFL file variations:

1. **AccurateRoflParser** - Most detailed parsing using `statsJson` extraction
2. **EnhancedRoflParser** - Zlib decompression and JSON parsing
3. **RoflParser** - Standard binary parsing with BinData
4. **SimpleRoflParser** - Basic header and metadata extraction
5. **BasicRoflHandler** - Fallback for minimal file validation

### Version Extraction
All parsers now extract both:
- **Full Version**: Complete patch version (e.g., "15.14.695.3589")
- **Patch Number**: Major.minor version (e.g., "15.14")

## Limitations and Known Issues

### Data Consistency
- Some older ROFL files may have incomplete metadata
- Item IDs may reference legacy items not in current patch
- Champion position data may vary by patch

### Parser Compatibility
- Different parsers may extract varying levels of detail
- Fallback mechanisms ensure basic functionality
- Team organization may differ between parsers

## Future Patch Considerations

When updating to new patches, consider:
1. **Item Database Updates** - New items may be added
2. **Champion Changes** - New champions and reworks
3. **Data Field Additions** - Riot may add new statistics
4. **Parser Adjustments** - File structure may evolve

## Usage in Application

The patch number is now available in the game info section of all parsed replays, allowing for:
- Patch-specific analysis
- Historical comparison
- Version-aware feature enabling
- Better error handling for patch mismatches

---

*Last Updated: Current development version*
*Patch Information Source: Riot Games Data Dragon API*