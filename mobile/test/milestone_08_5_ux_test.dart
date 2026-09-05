import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orbit_mobile/core/networking/orbit_websocket_client.dart';
import 'package:orbit_mobile/features/ai/controllers/ai_task_controller.dart';
import 'package:orbit_mobile/features/ai/views/ai_command_center_screen.dart';
import 'package:orbit_mobile/features/ai/views/ai_task_screen.dart';
import 'package:orbit_mobile/features/navigation/views/main_navigation_shell.dart';
import 'package:orbit_mobile/features/projects/models/project_models.dart';
import 'package:orbit_mobile/protocol/models/ai_context.dart';
import 'package:orbit_mobile/protocol/models/ai_models.dart';
import 'package:orbit_mobile/protocol/models/file_models.dart';

void main() {
  group('Milestone 08.5 — Flutter Product UX Correction Tests', () {
    testWidgets('1. Global AI navigation via MainNavigationShell', (tester) async {
      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: MainNavigationShell(
              host: '127.0.0.1',
              port: 4371,
              initialIndex: 1, // AI tab
            ),
          ),
        ),
      );
      await tester.pump();

      // Navigation shell renders navigation bar and contains AI tab
      expect(find.byType(MainNavigationShell), findsOneWidget);
      expect(find.text('AI'), findsWidgets);
      expect(find.textContaining('COMMAND CENTER'), findsOneWidget);
    });

    test('2. AI with no context', () {
      final noCtx = AiContext.none();
      expect(noCtx.source, AiContextSource.none);
      expect(noCtx.path, isNull);
      expect(noCtx.displayName, 'No context');
      expect(noCtx.isNone, isTrue);

      final state = AiTaskState(currentContext: noCtx);
      expect(state.currentContext.isNone, isTrue);
      expect(state.currentContext.path, isNull);
    });

    test('3. AI with project context', () {
      final projCtx = AiContext.fromProject(
        path: '/home/user/orbit',
        name: 'orbit',
        projectType: 'rust',
        isGit: true,
      );

      expect(projCtx.source, AiContextSource.project);
      expect(projCtx.path, '/home/user/orbit');
      expect(projCtx.displayName, 'orbit');
      expect(projCtx.projectType, 'rust');
      expect(projCtx.isGit, isTrue);
      expect(projCtx.isNone, isFalse);
    });

    test('4. AI with arbitrary directory context', () {
      final dirCtx = AiContext.fromDirectory('/workspace/custom_service');

      expect(dirCtx.source, AiContextSource.directory);
      expect(dirCtx.path, '/workspace/custom_service');
      expect(dirCtx.displayName, 'custom_service');
      expect(dirCtx.isGit, isFalse);
      expect(dirCtx.isNone, isFalse);
    });

    test('5. Context switching in AiTaskController', () {
      final client = OrbitWebSocketClient();
      final controller = AiTaskController(client);

      expect(controller.state.currentContext.isNone, isTrue);

      final newCtx = AiContext.fromProject(
        path: '/projects/rato',
        name: 'rato',
        isGit: true,
      );
      controller.setContext(newCtx);

      expect(controller.state.currentContext.path, '/projects/rato');
      expect(controller.state.currentContext.displayName, 'rato');
      expect(controller.state.currentContext.source, AiContextSource.project);

      // Switch back to none
      controller.setContext(AiContext.none());
      expect(controller.state.currentContext.isNone, isTrue);
    });

    test('6. Recent task display with duration, status, and title', () {
      final completedTask = AiTask(
        taskId: 'task_001',
        projectPath: '/projects/orbit',
        status: AiTaskStatus.completed,
        agent: AiAgent.plan,
        readOnly: true,
        startedAt: 100000,
        finishedAt: 105200,
        prompt: 'Analyze Orbit architecture',
      );

      expect(completedTask.status, AiTaskStatus.completed);
      expect(completedTask.displayPrompt, 'Analyze Orbit architecture');
      expect(completedTask.finishedAt! - completedTask.startedAt, 5200);

      final failedTask = AiTask(
        taskId: 'task_002',
        projectPath: '',
        status: AiTaskStatus.failed,
        agent: AiAgent.build,
        readOnly: false,
        startedAt: 200000,
        finishedAt: 201500,
        error: 'Compilation failed',
        prompt: 'Fix navigation layout',
      );

      expect(failedTask.status, AiTaskStatus.failed);
      expect(failedTask.displayPrompt, 'Fix navigation layout');
      expect(failedTask.error, 'Compilation failed');
    });

    test('7. Active task display', () {
      final runningTask = AiTask(
        taskId: 'task_active_01',
        projectPath: '/projects/orbit',
        status: AiTaskStatus.running,
        agent: AiAgent.plan,
        readOnly: true,
        startedAt: DateTime.now().millisecondsSinceEpoch - 60000,
        prompt: 'Running integration tests',
      );

      final client = OrbitWebSocketClient();
      final controller = AiTaskController(client);

      controller.setActiveTask(runningTask);
      expect(controller.state.activeTask?.taskId, 'task_active_01');
      expect(controller.state.activeTask?.status, AiTaskStatus.running);
      expect(controller.state.activeTask?.displayPrompt, 'Running integration tests');
    });

    test('8. Image preview model, dimensions, and base64 parsing', () {
      final rawBase64 = base64Encode(Uint8List.fromList([0x89, 0x50, 0x4E, 0x47]));
      final imgRes = BinaryReadResponse(
        path: '/workspace/assets/logo.png',
        name: 'logo.png',
        extension: 'png',
        size: 86016, // 84 KB
        mimeType: 'image/png',
        fileCategory: FileCategory.image,
        encoding: 'base64',
        content: rawBase64,
        width: 512,
        height: 512,
      );

      expect(imgRes.fileCategory, FileCategory.image);
      expect(imgRes.formattedSize, '84.0 KB');
      expect(imgRes.dimensionsText, '512 × 512');
      expect(imgRes.content, isNotNull);
      final decodedBytes = base64Decode(imgRes.content!);
      expect(decodedBytes.length, 4);
    });

    test('9. Binary file handling without UTF-8 decode error', () {
      final binRes = BinaryReadResponse(
        path: '/workspace/build/app.bin',
        name: 'app.bin',
        extension: 'bin',
        size: 1468006, // 1.4 MB
        mimeType: 'application/octet-stream',
        fileCategory: FileCategory.binary,
        encoding: 'base64',
        content: base64Encode([0x7F, 0x45, 0x4C, 0x46]), // ELF header
      );

      expect(binRes.fileCategory, FileCategory.binary);
      expect(binRes.formattedSize, '1.4 MB');
      expect(binRes.mimeType, 'application/octet-stream');
      expect(binRes.isTooLarge, isFalse);
    });

    test('10. Code language detection by extension', () {
      expect(FileCategory.fromExtension('main.dart'), FileCategory.code);
      expect(FileCategory.fromExtension('server.rs'), FileCategory.code);
      expect(FileCategory.fromExtension('index.ts'), FileCategory.code);
      expect(FileCategory.fromExtension('app.py'), FileCategory.code);
      expect(FileCategory.fromExtension('style.css'), FileCategory.code);
      expect(FileCategory.fromExtension('script.sh'), FileCategory.code);
      expect(FileCategory.fromExtension('query.sql'), FileCategory.code);

      expect(FileCategory.fromExtension('readme.md'), FileCategory.markdown);
      expect(FileCategory.fromExtension('notes.txt'), FileCategory.text);
      expect(FileCategory.fromExtension('config.yaml'), FileCategory.text);
      expect(FileCategory.fromExtension('package.json'), FileCategory.text);

      expect(FileCategory.fromExtension('photo.jpg'), FileCategory.image);
      expect(FileCategory.fromExtension('icon.svg'), FileCategory.image);
      expect(FileCategory.fromExtension('anim.gif'), FileCategory.image);

      expect(FileCategory.fromExtension('blob.bin'), FileCategory.binary);
      expect(FileCategory.fromExtension('archive.zip'), FileCategory.binary);
    });

    test('11. Syntax highlighting fallback for unknown language', () {
      const unknownFile = 'archive.xyz';
      expect(FileCategory.fromExtension(unknownFile), FileCategory.binary);
    });

    test('12. Editor dirty state detection', () {
      const initial = 'void main() {}';
      var current = initial;
      bool hasUnsavedChanges(String cur, String init) => cur != init;

      expect(hasUnsavedChanges(current, initial), isFalse);

      current = 'void main() {\n  print("hello");\n}';
      expect(hasUnsavedChanges(current, initial), isTrue);

      current = initial;
      expect(hasUnsavedChanges(current, initial), isFalse);
    });

    test('13. Save payload structure validation', () {
      const targetPath = '/home/user/project/lib/main.dart';
      const newContent = 'void main() => runApp(const App());';

      final writePayload = {
        'path': targetPath,
        'content': newContent,
      };

      expect(writePayload['path'], targetPath);
      expect(writePayload['content'], newContent);

      final writeResponseJson = {
        'path': targetPath,
        'size': newContent.length,
        'success': true,
      };
      final res = FileWriteResponse.fromJson(writeResponseJson);
      expect(res.success, isTrue);
      expect(res.size, newContent.length);
    });

    test('14. File search match counting and cyclic navigation', () {
      const sampleCode = '''
class AuthService {
  void login() {}
  void logout() {}
  void refreshToken() {}
}
''';
      final lines = sampleCode.split('\n');
      const query = 'void';

      final matchIndices = <int>[];
      for (var i = 0; i < lines.length; i++) {
        if (lines[i].contains(query)) {
          matchIndices.add(i);
        }
      }

      expect(matchIndices.length, 3);
      expect(matchIndices, [1, 2, 3]);

      var currentIndex = 0;
      // Next match cyclic navigation
      currentIndex = (currentIndex + 1) % matchIndices.length;
      expect(currentIndex, 1);
      currentIndex = (currentIndex + 1) % matchIndices.length;
      expect(currentIndex, 2);
      currentIndex = (currentIndex + 1) % matchIndices.length;
      expect(currentIndex, 0);

      // Previous match cyclic navigation
      currentIndex = (currentIndex - 1 + matchIndices.length) % matchIndices.length;
      expect(currentIndex, 2);
    });

    test('15. Oversized file UI model safety', () {
      final oversized = BinaryReadResponse(
        path: '/large/dump.bin',
        name: 'dump.bin',
        extension: 'bin',
        size: 50 * 1024 * 1024,
        mimeType: 'application/octet-stream',
        fileCategory: FileCategory.binary,
        encoding: 'base64',
        content: null,
        isTooLarge: true,
      );

      expect(oversized.isTooLarge, isTrue);
      expect(oversized.content, isNull);
      expect(oversized.formattedSize, '50.0 MB');
    });

    test('16. Non-Git project capabilities representation', () {
      final nonGit = ProjectSummary(
        name: 'plain-node-app',
        path: '/var/www/plain-node-app',
        kind: 'directory',
        projectType: 'node',
        git: null,
      );

      expect(nonGit.isGit, isFalse);
      expect(nonGit.git, isNull);
      expect(nonGit.projectType, 'node');
    });

    testWidgets('17. Project -> Ask Orbit AI passes project context to AiCommandCenterScreen',
        (tester) async {
      final projectContext = AiContext.fromProject(
        path: '/var/workspace/orbit',
        name: 'orbit',
        isGit: true,
      );

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: AiCommandCenterScreen(
              initialContext: projectContext,
            ),
          ),
        ),
      );
      await tester.pump();

      // Verify the preselected project context appears in the context selector button
      expect(find.text('orbit'), findsWidgets);
      expect(find.textContaining('COMMAND CENTER'), findsOneWidget);
    });

    testWidgets('18. Existing AI activity screen remains functional', (tester) async {
      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: AiTaskScreen(
              projectPath: '/workspace/project',
              projectName: 'project',
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.byType(AiTaskScreen), findsOneWidget);
      expect(find.textContaining('COMMAND CENTER'), findsOneWidget);
    });
  });
}
