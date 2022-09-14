CREATE TABLE public.dim_country (
    sk_country_code VARCHAR PRIMARY KEY,
    id_country INTEGER,
    country_code VARCHAR,
    country_name VARCHAR,
    default_locale VARCHAR,
    default_timezone VARCHAR,
    ts_created TIMESTAMP,
    ts_updated TIMESTAMP,
    ts_load TIMESTAMP
);

ALTER TABLE public.dim_country OWNER TO databricks;
