DROP TABLE IF EXISTS sale.dim_sale_agreeement;
CREATE TABLE sale.dim_sale_agreeement (
	sk_offer VARCHAR PRIMARY KEY,
	sale_agreement_status VARCHAR,
	sale_agreement_cancellation_reason VARCHAR,
	sale_price_agreed BIGINT,
	brokerage_fee DECIMAL(5,4),
	fgts_value BIGINT,
	financing_bank VARCHAR,
	financing_value BIGINT,
	earnest_value BIGINT,
	ts_sale_agreement_signed TIMESTAMP,
	ts_sale_agreement_cancelled TIMESTAMP,
	ts_house_registry_ended TIMESTAMP,
	ts_sale_transacton_paid TIMESTAMP,
	ts_load TIMESTAMP
);