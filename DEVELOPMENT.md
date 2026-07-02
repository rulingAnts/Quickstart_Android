# Flutter Development Guide

## Quick Start

### 1. Install Flutter

Download and install Flutter from: https://flutter.dev/docs/get-started/install

Or use version managers like:
- FVM (Flutter Version Management): https://fvm.app/
- asdf: https://github.com/asdf-vm/asdf

### 2. Set up Development Environment

#### Android Studio (Recommended)
1. Download from: https://developer.android.com/studio
2. Install Flutter and Dart plugins
3. Configure Android SDK

#### VS Code
1. Install VS Code: https://code.visualstudio.com/
2. Install Flutter extension
3. Install Dart extension

### 3. Verify Installation

```bash
flutter doctor
```

Fix any issues reported by Flutter Doctor.

### 4. Get Dependencies

```bash
cd /path/to/Quickstart_Android
flutter pub get
```

### 5. Run the App

#### On Android Emulator
```bash
# Start an emulator first, then:
flutter run
```

#### On Physical Device
1. Enable Developer Options and USB Debugging on your device
2. Connect via USB
3. Run: `flutter run`

## Development Workflow

### Running the App in Development
```bash
# Hot reload enabled
flutter run

# With specific device
flutter run -d <device-id>

# List available devices
flutter devices
```

### Building for Release

#### Android APK
```bash
# Build release APK
flutter build apk --release

# Build split APKs (smaller size)
flutter build apk --split-per-abi
```

#### Android App Bundle (for Play Store)
```bash
flutter build appbundle --release
```

### Testing

```bash
# Run all tests
flutter test

# Run with coverage
flutter test --coverage

# Run specific test file
flutter test test/models_test.dart
```

### Code Quality

```bash
# Analyze code
flutter analyze

# Format code
flutter format .

# Fix auto-fixable issues
dart fix --apply
```

## Project Structure Details

### Core Directories

- **`lib/`** - Main application code
  - **`models/`** - Data models (WordlistEntry, ConsentRecord)
  - **`providers/`** - State management (WordlistProvider)
  - **`screens/`** - UI screens (Home, Import, Elicitation, Export)
  - **`services/`** - Business logic (Database, XML, Audio, Export)
  - **`widgets/`** - Reusable UI components (currently empty, ready for custom widgets)
  - **`utils/`** - Utility functions and constants (ready for future use)

- **`test/`** - Unit and widget tests
- **`android/`** - Android-specific configuration
- **`ios/`** - iOS-specific configuration (not yet configured)

### Key Configuration Files

- **`pubspec.yaml`** - Dependencies and assets
- **`analysis_options.yaml`** - Linting rules
- **`android/app/build.gradle`** - Android build configuration
- **`android/app/src/main/AndroidManifest.xml`** - Android permissions and metadata

## Common Development Tasks

### Adding a New Dependency

1. Add to `pubspec.yaml`:
```yaml
dependencies:
  new_package: ^1.0.0
```

2. Get the package:
```bash
flutter pub get
```

### Adding a New Screen

1. Create file in `lib/screens/`: `new_screen.dart`
2. Define the widget class
3. Add navigation from existing screen
4. Update routes if using named routes

### Adding Localization

1. Create `.arb` files in `lib/l10n/`:
   - `app_en.arb` (English)
   - `app_es.arb` (Spanish)
   - etc.

2. Add translations:
```json
{
  "appTitle": "Wordlist Tool",
  "@appTitle": {
    "description": "Application title"
  }
}
```

3. Generate localization files:
```bash
flutter gen-l10n
```

4. Use in code:
```dart
import 'package:flutter_gen/gen_l10n/app_localizations.dart';

// In widget:
Text(AppLocalizations.of(context)!.appTitle)
```

### Working with Database

The app uses SQLite via `sqflite`. Database service is in `lib/services/database_service.dart`.

Example usage:
```dart
final db = DatabaseService.instance;
final entries = await db.getAllWordlistEntries();
await db.insertWordlistEntry(newEntry);
```

### Working with Audio

Audio service handles recording and playback:

```dart
final audioService = AudioService();

// Start recording
final filename = await audioService.startRecording(reference, gloss);

// Stop recording
await audioService.stopRecording();

// Play audio
final player = AudioPlayer();
await player.play(DeviceFileSource(filePath));
```

## Debugging

### Enable Debug Mode

```bash
flutter run --debug
```

### Flutter DevTools

```bash
# In another terminal while app is running
flutter pub global activate devtools
flutter pub global run devtools
```

Access at: http://localhost:9100

### Common Debug Commands

- **Hot Reload**: Press `r` in terminal or save file in IDE
- **Hot Restart**: Press `R` in terminal
- **Toggle Debug Paint**: Press `p`
- **Toggle Performance Overlay**: Press `P`

### Debugging Issues

#### Build Errors
```bash
# Clean build
flutter clean
flutter pub get
flutter run
```

#### Gradle Issues (Android)
```bash
cd android
./gradlew clean
cd ..
flutter clean
flutter run
```

#### Permission Issues
Check `android/app/src/main/AndroidManifest.xml` for required permissions.

## Performance Tips

1. **Use `const` constructors** where possible
2. **Avoid rebuilds** - use `const`, `keys`, and `Consumer` wisely
3. **Lazy loading** - load data as needed
4. **Image optimization** - compress and cache images
5. **Profile mode** - test performance:
   ```bash
   flutter run --profile
   ```

## Architecture Notes

### State Management (Provider)

The app uses Provider pattern for state management:

```dart
// Define provider
class WordlistProvider extends ChangeNotifier {
  void updateData() {
    // Update state
    notifyListeners();
  }
}

// Register in main.dart
MultiProvider(
  providers: [
    ChangeNotifierProvider(create: (_) => WordlistProvider()),
  ],
  child: MyApp(),
)

// Use in widget
Consumer<WordlistProvider>(
  builder: (context, provider, child) {
    return Text(provider.data);
  },
)
```

### Service Pattern

Services encapsulate business logic:
- `DatabaseService` - Data persistence
- `XmlService` - XML import/export
- `AudioService` - Audio recording/playback
- `ExportService` - Data export

### Clean Architecture

The app follows Clean Architecture principles:
1. **Models** - Pure data structures
2. **Services** - Business logic, external integrations
3. **Providers** - State management, UI state
4. **Screens** - UI presentation

## Platform-Specific Configuration

### Android

#### Minimum SDK Version
Set in `android/app/build.gradle.kts`:
```kotlin
minSdk = 23  // Android 6.0+, required by the `record` audio plugin
```

#### Permissions
Add to `AndroidManifest.xml`:
```xml
<uses-permission android:name="android.permission.RECORD_AUDIO"/>
```

#### Signing (for release)
1. Create keystore:
```bash
keytool -genkey -v -keystore ~/upload-keystore.jks -keyalg RSA -keysize 2048 -validity 10000 -alias upload
```

2. Create `android/key.properties`:
```properties
storePassword=<password>
keyPassword=<password>
keyAlias=upload
storeFile=<path-to-keystore>
```

3. Configure in `android/app/build.gradle`

### iOS (Future)
iOS configuration not yet implemented. Will require:
- Xcode installation
- CocoaPods setup
- iOS signing certificates
- Info.plist configuration

## Troubleshooting

### Issue: "Gradle build failed"
**Solution**: 
```bash
cd android
./gradlew clean
cd ..
flutter clean
flutter pub get
```

### Issue: "Package does not exist"
**Solution**:
```bash
flutter pub get
flutter pub upgrade
```

### Issue: "Android license not accepted"
**Solution**:
```bash
flutter doctor --android-licenses
```

### Issue: "Cannot find Flutter SDK"
**Solution**:
Set Flutter path in environment:
```bash
export PATH="$PATH:/path/to/flutter/bin"
```

## Resources

- **Flutter Documentation**: https://flutter.dev/docs
- **Dart Language Tour**: https://dart.dev/guides/language/language-tour
- **Flutter Cookbook**: https://flutter.dev/docs/cookbook
- **Provider Package**: https://pub.dev/packages/provider
- **sqflite Package**: https://pub.dev/packages/sqflite
- **Flutter Community**: https://flutter.dev/community

## Contributing to This Project

1. Read the main `README.md` for project goals
2. Check existing issues on GitHub
3. Follow the existing code style
4. Write tests for new features
5. Update documentation
6. Submit pull request

## Next Steps for Development

Priority features to implement:
1. Consent screen UI (verbal/written options)
2. LIFT XML export format
3. Image display for wordlist entries
4. Enhanced error handling
5. Offline capabilities
6. Data validation
7. Custom font integration (Charis SIL, Doulos SIL)
8. Cloud sync setup

See `FLUTTER_README.md` for more details on MVP features and roadmap.
