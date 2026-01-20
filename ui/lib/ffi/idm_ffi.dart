import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';

class IdmCore {
  IdmCore._(this._lib, this._engine);

  final DynamicLibrary _lib;
  final Pointer<Void> _engine;

  late final _EngineFree _engineFree =
      _lib.lookupFunction<_EngineFreeNative, _EngineFree>('idm_engine_free');
  late final _EngineAddTask _engineAddTask =
      _lib.lookupFunction<_EngineAddTaskNative, _EngineAddTask>('idm_engine_add_task');
  late final _EngineListTasksJson _engineListTasksJson = _lib
      .lookupFunction<_EngineListTasksJsonNative, _EngineListTasksJson>(
          'idm_engine_list_tasks_json');
  late final _EngineGetTaskJson _engineGetTaskJson = _lib
      .lookupFunction<_EngineGetTaskJsonNative, _EngineGetTaskJson>(
          'idm_engine_get_task_json');
  late final _EnginePause _enginePause =
      _lib.lookupFunction<_EnginePauseNative, _EnginePause>('idm_engine_pause_task');
  late final _EngineResume _engineResume =
      _lib.lookupFunction<_EngineResumeNative, _EngineResume>('idm_engine_resume_task');
  late final _EngineCancel _engineCancel =
      _lib.lookupFunction<_EngineCancelNative, _EngineCancel>('idm_engine_cancel_task');
  late final _EngineRemove _engineRemove =
      _lib.lookupFunction<_EngineRemoveNative, _EngineRemove>('idm_engine_remove_task');
  late final _EngineEnqueueQueued _engineEnqueueQueued = _lib
      .lookupFunction<_EngineEnqueueQueuedNative, _EngineEnqueueQueued>(
          'idm_engine_enqueue_queued');
  late final _EngineStartNext _engineStartNext =
      _lib.lookupFunction<_EngineStartNextNative, _EngineStartNext>(
          'idm_engine_start_next');
  late final _StringFree _stringFree =
      _lib.lookupFunction<_StringFreeNative, _StringFree>('idm_string_free');

  static Future<IdmCore> init(String dbPath) async {
    final lib = _openLibrary();
    final engineNewWithDb = lib.lookupFunction<_EngineNewWithDbNative,
        _EngineNewWithDb>('idm_engine_new_with_db');
    final pathPtr = dbPath.toNativeUtf8();
    final engine = engineNewWithDb(pathPtr);
    calloc.free(pathPtr);
    if (engine == nullptr) {
      throw StateError('Failed to open SQLite database');
    }
    return IdmCore._(lib, engine);
  }

  void dispose() {
    _engineFree(_engine);
  }

  String? addTask(String url, String dest) {
    final urlPtr = url.toNativeUtf8();
    final destPtr = dest.toNativeUtf8();
    final result = _engineAddTask(_engine, urlPtr, destPtr);
    calloc.free(urlPtr);
    calloc.free(destPtr);
    return _consumeString(result);
  }

  int enqueueQueued() {
    return _engineEnqueueQueued(_engine);
  }

  String? startNext() {
    final result = _engineStartNext(_engine);
    return _consumeString(result);
  }

  String? listTasksJson() {
    final result = _engineListTasksJson(_engine);
    return _consumeString(result);
  }

  String? getTaskJson(String id) {
    final idPtr = id.toNativeUtf8();
    final result = _engineGetTaskJson(_engine, idPtr);
    calloc.free(idPtr);
    return _consumeString(result);
  }

  bool pauseTask(String id) => _controlTask(id, _enginePause);
  bool resumeTask(String id) => _controlTask(id, _engineResume);
  bool cancelTask(String id) => _controlTask(id, _engineCancel);
  bool removeTask(String id) => _controlTask(id, _engineRemove);

  bool _controlTask(String id, _EngineControl fn) {
    final idPtr = id.toNativeUtf8();
    final result = fn(_engine, idPtr);
    calloc.free(idPtr);
    return result == 0;
  }

  String? _consumeString(Pointer<Utf8> ptr) {
    if (ptr == nullptr) {
      return null;
    }
    final value = ptr.toDartString();
    _stringFree(ptr.cast());
    return value;
  }
}

DynamicLibrary _openLibrary() {
  if (Platform.isAndroid || Platform.isLinux) {
    return DynamicLibrary.open('libidm_core_ffi.so');
  }
  if (Platform.isWindows) {
    return DynamicLibrary.open('idm_core_ffi.dll');
  }
  return DynamicLibrary.process();
}

typedef _EngineNewWithDbNative = Pointer<Void> Function(Pointer<Utf8>);
typedef _EngineNewWithDb = Pointer<Void> Function(Pointer<Utf8>);

typedef _EngineFreeNative = Void Function(Pointer<Void>);
typedef _EngineFree = void Function(Pointer<Void>);

typedef _EngineAddTaskNative = Pointer<Utf8> Function(
    Pointer<Void>, Pointer<Utf8>, Pointer<Utf8>);
typedef _EngineAddTask = Pointer<Utf8> Function(
    Pointer<Void>, Pointer<Utf8>, Pointer<Utf8>);

typedef _EngineListTasksJsonNative = Pointer<Utf8> Function(Pointer<Void>);
typedef _EngineListTasksJson = Pointer<Utf8> Function(Pointer<Void>);

typedef _EngineGetTaskJsonNative = Pointer<Utf8> Function(
    Pointer<Void>, Pointer<Utf8>);
typedef _EngineGetTaskJson = Pointer<Utf8> Function(
    Pointer<Void>, Pointer<Utf8>);

typedef _EnginePauseNative = Int32 Function(Pointer<Void>, Pointer<Utf8>);
typedef _EnginePause = int Function(Pointer<Void>, Pointer<Utf8>);

typedef _EngineResumeNative = Int32 Function(Pointer<Void>, Pointer<Utf8>);
typedef _EngineResume = int Function(Pointer<Void>, Pointer<Utf8>);

typedef _EngineCancelNative = Int32 Function(Pointer<Void>, Pointer<Utf8>);
typedef _EngineCancel = int Function(Pointer<Void>, Pointer<Utf8>);

typedef _EngineRemoveNative = Int32 Function(Pointer<Void>, Pointer<Utf8>);
typedef _EngineRemove = int Function(Pointer<Void>, Pointer<Utf8>);

typedef _EngineControl = int Function(Pointer<Void>, Pointer<Utf8>);

typedef _EngineEnqueueQueuedNative = Int32 Function(Pointer<Void>);
typedef _EngineEnqueueQueued = int Function(Pointer<Void>);

typedef _EngineStartNextNative = Pointer<Utf8> Function(Pointer<Void>);
typedef _EngineStartNext = Pointer<Utf8> Function(Pointer<Void>);

typedef _StringFreeNative = Void Function(Pointer<Void>);
typedef _StringFree = void Function(Pointer<Void>);
