#[derive(Debug, Clone)]
pub struct Scheduler {
    pub max_active: usize,
}

impl Scheduler {
    pub fn new(max_active: usize) -> Self {
        Self { max_active }
    }

    pub fn can_start(&self, active_count: usize) -> bool {
        active_count < self.max_active
    }
}
