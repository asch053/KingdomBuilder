local sKingdomNode = "kingdom"; -- Global or passed around

-- Stores the effects of buildings, edicts, etc. Needs population!
local tBuildingEffects = {
    ["House"] = { economy = 0, loyalty = 0, stability = 0, unrest = -1, population = 50 }, -- From UC, not exact UR rules for pop
    ["Inn"] = { economy = 1, loyalty = 1, stability = 0, basevalue = 500, population = 30 },
    ["Temple"] = { economy = 0, loyalty = 2, stability = 2, unrest = -2, population = 50 },
    ["Farm"] = { consumption_mod = -2 },
    ["Sawmill"] = { stability = 1, income_mod = 1 }, -- Generates 1 BP / turn in UC
    -- ... Add ALL buildings from UC and UR ...
};

local tEdictEffects = {
    ["Expansion"] = {
        ["Isolationist"] = { stability = 2, loyalty = 1, economy = -2, consumption_mod = -1 },
        ["Cautious"] = { stability = 1, economy = -1 },
        ["Standard"] = {},
        ["Aggressive"] = { stability = -1, loyalty = -1, economy = 1, consumption_bp_dice = "1d4" },
        ["Imperialist"] = { stability = -2, loyalty = -2, economy = 2, consumption_bp_dice = "2d4" },
    },
    ["Holiday"] = { -- Using UR Table A2
        ["None"] = { economy = -2, loyalty = -4 },
        ["Annual"] = { economy = -1, loyalty = -2, consumption_mod = 1 },
        ["Quarterly"] = { consumption_bp_dice = "1d3" },
        ["Monthly"] = { economy = 1, loyalty = 2, consumption_bp_dice = "1d6" },
        ["Weekly"] = { economy = 2, loyalty = 4, consumption_bp_dice = "1d12" },
    },
    ["Taxation"] = { -- Using UR Table A3
        ["Minimal"] = { economy = 2, loyalty = 2, revenue_divisor = 5 },
        ["Light"] = { economy = 1, loyalty = 1, revenue_divisor = 4 },
        ["Normal"] = { revenue_divisor = 3 },
        ["Heavy"] = { economy = -2, loyalty = -4, revenue_divisor = 2.5 },
        ["Crushing"] = { economy = -4, loyalty = -8, revenue_divisor = 2 },
    },
    ["Recruitment"] = { -- UR Table A5, simplified
        ["Pacifist"] = { fame = 2, defense = -1, economy = 2, society = 2, manpower = 0.01, elites = 0 },
        ["Peaceful"] = { fame = 1, economy = 1, society = 1, manpower = 0.05, elites = 0 },
        ["Normal"] = { manpower = 0.10, elites = 0.01 },
        ["Aggressive"] = { infamy = 1, economy = -1, society = -1, manpower = 0.15, elites = 0.03 },
        ["Warlike"] = { infamy = 2, defense = 1, economy = -2, society = -2, manpower = 0.20, elites = 0.05 },
    }
    -- ... Commission needs more complex handling ...
};

-- Base population by terrain (UR Table C1, simplified)
local tTerrainPop = {
    ["Plains"] = 100, ["Forest"] = 50, ["Hills"] = 50, ["Mountains"] = 25, ["Desert"] = 25, ["Swamp"] = 25, ["Jungle"] = 25, ["Cavern"] = 25
    -- Add Coastline/River multipliers later
};
local tImprovementPop = { -- UR, simplified
    ["Farm"] = 100, ["Fisheries"] = 50, ["Fort"] = 50, ["Mine"] = 25, ["Quarry"] = 25, ["Sawmill"] = 25, ["Watchtower"] = 25, ["Bridge"]=25, ["Canal"]=25, ["Highway"]=25
};

-- Main recalculation function
function recalculateKingdomStats()
    local nodeKingdom = DB.findNode(sKingdomNode);
    if not nodeKingdom then return end;

    local baseEcon, baseLoy, baseStab = 0, 0, 0;
    local baseCons = 0;
    local basePop = 0;
    local settlementCount = 0;
    local districtCount = 0;
    local hexCount = 0;

    -- 1. Alignment Bonuses (using UC standard bonuses)
    local sAlign = DB.getValue(nodeKingdom, "stats.alignment", "N");
    if string.find(sAlign, "L") then baseEcon = baseEcon + 2; end
    if string.find(sAlign, "C") then baseLoy = baseLoy + 2; end
    if string.find(sAlign, "G") then baseLoy = baseLoy + 2; end
    if string.find(sAlign, "E") then baseEcon = baseEcon + 2; end
    if sAlign == "N" then baseStab = baseStab + 4;
    elseif string.find(sAlign, "N") then baseStab = baseStab + 2; end

    -- 2. Leader Bonuses (simplified - assumes correct data on char sheet node)
    for _, nodeLeader in pairs(DB.getChildren(nodeKingdom .. ".leaders")) do
        local sPosition = DB.getValue(nodeLeader, "position", "");
        local sAttribute = DB.getValue(nodeLeader, "attribute", "");
         -- Need to get the character sheet node and read the actual attribute modifier
         -- This requires finding the char node based on the escaped path key
         -- local nodeChar = DB.findNode(unescapePath(DB.getName(nodeLeader))); -- Pseudocode
         -- local attrMod = ActorManager.getAbilityModifier(nodeChar, string.lower(sAttribute));
         local attrMod = 2; -- Placeholder! Replace with actual lookup

         -- Apply bonus based on position (needs full table)
         if sPosition == "Ruler" then baseEcon = baseEcon + attrMod; end -- Simplified, UC rules are more complex based on size
         if sPosition == "Councilor" then baseLoy = baseLoy + attrMod; end
         if sPosition == "General" then baseStab = baseStab + attrMod; end
         if sPosition == "Treasurer" then baseEcon = baseEcon + attrMod; end
         -- ... Add all leader roles and their attribute bonuses ...
    end

    -- 3. Hexes (Count, Population, Consumption base)
     for _, nodeHex in pairs(DB.getChildren(nodeKingdom .. ".hexes")) do
        hexCount = hexCount + 1;
        local sTerrain = DB.getValue(nodeHex, "terrain", "Plains");
        local sImprovement = DB.getValue(nodeHex, "improvement", "");

        basePop = basePop + (tTerrainPop[sTerrain] or 0);
        basePop = basePop + (tImprovementPop[sImprovement] or 0);
        -- Apply river/coast multipliers later

        -- Consumption from Improvements (e.g., Fort adds +1)
        if sImprovement == "Fort" then baseCons = baseCons + 1; end
        -- ... Check for other improvements affecting consumption ...
     end
     baseCons = baseCons + hexCount; -- Base Consumption = Size

    -- 4. Settlements & Buildings (Stats, Population, Districts)
    local totalBuildingEcon, totalBuildingLoy, totalBuildingStab = 0,0,0;
    for _, nodeSettlement in pairs(DB.getChildren(nodeKingdom .. ".settlements")) do
        settlementCount = settlementCount + 1;
        local nDistricts = DB.getValue(nodeSettlement, "districts", 1);
        districtCount = districtCount + nDistricts;

        local settlementPopMultiplier = 1; -- Default town pop
        local settlementLots = DB.getChildCount(nodeSettlement, "buildings");
        if settlementLots <= 4 then settlementPopMultiplier = 0.5; -- Village
        elseif settlementLots >= 17 then settlementPopMultiplier = 2; -- City
        -- Metropolis multiplier needs district check
        end

        for _, nodeBuilding in pairs(DB.getChildren(nodeSettlement, "buildings")) do
            local sType = DB.getValue(nodeBuilding, "type", "");
            local nCompletionMonth = DB.getValue(nodeBuilding, "completion_month", 0);
            -- Check if building is completed based on current kingdom month/year (add later)
            local bCompleted = true; -- Assume completed for now

            if bCompleted and tBuildingEffects[sType] then
                local effects = tBuildingEffects[sType];
                totalBuildingEcon = totalBuildingEcon + (effects.economy or 0);
                totalBuildingLoy = totalBuildingLoy + (effects.loyalty or 0);
                totalBuildingStab = totalBuildingStab + (effects.stability or 0);
                baseCons = baseCons + (effects.consumption_mod or 0);
                -- Add population from building, adjusted by multiplier
                 basePop = basePop + ( (effects.population or 0) * settlementPopMultiplier );
                 -- Add fame/infamy from buildings later
                 -- Add item slots later
                 -- Add settlement modifiers (Corruption, Crime etc) later
            end
        end
    end

    -- 5. Edicts (Stats, Consumption)
    local totalEdictEcon, totalEdictLoy, totalEdictStab = 0,0,0;
    local totalEdictConsMod = 0;
    local totalEdictFame, totalEdictInfamy = 0,0;
    local manpowerPerc = 0.10; -- default normal
    local elitePerc = 0.01; -- default normal

    for edictType, levels in pairs(tEdictEffects) do
        local sLevel = DB.getValue(nodeKingdom, "edicts." .. string.lower(edictType), "Standard"); -- Default may vary
        if levels[sLevel] then
            local effects = levels[sLevel];
            totalEdictEcon = totalEdictEcon + (effects.economy or 0);
            totalEdictLoy = totalEdictLoy + (effects.loyalty or 0);
            totalEdictStab = totalEdictStab + (effects.stability or 0);
            totalEdictConsMod = totalEdictConsMod + (effects.consumption_mod or 0);
            totalEdictFame = totalEdictFame + (effects.fame or 0);
            totalEdictInfamy = totalEdictInfamy + (effects.infamy or 0);
            if edictType == "Recruitment" then
                manpowerPerc = effects.manpower or manpowerPerc;
                elitePerc = effects.elites or elitePerc;
            end
            -- Handle BP dice consumption later (needs random roll during upkeep)
        end
    end

    -- 6. Calculate Final Stats
    local nUnrest = DB.getValue(nodeKingdom, "stats.unrest", 0);
    local finalEcon = baseEcon + totalBuildingEcon + totalEdictEcon - nUnrest;
    local finalLoy = baseLoy + totalBuildingLoy + totalEdictLoy - nUnrest;
    local finalStab = baseStab + totalBuildingStab + totalEdictStab - nUnrest;
    local finalCons = math.max(0, baseCons + totalEdictConsMod); -- Consumption can't be negative
    local finalControlDC = 20 + hexCount + districtCount; -- Add other modifiers later

    -- 7. Calculate Population derived stats
    local finalManpower = math.floor(basePop * manpowerPerc);
    local finalElites = math.floor(basePop * elitePerc);

    -- 8. Update DB (use temporary nodes for calculated values displayed in window)
    DB.setValue(nodeKingdom, "stats.economy_calc", "number", finalEcon);
    DB.setValue(nodeKingdom, "stats.loyalty_calc", "number", finalLoy);
    DB.setValue(nodeKingdom, "stats.stability_calc", "number", finalStab);
    DB.setValue(nodeKingdom, "stats.consumption_calc", "number", finalCons); -- Store calculated consumption
    DB.setValue(nodeKingdom, "stats.control_dc_calc", "number", finalControlDC);
    DB.setValue(nodeKingdom, "stats.population_calc", "number", basePop);
    DB.setValue(nodeKingdom, "stats.manpower_calc", "number", finalManpower);
    DB.setValue(nodeKingdom, "stats.elites_calc", "number", finalElites);
    DB.setValue(nodeKingdom, "stats.hex_count_calc", "number", hexCount);
    DB.setValue(nodeKingdom, "stats.settlement_count_calc", "number", settlementCount);

    -- Update Fame/Infamy
    local baseFame = DB.getValue(nodeKingdom, "stats.fame", 0);
    local baseInfamy = DB.getValue(nodeKingdom, "stats.infamy", 0);
    DB.setValue(nodeKingdom, "stats.fame_calc", "number", baseFame + totalEdictFame); -- Add building fame later
    DB.setValue(nodeKingdom, "stats.infamy_calc", "number", baseInfamy + totalEdictInfamy); -- Add building infamy later

    -- Update edict effect labels (find window and set text)
    updateEdictEffectLabels(); -- Need to write this function
end

-- Called when an edict dropdown changes
function onEdictChanged()
    -- Could recalculate just the affected stats, or do a full recalc
    recalculateKingdomStats();
end

-- Function to update the effect labels on the Edicts tab
function updateEdictEffectLabels()
    local nodeKingdom = DB.findNode(sKingdomNode);
    if not nodeKingdom then return end;

    local w = Interface.findWindow("kingdom_manager", nil);
    if not w then return end;

    for edictType, levels in pairs(tEdictEffects) do
        local sLevel = DB.getValue(nodeKingdom, "edicts." .. string.lower(edictType), "Standard");
        local effectString = "";
        if levels[sLevel] then
            local effects = levels[sLevel];
            local parts = {};
            if effects.economy then table.insert(parts, "Econ:" .. string.format("%+d", effects.economy)); end
            if effects.loyalty then table.insert(parts, "Loy:" .. string.format("%+d", effects.loyalty)); end
            if effects.stability then table.insert(parts, "Stab:" .. string.format("%+d", effects.stability)); end
            if effects.consumption_mod then table.insert(parts, "ConsMod:" .. string.format("%+d", effects.consumption_mod)); end
            if effects.consumption_bp_dice then table.insert(parts, "ConsDice:" .. effects.consumption_bp_dice); end
            if effects.fame then table.insert(parts, "Fame:" .. string.format("%+d", effects.fame)); end
            if effects.infamy then table.insert(parts, "Infamy:" .. string.format("%+d", effects.infamy)); end
            if effects.defense then table.insert(parts, "Defense:" .. string.format("%+d", effects.defense)); end
            if effects.society then table.insert(parts, "Society:" .. string.format("%+d", effects.society)); end
            if effects.revenue_divisor then table.insert(parts, "TaxDiv:" .. effects.revenue_divisor); end
            effectString = table.concat(parts, ", ");
        end
        -- Assumes label controls are named like 'expansion_effect'
        local labelControl = w.findWidget(string.lower(edictType) .. "_effect");
        if labelControl then
            labelControl.setText(effectString);
        end
    end
end


-- Function called when window opens
function onInit()
    -- Set the datasource for the main window
    local nodeKingdom = DB.findNode(sKingdomNode);
    if not nodeKingdom then
        -- Optional: Create a basic kingdom node if one doesn't exist
        nodeKingdom = DB.createNode(sKingdomNode);
        DB.setValue(nodeKingdom, "stats.name", "string", "New Kingdom");
        DB.setValue(nodeKingdom, "stats.treasury", "number", 50); -- Example starting BP
        -- Set other defaults...
        Debug.console("Created default kingdom node");
    end
    getDatabaseNode().setDatasource(nodeKingdom);

    -- Perform initial calculation
    recalculateKingdomStats();

    -- Register for updates if data changes elsewhere (more advanced)
    -- DB.addHandler(sKingdomNode, "onChildUpdate", recalculateKingdomStats);
end

-- Add functions for adding/removing settlements, buildings, hexes
-- Add function for nextTurn logic (upkeep, income, events)

-- Need Lua tables representing the Event Tables from UC/UR
-- Example structure (needs full population)
local tBeneficialKingdomEvents = { -- UC Table 4-8
    [1] = { name="Archaeological find", effect=function() triggerArchaeologicalFind() end }, -- Link to specific effect functions
    [8] = { name="Diplomatic overture", effect=function() triggerDiplomaticOverture() end },
    -- ... Add all events ...
};
local tDangerousKingdomEvents = { -- UC Table 4-9
    [1] = { name="Assassination attempt", effect=function() triggerAssassinationAttempt() end },
    -- ... Add all events ...
};
-- ... Add Settlement Event tables too ...
local tEventTypeDangerLevel = { -- UC Table 4-7 condensed
    [1] = { name="Natural blessing", beneficial=true, type="Kingdom", reroll=true },
    [3] = { name="Good weather", beneficial=true, type="Kingdom", reroll=true },
    [5] = { name="Beneficial kingdom event", beneficial=true, type="Kingdom" },
    [26] = { name="Dangerous kingdom event", beneficial=false, type="Kingdom" },
    [51] = { name="Beneficial settlement event", beneficial=true, type="Settlement" },
    [76] = { name="Dangerous settlement event", beneficial=false, type="Settlement" },
    [97] = { name="Bandit activity", beneficial=false, type="Kingdom", reroll=true },
    [98] = { name="Squatters", beneficial=false, type="Settlement", reroll=true },
    [99] = { name="Monster attack", beneficial=false, type="Both", reroll=true }, -- Can be kingdom or settlement
    [100] = { name="Vandals", beneficial=false, type="Settlement", reroll=true },
};


-- Function to advance the kingdom turn by one month
function advanceMonth()
    local nodeKingdom = DB.findNode(sKingdomNode);
    if not nodeKingdom then
        Debug.console("ERROR: Kingdom node not found for advanceMonth.");
        return;
    end

    -- Increment Month/Year
    local nCurrentMonth = DB.getValue(nodeKingdom, "stats.current_month", 1);
    local nCurrentYear = DB.getValue(nodeKingdom, "stats.current_year", 4710); -- Example starting year
    nCurrentMonth = nCurrentMonth + 1;
    if nCurrentMonth > 12 then
        nCurrentMonth = 1;
        nCurrentYear = nCurrentYear + 1;
    end
    DB.setValue(nodeKingdom, "stats.current_month", "number", nCurrentMonth);
    DB.setValue(nodeKingdom, "stats.current_year", "number", nCurrentYear);
    ChatManager.System("Advancing kingdom turn to Month " .. nCurrentMonth .. ", Year " .. nCurrentYear .. ".");

    -- Phase 1: Upkeep
    performUpkeep(nodeKingdom);

    -- Phase 2: Edict (Player makes choices via UI - already done implicitly)
    -- We assume edicts set in the UI are the ones for this turn.

    -- Phase 3: Income
    performIncome(nodeKingdom);

    -- Phase 4: Event
    checkForEvent(nodeKingdom);

    -- Final Recalculation (might be redundant if done within phases, but ensures UI updates)
    recalculateKingdomStats();
end

-- UPKEEP LOGIC (Simplified)
function performUpkeep(nodeKingdom)
    ChatManager.System("Beginning Upkeep Phase...");
    local nStability = DB.getValue(nodeKingdom, "stats.stability_calc", 0);
    local nUnrest = DB.getValue(nodeKingdom, "stats.unrest", 0);
    local nControlDC = DB.getValue(nodeKingdom, "stats.control_dc_calc", 20);
    local nTreasury = DB.getValue(nodeKingdom, "stats.treasury", 0);
    local nConsumption = DB.getValue(nodeKingdom, "stats.consumption_calc", 0);

    -- Step 1: Stability Check
    local stabRoll = math.random(1, 20);
    local stabCheck = stabRoll + nStability; -- Note: Recalced stats already subtract unrest
    ChatManager.System("  Stability Check: Rolled " .. stabRoll .. " + " .. nStability .. " = " .. stabCheck .. " vs DC " .. nControlDC);
    if stabRoll == 1 then
        ChatManager.System("    Natural 1! Check fails.");
        nUnrest = nUnrest + math.random(1, 4); -- Fail by 5 or more equivalent
    elseif stabRoll == 20 then
         ChatManager.System("    Natural 20! Check succeeds.");
         if nUnrest > 0 then nUnrest = nUnrest - 1; else nTreasury = nTreasury + 1; end
    elseif stabCheck >= nControlDC then
        ChatManager.System("    Success!");
        if nUnrest > 0 then nUnrest = nUnrest - 1; else nTreasury = nTreasury + 1; end
    elseif (nControlDC - stabCheck) <= 4 then
         ChatManager.System("    Failure (by 4 or less).");
        nUnrest = nUnrest + 1;
    else -- Fail by 5+
        ChatManager.System("    Failure (by 5 or more).");
        nUnrest = nUnrest + math.random(1, 4);
    end

    -- Step 2: Pay Consumption
    ChatManager.System("  Paying Consumption: " .. nConsumption .. " BP");
    nTreasury = nTreasury - nConsumption;
    if nTreasury < 0 then
        ChatManager.System("    Treasury is negative! Unrest increases by 2.");
        nUnrest = nUnrest + 2;
    end

    -- Step 3: Fill Magic Item Slots (Needs implementation)
    ChatManager.System("  Checking magic item slots...");

     -- Step 4: Modify Unrest based on negative attributes
     local econCheck = DB.getValue(nodeKingdom, "stats.economy_calc", 0);
     local loyCheck = DB.getValue(nodeKingdom, "stats.loyalty_calc", 0);
     local stabCheckVal = DB.getValue(nodeKingdom, "stats.stability_calc", 0); -- Renamed to avoid conflict
     local unrestIncreaseNeg = 0;
     if econCheck < 0 then unrestIncreaseNeg = unrestIncreaseNeg + 1; end
     if loyCheck < 0 then unrestIncreaseNeg = unrestIncreaseNeg + 1; end
     if stabCheckVal < 0 then unrestIncreaseNeg = unrestIncreaseNeg + 1; end
     if unrestIncreaseNeg > 0 then
         ChatManager.System("  Unrest increases by " .. unrestIncreaseNeg .. " due to negative attributes.");
         nUnrest = nUnrest + unrestIncreaseNeg;
     end

     -- Check for hex loss / anarchy
     if nUnrest >= 20 then
         ChatManager.System("  KINGDOM FALLS INTO ANARCHY! Unrest is " .. nUnrest);
         -- Implement anarchy effects (stop actions, checks = 0)
     elseif nUnrest >= 11 then
         ChatManager.System("  Unrest is " .. nUnrest .. "! Kingdom loses 1 hex.");
         -- Implement hex loss logic (player choice or random?)
     end

    -- Update DB
    DB.setValue(nodeKingdom, "stats.unrest", "number", nUnrest);
    DB.setValue(nodeKingdom, "stats.treasury", "number", nTreasury);
    ChatManager.System("Upkeep Phase Complete. Unrest: " .. nUnrest .. ", Treasury: " .. nTreasury .. " BP.");
end

-- INCOME LOGIC (Simplified)
function performIncome(nodeKingdom)
     ChatManager.System("Beginning Income Phase...");
     local nEconomy = DB.getValue(nodeKingdom, "stats.economy_calc", 0);
     local nControlDC = DB.getValue(nodeKingdom, "stats.control_dc_calc", 20);
     local nTreasury = DB.getValue(nodeKingdom, "stats.treasury", 0);
     local nTaxDivisor = 3; -- Default for Normal Taxation

     -- Get taxation level and divisor (needs full implementation from Edict Effects)
     local sTaxLevel = DB.getValue(nodeKingdom, "edicts.taxation", "Normal");
     if tEdictEffects["Taxation"][sTaxLevel] and tEdictEffects["Taxation"][sTaxLevel].revenue_divisor then
         nTaxDivisor = tEdictEffects["Taxation"][sTaxLevel].revenue_divisor;
     end
     ChatManager.System("  Taxation Level: " .. sTaxLevel .. " (Divisor: " .. nTaxDivisor .. ")");

     -- Step 4: Collect Taxes
     local econRoll = math.random(1, 20);
     local econCheck = econRoll + nEconomy; -- Recalced stats already subtract unrest
     ChatManager.System("  Economy Check: Rolled " .. econRoll .. " + " .. nEconomy .. " = " .. econCheck .. " vs DC " .. nControlDC);

     local nTaxRevenue = 0;
     if econRoll == 1 then
         ChatManager.System("    Natural 1! Check fails. No tax revenue.");
     elseif econRoll == 20 then
         ChatManager.System("    Natural 20! Check automatically succeeds.");
         nTaxRevenue = math.floor(econCheck / nTaxDivisor);
     elseif econCheck >= nControlDC then
         ChatManager.System("    Success!");
         nTaxRevenue = math.floor(econCheck / nTaxDivisor);
     else
         ChatManager.System("    Failure! No tax revenue.");
     end

     if nTaxRevenue > 0 then
         ChatManager.System("  Collected " .. nTaxRevenue .. " BP in taxes.");
         nTreasury = nTreasury + nTaxRevenue;
         DB.setValue(nodeKingdom, "stats.treasury", "number", nTreasury);
     end
     ChatManager.System("Income Phase Complete. Treasury: " .. nTreasury .. " BP.");
     -- Steps 1-3 (Withdrawals, Deposits, Selling Items) would need player interaction/buttons
end

-- EVENT LOGIC (Basic Structure)
function checkForEvent(nodeKingdom)
    ChatManager.System("Beginning Event Phase...");
    -- Track event chance (needs persistent storage, perhaps in DB)
    local nEventChance = DB.getValue(nodeKingdom, "stats.event_chance", 25); -- UC rule p. 208
    local eventRoll = math.random(1, 100);
    ChatManager.System("  Event Check: Rolled " .. eventRoll .. " vs Chance " .. nEventChance .. "%");

    if eventRoll <= nEventChance then
        ChatManager.System("    Event Occurs!");
        DB.setValue(nodeKingdom, "stats.event_chance", "number", 25); -- Reset chance

        local dangerRoll = math.random(1, 100);
        local eventDetails = nil;
        for threshold, data in pairs(tEventTypeDangerLevel) do
            if dangerRoll <= threshold then
                eventDetails = data;
                break;
            end
        end

        if eventDetails then
            ChatManager.System("    Event Type: " .. eventDetails.name);
            triggerEvent(nodeKingdom, eventDetails);
            if eventDetails.reroll then
                ChatManager.System("    Rerolling for additional event...");
                local dangerRoll2 = math.random(1, 100);
                -- Find and trigger second event, avoiding duplicates if possible
            end
        else
             ChatManager.System("    Error determining event type!");
        end

    else
        ChatManager.System("    No event this month.");
        nEventChance = math.min(95, nEventChance + 5); -- UC p.114 rule; Cap at 95%
        DB.setValue(nodeKingdom, "stats.event_chance", "number", nEventChance);
    end
     ChatManager.System("Event Phase Complete.");
end

-- Function to actually trigger a specific event
function triggerEvent(nodeKingdom, eventDetails)
    local eventTable = nil;
    if eventDetails.type == "Kingdom" then
        eventTable = eventDetails.beneficial and tBeneficialKingdomEvents or tDangerousKingdomEvents;
    elseif eventDetails.type == "Settlement" then
        -- eventTable = eventDetails.beneficial and tBeneficialSettlementEvents or tDangerousSettlementEvents;
        ChatManager.System("    (Settlement event table needed)"); -- Placeholder
    elseif eventDetails.type == "Both" then
        -- Randomly choose Kingdom or Settlement? Needs rule clarification
        ChatManager.System("    (Kingdom/Settlement event table needed)"); -- Placeholder
    end

    if eventTable then
         -- Need a way to roll on the specific d% table for the chosen category
         -- local specificEventRoll = math.random(1,100);
         -- local chosenEvent = -- find event in eventTable based on roll
         -- if chosenEvent and chosenEvent.effect then
         --     ChatManager.System("    Specific Event: " .. chosenEvent.name);
         --     chosenEvent.effect(); -- Call the Lua function for the event
         -- else ChatManager.System("    Could not determine specific event or effect function missing."); end
         ChatManager.System("    (Specific event roll/trigger needed)"); -- Placeholder
    end
end

-- Placeholder functions for specific event effects
function triggerArchaeologicalFind() ChatManager.System("      Effect: Archaeological Find triggered!"); end
function triggerDiplomaticOverture() ChatManager.System("      Effect: Diplomatic Overture triggered!"); end
function triggerAssassinationAttempt() ChatManager.System("      Effect: Assassination Attempt triggered!"); end
-- ... Need functions for ALL events ...