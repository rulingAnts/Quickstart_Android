import 'package:flutter/material.dart';
import '../models/consent_record.dart';
import '../services/audio_service.dart';
import '../services/database_service.dart';
import 'elicitation_screen.dart';

/// Obtains informed consent from the speaker before any data collection.
///
/// Shows a plain-language explanation with large Agree / Decline buttons and
/// an optional verbal-consent recording. The response is stored as a
/// timestamped [ConsentRecord] that is included in every export.
class ConsentScreen extends StatefulWidget {
  const ConsentScreen({super.key});

  @override
  State<ConsentScreen> createState() => _ConsentScreenState();
}

class _ConsentScreenState extends State<ConsentScreen> {
  final DatabaseService _db = DatabaseService.instance;
  final AudioService _audioService = AudioService();

  bool _isRecording = false;
  bool _isSaving = false;
  String? _verbalConsentFilename;

  // TODO(researcher): localize this text for the language community, or read
  // it aloud in the local language before recording verbal consent.
  static const String _consentText =
      'We are collecting words in your language, with recordings of your '
      'voice, to help document and preserve it.\n\n'
      'The words and recordings will be kept and may be shared with language '
      'researchers. Your name will not be attached to them.\n\n'
      'You may stop at any time. Do you agree to take part?';

  @override
  void dispose() {
    if (_isRecording) {
      _audioService.cancelRecording();
    }
    _audioService.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Consent'),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Icon(
                Icons.handshake,
                size: 72,
                color: Colors.blue,
              ),
              const SizedBox(height: 24),
              const Card(
                child: Padding(
                  padding: EdgeInsets.all(20.0),
                  child: Text(
                    _consentText,
                    style: TextStyle(fontSize: 18, height: 1.4),
                  ),
                ),
              ),
              const SizedBox(height: 24),

              // Optional verbal consent recording.
              Card(
                color: _isRecording ? Colors.red.shade50 : null,
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    children: [
                      Text(
                        _verbalConsentFilename != null
                            ? 'Verbal consent recorded'
                            : 'Optional: record spoken consent',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      IconButton(
                        onPressed: _isSaving ? null : _toggleRecording,
                        icon: Icon(
                          _isRecording
                              ? Icons.stop_circle
                              : (_verbalConsentFilename != null
                                  ? Icons.check_circle
                                  : Icons.mic),
                          size: 56,
                          color: _isRecording
                              ? Colors.red
                              : (_verbalConsentFilename != null
                                  ? Colors.green
                                  : Colors.blue),
                        ),
                      ),
                      if (_isRecording)
                        const Text('Recording... tap to stop'),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 32),

              SizedBox(
                height: 72,
                child: ElevatedButton.icon(
                  onPressed: _isSaving || _isRecording
                      ? null
                      : () => _respond(ConsentResponse.assent),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green,
                    foregroundColor: Colors.white,
                  ),
                  icon: const Icon(Icons.thumb_up, size: 32),
                  label: const Text(
                    'I Agree',
                    style: TextStyle(fontSize: 22),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(
                height: 56,
                child: OutlinedButton.icon(
                  onPressed: _isSaving || _isRecording
                      ? null
                      : () => _respond(ConsentResponse.decline),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.red,
                  ),
                  icon: const Icon(Icons.thumb_down),
                  label: const Text(
                    'No, I do not agree',
                    style: TextStyle(fontSize: 18),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _toggleRecording() async {
    if (_isRecording) {
      final filename = await _audioService.stopRecording();
      if (!mounted) return;
      setState(() {
        _isRecording = false;
        _verbalConsentFilename = filename ?? _verbalConsentFilename;
      });
    } else {
      try {
        await _audioService.startConsentRecording();
        if (!mounted) return;
        setState(() => _isRecording = true);
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error starting recording: $e')),
          );
        }
      }
    }
  }

  Future<void> _respond(ConsentResponse response) async {
    setState(() => _isSaving = true);

    try {
      // Recordings sit in the temp directory until committed; keep the
      // verbal consent only when a response is actually recorded.
      var verbalFilename = _verbalConsentFilename;
      if (verbalFilename != null &&
          !await _audioService.finalizeRecording(verbalFilename)) {
        verbalFilename = null;
      }

      final deviceId = await _db.getOrCreateDeviceId();
      await _db.insertConsentRecord(ConsentRecord(
        timestamp: DateTime.now(),
        deviceId: deviceId,
        type: verbalFilename != null
            ? ConsentType.verbal
            : ConsentType.written,
        response: response,
        verbalConsentFilename: verbalFilename,
      ));
    } catch (e) {
      if (mounted) {
        setState(() => _isSaving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error saving consent: $e')),
        );
      }
      return;
    }

    if (!mounted) return;

    if (response == ConsentResponse.assent) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (context) => const ElicitationScreen()),
      );
    } else {
      // Grab the messenger before popping; this context is going away.
      final messenger = ScaffoldMessenger.of(context);
      Navigator.pop(context);
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Consent declined — no data will be collected.'),
        ),
      );
    }
  }
}
