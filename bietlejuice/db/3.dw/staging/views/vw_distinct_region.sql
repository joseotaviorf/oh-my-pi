drop view staging.vw_distinct_region
create view staging.vw_distinct_region as (
SELECT DISTINCT
    dim_region.city_name,
    dim_region.region_code
FROM dim_region
WHERE ((dim_region.region_code)::text <> ''::text)
)
