DROP TABLE IF EXISTS rede.dim_lead_3p_context;
CREATE TABLE rede.dim_lead_3p_context (
    sk_lead_3p_context INTEGER PRIMARY KEY,
    business_context VARCHAR,
    recurrency_type VARCHAR,
    is_for_sale BOOLEAN,
    is_for_rent BOOLEAN,
    is_first_batch BOOLEAN,
    is_first_month_batch BOOLEAN,
    is_complementary BOOLEAN,
    is_recurrent BOOLEAN,
    ts_load TIMESTAMP
);
ALTER TABLE rede.dim_lead_3p_context OWNER TO airflow;