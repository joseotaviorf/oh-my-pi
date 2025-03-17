SELECT 
	id,
	flow_id AS id_flow,
	author_external_id AS id_external_author,
	rent_flow_id AS id_rent_flow,
	event_domain_id AS id_event_domain,
	actor_role,
	type,
	debug_additional_info,
	source,
	created_at AS ts_created,
	updated_at AS ts_updated
FROM 
	datalake_rental_transact_raw.event_log