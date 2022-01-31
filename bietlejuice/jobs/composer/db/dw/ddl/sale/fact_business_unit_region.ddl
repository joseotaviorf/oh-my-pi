DROP TABLE IF EXISTS sale.fact_business_unit_region;
CREATE TABLE IF NOT EXISTS sale.fact_business_unit_region (
    sk_region BIGINT,
    sk_coverage_started_date BIGINT,
    sk_coverage_ended_date BIGINT,
    business_model VARCHAR,
    business_unit VARCHAR,
    dt_coverage_started DATE,
    dt_coverage_ended DATE,
    ts_load TIMESTAMP
);
ALTER TABLE sale.fact_business_unit_region OWNER TO databricks;
