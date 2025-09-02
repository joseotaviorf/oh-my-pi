SELECT
	id AS id_automatic_invoice,
	inspection_uuid AS uuid_inspection,
	contract_id AS id_contract,
	payment_method,
	tag,
	tenant_cost,
	owner_cost,
	installments,
	created_at AS ts_created,
	updated_at AS ts_updated
FROM
	datalake_inspection_services_raw.automatic_invoice
