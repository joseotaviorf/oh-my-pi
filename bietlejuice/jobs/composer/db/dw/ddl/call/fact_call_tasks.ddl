DROP TABLE IF EXISTS call.fact_call_tasks;
CREATE TABLE IF NOT EXISTS call.fact_call_tasks (
    sk_task VARCHAR(50),
    sk_call VARCHAR(50),
    sk_agent VARCHAR(50),
    sk_queue VARCHAR(50),
    is_answered BOOLEAN,
    is_timeout BOOLEAN,
    is_rejected BOOLEAN,
    seconds_duration INTEGER,
    seconds_wait_time INTEGER,
    seconds_talk_time INTEGER
);
ALTER TABLE call.fact_call_tasks OWNER TO airflow;
