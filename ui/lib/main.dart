import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:path_provider/path_provider.dart';

import 'ffi/idm_ffi.dart';
import 'models/task.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const IdmApp());
}

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

  @override
  void initState() {
    super.initState();
    _initCore();
  }

  Future<void> _initCore() async {
    try {
      final dbPath = await _resolveDbPath();
      final core = await IdmCore.init(dbPath);
      setState(() {
        _core = core;
        _error = null;
      });
      await _refresh();
      _timer = Timer.periodic(const Duration(seconds: 2), (_) => _refresh());
    } catch (err) {
      setState(() {
        _error = err.toString();
      });
    }
  }

  void _showSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  bool _ensureCore() {
    if (_core != null) {
      return true;
    }
    if (_error != null) {
      _showSnack('Core belum siap: $_error');
    } else {
      _showSnack('Core belum siap, coba lagi sebentar.');
    }
    return false;
  }

  Future<String> _resolveDbPath() async {
    final dir = await getApplicationDocumentsDirectory();
    final dbDir = Directory('${dir.path}/idm_open');
    if (!dbDir.existsSync()) {
      dbDir.createSync(recursive: true);
    }
    return '${dbDir.path}/idm.db';
  }

  @override
  void dispose() {
    _timer?.cancel();
    _core?.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    final core = _core;
    if (core == null) {
      return;
    }
    final json = core.listTasksJson();
    if (json == null) {
      return;
    }
    final decoded = jsonDecode(json) as List<dynamic>;
    final tasks = decoded
        .map((item) => Task.fromJson(item as Map<String, dynamic>))
        .toList();
    setState(() {
      _tasks = tasks;
    });
  }

  Future<void> _addTask() async {
    if (!_ensureCore()) {
      return;
    }
    final core = _core!;
    final result = await showDialog<_AddTaskResult>(
      context: context,
      builder: (context) => const _AddTaskDialog(),
    );
    if (result == null) {
      return;
    }
    final id = core.addTask(result.url, result.dest);
    if (id == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Gagal menambah task')),
      );
      return;
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Task ditambahkan: ${id.substring(0, 8)}')),
    );
    await _refresh();
  }

  void _enqueue() {
    if (!_ensureCore()) {
      return;
    }
    _core!.enqueueQueued();
    _refresh();
  }

  void _startNext() {
    if (!_ensureCore()) {
      return;
    }
    _core!.enqueueQueued();
    _core!.startNext();
    _refresh();
  }

  void _pause(Task task) {
    if (!_ensureCore()) {
      return;
    }
    _core!.pauseTask(task.id);
    _refresh();
  }

  void _resume(Task task) {
    if (!_ensureCore()) {
      return;
    }
    _core!.resumeTask(task.id);
    _refresh();
  }

  void _cancel(Task task) {
    if (!_ensureCore()) {
      return;
    }
    _core!.cancelTask(task.id);
    _refresh();
  }

  @override
  Widget build(BuildContext context) {
    final theme = ThemeData(
      colorScheme: ColorScheme.fromSeed(
        seedColor: const Color(0xFF1B1F24),
        primary: const Color(0xFF1B1F24),
        secondary: const Color(0xFFF0B429),
      ),
      textTheme: GoogleFonts.spaceGroteskTextTheme(),
      useMaterial3: true,
    );

    return MaterialApp(
      title: 'IDM-Open',
      theme: theme,
      home: Scaffold(
        appBar: AppBar(
          title: const Text('IDM-Open'),
          actions: [
            IconButton(
              onPressed: _refresh,
              icon: const Icon(Icons.refresh),
            )
          ],
        ),
        body: _error != null
            ? Center(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text('Core gagal diinisialisasi'),
                      const SizedBox(height: 8),
                      Text(_error!, textAlign: TextAlign.center),
                      const SizedBox(height: 12),
                      OutlinedButton(
                        onPressed: _initCore,
                        child: const Text('Coba lagi'),
                      ),
                    ],
                  ),
                ),
              )
            : _tasks.isEmpty
                ? const Center(child: Text('Belum ada task'))
                : ListView.builder(
                    padding: const EdgeInsets.all(12),
                    itemCount: _tasks.length,
                    itemBuilder: (context, index) {
                      final task = _tasks[index];
                      return _TaskCard(
                        task: task,
                        onPause: () => _pause(task),
                        onResume: () => _resume(task),
                        onCancel: () => _cancel(task),
                      );
                    },
                  ),
        floatingActionButton: FloatingActionButton(
          onPressed: _addTask,
          child: const Icon(Icons.add),
        ),
        bottomNavigationBar: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          color: theme.colorScheme.surface,
          child: Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: _enqueue,
                  icon: const Icon(Icons.queue),
                  label: const Text('Enqueue'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: _startNext,
                  icon: const Icon(Icons.play_arrow),
                  label: const Text('Start Next'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TaskCard extends StatelessWidget {
  const _TaskCard({
    required this.task,
    required this.onPause,
    required this.onResume,
    required this.onCancel,
  });

  final Task task;
  final VoidCallback onPause;
  final VoidCallback onResume;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final status = task.status.toLowerCase();
    final progress = task.progress;
    final percent = (progress * 100).clamp(0, 100).toStringAsFixed(1);
    final subtitle = task.destPath.isNotEmpty ? task.destPath : task.url;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(task.url, maxLines: 1, overflow: TextOverflow.ellipsis),
            const SizedBox(height: 6),
            Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis),
            const SizedBox(height: 8),
            LinearProgressIndicator(
              value: task.totalBytes > 0 ? progress : null,
            ),
            const SizedBox(height: 6),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('${status.toUpperCase()} $percent%'),
                if (task.error != null)
                  const Icon(Icons.warning, color: Colors.redAccent),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                TextButton.icon(
                  onPressed: status == 'active' ? onPause : null,
                  icon: const Icon(Icons.pause),
                  label: const Text('Pause'),
                ),
                TextButton.icon(
                  onPressed: status == 'paused' || status == 'failed' ? onResume : null,
                  icon: const Icon(Icons.play_arrow),
                  label: const Text('Resume'),
                ),
                TextButton.icon(
                  onPressed: onCancel,
                  icon: const Icon(Icons.stop),
                  label: const Text('Cancel'),
                ),
              ],
            )
          ],
        ),
      ),
    );
  }
}

class _AddTaskDialog extends StatefulWidget {
  const _AddTaskDialog();

  @override
  State<_AddTaskDialog> createState() => _AddTaskDialogState();
}

class _AddTaskDialogState extends State<_AddTaskDialog> {
  final _urlController = TextEditingController();
  final _destController = TextEditingController();

  @override
  void dispose() {
    _urlController.dispose();
    _destController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Tambah Download'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _urlController,
            decoration: const InputDecoration(labelText: 'URL'),
          ),
          TextField(
            controller: _destController,
            decoration: const InputDecoration(
              labelText: 'Dest (opsional)',
              hintText: '/storage/emulated/0/Download/file.bin',
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Batal'),
        ),
        ElevatedButton(
          onPressed: () {
            final url = _urlController.text.trim();
            final dest = _destController.text.trim();
            if (url.isEmpty) {
              return;
            }
            Navigator.pop(context, _AddTaskResult(url: url, dest: dest));
          },
          child: const Text('Tambah'),
        ),
      ],
    );
  }
}

class _AddTaskResult {
  const _AddTaskResult({required this.url, required this.dest});

  final String url;
  final String dest;
}
