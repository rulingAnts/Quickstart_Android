import 'package:dekereke_core/dekereke_core.dart' show DekTask;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import '../providers/wordlist_provider.dart';
import '../services/export_service.dart';
import '../services/task_service.dart';

class ExportScreen extends StatefulWidget {
  const ExportScreen({super.key});

  @override
  State<ExportScreen> createState() => _ExportScreenState();
}

class _ExportScreenState extends State<ExportScreen> {
  final ExportService _exportService = ExportService();
  final TaskService _taskService = TaskService();

  /// Active task, if any: exports then produce a `.dekresult` answers file
  /// instead of the full ZIP backup.
  DekTask? _activeTask;
  bool _taskLoaded = false;

  bool _isExporting = false;
  String? _exportedFilePath;

  @override
  void initState() {
    super.initState();
    _taskService.getActiveTask().then((task) {
      if (mounted) {
        setState(() {
          _activeTask = task;
          _taskLoaded = true;
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Export Data'),
      ),
      body: Consumer<WordlistProvider>(
        builder: (context, provider, child) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(
                    Icons.file_download,
                    size: 80,
                    color: Colors.blue,
                  ),
                  const SizedBox(height: 32),
                  const Text(
                    'Export Collected Data',
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 48),
                  
                  // Summary card
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        children: [
                          _buildSummaryRow(
                            'Total Entries',
                            '${provider.totalCount}',
                          ),
                          const Divider(),
                          _buildSummaryRow(
                            'Completed',
                            '${provider.completedCount}',
                          ),
                          const Divider(),
                          _buildSummaryRow(
                            'Remaining',
                            '${provider.totalCount - provider.completedCount}',
                          ),
                        ],
                      ),
                    ),
                  ),
                  
                  const SizedBox(height: 32),
                  
                  if (_exportedFilePath != null) ...[
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.green.shade50,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Row(
                        children: [
                          Icon(Icons.check_circle, color: Colors.green),
                          SizedBox(width: 16),
                          Expanded(
                            child: Text(
                              'Export successful!',
                              style: TextStyle(fontSize: 16),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),
                  ],
                  
                  SizedBox(
                    width: double.infinity,
                    height: 64,
                    child: ElevatedButton.icon(
                      onPressed:
                          _isExporting || !_taskLoaded ? null : _exportData,
                      icon: _isExporting
                          ? const SizedBox(
                              width: 24,
                              height: 24,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.save_alt, size: 32),
                      label: Text(
                        _isExporting
                            ? 'Exporting...'
                            : (_activeTask != null
                                ? 'Export My Answers'
                                : 'Export as ZIP'),
                        style: const TextStyle(fontSize: 18),
                      ),
                      style: ElevatedButton.styleFrom(
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ),
                  
                  if (_exportedFilePath != null) ...[
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      height: 64,
                      child: ElevatedButton.icon(
                        onPressed: _shareExport,
                        icon: const Icon(Icons.share, size: 32),
                        label: const Text(
                          'Share Export',
                          style: TextStyle(fontSize: 18),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.green,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                    ),
                  ],
                  
                  const SizedBox(height: 32),
                  Text(
                    _activeTask != null
                        ? 'The answers file includes:\n'
                            '• Your typed answers\n'
                            '• Your recordings (WAV format)\n'
                            '• Consent log\n'
                            'Send it back to the person who gave you the task.'
                        : 'Export includes:\n'
                            '• Dekereke XML with transcriptions\n'
                            '• Audio recordings (WAV format)\n'
                            '• Consent log',
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 14),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildSummaryRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: const TextStyle(fontSize: 16),
          ),
          Text(
            value,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _exportData() async {
    setState(() {
      _isExporting = true;
      _exportedFilePath = null;
    });

    try {
      final filePath = _activeTask != null
          ? await _taskService.exportDekResult()
          : await _exportService.exportData();

      setState(() {
        _isExporting = false;
        _exportedFilePath = filePath;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Data exported successfully!'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      setState(() {
        _isExporting = false;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error exporting data: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _shareExport() async {
    if (_exportedFilePath == null) return;

    try {
      await Share.shareXFiles(
        [XFile(_exportedFilePath!)],
        subject: 'Wordlist Elicitation Export',
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error sharing file: $e')),
        );
      }
    }
  }
}
