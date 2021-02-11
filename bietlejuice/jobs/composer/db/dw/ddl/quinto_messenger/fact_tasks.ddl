DROP TABLE IF EXISTS quinto_messenger.fact_tasks;
CREATE TABLE IF NOT EXISTS quinto_messenger.fact_tasks (
    sk_task VARCHAR(100) PRIMARY KEY,
    sk_chat VARCHAR(100),
    sk_quinto_messenger_agent VARCHAR(100),
    sk_created_date BIGINT,
    is_forwarded BOOLEAN,
    seconds_first_reply BIGINT,
    task_number INTEGER,
    ts_load TIMESTAMP
)
ALTER TABLE quinto_messenger.fact_tasks OWNER TO airflow;
