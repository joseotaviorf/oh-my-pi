DROP TABLE IF EXISTS rede.dim_lead_3p_status;
CREATE TABLE rede.dim_lead_3p_status (
    sk_lead_3p_status BIGINT,
    status VARCHAR,
    growth_status VARCHAR,
    waiting_for_enrichment_indicator VARCHAR,
    ineligible_indicator VARCHAR,
    discarded_indicator VARCHAR,
    is_waiting_for_enrichment BOOLEAN,
    is_ineligible BOOLEAN,
    is_discarded BOOLEAN,
    ts_load TIMESTAMP
);
ALTER TABLE rede.dim_lead_3p_status OWNER TO airflow;