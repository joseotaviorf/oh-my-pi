DROP TABLE IF EXISTS public.fact_affiliate_costs;
CREATE TABLE IF NOT EXISTS public.fact_affiliate_costs (
    sk_rh_accounting_entry VARCHAR(50),
    sk_date VARCHAR(100),
    sk_user BIGINT,
    cost FLOAT,
    tax FLOAT,
    ts_load TIMESTAMP,
);
ALTER TABLE public.fact_affiliate_costs OWNER TO airflow;
