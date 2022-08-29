DROP TABLE IF EXISTS rede.fact_lead_3p_flows;
CREATE TABLE rede.fact_lead_3p_flows (
    sk_lead_3p BIGINT,
    sk_file BIGINT,
    sk_company BIGINT,
    sk_lead_3p_status BIGINT,
    sk_house BIGINT,
    sk_lead_date BIGINT,
    sk_prospect_date BIGINT,
    sk_qualified_date BIGINT,
    sk_opportunity_date BIGINT,
    sk_first_listing_date BIGINT,
    days_lead_to_prospect INTEGER,
    days_lead_to_qualified INTEGER,
    days_lead_to_opportunity INTEGER,
    days_lead_to_first_listing INTEGER,
    ts_lead TIMESTAMP,
    ts_prospect TIMESTAMP,
    ts_qualified TIMESTAMP,
    ts_opportunity TIMESTAMP,
    ts_first_listing TIMESTAMP,
    ts_load TIMESTAMP
);
ALTER TABLE rede.fact_lead_3p_flows OWNER TO airflow;