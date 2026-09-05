import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../protocol/models/script_models.dart';
import '../../../shared/theme/orbit_colors.dart';
import '../../../shared/widgets/orbit_button.dart';
import '../../../shared/widgets/orbit_card.dart';
import '../../../shared/widgets/orbit_loading_indicator.dart';
import '../../terminal/views/terminal_screen.dart';
import '../controllers/scripts_controller.dart';

class ScriptsScreen extends ConsumerStatefulWidget {
  final String? projectPath;
  final String? projectName;
  final VoidCallback? onBack;

  const ScriptsScreen({
    super.key,
    this.projectPath,
    this.projectName,
    this.onBack,
  });

  @override
  ConsumerState<ScriptsScreen> createState() => _ScriptsScreenState();
}

class _ScriptsScreenState extends ConsumerState<ScriptsScreen> {
  final TextEditingController _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _runScript(Script script) {
    if (script.content.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Script content is empty.')),
      );
      return;
    }

    final resolvedCwd = script.workingDirectory ?? script.projectPath;

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => TerminalScreen(
          initialCwd: resolvedCwd,
          initialCommand: script.content,
          runningScriptName: script.name,
        ),
      ),
    );
  }

  void _openEditorSheet([Script? script]) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _ScriptEditorSheet(
        script: script,
        defaultProjectPath: widget.projectPath,
        onSave: (input) async {
          final controller = ref.read(scriptsControllerProvider(widget.projectPath).notifier);
          final success = await controller.saveScript(input);
          if (success && ctx.mounted) {
            Navigator.pop(ctx);
          }
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(scriptsControllerProvider(widget.projectPath));
    final controller = ref.read(scriptsControllerProvider(widget.projectPath).notifier);

    final title = widget.projectName != null
        ? '${widget.projectName} Scripts'
        : 'Saved Scripts';

    return Scaffold(
      backgroundColor: OrbitColors.orbitBackground,
      appBar: AppBar(
        backgroundColor: OrbitColors.orbitSurface,
        elevation: 0,
        leading: widget.onBack != null
            ? IconButton(
                icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 18),
                onPressed: widget.onBack,
              )
            : (Navigator.canPop(context)
                ? IconButton(
                    icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 18),
                    onPressed: () => Navigator.pop(context),
                  )
                : null),
        title: Text(
          title,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            letterSpacing: 0.5,
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded, size: 20),
            onPressed: () => controller.loadScripts(),
            tooltip: 'Refresh',
          ),
          IconButton(
            icon: const Icon(Icons.add_rounded, size: 24),
            onPressed: () => _openEditorSheet(),
            tooltip: 'New Script',
          ),
        ],
      ),
      body: Column(
        children: [
          // Search and Filters
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: const BoxDecoration(
              color: OrbitColors.orbitSurface,
              border: Border(
                bottom: BorderSide(color: OrbitColors.orbitBorder, width: 0.8),
              ),
            ),
            child: Column(
              children: [
                // Search field
                Container(
                  height: 38,
                  decoration: BoxDecoration(
                    color: OrbitColors.orbitBackground,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: OrbitColors.orbitBorder),
                  ),
                  child: TextField(
                    controller: _searchController,
                    onChanged: (val) => controller.setSearchQuery(val),
                    style: const TextStyle(fontSize: 13, color: Colors.white),
                    decoration: InputDecoration(
                      hintText: 'Search scripts...',
                      hintStyle: const TextStyle(color: OrbitColors.orbitTextMuted, fontSize: 13),
                      prefixIcon: const Icon(Icons.search, size: 16, color: OrbitColors.orbitTextMuted),
                      suffixIcon: _searchController.text.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear, size: 14, color: OrbitColors.orbitTextMuted),
                              onPressed: () {
                                _searchController.clear();
                                controller.setSearchQuery('');
                              },
                            )
                          : null,
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(vertical: 9),
                    ),
                  ),
                ),

                // Scope filters (only if not viewing within specific project)
                if (widget.projectPath == null) ...[
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      _buildScopeFilterChip('all', 'All (${state.scripts.length})', state, controller),
                      const SizedBox(width: 8),
                      _buildScopeFilterChip('global', 'Global', state, controller),
                      const SizedBox(width: 8),
                      _buildScopeFilterChip('project', 'Project', state, controller),
                    ],
                  ),
                ],
              ],
            ),
          ),

          // Error Banner
          if (state.errorMessage != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              color: const Color(0xFF3B1212),
              child: Row(
                children: [
                  const Icon(Icons.error_outline, size: 16, color: Color(0xFFF87171)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      state.errorMessage!,
                      style: const TextStyle(color: Color(0xFFF87171), fontSize: 12),
                    ),
                  ),
                ],
              ),
            ),

          // Main list or Empty State
          Expanded(
            child: state.isLoading && state.scripts.isEmpty
                ? const Center(child: OrbitLoadingIndicator(size: 32))
                : state.filteredScripts.isEmpty
                    ? _buildEmptyState()
                    : RefreshIndicator(
                        color: Colors.white,
                        backgroundColor: OrbitColors.orbitSurface,
                        onRefresh: () => controller.loadScripts(),
                        child: ListView.separated(
                          padding: const EdgeInsets.all(16),
                          itemCount: state.filteredScripts.length,
                          separatorBuilder: (ctx, i) => const SizedBox(height: 10),
                          itemBuilder: (context, index) {
                            final script = state.filteredScripts[index];
                            return _buildScriptCard(script, controller);
                          },
                        ),
                      ),
          ),
        ],
      ),
    );
  }

  Widget _buildScopeFilterChip(
    String filter,
    String label,
    ScriptsState state,
    ScriptsController controller,
  ) {
    final isSelected = state.scopeFilter == filter;
    return InkWell(
      onTap: () => controller.setScopeFilter(filter),
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF222222) : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: isSelected ? Colors.white30 : OrbitColors.orbitBorder,
            width: 0.8,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11.5,
            fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
            color: isSelected ? Colors.white : OrbitColors.orbitTextMuted,
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: const BoxDecoration(
                color: Color(0xFF141414),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.code_rounded, size: 26, color: OrbitColors.orbitTextMuted),
            ),
            const SizedBox(height: 16),
            const Text(
              'No scripts yet',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'Save commands you use often\nand run them from Orbit whenever you need.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12.5,
                color: OrbitColors.orbitTextMuted,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 20),
            OrbitButton(
              text: '+ New Script',
              onPressed: () => _openEditorSheet(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildScriptCard(Script script, ScriptsController controller) {
    return OrbitCard(
      padding: const EdgeInsets.all(12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Run Action Button
          Material(
            color: const Color(0xFF16251C),
            borderRadius: BorderRadius.circular(8),
            child: InkWell(
              onTap: () => _runScript(script),
              borderRadius: BorderRadius.circular(8),
              child: Container(
                width: 40,
                height: 40,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFF1D5A36)),
                ),
                child: const Icon(
                  Icons.play_arrow_rounded,
                  color: Color(0xFF10B981),
                  size: 22,
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),

          // Script Info
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        script.name,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 6),
                    // Scope tag
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: script.isGlobal
                            ? const Color(0xFF1A1A1A)
                            : const Color(0xFF0C2436),
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(
                          color: script.isGlobal
                              ? OrbitColors.orbitBorder
                              : const Color(0xFF1E4968),
                        ),
                      ),
                      child: Text(
                        script.isGlobal
                            ? 'GLOBAL'
                            : (script.projectPath?.split('/').where((s) => s.isNotEmpty).lastOrNull ?? 'PROJECT').toUpperCase(),
                        style: TextStyle(
                          fontSize: 9,
                          fontFamily: 'monospace',
                          fontWeight: FontWeight.bold,
                          color: script.isGlobal ? OrbitColors.orbitTextMuted : const Color(0xFF38BDF8),
                        ),
                      ),
                    ),
                  ],
                ),

                if (script.description != null && script.description!.isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text(
                    script.description!,
                    style: const TextStyle(
                      fontSize: 12,
                      color: OrbitColors.orbitTextMuted,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],

                const SizedBox(height: 4),
                // Working directory / command preview
                Text(
                  script.workingDirectory != null
                      ? 'dir: ${script.workingDirectory}'
                      : 'cmd: ${script.content.split('\n').first}',
                  style: const TextStyle(
                    fontSize: 10.5,
                    fontFamily: 'monospace',
                    color: OrbitColors.orbitTextSecondary,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),

          // More Options (Edit / Delete)
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert, size: 18, color: OrbitColors.orbitTextMuted),
            color: OrbitColors.orbitSurface,
            onSelected: (val) {
              if (val == 'edit') {
                _openEditorSheet(script);
              } else if (val == 'delete') {
                _confirmDelete(script, controller);
              }
            },
            itemBuilder: (_) => [
              const PopupMenuItem(
                value: 'edit',
                child: Row(
                  children: [
                    Icon(Icons.edit_outlined, size: 16, color: Colors.white70),
                    SizedBox(width: 8),
                    Text('Edit', style: TextStyle(color: Colors.white, fontSize: 13)),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'delete',
                child: Row(
                  children: [
                    Icon(Icons.delete_outline, size: 16, color: Color(0xFFF87171)),
                    SizedBox(width: 8),
                    Text('Delete', style: TextStyle(color: Color(0xFFF87171), fontSize: 13)),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _confirmDelete(Script script, ScriptsController controller) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: OrbitColors.orbitSurface,
        title: const Text('Delete Script', style: TextStyle(color: Colors.white, fontSize: 16)),
        content: Text(
          'Are you sure you want to delete "${script.name}"?',
          style: const TextStyle(color: OrbitColors.orbitTextMuted, fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel', style: TextStyle(color: Colors.white70)),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              controller.deleteScript(script.id);
            },
            child: const Text('Delete', style: TextStyle(color: Color(0xFFF87171))),
          ),
        ],
      ),
    );
  }
}

class _ScriptEditorSheet extends StatefulWidget {
  final Script? script;
  final String? defaultProjectPath;
  final Future<void> Function(ScriptInput) onSave;

  const _ScriptEditorSheet({
    this.script,
    this.defaultProjectPath,
    required this.onSave,
  });

  @override
  State<_ScriptEditorSheet> createState() => _ScriptEditorSheetState();
}

class _ScriptEditorSheetState extends State<_ScriptEditorSheet> {
  late final TextEditingController _nameController;
  late final TextEditingController _descController;
  late final TextEditingController _contentController;
  late final TextEditingController _cwdController;
  late final TextEditingController _projectController;
  late bool _isGlobal;
  bool _isSaving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final s = widget.script;
    _nameController = TextEditingController(text: s?.name ?? '');
    _descController = TextEditingController(text: s?.description ?? '');
    _contentController = TextEditingController(text: s?.content ?? '');
    _cwdController = TextEditingController(text: s?.workingDirectory ?? '');
    _projectController = TextEditingController(
      text: s?.projectPath ?? widget.defaultProjectPath ?? '',
    );
    _isGlobal = s != null ? s.isGlobal : (widget.defaultProjectPath == null);
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descController.dispose();
    _contentController.dispose();
    _cwdController.dispose();
    _projectController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final name = _nameController.text.trim();
    final content = _contentController.text.trim();

    if (name.isEmpty) {
      setState(() => _error = 'Please enter a script name.');
      return;
    }
    if (content.isEmpty) {
      setState(() => _error = 'Script content cannot be empty.');
      return;
    }

    setState(() {
      _isSaving = true;
      _error = null;
    });

    final input = ScriptInput(
      id: widget.script?.id,
      name: name,
      description: _descController.text.trim().isEmpty ? null : _descController.text.trim(),
      content: _contentController.text,
      workingDirectory: _cwdController.text.trim().isEmpty ? null : _cwdController.text.trim(),
      projectPath: _isGlobal ? null : (_projectController.text.trim().isEmpty ? null : _projectController.text.trim()),
    );

    await widget.onSave(input);
    if (mounted) {
      setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF0F0F0F),
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
        border: Border(
          top: BorderSide(color: OrbitColors.orbitBorder, width: 1),
        ),
      ),
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 16,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Handle bar
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: OrbitColors.orbitBorder,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 14),

            // Header
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  widget.script == null ? 'New Script' : 'Edit Script',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close, size: 18, color: OrbitColors.orbitTextMuted),
                  onPressed: () => Navigator.pop(context),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
              ],
            ),
            const SizedBox(height: 12),

            if (_error != null) ...[
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0xFF3B1212),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.error_outline, size: 15, color: Color(0xFFF87171)),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _error!,
                        style: const TextStyle(color: Color(0xFFF87171), fontSize: 12),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
            ],

            // Script Name
            _buildFieldLabel('SCRIPT NAME'),
            _buildTextField(
              controller: _nameController,
              hint: 'e.g. Build APK, Run Tests, DB Migrate',
            ),
            const SizedBox(height: 12),

            // Description
            _buildFieldLabel('DESCRIPTION (OPTIONAL)'),
            _buildTextField(
              controller: _descController,
              hint: 'What does this script do?',
            ),
            const SizedBox(height: 12),

            // Scope toggle
            _buildFieldLabel('SCOPE'),
            Row(
              children: [
                Expanded(
                  child: InkWell(
                    onTap: () => setState(() => _isGlobal = true),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: _isGlobal ? const Color(0xFF222222) : Colors.transparent,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                          color: _isGlobal ? Colors.white : OrbitColors.orbitBorder,
                        ),
                      ),
                      child: Text(
                        'Global',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: _isGlobal ? Colors.white : OrbitColors.orbitTextMuted,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: InkWell(
                    onTap: () => setState(() => _isGlobal = false),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: !_isGlobal ? const Color(0xFF222222) : Colors.transparent,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                          color: !_isGlobal ? Colors.white : OrbitColors.orbitBorder,
                        ),
                      ),
                      child: Text(
                        'Project-Specific',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: !_isGlobal ? Colors.white : OrbitColors.orbitTextMuted,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            if (!_isGlobal) ...[
              _buildFieldLabel('PROJECT PATH'),
              _buildTextField(
                controller: _projectController,
                hint: '/path/to/project',
                isMono: true,
              ),
              const SizedBox(height: 12),
            ],

            // Working Directory
            _buildFieldLabel('WORKING DIRECTORY (OPTIONAL)'),
            _buildTextField(
              controller: _cwdController,
              hint: _isGlobal ? 'Defaults to user home' : 'Defaults to project root',
              isMono: true,
            ),
            const SizedBox(height: 12),

            // Script Content
            _buildFieldLabel('SCRIPT COMMAND(S)'),
            Container(
              decoration: BoxDecoration(
                color: const Color(0xFF050505),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: OrbitColors.orbitBorder),
              ),
              child: TextField(
                controller: _contentController,
                maxLines: 7,
                minLines: 4,
                style: const TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 12.5,
                  color: Color(0xFF38BDF8),
                  height: 1.4,
                ),
                decoration: const InputDecoration(
                  hintText: 'flutter clean\nflutter pub get\nflutter build apk --release',
                  hintStyle: TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 12,
                    color: OrbitColors.orbitTextMuted,
                  ),
                  contentPadding: EdgeInsets.all(10),
                  border: InputBorder.none,
                ),
              ),
            ),
            const SizedBox(height: 20),

            // Actions
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(context),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white70,
                      side: const BorderSide(color: OrbitColors.orbitBorder),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    child: const Text('Cancel'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: _isSaving ? null : _submit,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: Colors.black,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    child: _isSaving
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black),
                          )
                        : Text(
                            widget.script == null ? 'Save Script' : 'Update Script',
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFieldLabel(String label) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text(
        label,
        style: const TextStyle(
          fontSize: 10,
          fontFamily: 'monospace',
          fontWeight: FontWeight.bold,
          letterSpacing: 0.8,
          color: OrbitColors.orbitTextMuted,
        ),
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String hint,
    bool isMono = false,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF050505),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: OrbitColors.orbitBorder),
      ),
      child: TextField(
        controller: controller,
        style: TextStyle(
          fontSize: 13,
          fontFamily: isMono ? 'monospace' : null,
          color: Colors.white,
        ),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: TextStyle(
            fontSize: 12,
            fontFamily: isMono ? 'monospace' : null,
            color: OrbitColors.orbitTextMuted,
          ),
          contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          border: InputBorder.none,
        ),
      ),
    );
  }
}
