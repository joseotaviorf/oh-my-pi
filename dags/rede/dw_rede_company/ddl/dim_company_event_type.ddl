DROP TABLE IF EXISTS rede.dim_company_event_type;
CREATE TABLE rede.dim_company_event_type (
    sk_company_event_type BIGINT PRIMARY KEY,
    business_context VARCHAR,
    event VARCHAR,
    event_type VARCHAR,
    source_type VARCHAR,
    hubspot_event_detail VARCHAR,
    hubspot_event_origin VARCHAR,
    hubspot_company_status VARCHAR,
    hubspot_deal_stage VARCHAR,
    hubspot_demand_onboarding_ticket_stage VARCHAR,
    hubspot_supply_onboarding_ticket_stage VARCHAR,
    ts_load TIMESTAMP
);
ALTER TABLE rede.dim_company_event_type OWNER TO airflow;
