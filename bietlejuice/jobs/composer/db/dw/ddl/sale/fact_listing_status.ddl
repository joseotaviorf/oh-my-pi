DROP TABLE IF EXISTS sale.fact_listing_status;
CREATE TABLE sale.fact_listing_status (
	sk_sale_listing BIGINT PRIMARY KEY,
	sk_region BIGINT,
	sk_first_publication_date BIGINT,
	sk_status_start_date BIGINT,
	sk_status_end_date BIGINT,
	ts_status_started TIMESTAMP,
	ts_status_ended TIMESTAMP,
	status_history VARCHAR,
	status_change_reason VARCHAR(2000),
	is_last_status BOOLEAN,
	ts_load TIMESTAMP
);
ALTER TABLE sale.fact_listing_status OWNER TO airflow;