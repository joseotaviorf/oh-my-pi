DROP TABLE IF EXISTS sale.fact_sale_cohort_conversion;
CREATE TABLE sale.fact_sale_cohort_conversion (
    sk_sale_cohort_conversion VARCHAR,
    sk_base_date BIGINT,
    sk_conversion_date BIGINT,
    sk_cohort_type VARCHAR,
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
    days_to_conversion INT,
    week_number INT,
    year INT,
    month INT,
    day INT,
    ts_load TIMESTAMP
)
SORTKEY(sk_base_date)
;
ALTER TABLE sale.fact_sale_cohort_conversion OWNER TO airflow;
