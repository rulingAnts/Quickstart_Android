import 'package:flutter_test/flutter_test.dart';
import 'package:wordlist_elicitation/models/wordlist_entry.dart';

void main() {
  test('probe copyWith semantics', () {
    final incoming = WordlistEntry(
      reference: '0001',
      gloss: 'body',
      localTranscription: 'bɔdi',
      isCompleted: true,
    );
    final current = WordlistEntry(
      id: 1,
      reference: '0001',
      gloss: 'body',
      isCompleted: false,
    );
    final merged = incoming.copyWith(
      id: current.id,
      localTranscription: current.localTranscription,
      audioFilename: current.audioFilename,
      recordedAt: current.recordedAt,
      isCompleted: current.isCompleted,
    );
    // ignore: avoid_print
    print('PROBE merged.isCompleted=${merged.isCompleted} '
        'localTranscription=${merged.localTranscription} map=${merged.toMap()}');
  });
}
