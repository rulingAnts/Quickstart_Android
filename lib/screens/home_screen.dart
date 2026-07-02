import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/wordlist_provider.dart';
import '../services/database_service.dart';
import 'consent_screen.dart';
import 'import_screen.dart';
import 'elicitation_screen.dart';
import 'export_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<WordlistProvider>().loadWordlist();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Wordlist Elicitation Tool'),
        centerTitle: true,
      ),
      body: Consumer<WordlistProvider>(
        builder: (context, provider, child) {
          return Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(
                    Icons.book,
                    size: 80,
                    color: Colors.blue,
                  ),
                  const SizedBox(height: 32),
                  const Text(
                    'Comparative Wordlist\nElicitation Tool',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 48),
                  _buildProgressCard(provider),
                  const SizedBox(height: 32),
                  _buildMainButton(
                    context,
                    icon: Icons.file_upload,
                    label: 'Import Wordlist',
                    onPressed: () => _navigateToImport(context),
                  ),
                  const SizedBox(height: 16),
                  _buildMainButton(
                    context,
                    icon: Icons.mic,
                    label: 'Start Elicitation',
                    onPressed: provider.entries.isEmpty
                        ? null
                        : () => _navigateToElicitation(context),
                  ),
                  const SizedBox(height: 16),
                  _buildMainButton(
                    context,
                    icon: Icons.file_download,
                    label: 'Export Data',
                    onPressed: provider.entries.isEmpty
                        ? null
                        : () => _navigateToExport(context),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildProgressCard(WordlistProvider provider) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            const Text(
              'Progress',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildStatColumn(
                  'Total',
                  '${provider.totalCount}',
                  Icons.list,
                ),
                _buildStatColumn(
                  'Completed',
                  '${provider.completedCount}',
                  Icons.check_circle,
                ),
                _buildStatColumn(
                  'Remaining',
                  '${provider.totalCount - provider.completedCount}',
                  Icons.pending,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatColumn(String label, String value, IconData icon) {
    return Column(
      children: [
        Icon(icon, size: 32, color: Colors.blue),
        const SizedBox(height: 8),
        Text(
          value,
          style: const TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.bold,
          ),
        ),
        Text(
          label,
          style: TextStyle(
            fontSize: 14,
            color: Colors.grey[600],
          ),
        ),
      ],
    );
  }

  Widget _buildMainButton(
    BuildContext context, {
    required IconData icon,
    required String label,
    required VoidCallback? onPressed,
  }) {
    return SizedBox(
      width: double.infinity,
      height: 64,
      child: ElevatedButton.icon(
        onPressed: onPressed,
        icon: Icon(icon, size: 32),
        label: Text(
          label,
          style: const TextStyle(fontSize: 18),
        ),
        style: ElevatedButton.styleFrom(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
    );
  }

  void _navigateToImport(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const ImportScreen()),
    );
  }

  /// Elicitation is gated on informed consent: the consent screen is shown
  /// until the speaker has agreed (an MVP ethics requirement).
  Future<void> _navigateToElicitation(BuildContext context) async {
    final hasAssent = await DatabaseService.instance.hasAssent();
    if (!context.mounted) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) =>
            hasAssent ? const ElicitationScreen() : const ConsentScreen(),
      ),
    );
  }

  void _navigateToExport(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const ExportScreen()),
    );
  }
}
