import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/providers.dart';
import '../../../shared/theme/orbit_colors.dart';
import '../models/project_models.dart';
import '../widgets/commit_tile.dart';
import '../../../shared/widgets/orbit_loading_indicator.dart';

class GitHistoryScreen extends ConsumerStatefulWidget {
  final String projectPath;
  final String projectName;

  const GitHistoryScreen({
    super.key,
    required this.projectPath,
    required this.projectName,
  });

  @override
  ConsumerState<GitHistoryScreen> createState() => _GitHistoryScreenState();
}

class _GitHistoryScreenState extends ConsumerState<GitHistoryScreen> {
  bool _isLoading = true;
  List<GitCommit> _commits = [];
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadCommits();
  }

  Future<void> _loadCommits() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final client = ref.read(orbitClientProvider);
      final res = await client.sendRequest('git.log', payload: {
        'path': widget.projectPath,
        'limit': 30,
      });

      if (res.success && res.payload != null) {
        final commitsList = res.payload!['commits'] as List<dynamic>?;
        final parsed = commitsList
                ?.map((c) => GitCommit.fromJson(c as Map<String, dynamic>))
                .toList() ??
            [];
        setState(() {
          _commits = parsed;
          _isLoading = false;
        });
      } else {
        setState(() {
          _errorMessage = res.error?.message ?? 'Failed to load commits';
          _isLoading = false;
        });
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'Error: $e';
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: OrbitColors.backgroundDark,
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'GIT HISTORY',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                letterSpacing: 1.1,
                fontFamily: 'monospace',
              ),
            ),
            Text(
              widget.projectName,
              style: const TextStyle(
                fontSize: 11,
                color: OrbitColors.textMuted,
                fontFamily: 'monospace',
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: OrbitColors.accentCyan),
            onPressed: _isLoading ? null : _loadCommits,
            tooltip: 'Refresh history',
          ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(
        child: OrbitLoadingIndicator(size: 40),
      );
    }

    if (_errorMessage != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline,
                  color: OrbitColors.error, size: 40),
              const SizedBox(height: 12),
              Text(
                _errorMessage!,
                style: const TextStyle(
                  color: OrbitColors.error,
                  fontFamily: 'monospace',
                  fontSize: 13,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: _loadCommits,
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    if (_commits.isEmpty) {
      return const Center(
        child: Text(
          'No commits found.',
          style: TextStyle(
            color: OrbitColors.textMuted,
            fontFamily: 'monospace',
          ),
        ),
      );
    }

    return RefreshIndicator(
      color: OrbitColors.primary,
      backgroundColor: OrbitColors.surfaceDark,
      onRefresh: _loadCommits,
      child: ListView.builder(
        padding: const EdgeInsets.symmetric(vertical: 12),
        itemCount: _commits.length,
        itemBuilder: (context, index) {
          final commit = _commits[index];
          return CommitTile(commit: commit);
        },
      ),
    );
  }
}
