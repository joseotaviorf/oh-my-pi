SELECT
	id,
	status,
	amount,
	user_type,
	source_client,
	reference_year_month,
	city_state,
	city,
	person_card_code,
	person_document,
	person_document_type,
	sequence_code,
	description,
	cost_center,
	business_place,
	account_code,
	account_cfop_code,
	account_managerial_center,
	TIMESTAMP(created_at) AS ts_created,
	TIMESTAMP(updated_at) AS ts_updated
FROM
    datalake_sap_gateway_raw.consolidated_invoice
