# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Fixed - Make the app actually work (2026-07)
- **XML import rewritten for the real Dekereke format.** The importer now
  reads the actual QWOM data file: UTF-16 little-endian encoding (with BOM
  detection for UTF-16 LE/BE and UTF-8) and the `<phon_data>/<data_form>`
  record structure. Previously the app expected a `<Wordlist>/<Entry>`
  structure that real data files do not use, and read UTF-16 files as
  UTF-8, so imports of real data failed entirely. The simplified structure
  is still accepted for test files.
- **Duplicate/failed inserts fixed.** Entries were inserted with an explicit
  `id: 0` for every row, breaking SQLite auto-increment. Ids are now
  auto-assigned, references are enforced UNIQUE at the schema level
  (v2 migration included), imports run in a single transaction, and
  duplicate references within a file are skipped with a report.
- **Compile error fixed.** The export service referenced a nonexistent
  `utf16` codec; export now writes real UTF-16 LE bytes with BOM.
- **Export ZIP layout fixed.** Contents are no longer nested inside an
  `export_temp/` folder; stale export archives are cleaned up; the consent
  log is always included.
- **Elicitation session resume.** Revisiting a completed word now shows its
  saved transcription and recording (previously fields were blank);
  sessions resume at the first incomplete word; recordings in progress are
  stopped on save and discarded on navigation.
- **Recording filenames.** Recordings use the wordlist-assigned
  `<SoundFile>` name (e.g. `0002skin.wav`), with sanitized fallback names
  for glosses containing spaces or punctuation.
- **Android project made buildable.** The android/ scaffold was missing the
  Gradle wrapper, resources, and launch themes; it has been regenerated
  (minSdk 23 for the audio recorder) and CI now builds APK artifacts.

### Added
- Consent screen (written + optional verbal recording) gating elicitation,
  with persistent consent log — an MVP ethics requirement.
- Merge-on-import option that updates the wordlist while preserving
  collected transcriptions and recordings.
- Indonesian and Tok Pisin gloss display on the elicitation screen.
- Picture display when researcher-supplied images exist under
  `<app documents>/pictures/`.
- Comprehensive test suite (XML parsing/round-trip, UTF-16 handling,
  database migration, duplicate prevention, provider logic, widget smoke
  tests) runnable headless in CI.
- GitHub Actions workflow: analyze, test, and APK artifact builds.

### Planned Features
- LIFT XML export format support
- Cloud sync capabilities
- Custom font integration (Charis SIL, Doulos SIL)
- Enhanced keyboard support for IPA input
- Data validation and quality checks
- Batch import/export operations
- Configurable consent text (per-language, via bundling wizard)

## [1.0.0] - 2024-10-12

### Added - Initial Flutter Implementation

#### Core Features (MVP)
- **Data Management**
  - XML import functionality for Dekereke format
  - SQLite database for local storage using `sqflite`
  - Session tracking with progress indicators
  - ZIP export with XML, audio, and consent logs
  
- **User Interface**
  - Home screen with progress statistics
  - Import screen with file picker
  - Elicitation screen with recording and transcription
  - Export screen with share functionality
  - High-contrast, accessibility-focused design
  - Localization framework ready for multiple languages

- **Audio Recording**
  - WAV format audio capture
  - Instant playback capability
  - Proper file naming: `{reference}{gloss}.wav`
  - Permission handling for microphone access

- **Data Models**
  - `WordlistEntry` model with full serialization
  - `ConsentRecord` model for ethical data collection
  - Database schema for entries and consent logs

- **Services**
  - `DatabaseService` - SQLite CRUD operations
  - `XmlService` - Dekereke XML import/export
  - `AudioService` - Recording and playback
  - `ExportService` - ZIP archive creation

- **State Management**
  - Provider pattern implementation
  - `WordlistProvider` for app state
  - Reactive UI updates

#### Documentation
- `README.md` - Project overview and goals (existing)
- `FLUTTER_README.md` - Flutter implementation details
- `QUICKSTART.md` - Quick setup guide
- `DEVELOPMENT.md` - Comprehensive development guide
- `CONTRIBUTING.md` - Contribution guidelines
- `ARCHITECTURE.md` - System architecture overview
- `LICENSE` - AGPL-3.0 license (existing)

#### Testing
- Unit tests for data models
- Test data samples for development

#### Platform Support
- Android configuration with proper permissions
- Kotlin MainActivity implementation
- Gradle build scripts
- AndroidManifest.xml with required permissions

#### Development Tools
- Linting configuration (`analysis_options.yaml`)
- Flutter metadata (`.metadata`)
- Dart/Flutter `.gitignore` entries

### Technical Details

#### Dependencies
- `provider: ^6.1.1` - State management
- `sqflite: ^2.3.0` - SQLite database
- `xml: ^6.4.2` - XML parsing
- `record: ^5.0.4` - Audio recording
- `audioplayers: ^5.2.1` - Audio playback
- `file_picker: ^6.1.1` - File selection
- `archive: ^3.4.9` - ZIP creation
- `share_plus: ^7.2.1` - File sharing
- `permission_handler: ^11.1.0` - Permissions
- `path_provider: ^2.1.1` - File paths
- `intl: ^0.18.1` - Internationalization

#### Minimum Requirements
- Flutter SDK: 3.0.0+
- Android: API 21+ (Android 5.0+)
- Dart: 3.0.0+

### Notes

This is the initial Flutter implementation of the Comparative Wordlist Elicitation Tool. The codebase is licensed under AGPL-3.0. Wordlist data is licensed separately under CC BY-NC-SA 4.0 and is not bundled with the app.

#### Known Limitations
- Audio uses device default sample rate (not configurable to 16-bit WAV yet)
- Currently supports Dekereke XML format only
- No built-in consent screen UI (structure exists, UI pending)
- Images referenced in XML are not yet displayed in UI
- iOS platform not yet configured

#### Migration from Native Android
This Flutter implementation provides an alternative to the Kotlin/Jetpack Compose approach outlined in the main README. Both implementations follow the same functional requirements.

## Version History

### Version Numbering
- **Major (1.x.x)**: Breaking changes or major new features
- **Minor (x.1.x)**: New features, backwards compatible
- **Patch (x.x.1)**: Bug fixes, minor improvements

### Release Schedule
- MVP (1.0.0): Initial release with core features ✅
- Phase 2 (1.1.0): Consent UI, LIFT export, image display
- Phase 3 (1.2.0): Cloud sync, advanced features
- Future: Desktop/web support, advanced audio editing

---

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for how to contribute to this project.

## License

This project is licensed under the AGPL-3.0 License - see the [LICENSE](LICENSE) file for details.

Wordlist data is licensed under CC BY-NC-SA 4.0 (separate from app code).
