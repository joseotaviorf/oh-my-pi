DROP TABLE IF EXISTS call.fact_calls;
CREATE TABLE IF NOT EXISTS call.fact_calls (
    sk_call VARCHAR(40),
    sk_user BIGINT,
    sk_personal_document VARCHAR(20),
    sk_call_date BIGINT,
    last_queue_name VARCHAR(100),
    has_ended_in_ura BOOLEAN,
    is_answered BOOLEAN,
    is_transfered BOOLEAN,
    is_csat_answered BOOLEAN,
    is_solved BOOLEAN,
    tasks BIGINT,
    answered_tasks BIGINT,
    seconds_first_answer DOUBLE PRECISION,
    seconds_ivr_time  BIGINT,
    seconds_total_wait_time DOUBLE PRECISION,
    seconds_total_talk_time DOUBLE PRECISION,
    seconds_wrapup_time BIGINT,
    seconds_aht BIGINT,
    seconds_duration BIGINT,
    csat_rating INTEGER,
    is_scheduled BOOLEAN,
    ts_load TIMESTAMP
);
ALTER TABLE call.fact_calls OWNER TO databricks;
