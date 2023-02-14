DROP TABLE IF EXISTS sale.fact_sale_offer_users;
CREATE TABLE sale.fact_sale_offer_users (
	sk_sale_offer_user VARCHAR PRIMARY KEY,
	sk_offer VARCHAR,
	sk_user_external BIGINT,
	sk_user_sales_flow BIGINT,
	sk_user_info BIGINT,
	sk_inviter BIGINT,
	sk_house BIGINT,
	sk_house_docx_folder BIGINT,
	sk_user_docx_folder BIGINT,
	sk_date_user_invited BIGINT,
	sk_date_user_invite_accepted BIGINT,
	ts_user_invited TIMESTAMP,
	ts_user_invite_accepted TIMESTAMP
);
ALTER TABLE sale.fact_sale_offer_users OWNER TO airflow;
