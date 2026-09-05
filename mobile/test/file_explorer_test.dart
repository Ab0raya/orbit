import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orbit_mobile/core/networking/orbit_websocket_client.dart';
import 'package:orbit_mobile/core/providers.dart';
import 'package:orbit_mobile/features/files/controllers/file_explorer_controller.dart';
import 'package:orbit_mobile/features/files/views/file_explorer_screen.dart';
import 'package:orbit_mobile/features/files/widgets/file_entry_tile.dart';
import 'package:orbit_mobile/features/files/widgets/file_path_bar.dart';
import 'package:orbit_mobile/core/storage/local_storage.dart';
import 'package:orbit_mobile/protocol/messages/orbit_response.dart';
import 'package:orbit_mobile/protocol/models/file_models.dart';

class MockFileExplorerWebSocketClient extends OrbitWebSocketClient {
  List<Map<String, dynamic>>? customEntries;
  List<Map<String, dynamic>>? customSearchResults;

  MockFileExplorerWebSocketClient({
    this.customEntries,
    this.customSearchResults,
  });

  @override
  Future<OrbitResponse> sendRequest(
    String action, {
    Map<String, dynamic>? payload,
    Duration timeout = const Duration(seconds: 10),
  }) async {
    if (action == 'files.roots') {
      return OrbitResponse(
        id: '1',
        action: action,
        success: true,
        payload: {
          'roots': [
            {'name': 'Home', 'path': '/home/aburaya'}
          ]
        },
      );
    } else if (action == 'files.list') {
      return OrbitResponse(
        id: '2',
        action: action,
        success: true,
        payload: {
          'path': payload?['path'] ?? '/home/aburaya',
          'entries': customEntries ?? [
            {
              'name': 'Antigravity',
              'path': '${payload?['path'] ?? '/home/aburaya'}/Antigravity',
              'kind': 'directory',
              'size': 0,
              'modifiedAt': 1788500000,
              'hidden': false,
            },
          ],
        },
      );
    } else if (action == 'files.search') {
      final results = customSearchResults ?? [];
      return OrbitResponse(
        id: '3',
        action: action,
        success: true,
        payload: {
          'root': payload?['root'] ?? '/home/aburaya',
          'query': payload?['query'] ?? '',
          'mode': payload?['mode'] ?? 'name',
          'totalMatches': results.length,
          'truncated': false,
          'results': results,
        },
      );
    }
    return OrbitResponse(
      id: '99',
      action: action,
      success: true,
      payload: {},
    );
  }
}

class MockFileStorage implements ILocalStorage {
  bool showHidden = false;

  @override
  Future<bool> getShowHiddenFiles() async => showHidden;

  @override
  Future<void> saveShowHiddenFiles(bool show) async {
    showHidden = show;
  }

  @override
  Future<void> clearPairedDevice() async {}

  @override
  Future<String> getOrCreateInstallationDeviceId() async => 'test-device-id';

  @override
  Future<PairedDeviceRecord?> getPairedDevice() async => null;

  @override
  Future<Map<String, dynamic>?> getRecentConnection() async => null;

  @override
  Future<void> savePairedDevice(PairedDeviceRecord record) async {}

  @override
  Future<void> saveRecentConnection(String host, int port) async {}
}

void main() {
  group('File Models', () {
    test('FileEntry parses correctly and formats size', () {
      final fileJson = {
        'name': 'main.dart',
        'path': '/project/lib/main.dart',
        'kind': 'file',
        'size': 2048,
        'modifiedAt': 1788470000,
        'hidden': false,
      };

      final file = FileEntry.fromJson(fileJson);
      expect(file.name, 'main.dart');
      expect(file.path, '/project/lib/main.dart');
      expect(file.isFile, true);
      expect(file.isDirectory, false);
      expect(file.size, 2048);
      expect(file.formattedSize, '2.0 KB');
      expect(file.hidden, false);

      final dirJson = {
        'name': 'src',
        'path': '/project/src',
        'kind': 'directory',
        'size': 0,
        'hidden': false,
      };
      final dir = FileEntry.fromJson(dirJson);
      expect(dir.isDirectory, true);
      expect(dir.isFile, false);
      expect(dir.formattedSize, 'Folder');
    });

    test('FileListResponse parses directory entries correctly', () {
      final json = {
        'path': '/workspace',
        'entries': [
          {
            'name': 'build',
            'path': '/workspace/build',
            'kind': 'directory',
            'size': 0,
            'hidden': false,
          },
          {
            'name': 'README.md',
            'path': '/workspace/README.md',
            'kind': 'file',
            'size': 512,
            'hidden': false,
          },
        ],
      };

      final res = FileListResponse.fromJson(json);
      expect(res.path, '/workspace');
      expect(res.entries.length, 2);
      expect(res.entries[0].name, 'build');
      expect(res.entries[1].name, 'README.md');
      expect(res.entries[1].formattedSize, '512 B');
    });

    test('FileReadResponse and FileWriteResponse roundtrip', () {
      final readJson = {
        'path': '/home/user/notes.txt',
        'content': 'Hello from Orbit Desktop\nLine 2',
        'encoding': 'utf8',
        'size': 32,
      };

      final readRes = FileReadResponse.fromJson(readJson);
      expect(readRes.path, '/home/user/notes.txt');
      expect(readRes.content, contains('Hello from Orbit'));
      expect(readRes.encoding, 'utf8');
      expect(readRes.size, 32);

      final writeJson = {
        'path': '/home/user/notes.txt',
        'size': 32,
        'success': true,
      };

      final writeRes = FileWriteResponse.fromJson(writeJson);
      expect(writeRes.path, '/home/user/notes.txt');
      expect(writeRes.size, 32);
      expect(writeRes.success, true);
    });

    test('FileRoot parses correctly', () {
      final json = {
        'name': 'Home',
        'path': '/home/user',
      };
      final root = FileRoot.fromJson(json);
      expect(root.name, 'Home');
      expect(root.path, '/home/user');
      expect(root.toJson()['name'], 'Home');
    });
  });

  group('FileExplorerState', () {
    test('Default state and copyWith works properly', () {
      const state = FileExplorerState();
      expect(state.currentPath, '');
      expect(state.isLoading, false);
      expect(state.errorMessage, isNull);
      expect(state.entries, isEmpty);

      final updated = state.copyWith(
        currentPath: '/home/user/orbit',
        isLoading: true,
        errorMessage: 'Network timeout',
      );

      expect(updated.currentPath, '/home/user/orbit');
      expect(updated.isLoading, true);
      expect(updated.errorMessage, 'Network timeout');

      final cleared = updated.copyWith(clearError: true, isLoading: false);
      expect(cleared.errorMessage, isNull);
      expect(cleared.isLoading, false);
      expect(cleared.currentPath, '/home/user/orbit');
    });
  });

  group('Copy Directory Path Widgets', () {
    testWidgets('FilePathBar invokes onCopyPath when copy button is tapped', (tester) async {
      bool copied = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: FilePathBar(
              currentPath: '/home/user/orbit/mobile',
              onNavigateUp: () {},
              onRefresh: () {},
              onCreateFolder: () {},
              onCopyPath: () {
                copied = true;
              },
            ),
          ),
        ),
      );

      expect(find.text('/home/user/orbit/mobile'), findsOneWidget);
      final copyButton = find.byTooltip('Copy Directory Path');
      expect(copyButton, findsOneWidget);

      await tester.tap(copyButton);
      await tester.pump();
      expect(copied, isTrue);
    });

    testWidgets('FilePathBar invokes onCopyPath when path text is tapped', (tester) async {
      bool copied = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: FilePathBar(
              currentPath: '/home/user/orbit/mobile',
              onNavigateUp: () {},
              onRefresh: () {},
              onCreateFolder: () {},
              onCopyPath: () {
                copied = true;
              },
            ),
          ),
        ),
      );

      await tester.tap(find.text('/home/user/orbit/mobile'));
      await tester.pump();
      expect(copied, isTrue);
    });

    testWidgets('FileEntryTile provides Copy Directory Path in popup menu for directories', (tester) async {
      bool copied = false;
      final dirEntry = FileEntry.fromJson({
        'name': 'src',
        'path': '/home/user/orbit/src',
        'kind': 'directory',
        'size': 0,
        'hidden': false,
      });

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: FileEntryTile(
              entry: dirEntry,
              onTap: () {},
              onRename: () {},
              onDelete: () {},
              onCopyPath: () {
                copied = true;
              },
            ),
          ),
        ),
      );

      // Open popup menu
      await tester.tap(find.byIcon(Icons.more_vert));
      await tester.pumpAndSettle();

      expect(find.text('Copy Directory Path'), findsOneWidget);
      await tester.tap(find.text('Copy Directory Path'));
      await tester.pumpAndSettle();

      expect(copied, isTrue);
    });

    testWidgets('FileEntryTile invokes onCopyPath on long press', (tester) async {
      bool copied = false;
      final dirEntry = FileEntry.fromJson({
        'name': 'src',
        'path': '/home/user/orbit/src',
        'kind': 'directory',
        'size': 0,
        'hidden': false,
      });

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: FileEntryTile(
              entry: dirEntry,
              onTap: () {},
              onRename: () {},
              onDelete: () {},
              onCopyPath: () {
                copied = true;
              },
            ),
          ),
        ),
      );

      await tester.longPress(find.text('src'));
      await tester.pump();

      expect(copied, isTrue);
    });
  });

  group('Back Navigation Tests', () {
    testWidgets('FilePathBar renders arrow_back_rounded navigate back button and calls onNavigateUp when tapped', (tester) async {
      bool navigatedUp = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: FilePathBar(
              currentPath: '/home/aburaya/.config',
              onNavigateUp: () {
                navigatedUp = true;
              },
              onRefresh: () {},
              onCreateFolder: () {},
            ),
          ),
        ),
      );

      final backButton = find.byIcon(Icons.arrow_back_rounded);
      expect(backButton, findsOneWidget);
      expect(find.byTooltip('Navigate back to parent directory'), findsOneWidget);

      await tester.tap(backButton);
      await tester.pump();
      expect(navigatedUp, isTrue);
    });

    testWidgets('FilePathBar renders home_outlined root button when onGoHome is provided and calls onGoHome', (tester) async {
      bool wentHome = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: FilePathBar(
              currentPath: '/home/aburaya/.config',
              onNavigateUp: () {},
              onRefresh: () {},
              onCreateFolder: () {},
              onGoHome: () {
                wentHome = true;
              },
            ),
          ),
        ),
      );

      final homeButton = find.byIcon(Icons.home_outlined);
      expect(homeButton, findsOneWidget);
      expect(find.byTooltip('Go to root directory'), findsOneWidget);

      await tester.tap(homeButton);
      await tester.pump();
      expect(wentHome, isTrue);
    });

    testWidgets('FileExplorerScreen renders back button in AppBar when onBack is provided and calls onBack', (tester) async {
      bool backCalled = false;
      final mockClient = MockFileExplorerWebSocketClient();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            webSocketClientProvider.overrideWithValue(mockClient),
          ],
          child: MaterialApp(
            home: FileExplorerScreen(
              onBack: () {
                backCalled = true;
              },
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      final backButton = find.byTooltip('Back');
      expect(backButton, findsOneWidget);
      expect(find.byIcon(Icons.arrow_back), findsOneWidget);

      await tester.tap(backButton);
      await tester.pump();

      expect(backCalled, isTrue);
    });

    testWidgets('FileExplorerScreen pushed via Navigator renders back button and pops on tap', (tester) async {
      final mockClient = MockFileExplorerWebSocketClient();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            webSocketClientProvider.overrideWithValue(mockClient),
          ],
          child: MaterialApp(
            home: Builder(
              builder: (context) => Scaffold(
                body: ElevatedButton(
                  onPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const FileExplorerScreen(
                          initialPath: '/home/aburaya',
                        ),
                      ),
                    );
                  },
                  child: const Text('Open Files'),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Tap Open Files
      await tester.tap(find.text('Open Files'));
      await tester.pumpAndSettle();

      expect(find.text('ORBIT / FILES'), findsOneWidget);
      final backButton = find.byTooltip('Back');
      expect(backButton, findsOneWidget);

      // Tap back button
      await tester.tap(backButton);
      await tester.pumpAndSettle();

      // Should be popped back to home screen with 'Open Files' button
      expect(find.text('Open Files'), findsOneWidget);
      expect(find.text('ORBIT / FILES'), findsNothing);
    });
  });

  group('Show Hidden Files Preference', () {
    test('isHiddenEntryName correctly identifies hidden files vs normal files and dot parents', () {
      expect(isHiddenEntryName('.'), isFalse);
      expect(isHiddenEntryName('..'), isFalse);
      expect(isHiddenEntryName('.orbit'), isTrue);
      expect(isHiddenEntryName('.pi'), isTrue);
      expect(isHiddenEntryName('.pkl'), isTrue);
      expect(isHiddenEntryName('.pub-cache'), isTrue);
      expect(isHiddenEntryName('.rustup'), isTrue);
      expect(isHiddenEntryName('.git'), isTrue);
      expect(isHiddenEntryName('.env'), isTrue);
      expect(isHiddenEntryName('src'), isFalse);
      expect(isHiddenEntryName('main.dart'), isFalse);
      expect(isHiddenEntryName('orbit.yaml'), isFalse);
    });

    test('isSearchResultHidden correctly identifies entries under hidden directories', () {
      final normalItem = SearchFileResult(
        name: 'main.dart',
        path: '/home/aburaya/project/main.dart',
        isDirectory: false,
      );
      final dotFileItem = SearchFileResult(
        name: '.env',
        path: '/home/aburaya/project/.env',
        isDirectory: false,
      );
      final insideDotDirItem = SearchFileResult(
        name: 'config.json',
        path: '/home/aburaya/project/.orbit/config.json',
        isDirectory: false,
      );

      expect(isSearchResultHidden(normalItem, searchRoot: '/home/aburaya/project'), isFalse);
      expect(isSearchResultHidden(dotFileItem, searchRoot: '/home/aburaya/project'), isTrue);
      expect(isSearchResultHidden(insideDotDirItem, searchRoot: '/home/aburaya/project'), isTrue);
      // When already rooted inside a hidden dir, sub items not starting with dot are not hidden
      expect(isSearchResultHidden(insideDotDirItem, searchRoot: '/home/aburaya/project/.orbit'), isFalse);
    });

    test('FileExplorerState.entries dynamically filters raw entries based on showHiddenFiles', () {
      final raw = <FileEntry>[
        const FileEntry(name: '.', path: '/test/.', kind: 'directory', size: 0, hidden: true),
        const FileEntry(name: '..', path: '/test/..', kind: 'directory', size: 0, hidden: true),
        const FileEntry(name: '.orbit', path: '/test/.orbit', kind: 'directory', size: 0, hidden: true),
        const FileEntry(name: '.pi', path: '/test/.pi', kind: 'directory', size: 0, hidden: true),
        const FileEntry(name: '.pkl', path: '/test/.pkl', kind: 'directory', size: 0, hidden: true),
        const FileEntry(name: '.pub-cache', path: '/test/.pub-cache', kind: 'directory', size: 0, hidden: true),
        const FileEntry(name: '.rustup', path: '/test/.rustup', kind: 'directory', size: 0, hidden: true),
        const FileEntry(name: 'src', path: '/test/src', kind: 'directory', size: 0, hidden: false),
        const FileEntry(name: 'main.dart', path: '/test/main.dart', kind: 'file', size: 100, hidden: false),
      ];

      // Default: showHiddenFiles == false
      final stateHidden = FileExplorerState(rawEntries: raw, showHiddenFiles: false);
      final namesHidden = stateHidden.entries.map((e) => e.name).toList();
      expect(namesHidden, ['src', 'main.dart']);
      expect(namesHidden.contains('.orbit'), isFalse);
      expect(namesHidden.contains('.pi'), isFalse);
      expect(namesHidden.contains('.pkl'), isFalse);
      expect(namesHidden.contains('.pub-cache'), isFalse);
      expect(namesHidden.contains('.rustup'), isFalse);
      expect(namesHidden.contains('.'), isFalse);
      expect(namesHidden.contains('..'), isFalse);

      // Enabled: showHiddenFiles == true
      final stateVisible = stateHidden.copyWith(showHiddenFiles: true);
      final namesVisible = stateVisible.entries.map((e) => e.name).toList();
      expect(namesVisible, [
        '.orbit',
        '.pi',
        '.pkl',
        '.pub-cache',
        '.rustup',
        'src',
        'main.dart',
      ]);
      expect(namesVisible.contains('.'), isFalse);
      expect(namesVisible.contains('..'), isFalse);
    });

    test('ShowHiddenFilesNotifier persists to ILocalStorage and restores correctly', () async {
      final storage = MockFileStorage();
      expect(await storage.getShowHiddenFiles(), isFalse);

      final notifier = ShowHiddenFilesNotifier(storage);
      expect(notifier.state, isFalse);

      await notifier.toggle();
      expect(notifier.state, isTrue);
      expect(await storage.getShowHiddenFiles(), isTrue);

      // New notifier with same storage restores choice
      final restoredNotifier = ShowHiddenFilesNotifier(storage);
      await pumpEventQueue();
      expect(restoredNotifier.state, isTrue);

      await restoredNotifier.setShowHiddenFiles(false);
      expect(restoredNotifier.state, isFalse);
      expect(await storage.getShowHiddenFiles(), isFalse);
    });

    test('FileExplorerController searchFiles filters out hidden items when showHiddenFiles is false', () async {
      final mockClient = MockFileExplorerWebSocketClient(
        customSearchResults: [
          {
            'name': 'normal.dart',
            'path': '/home/aburaya/normal.dart',
            'kind': 'file',
            'size': 120,
            'modifiedAt': 12345,
          },
          {
            'name': '.secret',
            'path': '/home/aburaya/.secret',
            'kind': 'file',
            'size': 80,
            'modifiedAt': 12345,
          },
          {
            'name': 'nested.txt',
            'path': '/home/aburaya/.orbit/nested.txt',
            'kind': 'file',
            'size': 60,
            'modifiedAt': 12345,
          },
        ],
      );

      final controller = FileExplorerController(mockClient, showHidden: false);
      controller.state = controller.state.copyWith(currentPath: '/home/aburaya');

      // Search with hidden files OFF
      final searchResOff = await controller.searchFiles('test', 'name');
      expect(searchResOff, isNotNull);
      expect(searchResOff!.results.length, 1);
      expect(searchResOff.results.first.name, 'normal.dart');

      // Toggle ON
      controller.setShowHiddenFiles(true);
      final searchResOn = await controller.searchFiles('test', 'name');
      expect(searchResOn, isNotNull);
      expect(searchResOn!.results.length, 3);
    });

    testWidgets('FileExplorerScreen renders compact Hidden toggle and toggles hidden files in UI', (tester) async {
      final mockClient = MockFileExplorerWebSocketClient(
        customEntries: [
          {
            'name': 'src',
            'path': '/home/aburaya/src',
            'kind': 'directory',
            'size': 0,
            'modifiedAt': 1788500000,
            'hidden': false,
          },
          {
            'name': '.orbit',
            'path': '/home/aburaya/.orbit',
            'kind': 'directory',
            'size': 0,
            'modifiedAt': 1788500000,
            'hidden': true,
          },
          {
            'name': '.rustup',
            'path': '/home/aburaya/.rustup',
            'kind': 'directory',
            'size': 0,
            'modifiedAt': 1788500000,
            'hidden': true,
          },
        ],
      );

      final storage = MockFileStorage();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            webSocketClientProvider.overrideWithValue(mockClient),
            localStorageProvider.overrideWithValue(storage),
          ],
          child: const MaterialApp(
            home: FileExplorerScreen(initialPath: '/home/aburaya'),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Verify compact hidden toggle exists
      expect(find.byKey(const Key('toggle_show_hidden_files')), findsOneWidget);
      expect(find.byKey(const Key('switch_show_hidden_files')), findsOneWidget);
      expect(find.text('Hidden'), findsOneWidget);

      // Default: OFF -> normal dir visible, hidden dirs NOT visible
      expect(find.text('src'), findsOneWidget);
      expect(find.text('.orbit'), findsNothing);
      expect(find.text('.rustup'), findsNothing);

      // Tap toggle to enable Show Hidden Files
      await tester.tap(find.byKey(const Key('toggle_show_hidden_files')));
      await tester.pumpAndSettle();

      // Now hidden entries appear
      expect(find.text('src'), findsOneWidget);
      expect(find.text('.orbit'), findsOneWidget);
      expect(find.text('.rustup'), findsOneWidget);
      expect(await storage.getShowHiddenFiles(), isTrue);

      // Tap toggle again to disable
      await tester.tap(find.byKey(const Key('toggle_show_hidden_files')));
      await tester.pumpAndSettle();

      // Hidden entries disappear again
      expect(find.text('src'), findsOneWidget);
      expect(find.text('.orbit'), findsNothing);
      expect(find.text('.rustup'), findsNothing);
      expect(await storage.getShowHiddenFiles(), isFalse);
    });
  });
}
