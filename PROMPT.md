# Ralph: zbuduj Droplet wg planów

Jesteś w pętli Ralph. Ten sam prompt dostajesz co iterację — postęp widzisz w plikach
i historii gita, nie w rozmowie.

## Zadanie

Zbuduj projekt Droplet, wykonując plany milestone'ów **w kolejności M0 → M6**:

- Spec: `docs/superpowers/specs/2026-09-01-droplet-design.md`
- Plany: `docs/superpowers/plans/2026-09-01-m0-*.md` … `2026-09-01-m6-*.md`

## Algorytm każdej iteracji

1. Znajdź **pierwszy nieodhaczony krok** (`- [ ]`) w najniższym nieukończonym
   milestone. Sprawdź `git log` i stan plików — nie rób drugi raz tego, co już jest.
2. Wykonaj TEN JEDEN task (wszystkie jego kroki) dokładnie wg planu: failing test →
   implementacja → testy zielone → commit. Nie wybiegaj naprzód.
3. Bramki przed odhaczeniem: backend `cd backend && pytest -v` (100% pokrycia);
   Flutter `flutter test` + `./scripts/check_coverage_app.sh`. Czerwone = napraw
   w tej iteracji, nie odhaczaj.
4. Po przejściu bramek: zamień `- [ ]` na `- [x]` przy wykonanych krokach w pliku
   planu i dołącz tę zmianę do commita zadania.
5. Jeśli krok wymaga człowieka lub sprzętu (akceptacja wyglądu, fizyczny telefon,
   realny NAS, tydzień feedbacku): NIE wykonuj go — dopisz go do `RALPH-STATUS.md`
   w sekcji "Czeka na Jana" (raz, bez duplikatów), odhacz jako `- [x] (odłożone
   na człowieka)` i idź dalej.
6. Jeśli utkniesz drugi raz na tym samym problemie: opisz go w `RALPH-STATUS.md`
   w sekcji "Blokery" i przejdź do następnego niezależnego kroku.

## Zasady

- Przestrzegaj Global Constraints z planu bieżącego milestone'u.
- Commit po każdym tasku, komunikaty po angielsku (`feat:`/`test:`/`chore:`).
- Żadnych skrótów w bramkach: nie wyłączaj testów, nie dopisuj wyłączeń pokrycia
  poza technicznymi już opisanymi w planach.
- Nie zmieniaj specu ani zakresu planów; rozjazd planu z rzeczywistością
  (np. inna nazwa API w bibliotece) rozwiąż minimalnie i odnotuj w `RALPH-STATUS.md`.

## Koniec

Gdy WSZYSTKIE kroki M0–M6 są odhaczone (wykonane albo jawnie odłożone na człowieka),
a bramki testowe przechodzą — wypisz dokładnie:

<promise>DROPLET GOTOWY</promise>
