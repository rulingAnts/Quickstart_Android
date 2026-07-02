import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:provider/provider.dart';
import '../services/xml_service.dart';
import '../providers/wordlist_provider.dart';

class ImportScreen extends StatefulWidget {
  const ImportScreen({super.key});

  @override
  State<ImportScreen> createState() => _ImportScreenState();
}

class _ImportScreenState extends State<ImportScreen> {
  final XmlImportService _xmlService = XmlImportService();
  bool _isImporting = false;
  String? _statusMessage;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Import Wordlist'),
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(
                Icons.file_upload,
                size: 80,
                color: Colors.blue,
              ),
              const SizedBox(height: 32),
              const Text(
                'Import Wordlist XML',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'Select a Dekereke XML wordlist file to import',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 16),
              ),
              const SizedBox(height: 48),
              if (_statusMessage != null) ...[
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.blue.shade50,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    _statusMessage!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 16),
                  ),
                ),
                const SizedBox(height: 24),
              ],
              SizedBox(
                width: double.infinity,
                height: 64,
                child: ElevatedButton.icon(
                  onPressed: _isImporting ? null : _pickAndImportFile,
                  icon: _isImporting
                      ? const SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.folder_open, size: 32),
                  label: Text(
                    _isImporting ? 'Importing...' : 'Select XML File',
                    style: const TextStyle(fontSize: 18),
                  ),
                  style: ElevatedButton.styleFrom(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 32),
              const Divider(),
              const SizedBox(height: 16),
              const Text(
                'Note: If you already have recordings, you can choose to '
                'keep them when importing an updated wordlist.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.orange,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _pickAndImportFile() async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['xml'],
      );

      final filePath = result?.files.single.path;
      if (filePath == null) return;
      if (!mounted) return;

      // If data has already been collected, let the user choose between
      // replacing everything and updating the wordlist in place.
      final provider = context.read<WordlistProvider>();
      var merge = false;
      if (provider.completedCount > 0) {
        final choice = await _askReplaceOrMerge();
        if (choice == null) return; // cancelled
        merge = choice;
      }
      if (!mounted) return;

      setState(() {
        _isImporting = true;
        _statusMessage = 'Importing wordlist...';
      });

      final importResult =
          await _xmlService.importDekerekeXml(filePath, merge: merge);

      if (!mounted) return;
      await context.read<WordlistProvider>().loadWordlist();
      if (!mounted) return;

      final details = <String>[
        'Imported ${importResult.imported} entries.',
        if (importResult.skippedDuplicates > 0)
          '${importResult.skippedDuplicates} duplicate references skipped.',
        if (importResult.skippedInvalid > 0)
          '${importResult.skippedInvalid} incomplete records skipped.',
      ];
      setState(() {
        _isImporting = false;
        _statusMessage = details.join('\n');
      });

      // Navigate back after a delay
      await Future.delayed(const Duration(seconds: 2));
      if (mounted) {
        Navigator.pop(context);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isImporting = false;
        _statusMessage = 'Error importing file: ${e.toString()}';
      });
    }
  }

  /// Returns true to merge (keep collected data), false to replace all,
  /// null if cancelled.
  Future<bool?> _askReplaceOrMerge() {
    return showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Existing data found'),
        content: const Text(
          'You already have recordings or transcriptions. How should the '
          'new wordlist be imported?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Replace everything'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Update, keep my data'),
          ),
        ],
      ),
    );
  }
}
