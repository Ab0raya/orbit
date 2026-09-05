import 'package:flutter_test/flutter_test.dart';
import 'package:orbit_mobile/features/scripts/controllers/scripts_controller.dart';
import 'package:orbit_mobile/protocol/models/script_models.dart';

void main() {
  group('Scripts Models & Controller Logic Tests', () {
    test('1. Script model serialization and isGlobal property', () {
      final globalScript = const Script(
        id: 'script-1',
        name: 'Run Tests',
        description: 'Run project test suite',
        content: 'cargo test',
        workingDirectory: '/home/user/orbit',
        projectPath: null,
        createdAt: 1757112000,
        updatedAt: 1757112000,
      );

      expect(globalScript.isGlobal, isTrue);

      final json = globalScript.toJson();
      expect(json['id'], 'script-1');
      expect(json['name'], 'Run Tests');
      expect(json['description'], 'Run project test suite');
      expect(json['content'], 'cargo test');
      expect(json['workingDirectory'], '/home/user/orbit');
      expect(json['projectPath'], isNull);

      final fromJson = Script.fromJson(json);
      expect(fromJson.id, 'script-1');
      expect(fromJson.name, 'Run Tests');
      expect(fromJson.isGlobal, isTrue);

      final projectScript = const Script(
        id: 'script-2',
        name: 'Build Android',
        description: 'Build release APK',
        content: 'flutter build apk',
        workingDirectory: '/home/user/orbit/mobile',
        projectPath: '/home/user/orbit/mobile',
        createdAt: 1757112000,
        updatedAt: 1757112000,
      );

      expect(projectScript.isGlobal, isFalse);
      expect(projectScript.projectPath, '/home/user/orbit/mobile');

      final updated = projectScript.copyWith(name: 'Build Release APK');
      expect(updated.id, 'script-2');
      expect(updated.name, 'Build Release APK');
      expect(updated.content, 'flutter build apk');
    });

    test('2. ScriptInput serialization', () {
      final input = const ScriptInput(
        id: 'sc-123',
        name: 'Custom Script',
        description: 'Runs custom bash',
        content: 'echo hello\nls -la',
        workingDirectory: '/tmp',
        projectPath: null,
      );

      final json = input.toJson();
      expect(json['id'], 'sc-123');
      expect(json['name'], 'Custom Script');
      expect(json['description'], 'Runs custom bash');
      expect(json['content'], 'echo hello\nls -la');
      expect(json['workingDirectory'], '/tmp');
      expect(json.containsKey('projectPath'), isFalse);
    });

    test('3. ScriptsState filtering by search query and scope', () {
      final s1 = const Script(
        id: 's1',
        name: 'Build Android APK',
        description: 'Compile release build',
        content: 'flutter build apk',
        workingDirectory: '/home/user/orbit/mobile',
        projectPath: '/home/user/orbit/mobile',
        createdAt: 100,
        updatedAt: 100,
      );

      final s2 = const Script(
        id: 's2',
        name: 'Run Cargo Tests',
        description: 'Run all Rust tests',
        content: 'cargo test --lib',
        workingDirectory: '/home/user/orbit/src-tauri',
        projectPath: null,
        createdAt: 200,
        updatedAt: 200,
      );

      final s3 = const Script(
        id: 's3',
        name: 'Docker Compose Up',
        description: 'Start dev databases',
        content: 'docker compose up -d',
        workingDirectory: '/home/user/orbit',
        projectPath: null,
        createdAt: 300,
        updatedAt: 300,
      );

      final state = ScriptsState(
        scripts: [s1, s2, s3],
        searchQuery: '',
        scopeFilter: 'all',
      );

      // All scripts
      expect(state.filteredScripts.length, 3);

      // Filter by global scope
      final globalState = state.copyWith(scopeFilter: 'global');
      expect(globalState.filteredScripts.length, 2);
      expect(globalState.filteredScripts.map((s) => s.id), containsAll(['s2', 's3']));

      // Filter by project scope
      final projState = state.copyWith(scopeFilter: 'project');
      expect(projState.filteredScripts.length, 1);
      expect(projState.filteredScripts.first.id, 's1');

      // Filter by search query "cargo"
      final searchState = state.copyWith(searchQuery: 'cargo');
      expect(searchState.filteredScripts.length, 1);
      expect(searchState.filteredScripts.first.id, 's2');

      // Filter by search query in content "docker"
      final searchContentState = state.copyWith(searchQuery: 'docker');
      expect(searchContentState.filteredScripts.length, 1);
      expect(searchContentState.filteredScripts.first.id, 's3');
    });
  });
}
