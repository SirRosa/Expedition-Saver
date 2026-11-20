-- Expedition Saver v0.7.3 Story currency + reduced registry scans | UE4SS 3.x
-- Host-authoritative only. This mod is EXPERIMENTAL; back up the save.
-- The latest 2026-11-20 USMAP confirms fields and reflected signatures,
-- not the exact native save/death sequence. Every mutation is checked.
local CFG = {
    PollSeconds = 0.30,
    AnimationSample = 8,
    MaxDepth = 10000,
    EnableRespawn = true,
    EnableRespawnSound = true, -- local player only, after verified successful respawn
    EnableItemRecovery = true,
    RestoreDestroyedItems = true, -- only after native inventory reconciliation, with dedup
    MaxGearPerPlayer = 64,
    InventoryRecoveryRetryTicks = 6,
    MaxInventoryRecoveryTicks = 24,
    EnableMoneyRecovery = true,
    CleanupNativeDeathCoins = true, -- strictly proven currency drops, NEVER equipment
    DeathCoinRadius = 240, -- centimeters
    DeathCoinMaxAgeSeconds = 30,
    DeathCoinScanTicks = 100, -- watch currency drops for 30 seconds
    EnableNoPermadeath = true,
    EnablePhysicalCoins = false, -- furniture rewards NEVER spawn physical currency
    DirectFurnitureRewards = true, -- wallet credit to verified or uniquely close destroyer
    RewardNearbyPlayerRadius = 280, -- 2.8 m, solo melee reach only
    SlowPollWarnSeconds = 0.035,
    CoinBaselineEveryPolls = 30, -- 9s in healthy gameplay; avoid 1.2s full registry hitches
    CoinCriticalHealthFraction = 0.35,
    CoinCriticalEveryPolls = 4, -- keep frequent baseline checks near death
    GearFullScanPolls = 30, -- world-wide inventory scan only every 9s
    PlayerControllerScanPolls = 100, -- cache live controllers for up to 30s; invalidate on new pawn
    RewardRetryMaxTicks = 120, -- backoff up to 36 seconds, no every-300ms retry storm
    UseCoinObjectTracking = true, -- UE4SS NotifyOnNewObject avoids periodic coin registry scans
    RecentCoinMaxReferences = 512,
    StoryValueGoldFromScraps = 3, -- deliberate modded reward, not a native destruction drop
    StoryValueGoldFromXPDivisor = 6,
    StoryValuableMinScraps = 3,
    StoryValuableMinXP = 10,
    StoryArtifactScrapsPerCoin = 12, -- rare, epic or treasure objects only
    DeathCoinScanEveryPolls = 8, -- 2.4s between full scans while recovering
    RespawnDelaySeconds = 0.15,
    RespawnRetrySeconds = 1.5,
    MaxRespawnRequests = 3,
    EnableExistingPawnReviveFallback = true, -- after native server respawn failed
    FallbackAfterTicks = 15,
    BackupFile = true,
    MaxCoinsPerDrop = 100000,
    RewardDelaySeconds = 0.20,
    RetryHookSeconds = 8,
    HeartbeatDiagnosticsSeconds = 12,
    RecoveryRetrySeconds = 2,
    Verbose = false,
}
local TAG = "[ExpeditionSaver] "
local function log(s) print(TAG..tostring(s).."\n") end
local function diag(s) if CFG.Verbose then log(s) end end
local function get(o,k)
    if o == nil then return nil end
    local ok,r=pcall(function() return o[k] end)
    if ok then return r end
end
local function put(o,k,v)
    if o == nil then return false end
    local ok=pcall(function() o[k]=v end)
    if not ok then return false end
    return true
end
local function valid(o)
    if o==nil then return false end
    local ok,r=pcall(function() return o:IsValid() end)
    return ok and r==true
end
local function unwrap(o)
    if o==nil then return nil end
    local ok,r=pcall(function() return o:get() end)
    if ok then return r end
    return o
end
local function resolveWeak(o)
    if valid(o) then return o end
    if o==nil then return nil end
    local ok,r=pcall(function() return o:Get() end)
    if ok and valid(r) then return r end
end
local function asName(o)
    if o==nil then return nil end
    local ok,r=pcall(function() return o:ToString() end)
    if ok and r then return tostring(r) end
    return tostring(o)
end
local function number(o,lo,hi)
    local n=tonumber(o)
    if n and n==n and n~=math.huge and n~=-math.huge then
        n=math.floor(n)
        if n>=lo and n<=hi then return n end
    end
    return nil
end
local function enum(v)
    if type(v)=="number" then return v end
    if v==nil then return nil end
    local s=tostring(v)
    local n=tonumber(s)
    if n then return n end
    if s:find("Expedition",1,true) then return 1 end
    if s:find("Story",1,true) then return 0 end
    if s:find("Exploring",1,true) then return 2 end
    if s:find("EndScreen",1,true) then return 3 end
    if s:find("ElevatorRideDown",1,true) then return 1 end
    if s:find("Epic",1,true) then return 2 end
    if s:find("Failed",1,true) then return 1 end
    if s:find("Dead",1,true) then return 1 end
    if s:find("None",1,true) or s:find("Default",1,true) then return 0 end
    return nil -- important: tostring(enum(...)) must receive a value
end
local function failure(v)
    local n=enum(v)
    return n~=nil and n%2==1
end
local function path(o)
    if not valid(o) then return nil end
    local ok,r=pcall(function() return o:GetFullName() end)
    if ok and r then return tostring(r) end
    return tostring(o)
end
local function each(arr,callback)
    if not arr then return end
    local ok,n=pcall(function() return #arr end)
    if not ok or type(n)~="number" then return end
    for i=1,math.min(n,128) do
        local success,o=pcall(function() return unwrap(arr[i]) end)
        if success and o then callback(o,i) end
    end
end
local cache={}
local function first(cls)
    if valid(cache[cls]) then return cache[cls] end
    cache[cls]=nil
    local function live(obj)
        if not valid(obj) then return false end
        local id=path(obj)
        return id and not id:find("Default__",1,true)
    end
    local ok,obj=pcall(FindFirstOf,cls)
    if ok and live(obj) then cache[cls]=obj;return obj end
    -- FindFirstOf may return a Class Default Object before an actual actor.
    local good,items=pcall(FindAllOf,cls)
    if good and type(items)=="table" then
        for _,candidate in ipairs(items) do
            if live(candidate) then cache[cls]=candidate;return candidate end
        end
    end
end
local function all(cls)
    local ok,objects=pcall(FindAllOf,cls)
    if ok and type(objects)=="table" then return objects end
    return {}
end
local function vec(v)
    if not v then return nil end
    local x,y,z=tonumber(get(v,"X")),tonumber(get(v,"Y")),tonumber(get(v,"Z"))
    if x and y and z then return {X=x,Y=y,Z=z} end
end
local function distance2(a,b)
    if not a or not b then return math.huge end
    return (a.X-b.X)^2+(a.Y-b.Y)^2+(a.Z-b.Z)^2
end
local function location(a)
    if not valid(a) then return nil end
    local ok,r=pcall(function() return a:K2_GetComponentLocation() end)
    if ok and r then return vec(r) end
    ok,r=pcall(function() return a:K2_GetActorLocation() end)
    if ok and r then return vec(r) end
end
local function teleport(obj,dest)
    if not valid(obj) or not dest then return false end
    local rot={Pitch=0,Yaw=0,Roll=0}
    local ok,result=pcall(function() return obj:K2_TeleportTo(dest,rot) end)
    if ok and result~=false then return true end
    ok,result=pcall(function()
        return obj:K2_SetActorLocation(dest,false,{},true)
    end)
    return ok and result~=false
end
local function onHost()
    return valid(first("HeldenGameMode")) or valid(first("GameModeBase"))
end
-- Both modes use the same HeldenPlayerController / Character APIs.
-- EHeldenGameMode.Default=0 (Story), Expedition=1. Story may not have an
-- active CurrentDungeonRun, so only Expedition mechanics require that struct.
local function game()
    local gi=first("HeldenGameInstance")
    local gs=first("HeldenGameState")
    local save=gi and get(gi,"CurrentSaveGame")
    if not valid(gs) or not valid(save) then return nil end
    local gm=enum(get(gs,"GameModeType"))
    local sg=enum(get(save,"GameMode"))
    local metadataMode=enum(get(get(save,"MetaData"),"GameMode"))
    local function modeKnown(n) return n==0 or n==1 end
    if not modeKnown(sg) and not modeKnown(metadataMode) and
       not modeKnown(gm) then return nil end
    -- During transitions, the saved mode may be ahead of a stale GameState.
    -- Require agreement between both persisted values before overriding it.
    if modeKnown(sg) and modeKnown(metadataMode) and
       sg~=metadataMode then return nil end
    local expected
    if modeKnown(sg) and sg==metadataMode then expected=sg
    elseif modeKnown(sg) and gm==sg then expected=sg
    elseif modeKnown(metadataMode) and gm==metadataMode then
        expected=metadataMode
    elseif modeKnown(gm) then expected=gm
    end
    if not modeKnown(expected) then return nil end
    if gm~=expected then
        for _,candidate in ipairs(all("HeldenGameState")) do
            if valid(candidate) and enum(get(candidate,"GameModeType"))==expected then
                gs=candidate;cache.HeldenGameState=candidate;gm=expected;break
            end
        end
        if gm~=expected and not
           (sg==expected and metadataMode==expected) then return nil end
    end
    local run=get(gs,"CurrentDungeonRun")
    if expected==1 and not run then return nil end
    return {gi=gi,gs=gs,save=save,run=run,
        mode=expected,isStory=expected==0,isExpedition=expected==1,
        phase=enum(get(run,"State")) or 0,
        failed=failure(get(run,"Flags"))}
end
local S={
    slot=nil,saveKey=nil,depth=0,highestSeed=0,offset=nil,
    active=false,failed=false,phase=nil,pending={},
    sample=0,lastPoll=-1,nextBackupDepth=-1,
    nextBackupTime=-1,coinLedger={},respawned=0,
    lastMode="unknown",lastDisplay=nil,warned=false,
    lastHeartbeat=-1000,lastGuard=nil,recoveryRequired=false,
    nextMachineRepair=0,machineRepairAttempts=0,
    dropQueue={},destructionSeen={},dropAttempt=0,
    deathEvents=0,newPawnEvents=0,rewardEvents=0,rawDeathEvents=0,rawDestroyEvents=0,heartbeatTicks=1000,machineRepairCycle=1000,
    players={},recoveries={},observedDeaths=0,failedBarriers=0,coinsLocated=0,
    unresolvedTreasureLogs=0,
    damageHits={},attackIntents={},pollCycle=0,
    gearScanTick=-1,gearScanObjects={},
    cachedControllers=nil,controllerScanTick=-1,
    coinBaseline={},coinBaselineCycle=0,coinBaselineReady=false,
    coinEventsActive=false,createdCoinActors={},
    currencyCleanup={},claimedDeathCoins={},
    failureChecks=0,storyLootDiagnosticCount=0,rewardOwnerDiagnosticCount=0,
    mode=nil
}
local function deathAllowed(ctx)
    return ctx~=nil and
        (ctx.isStory or (ctx.isExpedition and
            (ctx.phase==2 or (ctx.phase==3 and (S.active or ctx.failed)))))
end
local function backupFile(slot)
    if not CFG.BackupFile then return nil end
    local base
    pcall(function() base=os.getenv("LOCALAPPDATA") end)
    if not base or base=="" then return nil end
    return base.."\\Helden\\Saved\\ExpeditionSaver_slot"..slot..".txt"
end
local function readBackup(slot,played,fails)
    local fname=backupFile(slot)
    if not fname or played==nil or fails==nil then return nil end
    local f=io.open(fname,"r")
    if not f then return nil end
    local line=f:read("*l");f:close()
    if not line then return nil end
    local ver,sl,d,t,ff=line:match("^(%S+) (%d+) (%d+) (%d+) (%d+)$")
    if ver~="EXPS1" or tonumber(sl)~=slot then return nil end
    local depth=number(d,0,CFG.MaxDepth)
    local oldTime=number(t,0,1000000000)
    local oldFails=number(ff,0,1000000000)
    if not depth or not oldTime or not oldFails then return nil end
    -- Never restore older progress to a brand-new game on the same slot.
    if played+5<oldTime or fails<oldFails then return nil end
    return depth
end
local function backupDepth(ctx,depth)
    if not CFG.BackupFile or depth<1 then return end
    if S.nextBackupDepth==depth then return end
    local slot=S.slot
    local time=number(get(ctx.save,"TimePlayed"),0,1000000000)
    local fails=number(get(ctx.save,"DungeonFails"),0,1000000000)
    local fname=slot and backupFile(slot)
    if not fname or time==nil or fails==nil then return end
    local f=io.open(fname,"w")
    if not f then return end
    f:write(string.format("EXPS1 %d %d %d %d\n",slot,depth,time,fails))
    f:close()
    S.nextBackupDepth=depth
end
local function resetForSave(ctx,key,slot)
    local oldSlot=S.slot
    local oldPending=S.pending
    local oldPlayers=S.players
    local oldRecoveries=S.recoveries
    local oldCurrencyCleanup=S.currencyCleanup
    local preserve=oldSlot==slot and S.mode==ctx.mode and
        (S.recoveryRequired or S.active or next(oldPending)~=nil)
    local oldDepth,oldSeed,oldOffset,oldActive,oldFailed=
        S.depth,S.highestSeed,S.offset,S.active,S.failed
    S.slot=slot;S.saveKey=key
    S.depth=number(get(ctx.save,"DungeonLevel"),0,CFG.MaxDepth) or 0
    if preserve and oldDepth>S.depth then S.depth=oldDepth end
    S.highestSeed=preserve and oldSeed or 0
    S.offset=preserve and oldOffset or nil
    S.active=preserve and oldActive or false
    S.failed=preserve and oldFailed or false
    S.phase=nil;S.pending=preserve and oldPending or {};S.coinLedger={}
    S.players=preserve and oldPlayers or {}
    S.recoveries=preserve and oldRecoveries or {}
    S.currencyCleanup=preserve and oldCurrencyCleanup or {}
    S.coinBaseline={};S.coinBaselineCycle=0;S.coinBaselineReady=false
    S.createdCoinActors={}
    S.claimedDeathCoins={}
    S.damageHits={};S.attackIntents={};S.pollCycle=0
    S.rewardOwnerDiagnosticCount=0
    S.gearScanTick=-1;S.gearScanObjects={}
    S.cachedControllers=nil;S.controllerScanTick=-1
    S.nextBackupDepth=-1
    S.dropQueue={};S.destructionSeen={}
    S.nextMachineRepair=0;S.machineRepairAttempts=0
    local time=number(get(ctx.save,"TimePlayed"),0,1000000000)
    local fails=number(get(ctx.save,"DungeonFails"),0,1000000000)
    if ctx.isExpedition then
        local recovered=readBackup(slot,time,fails)
        if recovered and recovered>S.depth then S.depth=recovered end
    end
    log((ctx.isStory and "Story" or "Expedition").." slot "..slot..
        " loaded; protected depth "..S.depth..
        " retainedRunState="..tostring(preserve))
end
local function keepExpedition(ctx)
    if not ctx.isExpedition or not CFG.EnableNoPermadeath then return end
    -- EndScreen+Failed is sufficient even when no previous Exploring poll ran.
    if ctx.phase==3 and ctx.failed then
        if not S.recoveryRequired then log("RECOVERY detected directly from EndScreen/Failed") end
        S.active=true;S.failed=true;S.recoveryRequired=true
    end
    local raw=number(get(ctx.save,"DungeonLevel"),0,CFG.MaxDepth)
    if not raw then return end
    if raw>S.depth then S.depth=raw;diag("reached save depth "..raw) end
    local dungeon=get(ctx.run,"DungeonActor")
    local seed=get(dungeon,"CurrentSeed")
    local lv=number(get(seed,"Level"),0,CFG.MaxDepth)
    if ctx.phase==1 or ctx.phase==2 then
        if ctx.phase==1 and S.phase~=1 and S.recoveryRequired then
            S.recoveryRequired=false;S.machineRepairAttempts=0
            log("new expedition ride started; recovery finished")
        end
        S.active=true
        if lv then
            if raw>=lv and raw<=lv+1 then S.offset=raw-lv end
            if lv>S.highestSeed then S.highestSeed=lv end
        end
    end
    if S.highestSeed>0 then
        local goal=S.highestSeed+(S.offset or 0)
        if goal>S.depth then S.depth=goal end
    end
    if (ctx.phase==3 or ctx.phase==0) and S.active and ctx.failed then
        if not S.failed then
            S.failed=true;S.recoveryRequired=true
            log("failed Expedition run; keeping dungeon depth "..S.depth)
        end
    end
    -- Clear permanent flags even during Exploration: the native game may
    -- set them at the instant the last party member dies.
    local md=get(ctx.save,"MetaData")
    if md and get(md,"bHasFailed")==true then
        if put(md,"bHasFailed",false) then
            S.recoveryRequired=true
            log("suppressed permanent failure in SaveGame metadata")
        end
    end
    if get(ctx.gs,"bExpeditionFailed")==true then
        if put(ctx.gs,"bExpeditionFailed",false) then
            S.recoveryRequired=true
            log("cleared expedition failure in runtime")
        end
    end
    if ctx.phase==3 or ctx.phase==0 then
        -- Do not clear CurrentDungeonRun.Flags.Failed: the end screen uses it.
        if raw<S.depth and (S.failed or (ctx.phase==0 and not S.active)) then
            if put(ctx.save,"DungeonLevel",S.depth) then
                log("restored Expedition depth "..raw.." -> "..S.depth)
            end
        end
    end
    backupDepth(ctx,S.depth)
end

-- Record *existing* item actors, not classes or copies. No destructive array
-- operations on the new pawn; we never create duplicated item instances.
local function snapshotMoney(char)
    if not valid(char) then return nil end
    local money=get(char,"Money")
    if not money then return nil end
    local record={}
    for _,currency in ipairs({"Gold","Artifacts","Scraps"}) do
        record[currency]=number(get(money,currency),0,100000000) or 0
    end
    return record
end
local function recoverMoney(pawn,entry)
    if not CFG.EnableMoneyRecovery or not entry.money or not valid(pawn) then return false end
    local money=get(pawn,"Money")
    if not money then log("MONEY: new pawn has no Money struct");return false end
    local changed={}
    local verified=true
    for _,currency in ipairs({"Gold","Artifacts","Scraps"}) do
        local expected=entry.money[currency] or 0
        local current=number(get(money,currency),0,100000000)
        if current~=nil and current<expected then
            local ok=put(money,currency,expected)
            local actual=get(pawn,"Money")
            local after=number(get(actual,currency),0,100000000)
            changed[#changed+1]=currency..":"..current.."->"..tostring(after)
            verified=verified and ok and after~=nil and after>=expected
        end
    end
    if #changed>0 then
        log("MONEY RESTORE "..table.concat(changed,",")..
            " verified="..tostring(verified))
    else
        diag("MONEY RESTORE none required")
    end
    return verified
end
-- Record coin actors while players are alive. Unlike inventory items, these
-- baseline refs are never mutated or destroyed and impose no per-frame hook.
local function snapshotExistingCoins()
    if not CFG.CleanupNativeDeathCoins then return end
    local existing={}
    for _,coin in ipairs(all("HeldenPhysicsCoin")) do
        if valid(coin) then
            local id=path(coin)
            if id then existing[id]=true end
        end
    end
    S.coinBaseline=existing
    S.coinBaselineReady=true
end

-- Currency actors spawned during play are recorded on construction. This
-- avoids a 9-second periodic scan through the global UObject registry in
-- Story Mode. The ONE initial level baseline remains, and we never perform
-- any refund or deletion in this callback.
local function watchNewCoin(coin)
    coin=unwrap(coin)
    if not valid(coin) then return end
    local record={ref=coin,tick=S.pollCycle}
    local ledger=S.createdCoinActors
    ledger[#ledger+1]=record
    if #ledger>CFG.RecentCoinMaxReferences then table.remove(ledger,1) end
    local inDeath=false
    for _,tracking in pairs(S.players) do
        local pawn=tracking.lastPawn
        local stat=valid(pawn) and get(pawn,"CharacterStats")
        local health=tonumber(get(stat,"CurrentHealth"))
        if (health and health<=0) or tracking.dead then
            inDeath=true;break
        end
    end
    -- Do not classify a newly created death drop as pre-existing currency.
    if not inDeath then
        local id=path(coin)
        if id then S.coinBaseline[id]=true end
    end
end

-- Native death coins can remain in the dungeon after the wallet is restored.
-- Only zero and destroy a *complete exact match* of new physical coins close
-- to the death point, after checking the new player already owns the money.
-- Never touch equipable items, normal pickups, or unrelated coins.
local function processCurrencyCleanup()
    if not CFG.CleanupNativeDeathCoins or not CFG.EnableMoneyRecovery or
       not onHost() then return end
    for key,job in pairs(S.currencyCleanup) do
        job.ticks=job.ticks+1
        if not valid(job.pawn) or not job.at then
            S.currencyCleanup[key]=nil
        else
            -- Wallet must be credited *before* a physical coin can be removed.
            -- A partial native drop (e.g. Gold+Artifacts without Scraps)
            -- is completely legitimate; requiring an exact 3-field total
            -- previously left all physical coins on the floor.
            local wallet=snapshotMoney(job.pawn)
            local funded=wallet~=nil
            for _,currency in ipairs({"Gold","Artifacts","Scraps"}) do
                if not wallet or wallet[currency]<(job.money[currency] or 0) then
                    funded=false
                end
            end
            -- One initial lookup, then 2.4s between world-wide searches;
            -- previously up to 100 FindAllOf calls in 30s after a death.
            if funded and (job.ticks==1 or
               job.ticks%CFG.DeathCoinScanEveryPolls==0) then
                local newCoins=0
                -- One immediate native registry scan; subsequent sweeps
                -- use the lightweight newly-created actor queue. Retain
                -- occasional fallbacks if the game bypasses notifications.
                local candidates
                if S.coinEventsActive and job.ticks~=1 and
                   job.ticks~=8 and job.ticks~=40 then
                    candidates={}
                    for _,rec in ipairs(S.createdCoinActors) do
                        if rec.tick>=job.startCycle-2 then
                            candidates[#candidates+1]=rec.ref
                        end
                    end
                else
                    candidates=all("HeldenPhysicsCoin")
                end
                for _,coin in ipairs(candidates) do
                    if valid(coin) then
                        local id=path(coin)
                        if id and not job.oldCoins[id] and
                           not S.claimedDeathCoins[id] and
                           not id:find("Default__",1,true) then
                            local at=location(coin)
                            if at and distance2(at,job.at)<=
                               CFG.DeathCoinRadius*CFG.DeathCoinRadius then
                                local age
                                pcall(function()
                                    age=coin:GetGameTimeSinceCreation()
                                end)
                                if type(age)=="number" and age>=0 and
                                   age<=CFG.DeathCoinMaxAgeSeconds then
                                    local world
                                    pcall(function() world=coin:GetWorld() end)
                                    local sameWorld=not job.world or
                                        (valid(world) and path(world)==job.world)
                                    -- A coin explicitly owned/instigated by
                                    -- another player or object is NOT death loot.
                                    local owner,instigator
                                    pcall(function() owner=coin:GetOwner() end)
                                    pcall(function()
                                        instigator=coin:GetInstigatorController()
                                    end)
                                    local ownerId=valid(owner) and path(owner)
                                    local instId=valid(instigator) and path(instigator)
                                    local hasForeignOwner=(ownerId and
                                        ownerId~=job.oldChar and
                                        ownerId~=job.controller) or
                                        (instId and instId~=job.controller)
                                    if sameWorld and not hasForeignOwner then
                                        local m=get(coin,"Money")
                                        local amounts={}
                                        local safe=m~=nil
                                        local positive=false
                                        for _,currency in ipairs(
                                            {"Gold","Artifacts","Scraps"}) do
                                            local n=number(get(m,currency),0,100000000)
                                            if n==nil then safe=false end
                                            amounts[currency]=n or 0
                                            if n and n>0 then positive=true end
                                            if n and n>
                                                (job.money[currency] or 0)-
                                                (job.removed[currency] or 0) then
                                                safe=false
                                            end
                                        end
                                        if safe and positive then
                                            newCoins=newCoins+1
                                            -- Clear native Money on the actor
                                            -- FIRST so a destroy replication
                                            -- delay cannot create a second
                                            -- collectible payout.
                                            local zero=true
                                            for _,currency in ipairs(
                                                {"Gold","Artifacts","Scraps"}) do
                                                if not put(m,currency,0) then
                                                    zero=false
                                                end
                                            end
                                            local actual=get(coin,"Money")
                                            for _,currency in ipairs(
                                                {"Gold","Artifacts","Scraps"}) do
                                                if number(get(actual,currency),
                                                    0,100000000)~=0 then
                                                    zero=false
                                                end
                                            end
                                            if not zero then
                                                put(coin,"Money",{
                                                    Gold=0,Artifacts=0,Scraps=0
                                                })
                                                actual=get(coin,"Money")
                                                zero=true
                                                for _,currency in ipairs(
                                                    {"Gold","Artifacts","Scraps"}) do
                                                    if number(get(actual,currency),
                                                        0,100000000)~=0 then
                                                        zero=false
                                                    end
                                                end
                                            end
                                            if zero then
                                                S.claimedDeathCoins[id]=true
                                                for _,currency in ipairs(
                                                    {"Gold","Artifacts","Scraps"}) do
                                                    job.removed[currency]=
                                                        job.removed[currency]+
                                                        amounts[currency]
                                                end
                                                local ok=pcall(function()
                                                    coin:K2_DestroyActor()
                                                end)
                                                job.cleared=job.cleared+1
                                                log("DEATH COINS REMOVED "..id..
                                                    " Gold="..amounts.Gold..
                                                    " Artifacts="..amounts.Artifacts..
                                                    " Scraps="..amounts.Scraps..
                                                    " destroyed="..tostring(ok))
                                            else
                                                job.rejected=job.rejected+1
                                                log("DEATH COINS: unable to zero "..
                                                    id.."; not destroyed")
                                            end
                                        end
                                    end
                                end
                            end
                        end
                    end
                end
            end
            local full=job.removed.Gold==job.money.Gold and
                job.removed.Artifacts==job.money.Artifacts and
                job.removed.Scraps==job.money.Scraps
            if full or job.ticks>=CFG.DeathCoinScanTicks then
                log("DEATH COINS RESULT removed="..job.cleared..
                    " Gold="..job.removed.Gold..
                    " Artifacts="..job.removed.Artifacts..
                    " Scraps="..job.removed.Scraps..
                    " nativeDropMayBePartial="..tostring(not full)..
                    " errors="..job.rejected..
                    " itemsUntouched=true")
                S.currencyCleanup[key]=nil
            end
        end
    end
end

local function gearOf(char,forceFresh)
    if not valid(char) then return {} end
    local result,seen={},{}
    local function add(item,source,slotIndex)
        item=unwrap(item)
        if not valid(item) or #result>=CFG.MaxGearPerPlayer then return end
        local id=path(item)
        if not id or seen[id] then return end
        seen[id]=true
        local cls
        pcall(function() cls=item:GetClass() end)
        if not valid(cls) then return end
        local asset=get(item,"ItemDataAsset")
        result[#result+1]={ref=item,key=id,klass=cls,
            dynamicSaveName=asName(get(item,"DynamicSaveName")),
            classPath=path(cls),
            asset=asset,assetPath=valid(asset) and path(asset) or nil,
            durability=tonumber(get(item,"ItemDurability")),
            enchant=get(item,"ItemEnchantment"),
            slotIdx=number(get(item,"CurrentInventorySlot"),0,128) or slotIndex,
            source=source}
    end
    -- The game stores inventory items in BOTH EquipedItems and ItemSlots.
    -- Previously the latter was missing, explaining 1 retained item in log.
    each(get(char,"EquipedItems"),function(item,i) add(item,"EquipedItems",i-1) end)
    each(get(char,"ItemSlots"),function(slot,i)
        if valid(slot) then add(get(slot,"CurrentItemInSlot"),"ItemSlots",i-1) end
    end)
    local owner=path(char)
    -- At most one UObject-wide equipment scan per game-thread poll,
    -- shared by all co-op players. An actual death requests a fresh list.
    -- Story inventory is already available from EquipedItems and ItemSlots.
    -- The full UObject registry query was freezing frames every nine seconds.
    -- The death path still performs ONE forced scan to recover unusual slots.
    if forceFresh or (S.mode==1 and
       (S.gearScanTick<0 or S.pollCycle-S.gearScanTick>=CFG.GearFullScanPolls)) then
        S.gearScanTick=S.pollCycle
        S.gearScanObjects=all("HeldenEquipableItem")
    end
    if forceFresh or S.mode==1 then
        for _,item in ipairs(S.gearScanObjects) do
            if valid(item) and path(get(item,"PreviousOwner"))==owner and
               valid(get(item,"CurrentSlot")) then
                add(item,"PreviousOwner")
            end
        end
    end
    table.sort(result,function(a,b)
        return (a.slotIdx or 999)<(b.slotIdx or 999)
    end)
    return result
end
local function currentPawn(pc)
    if not valid(pc) then return nil end
    local ok,pawn=pcall(function() return pc:GetPawn() end)
    if ok and valid(pawn) then return pawn end
end
local function playerControllers(force)
    -- FindAllOf scans the global UObject registry. Cache this small set
    -- across 10 engine ticks instead of repeating it for each operation.
    if force or S.cachedControllers==nil or
       S.pollCycle-S.controllerScanTick>=CFG.PlayerControllerScanPolls then
        S.cachedControllers=all("HeldenPlayerController")
        S.controllerScanTick=S.pollCycle
    end
    return S.cachedControllers
end
-- Live UE4SS(7).log: GrainRotQuickJunk reports GetPawn()=nil (raw=none)
-- while BP_HeldenPlayerController.LastPlayerChar is the valid Story player.
-- currentPawn() intentionally remains unchanged for native respawn logic.
-- Reward owner resolution MUST use LastPlayerChar when GetPawn is nil.
local function rewardCharacter(pc)
    if not valid(pc) then return nil,nil end
    local candidates={
        {pawn=currentPawn(pc),source="GetPawn"},
        {pawn=resolveWeak(unwrap(get(pc,"LastPlayerChar"))),source="LastPlayerChar"},
    }
    local tracked=S.players[path(pc)]
    if tracked and valid(tracked.lastPawn) then
        candidates[#candidates+1]={pawn=tracked.lastPawn,source="tracked-live-character"}
    end
    local seen={}
    for _,candidate in ipairs(candidates) do
        local char=unwrap(candidate.pawn)
        local id=valid(char) and path(char)
        if id and not seen[id] then
            seen[id]=true
            local money=get(char,"Money")
            -- Check actual currency fields, not merely presence of a
            -- detached UScriptStruct proxy.
            local gold=number(get(money,"Gold"),0,100000000)
            local artifacts=number(get(money,"Artifacts"),0,100000000)
            local stats=get(char,"CharacterStats")
            local health=tonumber(get(stats,"CurrentHealth"))
            local state=enum(get(char,"CharacterState"))
            if gold~=nil and artifacts~=nil and state~=1 and
               (health==nil or health>0) then
                return char,candidate.source
            end
        end
    end
    return nil,nil
end

-- In real Expedition runs the native Die_Auth and Blueprint
-- OnPlayerKilled hook were NEVER called (observed v0.3 log).
-- Monitor actual controller/pawn state and preserve inventory BEFORE death.
local function queuePlayerDeath(pc,char,snapshot,reason)
    if not CFG.EnableRespawn or not onHost() then return false end
    local ctx=game()
    if not deathAllowed(ctx) then return false end
    if not valid(pc) or (not valid(char) and snapshot==nil) then return false end
    local key=path(pc)
    if not key or S.pending[key] then return false end
    local player=false
    for _,candidate in ipairs(playerControllers()) do
        if path(candidate)==key then player=true;break end
    end
    if not player then return false end
    local inv=snapshot or gearOf(char,true)
    local tracked=S.players[key]
    local cash=(tracked and tracked.money) or snapshotMoney(char)
    local deathPos=(tracked and tracked.lastLocation) or location(char)
    local worldName=tracked and tracked.lastWorld
    if not worldName and valid(char) then
        local w
        pcall(function() w=char:GetWorld() end)
        if valid(w) then worldName=path(w) end
    end
    local oldCoins={}
    for id in pairs(S.coinBaseline) do oldCoins[id]=true end
    S.pending[key]={controller=pc,oldChar=char,gear=inv,money=cash,
        started=os.clock(),ageTicks=0,attempts=0,nextRequestTick=0,
        deathPos=deathPos,deathWorld=worldName,oldCoins=oldCoins,
        baselineReady=S.coinBaselineReady,
        mode=ctx.mode,spawned=nil,delivered=false}
    S.deathEvents=S.deathEvents+1
    log("PLAYER DEATH queued from "..tostring(reason).." controller="..key..
        " oldPawn="..tostring(path(char)).." retained="..#inv..
        " cash="..(cash and (cash.Gold.."/"..cash.Artifacts.."/"..cash.Scraps) or "nil")..
        " phase="..ctx.phase.." mode="..ctx.mode)
    return true
end
local function captureDeath(char)
    if not valid(char) then return end
    local pc
    pcall(function() pc=char:GetController() end)
    if valid(pc) then queuePlayerDeath(pc,char,nil,"Die_Auth") end
end
local function monitorPlayers(ctx)
    if not CFG.EnableRespawn or not deathAllowed(ctx) then return end
    local anyAlive,anyDanger=false,false
    for _,pc in ipairs(playerControllers()) do
        if valid(pc) then
            local key=path(pc)
            local tracking=S.players[key]
            if not tracking then
                tracking={alive=false,dead=false,lastPawn=nil,gear={},money=nil,
                    snapshotCycle=0,lastState=nil,lastHealth=nil,
                    lastLocation=nil,lastWorld=nil}
                S.players[key]=tracking
            end
            local pawn=currentPawn(pc)
            local soul=get(pc,"SoulCharacter")
            local last=get(pc,"LastPlayerChar")
            local char
            if valid(soul) and valid(pawn) and path(soul)==path(pawn) and
               valid(last) and valid(get(last,"CharacterStats")) then
                char=last
            elseif valid(pawn) and valid(get(pawn,"CharacterStats")) then
                char=pawn
            elseif valid(last) and valid(get(last,"CharacterStats")) then
                char=last
            elseif valid(tracking.lastPawn) then
                char=tracking.lastPawn
            end
            local stats=char and get(char,"CharacterStats")
            local health=tonumber(get(stats,"CurrentHealth"))
            local state=enum(get(char,"CharacterState"))
            local isSoul=valid(soul) and valid(pawn) and path(soul)==path(pawn)
            local dead=(state==1 or (health and health<=0) or isSoul or
                (ctx.isExpedition and tracking.alive and
                 ctx.phase==3 and ctx.failed))
            local activeCharacter=valid(char) and not dead and health and health>0
            if tracking.lastState~=state or tracking.lastHealth~=nil and
                    health and ((tracking.lastHealth>0)~=(health>0)) then
                log("PLAYER STATE controller="..tostring(key)..
                    " state="..tostring(state).." hp="..tostring(health)..
                    " soulPawn="..tostring(isSoul).." run="..ctx.phase)
            end
            tracking.lastState=state
            tracking.lastHealth=health
            if activeCharacter then
                anyAlive=true
                local total=get(stats,"TotalStats")
                local maxHealth=tonumber(get(total,"MaxHealth"))
                if maxHealth and maxHealth>0 and
                   health<=maxHealth*CFG.CoinCriticalHealthFraction then
                    anyDanger=true
                end
                tracking.lastPawn=char
                tracking.money=snapshotMoney(char) or tracking.money
                tracking.lastLocation=location(char) or tracking.lastLocation
                local w
                pcall(function() w=char:GetWorld() end)
                if valid(w) then tracking.lastWorld=path(w) end
                tracking.alive=true
                tracking.dead=false
                tracking.snapshotCycle=tracking.snapshotCycle+1
                if tracking.snapshotCycle>=4 or #tracking.gear==0 then
                    tracking.gear=gearOf(char)
                    tracking.snapshotCycle=0
                end
            elseif dead and not tracking.dead then
                tracking.dead=true
                if tracking.alive then
                    local ok=queuePlayerDeath(pc,tracking.lastPawn,
                        tracking.gear,"poll: CharacterState/Health/Soul/failed run")
                    if ok then S.observedDeaths=S.observedDeaths+1 end
                else
                    log("PLAYER DEAD but no prior alive snapshot; waiting for native event")
                end
            end
        end
    end
    -- One registry scan at most every 4 poll cycles, regardless of player count.
    if anyAlive then
        -- NotifyOnNewObject tracks coin creation without a FindAllOf sweep.
        -- Take just ONE initial level snapshot to index preexisting coins.
        -- On UE4SS builds without object notifications, retain the older
        -- health-adaptive periodic fallback for native death deduplication.
        S.coinBaselineCycle=S.coinBaselineCycle+1
        local period=anyDanger and CFG.CoinCriticalEveryPolls or
            CFG.CoinBaselineEveryPolls
        if not S.coinBaselineReady or
           (not S.coinEventsActive and S.coinBaselineCycle>=period) then
            S.coinBaselineCycle=0
            snapshotExistingCoins()
        end
    end
end

-- Story can have no DungeonElevator; preserve native Story spawn position
-- when available, and only revive the old pawn at a real player start.
local function respawnLocation(entry,newPawn)
    local story=entry and entry.mode==0
    local lift=first("HeldenDungeonElevator")
    if not valid(lift) and story then lift=first("HeldenElevator") end
    if valid(lift) then
        local comp=get(lift,"InteriorCollisionBox")
        local loc=location(comp) or location(lift)
        if loc then return {X=loc.X,Y=loc.Y,Z=loc.Z+80} end
    end
    if not story then return nil end
    if valid(newPawn) and
       path(newPawn)~=path(entry and entry.oldChar) then
        local at=location(newPawn)
        if at then return at end
    end
    local spawn=first("PlayerStart")
    local at=location(spawn)
    if at then return {X=at.X,Y=at.Y,Z=at.Z+80} end
    -- No valid spawn object: the last *known alive* location is preferable
    -- to a blind 0,0,0 teleport. Native respawn remains first preference.
    local last=entry and entry.deathPos
    if last then return {X=last.X,Y=last.Y,Z=last.Z+100} end
    return nil
end
local function heal(pawn)
    local stats=get(pawn,"CharacterStats")
    if not valid(stats) then return false end
    local max=tonumber(get(get(stats,"TotalStats"),"MaxHealth"))
    if not max or max<=0 or max>1000000 then return false end
    return put(stats,"CurrentHealth",max)
end
-- Item ownership must be transferred by the native Interact path. Moving
-- items to the lift ground (v0.4) only kept them in the world, not inventory.
-- Recover over multiple game-thread ticks to allow native equip replication.
local function snapshotNativeGear(pawn)
    local refs,byClass={},{ }
    local function track(item)
        item=unwrap(item)
        if not valid(item) then return end
        refs[path(item)]=true
        local klass
        pcall(function() klass=item:GetClass() end)
        local key=path(klass)
        if key then byClass[key]=(byClass[key] or 0)+1 end
    end
    each(get(pawn,"EquipedItems"),track)
    each(get(pawn,"ItemSlots"),function(slot)
        track(get(slot,"CurrentItemInSlot"))
    end)
    return refs,byClass
end
local function ownsItem(pawn,item)
    if not valid(pawn) or not valid(item) then return false end
    local refs=snapshotNativeGear(pawn)
    if refs[path(item)] then return true end
    local owner=get(item,"PreviousOwner")
    return valid(owner) and path(owner)==path(pawn) and
        valid(get(item,"CurrentSlot"))
end
local function collectAtElevator(entry,dest,pawn)
    local key=path(entry.controller)
    if not key then return end
    -- Money restoration and anti-duplication must NOT depend on the
    -- separate gear-recovery feature flag.
    if CFG.EnableItemRecovery and #entry.gear>0 then
        S.recoveries[key]={entry=entry,dest=dest,pawn=pawn,tick=0,
            done={},attempts={},recreated={},warnings={}}
    end
    recoverMoney(pawn,entry)
    if CFG.CleanupNativeDeathCoins and CFG.EnableMoneyRecovery and
       entry.baselineReady and entry.money and entry.deathPos and
       ((entry.money.Gold or 0)>0 or (entry.money.Artifacts or 0)>0 or
        (entry.money.Scraps or 0)>0) then
        S.currencyCleanup[key]={
            pawn=pawn,money=entry.money,at=entry.deathPos,
            oldCoins=entry.oldCoins or {},world=entry.deathWorld,ticks=0,
            controller=key,oldChar=path(entry.oldChar),
            startCycle=S.pollCycle,
            removed={Gold=0,Artifacts=0,Scraps=0},
            cleared=0,rejected=0
        }
        log("DEATH COINS tracking death location "..
            string.format("%.0f/%.0f/%.0f",entry.deathPos.X,
                entry.deathPos.Y,entry.deathPos.Z)..
            " Gold="..entry.money.Gold.." Artifacts="..entry.money.Artifacts..
            " Scraps="..entry.money.Scraps)
    end
    log("INVENTORY RECOVERY queued items="..#entry.gear..
        " cash="..(entry.money and
            entry.money.Gold.."/"..entry.money.Artifacts.."/"..entry.money.Scraps or "unknown"))
end
local function isOriginalItemAlreadyPresent(pawn,rec)
    if not valid(pawn) then return false end
    local refs=snapshotNativeGear(pawn)
    if refs[rec.key] then return true end
    -- Do not scan all world items for every saved item. Only the receiving
    -- pawn's inventory can prove that an item was actually restored.
    local dynamic=rec.dynamicSaveName
    if dynamic and dynamic~="None" and dynamic~="" then
        local found=false
        local function match(item)
            if valid(item) and asName(get(item,"DynamicSaveName"))==dynamic then
                found=true
            end
        end
        each(get(pawn,"EquipedItems"),match)
        each(get(pawn,"ItemSlots"),function(slot)
            match(get(slot,"CurrentItemInSlot"))
        end)
        if found then return true end
    end
    if rec.slotIdx~=nil and rec.classPath then
        -- If the native engine rebuilt the same slot with the same class,
        -- prefer that actor rather than creating a second instance.
        local items=get(pawn,"ItemSlots")
        local native
        pcall(function() native=get(items[rec.slotIdx+1],"CurrentItemInSlot") end)
        if valid(native) then
            local cls
            pcall(function() cls=native:GetClass() end)
            if path(cls)==rec.classPath then return true end
        end
    end
    return false
end
local function processInventoryRecoveries()
    if not CFG.EnableItemRecovery or not onHost() then return end
    for key,job in pairs(S.recoveries) do
        job.tick=job.tick+1
        local pawn=job.pawn
        if not valid(pawn) then
            log("INVENTORY RECOVERY aborted: pawn invalid")
            S.recoveries[key]=nil
        else
            local total=#job.entry.gear
            local retained=0
            -- Identity and native slot checks precede any spawns. A
            -- generic class-count match is unsafe: two swords of the same
            -- class are not one sword.
            for _,rec in ipairs(job.entry.gear) do
                if ownsItem(pawn,rec.ref) or
                   isOriginalItemAlreadyPresent(pawn,rec) then
                    job.done[rec.key]=true
                end
            end
            local unowned=0
            for i,rec in ipairs(job.entry.gear) do
                if job.done[rec.key] then
                    retained=retained+1
                else
                    unowned=unowned+1
                    local item=rec.ref
                    local tries=job.attempts[rec.key] or 0
                    local dest={X=job.dest.X+(i%5)*48-96,
                        Y=job.dest.Y+math.floor((i-1)/5)*48,
                        Z=job.dest.Z+25}
                    if not valid(item) and CFG.RestoreDestroyedItems and
                        not job.recreated[rec.key] and job.tick>=3 then
                        local klass=rec.klass
                        local world
                        pcall(function() world=pawn:GetWorld() end)
                        if not valid(world) then
                            local lift=first("HeldenDungeonElevator")
                            pcall(function() world=lift:GetWorld() end)
                        end
                        if valid(klass) and valid(world) then
                            local ok,new=pcall(function()
                                return world:SpawnActor(klass,dest,{Pitch=0,Yaw=0,Roll=0})
                            end)
                            job.recreated[rec.key]=true -- no repeat spawns
                            if ok and valid(new) then
                                rec.ref=new;item=new
                                if valid(rec.asset) then put(new,"ItemDataAsset",rec.asset) end
                                if rec.durability~=nil then
                                    put(new,"ItemDurability",rec.durability)
                                    pcall(function() new:OnRep_ItemDurability() end)
                                end
                                if rec.enchant~=nil then
                                    -- Preserve the original FName userdata,
                                    -- not an unsafe string->FName conversion.
                                    if put(new,"ItemEnchantment",rec.enchant) then
                                        pcall(function() new:OnRep_ItemEnchantment() end)
                                    end
                                end
                                -- Keep native unique ID generated by the engine.
                                log("INVENTORY recreated missing "..rec.key..
                                    " class="..tostring(rec.classPath))
                            else
                                log("INVENTORY cannot recreate "..rec.key)
                            end
                        end
                    end
                    if valid(item) and tries<CFG.InventoryRecoveryRetryTicks and
                        job.tick%2==1 then
                        job.attempts[rec.key]=tries+1
                        -- Don't destroy this actor: if native pickup rejects,
                        -- leaving it at the lift is better than losing it.
                        pcall(function() item:DetachFromAll() end)
                        pcall(function() item:SetSimulatePhysics(true) end)
                        local move=teleport(item,dest)
                        local pick,err=pcall(function() item:Interact(pawn) end)
                        if not ownsItem(pawn,item) then
                            local interact=get(item,"InteractComponent")
                            if valid(interact) then
                                local ok=pcall(function()
                                    job.entry.controller:Interact_Server(pawn,interact)
                                end)
                                pick=pick or ok
                            end
                        end
                        log("INVENTORY pickup "..rec.source..
                            " key="..rec.key.." move="..tostring(move)..
                            " nativeCall="..tostring(pick)..
                            " owned="..tostring(ownsItem(pawn,item))..
                            (pick and "" or " err="..tostring(err)))
                    end
                    if valid(item) and ownsItem(pawn,item) then
                        job.done[rec.key]=true
                    end
                end
            end
            -- Native pickup can be asynchronous; allow rep updates. After a
            -- bounded number of attempts, keep remaining actors on elevator
            -- floor, never claim full success.
            local allDone=true
            for _,rec in ipairs(job.entry.gear) do
                if not job.done[rec.key] then allDone=false;break end
            end
            if allDone or job.tick>=CFG.MaxInventoryRecoveryTicks then
                local recovered,failed=0,0
                for _,rec in ipairs(job.entry.gear) do
                    if job.done[rec.key] then recovered=recovered+1
                    else failed=failed+1 end
                end
                log("INVENTORY RESULT inventory="..recovered..
                    " floor_or_missing="..failed.." total="..total..
                    " fullyRestored="..tostring(failed==0))
                S.recoveries[key]=nil
            end
        end
    end
end

-- Audio is deliberately outside Unreal's game thread and does not use
-- UObject/USoundBase APIs. Install the user's NEW 44.1kHz PCM WAV unchanged.
-- UE4SS does not natively import arbitrary audio as a cooked USoundBase.
-- Tiny, source-auditable helper: Audio/respawn_audio.exe (WinMM PlaySoundW).
-- Both files must be installed. Missing files fail open without affecting
-- respawn, item recovery, currency or game performance.
local respawnAudioRoot=nil
local respawnAudioMissingLogged=false
local function audioFolder()
    if respawnAudioRoot then return respawnAudioRoot end
    local dirs={}
    local ok,info=pcall(function() return debug.getinfo(1,"S") end)
    local source=ok and info and info.source
    if type(source)=="string" and source:sub(1,1)=="@" then
        local scriptDir=source:sub(2):match("^(.*[\\/])[^\\/]+$")
        if scriptDir then dirs[#dirs+1]=scriptDir.."../Audio/" end
    end
    dirs[#dirs+1]="Mods/ExpeditionSaver/Audio/"
    dirs[#dirs+1]="ue4ss/Mods/ExpeditionSaver/Audio/"
    local function exists(path)
        local ok,h=pcall(function() return io.open(path,"rb") end)
        if ok and h then pcall(function() h:close() end);return true end
        return false
    end
    for _,dir in ipairs(dirs) do
        if exists(dir.."respawn_audio.exe") and exists(dir.."respawn.wav") then
            respawnAudioRoot=dir
            return dir
        end
    end
    return nil
end
local function playRespawnSound(pc)
    if not CFG.EnableRespawnSound then return end
    -- Every game instance plays only for its own locally controlled player.
    -- A client installation detects client respawns independently of host
    -- authority and never plays the host's or another client's events.
    if valid(pc) then
        local ok,isLocal=pcall(function() return pc:IsLocalController() end)
        if ok and isLocal==false then return end
    end
    if type(ExecuteAsync)~="function" or type(os.execute)~="function" then
        if not respawnAudioMissingLogged then
            respawnAudioMissingLogged=true
            log("RESPAWN SOUND unavailable: UE4SS ExecuteAsync/os.execute missing")
        end
        return
    end
    local dir=audioFolder()
    if not dir then
        if not respawnAudioMissingLogged then
            respawnAudioMissingLogged=true
            log("RESPAWN SOUND missing Audio/respawn.wav or respawn_audio.exe")
        end
        return
    end
    local exe=dir.."respawn_audio.exe"
    local wav=dir.."respawn.wav"
    -- Each path is double-quoted and the whole command is protected for
    -- cmd.exe /c (works with Steam libraries containing whitespace).
    if exe:find('"',1,true) or wav:find('"',1,true) then return end
    local command='""'..exe..'" "'..wav..'""'
    local ok,err=pcall(function()
        ExecuteAsync(function()
            local ran,why=pcall(os.execute,command)
            if not ran then log("RESPAWN SOUND process error: "..tostring(why)) end
        end)
    end)
    if not ok then log("RESPAWN SOUND async dispatch failed: "..tostring(err)) end
end

-- Local client-side witness for the death -> successful respawn transition.
-- This is ONLY audio: it neither respawns nor heals, moves or rewrites items.
-- The host continues to use its confirmed processDeaths() completion path.
-- Clients have no HeldenGameMode, so the host-only death queue cannot drive
-- their sound. The client must observe its own character's state instead.
local clientAudio={
    controllerId=nil,seenAlive=false,armed=false,
    pendingPawn=nil,missingControllerTicks=0,
}
local function localAudioController()
    local function choose(list)
        for _,pc in ipairs(list) do
            if valid(pc) then
                local ok,isLocal=pcall(function() return pc:IsLocalController() end)
                if ok and isLocal==true then return pc end
            end
        end
    end
    local pc=choose(playerControllers())
    -- Initial client join may have cached an empty controller list before
    -- network replication completed. Retry at most once every 3s.
    if not pc and S.pollCycle%10==0 then
        pc=choose(playerControllers(true))
    end
    return pc
end
local function markClientAudioDeath(pc)
    if not CFG.EnableRespawnSound or not valid(pc) then return end
    local ok,isLocal=pcall(function() return pc:IsLocalController() end)
    if not ok or isLocal~=true then return end
    local id=path(pc)
    if clientAudio.controllerId==id and clientAudio.seenAlive then
        clientAudio.armed=true
    end
end
local function observeClientRespawnAudio()
    if not CFG.EnableRespawnSound then return end
    local pc=localAudioController()
    if not valid(pc) then
        clientAudio.missingControllerTicks=clientAudio.missingControllerTicks+1
        if clientAudio.missingControllerTicks>100 then
            clientAudio.controllerId=nil
            clientAudio.seenAlive=false
            clientAudio.armed=false
            clientAudio.pendingPawn=nil
        end
        return
    end
    clientAudio.missingControllerTicks=0
    local pcId=path(pc)
    if clientAudio.controllerId~=pcId then
        -- New joining controller: first spawn is never a respawn.
        clientAudio.controllerId=pcId
        clientAudio.seenAlive=false
        clientAudio.armed=false
        clientAudio.pendingPawn=nil
    end

    local pawn=currentPawn(pc)
    local soul=resolveWeak(unwrap(get(pc,"SoulCharacter")))
    local isSoul=valid(pawn) and valid(soul) and path(pawn)==path(soul)
    local last=resolveWeak(unwrap(get(pc,"LastPlayerChar")))
    local function character(o)
        return valid(o) and valid(get(o,"CharacterStats"))
    end

    -- A dying old pawn may remain the controller's GetPawn while OnNewPawn
    -- already reports a fully alive replacement. Prefer the actually alive
    -- pawn, then the newer confirmed OnNewPawn target, then LastPlayerChar.
    local pawnStats=character(pawn) and get(pawn,"CharacterStats")
    local pawnHealthRaw=get(pawnStats,"CurrentHealth")
    -- get() may return zero Lua values on a missing GetPawn. tonumber()
    -- requires an explicit argument, even if nil.
    local pawnHp=tonumber(pawnHealthRaw)
    local pawnState=enum(get(pawn,"CharacterState"))
    local pawnAlive=character(pawn) and not isSoul and pawnHp and
        pawnHp>0 and pawnState~=1
    local char=nil
    if pawnAlive then
        char=pawn
    elseif clientAudio.armed and character(clientAudio.pendingPawn) then
        -- OnNewPawn can arrive before LastPlayerChar/GetPawn replicates.
        char=clientAudio.pendingPawn
    elseif character(last) then
        char=last
    elseif character(pawn) then
        char=pawn
    end

    local stats=char and get(char,"CharacterStats")
    local healthRaw=get(stats,"CurrentHealth")
    local hp=tonumber(healthRaw)
    local state=enum(get(char,"CharacterState"))
    local isDead=isSoul or state==1 or (hp and hp<=0)
    local isAlive=character(char) and not isDead and hp and hp>0

    if isDead then
        -- Require a witnessed healthy player beforehand. This prevents
        -- first join, loading a save, and joining as a spectator from
        -- triggering audio when a pawn first materializes.
        if clientAudio.seenAlive then clientAudio.armed=true end
    elseif isAlive then
        if clientAudio.armed then
            clientAudio.armed=false
            clientAudio.pendingPawn=nil
            playRespawnSound(pc)
            log("RESPAWN SOUND client verified dead->alive "..tostring(pcId))
        end
        clientAudio.seenAlive=true
    end
end

local function reviveOldPawn(entry)
    if not CFG.EnableExistingPawnReviveFallback then return false end
    local char,pc=entry.oldChar,entry.controller
    if not valid(char) or not valid(pc) then return false end
    local at=respawnLocation(entry,char)
    if not at then
        log("REVIVE FALLBACK: no safe Story/Expedition spawn location")
        return false
    end
    -- A native respawn is always attempted first. After it fails, re-enable
    -- the *existing* character (and existing inventory) rather than cloning
    -- players or silently abandoning the expedition.
    local write=put(char,"CharacterState",0)
    put(char,"bCollisionAndMovementDisable",false)
    local hp=heal(char)
    local moved=teleport(char,at)
    if not write or not hp or not moved then
        log("REVIVE FALLBACK skipped possession: state/health/teleport verification failed")
        return false
    end
    pcall(function() char:SetActorEnableCollision(true) end)
    pcall(function() char:OnRep_CharacterState() end)
    pcall(function() char:OnRep_bCollisionAndMovementDisable() end)
    local possessed,why=pcall(function() pc:Possess(char) end)
    local owns=path(currentPawn(pc))==path(char)
    if possessed and owns then
        pcall(function() pc:ClientRestart(char) end)
    end
    log("REVIVE FALLBACK stateSet="..tostring(write)..
        " healed="..tostring(hp).." moved="..tostring(moved)..
        " possess="..tostring(possessed).." owned="..tostring(owns)..
        (possessed and "" or " error="..tostring(why)))
    if write and hp and moved and owns then
        collectAtElevator(entry,at,char)
        return true
    end
    return false
end
local function processDeaths(ctx)
    if not CFG.EnableRespawn then return end
    for key,entry in pairs(S.pending) do
        -- LoopAsync/LoopInGameThread use wall time. os.clock() is process CPU
        -- time on Windows; previously a "35-second" timeout could last minutes.
        entry.ageTicks=(entry.ageTicks or 0)+1
        if entry.ageTicks>120 then
            log("respawn timed out for "..key)
            S.pending[key]=nil
        else
            local pawn=currentPawn(entry.controller)
            if entry.spawned and valid(entry.spawned) then pawn=entry.spawned end
            local soul=get(entry.controller,"SoulCharacter")
            local isSoul=valid(soul) and valid(pawn) and path(soul)==path(pawn)
            if pawn and not isSoul and path(pawn)~=path(entry.oldChar) and
               valid(get(pawn,"CharacterStats")) then
                local at=respawnLocation(entry,pawn)
                if at and teleport(pawn,at) then
                    local healed=heal(pawn)
                    collectAtElevator(entry,at,pawn)
                    log("respawn in elevator "..key.."; healed="..tostring(healed))
                    S.pending[key]=nil
                    S.respawned=S.respawned+1
                    if healed then playRespawnSound(entry.controller) end
                end
            elseif entry.attempts<CFG.MaxRespawnRequests and
                   entry.ageTicks>=(entry.nextRequestTick or 1) then
                entry.attempts=entry.attempts+1
                entry.nextRequestTick=entry.ageTicks+5
                local ok,err=pcall(function()
                    entry.controller:RespawnCharacter_Server()
                end)
                log("NATIVE RESPAWN request "..entry.attempts.." -> "..tostring(ok)..
                    (ok and "" or (": "..tostring(err))))
            elseif entry.attempts>=CFG.MaxRespawnRequests and
                   entry.ageTicks>=CFG.FallbackAfterTicks and
                   not entry.fallbackDone then
                entry.fallbackDone=true
                if reviveOldPawn(entry) then
                    log("REVIVE FALLBACK succeeded, recovered existing player pawn")
                    S.pending[key]=nil
                    S.respawned=S.respawned+1
                    playRespawnSound(entry.controller)
                end
            end
        end
    end
end
-- Automatic payout on physical destruction. There is no hotkey.
-- The game still handles its native scrap/resource drops; we add only
-- the Gold/Artifacts that the *same actor* would pay at extraction.
-- IMPORTANT: Read live structs/tables, which also sees QOL's edited values.
local function rowOf(tableObject,rowName)
    if not valid(tableObject) or not rowName then return nil end
    local key=asName(rowName)
    local ok,row=pcall(function() return tableObject:FindRow(key) end)
    if ok and row then return unwrap(row) end
    ok,row=pcall(function() return tableObject:GetRowMap() end)
    if ok and type(row)=="table" then
        return unwrap(row[key])
    end
end
local function getDataSingleton()
    local ds=first("HeldenDataSingleton")
    if valid(ds) then return ds end
    -- The game's singleton may initially exist only through a CDO. Unlike
    -- generic actor searches, we can use its reflected static Get().
    local ok,list=pcall(FindAllOf,"HeldenDataSingleton")
    if ok and type(list)=="table" then
        for _,entry in ipairs(list) do
            if valid(entry) then
                local good,instance=pcall(function() return entry:Get() end)
                if good and valid(instance) then return instance end
            end
        end
    end
end
local function treasureDataKey(actor,ds)
    if not ds then return nil end
    local container=get(ds,"PhysTreasureContainer")
    if not valid(container) then return nil end
    local root=get(actor,"RootMesh")
    local mesh=get(root,"StaticMesh")
    if not valid(mesh) and valid(root) then
        pcall(function() mesh=root:GetStaticMesh() end)
    end
    if not valid(mesh) then return nil end
    local match=path(mesh)
    local key
    each(get(container,"TreasureData"),function(row)
        local rowMesh=get(row,"StaticMesh")
        if not key and valid(rowMesh) and path(rowMesh)==match then
            key=get(row,"DataName")
        end
    end)
    return key
end
local function storyFallbackValue(actor,inspectedZero)
    -- Story furniture uses HeldenTrashConstruct.RandomMoneySpawn
    -- (HeldenMoneyResource {Type,Amount}) as its native money source.
    -- The dungeon-only inspect Value and scrap data rows can be zero even
    -- though this actor is configured to drop a currency on destruction.
    -- Respect its native chance; never invent Gold or Artifacts for items
    -- configured to drop only Scraps.
    if S.mode==0 then
        local native=get(actor,"RandomMoneySpawn")
        local kind=get(native,"Type")
        if type(kind)~="number" then
            local raw=tostring(kind or "")
            kind=tonumber(raw) or
                (raw:find("Artifacts",1,true) and 2) or
                (raw:find("Gold",1,true) and 1) or
                (raw:find("Scraps",1,true) and 0)
        end
        -- EHeldenResource: 0 Scraps, 1 Gold, 2 Artifacts
        local amount=number(get(native,"Amount"),0,CFG.MaxCoinsPerDrop)
        local chance=tonumber(get(actor,"MoneySpawnChance"))
        local canLoot=get(actor,"bCanSpawnLoot")
        if canLoot~=false and amount and amount>0 and
            (kind==1 or kind==2) and chance and chance>0 then
            local probability=chance>1 and chance/100 or chance
            probability=math.min(1,probability)
            if probability>=1 or math.random()<probability then
                return {gold=kind==1 and amount or 0,
                    artifacts=kind==2 and amount or 0,
                    source="story-trash-native-money-resource"}
            end
            -- Native random chance failed, but this does not imply that
            -- a VALUABLE Story item has zero scrap/sale value. Continue
            -- to inspect its economic value rather than suppress payout.
        end
        -- Native physical-actor resource rewards can also be specified
        -- directly as a HeldenMoney struct rather than through a row.
        local amountStruct=get(actor,"ResourceDropAmount")
        local gold=number(get(amountStruct,"Gold"),0,CFG.MaxCoinsPerDrop) or 0
        local artifacts=number(get(amountStruct,"Artifacts"),0,CFG.MaxCoinsPerDrop) or 0
        if gold>0 or artifacts>0 then
            return {gold=gold,artifacts=artifacts,
                source="story-physics-resource-drop-amount"}
        end

        -- In Story Mode smashing valuables normally grants scrap, while
        -- their Gold value comes from the Grinder. A destruction callback
        -- therefore often reports Gold=0,Artifacts=0 even for a valuable
        -- item. Derive an explicit MOD reward from *this actor's* nonzero
        -- scrap/sale value (or XP) rather than pretending native coins exist.
        local inspected
        pcall(function() inspected=actor:GetInspectData() end)
        local v=get(inspected,"Value")
        local scrap=number(get(v,"Scraps"),0,CFG.MaxCoinsPerDrop) or 0
        scrap=math.max(scrap,
            number(get(amountStruct,"Scraps"),0,CFG.MaxCoinsPerDrop) or 0)
        local asset
        pcall(function() asset=actor:GetConstructAssetData() end)
        local quality=enum(get(actor,"ConstructQuality"))
        if quality==nil then quality=enum(get(inspected,"Quality")) end
        local valueField=quality==2 and "Parsed_ScrapValue_Epic"
            or quality==1 and "Parsed_ScrapValue_Rare"
            or "Parsed_ScrapValue_Common"
        local assetValue=get(asset,valueField)
        scrap=math.max(scrap,
            number(get(assetValue,"Scraps"),0,CFG.MaxCoinsPerDrop) or 0)
        local xp=math.max(
            number(get(inspected,"XP"),0,CFG.MaxCoinsPerDrop) or 0,
            number(get(asset,"XP"),0,CFG.MaxCoinsPerDrop) or 0)
        if scrap>=CFG.StoryValuableMinScraps or
           xp>=CFG.StoryValuableMinXP then
            local derivedGold=scrap>=CFG.StoryValuableMinScraps
                and math.floor(scrap*CFG.StoryValueGoldFromScraps)
                or math.max(1,math.floor(xp/CFG.StoryValueGoldFromXPDivisor))
            local id=path(actor) or ""
            local valuableQuality=quality==1 or quality==2 or
                id:lower():find("treasure",1,true)~=nil
            local derivedArtifacts=valuableQuality and
                math.max(1,math.floor(scrap/CFG.StoryArtifactScrapsPerCoin)) or 0
            return {gold=derivedGold,artifacts=derivedArtifacts,
                source="story-valuables-scrap-xp-conversion"}
        end
    end
    return inspectedZero
end

local function lootValue(actor)
    if not valid(actor) then return nil end
    local id=path(actor) or ""
    local normalized=id:lower()
    -- Coin/pickup destruction must never recursively create currency.
    if normalized:find("coin",1,true) or normalized:find("pickup",1,true) then return nil end
    local ds=getDataSingleton()
    local inspected
    local inspectedZero
    pcall(function() inspected=actor:GetInspectData() end)
    if inspected and (get(inspected,"bIsInDungeon")==true or S.mode==0) then
        local value=get(inspected,"Value")
        if value then
            local gold=number(get(value,"Gold"),0,CFG.MaxCoinsPerDrop) or 0
            local artifacts=number(get(value,"Artifacts"),0,CFG.MaxCoinsPerDrop) or 0
            if gold>0 or artifacts>0 then
                return {gold=gold,artifacts=artifacts,source="inspect"}
            end
            -- Some native physical treasure objects expose an inspect value
            -- of zero while their DataTable extraction value is nonzero.
            -- Try the actual data row before declaring no payout.
            inspectedZero={gold=0,artifacts=0,source="inspect-zero"}
        end
    end
    if not ds then return storyFallbackValue(actor,inspectedZero) end
    -- Reflected actor DataName fields are used as keys; never infer rewards
    -- from an object's color or from an unrelated player's inventory.
    -- These are the actual reflected HeldenConstructActor methods.
    local struct
    pcall(function() struct=actor:GetConstructAssetData() end)
    local construct
    pcall(function() construct=actor:GetConstructAsset() end)
    if not struct and valid(construct) then
        struct=rowOf(get(ds,"ConstructAssetDataTable"),get(construct,"DataName"))
    end
    if struct then
        local quality=enum(get(actor,"ConstructQuality"))
        local key=quality==2 and "Parsed_ScrapValue_Epic"
            or quality==1 and "Parsed_ScrapValue_Rare"
            or "Parsed_ScrapValue_Common"
        local value=get(struct,key)
        if value then
            local gold=number(get(value,"Gold"),0,CFG.MaxCoinsPerDrop) or 0
            local artifacts=number(get(value,"Artifacts"),0,CFG.MaxCoinsPerDrop) or 0
            if gold>0 or artifacts>0 then
                return {gold=gold,artifacts=artifacts,
                    source="construct-asset-data",row=asName(get(struct,"DataName"))}
            end
            inspectedZero={gold=0,artifacts=0,source="construct-zero"}
        end
    end
    -- IMPORTANT: generic BP_DefaultPhysTreasure often has zero Construct
    -- scrap value. The actual reward lives in PhysActorData or in
    -- PhysTreasureContainer.TreasureData keyed by its current mesh.
    local candidates={}
    local seen={}
    local function candidate(value,source)
        local n=asName(value)
        if n and n~="None" and n~="" and not seen[n] then
            seen[n]=true
            candidates[#candidates+1]={key=value,name=n,source=source}
        end
    end
    candidate(get(actor,"StatsDataName"),"StatsDataName")
    candidate(get(actor,"ConstructDataName"),"ConstructDataName")
    candidate(get(get(actor,"InitConAsset"),"DataName"),"InitConAsset")
    candidate(get(get(actor,"SetupConstructAsset"),"DataName"),"SetupConstructAsset")
    candidate(get(construct,"DataName"),"GetConstructAsset")
    candidate(treasureDataKey(actor,ds),"TreasureData.StaticMesh")
    local tableObject=get(ds,"PhysActorDataTable")
    for _,entry in ipairs(candidates) do
        local row=rowOf(tableObject,entry.key)
        local value=row and get(row,"Parsed_ScrapReward")
        if value then
            local gold=number(get(value,"Gold"),0,CFG.MaxCoinsPerDrop) or 0
            local artifacts=number(get(value,"Artifacts"),0,CFG.MaxCoinsPerDrop) or 0
            if gold>0 or artifacts>0 then
                return {gold=gold,artifacts=artifacts,
                    source="physical-table:"..entry.source,row=entry.name}
            end
        end
    end
    if normalized:find("treasure",1,true) and
        S.unresolvedTreasureLogs<16 then
        S.unresolvedTreasureLogs=S.unresolvedTreasureLogs+1
        local names={}
        for _,entry in ipairs(candidates) do names[#names+1]=entry.name end
        log("TREASURE REWARD UNRESOLVED actor="..id..
            " quality="..tostring(enum(get(actor,"ConstructQuality")))..
            " candidates="..table.concat(names,",")..
            " inspect="..tostring(inspectedZero~=nil))
    end
    return storyFallbackValue(actor,inspectedZero)
end
-- The destroyed actor's GetInstigatorController() describes the actor's
-- OWN creation context, not necessarily the attacking player. Never credit
-- it as damage evidence. Track actual active damage overlaps and projectile
-- damage instead, matching player-controlled attack owners to the target.
local function ownerController(source)
    source=unwrap(source)
    if not valid(source) then return nil end
    local ids={}
    local obj=source
    for _=1,4 do
        if not valid(obj) then break end
        local id=path(obj)
        if not id or ids[id] then break end
        ids[id]=true
        local previous=get(obj,"PreviousOwner")
        local nextObj
        if valid(previous) then nextObj=previous
        else pcall(function() nextObj=obj:GetOwner() end) end
        obj=nextObj
    end
    local pcList=playerControllers()
    for _,pc in ipairs(pcList) do
        if valid(pc) then
            local pawn=rewardCharacter(pc)
            if valid(pawn) and ids[path(pawn)] then return pc end
        end
    end
    return nil
end

local function recordDamage(target,pc,kind)
    if not (S.mode==0 or S.phase==2) or
       not valid(target) or not valid(pc) or
       not valid(get(target,"StatsComponent")) then return end
    local key,player=path(target),path(pc)
    if not key or not player then return end
    local prev=S.damageHits[key]
    if prev and S.pollCycle-prev.tick<=2 and
       prev.player~=player then
        prev.ambiguous=true
        prev.tick=S.pollCycle
    else
        S.damageHits[key]={player=player,tick=S.pollCycle,kind=kind,
            ambiguous=(prev and S.pollCycle-prev.tick<=2 and
                prev.ambiguous) or false}
    end
end

local function recordAttackIntent(weapon)
    if not (S.mode==0 or S.phase==2) then return end
    local pc=ownerController(weapon)
    local id=valid(pc) and path(pc) or nil
    if id then
        S.attackIntents[id]={tick=S.pollCycle}
    end
end

-- Find the closest currently living player with a wallet. No maximum range:
-- even a 0.001 cm difference wins. Exact distance ties use the controller
-- full name to guarantee deterministic host-side attribution.
local function nearestPlayerAt(at)
    local best,bestDistance,bestId
    local sole,eligible,unknownPositions=nil,0,0
    for _,pc in ipairs(playerControllers()) do
        if valid(pc) then
            local pawn=rewardCharacter(pc)
            if valid(pawn) then
                eligible=eligible+1
                if eligible==1 then sole=pawn end
                local pos=location(pawn)
                if pos and at then
                    local dist=distance2(pos,at)
                    local id=path(pc) or ""
                    if not best or dist<bestDistance or
                       (dist==bestDistance and id<bestId) then
                        best,bestDistance,bestId=pawn,dist,id
                    end
                else
                    unknownPositions=unknownPositions+1
                end
            end
        end
    end
    if eligible==1 and valid(sole) then return sole,"sole-player" end
    if eligible==0 then
        -- The v0.7.3 log exposed this exact failure; retain a cheap,
        -- strictly capped trace on real destruction events so any future
        -- mismatch reveals the controller and LastPlayerChar at once.
        if S.rewardOwnerDiagnosticCount<4 then
            S.rewardOwnerDiagnosticCount=S.rewardOwnerDiagnosticCount+1
            for _,pc in ipairs(playerControllers()) do
                local current=currentPawn(pc)
                local last=resolveWeak(unwrap(get(pc,"LastPlayerChar")))
                local money=get(last,"Money")
                log("REWARD OWNER TRACE pc="..tostring(path(pc))..
                    " GetPawn="..tostring(path(current))..
                    " LastPlayerChar="..tostring(path(last))..
                    " LastHP="..tostring(get(get(last,"CharacterStats"),"CurrentHealth"))..
                    " LastGold="..tostring(get(money,"Gold"))..
                    " LastArtifacts="..tostring(get(money,"Artifacts")))
            end
        end
        return nil,"no-eligible-player"
    end
    if valid(best) then return best,"nearest-player" end
    if not at then return sole,"no-destroy-position-first-live-player" end
    if unknownPositions>0 then
        return sole,"player-position-unavailable-first-live-player"
    end
    return nil,"no-valid-position"
end

local function selectDestroyer(actor,origin)
    if not CFG.DirectFurnitureRewards then return nil,"disabled" end
    local key=path(actor)
    local hit=key and S.damageHits[key] or nil
    local recent=hit and S.pollCycle-hit.tick<=2
    if recent and not hit.ambiguous then
        for _,pc in ipairs(playerControllers()) do
            if valid(pc) and path(pc)==hit.player then
                local pawn=rewardCharacter(pc)
                if valid(pawn) then
                    return pawn,"verified-"..hit.kind
                end
            end
        end
    end
    -- A unique recent active weapon attack is useful evidence, even if
    -- another player is a millimetre closer. Multiple attackers are not.
    local at=location(actor)
    local attacker,count=nil,0
    if at then
        for _,pc in ipairs(playerControllers()) do
            if valid(pc) then
                local pawn=rewardCharacter(pc)
                local attack=S.attackIntents[path(pc)]
                local pos=location(pawn)
                if valid(pawn) and pos and
                   distance2(pos,at)<=CFG.RewardNearbyPlayerRadius^2 and
                   attack and S.pollCycle-attack.tick<=2 then
                    attacker,count=pawn,count+1
                end
            end
        end
    end
    if count==1 and valid(attacker) then
        return attacker,"recent-weapon-attack"
    end
    -- Explicit user preference: nearest payer ALWAYS wins when no uniquely
    -- confirmed attacker exists, no matter how small the distance margin.
    local nearest,reason=nearestPlayerAt(at)
    return nearest,reason
end

local function creditReward(pawn,currency,amount)
    if not valid(pawn) or amount<=0 then return false end
    local money=get(pawn,"Money")
    local old=number(get(money,currency),0,100000000)
    if old==nil or old+amount>100000000 then return false end
    local goal=old+amount
    -- UE4SS can return an attached proxy or a copied UScriptStruct.
    put(money,currency,goal)
    local after=number(get(get(pawn,"Money"),currency),0,100000000)
    if after~=goal then
        -- UE4SS can expose a detached UScriptStruct. Reassigning its
        -- original UObject-backed struct is more reliable than a Lua
        -- table on older UE4SS builds.
        put(pawn,"Money",money)
        after=number(get(get(pawn,"Money"),currency),0,100000000)
    end
    if after~=goal and after==old then
        local fresh=get(pawn,"Money")
        local newMoney={}
        for _,key in ipairs({"Gold","Artifacts","Scraps"}) do
            newMoney[key]=number(get(fresh,key),0,100000000)
            if newMoney[key]==nil then return false end
        end
        newMoney[currency]=goal
        put(pawn,"Money",newMoney)
        after=number(get(get(pawn,"Money"),currency),0,100000000)
    end
    if after==goal then
        pcall(function() pawn:ForceNetUpdate() end)
        return true
    end
    -- The queue logs failures with exponential backoff, not per frame.
    return false
end

local function destructionEvent(ctx,origin)
    S.rawDestroyEvents=S.rawDestroyEvents+1
    local a=unwrap(ctx)
    -- Do not call GetFullName()/onHost() or print from the frequently hit
    -- health hook; the live log recorded 5,649 raw callbacks for 3 kills.
    if CFG.Verbose and S.rawDestroyEvents<=10 then
        log("RAW DESTRUCTION "..origin.." actor="..tostring(path(a)))
    end
    -- Reject the common nonlethal hits before expensive reflected context.
    if not (S.mode==0 or S.phase==2) or not valid(a) then return end
    local stats=get(a,"StatsComponent")
    if not valid(stats) then return end
    if origin=="health" then
        local hp=tonumber(get(stats,"CurrentHealth"))
        if not hp or hp>0 then return end
    end
    if not onHost() then return end
    local gameCtx=game()
    if not gameCtx or not
       (gameCtx.isStory or (gameCtx.isExpedition and gameCtx.phase==2)) then
        return
    end
    if get(a,"bIsQuestObjective")==true or
       get(a,"bRequireQuestObjectiveToKill")==true then return end
    -- Require an actual in-dungeon loot actor; never pay for built furniture.
    local owning=resolveWeak(get(a,"OwningDungeon"))
    local inspecting
    pcall(function() inspecting=a:GetInspectData() end)
    local inDungeon=inspecting and get(inspecting,"bIsInDungeon")==true
    if not gameCtx.isStory and not inDungeon and not valid(owning) then
        if S.rawDestroyEvents<=10 then
            log("DROP SKIP: no valid dungeon origin for "..tostring(path(a)))
        end
        return
    end
    local key=path(a)
    if not key or S.destructionSeen[key] then return end
    S.rewardEvents=S.rewardEvents+1
    local value=lootValue(a)
    if gameCtx.isStory and S.storyLootDiagnosticCount<12 then
        S.storyLootDiagnosticCount=S.storyLootDiagnosticCount+1
        local cls
        pcall(function() cls=a:GetClass() end)
        local nat=get(a,"RandomMoneySpawn")
        log("STORY LOOT DIAG actor="..key..
            " class="..tostring(path(cls))..
            " hp="..tostring(get(stats,"CurrentHealth"))..
            " inspect="..tostring(inDungeon)..
            " source="..tostring(value and value.source)..
            " gold="..tostring(value and value.gold)..
            " artifacts="..tostring(value and value.artifacts)..
            " nativeType="..tostring(get(nat,"Type"))..
            " nativeAmount="..tostring(get(nat,"Amount"))..
            " chance="..tostring(get(a,"MoneySpawnChance")))
    end
    if not value then
        if S.rewardEvents<=15 then log("DESTRUCTION "..origin.." "..key.." (no reward data)") end
        return
    end
    if value.gold<=0 and value.artifacts<=0 then
        if S.rewardEvents<=15 then log("DESTRUCTION "..origin.." "..key.." (no coin payout)") end
        return
    end
    local at=location(a)
    local world
    pcall(function() world=a:GetWorld() end)
    -- Direct wallet credits do not need a World or a currency SpawnActor.
    -- Story construction actors can lose their World during destruction.
    -- Keep the event if their position is known; a single valid player can
    -- also be paid without a position.
    if not at and S.rewardEvents<=12 then
        log("DESTRUCTION POSITION UNKNOWN "..tostring(key)..
            " (wallet-only payout will retry owner selection)")
    end
    S.destructionSeen[key]=true
    local recipient,ownership=selectDestroyer(a,origin)
    S.dropQueue[#S.dropQueue+1]={at=at,key=key,
        gold=value.gold,artifacts=value.artifacts,source=value.source,
        recipient=recipient,recipientSource=ownership,
        queued=os.clock(),goldDone=false,artifactDone=false}
    log("DESTRUCTION queued "..key.." gold="..value.gold.." artifacts="..
        value.artifacts.." source="..value.source.." from="..origin)
end
-- Furniture / extraction currency is wallet-only. No actor spawning,
-- mesh physics, collision, or physical Gold/Artifacts fallback.
local function processDropQueue()
    if #S.dropQueue==0 or not onHost() then return end
    for i=#S.dropQueue,1,-1 do
        local job=S.dropQueue[i]
        -- A detached Money struct can fail writes on some UE4SS versions.
        -- Never retry every 300ms for every smashed chair: that produced
        -- an ever-growing queue of costly UObject writes and stutters.
        if S.pollCycle>=(job.nextRewardCycle or 0) then
            job.attempts=(job.attempts or 0)+1
            if not valid(job.recipient) or
               get(job.recipient,"Money")==nil then
                job.recipient,job.recipientSource=nearestPlayerAt(job.at)
            end
            local receiver=job.recipient
            if valid(receiver) then
                if job.gold>0 and not job.goldDone then
                    job.goldDone=creditReward(receiver,"Gold",job.gold)
                    if job.goldDone then
                        log("DIRECT REWARD Gold="..job.gold..
                            " to="..tostring(path(receiver))..
                            " via="..tostring(job.recipientSource))
                    end
                end
                if job.artifacts>0 and not job.artifactDone then
                    job.artifactDone=creditReward(receiver,"Artifacts",job.artifacts)
                    if job.artifactDone then
                        log("DIRECT REWARD Artifacts="..job.artifacts..
                            " to="..tostring(path(receiver))..
                            " via="..tostring(job.recipientSource))
                    end
                end
            end
            if (job.gold<=0 or job.goldDone) and
               (job.artifacts<=0 or job.artifactDone) then
                table.remove(S.dropQueue,i)
            else
                -- 0.6s, 1.2s, 2.4s, 4.8s, 9.6s, ... capped at 36s.
                local step=math.min(CFG.RewardRetryMaxTicks,
                    2^math.min(job.attempts,7))
                job.nextRewardCycle=S.pollCycle+step
                -- Diagnostic on first attempt and at powers of two only,
                -- not once per currency and not every engine poll.
                local n=job.attempts
                if n==1 or n==2 or n==4 or n==8 or n==16 then
                    log("DIRECT REWARD PENDING actor="..tostring(job.key)..
                        " GoldPending="..tostring(not job.goldDone)..
                        " ArtifactsPending="..tostring(not job.artifactDone)..
                        " recipient="..tostring(path(receiver))..
                        " reason="..tostring(job.recipientSource)..
                        " attempt="..n.." nextPolls="..step..
                        " (NO PHYSICAL DROP)")
                end
            end
        end
    end
end

-- Game preserves an EndScreen/Failed state after the final death. Updating
-- DungeonLevel alone does NOT unlock the machine; repair the run AND its
-- interaction gate only after the elevator is back at the home station.
-- Expedition's door is a separate Blueprint actor, not the elevator
-- machine. v0.3 never touched BP_ExpeditionFailed_Actor_C; it remained solid
-- even after GameState flags were cleared (confirmed by live object dump).
local function repairFailedDoor(ctx)
    if not ctx.isExpedition or not CFG.EnableNoPermadeath or
       not S.recoveryRequired then return end
    if ctx.phase==1 or ctx.phase==2 then return end
    local observed=0
    for _,barrier in ipairs(all("BP_ExpeditionFailed_Actor_C")) do
        local key=path(barrier)
        if valid(barrier) and key and
            key:find("PersistentLevel",1,true) and
            not key:find("Default__",1,true) then
            observed=observed+1
            local failed=get(barrier,"bFailedExpedition")
            if failed~=false then
                put(barrier,"bFailedExpedition",false)
                pcall(function() barrier:OnRep_bFailedExpedition() end)
                pcall(function() barrier:UpdateCollisionSate() end)
            end
            -- Regardless of BP flag, remove the physical door collision
            -- on the authoritative host. Never destroy the actor, which may
            -- have other OnObjetEvent handlers needed for the next run.
            pcall(function() barrier:SetActorEnableCollision(false) end)
            for _,component in ipairs({
                    get(barrier,"Box"),
                    get(barrier,"SM_SM_Door_Lock"),
                    get(barrier,"Cube")}) do
                if valid(component) then
                    pcall(function() component:SetCollisionEnabled(0) end)
                    pcall(function() component:SetVisibility(false,true) end)
                end
            end
            if S.failedBarriers<5 then
                local boxCollision
                local lockVisibility
                local c=get(barrier,"Box")
                local lock=get(barrier,"SM_SM_Door_Lock")
                if valid(c) then pcall(function() boxCollision=c:GetCollisionEnabled() end) end
                if valid(lock) then pcall(function() lockVisibility=lock:IsVisible() end) end
                log("FAILURE DOOR disabled actor="..key..
                    " wasFailed="..tostring(failed)..
                    " nowFailed="..tostring(get(barrier,"bFailedExpedition"))..
                    " boxCollision="..tostring(boxCollision)..
                    " lockVisible="..tostring(lockVisibility))
                S.failedBarriers=S.failedBarriers+1
            end
        end
    end
    if observed==0 and S.failedBarriers==0 then
        S.failedBarriers=-1
        log("FAILURE DOOR: no live BP_ExpeditionFailed_Actor_C found")
    end
end

local function repairElevator(ctx)
    if not ctx.isExpedition or not CFG.EnableNoPermadeath or
       not S.recoveryRequired then return end
    if ctx.phase==1 or ctx.phase==2 then return end
    local now=os.clock()
    S.machineRepairCycle=S.machineRepairCycle+1
    if S.machineRepairCycle<5 or S.machineRepairAttempts>=10 then return end
    S.machineRepairCycle=0
    S.machineRepairAttempts=S.machineRepairAttempts+1
    local lift=first("HeldenDungeonElevator")
    local machine=valid(lift) and get(lift,"ElevatorMachine") or nil
    if not valid(machine) then machine=first("HeldenElevatorMachine") end
    if valid(lift) then
        local home=number(get(lift,"HomeStationIdx"),0,256)
        local station=number(get(lift,"CurrentStationIdx"),0,256)
        if home~=nil and station~=nil and home~=station then
            log("RECOVERY waiting for elevator at home; station="..station.." home="..home)
            return
        end
    elseif ctx.phase~=0 then
        log("RECOVERY waiting for home elevator (run="..ctx.phase..")")
        return
    end
    local run=get(ctx.gs,"CurrentDungeonRun")
    local before=enum(get(run,"State"))
    local flagsBefore=enum(get(run,"Flags"))
    local changed=true
    if before==3 then changed=put(run,"State",0) end
    if get(run,"Flags")~=nil then put(run,"Flags",0) end
    -- A reflected UStruct might be copy-on-read. Write it back to its
    -- GameState owner and verify that the actual source changed.
    if before==3 and enum(get(get(ctx.gs,"CurrentDungeonRun"),"State"))~=0 then
        put(ctx.gs,"CurrentDungeonRun",run)
    end
    local after=enum(get(get(ctx.gs,"CurrentDungeonRun"),"State"))
    local clear=after==0
    local interaction="not found"
    if valid(machine) then
        if get(machine,"bInteractionLocked")==true then
            put(machine,"bInteractionLocked",false)
        end
        -- The machine has a second, independent requirement gate.
        if get(machine,"bUseInteractRequirement")==true then
            put(machine,"bUseInteractRequirement",false)
        end
        local ok,why=pcall(function() machine:SetCanBeInteracted_Auth(true) end)
        if ok then interaction="unlocked" else interaction="error:"..tostring(why) end
        pcall(function() machine:OnRequirementSysUpdate_Auth() end)
        -- Recompute native elevator-button state using the restored run.
        if clear then
            pcall(function() machine:OnDungeonRunStateChanged(get(ctx.gs,"CurrentDungeonRun")) end)
        end
        -- Blueprint recomputation can reinstate these gate fields.
        put(machine,"bInteractionLocked",false)
        put(machine,"bUseInteractRequirement",false)
    end
    if valid(lift) and get(lift,"bInteractionLocked")==true then
        put(lift,"bInteractionLocked",false)
    end
    if clear then
        pcall(function() ctx.gs:OnRep_DungeonRunState() end)
    end
    log("RECOVERY run="..tostring(before).." -> "..tostring(after)..
        " flags="..tostring(flagsBefore).." -> "..
        tostring(enum(get(get(ctx.gs,"CurrentDungeonRun"),"Flags")))..
        " machine="..interaction.." attempt="..S.machineRepairAttempts)
    if after~=0 and S.machineRepairAttempts==10 then
        log("WARNING: cannot reset ended run; elevator may stay locked")
    end
end

local function poll()
    S.pollCycle=S.pollCycle+1
    if S.pollCycle%20==0 then
        for key,hit in pairs(S.damageHits) do
            if S.pollCycle-hit.tick>3 then S.damageHits[key]=nil end
        end
        for key,attack in pairs(S.attackIntents) do
            if S.pollCycle-attack.tick>3 then S.attackIntents[key]=nil end
        end
    end
    local now=os.clock()
    local host=onHost()
    -- Client scripts must observe their own respawns even though they do not
    -- have the authoritative GameMode required by the gameplay features.
    if not host then observeClientRespawnAudio() end
    local ctx=host and game()
    S.heartbeatTicks=S.heartbeatTicks+1
    if S.heartbeatTicks>=120 then
        S.heartbeatTicks=0
        local gs=first("HeldenGameState")
        local gi=first("HeldenGameInstance")
        local save=gi and get(gi,"CurrentSaveGame")
        log("HEARTBEAT host="..tostring(host)..
            " GS="..tostring(path(gs))..
            " mode="..tostring(enum(get(gs,"GameModeType")))..
            " save="..tostring(valid(save))..
            " saveMode="..tostring(enum(get(save,"GameMode")))..
            " phase="..tostring(ctx and ctx.phase)..
            " rawPhase="..tostring(enum(get(get(gs,"CurrentDungeonRun"),"State")))..
            " flags="..tostring(enum(get(get(gs,"CurrentDungeonRun"),"Flags")))..
            " expeditionFailed="..tostring(get(gs,"bExpeditionFailed"))..
            " savedFailed="..tostring(get(get(save,"MetaData"),"bHasFailed"))..
            " recovery="..tostring(S.recoveryRequired)..
            " deaths="..S.deathEvents.." rawDeaths="..S.rawDeathEvents..
            " destructionEvents="..S.rewardEvents..
            " rawDestructions="..S.rawDestroyEvents..
            " playerControllers="..#playerControllers()..
            " failureDoors="..(ctx and ctx.isExpedition and
                #all("BP_ExpeditionFailed_Actor_C") or 0)..
            " failureChecks="..S.failureChecks)
    end
    if not ctx then
        if S.lastMode~="no-context" then
            S.lastMode="no-context"
            log("inactive: missing authoritative Story/Expedition context")
        end
        return
    end
    S.lastMode=ctx.isStory and "story" or "expedition"
    local md=get(ctx.save,"MetaData")
    local slot=number(get(md,"GameSlot"),0,100)
    if not slot then return end
    local key=path(ctx.save)
    if S.slot~=slot or S.saveKey~=key or S.mode~=ctx.mode then
        resetForSave(ctx,key,slot)
    end
    S.mode=ctx.mode
    if ctx.isExpedition then keepExpedition(ctx) end
    monitorPlayers(ctx)
    processDeaths(ctx)
    processInventoryRecoveries()
    processCurrencyCleanup()
    if ctx.isExpedition then
        repairElevator(ctx)
        repairFailedDoor(ctx)
    end
    processDropQueue()
    if ctx.isExpedition and (ctx.phase==1 or ctx.phase==2) then
        if S.phase==0 or S.phase==3 then
            cache["HeldenDungeonElevator"]=nil
        end
    end
    if S.phase~=ctx.phase then
        log((ctx.isStory and "Story" or "Expedition")..
            " run state "..tostring(S.phase).." -> "..ctx.phase..
            "; depth="..S.depth)
    end
    S.phase=ctx.phase
end

local function isPlayableDeath()
    if not onHost() then return false end
    return deathAllowed(game())
end
local function watchDeath(context)
    S.rawDeathEvents=S.rawDeathEvents+1
    local character=unwrap(context)
    if S.rawDeathEvents<=12 then
        local ctx=game()
        log("RAW DIE_Auth actor="..tostring(path(character))..
            " host="..tostring(onHost())..
            " phase="..tostring(ctx and ctx.phase)..
            " accepted="..tostring(isPlayableDeath()))
    end
    if not valid(character) or not isPlayableDeath() then return end
    captureDeath(character)
end
local function watchControllerKilled(context)
    local pc=unwrap(context)
    if not onHost() then markClientAudioDeath(pc) end
    if valid(pc) then
        log("RAW OnPlayerKilled controller="..tostring(path(pc))..
            " accepted="..tostring(isPlayableDeath()))
    end
    if not valid(pc) or not isPlayableDeath() then return end
    local old=get(pc,"LastPlayerChar")
    if valid(old) then captureDeath(old) end
end
local function immediatelyRequestRespawn(context)
    local pc=unwrap(context)
    if not valid(pc) or not onHost() then return end
    local entry=S.pending[path(pc)]
    if not entry or entry.attempts>0 then return end
    entry.attempts=1
    entry.nextRequestTick=(entry.ageTicks or 0)+5
    local ok,err=pcall(function() pc:RespawnCharacter_Server() end)
    log("IMMEDIATE RESPAWN on OnPlayerKilled post -> "..tostring(ok)..
        (ok and "" or ": "..tostring(err)))
end
local function watchReplicatedDeadState(context)
    local character=unwrap(context)
    if not valid(character) or enum(get(character,"CharacterState"))~=1 then return end
    for _,pc in ipairs(playerControllers()) do
        if valid(pc) then
            local key=path(pc)
            local record=S.players[key]
            local old=record and record.lastPawn
            if record and record.alive and valid(old) and
               path(old)==path(character) then
                queuePlayerDeath(pc,character,record.gear,
                    "OnRep_CharacterState Dead")
                return
            end
        end
    end
end
local function watchNewPawn(context,oldPawn,newPawn)
    S.cachedControllers=nil
    S.controllerScanTick=-1
    local pc=unwrap(context)
    local pawn=unwrap(newPawn)
    if not valid(pc) or not valid(pawn) then return end
    if not onHost() and clientAudio.armed and
       clientAudio.controllerId==path(pc) then
        local ok,isLocal=pcall(function() return pc:IsLocalController() end)
        if ok and isLocal==true then
            clientAudio.pendingPawn=pawn
        end
    end
    S.newPawnEvents=S.newPawnEvents+1
    local entry=S.pending[path(pc)]
    if entry then entry.spawned=pawn;log("NEWPAWN event for pending death") end
end
local registered={}
local retries={}
local knownHooks={}
local function hook(f,pre,post)
    if not knownHooks[f] then knownHooks[f]={pre=pre,post=post} end
    if registered[f] then return end
    local now=os.clock()
    if retries[f] and now<retries[f] then return end
    retries[f]=now+CFG.RetryHookSeconds
    local ok,a,b=pcall(function() return RegisterHook(f,pre,post) end)
    if ok and a~=nil then
        registered[f]=true
        log("HOOK ACTIVE "..f)
    else
        log("HOOK NOT READY "..f.." (will retry): "..tostring(a))
    end
end
local function safePre(label,cb)
    return function(...)
        local ok,err=pcall(cb,...)
        if not ok then log("HOOK "..label.." callback failed: "..tostring(err)) end
    end
end
local function safePostBool(cb)
    return function(...)
        local ok,result=pcall(cb,...)
        if ok then return result end
        log("HOOK return override failed: "..tostring(result))
    end
end
local function retryHooks()
    for f,spec in pairs(knownHooks) do
        if not registered[f] then hook(f,spec.pre,spec.post) end
    end
end
-- Native hooks run on the engine thread; no worker threads modify UObjects.
hook("/Script/Helden.HeldenCharacter:Die_Auth",
     safePre("Die_Auth",watchDeath))
hook("/Script/Helden.HeldenCharacter:OnRep_CharacterState",
     safePre("OnRep_CharacterState",watchReplicatedDeadState))
hook("/Script/Helden.HeldenPlayerController:OnPlayerKilled",
     safePre("OnPlayerKilled",watchControllerKilled),
     safePre("OnPlayerKilledPost",function(context,...)
         watchControllerKilled(context,...)
         immediatelyRequestRespawn(context)
     end))
hook("/Script/Helden.HeldenPlayerController:OnNewPawn",
     function() end,safePre("OnNewPawn",watchNewPawn))
if CFG.EnableNoPermadeath then
    -- Native post-hook return override, documented in UE4SS RegisterHook.
    -- A false result is intentionally restricted to the Expedition game
    -- mode and authoritative host; it does not touch normal saves.
    hook("/Script/Helden.HeldenGameState:HasFailedExpedition",
        function() end,
        safePostBool(function(context)
            S.failureChecks=S.failureChecks+1
            local gs=unwrap(context)
            local ctx=onHost() and game()
            if S.failureChecks<=5 then
                log("HAS FAILED check event host="..tostring(onHost())..
                    " ctx="..tostring(ctx and ctx.phase))
            end
            if valid(gs) and ctx and ctx.isExpedition and
               path(ctx.gs)==path(gs) then
                return false
            end
        end))
    hook("/Script/Helden.HeldenGameState:EndDungeonRunSequence_Multicast",
        safePre("EndDungeonRunSequence",function(context,statsArg)
            local gs=unwrap(context)
            local ctx=onHost() and game()
            if not ctx or not ctx.isExpedition or
               path(ctx.gs)~=path(gs) then return end
            local stats=unwrap(statsArg)
            if get(stats,"bHaveFailed")==true then
                S.failed=true;S.recoveryRequired=true
                local depth=number(get(stats,"DungeonLevel"),0,CFG.MaxDepth)
                if depth and depth>S.depth then S.depth=depth end
                log("END RUN failure event; protected depth="..S.depth)
            end
        end))
    hook("/Script/Helden.HeldenInteractableObject:CanBeInteracted",
        function() end,
        safePostBool(function(context)
            if not S.recoveryRequired or not onHost() then return end
            local ctx=game()
            if not ctx or not ctx.isExpedition or
               (ctx.phase~=0 and ctx.phase~=3) then return end
            local machine=first("HeldenElevatorMachine")
            if valid(machine) and path(machine)==path(unwrap(context)) then return true end
        end))
end
-- Damage ownership hooks are event-driven, not per animation frame.
-- These reflected callbacks carry the actual target actor.
if CFG.DirectFurnitureRewards then
    hook("/Script/Helden.HeldenWeapon:Attack_Server",
        safePre("weapon attack",function(weapon)
            recordAttackIntent(unwrap(weapon))
        end))
    -- OnTriggerOverlapBegin is NOT an exposed HeldenDamageBoxComponent
    -- UFunction in the current live reflection dump. RegisterHook retries
    -- for it produced repeated expensive failures. We rely on real
    -- projectile callbacks, weapon attack events and nearest-player fallback.
    hook("/Script/Helden.HeldenProjectile:OnDamagedActor",
        safePre("projectile hit",function(projectile,overlap,otherActor)
            if not (S.mode==0 or S.phase==2) then return end
            local source=unwrap(projectile)
            local pc
            if valid(source) then
                pcall(function() pc=source:GetInstigatorController() end)
            end
            if not valid(pc) then pc=ownerController(source) end
            recordDamage(unwrap(otherActor),pc,"projectile-hit")
        end))
end
-- Capture the destruction signal from the engine, not keyboard actions.
-- Health==0 handles direct damage. Multicast catches non-health-based breakage.
hook("/Script/Helden.HeldenPhysicsActor:OnHealthModifed",
     function() end, -- no expensive duplicate prehook
     safePre("health post",function(context)
         -- Thousands of harmless health notifications occur during level
         -- loading and incidental damage. Only process confirmed zero HP.
         if S.mode~=0 and S.phase~=2 then return end
         local actor=unwrap(context)
         if not valid(actor) then return end
         local stats=get(actor,"StatsComponent")
         local hp=tonumber(get(stats,"CurrentHealth"))
         if hp and hp<=0 then
             destructionEvent(context,"health")
         end
     end))
hook("/Script/Helden.HeldenPhysicsActor:PlayDestructionEffect_Mulitcast",
     safePre("destruction",function(context) destructionEvent(context,"effect") end))
-- Story TrashConstruct is a child of HeldenConstructActor. Native collision
-- disabling is a separate reflected event used by destructible furniture.
-- Only treat it as a kill when the real StatsComponent health is <= 0,
-- otherwise ordinary placement/interaction would generate fake rewards.
hook("/Script/Helden.HeldenConstructActor:DisableCollision_Multicast",
     safePre("story-destruction-collision",function(context)
         if S.mode~=0 then return end
         local actor=unwrap(context)
         local stats=valid(actor) and get(actor,"StatsComponent")
         local hp=tonumber(get(stats,"CurrentHealth"))
         if valid(stats) and hp and hp<=0 then
             destructionEvent(context,"story-collision")
         end
     end))
local lastSlowPoll=-1000
local function safePoll(onTimer)
    local started=os.clock()
    local now=started
    -- The engine-thread delayed loop already throttles callbacks. os.clock
    -- measures CPU time on Windows and must NOT gate that loop; otherwise
    -- pauses/slow frames can postpone a respawn until after party wipe.
    if not onTimer then
        if S.lastPoll>=0 and now>=S.lastPoll and
            now-S.lastPoll<CFG.PollSeconds then return end
    end
    S.lastPoll=now
    retryHooks()
    local ok,err=pcall(poll)
    local finished=os.clock()
    if finished-started>=CFG.SlowPollWarnSeconds and
       finished-lastSlowPoll>=5 then
        lastSlowPoll=finished
        log(string.format("PERF slow Expedition poll CPU=%.1fms",
            (finished-started)*1000))
    end
    if not ok and not S.warned then
        S.warned=true;log("poll error: "..tostring(err))
    end
end
local function heartbeat()
    S.sample=S.sample+1
    if S.sample<CFG.AnimationSample then return end
    S.sample=0
    safePoll()
end
-- Persistent game-thread polling is crucial: when the final player dies,
-- BlueprintUpdateAnimation may stop entirely. UE4SS v3 has LoopAsync and
-- ExecuteInGameThread; v4 also has a direct game-thread timer.
-- NotifyOnNewObject is a genuine UE4SS API. It is registered once,
-- does not poll the UObject array, and fires only for newly constructed
-- HeldenPhysicsCoin (including blueprint-derived coin classes).
if CFG.UseCoinObjectTracking and type(NotifyOnNewObject)=="function" then
    local ok,err=pcall(function()
        NotifyOnNewObject("/Script/Helden.HeldenPhysicsCoin",
            function(coin) pcall(watchNewCoin,coin) end)
    end)
    S.coinEventsActive=ok
    log(ok and "coin creation tracking active; periodic baseline scans disabled"
        or ("coin notification unavailable: "..tostring(err)))
end

local scheduled=false
if type(LoopInGameThreadWithDelay)=="function" then
    local ok=pcall(function()
        LoopInGameThreadWithDelay(300,function() safePoll(true) end)
    end)
    if ok then scheduled=true;log("game-thread timer active (300 ms)") end
elseif type(LoopAsync)=="function" and type(ExecuteInGameThread)=="function" then
    local ok=pcall(function()
        LoopAsync(300,function()
            pcall(function() ExecuteInGameThread(function() safePoll(true) end) end)
            return false
        end)
    end)
    if ok then scheduled=true;log("UE4SS v3 async timer -> game-thread queue active") end
end
if not scheduled then
    log("WARNING: no independent timer; animation-hook fallback may stop during party wipe")
    hook("/Game/Animation/ABP_HeldenPlayer.ABP_HeldenPlayer_C:BlueprintUpdateAnimation",
         function() heartbeat() end)
end
hook("/Script/Engine.PlayerController:ClientRestart",
     function()
         cache={};S.lastPoll=-1;S.sample=CFG.AnimationSample-1
         S.coinLedger={}
         S.dropQueue={};S.destructionSeen={}
     end)
log("v0.7.6 LIVE-LOG FIX + host and client self-respawn WAV (async WinMM)")
