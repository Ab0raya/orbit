import 'package:flutter_test/flutter_test.dart';
import 'package:orbit_mobile/protocol/models/project_models.dart';

void main() {
  group('Projects & Git Models Serialization Tests', () {
    test('1. ProjectRoot serialization', () {
      final root = const ProjectRoot(name: 'Workspace', path: '/home/user/orbit');
      final json = root.toJson();
      expect(json['name'], 'Workspace');
      expect(json['path'], '/home/user/orbit');

      final fromJson = ProjectRoot.fromJson(json);
      expect(fromJson.name, 'Workspace');
      expect(fromJson.path, '/home/user/orbit');
    });

    test('2. ProjectSummary serialization (Git and non-Git)', () {
      final gitProj = const ProjectSummary(
        name: 'orbit',
        path: '/home/user/orbit',
        kind: 'git',
        projectType: 'rust',
        git: ProjectGitSummary(branch: 'main', isDirty: true),
      );

      final gitJson = gitProj.toJson();
      expect(gitJson['kind'], 'git');
      expect(gitJson['git']['branch'], 'main');
      expect(gitJson['git']['isDirty'], true);

      final fromGitJson = ProjectSummary.fromJson(gitJson);
      expect(fromGitJson.isGit, isTrue);
      expect(fromGitJson.git?.branch, 'main');
      expect(fromGitJson.git?.isDirty, isTrue);

      final nonGit = const ProjectSummary(
        name: 'simple-notes',
        path: '/home/user/notes',
        kind: 'directory',
        projectType: 'generic',
      );
      expect(nonGit.isGit, isFalse);
      expect(nonGit.git, isNull);
    });

    test('3. GitStatus serialization and counters', () {
      final status = const GitStatus(
        branch: 'feature/projects',
        clean: false,
        staged: [
          GitFileChange(path: 'lib/main.dart', status: 'modified'),
          GitFileChange(path: 'README.md', status: 'added'),
        ],
        unstaged: [
          GitFileChange(path: 'pubspec.yaml', status: 'modified'),
        ],
        untracked: [
          GitFileChange(path: 'notes.txt', status: 'untracked'),
        ],
      );

      expect(status.totalChanges, 4);
      expect(status.staged.length, 2);
      expect(status.unstaged.length, 1);
      expect(status.untracked.length, 1);

      final json = status.toJson();
      final fromJson = GitStatus.fromJson(json);
      expect(fromJson.branch, 'feature/projects');
      expect(fromJson.clean, isFalse);
      expect(fromJson.staged[0].path, 'lib/main.dart');
      expect(fromJson.staged[1].status, 'added');
      expect(fromJson.untracked[0].path, 'notes.txt');
    });

    test('4. GitBranches serialization', () {
      final branches = const GitBranches(
        current: 'main',
        local: ['main', 'feature/login', 'develop'],
        remote: ['origin/main', 'origin/develop'],
      );

      final json = branches.toJson();
      final fromJson = GitBranches.fromJson(json);

      expect(fromJson.current, 'main');
      expect(fromJson.local.length, 3);
      expect(fromJson.remote.length, 2);
      expect(fromJson.local.contains('feature/login'), isTrue);
    });

    test('5. GitCommit and GitCommitResult serialization', () {
      final commitRes = const GitCommitResult(
        hash: 'a1b2c3d4e5f6',
        branch: 'main',
        message: 'Feat: Add project models',
      );
      final resJson = commitRes.toJson();
      expect(resJson['hash'], 'a1b2c3d4e5f6');

      final commit = const GitCommit(
        hash: 'a1b2c3d4e5f6',
        shortHash: 'a1b2c3d',
        message: 'Initial commit',
        author: 'Orbit Developer',
        timestamp: 1725400000,
      );
      final json = commit.toJson();
      final fromJson = GitCommit.fromJson(json);

      expect(fromJson.shortHash, 'a1b2c3d');
      expect(fromJson.author, 'Orbit Developer');
      expect(fromJson.timestamp, 1725400000);
    });

    test('6. ProjectInfo with nested GitStatus', () {
      final info = const ProjectInfo(
        name: 'orbit',
        path: '/home/user/orbit',
        kind: 'git',
        projectType: 'rust',
        git: GitStatus(branch: 'main', clean: true),
      );

      final json = info.toJson();
      final fromJson = ProjectInfo.fromJson(json);

      expect(fromJson.name, 'orbit');
      expect(fromJson.projectType, 'rust');
      expect(fromJson.git?.clean, isTrue);
    });
  });
}
