-- Explodes datahub_urns already materialized on query_annotations (Vector-sourced).
WITH annotations AS (
    SELECT
        id_query,
        id_session,
        user,
        business_domain_normalized,
        datahub_urns,
        ts_started,
        year,
        month,
        day
    FROM
        datalake_tars.query_annotations
    WHERE
        MAKE_DATE(year, month, day) BETWEEN "{load_start_date}"
        AND "{load_end_date}"
        AND has_tars_comment = TRUE
        AND urn_count > 0
),
exploded AS (
    SELECT
        annotations.id_query,
        annotations.id_session,
        annotations.user,
        annotations.business_domain_normalized AS business_domain,
        annotations.ts_started,
        annotations.year,
        annotations.month,
        annotations.day,
        urn
    FROM
        annotations
    LATERAL VIEW OUTER EXPLODE(annotations.datahub_urns) AS urn
    WHERE
        urn IS NOT NULL
        AND LENGTH(urn) > 0
)
SELECT
    id_query,
    id_session,
    user,
    business_domain,
    urn AS datahub_urn,
    CASE
        WHEN urn LIKE '%dataProduct%' THEN 'dataProduct'
        WHEN urn LIKE '%dataset%' THEN 'dataset'
        ELSE 'other'
    END AS asset_type,
    CASE
        WHEN urn LIKE '%dataProduct%' THEN
            regexp_extract(urn, ':dataProduct:(.+)$', 1)
        WHEN urn LIKE '%dataset%' THEN
            regexp_extract(urn, ':dataset:\\((.+)\\)', 1)
        ELSE urn
    END AS asset_slug,
    1 AS urn_hit_count,
    ts_started,
    year,
    month,
    day
FROM
    exploded
