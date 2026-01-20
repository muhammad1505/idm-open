use std::ffi::{CStr, CString};
use std::os::raw::c_char;
use std::ptr;
use std::sync::Mutex;

use idm_core::config::EngineConfig;
use idm_core::storage::SqliteStorage;
use idm_core::{DownloadEngine, TaskId};

fn cstr_to_string(ptr: *const c_char) -> Option<String> {
    if ptr.is_null() {
        return None;
    }
    Some(unsafe { CStr::from_ptr(ptr) }.to_string_lossy().to_string())
}

pub struct EngineHandle {
    engine: Mutex<DownloadEngine>,
}

#[no_mangle]
pub extern "C" fn idm_engine_new() -> *mut EngineHandle {
    let engine = DownloadEngine::new(EngineConfig::default());
    let handle = EngineHandle {
        engine: Mutex::new(engine),
    };
    Box::into_raw(Box::new(handle))
}

#[no_mangle]
pub extern "C" fn idm_engine_new_with_db(path: *const c_char) -> *mut EngineHandle {
    let Some(path) = cstr_to_string(path) else {
        return ptr::null_mut();
    };
    let mut engine = DownloadEngine::new(EngineConfig::default());
    let storage = match SqliteStorage::new(path) {
        Ok(storage) => storage,
        Err(_) => return ptr::null_mut(),
    };
    engine = engine.with_storage(Box::new(storage));
    let handle = EngineHandle {
        engine: Mutex::new(engine),
    };
    Box::into_raw(Box::new(handle))
}

#[no_mangle]
pub extern "C" fn idm_engine_free(ptr: *mut EngineHandle) {
    if ptr.is_null() {
        return;
    }
    unsafe {
        drop(Box::from_raw(ptr));
    }
}

#[no_mangle]
pub extern "C" fn idm_engine_add_task(
    ptr: *mut EngineHandle,
    url: *const c_char,
    dest_path: *const c_char,
) -> *mut c_char {
    if ptr.is_null() || url.is_null() || dest_path.is_null() {
        return ptr::null_mut();
    }

    let url = unsafe { CStr::from_ptr(url) }.to_string_lossy().to_string();
    let dest_path = unsafe { CStr::from_ptr(dest_path) }
        .to_string_lossy()
        .to_string();

    let handle = unsafe { &*ptr };
    let engine = match handle.engine.lock() {
        Ok(guard) => guard,
        Err(_) => return ptr::null_mut(),
    };

    match engine.add_task(url, dest_path) {
        Ok(id) => CString::new(id.to_string())
            .map(|s| s.into_raw())
            .unwrap_or(ptr::null_mut()),
        Err(_) => ptr::null_mut(),
    }
}

#[no_mangle]
pub extern "C" fn idm_engine_start_next(ptr: *mut EngineHandle) -> *mut c_char {
    if ptr.is_null() {
        return ptr::null_mut();
    }
    let handle = unsafe { &*ptr };
    let engine = match handle.engine.lock() {
        Ok(guard) => guard,
        Err(_) => return ptr::null_mut(),
    };

    match engine.start_next() {
        Ok(Some(id)) => CString::new(id.to_string())
            .map(|s| s.into_raw())
            .unwrap_or(ptr::null_mut()),
        _ => ptr::null_mut(),
    }
}

#[no_mangle]
pub extern "C" fn idm_engine_enqueue_queued(ptr: *mut EngineHandle) -> i32 {
    if ptr.is_null() {
        return -1;
    }
    let handle = unsafe { &*ptr };
    let engine = match handle.engine.lock() {
        Ok(guard) => guard,
        Err(_) => return -1,
    };
    match engine.enqueue_queued() {
        Ok(count) => count as i32,
        Err(_) => -1,
    }
}

#[no_mangle]
pub extern "C" fn idm_engine_list_tasks_json(ptr: *mut EngineHandle) -> *mut c_char {
    if ptr.is_null() {
        return ptr::null_mut();
    }
    let handle = unsafe { &*ptr };
    let engine = match handle.engine.lock() {
        Ok(guard) => guard,
        Err(_) => return ptr::null_mut(),
    };
    match engine.list_tasks() {
        Ok(tasks) => serde_json::to_string(&tasks)
            .ok()
            .and_then(|value| CString::new(value).ok())
            .map(|value| value.into_raw())
            .unwrap_or(ptr::null_mut()),
        Err(_) => ptr::null_mut(),
    }
}

#[no_mangle]
pub extern "C" fn idm_engine_get_task_json(
    ptr: *mut EngineHandle,
    id: *const c_char,
) -> *mut c_char {
    if ptr.is_null() {
        return ptr::null_mut();
    }
    let Some(id) = cstr_to_string(id) else {
        return ptr::null_mut();
    };
    let task_id = match TaskId::parse_str(&id) {
        Ok(value) => value,
        Err(_) => return ptr::null_mut(),
    };
    let handle = unsafe { &*ptr };
    let engine = match handle.engine.lock() {
        Ok(guard) => guard,
        Err(_) => return ptr::null_mut(),
    };
    match engine.get_task(&task_id) {
        Ok(task) => serde_json::to_string(&task)
            .ok()
            .and_then(|value| CString::new(value).ok())
            .map(|value| value.into_raw())
            .unwrap_or(ptr::null_mut()),
        Err(_) => ptr::null_mut(),
    }
}

#[no_mangle]
pub extern "C" fn idm_engine_pause_task(ptr: *mut EngineHandle, id: *const c_char) -> i32 {
    control_task(ptr, id, |engine, task_id| engine.pause_task(task_id))
}

#[no_mangle]
pub extern "C" fn idm_engine_resume_task(ptr: *mut EngineHandle, id: *const c_char) -> i32 {
    control_task(ptr, id, |engine, task_id| engine.resume_task(task_id))
}

#[no_mangle]
pub extern "C" fn idm_engine_cancel_task(ptr: *mut EngineHandle, id: *const c_char) -> i32 {
    control_task(ptr, id, |engine, task_id| engine.cancel_task(task_id))
}

#[no_mangle]
pub extern "C" fn idm_engine_remove_task(ptr: *mut EngineHandle, id: *const c_char) -> i32 {
    control_task(ptr, id, |engine, task_id| engine.remove_task(task_id))
}

fn control_task<F>(ptr: *mut EngineHandle, id: *const c_char, f: F) -> i32
where
    F: FnOnce(&DownloadEngine, &TaskId) -> Result<(), idm_core::CoreError>,
{
    if ptr.is_null() {
        return -1;
    }
    let Some(id) = cstr_to_string(id) else {
        return -1;
    };
    let task_id = match TaskId::parse_str(&id) {
        Ok(value) => value,
        Err(_) => return -1,
    };
    let handle = unsafe { &*ptr };
    let engine = match handle.engine.lock() {
        Ok(guard) => guard,
        Err(_) => return -1,
    };
    match f(&engine, &task_id) {
        Ok(()) => 0,
        Err(_) => -1,
    }
}

#[no_mangle]
pub extern "C" fn idm_string_free(s: *mut c_char) {
    if s.is_null() {
        return;
    }
    unsafe {
        drop(CString::from_raw(s));
    }
}
