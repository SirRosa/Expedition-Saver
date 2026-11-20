# Grain Rot — Expedition Saver

**v0.1.0-alpha | testowa wersja moda UE4SS | tylko tryb Expedition i host.**

Kod powstał na podstawie pliku mapowań wygenerowanego 20 listopada 2026 r. oraz pełnego zrzutu refleksji. **Zaliczone testy GitHub Actions symulują grę, nie potwierdzają działania w rzeczywistej sesji.** Wykonaj kopię zapisu.

## Funkcje

| Żądana funkcja | Stan implementacji i ograniczenia |
|---|---|
| Respawn po śmierci w windzie | Przechwytuje serwerową śmierć gracza, następnie próbuje wywołać natywne `RespawnCharacter_Server`, przenieść nową postać do windy i przywrócić zdrowie. Nie działa poza Expedition. Nie jest jeszcze potwierdzone, że gra zezwala na takie odrodzenie po śmierci ostatniego gracza. |
| Ekwipunek po odrodzeniu | Zachowuje referencje do istniejących przedmiotów. Te automatycznie wyposażone przez grę pozostawia nietknięte. Pozostałe *nadal istniejące* przedmioty próbuje przenieść do windy. **Nie odtwarza przedmiotów, które silnik już zniszczył**, i nie gwarantuje ponownego wyposażenia w slotach. To jeszcze nie jest pełna, potwierdzona realizacja „wszystkie itemki”. |
| Koniec permadeath i ostatnie piętro | Próbuje nadpisać wynik `HasFailedExpedition`, wyczyścić trwałe flagi porażki i przywrócić najwyższe `DungeonLevel`. Ma pomocniczą, lokalną kopię głębokości per slot. Nie modyfikuje aktywnego seeda wygenerowanej mapy. Nie ma jeszcze testu powrotu z końca ekspedycji w grze. |
| Fioletowy loot → fizyczne Artifact Coins | Na hoście naciśnij **F7** przy trzymanym albo wskazywanym przedmiocie klasy Epic. Wymagane są dodatnie `GetInspectData().Value.Artifacts`, bliskość i dostępna `ArtifactCoinActorClass`. Najpierw tworzy fizyczny żeton i weryfikuje wartość, a dopiero potem próbuje zniszczyć oryginał. Brak bezpośredniego dodawania żetonów do portfela. Pomija wskazane flagi questowe. Niepotwierdzone w multiplayer i nie gwarantuje atomowej transakcji, jeśli gra nadpisze aktora żetonu. |

## Instalacja

1. Zrób **kopię zapisu gry** przed pierwszym uruchomieniem.
2. Pobierz `ExpeditionSaver-v0.1.0-alpha.zip` z artefaktów ostatniego udanego przebiegu [GitHub Actions](https://github.com/SirRosa/Expedition-Saver/actions).
3. Rozpakuj do `Grain Rot\Helden\Binaries\Win64\`. Powinno powstać `ue4ss\Mods\ExpeditionSaver\Scripts\main.lua` oraz `enabled.txt`. Nie instaluj kolejnego UE4SS.
4. Gra z innymi osobami: instalacja **wyłącznie u hosta**. Przycisk F7 działa na hoście. Nie ma jeszcze klient-serwer RPC do zdalnego użycia tej funkcji.
5. **Na pierwsze testy wyłącz Depth Keeper i QOL**, gdyż oba mogą modyfikować głębokość lub odzyskiwanie wyposażenia i utrudnią analizę.

Mod `ExpeditionMapper` pozostaje w repozytorium jako **osobne, tylko diagnostyczne narzędzie**. Nie jest potrzebny do uruchomienia Expedition Saver i nie znajduje się w paczce gameplay.

## Pierwszy test w grze (na kopii zapisu)

1. Otwórz Expedition i sprawdź, czy w `ue4ss\UE4SS.log` jest wpis `[ExpeditionSaver] v0.1.0-alpha loaded`. Jeżeli znajdziesz `hook unavailable`, `poll error` albo `respawn timed out`, zachowaj log.
2. Z jednym tanim przedmiotem sprawdź respawn po śmierci, pozycję postaci, przedmiot na miejscu i aktualny stan gry.
3. Osobno przetestuj śmierć całej drużyny i ponowne uruchomienie ekspedycji — nie wystarczy, że sam wyświetlacz pokazuje ostatnie piętro.
4. W Expedition zbliż się do fioletowego lootu z **wartością Artifact Coins większą od zera**, złap go lub wskaż i naciśnij F7. Sprawdź fizyczny żeton na ziemi oraz to, czy oryginał zniknął. Nie testuj na unikatowym/przedmiocie questowym.
5. Po sesji prześlij `UE4SS.log`, jeśli któraś funkcja nie zadziała lub itemy znikną.

## Bezpieczeństwo i szczegóły techniczne

- UE4SS v3: niezależny timer `LoopAsync` przekazuje sprawdzenia na główny wątek za pomocą `ExecuteInGameThread`. Jeśli timer jest niedostępny, działa awaryjny hook animacji.
- Nie zmienia zachowania poza Expedition; przy braku autorytatywnego `GameModeBase` pozostaje bezczynny.
- Nie tworzy kopii ekwipunku po śmierci; zapobiega przypadkowej duplikacji, ale nie daje jeszcze gwarancji zachowania wszystkich slotów.
- Nie niszczy fioletowego przedmiotu, jeżeli nie uda się stworzyć i zainicjalizować fizycznej monety; próbuje wycofać monetę, jeśli niszczenie przedmiotu zawiedzie.
- Lokalna kopia głębokości: `%LOCALAPPDATA%\Helden\Saved\ExpeditionSaver_slotN.txt`. Jest pomocnicza, a nie zamiennikiem save'u gry.
- Przedmioty Quest, odmienne reprezentacje fioletowej rzadkości i numeryczne enumy innej wersji gry wymagają oddzielnej walidacji.

## Badania

[Szczegółowy raport o zrzucie klas i funkcji](docs/mapping-analysis-2026-11-20.md).

Testy w `tests/test_expedition.lua` działają w symulowanym API i nie uruchamiają Unreal Engine ani sieci multiplayer.
