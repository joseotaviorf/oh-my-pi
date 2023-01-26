DROP TABLE IF EXISTS sale.fact_sale_demand_event;
CREATE TABLE sale.fact_sale_demand_event (
    sk_sale_demand_event VARCHAR,
    sk_event_date BIGINT,
    sk_event_type INTEGER,
    sk_booking BIGINT,
    sk_offer VARCHAR,
    sk_house BIGINT,
    sk_region BIGINT,
    sk_buyer BIGINT,
    sk_seller BIGINT,
    sk_agent BIGINT,
    sk_agent_work_contract BIGINT,
    sk_business_unit BIGINT,
    sk_company_supply BIGINT,
    sk_company_demand BIGINT,
    year INT,
    month INT,
    day INT,
    ts_load TIMESTAMP
)
SORTKEY(sk_event_date)
;
ALTER TABLE sale.fact_sale_demand_event OWNER TO airflow;
