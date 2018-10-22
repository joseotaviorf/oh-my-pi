WITH reg AS (
SELECT
	COALESCE(to_char(r.dt::DATE,'YYYYMMDD')::INTEGER, -1) AS sk_date,
	dadosagente_id AS sk_dadosagente_id,
	regioes,
	area,
	secondary_area,
	new_area,
	new_secondary_area
FROM staging.agent_region_group r
)
SELECT
	CONCAT(sk_date, sk_dadosagente_id)::BIGINT AS sk_agentregiongroup_id,
	*,
	getdate() as dt_timestamp
FROM reg