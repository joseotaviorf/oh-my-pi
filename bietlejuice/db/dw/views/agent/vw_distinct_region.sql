DROP VIEW staging.vw_distinct_region;

CREATE VIEW staging.vw_distinct_region AS (
SELECT
	dim_region.city_name,
    dim_region.region_code
FROM dim_region
WHERE dim_region.region_code <> ''
UNION
SELECT
	dim_region.city_name,
	dim_region.region_code_deprecated AS region_code
FROM dim_region
WHERE dim_region.region_code <> ''
);