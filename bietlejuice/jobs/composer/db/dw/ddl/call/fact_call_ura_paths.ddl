DROP TABLE IF EXISTS call.fact_call_ura_paths;
CREATE TABLE IF NOT EXISTS call.fact_call_ura_paths (
    sk_call VARCHAR(30),
    sk_flow_step BIGINT,
    sk_started INT,
    sk_call_date INT,
    sk_call_date_local INT,
    flow_step_name VARCHAR(20),
    ura_step_name VARCHAR(40),
    option_answered VARCHAR(10),
    seconds_ura_step_duration BIGINT,
    ts_created TIMESTAMP,
    ts_created_local TIMESTAMP,
    ts_load TIMESTAMP
)
ALTER TABLE call.fact_call_ura_paths OWNER TO airflow;
