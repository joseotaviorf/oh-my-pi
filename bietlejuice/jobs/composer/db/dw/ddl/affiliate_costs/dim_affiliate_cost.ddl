DROP TABLE IF EXISTS quintoandar.dim_affiliate_cost;
CREATE TABLE IF NOT EXISTS quintoandar.dim_affiliate_cost (
    sk_rh_accounting_entry BIGINT,
    sk_payee INTEGER,
    city_group VARCHAR(255),
    description VARCHAR(255),
    source_bill_item VARCHAR(255),
    commission_type VARCHAR(255),
    cost_center_code VARCHAR(255),
    mkt_origin VARCHAR(255),
    ts_load TIMESTAMP
);
ALTER TABLE quintoandar.dim_affiliate_cost OWNER TO airflow;