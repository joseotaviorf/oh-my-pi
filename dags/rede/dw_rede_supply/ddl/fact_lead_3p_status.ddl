DROP TABLE IF EXISTS rede.fact_lead_3p_status;
CREATE TABLE rede.fact_lead_3p_status (
    sk_status_event BIGINT PRIMARY KEY,
    sk_lead_3p_flow BIGINT,
    sk_lead_3p BIGINT,
    sk_lead_3p_context INTEGER,
    sk_file BIGINT,
    sk_company BIGINT,
    sk_house BIGINT,
    sk_lead_3p_status BIGINT,
    sk_status_started_date BIGINT,
    sk_status_ended_date BIGINT,
    days_in_status INTEGER,
    ts_status_started TIMESTAMP,
    ts_status_ended TIMESTAMP,
    ts_load TIMESTAMP
);
ALTER TABLE rede.fact_lead_3p_status OWNER TO airflow;