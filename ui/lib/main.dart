import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';

import 'ffi/idm_ffi.dart';
import 'models/task.dart';
import 'screens/browser.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  if (!kUseGoogleFonts) {
    GoogleFonts.config.allowRuntimeFetching = false;
  }
  runApp(const IdmApp());
}

// --- THEME COLORS ---
const kCyberBlack = Color(0xFF0B1220);
const kCyberDark = Color(0xFF121A2B);
const kCyberPanel = Color(0xFF1A2336);
const kNeonCyan = Color(0xFF14B8A6);
const kNeonPink = Color(0xFFF25F5C);
const kNeonYellow = Color(0xFFF6C453);
const kNeonBlue = Color(0xFF6BA6FF);
const kMutedText = Color(0xFF9AA7BD);
const bool kUseGoogleFonts =
    bool.fromEnvironment('USE_GOOGLE_FONTS', defaultValue: true);
const bool kEnablePermissions =
    bool.fromEnvironment('ENABLE_PERMISSIONS', defaultValue: true);

class IdmApp extends StatefulWidget {
  const IdmApp({super.key});

  @override
  State<IdmApp> createState() => _IdmAppState();
}

class _IdmAppState extends State<IdmApp> {
  IdmCore? _core;
  List<Task> _tasks = const [];
  Timer? _timer;
  String? _error;
  String _statusLog = '[SYSTEM BOOT]\nInitializing protocols...\n';
  String _dbPath = 'Locating...';
  final GlobalKey<NavigatorState> _navKey = GlobalKey<NavigatorState>();
  final GlobalKey<ScaffoldMessengerState> _scaffoldKey =
      GlobalKey<ScaffoldMessengerState>();
  Future<void>? _permissionsFuture;
  int _tabIndex = 0;
  int _filterIndex = 0;

  bool _smartDownload = true;
  bool _wifiOnly = false;
  bool _hideDownloads = false;
  bool _autoResume = true;
  bool _unlimitedRetries = true;
  bool _notifySound = true;
  bool _notifyVibrate = false;
  bool _useProxy = false;

  double _speedLimit = 0;
  double _maxConnections = 8;
  double _partsPerDownload = 8;
  String _downloadDir = '/storage/emulated/0/Download';
  bool _downloadPromptOpen = false;

  static const List<String> _filters = [
    'All',
    'Active',
    'Queued',
    'Paused',
    'Failed',
    'Completed',
    'Torrents',
  ];

  @override
  void initState() {
    super.initState();
    _log('Kernel initialized.');
    _initCore();
  }

  void _log(String msg) {
    debugPrint(msg);
    setState(() {
      _statusLog += '>> $msg\n';
    });
  }

  void _showAppDialog(WidgetBuilder builder) {
    final dialogContext = _navKey.currentContext;
    if (dialogContext == null) {
      _log('Dialog context unavailable.');
      return;
    }
    showDialog(
      context: dialogContext,
      builder: builder,
    );
  }

  Future<void> _initCore() async {
    // Request permissions in background, don't block init
    if (kEnablePermissions && _permissionsFuture == null) {
      _permissionsFuture = _requestPermissions();
    } else if (!kEnablePermissions) {
      _log('Permission requests disabled by build flag.');
    }

    _log('Mounting Core Systems...');
    try {
      final dbPath = await _resolveDbPath();
      _log('Database detected at: $dbPath');
      setState(() {
        _dbPath = dbPath;
      });

      _log('Loading Neural Interface (FFI)...');
      final core = await IdmCore.init(dbPath);
      _log('Engine ONLINE.');

      setState(() {
        _core = core;
        _error = null;
      });
      await _refresh();
      _timer = Timer.periodic(const Duration(seconds: 1), (_) => _refresh());
    } catch (err, stack) {
      _log('CRITICAL FAILURE: $err');
      _log('Trace: $stack');
      setState(() {
        _error = err.toString();
      });
    }
  }

  Future<void> _requestPermissions() async {
    _log('Requesting Permissions...');
    try {
      await [
        Permission.storage,
        Permission.manageExternalStorage,
      ].request();
      _log('Permissions processed.');
    } catch (e) {
      _log('Permission request failed: $e');
    }
  }

  Future<String> _resolveDbPath() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final dbDir = Directory('${dir.path}/idm_open');
      if (!dbDir.existsSync()) {
        dbDir.createSync(recursive: true);
      }
      return '${dbDir.path}/idm.db';
    } catch (e) {
      _log('Path resolution failed: $e');
      rethrow;
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _core?.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    final core = _core;
    if (core == null) return;
    try {
      final json = core.listTasksJson();
      if (json == null) return;
      final decoded = jsonDecode(json) as List<dynamic>;
      final tasks = decoded
          .map((item) => Task.fromJson(item as Map<String, dynamic>))
          .toList();
      // Sort: Active first, then Queued, then others by date desc
      tasks.sort((a, b) {
        if (a.status == 'active' && b.status != 'active') return -1;
        if (b.status == 'active' && a.status != 'active') return 1;
        return b.id.compareTo(a.id); 
      });
      setState(() {
        _tasks = tasks;
      });
    } catch (e) {
      _log('Refresh cycle error: $e');
    }
  }

  List<Task> _filteredTasks() {
    if (_filterIndex <= 0) return _tasks;
    final filter = _filters[_filterIndex].toLowerCase();
    return _tasks.where((task) => task.status.toLowerCase() == filter).toList();
  }

  int _countByStatus(String status) {
    return _tasks
        .where((task) => task.status.toLowerCase() == status.toLowerCase())
        .length;
  }

  String _formatBytes(int bytes) {
    if (bytes <= 0) return '0 B';
    const units = ['B', 'KB', 'MB', 'GB', 'TB'];
    double size = bytes.toDouble();
    int unit = 0;
    while (size >= 1024 && unit < units.length - 1) {
      size /= 1024;
      unit++;
    }
    return '${size.toStringAsFixed(size < 10 ? 1 : 0)} ${units[unit]}';
  }

  String _formatSpeedLimit(double value) {
    if (value <= 0) return 'Unlimited';
    return '${value.toStringAsFixed(1)} MB/s';
  }

  IconData _fileIcon(Task task) {
    final url = task.url.toLowerCase();
    if (url.endsWith('.mp4') || url.endsWith('.mkv') || url.endsWith('.webm')) {
      return Icons.movie;
    }
    if (url.endsWith('.mp3') || url.endsWith('.wav') || url.endsWith('.flac')) {
      return Icons.music_note;
    }
    if (url.endsWith('.zip') || url.endsWith('.rar') || url.endsWith('.7z')) {
      return Icons.archive;
    }
    if (url.endsWith('.apk') || url.endsWith('.exe') || url.endsWith('.msi')) {
      return Icons.apps;
    }
    if (url.endsWith('.pdf') || url.endsWith('.doc') || url.endsWith('.docx')) {
      return Icons.description;
    }
    return Icons.insert_drive_file;
  }

  Color _statusColor(Task task) {
    final status = task.status.toLowerCase();
    if (status == 'failed' || task.error != null) return kNeonPink;
    if (status == 'paused') return kNeonYellow;
    if (status == 'completed') return kNeonBlue;
    return kNeonCyan;
  }

  Future<void> _addTask() async {
    final dialogContext = _navKey.currentContext;
    if (dialogContext == null) {
      _log('Dialog context unavailable.');
      return;
    }
    final result = await showDialog<_AddTaskResult>(
      context: dialogContext,
      barrierColor: kCyberBlack.withOpacity(0.8),
      builder: (context) => _CyberAddTaskDialog(defaultPath: _downloadDir),
    );
    if (result == null) return;
    await _enqueueTask(result.url, result.dest);
  }

  Future<void> _enqueueTask(String url, String dest) async {
    if (_core == null) {
      _log('Command Rejected: Core offline.');
      return;
    }
    _log('Injecting Task: $url');
    try {
      final id = _core!.addTask(url, dest);
      if (id == null) {
        _log('Injection Failed: Null response.');
        if (!mounted) return;
        _showSnack('Injection Failed', isError: true);
        return;
      }
      _log('Task Assigned ID: $id');
      if (!mounted) return;
      _showSnack('Task Initiated');
      await _refresh();
    } catch (e) {
      _log('Exception during injection: $e');
    }
  }

  Future<void> _promptBrowserDownload(String url) async {
    if (_downloadPromptOpen) return;
    final dialogContext = _navKey.currentContext;
    if (dialogContext == null) {
      _log('Dialog context unavailable.');
      return;
    }
    _downloadPromptOpen = true;
    try {
      final action = await showDialog<_BrowserDownloadAction>(
        context: dialogContext,
        barrierColor: kCyberBlack.withOpacity(0.8),
        builder: (context) => _CyberConfirmDownloadDialog(
          url: url,
          downloadDir: _downloadDir,
        ),
      );
      if (action == null) return;
      if (action == _BrowserDownloadAction.download) {
        await _enqueueTask(url, _downloadDir);
        return;
      }
      if (action == _BrowserDownloadAction.edit) {
        final result = await showDialog<_AddTaskResult>(
          context: dialogContext,
          barrierColor: kCyberBlack.withOpacity(0.8),
          builder: (context) => _CyberAddTaskDialog(
            defaultPath: _downloadDir,
            initialUrl: url,
          ),
        );
        if (result == null) return;
        await _enqueueTask(result.url, result.dest);
      }
    } finally {
      _downloadPromptOpen = false;
    }
  }

  void _showSnack(String msg, {bool isError = false}) {
    final messenger = _scaffoldKey.currentState;
    if (messenger == null) {
      _log('Snack requested before messenger ready.');
      return;
    }
    messenger.showSnackBar(
      SnackBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        content: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: kCyberPanel,
            border: Border.all(color: isError ? kNeonPink : kNeonCyan),
            boxShadow: [
              BoxShadow(
                color: isError ? kNeonPink.withOpacity(0.5) : kNeonCyan.withOpacity(0.5),
                blurRadius: 10,
              )
            ],
          ),
          child: Text(
            msg,
            style: TextStyle(
              color: isError ? kNeonPink : kNeonCyan,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }

  void _enqueue() {
    if (_core == null) return;
    try {
      final count = _core!.enqueueQueued();
      _log('Queue optimized. Count: $count');
      _refresh();
    } catch (e) {
      _log('Queue command failed: $e');
    }
  }

  void _startNext() {
    if (_core == null) return;
    try {
      final id = _core!.startNext();
      _log('Executing next sequence. Target: $id');
      _refresh();
    } catch (e) {
      _log('Sequence start failed: $e');
    }
  }

  void _pause(Task task) {
    if (_core == null) return;
    _core!.pauseTask(task.id);
    _refresh();
  }

  void _resume(Task task) {
    if (_core == null) return;
    _core!.resumeTask(task.id);
    _refresh();
  }

  void _cancel(Task task) {
    if (_core == null) return;
    _core!.cancelTask(task.id);
    _refresh();
  }

  void _remove(Task task) {
    if (_core == null) return;
    try {
      _core!.removeTask(task.id);
      _log('Task deleted: ${task.id}');
      _refresh();
    } catch (e) {
      _log('Deletion failed: $e');
      _showSnack('Deletion Failed: $e', isError: true);
    }
  }

  void _showDetails(Task task) {
    final dialogContext = _navKey.currentContext;
    if (dialogContext == null) {
      _log('Dialog context unavailable.');
      return;
    }
    showDialog(
      context: dialogContext,
      builder: (context) => _CyberDetailDialog(task: task),
    );
  }

  Future<void> _resetData() async {
    _log('Initiating Factory Reset...');
    try {
      _core?.dispose();
      _core = null;
      final dir = await getApplicationDocumentsDirectory();
      final dbFile = File('${dir.path}/idm_open/idm.db');
      if (await dbFile.exists()) {
        await dbFile.delete();
        _log('Database purged.');
      }
      _log('Rebooting Core...');
      await _initCore();
      if (!mounted) return;
      _navKey.currentState?.pop(); // Close dialog
      _showSnack('SYSTEM RESET COMPLETE');
    } catch (e) {
      _log('Reset failed: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: _navKey,
      scaffoldMessengerKey: _scaffoldKey,
      title: 'IDM-Open',
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: Colors.transparent,
        colorScheme: const ColorScheme.dark(
          primary: kNeonCyan,
          secondary: kNeonBlue,
          surface: kCyberPanel,
        ),
        textTheme: kUseGoogleFonts
            ? GoogleFonts.spaceGroteskTextTheme(ThemeData.dark().textTheme)
            : ThemeData.dark().textTheme,
      ),
      home: Scaffold(
        resizeToAvoidBottomInset: false,
        backgroundColor: Colors.transparent,
        body: Stack(
          children: [
            Positioned.fill(
              child: Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Color(0xFF0B1220), Color(0xFF0A0F19)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
              ),
            ),
            Positioned(
              top: -120,
              right: -80,
              child: Container(
                width: 220,
                height: 220,
                decoration: BoxDecoration(
                  color: kNeonBlue.withOpacity(0.15),
                  shape: BoxShape.circle,
                ),
              ),
            ),
            Positioned(
              bottom: -140,
              left: -60,
              child: Container(
                width: 260,
                height: 260,
                decoration: BoxDecoration(
                  color: kNeonCyan.withOpacity(0.12),
                  shape: BoxShape.circle,
                ),
              ),
            ),
            Positioned.fill(child: CustomPaint(painter: GridPainter())),
            SafeArea(
              child: IndexedStack(
                index: _tabIndex,
                children: [
                  _buildDownloadsPage(context),
                  _buildBrowserPage(context),
                  _buildSettingsPage(context),
                ],
              ),
            ),
          ],
        ),
        floatingActionButton: _tabIndex == 0
            ? FloatingActionButton.extended(
                onPressed: _addTask,
                backgroundColor: kNeonCyan,
                foregroundColor: kCyberBlack,
                icon: const Icon(Icons.add),
                label: const Text('New Download'),
              )
            : null,
        bottomNavigationBar: _buildBottomNav(),
      ),
    );
  }

  Widget _buildBottomNav() {
    return Container(
      decoration: BoxDecoration(
        color: kCyberDark,
        border: Border(top: BorderSide(color: kCyberPanel)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.35),
            blurRadius: 16,
            offset: const Offset(0, -6),
          ),
        ],
      ),
      child: BottomNavigationBar(
        currentIndex: _tabIndex,
        onTap: (index) => setState(() => _tabIndex = index),
        type: BottomNavigationBarType.fixed,
        backgroundColor: kCyberDark,
        selectedItemColor: kNeonCyan,
        unselectedItemColor: kMutedText,
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.downloading_rounded),
            label: 'Downloads',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.public),
            label: 'Browser',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.tune),
            label: 'Settings',
          ),
        ],
      ),
    );
  }

  Widget _buildDownloadsPage(BuildContext context) {
    final filtered = _filteredTasks();
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildHeader(
            context,
            title: 'IDM Open',
            subtitle: 'Smart download manager',
            actions: [
              _buildHeaderAction(
                icon: Icons.bug_report,
                color: kNeonYellow,
                onTap: () {
                  _showAppDialog(
                    (context) => _CyberLogDialog(
                      log: _statusLog,
                      onReset: _resetData,
                    ),
                  );
                },
              ),
              const SizedBox(width: 8),
              _buildHeaderAction(
                icon: Icons.refresh,
                color: kNeonCyan,
                onTap: _refresh,
              ),
            ],
          ),
          const SizedBox(height: 12),
          _buildStatusStrip(context),
          const SizedBox(height: 12),
          _buildStatsRow(context),
          const SizedBox(height: 12),
          _buildQuickActions(),
          const SizedBox(height: 12),
          _buildFilterChips(),
          const SizedBox(height: 8),
          Expanded(
            child: filtered.isEmpty
                ? _buildEmptyState()
                : ListView.builder(
                    padding: const EdgeInsets.only(bottom: 80),
                    itemCount: filtered.length,
                    itemBuilder: (context, index) {
                      final task = filtered[index];
                      return _buildTaskCard(task);
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildBrowserPage(BuildContext context) {
    return CyberBrowser(
      onDownloadRequest: (url) {
        _log('Browser requested download: $url');
        _promptBrowserDownload(url);
      },
    );
  }

  Widget _buildSettingsPage(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: ListView(
        children: [
          _buildHeader(
            context,
            title: 'Settings',
            subtitle: 'Control center',
          ),
          const SizedBox(height: 12),
          _buildSettingsSection(
            context,
            title: 'General',
            children: [
              _buildSwitchTile(
                title: 'Smart download',
                subtitle: 'Capture links copied to clipboard',
                value: _smartDownload,
                onChanged: (value) => setState(() => _smartDownload = value),
              ),
              _buildSwitchTile(
                title: 'Wi-Fi only',
                subtitle: 'Download only on Wi-Fi networks',
                value: _wifiOnly,
                onChanged: (value) => setState(() => _wifiOnly = value),
              ),
              _buildSwitchTile(
                title: 'Hide downloads',
                subtitle: 'Hide files from other apps',
                value: _hideDownloads,
                onChanged: (value) => setState(() => _hideDownloads = value),
              ),
              _buildInfoTile(
                title: 'Download folder',
                value: _downloadDir,
                icon: Icons.folder,
              ),
            ],
          ),
          _buildSettingsSection(
            context,
            title: 'Downloads',
            children: [
              _buildSwitchTile(
                title: 'Auto resume',
                subtitle: 'Resume after temporary failures',
                value: _autoResume,
                onChanged: (value) => setState(() => _autoResume = value),
              ),
              _buildSwitchTile(
                title: 'Unlimited retries',
                subtitle: 'Retry until link expires',
                value: _unlimitedRetries,
                onChanged: (value) => setState(() => _unlimitedRetries = value),
              ),
              _buildSliderTile(
                title: 'Max connections',
                value: _maxConnections,
                min: 1,
                max: 30,
                divisions: 29,
                label: _maxConnections.toStringAsFixed(0),
                onChanged: (value) => setState(() => _maxConnections = value),
              ),
              _buildSliderTile(
                title: 'Parts per download',
                value: _partsPerDownload,
                min: 1,
                max: 32,
                divisions: 31,
                label: _partsPerDownload.toStringAsFixed(0),
                onChanged: (value) => setState(() => _partsPerDownload = value),
              ),
              _buildSliderTile(
                title: 'Speed limit',
                value: _speedLimit,
                min: 0,
                max: 20,
                divisions: 20,
                label: _formatSpeedLimit(_speedLimit),
                onChanged: (value) => setState(() => _speedLimit = value),
              ),
            ],
          ),
          _buildSettingsSection(
            context,
            title: 'Network',
            children: [
              _buildSwitchTile(
                title: 'Use proxy',
                subtitle: 'Apply HTTP proxy for downloads',
                value: _useProxy,
                onChanged: (value) => setState(() => _useProxy = value),
              ),
              _buildInfoTile(
                title: 'Proxy address',
                value: _useProxy ? 'proxy.example:8080' : 'Not configured',
                icon: Icons.shield,
              ),
            ],
          ),
          _buildSettingsSection(
            context,
            title: 'Notifications',
            children: [
              _buildSwitchTile(
                title: 'Sound',
                subtitle: 'Play sound on completion',
                value: _notifySound,
                onChanged: (value) => setState(() => _notifySound = value),
              ),
              _buildSwitchTile(
                title: 'Vibrate',
                subtitle: 'Vibrate on completion',
                value: _notifyVibrate,
                onChanged: (value) => setState(() => _notifyVibrate = value),
              ),
            ],
          ),
          _buildSettingsSection(
            context,
            title: 'About',
            children: [
              _buildInfoTile(
                title: 'Database path',
                value: _dbPath,
                icon: Icons.storage,
              ),
              _buildInfoTile(
                title: 'Engine',
                value: _core != null ? 'Online' : 'Offline',
                icon: Icons.memory,
              ),
            ],
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _buildHeader(
    BuildContext context, {
    required String title,
    String? subtitle,
    List<Widget> actions = const [],
  }) {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.6,
                    ),
              ),
              if (subtitle != null)
                Text(
                  subtitle,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: kMutedText,
                        fontWeight: FontWeight.w500,
                      ),
                ),
            ],
          ),
        ),
        ...actions,
      ],
    );
  }

  Widget _buildHeaderAction({
    required IconData icon,
    required VoidCallback onTap,
    Color? color,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: kCyberPanel,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: kCyberDark),
        ),
        child: Icon(icon, color: color ?? kNeonYellow),
      ),
    );
  }

  Widget _buildStatusStrip(BuildContext context) {
    final online = _core != null && _error == null;
    final statusColor = _error != null
        ? kNeonPink
        : online
            ? kNeonCyan
            : kNeonYellow;
    final statusText = _error != null
        ? 'STATUS: ERROR'
        : online
            ? 'STATUS: ONLINE'
            : 'STATUS: BOOTING...';
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: kCyberPanel,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: kCyberDark),
      ),
      child: Wrap(
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 12,
        runSpacing: 8,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: statusColor,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                statusText,
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: statusColor,
                      fontWeight: FontWeight.w700,
                    ),
              ),
            ],
          ),
          _buildToggleChip(
            label: 'Smart',
            value: _smartDownload,
            onChanged: (value) => setState(() => _smartDownload = value),
          ),
          _buildToggleChip(
            label: 'Wi-Fi',
            value: _wifiOnly,
            onChanged: (value) => setState(() => _wifiOnly = value),
          ),
        ],
      ),
    );
  }

  Widget _buildToggleChip({
    required String label,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return InkWell(
      onTap: () => onChanged(!value),
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: value ? kNeonCyan.withOpacity(0.2) : kCyberDark,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: value ? kNeonCyan : kCyberPanel,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              value ? Icons.toggle_on : Icons.toggle_off,
              color: value ? kNeonCyan : kMutedText,
              size: 18,
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                color: value ? kNeonCyan : kMutedText,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatsRow(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _buildStatCard(
            label: 'Active',
            value: _countByStatus('active'),
            color: kNeonCyan,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _buildStatCard(
            label: 'Queued',
            value: _countByStatus('queued'),
            color: kNeonYellow,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _buildStatCard(
            label: 'Done',
            value: _countByStatus('completed'),
            color: kNeonBlue,
          ),
        ),
      ],
    );
  }

  Widget _buildStatCard({
    required String label,
    required int value,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: kCyberPanel,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: kCyberDark),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(color: kMutedText, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 6),
          Text(
            value.toString(),
            style: TextStyle(
              color: color,
              fontSize: 20,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQuickActions() {
    return Row(
      children: [
        Expanded(
          child: _buildActionButton(
            icon: Icons.queue,
            label: 'Queue all',
            onTap: _enqueue,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _buildActionButton(
            icon: Icons.play_arrow,
            label: 'Start next',
            onTap: _startNext,
          ),
        ),
      ],
    );
  }

  Widget _buildActionButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
        decoration: BoxDecoration(
          color: kCyberPanel,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: kCyberDark),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: kNeonCyan, size: 18),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFilterChips() {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: List.generate(_filters.length, (index) {
        final selected = _filterIndex == index;
        return ChoiceChip(
          label: Text(_filters[index]),
          selected: selected,
          onSelected: (_) => setState(() => _filterIndex = index),
          selectedColor: kNeonCyan.withOpacity(0.2),
          backgroundColor: kCyberDark,
          labelStyle: TextStyle(
            color: selected ? kNeonCyan : kMutedText,
            fontWeight: FontWeight.w600,
          ),
          side: BorderSide(color: selected ? kNeonCyan : kCyberPanel),
        );
      }),
    );
  }

  Widget _buildTaskCard(Task task) {
    final status = task.status.toLowerCase();
    final statusColor = _statusColor(task);
    final progress = task.totalBytes > 0 ? task.progress : 0;
    final percent = (progress * 100).clamp(0, 100).toStringAsFixed(1);
    final totalLabel =
        task.totalBytes > 0 ? _formatBytes(task.totalBytes) : '--';
    final downloadedLabel = _formatBytes(task.downloadedBytes);

    return GestureDetector(
      onTap: () => _showDetails(task),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: kCyberPanel,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: statusColor.withOpacity(0.35)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.2),
              blurRadius: 12,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: statusColor.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(_fileIcon(task), color: statusColor),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    task.url,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  status.toUpperCase(),
                  style: TextStyle(
                    color: statusColor,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: LinearProgressIndicator(
                value: task.totalBytes > 0 ? progress.toDouble() : null,
                minHeight: 6,
                backgroundColor: kCyberDark,
                color: statusColor,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Text(
                  '$percent%',
                  style: TextStyle(
                    color: statusColor,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  '$downloadedLabel / $totalLabel',
                  style: TextStyle(color: kMutedText, fontSize: 12),
                ),
                const Spacer(),
                if (task.error != null)
                  Text(
                    'ERR',
                    style: TextStyle(
                      color: kNeonPink,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [
                if (status == 'active')
                  _buildTaskAction(
                    icon: Icons.pause,
                    color: kNeonYellow,
                    onTap: () => _pause(task),
                  ),
                if (status == 'paused' || status == 'failed')
                  _buildTaskAction(
                    icon: Icons.play_arrow,
                    color: kNeonCyan,
                    onTap: () => _resume(task),
                  ),
                if (status != 'completed')
                  _buildTaskAction(
                    icon: Icons.stop,
                    color: kNeonPink,
                    onTap: () => _cancel(task),
                  ),
                _buildTaskAction(
                  icon: Icons.delete_outline,
                  color: kMutedText,
                  onTap: () => _remove(task),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTaskAction({
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: color.withOpacity(0.12),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withOpacity(0.6)),
        ),
        child: Icon(icon, color: color, size: 18),
      ),
    );
  }

  Widget _buildEmptyState() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxHeight < 160;
        final iconSize = compact ? 40.0 : 64.0;
        final gap = compact ? 8.0 : 12.0;
        return Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.download_for_offline, size: iconSize, color: kMutedText),
                SizedBox(height: gap),
                Text(
                  'No downloads yet',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                SizedBox(height: compact ? 4 : 6),
                Text(
                  'Tap New Download to add a link',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: kMutedText),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildPillAction({required IconData icon, required String label}) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
      decoration: BoxDecoration(
        color: kCyberPanel,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: kCyberDark),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: kNeonCyan, size: 18),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQuickSite(String title, String url, IconData icon) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: kCyberPanel,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: kCyberDark),
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: kNeonBlue.withOpacity(0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: kNeonBlue),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(height: 2),
                Text(url, style: TextStyle(color: kMutedText, fontSize: 12)),
              ],
            ),
          ),
          const Icon(Icons.chevron_right, color: kMutedText),
        ],
      ),
    );
  }

  Widget _buildSectionTitle(BuildContext context, String title) {
    return Text(
      title,
      style: Theme.of(context).textTheme.titleMedium?.copyWith(
            color: Colors.white,
            fontWeight: FontWeight.w700,
          ),
    );
  }

  Widget _buildInfoCard(
    BuildContext context, {
    required String title,
    required String body,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: kCyberPanel,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: kCyberDark),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                ),
          ),
          const SizedBox(height: 6),
          Text(body, style: TextStyle(color: kMutedText)),
        ],
      ),
    );
  }

  Widget _buildSettingsSection(
    BuildContext context, {
    required String title,
    required List<Widget> children,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: kCyberPanel,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: kCyberDark),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                ),
          ),
          const SizedBox(height: 8),
          ...children,
        ],
      ),
    );
  }

  Widget _buildSwitchTile({
    required String title,
    String? subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: subtitle == null
          ? null
          : Text(subtitle, style: TextStyle(color: kMutedText, fontSize: 12)),
      trailing: Switch.adaptive(
        value: value,
        activeColor: kNeonCyan,
        onChanged: onChanged,
      ),
      onTap: () => onChanged(!value),
    );
  }

  Widget _buildInfoTile({
    required String title,
    required String value,
    required IconData icon,
  }) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(icon, color: kNeonBlue),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: Text(value, style: TextStyle(color: kMutedText, fontSize: 12)),
    );
  }

  Widget _buildSliderTile({
    required String title,
    required double value,
    required double min,
    required double max,
    required int divisions,
    required String label,
    required ValueChanged<double> onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
            ),
            Text(label, style: TextStyle(color: kNeonCyan)),
          ],
        ),
        Slider(
          value: value,
          min: min,
          max: max,
          divisions: divisions,
          activeColor: kNeonCyan,
          inactiveColor: kCyberDark,
          onChanged: onChanged,
        ),
        const Divider(color: kCyberDark),
      ],
    );
  }
}

class GridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = kNeonBlue.withOpacity(0.08)
      ..strokeWidth = 1;

    const step = 36.0;
    for (double x = 0; x < size.width; x += step) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (double y = 0; y < size.height; y += step) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _CyberTaskCard extends StatelessWidget {
  const _CyberTaskCard({
    required this.task,
    required this.onTap,
    required this.onPause,
    required this.onResume,
    required this.onCancel,
    required this.onRemove,
  });

  final Task task;
  final VoidCallback onTap;
  final VoidCallback onPause;
  final VoidCallback onResume;
  final VoidCallback onCancel;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final status = task.status.toLowerCase();
    final progress = task.progress;
    final percent = (progress * 100).clamp(0, 100).toStringAsFixed(1);
    
    Color statusColor = kNeonCyan;
    if (status == 'failed' || task.error != null) statusColor = kNeonPink;
    if (status == 'paused') statusColor = kNeonYellow;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 16),
        decoration: ShapeDecoration(
          color: kCyberPanel,
          shape: BeveledRectangleBorder(
            side: BorderSide(color: statusColor.withOpacity(0.5), width: 1),
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(10),
              bottomRight: Radius.circular(10),
            ),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.file_download, color: statusColor, size: 16),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(task.url, 
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                        maxLines: 1, overflow: TextOverflow.ellipsis),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Stack(
                children: [
                  Container(height: 8, color: Colors.black),
                  FractionallySizedBox(
                    widthFactor: task.totalBytes > 0 ? progress : 0,
                    child: Container(
                      height: 8,
                      decoration: BoxDecoration(
                        color: statusColor,
                        boxShadow: [BoxShadow(color: statusColor, blurRadius: 6)],
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('$percent%', style: TextStyle(color: statusColor, fontSize: 18, fontWeight: FontWeight.w900)),
                  Text(status.toUpperCase(), style: TextStyle(color: statusColor.withOpacity(0.7), fontSize: 12)),
                ],
              ),
               if (task.error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text('ERR: ${task.error}', style: TextStyle(color: kNeonPink, fontSize: 10)),
                  ),
              const Divider(color: Colors.white10),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  if (status == 'active')
                    _CyberMiniButton(icon: Icons.pause, color: kNeonYellow, onPressed: onPause),
                  if (status == 'paused' || status == 'failed')
                    _CyberMiniButton(icon: Icons.play_arrow, color: kNeonCyan, onPressed: onResume),
                  
                  const SizedBox(width: 8),
                  if (status != 'completed')
                    _CyberMiniButton(icon: Icons.stop, color: kNeonPink, onPressed: onCancel),
                  
                  const SizedBox(width: 8),
                  _CyberMiniButton(icon: Icons.delete_outline, color: Colors.grey, onPressed: onRemove),
                ],
              )
            ],
          ),
        ),
      ),
    );
  }
}

class _CyberMiniButton extends StatelessWidget {
  final IconData icon;
  final Color color;
  final VoidCallback onPressed;

  const _CyberMiniButton({required this.icon, required this.color, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onPressed,
      child: Container(
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          border: Border.all(color: color),
          color: color.withOpacity(0.1),
        ),
        child: Icon(icon, color: color, size: 18),
      ),
    );
  }
}

class _CyberButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback onPressed;

  const _CyberButton({required this.label, required this.icon, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    // Wrap Text in Flexible/Expanded if needed, or allow it to be clipped
    return ElevatedButton(
      style: ElevatedButton.styleFrom(
        backgroundColor: kCyberPanel,
        foregroundColor: kNeonCyan,
        shape: const BeveledRectangleBorder(
          side: BorderSide(color: kNeonCyan),
          borderRadius: BorderRadius.all(Radius.circular(10)),
        ),
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8), // Reduced padding
      ),
      onPressed: onPressed,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min, // Use min size to shrink-wrap
        children: [
          Icon(icon, size: 18),
          const SizedBox(width: 4),
          Flexible( // Prevent overflow
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11),
            ),
          ),
        ],
      ),
    );
  }
}

class _CyberAddButton extends StatelessWidget {
  final VoidCallback onPressed;
  const _CyberAddButton({required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onPressed,
      child: Container(
        width: 50, // Reduced size
        height: 50,
        decoration: ShapeDecoration(
          color: kNeonCyan.withOpacity(0.2),
          shape: const BeveledRectangleBorder(
            side: BorderSide(color: kNeonCyan, width: 2),
            borderRadius: BorderRadius.all(Radius.circular(15)),
          ),
        ),
        child: const Icon(Icons.add, color: kNeonCyan, size: 28),
      ),
    );
  }
}

class _CyberIconButton extends StatelessWidget {
  final IconData icon;
  final Color color;
  final VoidCallback onPressed;
  const _CyberIconButton({required this.icon, required this.color, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: Icon(icon, color: color),
      onPressed: onPressed,
      style: IconButton.styleFrom(
        shape: BeveledRectangleBorder(side: BorderSide(color: color.withOpacity(0.5))),
      ),
    );
  }
}

enum _BrowserDownloadAction { download, edit }

String _filenameFromUrl(String url) {
  try {
    final uri = Uri.parse(url);
    if (uri.pathSegments.isNotEmpty) {
      final last = uri.pathSegments.last;
      if (last.isNotEmpty) return last;
    }
  } catch (_) {}
  return url;
}

class _CyberConfirmDownloadDialog extends StatelessWidget {
  final String url;
  final String downloadDir;

  const _CyberConfirmDownloadDialog({required this.url, required this.downloadDir});

  @override
  Widget build(BuildContext context) {
    final name = _filenameFromUrl(url);
    return Dialog(
      backgroundColor: Colors.transparent,
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: ShapeDecoration(
          color: kCyberBlack,
          shape: const BeveledRectangleBorder(
            side: BorderSide(color: kNeonYellow, width: 1),
            borderRadius: BorderRadius.only(topLeft: Radius.circular(20), bottomRight: Radius.circular(20)),
          ),
          shadows: const [BoxShadow(color: kNeonYellow, blurRadius: 10)],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'CONFIRM DOWNLOAD',
              textAlign: TextAlign.center,
              style: TextStyle(color: kNeonYellow, fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            Text(name, style: const TextStyle(color: Colors.white, fontSize: 14)),
            const SizedBox(height: 6),
            Text(url, style: const TextStyle(color: Colors.white70, fontSize: 11)),
            const SizedBox(height: 6),
            Text('SAVE TO: $downloadDir', style: const TextStyle(color: kMutedText, fontSize: 11)),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: _CyberButton(
                    label: 'CANCEL',
                    icon: Icons.close,
                    onPressed: () => Navigator.pop(context),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: kNeonCyan,
                      foregroundColor: kCyberBlack,
                      shape: const BeveledRectangleBorder(
                        borderRadius: BorderRadius.all(Radius.circular(10)),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                    onPressed: () =>
                        Navigator.pop(context, _BrowserDownloadAction.download),
                    child: const Text('DOWNLOAD', style: TextStyle(fontWeight: FontWeight.w900)),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: () => Navigator.pop(context, _BrowserDownloadAction.edit),
              child: const Text('EDIT PATH', style: TextStyle(color: kNeonYellow)),
            ),
          ],
        ),
      ),
    );
  }
}

class _CyberAddTaskDialog extends StatefulWidget {
  const _CyberAddTaskDialog({required this.defaultPath, this.initialUrl});

  final String defaultPath;
  final String? initialUrl;
  @override
  State<_CyberAddTaskDialog> createState() => _CyberAddTaskDialogState();
}

class _CyberAddTaskDialogState extends State<_CyberAddTaskDialog> {
  final _urlController = TextEditingController();
  final _destController = TextEditingController();

  @override
  void initState() {
    super.initState();
    if (widget.initialUrl != null) {
      _urlController.text = widget.initialUrl!;
    } else {
      _checkClipboard();
    }
    _destController.text = widget.defaultPath;
  }

  Future<void> _checkClipboard() async {
    try {
        final data = await Clipboard.getData(Clipboard.kTextPlain);
        if (data?.text != null && (data!.text!.startsWith('http') || data.text!.startsWith('www'))) {
            setState(() {
                _urlController.text = data.text!;
            });
        }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: ShapeDecoration(
          color: kCyberBlack,
          shape: const BeveledRectangleBorder(
            side: BorderSide(color: kNeonCyan, width: 1),
            borderRadius: BorderRadius.only(topLeft: Radius.circular(20), bottomRight: Radius.circular(20)),
          ),
          shadows: const [BoxShadow(color: kNeonCyan, blurRadius: 10)],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('NEW DOWNLOAD', 
                textAlign: TextAlign.center,
                style: TextStyle(color: kNeonCyan, fontSize: 20, fontWeight: FontWeight.bold)),
            const SizedBox(height: 20),
            _CyberTextField(controller: _urlController, label: 'DOWNLOAD LINK'),
            const SizedBox(height: 12),
            _CyberTextField(controller: _destController, label: 'SAVE TO'),
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(child: _CyberButton(label: 'CANCEL', icon: Icons.close, onPressed: () => Navigator.pop(context))),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: kNeonCyan,
                      foregroundColor: kCyberBlack,
                      shape: const BeveledRectangleBorder(
                        borderRadius: BorderRadius.all(Radius.circular(10)),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                    onPressed: () {
                      final url = _urlController.text.trim();
                      if (url.isNotEmpty) {
                        Navigator.pop(context, _AddTaskResult(url: url, dest: _destController.text.trim()));
                      }
                    },
                    child: const Text('ADD', style: TextStyle(fontWeight: FontWeight.w900)),
                  ),
                ),
              ],
            )
          ],
        ),
      ),
    );
  }
}

class _CyberTextField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  const _CyberTextField({required this.controller, required this.label});

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      style: const TextStyle(color: Colors.white),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: TextStyle(color: kMutedText),
        enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: kCyberDark)),
        focusedBorder: const OutlineInputBorder(borderSide: BorderSide(color: kNeonCyan)),
        filled: true,
        fillColor: kCyberDark,
      ),
    );
  }
}

class _CyberLogDialog extends StatelessWidget {
  final String log;
  final VoidCallback? onReset;

  const _CyberLogDialog({required this.log, this.onReset});

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      child: Container(
        height: 500,
        padding: const EdgeInsets.all(16),
        decoration: ShapeDecoration(
          color: Colors.black,
          shape: const BeveledRectangleBorder(
            side: BorderSide(color: kNeonYellow),
            borderRadius: BorderRadius.all(Radius.circular(10)),
          ),
        ),
        child: Column(
          children: [
            const Text('SYSTEM LOG', style: TextStyle(color: kNeonYellow, fontWeight: FontWeight.bold)),
            const Divider(color: kNeonYellow),
            Expanded(
              child: SingleChildScrollView(
                child: Text(log, style: const TextStyle(color: kNeonYellow, fontFamily: 'monospace', fontSize: 10)),
              ),
            ),
            const SizedBox(height: 12),
            if (onReset != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: kNeonPink,
                    foregroundColor: Colors.white,
                  ),
                  onPressed: onReset,
                  icon: const Icon(Icons.delete_forever),
                  label: const Text('FACTORY RESET (FIX DB)'),
                ),
              ),
            _CyberMiniButton(icon: Icons.close, color: kNeonYellow, onPressed: () => Navigator.pop(context)),
          ],
        ),
      ),
    );
  }
}

class _CyberDetailDialog extends StatelessWidget {
  final Task task;
  const _CyberDetailDialog({required this.task});

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: ShapeDecoration(
          color: kCyberBlack,
          shape: const BeveledRectangleBorder(
            side: BorderSide(color: kNeonCyan, width: 2),
            borderRadius: BorderRadius.all(Radius.circular(15)),
          ),
        ),
        child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
                const Text('DATA LOG', style: TextStyle(color: kNeonCyan, fontSize: 18, fontWeight: FontWeight.bold)),
                const Divider(color: kNeonCyan),
                const SizedBox(height: 8),
                Text('URL: ${task.url}', style: const TextStyle(color: Colors.white70, fontSize: 12)),
                const SizedBox(height: 8),
                Text('DEST: ${task.destPath}', style: const TextStyle(color: Colors.white70, fontSize: 12)),
                const SizedBox(height: 8),
                Text('SIZE: ${(task.totalBytes / 1024 / 1024).toStringAsFixed(2)} MB', style: const TextStyle(color: kNeonYellow)),
                if (task.error != null)
                    Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text('ERROR: ${task.error}', style: const TextStyle(color: kNeonPink)),
                    ),
                const SizedBox(height: 16),
                Center(child: _CyberButton(label: 'CLOSE', icon: Icons.close, onPressed: () => Navigator.pop(context))),
            ],
        ),
      ),
    );
  }
}

class _AddTaskResult {
  const _AddTaskResult({required this.url, required this.dest});
  final String url;
  final String dest;
}
