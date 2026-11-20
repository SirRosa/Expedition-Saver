# Grain Rot — Expedition Saver

## v0.4.0-alpha — przebudowa na podstawie rzeczywistego logu

**Uwaga:** jest to testowa wersja gameplay, a nie potwierdzona poprawka działająca w grze. Poprzednie v0.1–v0.3 nie zrealizowały oczekiwanych funkcji u użytkownika. Zmiany v0.4 są oparte na konkretnych zdarzeniach z pliku `UE4SS(2).log` i na nowych mapowaniach.

### Co udowodnił log v0.3

- Wszystkie hooki zostały zarejestrowane, host miał `GameModeType=1` i rzeczywisty tryb Expedition.
- **0** wywołań `Die_Auth` i `OnPlayerKilled` podczas śmierci gracza. To była zasadnicza przyczyna braku respawnu.
- **369** zdarzeń niszczenia. Kod odnotował `DROP gold=39` za `Radiator_01_C`, ale nie sprawdzał, czy moneta jest widoczna lub możliwa do podniesienia.
- Gra rzeczywiście zakończyła ekspedycję (`EndDungeonRunSequence_Multicast`); reset `GameState` nie otworzył windy.
- W zrzucie obiektów jest osobny **`BP_ExpeditionFailed_Actor_C`**, zawierający `bFailedExpedition`, `Box`, `SM_SM_Door_Lock`, `UpdateCollisionSate`.
- W logu ładowały się **równolegle** Expedition Saver, GrainRotDepthKeeper i GrainRotQOL. QOL samodzielnie odtworzył jeden przedmiot po porażce.

[Pełna analiza logu v0.3](docs/live-session-audit-2026-11-20.md)

### Zmiany v0.4

| Funkcja | Nowa metoda |
|---|---|
| Respawn w windzie | Co 300 ms sprawdza `HeldenPlayerController`, aktywnego pawna, `SoulCharacter`, `LastPlayerChar`, stan `ECharacterState.Dead=1` i `CurrentHealth`. Zapisuje migawkę wyposażenia przed śmiercią. Dodatkowo nasłuchuje `OnRep_CharacterState`. |
| Awaryjne odrodzenie | Najpierw trzy próby natywnego `RespawnCharacter_Server`. Jeśli silnik ich nie przyjmie, próba wskrzeszenia i przejęcia **istniejącego**, nadal ważnego aktora gracza, z przemieszczeniem do windy. |
| Koniec permadeath i ponowny zjazd | Oprócz flag `GameState` naprawia właściwą maszynę `lift.ElevatorMachine` i jej `bUseInteractRequirement`. Wyłącza fizyczną blokadę `BP_ExpeditionFailed_Actor_C`: flagę, kolizje komponentów i widoczność zamka. Nie wymusza automatycznego zjazdu. |
| Nagroda po zniszczeniu | Nie używa F7. Fizyczne złoto i Artifact Coins pojawiają się ~130 jednostek nad zniszczonym obiektem, po czym kod próbuje włączyć replikację, widoczność i kolizję. Loguje klasę, współrzędne i wynik prób. |
| Współpraca z QOL | Płatności z bieżącego `GetInspectData` lub aktualnych wierszy DataTable (po modyfikacji QOL). W przypadku `Value=0` również sprawdza wiersz tabeli, zamiast natychmiast kończyć. Nie mnoży ponownie wartości. |
| Ochrona ekwipunku | Zachowuje referencje i migawkę przed śmiercią; **domyślnie wyłącza klonowanie zniszczonych przedmiotów**, aby nie dublować ubezpieczenia QOL. |

## Instalacja

1. **Zrób kopię zapisu** przed testami, szczególnie ze względu na eksperymentalne wskrzeszanie postaci.
2. Pobierz `ExpeditionSaver-v0.4.0-alpha.zip` z [GitHub Actions](https://github.com/SirRosa/Expedition-Saver/actions).
3. Usuń starą zawartość `Grain Rot\Helden\Binaries\Win64\ue4ss\Mods\ExpeditionSaver`; rozpakuj ZIP do `Grain Rot\Helden\Binaries\Win64\`.
4. Instalacja **tylko u hosta**. Pozostaw włączony mod QOL do sprawdzenia mnożników, ale wyłącz w nim `InsuranceOnWipe` na czas testu odzyskiwania przedmiotów. **Całkowicie wyłącz Depth Keeper**, by oba mody nie modyfikowały stanu tej samej ekspedycji.
5. Sprawdź w logu `[ExpeditionSaver] v0.4.0-alpha loaded`.

## Kolejność testów

1. Najpierw rozbij zwykły i fioletowy przedmiot podczas aktywnej wyprawy. Sprawdź, czy fizyczne monety naprawdę da się zobaczyć i podnieść. Potrzebne logi: `DESTRUCTION`, `COIN PHYSICAL`, `DROP gold`, `DROP artifacts`.
2. Na testowym zapisie z tanim wyposażeniem umrzyj. Oczekiwane wpisy: `PLAYER STATE`, `PLAYER DEATH queued`, `NATIVE RESPAWN`, ewentualnie `REVIVE FALLBACK`.
3. Po pełnym wipe sprawdź fizyczne drzwi windy. Log `FAILURE DOOR` poda stan blokady, a `RECOVERY` pokaże stan runu. Sprawdź prawdziwy zjazd — nie tylko reset licznika.

**Jeżeli funkcje nie zadziałają, potrzebny będzie nowy `UE4SS.log` z v0.4.** Mamy już log rzeczywistej sesji v0.3, więc dalsze poprawki będą dotyczyć niepotwierdzonych mechanizmów, a nie ponownego zgadywania.

## Ograniczenia techniczne

- Wskrzeszenie starego pawna działa tylko, jeśli silnik go jeszcze nie zniszczył; nie ma możliwości odtworzenia całego stanu klienta z samego USMAP.
- Wyłączenie kolizji `BP_ExpeditionFailed_Actor_C` nie gwarantuje, że natywny serwer rozpocznie nowy przejazd. To osobna weryfikacja.
- `COIN PHYSICAL` dowodzi tylko odczytanej pozycji i prób konfiguracji; nie gwarantuje poprawnej replikacji ani możliwości podniesienia, dopóki nie zostanie to przetestowane w grze.
- Przechwycenie i odtworzenie przedmiotów jest obecnie niepełne, jeśli silnik niszczy oryginalny aktor. Nacisk v0.4: działający respawn, fizyczny zjazd oraz widoczne monety bez duplikacji.
- Automatyczne testy GitHub Actions używają symulowanego API. **Nie są dowodem działania w Grain Rot**.

## Dokumentacja

[Analiza USMAP](docs/mapping-analysis-2026-11-20.md) · [Analiza faktycznego logu v0.3](docs/live-session-audit-2026-11-20.md)
