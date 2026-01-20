use thiserror::Error;

#[derive(Error, Debug)]
pub enum CoreError {
    #[error("invalid task state: {0}")]
    InvalidState(String),
    #[error("task not found: {0}")]
    NotFound(String),
    #[error("network error: {0}")]
    Network(String),
    #[error("storage error: {0}")]
    Storage(String),
    #[error("io error: {0}")]
    Io(String),
    #[error("unsupported: {0}")]
    Unsupported(String),
}

pub type CoreResult<T> = Result<T, CoreError>;
