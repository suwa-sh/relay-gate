-- テスト fixture。正本は rdb-schema.yaml / worker/migrations(datastore_owner: tier-worker)。
-- facade/test/fixtures/generate-postgresql-schema.py が rdb-schema.yaml(version 1.0)の
-- transaction_rules「slot起動トランザクション」の tables から生成した。手動編集せず、正本の変更時に再生成する。

CREATE TABLE execution_specs (
  run_id uuid NOT NULL,
  parent_run_id uuid,
  job_id text NOT NULL,
  additional_args text,
  job_map_version text NOT NULL,
  hang_detect_limit_minutes integer NOT NULL,
  PRIMARY KEY (run_id),
  FOREIGN KEY (parent_run_id) REFERENCES execution_specs (run_id) ON DELETE SET NULL
);

CREATE INDEX idx_execution_specs_parent_run_id ON execution_specs (parent_run_id);

CREATE INDEX idx_execution_specs_job_id ON execution_specs (job_id);

CREATE TABLE slot_execution_specs (
  run_id uuid NOT NULL,
  slot_type text NOT NULL,
  host text NOT NULL,
  exec_user text NOT NULL,
  script_path text NOT NULL,
  work_dir text NOT NULL,
  fixed_args text,
  impl_version text NOT NULL,
  credential_ref text,
  PRIMARY KEY (run_id, slot_type),
  FOREIGN KEY (run_id) REFERENCES execution_specs (run_id) ON DELETE CASCADE
);

CREATE INDEX idx_slot_execution_specs_slot_type ON slot_execution_specs (slot_type);

CREATE TABLE runner_result_events (
  event_id uuid NOT NULL,
  run_id uuid NOT NULL,
  slot_type text NOT NULL,
  role_type text NOT NULL,
  attempt_id text NOT NULL,
  attempt_no integer NOT NULL,
  event_name text NOT NULL,
  status text NOT NULL,
  occurred_at timestamptz NOT NULL,
  started_at timestamptz,
  stdout_path text,
  stderr_path text,
  exit_code integer,
  PRIMARY KEY (event_id),
  CONSTRAINT uq_runner_result_events_attempt_event_name UNIQUE (run_id, slot_type, role_type, attempt_id, event_name),
  FOREIGN KEY (run_id) REFERENCES execution_specs (run_id) ON DELETE CASCADE
);

CREATE INDEX idx_runner_result_events_run_id_occurred_at ON runner_result_events (run_id, occurred_at);

CREATE TABLE runner_results (
  run_id uuid NOT NULL,
  slot_type text NOT NULL,
  role_type text NOT NULL,
  attempt_id text NOT NULL,
  attempt_no integer NOT NULL,
  accepted_at timestamptz NOT NULL,
  started_at timestamptz,
  stdout_path text,
  stderr_path text,
  exit_code integer,
  status text NOT NULL,
  updated_at timestamptz NOT NULL,
  PRIMARY KEY (run_id, slot_type, role_type, attempt_id),
  CONSTRAINT uq_runner_results_attempt_no UNIQUE (run_id, slot_type, role_type, attempt_no),
  FOREIGN KEY (run_id, slot_type) REFERENCES slot_execution_specs (run_id, slot_type) ON DELETE CASCADE
);

CREATE INDEX idx_runner_results_role_type_status ON runner_results (role_type, status);

CREATE INDEX idx_runner_results_slot_type_status ON runner_results (slot_type, status);

CREATE TABLE audit_logs (
  event_id uuid NOT NULL,
  event_name text NOT NULL,
  schema_version text NOT NULL,
  run_id uuid NOT NULL,
  parent_run_id uuid,
  slot text NOT NULL,
  attempt_id text NOT NULL,
  occurred_at timestamptz NOT NULL,
  actor text NOT NULL,
  operation text NOT NULL,
  outcome text NOT NULL,
  final_status text,
  error_code text,
  previous_hash text,
  event_hash text NOT NULL,
  PRIMARY KEY (event_id),
  CONSTRAINT uq_audit_logs_run_slot_attempt_event_name UNIQUE (run_id, slot, attempt_id, event_name)
);

CREATE INDEX idx_audit_logs_occurred_at ON audit_logs (occurred_at);

CREATE INDEX idx_audit_logs_run_id_occurred_at ON audit_logs (run_id, occurred_at);

CREATE INDEX idx_audit_logs_parent_run_id_occurred_at ON audit_logs (parent_run_id, occurred_at);

CREATE TABLE audit_chain_heads (
  run_id uuid NOT NULL,
  head_event_id uuid NOT NULL,
  head_hash text NOT NULL,
  chain_length integer NOT NULL,
  updated_at timestamptz NOT NULL,
  PRIMARY KEY (run_id)
);

CREATE INDEX idx_audit_chain_heads_updated_at ON audit_chain_heads (updated_at);
