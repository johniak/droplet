# Droplet — aplikacja Android

Klient Flutter dla serwera Droplet. Opis całości i wdrożenie: [`../README.md`](../README.md).

```bash
flutter pub get
flutter run                     # emulator: serwer na hoście to http://10.0.2.2:8000
flutter build apk --release
../scripts/check_coverage_app.sh   # bramka: 100% linii
```
