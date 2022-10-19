DROP TABLE IF EXISTS sale.dim_sale_event_type;
CREATE TABLE sale.dim_sale_event_type (
    sk_event_type INTEGER PRIMARY KEY,
    event_name VARCHAR,
    abbreviation VARCHAR,
    stage VARCHAR
);
ALTER TABLE sale.dim_sale_event_type OWNER TO airflow;
