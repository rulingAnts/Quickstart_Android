# XML Format Fix Summary

## Problem Identified

The app was using an incorrect XML format that did not match the actual QWOM data source. The issues were:

### Encoding Issues
- **Character Encoding**: Real QWOM data uses UTF-16 (LE) encoding
- **Line Endings**: Real QWOM data uses CRLF (Windows-style) line endings
- The sample test data was ASCII with LF endings

### XML Structure Issues
- **Root Element**: 
  - ❌ Code used: `<Wordlist>`
  - ✅ Actual format: `<phon_data>`
  
- **Row Elements**:
  - ❌ Code used: `<Entry>`
  - ✅ Actual format: `<data_form>`

- **Image Field**:
  - ❌ Code used: `<Picture>`
  - ✅ Actual format: `<Image_File>`

## Changes Made

### 1. XML Service (`lib/services/xml_service.dart`)

#### Import Parser
- Changed element lookup from `Entry` to `data_form`
- Added support for `Image_File` field (primary) with fallback to `Picture` (for compatibility)
- Updated comments to reflect actual Dekereke format

#### Export Generator
- Changed root element from `<Wordlist>` to `<phon_data>`
- Changed row elements from `<Entry>` to `<data_form>`
- Changed image field from `<Picture>` to `<Image_File>`
- Added CRLF line ending conversion (`\n` → `\r\n`)

### 2. Test Data (`test_data/sample_wordlist.xml`)
- Converted to UTF-16 LE encoding
- Added CRLF line endings
- Updated structure to use `<phon_data>` and `<data_form>`
- Updated to use `<Image_File>` instead of `<Picture>`
- Added format documentation in XML comments

### 3. Documentation (`FLUTTER_README.md`)
- Updated XML format examples to show correct structure
- Added format notes explaining:
  - UTF-16 encoding with CRLF line endings
  - Root element: `<phon_data>`
  - Row elements: `<data_form>`
  - Image field: `<Image_File>` (with legacy `<Picture>` support)

### 4. Tests (`test/xml_service_test.dart`)
- Created comprehensive tests for XML export
- Validates correct element names are used
- Verifies CRLF line endings in output
- Ensures old format elements are NOT present
- Tests optional field handling

## Verification

The changes were verified against the actual QWOM data source:
- Repository: https://github.com/rulingAnts/QWOM_Data
- File: QWOM2025-08.xml (987 entries)
- Format confirmed:
  - Encoding: UTF-16 LE with CRLF
  - Structure: `<phon_data>` → `<data_form>` elements
  - Fields: `<Reference>`, `<Gloss>`, `<Image_File>`, `<SoundFile>`, etc.

## Backward Compatibility

The import parser includes fallback support:
- Tries `<Image_File>` first (new format)
- Falls back to `<Picture>` if `<Image_File>` not found (old format)

This ensures the app can still import files using the old `<Picture>` element while preferring the correct `<Image_File>` format.

## Impact

### Import Functionality
✅ Can now successfully import actual QWOM data files
✅ Correctly parses UTF-16 encoded files
✅ Handles CRLF line endings properly

### Export Functionality  
✅ Exports use correct element names matching QWOM format
✅ Output uses UTF-16 encoding (already implemented)
✅ Output uses CRLF line endings (newly added)
✅ Compatible with Dekereke and other tools expecting this format

### Testing
✅ Sample test data now matches real data format
✅ Tests validate the correct format is used
✅ No breaking changes to the data model or database
