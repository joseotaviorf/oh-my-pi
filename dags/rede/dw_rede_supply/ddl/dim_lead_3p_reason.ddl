DROP TABLE IF EXISTS rede.dim_lead_3p_reason;
CREATE TABLE rede.dim_lead_3p_reason (
    sk_lead_3p_reason BIGINT,
    reason VARCHAR,
    reason_type VARCHAR,
    is_ineligible_reason BOOLEAN,
    is_discard_reason BOOLEAN,
    is_enrichment_reason BOOLEAN,
    ts_load TIMESTAMP
);
ALTER TABLE rede.dim_lead_3p_reason OWNER TO airflow;