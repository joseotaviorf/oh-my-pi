DROP TABLE IF EXISTS call.dim_call_task;
CREATE TABLE IF NOT EXISTS call.dim_call_task (
    sk_task VARCHAR(50),
    queue_name VARCHAR(100),
    dt_updated DATE,
    ts_created TIMESTAMP,
    ts_ended TIMESTAMP,
    ts_twilio_created_local TIMESTAMP,
    ts_twilio_created_utc TIMESTAMP,
    ts_load TIMESTAMP
);
ALTER TABLE call.dim_call_task OWNER TO airflow;
