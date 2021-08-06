DROP TABLE IF EXISTS customer_support.dim_department;
CREATE TABLE IF NOT EXISTS customer_support.dim_department (
    sk_department VARCHAR(40),
    department VARCHAR(100),
    board VARCHAR,
    team VARCHAR,
    journey_step VARCHAR,
    channel VARCHAR,
    front_or_back VARCHAR(10),
    area VARCHAR,
    concentrix_area_name VARCHAR,
    is_concentrix BOOLEAN,
    is_active BOOLEAN,
    ts_load TIMESTAMP
);
ALTER TABLE customer_support.dim_department OWNER TO airflow;