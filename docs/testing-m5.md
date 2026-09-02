# M5 — checklista testów na urządzeniu (kryteria akceptacji)

Automatyczne testy nie pokryją integracji z RetroArchem, wielogigabajtowych plików
ani zrywania sieci — te punkty przechodzi się ręcznie na fizycznym telefonie
podłączonym do realnego NAS-a.

## Bramki automatyczne

| Bramka | Komenda | Wynik |
|---|---|---|
| Testy jednostkowe + widgetowe aplikacji | `cd app && flutter test` | PASS (124 testy) |
| Pokrycie aplikacji 100% | `./scripts/check_coverage_app.sh` | PASS (827/827 linii) |
| E2E backendu | `./scripts/e2e_backend.sh` | PASS (12 testów) |
| E2E aplikacji | `E2E_SERVER=http://<ip-hosta>:8800 ./scripts/e2e_app.sh` | do uruchomienia na urządzeniu |

## Checklista ręczna

Wypełnij kolumnę „Wynik" (PASS/FAIL) i notatkę. FAIL-e naprawiamy przed
zamknięciem milestone'u.

| # | Scenariusz | Jak sprawdzić | Wynik | Notatka |
|---|---|---|---|---|
| 1 | Mała gra (kartridż) | Pobierz → plik ląduje w `<base>/<system>/`, badge „zainstalowana", RetroArch widzi grę i ją uruchamia | | |
| 2 | Duża gra (kilka GB, obraz płyty) | Start → pauza → wznowienie → wyłącz Wi-Fi w trakcie → przywróć sieć → retry/wznowienie → rozmiar pliku zgodny z manifestem | | |
| 3 | Gra wieloplikowa (cue/bin albo multi-disc) | Wszystkie pliki pobrane, na ekranie „Pobierania" **jedna** pozycja | | |
| 4 | Switch | Domyślna selekcja = base + najnowszy update + DLC; po pobraniu samego base badge pokazuje „dostępna aktualizacja" | | |
| 5 | Usuwanie | Pliki ROM znikają, katalogi `saves/` i `states/` RetroArcha **nietknięte** (sprawdź ręcznie), badge wraca do „niezainstalowana" | | |
| 6 | Zabicie aplikacji w trakcie pobierania | Pobieranie leci dalej w tle (powiadomienie z paskiem postępu), po powrocie do aplikacji stan jest poprawny | | |

## Notatki

(miejsce na obserwacje z biegu — np. czasy pobierania, zachowanie przy słabym Wi-Fi)
