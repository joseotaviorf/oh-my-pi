SELECT
	id,
	business_entity_id AS id_business_entity,
	cart_uuid AS uuid_cart,
	business_context,
	status,
	currency,
	source,
	metadata,
	created_at AS ts_created,
	updated_at AS ts_updated
FROM 
	datalake_cart_system_raw.cart
