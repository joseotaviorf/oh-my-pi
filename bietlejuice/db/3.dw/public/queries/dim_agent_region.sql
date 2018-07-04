WITH reg AS (
SELECT
	COALESCE(to_char(r.dt::DATE,'YYYYMMDD')::INTEGER, -1) AS sk_date,
	dadosagente_id AS sk_dadosagente_id,
	regioes,
	area,
	secondary_area
FROM staging.agent_region_group r
)
SELECT
	cast(sk_date AS CHAR(8)) +
	cast(sk_dadosagente_id AS CHAR(8)) AS sk_agentregiongroup_id,
	*
FROM reg