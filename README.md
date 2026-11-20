# Grain Rot — Expedition Saver

## v0.7.1 — bez fizycznego dropu walut za meble (TEST)

**W Story Mode i Expedition wszystkie Gold i Artifact Coins z niszczenia mebli są wpłacane bezpośrednio do portfela gracza.** Żaden przypadek nie wywołuje `SpawnActor` dla monet ani nie uruchamia ich fizyki.

Kolejność wyboru odbiorcy:
1. Gracz jednoznacznie wskazany przez zdarzenie trafienia.
2. Jeden jednoznacznie rozpoznany atakujący bronią.
3. **Gracz znajdujący się najbliżej zniszczonego obiektu** — bez limitu zasięgu i bez tolerancji odległości, nawet gdy różnica wynosi 1 mm lub mniej.

Jeżeli odległość jest *dokładnie* taka sama, wygrywa stabilna kolejność pełnych nazw kontrolerów. Jeżeli brak dostępnej postaci lub odczyt pozycji/portfela jest chwilowo niemożliwy, nagroda pozostaje w kolejce i mod ponawia próbę. **Nie zamienia jej na fizyczny drop.** Log `DIRECT REWARD PENDING` oznacza zaległą wypłatę.

To dotyczy dodatkowych monet i żetonów przy niszczeniu mebli. **Natywny drop scrapu oraz osobna procedura naprawy walut po śmierci nie zostały zmienione.** Nie są niszczone przedmioty ani ich fizyczne reprezentacje.

CI sprawdza testy Lua/UE4SS (w tym różnicę 1 mm, remis, równoczesne ataki, chwilowy brak portfela, Story Mode). W prawdziwej grze wynik wymaga potwierdzenia.


## v0.7.0 — Story + Expedition death/rewards (TEST BUILD)

**This build handles Story (EHeldenGameMode.Default=0) AND Expedition (1).**
- Shared native `RespawnCharacter_Server`, gear restoration and wallet recovery in BOTH modes.
- Expedition still restores depth and unlocks its failure/elevator objects; these save mutations do **not** run in Story.
- In Story without a DungeonElevator, native spawn location is preserved; if reviving the old pawn, use a PlayerStart or last known alive position.
- Destroying furniture/physical treasure uses the same XP-multiplied/QOL table reward in Story, and credits Gold/Artifacts directly when the recipient is known.
- In multiplayer, the recipient can be identified by native damage overlap, projectile damage, a recent `HeldenWeapon:Attack_Server`, or a unique melee-range player. Never pay two players or blindly assign an unresolved reward: fall back to the original physical Gold/Artifacts actor, with diagnostic `reason=unverified-coop` or `multiple-attackers`.
- **Death duplication:** after restoring the wallet, scan only *new, very recent, nearby* `HeldenPhysicsCoin` actors from the death area, verify the coin's value is within the missing-drop budget, zero its `Money` and destroy the actor. Unlike v0.5.1, the currency drop need NOT match the exact entire Gold/Artifacts/Scraps wallet; partial drop is supported.
- Never delete or alter `HeldenEquipableItem`, equipment actors, older floor coins, coins in other maps, or money before a safe wallet check. An unknown origin is inherently ambiguous; inspect log if some coins remain.

**Acceptance test (host + client):**
1. Back up save; replace previous ExpeditionSaver and QOL versions.
2. Story: destroy a furniture item, check gold/tokens instantly and normal native scrap behavior; die, respawn, verify all gear and money.
3. Expedition: repeat with both players close to the same furniture and test a confirmed hammer hit.
4. After death check original site for duplicated currency and logs: `PLAYER DEATH queued`, `MONEY RESTORE`, `DEATH COINS REMOVED`/`DEATH COINS RESULT`, `DIRECT REWARD`, `DROP ... reason=`.
5. Watch `PERF slow Expedition poll` events to correlate stalls. All CI tests are mocked UE4SS and cannot confirm runtime replication/FPS.

**Test branch:** `fix/story-respawn-rewards-and-death-dup-v07`; separate from main.

---


## v0.6.0 — experimental direct reward and stutter reduction

- When furniture or dungeon treasure is destroyed, credits its Gold / Artifact Coins directly to the verified player wallet, without spawning physics coin actors.
- For solo play, uses the sole player. In co-op, requires an active damage-box overlap or projectile hit associated with that player in a short window. **Does not use the destructible actor's own GetInstigatorController as proof of killer**.
- If co-op attribution is unavailable or ambiguous, physical money is retained instead of silently giving it to the wrong player or deleting the reward. Native scrap/resource drops stay unchanged.
- Before direct payout, validates `Money` changes through a fresh readback; retains physical fallback when it cannot verify the credit.
- Skips expensive full Expedition context lookups for non-lethal physics-health events and shares one global equipment scan across co-op players per 300-ms poll. `PERF slow Expedition poll CPU=...ms` logs costly cycles.
- Carries the prior anti-duplication patch for money dropped at the player's death; **never deletes equipment actors**.
- This is a GitHub Actions mock-tested experimental branch; actual damage attribution, HUD/replication, and stall improvements are not yet confirmed in Grain Rot.


## v0.5.1-alpha — testowa poprawka duplikowania waluty po śmierci

**Problem:** v0.5 przywracał `HeldenCharacter.Money` (Gold, Artifacts, Scraps)
na nowym pawnie, ale natywna gra mogła pozostawić tę samą walutę w
`HeldenPhysicsCoin` przy miejscu śmierci. Późniejsze podniesienie monet
powodowało duplikację.

**Poprawka (host, tylko Expedition):**
- Zapamiętuje aktorów monet istniejących za życia gracza oraz ostatnie miejsce śmierci.
- Po pomyślnym przywróceniu całego salda szuka wyłącznie **nowych,
  świeżych aktorów `HeldenPhysicsCoin`** w promieniu 240 cm od miejsca śmierci,
  w tym samym świecie.
- Usuwa tylko **jednoznaczny zestaw monet**, którego suma Gold/Artifacts/Scraps
  dokładnie odpowiada migawce utraconej waluty. Najpierw sprawdza saldo
  nowej postaci, następnie zeruje kwotę w aktorze i weryfikuje zapis
  do `Money`, a dopiero potem niszczy aktor monety.
- **Nie dotyka `HeldenEquipableItem`, wyposażenia ani zwykłych przedmiotów na ziemi.**
  Nie usuwa wcześniejszych, odległych, starych ani niejednoznacznych monet.
- Nie dokłada hooka animacji; monitoring trwa tylko podczas aktywnego
  problemu, a bazowe skanowanie monet odbywa się co cztery cykle timera.

**Status: testy symulacyjne GitHub Actions przechodzą, działanie w grze niezweryfikowane.**
Gdy gra używa innej klasy death drop lub rozdziela wypłatę inaczej,
mod zapisze `DEATH COINS UNRESOLVED` i **nie skasuje niczego w ciemno**.
Wtedy ryzyko duplikacji nadal istnieje; konieczny będzie log z gry.

Pobierz testową paczkę `ExpeditionSaver-v0.5.1-death-currency-hotfix.zip`
z [GitHub Actions](https://github.com/SirRosa/Expedition-Saver/actions)
dla gałęzi `fix/death-currency-duplication`.
Zainstaluj na hoście po wykonaniu kopii sejwa. Pozostałe funkcje
v0.5 (respawn, odzyskiwanie itemów, wypłata loot, fizyka monet) pozostają.
Przy równoczesnym QOL ustaw `InsuranceOnWipe=false`, aby osobny
mechanizm ubezpieczenia nie dublował **przedmiotów**.

**Test:** weź znane ilości wszystkich trzech walut oraz 1 przedmiot,
zgiń, sprawdź saldo i ekwipunek po respawnie, następnie wróć do miejsca
śmierci. Szukaj w `UE4SS.log` wpisów `DEATH COINS tracking`,
`DEATH COINS matched=...` lub `DEATH COINS UNRESOLVED`.
Poprawność musi obejmować również brak monet w miejscu śmierci i stan po
zapisaniu/ponownym wczytaniu.

---

## v0.5.0-alpha — ochrona ekwipunku, waluty, fizyka monet i skarby

**Wydanie testowe** po analizie rzeczywistego logu `UE4SS(4).log` z v0.4.

W v0.4 **respawn w windzie zadziałał**, ale log wykazał: `retained=1` i `EQUIPMENT native=0 moved=1`. Przedmiot został przeniesiony **na podłogę windy**, zamiast do slotu. Nie było też żadnego zapisu pieniędzy. Zwykłe meble generowały monety (np. Gold x9, x15, x45), ale bez włączonej symulacji fizyki. Wartościowe `BP_DefaultPhysTreasure_C` docierały do hooka, lecz otrzymywały `no coin payout`.

### Zmiany v0.5

| Funkcja | Nowa implementacja |
|---|---|
| **Odrodzenie z wyposażeniem** | Przed śmiercią zapisuje do 64 przedmiotów z `EquipedItems`, **wszystkich** `ItemSlots[].CurrentItemInSlot` i prawidłowo przypisanych przedmiotów gracza. Po respawnie próbuje ich **natywnego podniesienia** poprzez `Interact(InCharacter)`, a następnie `Interact_Server(InCharacter, InInteraction)`. Weryfikuje prawdziwe sloty. Wielokrotne próby są ograniczone, z ochroną przed duplikacją. |
| **Odtwarzanie zniszczonych przedmiotów** | Jeżeli oryginalny aktor nie istnieje i nie ma go w ekwipunku, próbuje jednorazowo zespawnować aktor tej samej klasy, z zachowanym assetem, trwałością i enchantmentem, a następnie natywnie go podnieść. Nie odtwarza bez końca. |
| **Ochrona walut** | Zapisuje Gold, Artifact Coins i Scraps z `HeldenCharacter.Money` w trakcie eksploracji, **przed śmiercią**. Po respawnie uzupełnia tylko brakującą różnicę na nowym pawnie. Nigdy nie zmniejsza wyższego salda. |
| **Monety na ziemi** | Na `RootMesh` fizycznych monet włącza `SetSimulatePhysics(true)`, `SetEnableGravity(true)`, `WakeAllRigidBodies()`; monety spawnują bliżej obiektu. Log podaje stan symulacji i grawitacji. |
| **Biały, niebieski i fioletowy loot** | Dla `BP_DefaultPhysTreasure_C` sprawdza `GetInspectData`, `GetConstructAssetData`, aktualne po QOL wiersze `PhysActorDataTable` oraz mapuje `PhysTreasureContainer.TreasureData` na mesh przedmiotu. **Zero z pierwszego źródła nie kończy wyliczenia.** |
| **Zwykłe meble** | Kwoty nadal pochodzą z aktualnych danych gry po modyfikacjach QOL; mod nie nakłada drugiego mnożnika. |

### Instalacja

1. **Zrób kopię zapisu.** Dotyczy to zwłaszcza testowania śmierci i odtwarzania sprzętu.
2. Pobierz `ExpeditionSaver-v0.5.0-alpha.zip` z [GitHub Actions](https://github.com/SirRosa/Expedition-Saver/actions).
3. Usuń starą zawartość folderu `ue4ss\Mods\ExpeditionSaver` i wypakuj archiwum do `Grain Rot\Helden\Binaries\Win64\`. Gra powinna uruchomić jedynie wersję `v0.5.0-alpha` — sprawdź wpis w `ue4ss\UE4SS.log`.
4. **Wyłącz GrainRotDepthKeeper**, który nadal był uruchomiony podczas testu v0.4. QOL pozostaw włączony, jeżeli testujesz jego wartości, ale w `GrainRotQOL\Scripts\main.lua` ustaw `InsuranceOnWipe = false`, aby uniknąć zdublowanych przedmiotów po porażce. Na serwerze mod musi być zainstalowany u hosta.

### Ważne warunki akceptacji

- Po śmierci postać rzeczywiście ma wszystkie wcześniej posiadane przedmioty **w slotach** i właściwe Gold/Artifacts/Scraps. Samo leżenie przedmiotu w windzie nie jest pełnym sukcesem.
- `INVENTORY RESULT inventory=N floor_or_missing=0 fullyRestored=true` oznacza, że kod rozpoznał wszystkie zapisane przedmioty w natywnym ekwipunku. Jeśli `floor_or_missing>0`, log wyraźnie wskazuje niepowodzenie.
- `MONEY RESTORE` pokazuje salda przed i po odzyskaniu. **Uwaga:** natywna gra może również porzucić walutę w miejscu śmierci. W v0.5 nie mamy jeszcze gwarancji eliminacji ewentualnych duplikatów przy jej późniejszym podniesieniu.
- `COIN PHYSICAL ... simulatesPhysics=true gravity=true` powinno potwierdzić fizykę; faktyczny ruch należy sprawdzić wzrokowo w grze.
- `TREASURE REWARD UNRESOLVED` oznacza, że nie udało się przypisać rzeczywistego rekordu wartości danemu skarbowi. Mod nie wymyśla nagrody, ale loguje kandydatów do dalszej analizy.
- Status `Expedition Failed` i ponowny zjazd windy **nie były testowane w logu v0.4**, a więc nie ma nowego potwierdzenia ich działania.

### Ograniczenia bezpieczeństwa

**Nie ma jeszcze gwarancji pełnego przywrócenia ekwipunku.** Jeśli silnik odrzuci natywną interakcję, mod pozostawia istniejący lub utworzony przedmiot **na podłodze windy** zamiast usuwać go. Nie manipuluje na ślepo niezidentyfikowanymi wskaźnikami slotów, aby nie uszkodzić zapisu. Rzeczywiste zachowanie `Interact` trzeba potwierdzić w grze.

Testy GitHub Actions są oparte na symulowanym API UE4SS, a nie na uruchomionym Grain Rot.

### Dokumentacja

- [Audyt logu v0.4](docs/live-session-audit-v0.4-2026-11-20.md)
- [Audyt logu v0.3](docs/live-session-audit-2026-11-20.md)
- [Analiza USMAP](docs/mapping-analysis-2026-11-20.md)
