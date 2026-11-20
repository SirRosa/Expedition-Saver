# Expedition Saver — Grain Rot

**Wersja v0.3.0-alpha (diagnostyczna i naprawcza).** Poprzednia v0.2 nie działała w prawdziwej sesji: gracz nie odradzał się, nagrody z rozbitych przedmiotów nie wypadały, a winda pozostawała zamknięta z komunikatem *Expedition Failed*. Bieżąca wersja usuwa błędy wykryte podczas audytu, lecz **wciąż nie ma potwierdzenia działania w grze**. 31 testów w GitHub Actions to testy symulacyjne, nie testy multiplayer UE5.

## Naprawy w v0.3

1. **Wartości lootu:** zastosowano reflektowane metody `HeldenConstructActor:GetConstructAssetData()` / `GetConstructAsset()`; poprzedni kod odczytywał nieistniejące pole `ConstructAsset` oraz nie uwzględniał, że zwykły `HeldenPhysicsActor` nie implementuje `GetInspectData()`.
2. **Przynależność do lochu:** `OwningDungeon` jest słabą referencją UE4SS (`FWeakObjectPtr`), rozwiązywaną przez `:Get()`, a nie `:get()`.
3. **Dane QOL:** odczytywane są bez dodatkowych mnożników aktualne wiersze `PhysActorDataTable` oraz dane konstrukcji. Odczytują one wartości zmienione przez QOL, o ile QOL zmienił te same dane.
4. **Fizyczne Gold i Artifact Coins:** wyniki niszczenia trafiają do kolejki i są realizowane w następnej iteracji wątku gry. Usunięto opóźnienia oparte na `os.clock()`. Dodano kontrolę struktury monety po jej zainicjalizowaniu; scrap pozostaje pod kontrolą gry.
5. **Respawn:** również ponowne próby i timeout są liczone w krokach pętli gry, nie w sekundach CPU. Mod zachowuje stan aktywnej ekspedycji i referencje do ekwipunku przy zmianie obiektu zapisu w tym samym slocie.
6. **Winda i porażka:** rozpoznaje `EndScreen` z flagą `Failed` również wtedy, kiedy nie zaobserwował wcześniej `Exploring`. Ponawia naprawę stanu zakończonego runu i blokady interakcji bez opóźnień zależnych od `os.clock()`.
7. **Weryfikacja uruchomienia:** `UE4SS.log` zawiera `HOOK ACTIVE`, `HEARTBEAT`, `RAW DIE_Auth`, `RAW OnPlayerKilled`, `RAW DESTRUCTION`, `DROP SKIP`, `COIN SPAWN FAILED`, `RECOVERY` oraz `DROP`. Pozwala to oddzielić brak rejestracji hooka od odrzucenia operacji przez serwer.

## Instalacja i bezpieczne testy

1. Zrób **kopię zapisu ekspedycji** — modyfikowanie flag permadeath i stanu runu może mieć konsekwencje dla serializacji gry.
2. Pobierz `ExpeditionSaver-v0.3.0-alpha.zip` z [GitHub Actions](https://github.com/SirRosa/Expedition-Saver/actions).
3. Zastąp stary folder moda w `Grain Rot\Helden\Binaries\Win64\ue4ss\Mods\ExpeditionSaver`. Nie instaluj kolejnego UE4SS. **Mod instaluj tylko u hosta.**
4. Na potrzeby testów wyłącz Depth Keeper. W modzie QOL ustaw `InsuranceOnWipe = false`, aby uniknąć podwójnego odzyskiwania przedmiotów.
5. Wejdź w Expedition, rozbij jeden niecenny przedmiot lootu młotkiem, a następnie — na **kopii zapisu** — sprawdź śmierć i ponowny zjazd windą.
6. Prześlij **pełny nowy `ue4ss\UE4SS.log`** wygenerowany podczas tego testu. Wcześniejszy log otrzymany z grą dotyczył narzędzia ExpeditionMapper, nie tych prób v0.2/v0.3.

### Jak interpretować log

| Wpis | Znaczenie |
|---|---|
| `v0.3.0-alpha loaded` | Kod Lua w ogóle się uruchomił |
| `HOOK ACTIVE` | Zarejestrowano callback; nie oznacza jeszcze, że gra go wywołuje |
| `HEARTBEAT ... mode=1 phase=2` | Rozpoznano grę w Expedition i aktywny run |
| `RAW DIE_Auth` / `RAW OnPlayerKilled` | Serwer wywołał zdarzenie śmierci |
| `RAW DESTRUCTION` / `DROP SKIP` | Zdarzenie niszczenia dotarło do moda, ale warunek mógł zablokować nagrodę |
| `DROP gold` / `DROP artifacts` | Kod potwierdził utworzenie aktora monety z kwotą |
| `RECOVERY run=3 -> 0` | Kod odczytał po zmianie stan runu równy 0 |
| `HOOK NOT READY`, `COIN ... FAILED`, `poll error` | Dane diagnostyczne problemów w rzeczywistym UE4SS |

**Nie stwierdzamy jeszcze, że v0.3 rozwiązuje wszystkie trzy problemy.** Bez logu hosta z prawdziwej wyprawy nie można potwierdzić faktycznej ścieżki śmierci, replikacji monet ani natywnego otwarcia windy. Zrzut `USMAP` zawiera nazwy pól i metod, ale nie logikę C++.

## Źródła i testy

- Mapowanie `Helden-5.7.4-51494982+++UE5+Release-5.7-1c1a1497.usmap` i `UE4SS_ObjectDump.txt` z 20 listopada 2026.
- [Analiza refleksji klas](docs/mapping-analysis-2026-11-20.md).
- `tests/test_expedition.lua` — 31 testów symulacyjnych.
- `ue4ss/Mods/ExpeditionMapper` — osobne narzędzie diagnostyczne, niepotrzebne do instalacji moda.
