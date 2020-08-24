WITH termination_aud AS (
	SELECT
		id,
		id_contract,
		rev,
		rev_end,
		status,
		dt_termination,
		ts_updated
	FROM datalake_terminator_clean_prod.termination_aud
), 
terminations_finished AS (
	SELECT
		id,
		min(ts_updated) AS ts_termination_finished
	FROM termination_aud ta
	WHERE ta.status = 'DONE'
	GROUP BY 1
), 
terminations_modified AS (
	SELECT
		ta1.id
	FROM termination_aud ta1
	INNER JOIN termination_aud ta2
		ON ta2.rev = ta1.rev_end
		AND ta2.id = ta1.id
	WHERE ta1.rev_end IS NOT NULL
		AND ta1.dt_termination != ta2.dt_termination
), 
inspections AS (
	SELECT
		id,
		id_contract,
		keys_location,
		keys_location_comment
	FROM datalake_terminator_clean_prod.inspection i
),
last_inspection AS (
	SELECT
		id_contract,
		max(id) AS id
	FROM inspections i
	WHERE i.keys_location IS NOT NULL
	GROUP BY 1
),
keys AS (
	SELECT
		i.id_contract,
		i.id,
		keys_location,
		keys_location_comment
	FROM inspections i
	INNER JOIN last_inspection ii
		ON ii.id = i.id
		AND ii.id_contract = i.id_contract
)
SELECT
	t.id AS sk_termination,
	t.id_contract AS sk_contract,
	COALESCE(k.id,-1) AS sk_inspection,
	t.reason,
	t.requested_by,
	t.status,
	t.source,
	k.keys_location AS key_location,
	k.keys_location_comment AS key_location_detail,
	n.has_landlord_comment AS has_repairs,
	n.needs_repair_by_tenant AS is_repair_tenant_duty,
	n.repair_resolution,
	n.repair_cost,
	(m.id IS NOT NULL) AS has_termination_date_modification,
	(t.ts_canceled IS NOT null) AS is_termination_canceled,
	t.dt_termination,
	t.ts_created,
	t.ts_canceled,
	CASE WHEN d.ts_termination_finished <= '2020-07-07' THEN n.ts_updated
		WHEN d.ts_termination_finished > '2020-07-07' THEN d.ts_termination_finished
		END AS ts_termination_finished,
	t.ts_updated,
	current_timestamp as ts_load
FROM datalake_terminator_clean_prod.termination t
LEFT JOIN terminations_finished d
	ON d.id = t.id
	AND t.status = 'DONE'
LEFT JOIN datalake_terminator_clean_prod.negotiation n
	ON t.id=n.id_termination
LEFT JOIN keys k
	ON k.id_contract = t.id_contract
LEFT JOIN terminations_modified m
	ON m.id = t.id
