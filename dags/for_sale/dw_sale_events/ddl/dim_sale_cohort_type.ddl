DROP TABLE IF EXISTS sale.dim_sale_cohort_type;
CREATE TABLE sale.dim_sale_cohort_type (
    sk_cohort_type VARCHAR PRIMARY KEY,
    week_number_up_to_20 VARCHAR,
    week_number_up_to_5 VARCHAR,
    calendar_days VARCHAR,
    calendar_days_exponential VARCHAR,
    calendar_days_by_week VARCHAR,
    calendar_days_by_month VARCHAR,
    conversion_abbreviation VARCHAR,
    conversion_name VARCHAR,
    first_event_abbreviation VARCHAR,
    second_event_abbreviation VARCHAR,
    first_event_name VARCHAR,
    second_event_name VARCHAR,
    ts_load TIMESTAMP
);
ALTER TABLE sale.dim_sale_cohort_type OWNER TO airflow;
