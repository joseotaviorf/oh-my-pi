DROP TABLE IF EXISTS tickets.dim_ticket;
CREATE TABLE IF NOT EXISTS tickets.dim_ticket (
	sk_ticket BIGINT PRIMARY KEY,
	subject VARCHAR(MAX),
	description VARCHAR(MAX),
	ticket_via VARCHAR(15),
	channel VARCHAR(15),
	group_name VARCHAR,
	priority VARCHAR(10),
	recipient VARCHAR,
	tags VARCHAR(MAX),
	status VARCHAR(20),
	custom_fields VARCHAR(MAX),
	score VARCHAR(20),
	reason VARCHAR,
	comment VARCHAR(MAX),
	request_type VARCHAR,
	client_type VARCHAR(30),
	customer_type_tag VARCHAR(50),
	contact_motivation_tag VARCHAR(50),
	contact_theme_tag VARCHAR(100),
	has_public_comments BOOLEAN,
	ts_created TIMESTAMP,
	ts_created_local TIMESTAMP,
	ts_updated TIMESTAMP,
	ts_updated_local TIMESTAMP,
	ts_load TIMESTAMP
);
ALTER TABLE tickets.dim_ticket OWNER TO airflow;
