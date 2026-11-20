# Expedition Saver — rozpoznanie API gry

**Stan: diagnostyka, nie ukończony mod zmieniający rozgrywkę.** Dostępne mapowanie Helden z 5 września 2026 r. jest starsze od trybu Expedition dodanego w patchu 1.1 (24 września 2026 r.). Nie należy na jego podstawie zgadywać metod serwerowej obsługi śmierci i permadeath.

## Docelowe zachowanie

- Po śmierci w Expedition: odrodzenie w windzie, pełny ekwipunek bez upuszczania przedmiotów ani duplikacji.
- Po porażce całej wyprawy: brak permadeath, zachowanie zapisu ekspedycji i możliwość kontynuacji od ostatniego osiągniętego piętra.
- Fioletowy loot: akcja przetworzenia przedmiotu na miejscu, po której na ziemię wypadają **fizyczne Artifact Coins** zgodnie z realną wartością przedmiotu, bez natychmiastowego dopisywania żetonów do portfela.

### Potwierdzone wskazówki ze starego USMAP

- HeldenDataSingleton.ArtifactCoinActorClass — referencja do klasy fizycznego żetonu.
- HeldenPhysicsCoin.Money — struktura nagrody.
- HeldenMoney.Artifacts — ilość żetonów.
- HeldenCoinDispenser — istniejąca mechanika wydawania monet.

Przed implementacją przetworzenia należy zidentyfikować **funkcję gry**, która odpowiada za przyznawanie Artifact Coins z konkretnego lootu i niszczenie lootu. Sama klasa monety nie wystarczy do bezpiecznego przyznania waluty w multiplayer. Preferowana ścieżka: wykorzystać wbudowany mechanizm wydawania monet / grindera i jego replikację; jeżeli API nie pozwoli, przygotować atomową transakcję hosta z kontrolą duplikacji.

## Aktualizacja 2026-11-20 — mapowania otrzymane

Użytkownik przekazał poprawny USMAP o **automatycznej nazwie** `Helden-5.7.4-51494982+++UE5+Release-5.7-1c1a1497.usmap`, obok `UE4SS_ObjectDump.txt` i `UE4SS(1).log`. Log potwierdza `Mappings Generation Completed Successfully!`.

Nowy zrzut zawiera `EHeldenGameMode.Expedition`, `HeldenGameState.HasFailedExpedition`, `HeldenPlayerController.RespawnCharacter_Server`, `HeldenSaveGame.MetaData.bHasFailed` i klasy fizycznych Artifact Coins. **Nie trzeba ponownie generować zrzutu.** Szczegółowe wyniki w [docs/mapping-analysis-2026-11-20.md](docs/mapping-analysis-2026-11-20.md).

**Nadal do weryfikacji:** kolejność serwerowych zdarzeń śmierci i zapisu oraz bezpieczne wystawianie monet w trakcie wyprawy. To nie jest jeszcze wersja moda zmieniająca rozgrywkę.

## Zdobądź aktualną mapę za pomocą UE4SS

W repo znajduje się tymczasowy, **tylko diagnostyczny** mod ExpeditionMapper.

1. Pobierz paczkę ExpeditionMapper z GitHub Actions i rozpakuj do katalogu Grain Rot/Helden/Binaries/Win64/.
2. Uruchom zaktualizowaną grę i wejdź **do trybu Expedition**, najlepiej do windy, aby załadować związane z nim klasy.
3. Wciśnij **F8**: UE4SS wykona DumpUSMAP i zapisze plik **Helden-*.usmap** (nazwa zależy od buildu; NIE `Mappings.usmap`).
4. Wciśnij **F9**: UE4SS wykona DumpAllObjects i zapisze UE4SS_ObjectDump.txt (lista załadowanych obiektów i funkcji).
5. W katalogu Grain Rot/Helden/Binaries/Win64/ue4ss/ lub obok Helden-Win64-Shipping.exe znajdź oba pliki. Ścieżkę sprawdzisz też w UE4SS.log.
6. Prześlij oba pliki i UE4SS.log w rozmowie. Nie ma potrzeby dołączania plików gry ani całego pakietu UE4SS.

**Alternatywa bez helpera:** UE4SS standardowo ma klawisz Ctrl + Num6 do mapowań oraz Ctrl + J do zrzutu obiektów; w niestandardowych konfiguracjach skróty mogą być niedostępne.

Dumper działa wyłącznie na żądanie. Nie wywołuje modyfikacji zapisu ani aktorów gry. Tworzenie zrzutów może chwilowo zamrozić grę — wykonaj je w menu lub w bezpiecznej lokalizacji.

## Ograniczenia

Nie mam bezpośredniego dostępu do plików gry na komputerze użytkownika ani nie mogę uruchomić Grain Rot we własnym kontenerze. Nowe mapowania muszą pochodzić z aktualnie uruchomionego procesu lub z wiarygodnej publicznej kopii dla tej samej wersji. Zautomatyzowałem ich generowanie po uruchomieniu gry, ale **nie mogę wygenerować ich zdalnie** bez procesu gry.

Po otrzymaniu aktualnych mapowań następnym krokiem będzie identyfikacja natywnych funkcji serwera: koniec ekspedycji, odrodzenie, zapis ekwipunku, numery pięter i przetwarzanie artefaktów.
