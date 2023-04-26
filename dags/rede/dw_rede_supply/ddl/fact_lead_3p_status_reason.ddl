DROP TABLE IF EXISTS rede.fact_lead_3p_status_reason;
CREATE TABLE rede.fact_lead_3p_status_reason (
    sk_reason_event BIGINT,
    sk_lead_3p_flow BIGINT,
    sk_lead_3p BIGINT,
    sk_lead_3p_context INTEGER,
    sk_company BIGINT,
    sk_file BIGINT,
    sk_lead_3p_reason BIGINT,
    sk_region BIGINT,
    sk_reason_started_date BIGINT,
    sk_reason_ended_date BIGINT,
    sk_status_when_reason_started BIGINT,
    sk_status_when_reason_ended BIGINT,
    days_in_reason INT,
    is_requirement_met BOOLEAN,
    ts_reason_started TIMESTAMP,
    ts_reason_ended TIMESTAMP,
    ts_load TIMESTAMP
);
ALTER TABLE rede.fact_lead_3p_status_reason OWNER TO airflow;