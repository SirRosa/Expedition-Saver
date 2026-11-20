# Grain Rot — Expedition Saver

**v0.2.0-alpha — nowa wersja testowa, niezweryfikowana wewnątrz gry.** Reakcja na zgłoszenie: v0.1.0 nie odradzała gracza, nie odblokowywała windy po porażce i nie wydawała Artifact Coins. Tamtego działania **nie uznajemy za potwierdzone**.

Repozytorium zawiera osobny mod gameplay `ExpeditionSaver` oraz niezależny, diagnostyczny `ExpeditionMapper` (niewymagany przy normalnej grze).

## Funkcje v0.2.0

| Funkcja | Implementacja i ograniczenia |
|---|---|
| **Respawn w windzie** | Używa hooków `HeldenCharacter.Die_Auth` oraz `HeldenPlayerController.OnPlayerKilled`. Żądanie `RespawnCharacter_Server()` wysyła niezwłocznie po natywnej obsłudze śmierci (i ponawia, jeśli nie było nowego pawna). Po uzyskaniu nowej postaci przenosi ją do windy i odnawia zdrowie. Próbuje także po przejściu gry do EndScreen. **Silnik może odrzucić respawn podczas zakończonej ekspedycji — do weryfikacji w grze**. |
| **Cały ekwipunek** | Zachowuje referencje, klasę i dane itemów w chwili śmierci. Nie rusza sprzętu odtworzonego natywnie przez grę, przenosi ocalałe egzemplarze do windy, a zniszczone próbuje ponownie zespawnować jeden raz. **Rekreacja nie gwarantuje natywnego założenia do slotu ani trwałości po restarcie.** |
| **Ostatnie piętro i brak permadeath** | Zachowuje `DungeonLevel`, wyłącza flagi `bHasFailed` / `bExpeditionFailed`, przechwytuje `HasFailedExpedition`. Po powrocie windy na stację domową próbuje usunąć EndScreen/Failed i odblokować `HeldenElevatorMachine` przez `SetCanBeInteracted_Auth` oraz `OnDungeonRunStateChanged`. Bez samoczynnego zjeżdżania windy. **Nie jest to jeszcze potwierdzone w prawdziwej sesji multiplayer.** |
| **Zniszczenie lootu = fizyczne monety** | **Nie ma F7 ani innego skrótu.** `HeldenPhysicsActor.OnHealthModifed` i `PlayDestructionEffect_Mulitcast` wykrywają zniszczenie (np. młotkiem). Dla obiektu pochodzącego z lochu pobierają jego rzeczywiste wartości złota i Artifact Coins i upuszczają fizyczne monety. Domyślny drop scrapu pozostaje bez zmian; mod nie dodaje go ponownie. |
| **Integracja z QOL** | Odczyt następuje **w chwili zniszczenia** z `GetInspectData().Value` albo zmodyfikowanych wierszy `ConstructAssetDataTable` i `PhysActorDataTable`. Jeżeli QOL zdążył zmienić nagrody, są odczytywane po zmianach, **bez kolejnego mnożenia**. |

Wypłata jest wykonywana raz na obiekt w trakcie jednej sesji. Jeśli nie uda się potwierdzić spawnu fizycznej monety, mod zapisuje ostrzeżenie w logu. Unika niszczenia oryginalnego przedmiotu własnym kodem i pomija oznaczone przedmioty questowe.

## Instalacja

1. **Utwórz kopię zapisu gry.** Szczególnie ważne, ponieważ v0.2 zmienia stan zakończenia ekspedycji.
2. Pobierz `ExpeditionSaver-v0.2.0-alpha.zip` z ostatniego udanego GitHub Actions.
3. Wypakuj do `Grain Rot\Helden\Binaries\Win64\`. Powinno powstać `ue4ss\Mods\ExpeditionSaver\Scripts\main.lua` oraz `enabled.txt`.
4. Zainstaluj **wyłącznie na hoście**, nie u klientów.
5. Wyłącz stary Depth Keeper do testu mechaniki pięter. Jeżeli masz także QOL, pozostaw go włączonego do testów mnożników, **ale wyłącz w nim `InsuranceOnWipe`**, żeby oba mody nie odtwarzały tych samych przedmiotów po porażce. W QOL v0.1 ta opcja jest na początku `main.lua` w `CFG`.

## Minimalny test i logowanie

1. Uruchom Expedition i upewnij się, że w `ue4ss\UE4SS.log` jest wpis `[ExpeditionSaver] v0.2.0-alpha loaded`.
2. W logu szukaj `HOOK ACTIVE` dla `Die_Auth`, `OnPlayerKilled`, `PlayDestructionEffect_Mulitcast` i `HasFailedExpedition`. `HOOK NOT READY` oznacza brak rejestracji — mod będzie próbować ponownie po załadowaniu mapy.
3. Zniszcz zwykły przedmiot lootu młotkiem i sprawdź, czy wypada **fizyczne złoto**. Wtedy zniszcz fioletowy przedmiot (nie questowy) i sprawdź **Artifact Coins**. Szukaj wpisów `DESTRUCTION queued` oraz `DROP artifacts` / `DROP gold`.
4. Na **testowym zapisie** z niecennym ekwipunkiem doprowadź do śmierci. Wpisy `DEATH HOOK`, `IMMEDIATE RESPAWN`, `NEWPAWN`, `EQUIPMENT` pozwolą ustalić, co wykonał serwer.
5. Po pełnym wipe wróć do windy: powinien pojawić się wpis `RECOVERY run=3 -> 0` i `machine=unlocked`. Sprawdź faktyczny zjazd, nie tylko numer na wyświetlaczu.

**Jeżeli cokolwiek nadal nie działa, prześlij pełen nowy `UE4SS.log` z v0.2.** Samo przejście testów CI nie potwierdza, że funkcje silnika są wywoływane w tej kolejności. W szczególności UI, replikacja sieciowa, serializacja i blokada ekspedycji wymagają rzeczywistych prób.

## Testy i źródła

- 26 przypadków w `tests/test_expedition.lua`, oraz 2 testy generatora mapowań. Wszystkie dotyczą **symulowanego** API UE4SS.
- Bazowe mapowanie: `Helden-5.7.4-51494982+++UE5+Release-5.7-1c1a1497.usmap` oraz `UE4SS_ObjectDump.txt` dostarczone 20 listopada 2026.
- [Raport o typach i hookach](docs/mapping-analysis-2026-11-20.md).
