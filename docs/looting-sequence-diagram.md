# Looting Corpses Sequence Diagram

```mermaid
sequenceDiagram
    participant User
    participant MainLoop
    participant LootMobs
    participant NavToID
    participant LootCorpse
    participant GetRule
    participant DB
    participant LootItem
    participant Cursor
    participant History
    participant Actors

    User->>MainLoop: Start LootNScoot
    
    MainLoop->>MainLoop: Check conditions (invis, combat, etc.)
    
    alt Looting Enabled
        MainLoop->>LootMobs: lootMobs(limit)
        
        LootMobs->>LootMobs: Check if in safe zone
        LootMobs->>LootMobs: Count corpses in radius
        LootMobs->>LootMobs: Check for player corpse
        
        alt Has Player Corpse & LootMyCorpse
            LootMobs->>LootMobs: Target player corpse
            LootMobs->>LootMobs: /corpse command
            LootMobs->>LootMobs: /lootall
        end
        
        loop For each NPC corpse
            LootMobs->>LootMobs: Check if already looted
            LootMobs->>NavToID: navToID(corpseID)
            NavToID->>NavToID: Navigate within 10 units
            NavToID-->>LootMobs: At corpse
            
            LootMobs->>LootCorpse: lootCorpse(corpseID)
            
            LootCorpse->>LootCorpse: Target corpse
            LootCorpse->>LootCorpse: Open loot window
            LootCorpse->>LootCorpse: Get item count
            
            loop For each item on corpse
                LootCorpse->>GetRule: getRule(item, 'loot')
                
                GetRule->>DB: lookupLootRule(itemID)
                DB-->>GetRule: rule, classes, link
                
                alt No rule exists (new item)
                    GetRule->>GetRule: Apply AutoRules
                    GetRule->>GetRule: addNewItem()
                    GetRule->>Actors: Send new item notification
                end
                
                GetRule->>GetRule: Check lore items
                GetRule->>GetRule: Check nodrop settings
                GetRule->>GetRule: Check class restrictions
                GetRule->>GetRule: Check bag space
                GetRule->>GetRule: Check augments/spells
                GetRule->>GetRule: Check quest items
                
                GetRule-->>LootCorpse: Return rule & qKeep
                
                alt Should Loot Item
                    LootCorpse->>LootCorpse: Add to corpseItems list
                else Ignore/Ask
                    LootCorpse->>History: insertIntoHistory(item, "Left/Ask")
                end
            end
            
            loop For each item to loot
                LootCorpse->>LootItem: lootItem(item, index, rule)
                
                LootItem->>LootItem: /itemnotify loot slot
                LootItem->>LootItem: Handle confirmation dialog
                
                alt Rule is Destroy
                    LootItem->>Cursor: Wait for cursor
                    LootItem->>LootItem: /destroy
                end
                
                LootItem->>Cursor: checkCursor()
                Cursor->>Cursor: /autoinv until clear
                
                alt Quest Item
                    LootItem->>User: Report quest progress
                end
                
                LootItem->>History: insertIntoHistory(item, action)
                History->>DB: Insert into history table
                History-->>LootItem: History entry
            end
            
            LootCorpse->>LootCorpse: Close loot window
            LootCorpse->>LootCorpse: Report skipped items
            LootCorpse-->>LootMobs: Looting complete
            
            LootMobs->>Actors: Send looted items data
            LootMobs->>LootMobs: Mark corpse as looted
        end
        
        LootMobs->>Actors: FinishedLooting()
        LootMobs-->>MainLoop: Return
    end
    
    MainLoop->>MainLoop: Continue main loop
```

## Key Components

### lootMobs()
- Main entry point for corpse looting
- Validates looting conditions (invisibility, zone, combat)
- Finds corpses within configured radius
- Processes player corpse separately if needed
- Iterates through NPC corpses up to configured limit

### lootCorpse()
- Opens loot window for specific corpse
- Scans all items on corpse
- Determines loot action for each item via getRule()
- Separates lore and non-lore items
- Processes items in order
- Reports skipped items

### getRule()
- Looks up existing loot rules from database (Personal > Global > Normal)
- Applies auto-rules for new items if configured
- Validates lore items (already have?)
- Checks nodrop settings
- Validates class restrictions
- Checks bag space availability
- Handles special cases (augments, spells, quest items)
- Returns action: Keep, Sell, Destroy, Ignore, Ask, etc.

### lootItem()
- Executes the actual looting action
- Uses /itemnotify to select item
- Handles nodrop confirmation dialogs
- Destroys items if configured
- Manages cursor via checkCursor()
- Records to history database
- Reports to console/chat

### Database Checks
- lookupLootRule: Checks Personal_Rules > Global_Rules > Normal_Rules
- CheckRulesDB: Queries SQLite database for item rules
- insertIntoHistory: Records looted/ignored items with timestamp

### Actors System
- Sends new item notifications to other characters
- Reports looted items for master looter coordination
- Signals when looting is complete
