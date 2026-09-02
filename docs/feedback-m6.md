# M6 — runda feedbacku po tygodniu używania

Zamknięcie M6 (i całego MVP) zależy od realnego używania: przez ~tydzień notuj tu
każdą irytację i brak. Potem przechodzimy listę punkt po punkcie — każdy albo
naprawiamy w M6, albo świadomie odkładamy z decyzją zapisaną w tabeli.

## Jak zacząć

```bash
cd app && flutter build apk --release
# APK: app/build/app/outputs/flutter-apk/app-release.apk
```

Zainstaluj na telefonie (release, nie debug — inaczej wydajność i wygląd nie są
reprezentatywne).

## Stan bramek automatycznych w chwili wydania buildu

| Bramka | Wynik |
|---|---|
| `cd backend && pytest -v` | PASS — 117 testów, pokrycie 100% |
| `./scripts/e2e_backend.sh` | PASS — 12 testów |
| `cd app && flutter test` | PASS — 148 testów |
| `./scripts/check_coverage_app.sh` | PASS — 1002/1002 linii = 100% |
| `E2E_SERVER=... ./scripts/e2e_app.sh` | do uruchomienia na urządzeniu |

## Lista uwag

Dopisuj wiersze w trakcie tygodnia. Kolumnę „Decyzja" wypełniamy razem po
przeglądzie.

| # | Data | Co irytuje / czego brakuje | Ekran | Decyzja (naprawa / odłożone + dlaczego) | Status |
|---|---|---|---|---|---|
| 1 | | | | | |
| 2 | | | | | |
| 3 | | | | | |

## Kryterium zamknięcia

M6 jest zamknięte, gdy każdy wiersz ma decyzję, naprawy są wdrożone (z testem,
jeśli dotyczy logiki), a wszystkie bramki z tabeli wyżej — łącznie z e2e
aplikacji na urządzeniu — są zielone.
