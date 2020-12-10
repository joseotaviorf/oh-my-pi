DROP TABLE IF EXISTS call.dim_call_task;
CREATE TABLE IF NOT EXISTS call.dim_call_task (
    sk_task VARCHAR(50),
    queue_name VARCHAR(100),
    ts_created TIMESTAMP,
    ts_ended TIMESTAMP,
    dt_updated DATE
);
ALTER TABLE call.dim_call_task OWNER TO airflow;
