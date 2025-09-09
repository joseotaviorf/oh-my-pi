SELECT
	id,
	cart_id AS id_cart,
	from_actor_id AS id_actor_from,
	to_actor_id AS id_actor_to,
	cart_item_uuid AS uuid_cart_item,
	description,
	from_actor_role AS actor_from_role,
	to_actor_role AS actor_to_role,
	metadata,
	source,
    slug,
	financial_category,
	amount,
	due_date AS dt_due,
	accrual_year_month AS dt_accrual_year_month,
	created_at AS ts_created,
	updated_at AS ts_updated
FROM 
	datalake_cart_system_raw.cart_item
