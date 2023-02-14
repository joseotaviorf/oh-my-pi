DROP TABLE IF EXISTS sale.dim_sale_offer_user;
CREATE TABLE sale.dim_sale_offer_user (
	sk_user_sales_flow BIGINT PRIMARY KEY,
	sk_user_external BIGINT,
	name VARCHAR,
	gender VARCHAR,
	email VARCHAR,
	alternative_email VARCHAR,
	phone_number VARCHAR,
	address VARCHAR,
	postal_code VARCHAR,
	city VARCHAR,
	state VARCHAR,
	houses_owned BIGINT,
	quintoandar_houses_owned BIGINT,
	owns_a_property VARCHAR,
	active_contract_status VARCHAR,
	user_status VARCHAR,
	block_status VARCHAR
);
ALTER TABLE sale.dim_sale_offer_user OWNER TO airflow;
