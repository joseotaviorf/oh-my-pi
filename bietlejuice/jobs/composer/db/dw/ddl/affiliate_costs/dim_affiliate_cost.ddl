DROP TABLE IF EXISTS public.dim_affiliate_cost;
CREATE TABLE IF NOT EXISTS public.dim_affiliate_cost (
    sk_rh_accounting_entry VARCHAR(50),
    city_group VARCHAR(50),
    description VARCHAR(255),
    source_bill_item VARCHAR(50),
    comission_type VARCHAR(50),
    mkt_origin VARCHAR(50),
    ts_load TIMESTAMP,
);
ALTER TABLE public.dim_affiliate_cost OWNER TO airflow;