DROP TABLE IF EXISTS sale.dim_listing;
CREATE TABLE sale.dim_listing (
	sk_sale_listing BIGINT PRIMARY KEY,
	sk_house BIGINT,
	price BIGINT,
	predicted_price BIGINT,
	status VARCHAR,
	closing_status VARCHAR,
	registration_abandoned_reason VARCHAR,
	unpublished_reason VARCHAR,
	short_url VARCHAR,
	is_for_rent BOOLEAN,
	has_active_rental_contract BOOLEAN,
	has_house_been_rented BOOLEAN,
	ts_created TIMESTAMP,
	ts_first_publication TIMESTAMP,
	ts_last_publication TIMESTAMP,
	ts_first_depublication TIMESTAMP,
	ts_last_depublication TIMESTAMP,
	ts_updated TIMESTAMP,
	ts_load TIMESTAMP
);
ALTER TABLE sale.dim_listing OWNER TO airflow;
