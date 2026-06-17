# CYD Flock-You Integration

This branch prepares DeFlock to consume detections from the CYD Flock-You firmware.

## User Flow

1. User powers the CYD from a battery pack, vehicle USB power, or another stable USB power source.
2. DeFlock scans for the CYD Bluetooth LE UART device named `CYD-Flock-You`.
3. DeFlock connects to the Nordic UART service and sends `FYHELLO`.
3. CYD replies with `event:"pair_status"` and repeats status every 5 seconds.
4. DeFlock streams phone GPS once per second using:

```text
FYGPS,<lat>,<lon>,<accuracy_m>,<speed_kmph>,<course_deg>,<sats>,<hdop>
```

5. CYD emits `event:"detection"` JSON when the WiFi detector sees a target signature.
6. DeFlock checks cached/visible surveillance nodes within 250 feet / 76.2 meters.
7. If no nearby camera is documented, DeFlock creates a pending CYD candidate.
8. The review UI must require the user to drag the marker from the road to the camera's actual roadside position.
9. The review UI must require a manually-set camera direction. Vehicle travel direction is not used.
10. Approval creates a normal DeFlock pending upload; OSM submission remains user-approved.

## Code Added

- `lib/models/cyd_flock_detection.dart`
  - parses `pair_status` and `detection` JSON lines
- `lib/services/cyd_candidate_service.dart`
  - applies the 250-foot duplicate suppression rule
  - creates review candidates only when the phone GPS is present and no nearby camera is documented
- `lib/state/cyd_candidate_state.dart`
  - tracks pair status, parse failures, ignored detections, and pending review candidates
  - suppresses duplicates against both cached OSM nodes and already-pending CYD candidates
- `lib/services/cyd_usb_serial_service.dart`
  - kept as a bench/debug fallback for USB serial
- `lib/services/cyd_bluetooth_service.dart`
  - scans for the `CYD-Flock-You` Bluetooth LE peripheral
  - connects to the Nordic UART service
  - sends `FYHELLO` and formats `FYGPS` lines
  - exposes newline-delimited CYD output as a Dart stream
- `AppState`
  - exposes CYD pending candidate counts and review helpers
  - connects/disconnects the CYD Bluetooth service
  - ingests serial lines into the candidate queue
  - streams phone GPS updates to CYD while connected
  - converts a CYD candidate into the existing add-node flow
- `AddNodeSheet`
  - disables submission for CYD-origin sessions until the marker is moved off the original phone GPS point
- `HomeScreen`
  - adds a CYD Bluetooth connect/disconnect button
  - shows a review button when CYD candidates are pending
  - opens the standard visual map-based add flow centered on the detected location
- `MapView` / `GpsController`
  - forwards live phone GPS updates to the paired CYD as `FYGPS`

## Still Needed

- paired-device status panel
- richer candidate list UI when multiple detections are queued
- optional cleanup of the old USB serial fallback after Bluetooth field testing

## Local Verification

Completed on 2026-06-17 with Flutter 3.44.2, Dart 3.12.2, OpenJDK 17, and Android SDK 36:

```text
flutter pub get
dart run flutter_native_splash:create
dart run flutter_launcher_icons
flutter analyze
flutter test
flutter build apk --debug
```

The debug APK builds at `build/app/outputs/flutter-apk/app-debug.apk`.

Bluetooth field verification on 2026-06-17:

- CYD firmware flashed with BLE UART support.
- Android debug APK installed on the Moto G Stylus.
- DeFlock connected to the CYD over Bluetooth LE after the failed phone-powered OTG path.
- Android GATT writes to the CYD succeeded.
- CYD serial status reported `ble_uart` in `features` and `gps:true` after DeFlock streamed phone GPS.
- The app includes a connected-only test button that sends `FYSIM` so the CYD can emit a synthetic detection for indoor review-flow testing.
