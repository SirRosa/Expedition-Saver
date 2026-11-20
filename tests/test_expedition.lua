-- Expedition Saver UE4SS mock suite. The native game is NOT running here.
local MAIN="ue4ss/Mods/ExpeditionSaver/Scripts/main.lua"
local function actor(fields)
    local a=fields or {}
    function a:IsValid() return self._valid~=false end
    function a:GetFullName() return self._name or tostring(self) end
    return a
end
local function fixture()
    local now=0
    local registry,hooks,keys,files,logs,spawned={},{},{},{},{},{}
    local counts={clock=0,first=0,all=0,respawn=0,teleport=0}
    local gm=actor({_name="GameMode /Game/GM"})
    local md={GameSlot=0,GameMode=1,bHasFailed=false}
    local save=actor({_name="SaveGame /Game/S0",MetaData=md,GameMode=1,
        DungeonLevel=2,TimePlayed=30,DungeonFails=0})
    local gi=actor({_name="HeldenGameInstance /Game/Instance",CurrentSaveGame=save})
    local lift=actor({_name="HeldenDungeonElevator /Game/Lift",InteriorCollisionBox=actor()})
    function lift.InteriorCollisionBox:K2_GetComponentLocation()
        return {X=1000,Y=2000,Z=300}
    end
    local dungeon=actor({CurrentSeed={Level=1}})
    local run={State=2,Flags=0,DungeonActor=dungeon}
    local gs=actor({_name="HeldenGameState /Game/GS",GameModeType=1,bExpeditionFailed=false,
        CurrentDungeonRun=run})
    local stats=actor({CurrentHealth=0,TotalStats={MaxHealth=120}})
    local corpse=actor({_name="HeldenCharacter /Game/Old",EquipedItems={},CharacterStats=stats})
    local newPawn=actor({_name="HeldenPlayerCharacter /Game/New",CharacterStats=
        actor({CurrentHealth=1,TotalStats={MaxHealth=120}})})
    function newPawn:K2_TeleportTo(at,rot)
        counts.teleport=counts.teleport+1
        self.location=at
        return true
    end
    local pc=actor({_name="HeldenPlayerController /Game/PC",LastPlayerChar=corpse})
    function corpse:GetController() return pc end
    function corpse:K2_GetActorLocation() return {X=1000,Y=2000,Z=300} end
    function pc:GetPawn() return self._pawn end
    pc._pawn=corpse
    function pc:IsLocalController() return true end
    function pc:RespawnCharacter_Server()
        counts.respawn=counts.respawn+1
        self._pawn=newPawn
    end
    local item=actor({_name="HeldenEquipableItem /Game/A",CurrentInventorySlot=0,
        PreviousOwner=corpse,CurrentSlot=actor({_name="ItemSlot"})})
    function item:DetachFromAll() self.detached=true end
    function item:K2_TeleportTo(at,rot)
        self.location=at
        self.wasMoved=true
        return true
    end
    corpse.EquipedItems={item}
    registry.GameModeBase=gm;registry.HeldenGameInstance=gi
    registry.HeldenGameState=gs;registry.HeldenDungeonElevator=lift
    local data=actor({_name="DataSingleton /Game/DS"})
    local coinClass=actor({_name="Class /Game/BP_ArtifactCoin"})
    data.ArtifactCoinActorClass=coinClass
    registry.HeldenDataSingleton=data
    local loot=actor({_name="ConstructActor /Game/EpicLoot",ConstructQuality=2})
    function loot:K2_GetActorLocation() return {X=1000,Y=1980,Z=300} end
    function loot:GetInspectData() return {bIsInDungeon=true,Value={Artifacts=6}} end
    function loot:K2_DestroyActor() self._valid=false end
    local itComp=actor()
    function itComp:GetOwner() return loot end
    pc.CurrentInteractTarget=itComp
    function newPawn:K2_GetActorLocation() return {X=1000,Y=2000,Z=300} end
    local world=actor({_name="World /Game/World"})
    function loot:GetWorld() return world end
    function world:SpawnActor(cls,loc,rot)
        assert(cls==coinClass)
        local coin=actor({Money={Artifacts=0,Gold=0,Scraps=0}})
        function coin:K2_DestroyActor() self._valid=false end
        spawned[#spawned+1]={coin=coin,loc=loc}
        return coin
    end
    local listing={HeldenPlayerController={pc},HeldenEquipableItem={item}}
    local clockcb
    local fakeio={open=function(fname,mode)
        if mode=="r" then
            local v=files[fname]
            if not v then return nil end
            return {read=function() return v:match("([^\r\n]+)") end,
                    close=function() end}
        end
        assert(mode=="w")
        return {write=function(_,text) files[fname]=text end,
                close=function() end}
    end}
    local env=setmetatable({
        os={clock=function() counts.clock=counts.clock+1;return now end,
            getenv=function() return "C:\\Users\\Tester\\AppData\\Local" end},
        io=fakeio,
        print=function(msg) logs[#logs+1]=msg end,
        FindFirstOf=function(cls) counts.first=counts.first+1;return registry[cls] end,
        FindAllOf=function(cls) counts.all=counts.all+1;return listing[cls] or {} end,
        RegisterHook=function(name,pre,post) hooks[name]={pre=pre,post=post} end,
        RegisterKeyBind=function(key,callback) keys[key]=callback end,
        Key={F7=118},
        LoopInGameThreadWithDelay=function(ms,callback)
            assert(ms==450);clockcb=callback;return 1
        end,
        ExecuteInGameThread=function(callback) callback() end,
    },{__index=_G})
    env._G=env
    assert(loadfile(MAIN,"t",env))()
    assert(clockcb,"game-thread timer not registered")
    local test={
        gm=gm,save=save,md=md,gi=gi,gs=gs,run=run,
        lift=lift,pc=pc,corpse=corpse,newPawn=newPawn,item=item,loot=loot,
        world=world,registry=registry,listing=listing,spawned=spawned,
        hooks=hooks,keys=keys,logs=logs,files=files,counts=counts,
        tick=function(dt) now=now+(dt or 0.7);clockcb() end,
        killed=function()
            local h=hooks["/Script/Helden.HeldenCharacter:Die_Auth"]
            assert(h and h.pre)
            h.pre(corpse)
        end,
        convert=function()
            assert(keys[118],"F7 missing")
            keys[118]()
        end,
        switchMode=function(mode)
            gs.GameModeType=mode;save.GameMode=mode;md.GameMode=mode
        end
    }
    return test
end
local passed=0
local function test(title,callback)
    callback()
    passed=passed+1
    print("PASS: "..title)
end
test("in expedition, depth and permadeath markers survive party wipe",function()
    local t=fixture()
    t.save.DungeonLevel=10;t.run.DungeonActor.CurrentSeed.Level=9
    t.tick()
    t.run.State=3;t.run.Flags=1;t.save.DungeonLevel=0
    t.md.bHasFailed=true;t.gs.bExpeditionFailed=true
    t.tick()
    assert(t.save.DungeonLevel==10,"depth must be restored")
    assert(t.md.bHasFailed==false and t.gs.bExpeditionFailed==false,
        "permadeath marker must clear on failed run")
end)
test("normal game is completely unchanged",function()
    local t=fixture()
    t.switchMode(0)
    t.md.bHasFailed=true
    t.gs.bExpeditionFailed=true
    t.run.State=3;t.run.Flags=1
    t.save.DungeonLevel=0
    t.tick()
    assert(t.save.DungeonLevel==0 and t.md.bHasFailed and t.gs.bExpeditionFailed)
    assert(t.counts.respawn==0)
end)
test("saved depth backup remains per-slot and never compounds",function()
    local t=fixture()
    t.save.DungeonLevel=5
    t.run.DungeonActor.CurrentSeed.Level=4
    t.tick()
    local count=0 for _ in pairs(t.files) do count=count+1 end
    assert(count==1 and t.files["C:\\Users\\Tester\\AppData\\Local\\Helden\\Saved\\ExpeditionSaver_slot0.txt"])
    t.tick()
    local count2=0 for _ in pairs(t.files) do count2=count2+1 end
    assert(count2==1)
end)
test("death of player uses native server respawn, then teleports to lift",function()
    local t=fixture()
    t.tick()
    t.killed()
    t.tick(1.5)
    assert(t.counts.respawn==1,"native server respawn should be requested")
    t.tick()
    assert(t.newPawn.location and t.newPawn.location.Z==380,"should respawn inside lift")
    assert(t.newPawn.CharacterStats.CurrentHealth==120,"health should restore")
    assert(t.counts.respawn==1,"no duplicate respawn")
end)
test("existing equipped item moves to elevator, never spawns duplicated item",function()
    local t=fixture();t.tick();t.killed();t.tick(1.5);t.tick()
    assert(t.item.wasMoved and t.item.detached)
    assert(#t.spawned==0)
    assert(t.item.location.Z==420)
end)
test("no respawn after whole expedition has ended",function()
    local t=fixture();t.tick();t.killed()
    t.run.State=3;t.run.Flags=1
    t.tick(2)
    assert(t.counts.respawn==0)
end)
test("AI character death is ignored",function()
    local t=fixture();t.tick()
    local npc=actor({_name="NPC /Game/Enemy"})
    local ai=actor({_name="AIController /Game/AI"})
    function npc:GetController() return ai end
    t.hooks["/Script/Helden.HeldenCharacter:Die_Auth"].pre(npc)
    t.tick(2)
    assert(t.counts.respawn==0)
end)
test("F7 destroys Epic loot only after creating physical coin with correct value",function()
    local t=fixture();t.tick()
    t.convert()
    assert(#t.spawned==1)
    assert(t.spawned[1].coin.Money.Artifacts==6)
    assert(t.spawned[1].coin.Money.Gold==0)
    assert(t.loot._valid==false)
end)
test("F7 double press cannot duplicate coins",function()
    local t=fixture();t.tick();t.convert();t.convert()
    assert(#t.spawned==1)
end)
test("F7 never converts a non-Epic object",function()
    local t=fixture();t.tick()
    t.loot.ConstructQuality=1
    t.convert()
    assert(#t.spawned==0 and t.loot._valid~=false)
end)
test("F7 never converts a non-Artifact reward or outpost loot",function()
    local t=fixture();t.tick()
    t.loot.GetInspectData=function() return {bIsInDungeon=true,Value={Artifacts=0}} end
    t.convert();assert(#t.spawned==0)
    t.loot.GetInspectData=function() return {bIsInDungeon=false,Value={Artifacts=9}} end
    t.convert();assert(#t.spawned==0)
end)
test("F7 disabled if world or coin class missing: no loot loss",function()
    local t=fixture();t.tick()
    t.registry.HeldenDataSingleton.ArtifactCoinActorClass=nil
    t.convert()
    assert(#t.spawned==0 and t.loot._valid~=false)
end)
test("F7 not enabled outside active Expedition",function()
    local t=fixture();t.tick()
    t.run.State=0;t.convert();assert(#t.spawned==0)
    t.run.State=2;t.switchMode(0);t.convert();assert(#t.spawned==0)
end)
test("client-only mode never changes save or coins",function()
    local t=fixture();t.tick()
    t.gm._valid=false;t.registry.GameModeBase=nil
    t.run.State=3;t.run.Flags=1
    t.md.bHasFailed=true;t.gs.bExpeditionFailed=true
    t.tick()
    assert(t.md.bHasFailed and t.gs.bExpeditionFailed)
    t.convert();assert(#t.spawned==0)
end)
test("a timer is independent of animation callback after all players die",function()
    local t=fixture()
    assert(t.hooks["/Game/Animation/ABP_HeldenPlayer.ABP_HeldenPlayer_C:BlueprintUpdateAnimation"]==nil,
        "timer should replace hot animation hook")
    t.run.State=3;t.run.Flags=1;t.md.bHasFailed=true
    t.tick()
    assert(t.md.bHasFailed==false)
end)
test("do not detach items the game already equipped on respawn",function()
    local t=fixture();t.tick();t.killed()
    t.newPawn.EquipedItems={t.item}
    t.item.PreviousOwner=t.newPawn
    t.tick(1.5);t.tick()
    assert(t.item.detached~=true and not t.item.wasMoved,
        "native equipped items must remain in native inventory")
end)
test("do not convert Epic quest artifacts",function()
    local t=fixture();t.tick()
    t.loot.bIsQuestObjective=true
    t.convert()
    assert(#t.spawned==0 and t.loot._valid~=false)
end)

print("ALL TESTS PASSED ("..passed..")")
