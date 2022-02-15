WITH region AS (
SELECT
	COALESCE(CAST(REPLACE(CAST(DATE(r.dt) AS string), '-', '') AS integer), -1) AS sk_regions_date,
	dadosagente_id AS sk_agent,
	regions,
	area,
	secondary_area,
	area_deprecated,
	secondary_area_deprecated
FROM datalake_ebdb_agents.agent_region_group r
)
SELECT
	CAST(CONCAT(sk_regions_date, sk_agent) AS BIGINT) AS sk_agent_region,
	CAST(sk_regions_date AS INTEGER) AS sk_regions_date,
	CAST(sk_agent AS INTEGER) AS sk_agent,
	CAST(regions AS VARCHAR(3076)) AS regions,
	CAST(area AS VARCHAR(10)) AS area,
	CAST(secondary_area AS VARCHAR(10)) AS secondary_area,
	CAST(area_deprecated AS VARCHAR(10)) AS area_deprecated,
	CAST(secondary_area_deprecated AS VARCHAR(10)) AS secondary_area_deprecated,
	CURRENT_TIMESTAMP AS dt_timestamp
FROM region