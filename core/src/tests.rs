use crate::config::EngineConfig;
use crate::engine::DownloadEngine;
use crate::task::TaskStatus;

#[test]
fn test_engine_basic_flow() {
    let config = EngineConfig::default();
    let engine = DownloadEngine::new(config);

    // 1. Add Task
    let url = "https://example.com/file.zip".to_string();
    let dest = "/tmp/file.zip".to_string();
    let id = engine.add_task(url.clone(), dest.clone()).expect("add_task failed");

    // 2. List Tasks
    let tasks = engine.list_tasks().expect("list_tasks failed");
    assert_eq!(tasks.len(), 1);
    assert_eq!(tasks[0].id, id);
    assert_eq!(tasks[0].url, url);
    assert_eq!(tasks[0].status, TaskStatus::Queued);

    // 3. Get Task
    let task = engine.get_task(&id).expect("get_task failed");
    assert_eq!(task.id, id);

    // 4. Remove Task
    engine.remove_task(&id).expect("remove_task failed");
    let tasks_after = engine.list_tasks().expect("list_tasks failed");
    assert!(tasks_after.is_empty());
}

#[test]
fn test_remove_non_existent_task() {
    let config = EngineConfig::default();
    let engine = DownloadEngine::new(config);
    // Remove random UUID
    let id = uuid::Uuid::new_v4();
    // Storage returns Ok(()) if not found usually? Or Err?
    // MemoryStorage implementation of delete_task:
    // fn delete_task(&mut self, id: &TaskId) -> CoreResult<()> {
    //    self.tasks.remove(id); ... Ok(())
    // }
    // HashMap remove returns value, but we ignore it. So it should return Ok.
    assert!(engine.remove_task(&id).is_ok());
}
