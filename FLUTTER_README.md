# Wordlist Elicitation Flutter App

This is the initial Flutter implementation of the Comparative Wordlist Elicitation Tool for linguistic fieldwork.

## Overview

This app is designed to assist linguists, fieldworkers, and community members in the systematic elicitation and documentation of minority languages through the collection of comparative wordlists.

## Features Implemented (MVP)

### ✅ Data Management
- **XML Import**: Import Dekereke XML wordlist files
- **Local Storage**: SQLite database for persistent storage using `sqflite`
- **Session Tracking**: Track progress through wordlist entries
- **Export**: Export collected data as ZIP archive containing:
  - Dekereke XML with transcriptions
  - Audio recordings (WAV format)
  - Consent log (JSON format)

### ✅ Elicitation Interface
- **Simple, Visual UI**: Large buttons and high-contrast design
- **Localization Support**: Framework ready for multiple languages
- **IPA Input**: Text fields compatible with IPA characters
- **Progress Tracking**: Visual progress indicators

### ✅ Audio Recording
- **High-Quality Recording**: WAV format audio capture
- **Easy Controls**: Large, recognizable recording button
- **Playback**: Instant audio review capability
- **Proper Naming**: Audio files named as `{reference}{gloss}.wav` (e.g., `0001body.wav`)

### ✅ Ethical Data Collection
- **Consent Records**: Database structure for consent logging
- **Export Integration**: Consent logs included in data exports

## Project Structure

```
lib/
├── main.dart                 # App entry point
├── models/                   # Data models
│   ├── wordlist_entry.dart
│   └── consent_record.dart
├── providers/                # State management (Provider pattern)
│   └── wordlist_provider.dart
├── screens/                  # UI screens
│   ├── home_screen.dart
│   ├── import_screen.dart
│   ├── elicitation_screen.dart
│   └── export_screen.dart
├── services/                 # Business logic
│   ├── database_service.dart
│   ├── xml_service.dart
│   ├── audio_service.dart
│   └── export_service.dart
└── widgets/                  # Reusable UI components
```

## Dependencies

Key packages used:
- **State Management**: `provider`
- **Database**: `sqflite` for SQLite
- **XML Parsing**: `xml`
- **Audio**: `record` for recording, `audioplayers` for playback
- **File Operations**: `file_picker`, `archive`, `share_plus`
- **Localization**: `flutter_localizations`, `intl`
- **Permissions**: `permission_handler`

## Getting Started

### Prerequisites
- Flutter SDK 3.0.0 or higher
- Android Studio or VS Code with Flutter extensions
- Android SDK (for Android builds)

### Installation

1. **Install Flutter dependencies**:
   ```bash
   flutter pub get
   ```

2. **Run the app**:
   ```bash
   flutter run
   ```

### Building for Android

```bash
flutter build apk --release
```

The APK will be generated at: `build/app/outputs/flutter-apk/app-release.apk`

## Usage

### 1. Import Wordlist
1. Launch the app
2. Tap "Import Wordlist"
3. Select a Dekereke XML file
4. Wait for import to complete

### 2. Elicitation
1. Tap "Start Elicitation" from home screen
2. For each word:
   - View the English gloss
   - Tap the microphone to record
   - Enter IPA transcription
   - Tap "Save & Next"

### 3. Export Data
1. Tap "Export Data" from home screen
2. Review summary statistics
3. Tap "Export as ZIP"
4. Share the exported file via "Share Export"

## Configuration

### Android Permissions
The app requires the following permissions (configured in `AndroidManifest.xml`):
- `RECORD_AUDIO`: For audio recording
- `READ_EXTERNAL_STORAGE`: For file access (Android < 13)
- `WRITE_EXTERNAL_STORAGE`: For file storage (Android < 13)
- `READ_MEDIA_AUDIO`: For media access (Android 13+)

### Localization
To add new languages:
1. Add locale to `supportedLocales` in `main.dart`
2. Create corresponding `.arb` files in `lib/l10n/`
3. Run `flutter gen-l10n`

## Architecture

The app follows Clean Architecture principles with:
- **Models**: Data structures
- **Services**: Business logic and external integrations
- **Providers**: State management using Provider pattern
- **Screens**: UI layer

## Data Flow

1. **Import**: XML → Parser → Database
2. **Elicitation**: UI → Provider → Database + Audio Files
3. **Export**: Database + Audio → ZIP Archive

## XML Format

### Dekereke XML Import Structure
```xml
<?xml version="1.0" encoding="utf-16"?>
<phon_data>
  <data_form>
    <Reference>0001</Reference>
    <Gloss>body</Gloss>
    <Image_File>0001body.png</Image_File>
  </data_form>
</phon_data>
```

**Format Notes:**
- Encoding: UTF-16 with CRLF line endings
- Root element: `<phon_data>`
- Row elements: `<data_form>`
- Image field: `<Image_File>` (also supports legacy `<Picture>` for compatibility)

### Dekereke XML Export Structure
```xml
<?xml version="1.0" encoding="utf-16"?>
<phon_data>
  <data_form>
    <Reference>0001</Reference>
    <Gloss>body</Gloss>
    <LocalWord>IPA transcription</LocalWord>
    <SoundFile>0001body.wav</SoundFile>
    <Image_File>0001body.png</Image_File>
  </data_form>
</phon_data>
```

## Future Enhancements

### Planned Features (Phase 2+)
- [ ] Consent screen UI for verbal/written consent
- [ ] LIFT XML export format
- [ ] Image display for wordlist entries
- [ ] Cloud sync capabilities
- [ ] Custom font integration (Charis SIL, Doulos SIL)
- [ ] Enhanced keyboard support (Keyman integration)
- [ ] Offline-first architecture improvements
- [ ] Data validation and quality checks

## License

This code is licensed under **AGPL-3.0**. See the LICENSE file in the repository root for details.

**Important**: The wordlist data used by this app is licensed separately under CC BY-NC-SA 4.0. The app does not bundle any wordlist data.

## Contributing

Contributions are welcome! Please:
1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Submit a pull request

All contributions must be licensed under AGPL-3.0 or a compatible license.

## Development Notes

### Known Limitations
- Audio recording uses device default sample rate
- Currently supports Dekereke XML format only
- No built-in consent screen (manual consent logging required)
- Images referenced in XML are not yet displayed

### Testing
To run tests:
```bash
flutter test
```

### Code Style
The project uses the default Flutter lints. Run:
```bash
flutter analyze
```

## Support

For issues, feature requests, or questions:
- Open an issue on the GitHub repository
- Check existing issues for similar problems
- Review the main project README for architectural guidance

## Attribution

This implementation follows the project goals and technical requirements outlined in the main repository README, which was collaboratively authored by Seth Johnston via conversation with Gemini (Google).
