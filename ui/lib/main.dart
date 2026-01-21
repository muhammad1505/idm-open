import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';

import 'ffi/idm_ffi.dart';
import 'models/task.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const IdmApp());
}

// --- THEME COLORS ---
const kCyberBlack = Color(0xFF0A0A12);
const kCyberDark = Color(0xFF14141F);
const kCyberPanel = Color(0xFF1E1E2C);
const kNeonCyan = Color(0xFF00F0FF);
const kNeonPink = Color(0xFFFF0055);
const kNeonYellow = Color(0xFFF0B429);

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
    _requestPermissions();

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
    await [
      Permission.storage,
      Permission.manageExternalStorage,
    ].request();
    _log('Permissions processed.');
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

  Future<void> _addTask() async {
    if (_core == null) {
      _log('Command Rejected: Core offline.');
      return;
    }
    final dialogContext = _navKey.currentContext;
    if (dialogContext == null) {
      _log('Dialog context unavailable.');
      return;
    }
    final core = _core!;
    final result = await showDialog<_AddTaskResult>(
      context: dialogContext,
      barrierColor: kCyberBlack.withOpacity(0.8),
      builder: (context) => const _CyberAddTaskDialog(),
    );
    if (result == null) return;

    _log('Injecting Task: ${result.url}');
    try {
      final id = core.addTask(result.url, result.dest);
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
              fontFamily: GoogleFonts.orbitron().fontFamily,
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
      title: 'IDM-Open: CYBER',
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: kCyberBlack,
        colorScheme: const ColorScheme.dark(
          primary: kNeonCyan,
          secondary: kNeonPink,
          surface: kCyberPanel,
        ),
        textTheme: GoogleFonts.orbitronTextTheme(ThemeData.dark().textTheme),
      ),
      home: Scaffold(
        resizeToAvoidBottomInset: false, // Prevent overflow when keyboard appears
        body: Stack(
          children: [
            Positioned.fill(child: CustomPaint(painter: GridPainter())),
            SafeArea(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Header
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    child: Row(
                      children: [
                        const Icon(Icons.download_for_offline, color: kNeonCyan, size: 28),
                        const SizedBox(width: 12),
                        Flexible(
                          child: Text('IDM // OPEN',
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.orbitron(
                                  fontSize: 24,
                                  fontWeight: FontWeight.w900,
                                  color: kNeonCyan,
                                  letterSpacing: 2)),
                        ),
                        const Spacer(), // Spacer is safe here with Flexible
                        _CyberIconButton(
                          icon: Icons.bug_report,
                          color: kNeonYellow,
                          onPressed: () {
                            _showAppDialog(
                              (context) => _CyberLogDialog(
                                log: _statusLog,
                                onReset: _resetData,
                              ),
                            );
                          },
                        ),
                        const SizedBox(width: 8),
                        _CyberIconButton(
                          icon: Icons.refresh,
                          color: kNeonCyan,
                          onPressed: _refresh,
                        ),
                      ],
                    ),
                  ),

                  // Status Panel
                  Container(
                    margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: kCyberDark.withOpacity(0.8),
                      border: Border.all(color: _error != null ? kNeonPink : kNeonCyan.withOpacity(0.3)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (_error != null)
                          Text('STATUS: CRITICAL ERROR', style: TextStyle(color: kNeonPink, fontWeight: FontWeight.bold)),
                        if (_error == null)
                          Text('STATUS: ${_core != null ? "ONLINE" : "BOOTING..."}', 
                              style: TextStyle(color: _core != null ? kNeonCyan : kNeonYellow)),
                        Text('DB: $_dbPath', style: TextStyle(color: Colors.white54, fontSize: 10)),
                      ],
                    ),
                  ),

                  // Task List
                  Expanded(
                    child: _tasks.isEmpty
                        ? Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.code, size: 64, color: kNeonCyan.withOpacity(0.2)),
                                const SizedBox(height: 16),
                                Text('NO ACTIVE TASKS', 
                                    style: TextStyle(color: kNeonCyan.withOpacity(0.5), letterSpacing: 2)),
                              ],
                            ),
                          )
                        : ListView.builder(
                            padding: const EdgeInsets.all(16),
                            itemCount: _tasks.length,
                            itemBuilder: (context, index) {
                              final task = _tasks[index];
                              return _CyberTaskCard(
                                task: task,
                                onTap: () => _showDetails(task),
                                onPause: () => _pause(task),
                                onResume: () => _resume(task),
                                onCancel: () => _cancel(task),
                                onRemove: () => _remove(task),
                              );
                            },
                          ),
                  ),

                  // Bottom Controls - Wrapped in Flexible to avoid overflow
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: const BoxDecoration(
                      color: kCyberDark,
                      border: Border(top: BorderSide(color: kNeonCyan, width: 2)),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: _CyberButton(
                            label: 'ENQUEUE',
                            icon: Icons.queue,
                            onPressed: _enqueue,
                          ),
                        ),
                        const SizedBox(width: 12),
                        _CyberAddButton(onPressed: _addTask), 
                        const SizedBox(width: 12),
                        Expanded(
                          child: _CyberButton(
                            label: 'START',
                            icon: Icons.play_arrow,
                            onPressed: _startNext,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// --- WIDGETS ---

class GridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = kNeonCyan.withOpacity(0.05)
      ..strokeWidth = 1;

    const step = 40.0;
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

class _CyberAddTaskDialog extends StatefulWidget {
  const _CyberAddTaskDialog();
  @override
  State<_CyberAddTaskDialog> createState() => _CyberAddTaskDialogState();
}

class _CyberAddTaskDialogState extends State<_CyberAddTaskDialog> {
  final _urlController = TextEditingController();
  final _destController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _checkClipboard();
    _destController.text = '/storage/emulated/0/Download/';
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
            const Text('NEW TARGET', 
                textAlign: TextAlign.center,
                style: TextStyle(color: kNeonCyan, fontSize: 20, fontWeight: FontWeight.bold)),
            const SizedBox(height: 20),
            _CyberTextField(controller: _urlController, label: 'URL SOURCE'),
            const SizedBox(height: 12),
            _CyberTextField(controller: _destController, label: 'DESTINATION PATH'),
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(child: _CyberButton(label: 'ABORT', icon: Icons.close, onPressed: () => Navigator.pop(context))),
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
                    child: const Text('INITIATE', style: TextStyle(fontWeight: FontWeight.w900)),
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
      style: const TextStyle(color: kNeonCyan),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: TextStyle(color: kNeonCyan.withOpacity(0.5)),
        enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: kNeonCyan.withOpacity(0.3))),
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
