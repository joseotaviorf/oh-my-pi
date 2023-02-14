DROP TABLE IF EXISTS sale.dim_sale_offer_user_info;
CREATE TABLE sale.dim_sale_offer_user_info (
	sk_user_info VARCHAR PRIMARY KEY,
	user_type VARCHAR,
	ccv_buyer_status VARCHAR,
	seller_ccv_signer_status VARCHAR,
	buyer_ccv_signer_status VARCHAR,
	user_legal_type VARCHAR,
	original_user_status VARCHAR,
	income_partner_status VARCHAR,
	joint_buyer_status VARCHAR
);
ALTER TABLE sale.dim_sale_offer_user_info OWNER TO airflow;
