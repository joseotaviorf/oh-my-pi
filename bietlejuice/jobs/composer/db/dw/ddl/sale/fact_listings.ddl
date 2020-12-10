DROP TABLE IF EXISTS sale.fact_listings;
CREATE TABLE sale.fact_listings (
	sk_sale_listing BIGINT PRIMARY KEY,
	sk_owner BIGINT,
	sk_region BIGINT,
	sk_first_publication_date BIGINT,
	sk_last_publication_date BIGINT,
	sk_first_depublication_date BIGINT,
	sk_last_depublication_date BIGINT,
	days_last_publication_to_depublication BIGINT,
	days_first_publication_to_first_depublication BIGINT,
	total_depublications BIGINT,
	days_as_published BIGINT,
	ts_load TIMESTAMP
);
ALTER TABLE sale.fact_listings OWNER TO airflow;