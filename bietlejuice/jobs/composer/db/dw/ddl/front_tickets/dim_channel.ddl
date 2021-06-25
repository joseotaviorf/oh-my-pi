DROP TABLE IF EXISTS front_tickets.dim_channel;
CREATE TABLE IF NOT EXISTS front_tickets.dim_channel (
    sk_channel VARCHAR(40),
    channel VARCHAR(5),
    direction VARCHAR(10),
    tags VARCHAR(2800),
    ts_load TIMESTAMP
);
ALTER TABLE front_tickets.dim_channel OWNER TO airflow;