# Droplet — Android app

Flutter client for the Droplet server. Overview and deployment: [`../README.md`](../README.md).

```bash
flutter pub get
flutter run                        # on the emulator the host server is http://10.0.2.2:8000
flutter build apk --release
../scripts/check_coverage_app.sh   # gate: 100% line coverage
```
