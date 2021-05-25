DROP TABLE IF EXISTS front_tickets.dim_department;
CREATE TABLE IF NOT EXISTS front_tickets.dim_department (
    sk_department VARCHAR(40),
    department VARCHAR(100),
    board VARCHAR,
    team VARCHAR,
    journey_step VARCHAR,
    channel VARCHAR,
    concentrix_area_name VARCHAR,
    is_concentrix BOOLEAN,
    is_active BOOLEAN,
    ts_load TIMESTAMP
);
ALTER TABLE front_tickets.dim_department OWNER TO airflow;