import 'package:flutter_test/flutter_test.dart';
import 'package:wordlist_elicitation/models/wordlist_entry.dart';
import 'package:wordlist_elicitation/services/xml_service.dart';

void main() {
  group('XmlImportService', () {
    late XmlImportService xmlService;

    setUp(() {
      xmlService = XmlImportService();
    });

    test('should generate XML with correct Dekereke format structure', () async {
      // Arrange
      final entries = [
        WordlistEntry(
          id: 1,
          reference: '0001',
          gloss: 'body',
          localTranscription: 'bɔdi',
          audioFilename: '0001body.wav',
          pictureFilename: '0001body.png',
        ),
        WordlistEntry(
          id: 2,
          reference: '0002',
          gloss: 'head',
          audioFilename: '0002head.wav',
        ),
      ];

      // Act
      final xmlString = await xmlService.exportDekerekeXml(entries);

      // Assert
      expect(xmlString, contains('<?xml version="1.0" encoding="UTF-16"?>'));
      expect(xmlString, contains('<phon_data>'));
      expect(xmlString, contains('</phon_data>'));
      expect(xmlString, contains('<data_form>'));
      expect(xmlString, contains('</data_form>'));
      expect(xmlString, contains('<Reference>0001</Reference>'));
      expect(xmlString, contains('<Gloss>body</Gloss>'));
      expect(xmlString, contains('<LocalWord>bɔdi</LocalWord>'));
      expect(xmlString, contains('<SoundFile>0001body.wav</SoundFile>'));
      expect(xmlString, contains('<Image_File>0001body.png</Image_File>'));
      
      // Verify CRLF line endings
      expect(xmlString, contains('\r\n'));
      
      // Verify old format elements are NOT present
      expect(xmlString, isNot(contains('<Wordlist>')));
      expect(xmlString, isNot(contains('<Entry>')));
      expect(xmlString, isNot(contains('<Picture>'))); // Only Image_File should be used in export
    });

    test('should export without optional fields when not present', () async {
      // Arrange
      final entries = [
        WordlistEntry(
          id: 1,
          reference: '0001',
          gloss: 'test',
        ),
      ];

      // Act
      final xmlString = await xmlService.exportDekerekeXml(entries);

      // Assert
      expect(xmlString, contains('<phon_data>'));
      expect(xmlString, contains('<data_form>'));
      expect(xmlString, contains('<Reference>0001</Reference>'));
      expect(xmlString, contains('<Gloss>test</Gloss>'));
      expect(xmlString, isNot(contains('<LocalWord>')));
      expect(xmlString, isNot(contains('<SoundFile>')));
      expect(xmlString, isNot(contains('<Image_File>')));
    });
  });
}
