-- Expedition Saver v0.2.0-alpha | Grain Rot (Helden / UE4SS 3.x)
-- Host-authoritative only. This mod is EXPERIMENTAL; back up the save.
-- The latest 2026-11-20 USMAP confirms fields and reflected signatures,
-- not the exact native save/death sequence. Every mutation is checked.
local CFG = {
    PollSeconds = 0.30,
    AnimationSample = 8,
    MaxDepth = 10000,
    EnableRespawn = true,
    EnableItemRecovery = true,
    EnableNoPermadeath = true,
    EnablePhysicalCoins = true,
    RespawnDelaySeconds = 1.25,
    RespawnRetrySeconds = 2.5,
    MaxRespawnRequests = 3,
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
    if s:find("Exploring",1,true) then return 2 end
    if s:find("EndScreen",1,true) then return 3 end
    if s:find("ElevatorRideDown",1,true) then return 1 end
    if s:find("Epic",1,true) then return 2 end
    if s:find("Failed",1,true) then return 1 end
    if s:find("None",1,true) or s:find("Default",1,true) then return 0 end
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
local function game()
    local gi=first("HeldenGameInstance")
    local gs=first("HeldenGameState")
    local save=gi and get(gi,"CurrentSaveGame")
    if not valid(gs) or not valid(save) then return nil end
    -- Do not touch the normal game. GameModeType is the authoritative check.
    local gm=enum(get(gs,"GameModeType"))
    local sg=enum(get(save,"GameMode"))
    if gm~=1 then return nil end -- GameState is authoritative; save may lag
    local run=get(gs,"CurrentDungeonRun")
    if not run then return nil end
    return {gi=gi,gs=gs,save=save,run=run,
        phase=enum(get(run,"State")) or 0,
        failed=failure(get(run,"Flags"))}
end
local S={
    slot=nil,saveKey=nil,depth=0,highestSeed=0,offset=nil,
    active=false,failed=false,phase=nil,pending={},
    sample=0,lastPoll=-1,nextBackupDepth=-1,
    nextBackupTime=-1,coinLedger={},respawned=0,
    lastMode="unknown",lastDisplay=nil,warned=false,
    lastHeartbeat=0,lastGuard=nil,recoveryRequired=false,
    nextMachineRepair=0,machineRepairAttempts=0,
    dropQueue={},destructionSeen={},dropAttempt=0,
    deathEvents=0,newPawnEvents=0,rewardEvents=0
}
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
    S.slot=slot;S.saveKey=key
    S.depth=number(get(ctx.save,"DungeonLevel"),0,CFG.MaxDepth) or 0
    S.highestSeed=0;S.offset=nil;S.active=false;S.failed=false
    S.phase=nil;S.pending={};S.coinLedger={}
    S.nextBackupDepth=-1
    local time=number(get(ctx.save,"TimePlayed"),0,1000000000)
    local fails=number(get(ctx.save,"DungeonFails"),0,1000000000)
    local recovered=readBackup(slot,time,fails)
    if recovered and recovered>S.depth then S.depth=recovered end
    log("Expedition slot "..slot.." loaded; protected depth "..S.depth)
end
local function keepExpedition(ctx)
    if not CFG.EnableNoPermadeath then return end
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
local function gearOf(char)
    local result,seen={},{}
    local function add(item)
        if not valid(item) then return end
        local id=path(item)
        if not id or seen[id] then return end
        seen[id]=true
        result[#result+1]={ref=item,key=id,slotIdx=number(get(item,"CurrentInventorySlot"),0,128)}
    end
    each(get(char,"EquipedItems"),add)
    for _,item in ipairs(all("HeldenEquipableItem")) do
        if valid(item) and get(item,"PreviousOwner")==char and valid(get(item,"CurrentSlot")) then
            add(item)
        end
    end
    return result
end
local function currentPawn(pc)
    if not valid(pc) then return nil end
    local ok,pawn=pcall(function() return pc:GetPawn() end)
    if ok and valid(pawn) then return pawn end
end
local function captureDeath(char)
    if not CFG.EnableRespawn or not onHost() then return end
    local ctx=game()
    if not ctx or ctx.phase~=2 then return end
    local pc
    pcall(function() pc=char:GetController() end)
    if not valid(pc) then return end
    local key=path(pc)
    if not key or S.pending[key] then return end
    -- Ignore NPC/AI deaths even if they expose a Controller method.
    local isPlayer=false
    for _,playerController in ipairs(all("HeldenPlayerController")) do
        if path(playerController)==key then isPlayer=true;break end
    end
    if not isPlayer then return end
    local inv=gearOf(char)
    local entry={controller=pc,oldChar=char,gear=inv,
        started=os.clock(),attempts=0,nextRequest=0,
        spawned=nil,delivered=false}
    S.pending[key]=entry
    S.deathEvents=S.deathEvents+1
    log("DEATH HOOK player="..key.." phase="..ctx.phase..
        " retained="..#inv.." awaiting server respawn")
end
local function respawnLocation()
    local lift=first("HeldenDungeonElevator")
    if not valid(lift) then return nil end
    local comp=get(lift,"InteriorCollisionBox")
    local loc=location(comp) or location(lift)
    if not loc then return nil end
    return {X=loc.X,Y=loc.Y,Z=loc.Z+80}
end
local function heal(pawn)
    local stats=get(pawn,"CharacterStats")
    if not valid(stats) then return false end
    local max=tonumber(get(get(stats,"TotalStats"),"MaxHealth"))
    if not max or max<=0 or max>1000000 then return false end
    return put(stats,"CurrentHealth",max)
end
local function collectAtElevator(entry,dest,pawn)
    if not CFG.EnableItemRecovery then return end
    local moved,alreadyOwned,lost=0,0,0
    local equipped={}
    each(get(pawn,"EquipedItems"),function(item)
        if valid(item) then equipped[path(item)]=true end
    end)
    for i,r in ipairs(entry.gear) do
        local item=r.ref
        if valid(item) then
            if equipped[path(item)] or get(item,"PreviousOwner")==pawn then
                -- If the native respawn already re-equipped it, NEVER detach
                -- that item. Preserve the game's correct replicated state.
                alreadyOwned=alreadyOwned+1
            else
                local at={X=dest.X+((i-1)%4)*55-75,Y=dest.Y+math.floor((i-1)/4)*55,Z=dest.Z+40}
                -- Only reposition surviving actor instances; never spawn copies.
                pcall(function() item:DetachFromAll() end)
                local ok=teleport(item,at)
                if ok then moved=moved+1 else lost=lost+1 end
            end
        else
            lost=lost+1
        end
    end
    log("equipment: "..alreadyOwned.." native re-equipped, "..moved..
        " moved to lift, "..lost.." lost/unavailable")
end
local function processDeaths(ctx)
    if not CFG.EnableRespawn then return end
    local now=os.clock()
    for key,entry in pairs(S.pending) do
        -- Do not try respawn after the entire expedition has already failed.
        if now-entry.started>35 then
            log("respawn timed out for "..key)
            S.pending[key]=nil
        else
            local pawn=currentPawn(entry.controller)
            if entry.spawned and valid(entry.spawned) then pawn=entry.spawned end
            if pawn and path(pawn)~=path(entry.oldChar) and valid(get(pawn,"CharacterStats")) then
                local at=respawnLocation()
                if at and teleport(pawn,at) then
                    local healed=heal(pawn)
                    collectAtElevator(entry,at,pawn)
                    log("respawn in elevator "..key.."; healed="..tostring(healed))
                    S.pending[key]=nil
                    S.respawned=S.respawned+1
                end
            elseif now-entry.started>=CFG.RespawnDelaySeconds and
                   entry.attempts<CFG.MaxRespawnRequests and now>=entry.nextRequest then
                entry.attempts=entry.attempts+1
                entry.nextRequest=now+CFG.RespawnRetrySeconds
                local ok,err=pcall(function()
                    entry.controller:RespawnCharacter_Server()
                end)
                log("respawn request "..entry.attempts.." -> "..tostring(ok)..
                    (ok and "" or (": "..tostring(err))))
            end
        end
    end
end
local function unwrapObject(r)
    r=unwrap(r)
    if not valid(r) then return nil end
    return r
end
local function hostController()
    for _,pc in ipairs(all("HeldenPlayerController")) do
        if valid(pc) then
            local ok,localController=pcall(function() return pc:IsLocalController() end)
            if ok and localController==true then return pc end
        end
    end
    -- On some listen servers this native method is not exposed.
    return nil
end
local function findCoinTarget(pc)
    local pawn=currentPawn(pc)
    if not valid(pawn) then return nil end
    local grab=get(get(pawn,"PhysGrabData"),"Target")
    local target=unwrapObject(grab)
    if not target then
        local inter=get(pc,"CurrentInteractTarget")
        if valid(inter) then
            local ok,owner=pcall(function() return inter:GetOwner() end)
            if ok then target=unwrapObject(owner) end
        end
    end
    if not target then return nil end
    -- Exactly Epic construct quality, no guessing based on material color.
    if enum(get(target,"ConstructQuality"))~=2 then return nil end
    -- Don't destroy quest/puzzle requirements for an optional currency action.
    if get(target,"bIsQuestObjective")==true or
       get(target,"bRequireQuestObjectiveToKill")==true then return nil end
    local pdata
    local ok=pcall(function() pdata=target:GetInspectData() end)
    if not ok or not pdata or get(pdata,"bIsInDungeon")~=true then return nil end
    local value=get(pdata,"Value")
    local artifacts=number(get(value,"Artifacts"),1,CFG.MaxArtifactsPerConversion)
    if not artifacts then return nil end
    local own=location(pawn)
    local obj=location(target)
    if distance2(own,obj)>CFG.MaxCoinDistance^2 then return nil end
    return target,artifacts,obj
end
local function coinClass()
    local ds=first("HeldenDataSingleton")
    local cls=ds and get(ds,"ArtifactCoinActorClass")
    if valid(cls) then return cls end
end
local function convertCoin()
    if not CFG.EnablePhysicalCoins then return end
    if not onHost() then return end
    local ctx=game()
    if not ctx or ctx.phase~=2 then
        log("F7: only available inside an active Expedition")
        return
    end
    local pc=hostController()
    if not pc then log("F7: host player controller not found");return end
    local target,amount,pos=findCoinTarget(pc)
    if not target then
        log("F7: aim at or grab an Epic artifact with a positive Artifact Coin value")
        return
    end
    local id=path(target)
    if not id or S.coinLedger[id] then return end
    local cls=coinClass()
    if not cls then log("F7: ArtifactCoinActorClass unavailable; loot untouched");return end
    local world
    pcall(function() world=target:GetWorld() end)
    if not valid(world) then log("F7: World unavailable; loot untouched");return end
    -- Reserve this actor transaction before any spawn. This is a session-only
    -- guard against double clicks, not an unsafe persistent economic rollback.
    S.coinLedger[id]=true
    local at={X=pos.X,Y=pos.Y,Z=pos.Z+60}
    local ok,coin=pcall(function()
        return world:SpawnActor(cls,at,{Pitch=0,Yaw=0,Roll=0})
    end)
    if not ok or not valid(coin) then
        S.coinLedger[id]=nil
        log("F7: coin spawn failed; artifact left untouched")
        return
    end
    local money=get(coin,"Money")
    local initialized=money and put(money,"Artifacts",amount)
    if initialized then
        -- Explicitly zero the other denominations for exact conversion.
        put(money,"Gold",0);put(money,"Scraps",0)
        initialized=number(get(money,"Artifacts"),0,CFG.MaxArtifactsPerConversion)==amount and
            number(get(money,"Gold"),0,1000000)==0 and
            number(get(money,"Scraps"),0,1000000)==0
    end
    if not initialized then
        log("F7: coin initialization unverified; original loot preserved")
        pcall(function() coin:K2_DestroyActor() end)
        return
    end
    local destroyed=pcall(function() target:K2_DestroyActor() end)
    if not destroyed then
        -- Fail closed: don't hand out extra currency alongside intact loot.
        pcall(function() coin:K2_DestroyActor() end)
        log("F7: cannot consume original loot; attempted coin rollback")
        return
    end
    log("F7: converted Epic loot into physical "..amount.." Artifact Coins")
end

local function poll()
    local now=os.clock()
    local host=onHost()
    local ctx=host and game()
    if now-S.lastHeartbeat>=CFG.HeartbeatDiagnosticsSeconds then
        S.lastHeartbeat=now
        local gs=first("HeldenGameState")
        local gi=first("HeldenGameInstance")
        local save=gi and get(gi,"CurrentSaveGame")
        log("HEARTBEAT host="..tostring(host).." GS="..tostring(valid(gs))..
            " mode="..tostring(enum(get(gs,"GameModeType")))..
            " save="..tostring(valid(save))..
            " saveMode="..tostring(enum(get(save,"GameMode")))..
            " phase="..tostring(ctx and ctx.phase)..
            " deaths="..S.deathEvents.." destructionEvents="..S.rewardEvents)
    end
    if not ctx then
        if S.lastMode~="nonexpedition" then
            S.lastMode="nonexpedition"
            log("inactive: missing authoritative Expedition context")
        end
        return
    end
    S.lastMode="expedition"
    local md=get(ctx.save,"MetaData")
    local slot=number(get(md,"GameSlot"),0,100)
    if not slot then return end
    local key=path(ctx.save)
    if S.slot~=slot or S.saveKey~=key then resetForSave(ctx,key,slot) end
    keepExpedition(ctx)
    processDeaths(ctx)
    if ctx.phase==1 or ctx.phase==2 then
        if S.phase==0 or S.phase==3 then
            cache["HeldenDungeonElevator"]=nil
        end
    end
    if S.phase~=ctx.phase then
        log("run state "..tostring(S.phase).." -> "..ctx.phase.."; depth="..S.depth)
    end
    S.phase=ctx.phase
end

local function isExpeditionDeath()
    if not onHost() then return false end
    local ctx=game()
    return ctx and ctx.phase==2
end
local function watchDeath(context)
    local character=unwrap(context)
    if not valid(character) or not isExpeditionDeath() then return end
    captureDeath(character)
end
local function watchControllerKilled(context)
    local pc=unwrap(context)
    if not valid(pc) or not isExpeditionDeath() then return end
    local old=get(pc,"LastPlayerChar")
    if valid(old) then captureDeath(old) end
end
local function watchNewPawn(context,oldPawn,newPawn)
    local pc=unwrap(context)
    local pawn=unwrap(newPawn)
    if not valid(pc) or not valid(pawn) then return end
    S.newPawnEvents=S.newPawnEvents+1
    local entry=S.pending[path(pc)]
    if entry then entry.spawned=pawn;log("NEWPAWN event for pending death") end
end
local registered={}
local function hook(f,pre,post)
    if registered[f] then return end
    local ok,err=pcall(function() RegisterHook(f,pre,post) end)
    if ok then registered[f]=true else log("hook unavailable "..f..": "..tostring(err)) end
end
-- Native hooks run on the engine thread; no worker threads modify UObjects.
hook("/Script/Helden.HeldenCharacter:Die_Auth",watchDeath)
hook("/Script/Helden.HeldenPlayerController:OnPlayerKilled",
     function() end,watchControllerKilled)
hook("/Script/Helden.HeldenPlayerController:OnNewPawn",
     function() end,watchNewPawn)
if CFG.EnableNoPermadeath then
    -- Native post-hook return override, documented in UE4SS RegisterHook.
    -- A false result is intentionally restricted to the Expedition game
    -- mode and authoritative host; it does not touch normal saves.
    hook("/Script/Helden.HeldenGameState:HasFailedExpedition",
        function() end,
        function(context)
            local gs=unwrap(context)
            if onHost() and valid(gs) and enum(get(gs,"GameModeType"))==1 then
                return false
            end
        end)
end
local function safePoll()
    local now=os.clock()
    if S.lastPoll>=0 and now>=S.lastPoll and now-S.lastPoll<CFG.PollSeconds then return end
    S.lastPoll=now
    local ok,err=pcall(poll)
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
local scheduled=false
if type(LoopInGameThreadWithDelay)=="function" then
    local ok=pcall(function()
        LoopInGameThreadWithDelay(450,function() safePoll() end)
    end)
    if ok then scheduled=true;log("game-thread timer active (450 ms)") end
elseif type(LoopAsync)=="function" and type(ExecuteInGameThread)=="function" then
    local ok=pcall(function()
        LoopAsync(450,function()
            pcall(function() ExecuteInGameThread(function() safePoll() end) end)
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
     end)
if CFG.EnablePhysicalCoins and RegisterKeyBind and Key and Key[CFG.CoinActionKey] then
    local ok,err=pcall(function()
        RegisterKeyBind(Key[CFG.CoinActionKey],function()
            local function task()
                local success,why=pcall(convertCoin)
                if not success then log("F7 coin conversion aborted: "..tostring(why)) end
            end
            if type(ExecuteInGameThread)=="function" then
                local scheduled,err=pcall(function() ExecuteInGameThread(task) end)
                if not scheduled then log("F7 dispatch failed: "..tostring(err)) end
            else
                log("F7: ExecuteInGameThread unavailable; no unsafe coin mutation")
            end
        end)
    end)
    if ok then log("F7 physical Artifact Coin conversion registered (host only)")
    else log("F7 key binding failed: "..tostring(err)) end
end
log("v0.1.0-alpha loaded: Expedition-only respawn, recovery, depth and physical coins")
