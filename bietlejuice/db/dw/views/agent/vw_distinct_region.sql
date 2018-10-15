DROP VIEW staging.vw_distinct_region
CREATE VIEW staging.vw_distinct_region AS (
SELECT DISTINCT
    dim_region.city_name,
    dim_region.region_code,
    dim_region.new_region_code
FROM dim_region
WHERE dim_region.region_code <> ''
)
