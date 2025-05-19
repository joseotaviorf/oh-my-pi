-- This DDL is not meant for Redshift, but for Spark itself.
-- This is because the query for this table is self-referential in order to create the Surrogate Keys.
-- Therefore, we need to have the empty table created manually before the query runs.
CREATE TABLE dw_public.dim_search_session_event_type (
    sk_event_type BIGINT,
    event_type STRING,
    business_context STRING,
    utm_source STRING,
    utm_medium STRING,
    platform STRING,
    base_referrer_url STRING,
    search_rendering_type STRING,
    search_location_type STRING,
    search_view_mode STRING,
    search_sort_order STRING,
    ts_load TIMESTAMP
) USING PARQUET LOCATION 's3://5a-dw-prod/public/dim_search_session_event_type'