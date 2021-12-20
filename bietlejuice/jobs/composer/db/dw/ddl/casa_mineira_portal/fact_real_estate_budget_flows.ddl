DROP TABLE IF EXISTS casa_mineira_portal.fact_real_estate_budget_flows;
CREATE TABLE IF NOT EXISTS casa_mineira_portal.fact_real_estate_budget_flows (
    sk_real_estate_budget_flow BIGINT PRIMARY KEY,
    sk_real_estate_agency INT,
    sk_month_started_date INT,
    month_budget FLOAT,
    dt_month_started DATE,
    ts_load TIMESTAMP
);
ALTER TABLE casa_mineira_portal.fact_real_estate_budget_flows OWNER TO databricks;
