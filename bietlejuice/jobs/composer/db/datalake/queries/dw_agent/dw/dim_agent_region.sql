WITH region AS (
SELECT
	COALESCE(CAST(REPLACE(CAST(DATE(r.dt) AS string), '-', '') AS integer), -1) AS sk_regions_date,
	dadosagente_id AS sk_agent,
	regions AS regioes,
	area,
	secondary_area,
	area_deprecated,
	secondary_area_deprecated
FROM datalake_ebdb_agents.agent_region_group r
)
SELECT
	CONCAT(sk_regions_date, sk_agent)::BIGINT AS sk_agent_region,
	*,
	CURRENT_TIMESTAMP AS dt_timestamp
FROM region