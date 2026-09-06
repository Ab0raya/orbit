import 'package:flutter/material.dart';

enum TargetOs {
  windows,
  linux,
  macos,
  all;

  static TargetOs fromString(String? os) {
    if (os == null) return TargetOs.linux;
    final lower = os.toLowerCase();
    if (lower.contains('win')) return TargetOs.windows;
    if (lower.contains('mac') || lower.contains('darwin') || lower.contains('apple')) {
      return TargetOs.macos;
    }
    return TargetOs.linux;
  }
}

enum CommandCategory {
  power('Power', Icons.power_settings_new_rounded),
  system('System', Icons.dns_outlined),
  processes('Processes', Icons.memory_rounded),
  network('Network', Icons.wifi_tethering_rounded),
  files('Files', Icons.folder_open_outlined),
  developer('Developer', Icons.code_rounded),
  osSpecific('OS Tools', Icons.build_outlined);

  final String label;
  final IconData icon;
  const CommandCategory(this.label, this.icon);
}

enum CommandExecutionType {
  instant,
  parameterized,
  confirmation,
  powerTimer,
  toggle,
}

enum DangerLevel {
  safe,
  warning,
  destructive,
}

class CommandInputField {
  final String key;
  final String label;
  final String hint;
  final String? defaultValue;
  final bool isNumeric;
  final bool isRequired;

  const CommandInputField({
    required this.key,
    required this.label,
    required this.hint,
    this.defaultValue,
    this.isNumeric = false,
    this.isRequired = true,
  });
}

class CommandTool {
  final String id;
  final String title;
  final String description;
  final CommandCategory category;
  final List<TargetOs> supportedOs;
  final CommandExecutionType executionType;
  final DangerLevel dangerLevel;
  final List<CommandInputField> inputFields;
  final String Function(TargetOs os, Map<String, String> params) commandBuilder;
  final IconData icon;

  const CommandTool({
    required this.id,
    required this.title,
    required this.description,
    required this.category,
    required this.supportedOs,
    required this.executionType,
    this.dangerLevel = DangerLevel.safe,
    this.inputFields = const [],
    required this.commandBuilder,
    this.icon = Icons.terminal_rounded,
  });

  bool isSupportedOn(TargetOs os) {
    return supportedOs.contains(TargetOs.all) || supportedOs.contains(os);
  }

  String buildCommand(TargetOs os, [Map<String, String> params = const {}]) {
    return commandBuilder(os, params);
  }
}

class CommandToolCatalog {
  static List<CommandTool> get tools => builtInCommandTools;
  static List<CommandTool> forOs(TargetOs os) =>
      builtInCommandTools.where((t) => t.isSupportedOn(os)).toList();
}

/// Catalog of all built-in commands tailored for Windows, Linux, and macOS.
final List<CommandTool> builtInCommandTools = [
  // ==========================================
  // POWER CATEGORY
  // ==========================================
  CommandTool(
    id: 'shutdown_timer',
    title: 'Shutdown Computer',
    description: 'Schedule or immediately power off the connected computer.',
    category: CommandCategory.power,
    supportedOs: [TargetOs.windows, TargetOs.linux, TargetOs.macos],
    executionType: CommandExecutionType.powerTimer,
    dangerLevel: DangerLevel.destructive,
    icon: Icons.power_settings_new_rounded,
    commandBuilder: (os, params) {
      final mins = int.tryParse(params['minutes'] ?? '0') ?? 0;
      switch (os) {
        case TargetOs.windows:
          final secs = mins * 60;
          return 'shutdown /s /t $secs';
        case TargetOs.linux:
          return mins == 0 ? 'shutdown now' : 'shutdown +$mins';
        case TargetOs.macos:
          return mins == 0 ? 'sudo shutdown -h now' : 'sudo shutdown -h +$mins';
        case TargetOs.all:
          return mins == 0 ? 'shutdown now' : 'shutdown +$mins';
      }
    },
  ),
  CommandTool(
    id: 'shutdown_cancel',
    title: 'Cancel Scheduled Shutdown',
    description: 'Abort a previously scheduled shutdown or timer.',
    category: CommandCategory.power,
    supportedOs: [TargetOs.windows, TargetOs.linux, TargetOs.macos],
    executionType: CommandExecutionType.instant,
    dangerLevel: DangerLevel.warning,
    icon: Icons.cancel_outlined,
    commandBuilder: (os, _) {
      switch (os) {
        case TargetOs.windows:
          return 'shutdown /a';
        case TargetOs.linux:
          return 'shutdown -c';
        case TargetOs.macos:
          return 'sudo killall shutdown';
        case TargetOs.all:
          return 'shutdown -c';
      }
    },
  ),
  CommandTool(
    id: 'restart_computer',
    title: 'Restart Computer',
    description: 'Reboot the connected operating system.',
    category: CommandCategory.power,
    supportedOs: [TargetOs.windows, TargetOs.linux, TargetOs.macos],
    executionType: CommandExecutionType.confirmation,
    dangerLevel: DangerLevel.destructive,
    icon: Icons.restart_alt_rounded,
    commandBuilder: (os, _) {
      switch (os) {
        case TargetOs.windows:
          return 'shutdown /r /t 0';
        case TargetOs.linux:
          return 'reboot';
        case TargetOs.macos:
          return 'sudo reboot';
        case TargetOs.all:
          return 'reboot';
      }
    },
  ),
  CommandTool(
    id: 'sleep_lock',
    title: 'Sleep / Lock Session',
    description: 'Lock screen or suspend machine session.',
    category: CommandCategory.power,
    supportedOs: [TargetOs.windows, TargetOs.linux, TargetOs.macos],
    executionType: CommandExecutionType.confirmation,
    dangerLevel: DangerLevel.warning,
    icon: Icons.lock_outline_rounded,
    commandBuilder: (os, _) {
      switch (os) {
        case TargetOs.windows:
          return 'rundll32.exe user32.dll,LockWorkStation';
        case TargetOs.linux:
          return 'loginctl lock-session';
        case TargetOs.macos:
          return 'pmset displaysleepnow';
        case TargetOs.all:
          return 'loginctl lock-session';
      }
    },
  ),
  CommandTool(
    id: 'system_suspend',
    title: 'Suspend (Sleep)',
    description: 'Put computer into low-power sleep mode.',
    category: CommandCategory.power,
    supportedOs: [TargetOs.linux, TargetOs.macos],
    executionType: CommandExecutionType.confirmation,
    dangerLevel: DangerLevel.warning,
    icon: Icons.bedtime_outlined,
    commandBuilder: (os, _) {
      switch (os) {
        case TargetOs.macos:
          return 'sudo pmset sleepnow';
        default:
          return 'systemctl suspend';
      }
    },
  ),

  // ==========================================
  // SYSTEM CATEGORY
  // ==========================================
  CommandTool(
    id: 'sysinfo',
    title: 'System Information',
    description: 'Display comprehensive OS, kernel, and hardware information.',
    category: CommandCategory.system,
    supportedOs: [TargetOs.windows, TargetOs.linux, TargetOs.macos],
    executionType: CommandExecutionType.instant,
    icon: Icons.info_outline_rounded,
    commandBuilder: (os, _) {
      switch (os) {
        case TargetOs.windows:
          return 'systeminfo';
        case TargetOs.macos:
          return 'sw_vers && uname -a';
        default:
          return 'uname -a && hostnamectl';
      }
    },
  ),
  CommandTool(
    id: 'uptime',
    title: 'System Uptime',
    description: 'Show how long the system has been running.',
    category: CommandCategory.system,
    supportedOs: [TargetOs.linux, TargetOs.macos, TargetOs.windows],
    executionType: CommandExecutionType.instant,
    icon: Icons.timer_outlined,
    commandBuilder: (os, _) {
      switch (os) {
        case TargetOs.windows:
          return 'net statistics workstation';
        default:
          return 'uptime';
      }
    },
  ),
  CommandTool(
    id: 'cpu_mem_info',
    title: 'Memory & CPU Summary',
    description: 'Display memory usage and CPU processor specification.',
    category: CommandCategory.system,
    supportedOs: [TargetOs.linux, TargetOs.macos],
    executionType: CommandExecutionType.instant,
    icon: Icons.memory_rounded,
    commandBuilder: (os, _) {
      switch (os) {
        case TargetOs.macos:
          return 'sysctl -n machdep.cpu.brand_string && vm_stat';
        default:
          return 'free -h && lscpu';
      }
    },
  ),
  CommandTool(
    id: 'disk_space',
    title: 'Disk Free Space',
    description: 'Report file system disk space usage and partitions.',
    category: CommandCategory.system,
    supportedOs: [TargetOs.windows, TargetOs.linux, TargetOs.macos],
    executionType: CommandExecutionType.instant,
    icon: Icons.storage_rounded,
    commandBuilder: (os, _) {
      switch (os) {
        case TargetOs.windows:
          return 'wmic logicaldisk get caption,volumename,size,freespace';
        case TargetOs.macos:
          return 'df -h && diskutil list';
        default:
          return 'df -h && lsblk';
      }
    },
  ),

  // ==========================================
  // PROCESSES CATEGORY
  // ==========================================
  CommandTool(
    id: 'list_processes',
    title: 'List Running Processes',
    description: 'List active processes with PIDs and resource usage.',
    category: CommandCategory.processes,
    supportedOs: [TargetOs.windows, TargetOs.linux, TargetOs.macos],
    executionType: CommandExecutionType.instant,
    icon: Icons.view_list_rounded,
    commandBuilder: (os, _) {
      switch (os) {
        case TargetOs.windows:
          return 'tasklist';
        default:
          return 'ps aux --sort=-%cpu | head -n 25';
      }
    },
  ),
  CommandTool(
    id: 'kill_pid',
    title: 'Kill Process by PID',
    description: 'Terminate a process by its process ID.',
    category: CommandCategory.processes,
    supportedOs: [TargetOs.windows, TargetOs.linux, TargetOs.macos],
    executionType: CommandExecutionType.parameterized,
    dangerLevel: DangerLevel.destructive,
    inputFields: [
      CommandInputField(
        key: 'pid',
        label: 'Process ID (PID)',
        hint: 'e.g. 12345',
        isNumeric: true,
      ),
    ],
    icon: Icons.close_rounded,
    commandBuilder: (os, params) {
      final pid = params['pid']?.trim() ?? '';
      switch (os) {
        case TargetOs.windows:
          return 'taskkill /PID $pid /F';
        default:
          return 'kill -9 $pid';
      }
    },
  ),
  CommandTool(
    id: 'kill_name',
    title: 'Kill Process by Name',
    description: 'Terminate all processes matching an executable name.',
    category: CommandCategory.processes,
    supportedOs: [TargetOs.windows, TargetOs.linux, TargetOs.macos],
    executionType: CommandExecutionType.parameterized,
    dangerLevel: DangerLevel.destructive,
    inputFields: [
      CommandInputField(
        key: 'name',
        label: 'Process Name',
        hint: 'e.g. node or chrome.exe',
      ),
    ],
    icon: Icons.filter_list_off_rounded,
    commandBuilder: (os, params) {
      final name = params['name']?.trim() ?? '';
      switch (os) {
        case TargetOs.windows:
          final img = name.endsWith('.exe') ? name : '$name.exe';
          return 'taskkill /IM $img /F';
        case TargetOs.macos:
          return 'killall "$name"';
        default:
          return 'pkill -f "$name"';
      }
    },
  ),

  // ==========================================
  // NETWORK CATEGORY
  // ==========================================
  CommandTool(
    id: 'ping_host',
    title: 'Ping Host',
    description: 'Send ICMP echo packets to test network latency.',
    category: CommandCategory.network,
    supportedOs: [TargetOs.windows, TargetOs.linux, TargetOs.macos],
    executionType: CommandExecutionType.parameterized,
    inputFields: [
      CommandInputField(
        key: 'host',
        label: 'Target Host / IP',
        hint: 'e.g. google.com or 1.1.1.1',
        defaultValue: 'google.com',
      ),
    ],
    icon: Icons.swap_vert_rounded,
    commandBuilder: (os, params) {
      final host = params['host']?.trim().isNotEmpty == true
          ? params['host']!.trim()
          : 'google.com';
      switch (os) {
        case TargetOs.windows:
          return 'ping -n 4 $host';
        default:
          return 'ping -c 4 $host';
      }
    },
  ),
  CommandTool(
    id: 'ip_config',
    title: 'Network Interfaces (IP)',
    description: 'Show active network adapters, IP addresses, and gateways.',
    category: CommandCategory.network,
    supportedOs: [TargetOs.windows, TargetOs.linux, TargetOs.macos],
    executionType: CommandExecutionType.instant,
    icon: Icons.language_rounded,
    commandBuilder: (os, _) {
      switch (os) {
        case TargetOs.windows:
          return 'ipconfig /all';
        case TargetOs.macos:
          return 'ifconfig && ipconfig getifaddr en0';
        default:
          return 'ip addr';
      }
    },
  ),
  CommandTool(
    id: 'dns_lookup',
    title: 'DNS Lookup',
    description: 'Query DNS name servers for domain records.',
    category: CommandCategory.network,
    supportedOs: [TargetOs.windows, TargetOs.linux, TargetOs.macos],
    executionType: CommandExecutionType.parameterized,
    inputFields: [
      CommandInputField(
        key: 'domain',
        label: 'Domain Name',
        hint: 'e.g. github.com',
        defaultValue: 'github.com',
      ),
    ],
    icon: Icons.search_rounded,
    commandBuilder: (os, params) {
      final domain = params['domain']?.trim().isNotEmpty == true
          ? params['domain']!.trim()
          : 'github.com';
      switch (os) {
        case TargetOs.windows:
          return 'nslookup $domain';
        default:
          return 'dig +short $domain || nslookup $domain';
      }
    },
  ),
  CommandTool(
    id: 'listening_ports',
    title: 'Listening Ports & Sockets',
    description: 'Display open network ports and listening connections.',
    category: CommandCategory.network,
    supportedOs: [TargetOs.windows, TargetOs.linux, TargetOs.macos],
    executionType: CommandExecutionType.instant,
    icon: Icons.router_outlined,
    commandBuilder: (os, _) {
      switch (os) {
        case TargetOs.windows:
          return 'netstat -ano | findstr LISTENING';
        case TargetOs.macos:
          return 'lsof -i -P -n | grep LISTEN';
        default:
          return 'ss -tulpn';
      }
    },
  ),
  CommandTool(
    id: 'flush_dns',
    title: 'Flush DNS Resolver Cache',
    description: 'Clear the local operating system DNS cache.',
    category: CommandCategory.network,
    supportedOs: [TargetOs.windows, TargetOs.macos],
    executionType: CommandExecutionType.instant,
    dangerLevel: DangerLevel.warning,
    icon: Icons.cleaning_services_rounded,
    commandBuilder: (os, _) {
      switch (os) {
        case TargetOs.windows:
          return 'ipconfig /flushdns';
        case TargetOs.macos:
          return 'sudo dscacheutil -flushcache; sudo killall -HUP mDNSResponder';
        default:
          return 'systemd-resolve --flush-caches || resolvectl flush-caches';
      }
    },
  ),

  // ==========================================
  // FILES CATEGORY
  // ==========================================
  CommandTool(
    id: 'list_directory_details',
    title: 'List Files Detailed',
    description: 'List current directory contents with permissions and sizes.',
    category: CommandCategory.files,
    supportedOs: [TargetOs.windows, TargetOs.linux, TargetOs.macos],
    executionType: CommandExecutionType.instant,
    icon: Icons.list_alt_rounded,
    commandBuilder: (os, _) {
      switch (os) {
        case TargetOs.windows:
          return 'dir';
        default:
          return 'ls -lah';
      }
    },
  ),
  CommandTool(
    id: 'directory_tree',
    title: 'Directory Tree',
    description: 'Visual tree of directory structures.',
    category: CommandCategory.files,
    supportedOs: [TargetOs.windows, TargetOs.linux, TargetOs.macos],
    executionType: CommandExecutionType.parameterized,
    inputFields: [
      CommandInputField(
        key: 'depth',
        label: 'Max Depth',
        hint: 'e.g. 2',
        defaultValue: '2',
        isNumeric: true,
      ),
    ],
    icon: Icons.account_tree_outlined,
    commandBuilder: (os, params) {
      final depth = params['depth']?.trim() ?? '2';
      switch (os) {
        case TargetOs.windows:
          return 'tree /F';
        default:
          return 'tree -L $depth || find . -maxdepth $depth';
      }
    },
  ),
  CommandTool(
    id: 'find_files',
    title: 'Find Files by Pattern',
    description: 'Search recursively for files matching a filename pattern.',
    category: CommandCategory.files,
    supportedOs: [TargetOs.windows, TargetOs.linux, TargetOs.macos],
    executionType: CommandExecutionType.parameterized,
    inputFields: [
      CommandInputField(
        key: 'pattern',
        label: 'Filename Pattern',
        hint: 'e.g. *.log or config.json',
        defaultValue: '*.log',
      ),
      CommandInputField(
        key: 'path',
        label: 'Search Path',
        hint: 'e.g. .',
        defaultValue: '.',
      ),
    ],
    icon: Icons.find_in_page_outlined,
    commandBuilder: (os, params) {
      final pattern = params['pattern']?.trim() ?? '*.log';
      final path = params['path']?.trim() ?? '.';
      switch (os) {
        case TargetOs.windows:
          return 'dir /s /b "$path\\$pattern"';
        default:
          return 'find "$path" -name "$pattern" -maxdepth 5';
      }
    },
  ),
  CommandTool(
    id: 'grep_text',
    title: 'Search Text in Files',
    description: 'Find lines matching text query across files.',
    category: CommandCategory.files,
    supportedOs: [TargetOs.windows, TargetOs.linux, TargetOs.macos],
    executionType: CommandExecutionType.parameterized,
    inputFields: [
      CommandInputField(
        key: 'query',
        label: 'Search Text',
        hint: 'e.g. TODO or ERROR',
      ),
      CommandInputField(
        key: 'path',
        label: 'In Directory',
        hint: 'e.g. .',
        defaultValue: '.',
      ),
    ],
    icon: Icons.manage_search_rounded,
    commandBuilder: (os, params) {
      final query = params['query']?.trim() ?? 'TODO';
      final path = params['path']?.trim() ?? '.';
      switch (os) {
        case TargetOs.windows:
          return 'findstr /s /i /n "$query" "$path\\*.*"';
        default:
          return 'grep -RIn --exclude-dir={.git,node_modules,target} "$query" "$path"';
      }
    },
  ),
  CommandTool(
    id: 'cd_directory',
    title: 'Change Directory (cd)',
    description: 'Safely change the active terminal working directory with shell quoting.',
    category: CommandCategory.files,
    supportedOs: [TargetOs.all],
    executionType: CommandExecutionType.parameterized,
    inputFields: [
      CommandInputField(
        key: 'path',
        label: 'Target Directory Path',
        hint: 'e.g. /run/media/aburaya/New Volume/The Cave/projects',
        defaultValue: '.',
      ),
    ],
    icon: Icons.folder_open_rounded,
    commandBuilder: (os, params) {
      final rawPath = params['path']?.trim() ?? '.';
      final clean = (rawPath.startsWith('"') && rawPath.endsWith('"')) ||
              (rawPath.startsWith("'") && rawPath.endsWith("'"))
          ? rawPath.substring(1, rawPath.length - 1)
          : rawPath;
      return 'cd "$clean"';
    },
  ),

  // ==========================================
  // DEVELOPER CATEGORY
  // ==========================================
  CommandTool(
    id: 'git_status',
    title: 'Git Status',
    description: 'Check working tree status and branch diffs.',
    category: CommandCategory.developer,
    supportedOs: [TargetOs.all],
    executionType: CommandExecutionType.instant,
    icon: Icons.alt_route_rounded,
    commandBuilder: (os, _) => 'git status',
  ),
  CommandTool(
    id: 'git_log',
    title: 'Git Recent Commits',
    description: 'Show recent 10 commits with short hash and titles.',
    category: CommandCategory.developer,
    supportedOs: [TargetOs.all],
    executionType: CommandExecutionType.instant,
    icon: Icons.history_rounded,
    commandBuilder: (os, _) => 'git log --oneline -n 10',
  ),
  CommandTool(
    id: 'node_version',
    title: 'Node.js & npm Version',
    description: 'Print installed Node and npm runtime versions.',
    category: CommandCategory.developer,
    supportedOs: [TargetOs.all],
    executionType: CommandExecutionType.instant,
    icon: Icons.javascript_rounded,
    commandBuilder: (os, _) => os == TargetOs.windows
        ? 'node --version && npm --version'
        : 'node --version 2>/dev/null && npm --version 2>/dev/null || echo "Node not found"',
  ),
  CommandTool(
    id: 'python_version',
    title: 'Python Version',
    description: 'Print installed Python interpreter version.',
    category: CommandCategory.developer,
    supportedOs: [TargetOs.all],
    executionType: CommandExecutionType.instant,
    icon: Icons.terminal_rounded,
    commandBuilder: (os, _) => os == TargetOs.windows
        ? 'python --version'
        : 'python3 --version 2>/dev/null || python --version 2>/dev/null',
  ),
  CommandTool(
    id: 'docker_ps',
    title: 'Docker Containers',
    description: 'List running Docker containers and status.',
    category: CommandCategory.developer,
    supportedOs: [TargetOs.all],
    executionType: CommandExecutionType.instant,
    icon: Icons.view_in_ar_rounded,
    commandBuilder: (os, _) => 'docker ps',
  ),

  // ==========================================
  // OS-SPECIFIC CATEGORY
  // ==========================================
  CommandTool(
    id: 'macos_caffeinate',
    title: 'Keep Awake (Caffeinate)',
    description: 'Prevent the Mac from sleeping or dimming the display.',
    category: CommandCategory.osSpecific,
    supportedOs: [TargetOs.macos],
    executionType: CommandExecutionType.toggle,
    icon: Icons.coffee_rounded,
    commandBuilder: (os, params) {
      if (params['action'] == 'stop') {
        return 'killall caffeinate';
      }
      return 'caffeinate -d &';
    },
  ),
  CommandTool(
    id: 'macos_restart_ui',
    title: 'Restart Finder & Dock',
    description: 'Relaunch unresponsive Finder and Dock processes.',
    category: CommandCategory.osSpecific,
    supportedOs: [TargetOs.macos],
    executionType: CommandExecutionType.confirmation,
    dangerLevel: DangerLevel.warning,
    icon: Icons.refresh_rounded,
    commandBuilder: (os, _) => 'killall Finder && killall Dock',
  ),
  CommandTool(
    id: 'windows_services',
    title: 'Check Running Services',
    description: 'List active Windows background services.',
    category: CommandCategory.osSpecific,
    supportedOs: [TargetOs.windows],
    executionType: CommandExecutionType.instant,
    icon: Icons.miscellaneous_services_rounded,
    commandBuilder: (os, _) => 'net start',
  ),
  CommandTool(
    id: 'linux_systemd_failed',
    title: 'Failed Systemd Units',
    description: 'Check for degraded or failed system services.',
    category: CommandCategory.osSpecific,
    supportedOs: [TargetOs.linux],
    executionType: CommandExecutionType.instant,
    icon: Icons.report_problem_outlined,
    commandBuilder: (os, _) => 'systemctl --failed',
  ),
];
