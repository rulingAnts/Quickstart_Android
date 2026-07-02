import 'dart:io';

import 'package:dekereke_core/dekereke_core.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

/// The Database health panel (plan §4.2) — already functional in the
/// scaffold: open a Dekereke XML file (optionally its settings file and
/// audio folder are picked up automatically when they sit next to it) and
/// run `dekereke_core`'s health rules against it.
class HealthScreen extends StatefulWidget {
  const HealthScreen({super.key});

  @override
  State<HealthScreen> createState() => _HealthScreenState();
}

class _HealthScreenState extends State<HealthScreen> {
  String? _databasePath;
  int _recordCount = 0;
  List<HealthIssue> _issues = const [];
  String? _error;
  bool _checkedFolder = false;
  bool _busy = false;

  Future<void> _openDatabase() async {
    const typeGroup = XTypeGroup(label: 'Dekereke database', extensions: ['xml']);
    final file = await openFile(acceptedTypeGroups: const [typeGroup]);
    if (file == null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final bytes = await File(file.path).readAsBytes();
      final db = parseDekerekeFile(bytes);

      // Settings and audio folder are used when found next to the file:
      // <name>-DkUserSettings.xml and the folder its sound_file_path names
      // (or an `audio` sibling).
      DkUserSettings? settings;
      final base = file.path.replaceAll(RegExp(r'\.xml$', caseSensitive: false), '');
      final settingsFile = File('$base-DkUserSettings.xml');
      if (await settingsFile.exists()) {
        settings = DkUserSettings.parseBytes(await settingsFile.readAsBytes());
      }

      List<String>? audioFilenames;
      final parent = File(file.path).parent;
      final candidates = <Directory>[
        if (settings?.soundFilePath case final path?
            when path.isNotEmpty) Directory(path),
        Directory('${parent.path}${Platform.pathSeparator}audio'),
      ];
      for (final dir in candidates) {
        if (await dir.exists()) {
          audioFilenames = [
            await for (final f in dir.list())
              if (f is File) f.uri.pathSegments.last,
          ];
          break;
        }
      }

      final issues = checkDatabaseHealth(
        db,
        audioFilenames: audioFilenames,
        settings: settings,
      );
      setState(() {
        _databasePath = file.path;
        _recordCount = db.records.length;
        _issues = issues;
        _checkedFolder = audioFilenames != null;
        _busy = false;
      });
    } catch (e) {
      setState(() {
        _error = 'Could not read that file: $e';
        _busy = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Database health check',
              style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 8),
          const Text(
            'Open your Dekereke database file (.xml). If its settings file '
            'and audio folder are next to it, recordings are checked too.',
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: _busy ? null : _openDatabase,
            icon: const Icon(Icons.folder_open),
            label: Text(_databasePath == null
                ? 'Open database…'
                : 'Open another database…'),
          ),
          if (_error != null) ...[
            const SizedBox(height: 16),
            Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ],
          if (_databasePath != null && _error == null) ...[
            const SizedBox(height: 16),
            Text(
              '$_databasePath — $_recordCount words'
              '${_checkedFolder ? ', audio folder checked' : ' (no audio folder found)'}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
            Expanded(child: _HealthResults(issues: _issues)),
          ],
        ],
      ),
    );
  }
}

class _HealthResults extends StatelessWidget {
  final List<HealthIssue> issues;

  const _HealthResults({required this.issues});

  @override
  Widget build(BuildContext context) {
    if (issues.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.check_circle, color: Colors.green, size: 64),
            SizedBox(height: 12),
            Text('Everything looks good!', style: TextStyle(fontSize: 18)),
          ],
        ),
      );
    }
    final problems =
        issues.where((i) => i.severity == HealthSeverity.problem).length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '$problems need${problems == 1 ? 's' : ''} attention, '
          '${issues.length - problems} worth a look:',
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: ListView.builder(
            itemCount: issues.length,
            itemBuilder: (context, index) {
              final issue = issues[index];
              final isProblem = issue.severity == HealthSeverity.problem;
              return ListTile(
                leading: Icon(
                  isProblem ? Icons.error : Icons.warning_amber,
                  color: isProblem ? Colors.red : Colors.orange,
                ),
                title: Text(issue.message),
                dense: true,
              );
            },
          ),
        ),
      ],
    );
  }
}
