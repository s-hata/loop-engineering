PRAGMA jounal_mode = WAL;
PRAGMA foreign_keys = ON;

CREATE TABLE IF NOT EXISTS tasks (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  definition_path TEXT NOT NULL,
  branch TEXT,
  worktree TEXT,
  status TEXT NOT NULL DEFAULT 'queued'
         CHECK (
          status IN (
            'queued',
            'running',
            'testing',
            'repairing',
            'completed',
            'failed'
      )
      ),
  attempt INTEGER NOT NULL DEFAULT 0,
  last_error TEXT,
  result_commit TEXT,
  created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
  started_at TEXT,
  finished_at TEXT,
  updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS attempts (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  task_id INTEGER NOT NULL,
  attempt INTEGER NOT NULL,
  phase TEXT NOT NULL
        CHECK (
          phase IN (
            'implement',
            'repair',
            'test',
            'verify'
          )
        ),
  status TEXT NOT NULL,
  log_path TEXT,
  started_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
  finished_at TEXT,

  FOREIGN KEY(task_id)
    REFERENCES tasks(id)
    ON DELETE CASCADE
);

CREATE INDEX IF NOT EXISTS idx_tasks_status
ON tasks(status);
