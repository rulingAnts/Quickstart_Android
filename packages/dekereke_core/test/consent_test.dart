import 'dart:convert';
import 'dart:typed_data';

import 'package:dekereke_core/dekereke_core.dart';
import 'package:test/test.dart';

ConsentReceipt ceremony({
  String id = 'cer-001',
  String? prev,
  String taskId = 'task-001',
  String speakerName = 'Yohanis',
}) =>
    ConsentReceipt.build(
      id: id,
      kind: ConsentReceiptKind.ceremony,
      prevReceiptSha256: prev,
      taskId: taskId,
      baseCheckpointId: 'checkpoint-42',
      scopeStatement: 'The words you are about to record in this task.',
      promptModes: const [ConsentAskMode.audio],
      promptMessage: '',
      promptAudioFile: 'prompt-abcd1234.wav',
      promptAudioSha256: 'a' * 64,
      playbackCompleted: true,
      playCount: 1,
      responseTypes: const [ConsentConfirmMode.record],
      assentFile: 'assent-$id.wav',
      assentSha256: 'b' * 64,
      speakerName: speakerName,
      timestampIso: '2026-07-03T08:00:00Z',
      timestampLocal: '2026-07-03 17:00',
      timezone: 'Asia/Jayapura',
      deviceId: 'device-1',
      appVersion: '1.0.0',
      platform: 'android',
    );

void main() {
  group('ConsentConfig', () {
    test('empty config is disabled and skips validation', () {
      const config = ConsentConfig();
      expect(config.enabled, isFalse);
      expect(config.validate(), isEmpty);
    });

    test('round-trips through JSON with unknown keys preserved', () {
      final config = ConsentConfig.fromJson({
        'ask': ['text', 'audio'],
        'confirm': ['record', 'signature'],
        'message': 'May we record you?',
        'audioFile': 'prompt-x.wav',
        'scopeStatement': 'These words.',
        'speakerName': 'required',
        'futureKey': {'nested': true},
      });
      expect(config.ask, [ConsentAskMode.text, ConsentAskMode.audio]);
      expect(config.confirm,
          [ConsentConfirmMode.record, ConsentConfirmMode.signature]);
      expect(config.speakerName, SpeakerNameRequirement.required);
      expect(config.reconsentButton, isTrue, reason: 'D11 default');
      final json = config.toJson();
      expect(json['futureKey'], {'nested': true});
      expect(ConsentConfig.fromJson(json), config);
    });

    test('legacy free-form block parses as disabled with extra preserved', () {
      final config = ConsentConfig.fromJson(
          {'mode': 'audio', 'script': 'May we record you?'});
      expect(config.enabled, isFalse);
      expect(config.extra['script'], 'May we record you?');
    });

    test('coherence validation catches every rule', () {
      expect(
          ConsentConfig.fromJson({
            'ask': ['text'],
            'confirm': ['yesno']
          }).validate().single,
          contains('no consent message'));
      expect(
          ConsentConfig.fromJson({
            'ask': ['audio'],
            'confirm': ['yesno']
          }).validate().single,
          contains('no prompt recording'));
      expect(
          ConsentConfig.fromJson({
            'confirm': ['yesno']
          }).validate().single,
          contains('presents no statement'));
      expect(
          ConsentConfig.fromJson({
            'ask': ['text'],
            'message': 'x'
          }).validate().single,
          contains('captures no response'));
      final continuation = ConsentConfig.fromJson({
        'ask': ['text', 'audio'],
        'confirm': ['yesno'],
        'message': 'x',
        'audioFile': 'p.wav',
        'continuation': 'perDay',
      }).validate();
      expect(continuation, hasLength(2));
      expect(continuation.join(' '), contains('continuation message'));
      expect(continuation.join(' '), contains('continuation recording'));
    });
  });

  group('ConsentReceipt', () {
    test('build seals a verifiable content hash and round-trips', () {
      final receipt = ceremony();
      expect(receipt.verifyContentHash(), isTrue);
      final reparsed = ConsentReceipt.fromJson(receipt.toJsonString());
      expect(reparsed.id, 'cer-001');
      expect(reparsed.kind, ConsentReceiptKind.ceremony);
      expect(reparsed.contentSha256, receipt.contentSha256);
      expect(reparsed.speakerName, 'Yohanis');
    });

    test('tampering with a sealed receipt is detected', () {
      final receipt = ceremony();
      final tampered = jsonDecode(receipt.toJsonString()) as Map<String, Object?>;
      (tampered['scope'] as Map<String, Object?>)['statement'] =
          'Anything we ever want, forever.';
      expect(() => ConsentReceipt.fromJson(jsonEncode(tampered)),
          throwsFormatException);
      expect(
          ConsentReceipt.fromJson(jsonEncode(tampered), verifyHash: false)
              .verifyContentHash(),
          isFalse);
    });

    test('content hash is order-independent (canonical JSON)', () {
      final receipt = ceremony();
      final shuffled = Map<String, Object?>.fromEntries(
          (jsonDecode(receipt.toJsonString()) as Map<String, Object?>)
              .entries
              .toList()
              .reversed);
      final reparsed = ConsentReceipt.fromJson(jsonEncode(shuffled));
      expect(reparsed.verifyContentHash(), isTrue);
    });

    test('human rendering is deterministic and footered with the hash', () {
      final receipt = ceremony();
      final text = receipt.renderHumanText();
      expect(text, receipt.renderHumanText());
      expect(text, contains('CONSENT RECEIPT (ceremony)'));
      expect(text, contains('Speaker: Yohanis'));
      expect(text, contains(receipt.contentSha256));
      expect(text, contains('JSON file is the authoritative record'));
    });

    test('rejects foreign and future files', () {
      expect(() => ConsentReceipt.fromJson('{"format":"x"}'),
          throwsFormatException);
      expect(
          () => ConsentReceipt.fromJson(
              '{"format":"deksync-consent-receipt","version":99,"id":"a","kind":"ceremony"}'),
          throwsFormatException);
    });
  });

  group('validateConsentCoverage', () {
    test('fully covered items pass', () {
      final cer = ceremony();
      final problems = validateConsentCoverage(receipts: [
        cer
      ], items: [
        StampedItem(
          description: 'Recording "x.wav"',
          receiptId: cer.id,
          receiptSha256: cer.contentSha256,
          collectedAtIso: '2026-07-03T09:00:00Z',
        ),
      ]);
      expect(problems, isEmpty);
    });

    test('unstamped, unknown-receipt and stale-hash items are flagged', () {
      final cer = ceremony();
      final problems = validateConsentCoverage(receipts: [
        cer
      ], items: [
        const StampedItem(description: 'Item A'),
        const StampedItem(description: 'Item B', receiptId: 'nope'),
        StampedItem(
            description: 'Item C',
            receiptId: cer.id,
            receiptSha256: 'f' * 64),
      ]);
      expect(problems, hasLength(3));
      expect(problems[0], contains('no consent stamp'));
      expect(problems[1], contains('not in this package'));
      expect(problems[2], contains('altered since collection'));
    });

    test('a withdrawal stamp never covers; post-withdrawal collection is '
        'flagged; pre-withdrawal passes; unknown time is flagged', () {
      final cer = ceremony();
      final withdrawal = ConsentReceipt.build(
        id: 'wd-001',
        kind: ConsentReceiptKind.withdrawal,
        refersTo: cer.id,
        refersToSha256: cer.contentSha256,
        taskId: 'task-001',
        baseCheckpointId: 'checkpoint-42',
        scopeStatement: 'Withdrawn.',
        promptModes: const [],
        promptMessage: '',
        responseTypes: const [ConsentConfirmMode.yesno],
        timestampIso: '2026-07-03T12:00:00Z',
        timestampLocal: '2026-07-03 21:00',
        timezone: 'Asia/Jayapura',
        deviceId: 'device-1',
        appVersion: '1.0.0',
        platform: 'android',
      );
      final problems = validateConsentCoverage(receipts: [
        cer,
        withdrawal
      ], items: [
        StampedItem(
            description: 'Stamped-with-withdrawal',
            receiptId: withdrawal.id,
            receiptSha256: withdrawal.contentSha256),
        StampedItem(
            description: 'Collected-after',
            receiptId: cer.id,
            receiptSha256: cer.contentSha256,
            collectedAtIso: '2026-07-03T13:00:00Z'),
        StampedItem(
            description: 'Collected-before',
            receiptId: cer.id,
            receiptSha256: cer.contentSha256,
            collectedAtIso: '2026-07-03T09:00:00Z'),
        StampedItem(
            description: 'Unknown-time',
            receiptId: cer.id,
            receiptSha256: cer.contentSha256),
      ]);
      expect(problems, hasLength(3));
      expect(problems.join('\n'), contains('never covers collection'));
      expect(problems.join('\n'), contains('AFTER consent was withdrawn'));
      expect(problems.join('\n'), contains('cannot verify it predates'));
    });

    test('continuation must chain to a bundled, unmodified ceremony', () {
      final cer = ceremony();
      final continuation = ConsentReceipt.build(
        id: 'con-001',
        kind: ConsentReceiptKind.continuation,
        refersTo: cer.id,
        refersToSha256: 'e' * 64, // wrong on purpose
        taskId: 'task-001',
        baseCheckpointId: 'checkpoint-42',
        scopeStatement: 'Continue.',
        promptModes: const [ConsentAskMode.audio],
        promptMessage: '',
        responseTypes: const [ConsentConfirmMode.yesno],
        timestampIso: '2026-07-04T08:00:00Z',
        timestampLocal: '2026-07-04 17:00',
        timezone: 'Asia/Jayapura',
        deviceId: 'device-1',
        appVersion: '1.0.0',
        platform: 'android',
      );
      final problems =
          validateConsentCoverage(receipts: [cer, continuation], items: const []);
      expect(problems.single, contains('content has changed since'));

      final orphan = validateConsentCoverage(receipts: [continuation], items: const []);
      expect(orphan.single, contains('not in this package'));
    });
  });

  group('format carriers', () {
    DekTaskPackage consentTask() => DekTaskPackage(
          task: DekTask(
            taskId: 'task-001',
            title: 'Consented task',
            baseCheckpointId: 'checkpoint-42',
            createdAt: '2026-07-02T12:00:00Z',
            fields: const [
              TaskField(column: 'Gloss', role: TaskFieldRole.visible),
              TaskField(
                  column: 'Yohanis',
                  role: TaskFieldRole.writable,
                  input: TaskInputKind.both,
                  suffix: '-yoh'),
            ],
            records: const [TaskRecordRef(dkSyncId: 'aaa', reference: '0001')],
            consent: const {
              'ask': ['audio'],
              'confirm': ['record'],
              'audioFile': 'prompt-abcd1234.wav',
              'scopeStatement': 'These words.',
            },
          ),
          wordlist: DekerekeDatabase([
            DekerekeRecord(const [
              DekerekeValueField('Reference', '0001'),
              DekerekeValueField('Gloss', 'body'),
              DekerekeValueField('Yohanis', ''),
            ]),
          ]),
          consentFiles: {
            'prompt-abcd1234.wav': Uint8List.fromList([1, 2]),
          },
        );

    test('.dektask bundles and round-trips consent config + audio', () {
      final decoded = decodeDekTask(encodeDekTask(consentTask()));
      final config = decoded.task.consentConfig;
      expect(config.enabled, isTrue);
      expect(config.ask, [ConsentAskMode.audio]);
      expect(config.reconsentButton, isTrue);
      expect(decoded.consentFiles['prompt-abcd1234.wav'], [1, 2]);
    });

    test('a task referencing unbundled consent audio is rejected', () {
      final package = consentTask();
      expect(
          () => DekTaskPackage(
                task: package.task,
                wordlist: package.wordlist,
                // consentFiles omitted
              ),
          throwsFormatException);
    });

    test('.dekresult carries receipts (json+txt) and verifies on decode', () {
      final cer = ceremony();
      final package = DekResultPackage(
        result: DekResult(
          taskId: 'task-001',
          baseCheckpointId: 'checkpoint-42',
          completedAt: '2026-07-03T10:00:00Z',
          values: [
            ResultValue(
              dkSyncId: 'aaa',
              column: 'Yohanis',
              value: 'bɔdi',
              receiptId: cer.id,
              receiptSha256: cer.contentSha256,
              collectedAt: '2026-07-03T09:00:00Z',
            ),
          ],
          recordings: const [],
        ),
        receipts: [cer],
        consentFiles: {
          'assent-cer-001.wav': Uint8List.fromList([7]),
        },
      );
      final decoded = decodeDekResult(encodeDekResult(package));
      expect(decoded.receipts.single.id, cer.id);
      expect(decoded.receipts.single.verifyContentHash(), isTrue);
      expect(decoded.consentFiles.containsKey('assent-cer-001.wav'), isTrue);
      expect(decoded.result.values.single.receiptId, cer.id);

      final task = decodeDekTask(encodeDekTask(consentTask())).task;
      expect(validateResult(task, decoded), isEmpty);
    });

    test('validateResult enforces coverage only when consent is configured',
        () {
      final consentOn = decodeDekTask(encodeDekTask(consentTask())).task;
      final unstamped = DekResultPackage(
        result: const DekResult(
          taskId: 'task-001',
          baseCheckpointId: 'checkpoint-42',
          completedAt: '',
          values: [ResultValue(dkSyncId: 'aaa', column: 'Yohanis', value: 'x')],
          recordings: [],
        ),
      );
      final problems = validateResult(consentOn, unstamped);
      expect(problems.single, contains('no consent stamp'));

      final consentOff = DekTask(
        taskId: 'task-001',
        title: '',
        baseCheckpointId: 'checkpoint-42',
        createdAt: '',
        fields: consentOn.fields,
        records: consentOn.records,
      );
      expect(validateResult(consentOff, unstamped), isEmpty,
          reason: 'consent-off tasks are exempt by design');
    });

    test('a receipt for a different task is flagged', () {
      final foreign = ceremony(taskId: 'other-task');
      final task = decodeDekTask(encodeDekTask(consentTask())).task;
      final package = DekResultPackage(
        result: const DekResult(
          taskId: 'task-001',
          baseCheckpointId: 'checkpoint-42',
          completedAt: '',
          values: [],
          recordings: [],
        ),
        receipts: [foreign],
      );
      expect(validateResult(task, package).join('\n'),
          contains('covers a different task'));
    });

    test('per-voice re-consent: items stamp their own ceremony (D11)', () {
      final voice1 = ceremony(id: 'cer-001', speakerName: 'Yohanis');
      final voice2 = ceremony(
          id: 'cer-002', prev: voice1.contentSha256, speakerName: 'Maria');
      final problems = validateConsentCoverage(receipts: [
        voice1,
        voice2
      ], items: [
        StampedItem(
            description: 'Yohanis word',
            receiptId: voice1.id,
            receiptSha256: voice1.contentSha256),
        StampedItem(
            description: 'Maria word',
            receiptId: voice2.id,
            receiptSha256: voice2.contentSha256),
      ]);
      expect(problems, isEmpty);
      expect(voice2.prevReceiptSha256, voice1.contentSha256,
          reason: 'per-device chain links ceremonies');
    });
  });
}
