# Database schema (SQLite)

## tasks
```
CREATE TABLE tasks (
  id TEXT PRIMARY KEY,
  url TEXT NOT NULL,
  dest_path TEXT NOT NULL,
  status TEXT NOT NULL,
  priority INTEGER NOT NULL DEFAULT 0,
  total_bytes INTEGER DEFAULT 0,
  downloaded_bytes INTEGER DEFAULT 0,
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL,
  error TEXT,
  checksum_type TEXT,
  checksum_hex TEXT,
  proxy_url TEXT,
  auth_user TEXT,
  auth_pass TEXT
);
```

## segments
```
CREATE TABLE segments (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  task_id TEXT NOT NULL,
  segment_index INTEGER NOT NULL,
  range_start INTEGER NOT NULL,
  range_end INTEGER NOT NULL,
  downloaded_bytes INTEGER NOT NULL DEFAULT 0,
  status TEXT NOT NULL,
  FOREIGN KEY(task_id) REFERENCES tasks(id)
);
```

## headers
```
CREATE TABLE headers (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  task_id TEXT NOT NULL,
  name TEXT NOT NULL,
  value TEXT NOT NULL,
  FOREIGN KEY(task_id) REFERENCES tasks(id)
);
```

## cookies
```
CREATE TABLE cookies (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  task_id TEXT NOT NULL,
  name TEXT NOT NULL,
  value TEXT NOT NULL,
  domain TEXT,
  path TEXT,
  FOREIGN KEY(task_id) REFERENCES tasks(id)
);
```

## mirrors
```
CREATE TABLE mirrors (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  task_id TEXT NOT NULL,
  url TEXT NOT NULL,
  rank INTEGER NOT NULL DEFAULT 0,
  FOREIGN KEY(task_id) REFERENCES tasks(id)
);
```

## events
```
CREATE TABLE events (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  task_id TEXT NOT NULL,
  event_type TEXT NOT NULL,
  payload TEXT,
  created_at INTEGER NOT NULL,
  FOREIGN KEY(task_id) REFERENCES tasks(id)
);
```
