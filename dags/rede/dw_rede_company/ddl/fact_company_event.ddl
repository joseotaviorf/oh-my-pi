DROP TABLE IF EXISTS rede.fact_company_event;
CREATE TABLE rede.fact_company_event (
    sk_company_event VARCHAR PRIMARY KEY,
    sk_event_date BIGINT,
    sk_company BIGINT,
    sk_company_event_type BIGINT,
    sk_company_journey BIGINT,
    journey_number BIGINT,
    ts_event TIMESTAMP,
    ts_load TIMESTAMP
);
ALTER TABLE rede.fact_company_event OWNER TO airflow;
