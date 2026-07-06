-- Reads from query_annotations (enrich layer) joined back to the raw source
-- to explode datahub_urns. The inner_dependency on query_annotations ensures
-- this runs after query_annotations is populated for the same window.
WITH annotations AS (
    SELECT
        id_query,
        id_session,
        user,
        business_domain,
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
raw_urns AS (
    SELECT
        query_id AS id_query,
        from_json(
            get_json_object(
                regexp_extract(query, '/\\* tars: (\\{{.*?\\}}) \\*/', 1),
                '$.datahub_urns'
            ),
            'ARRAY<STRING>'
        ) AS datahub_urns
    FROM
        data_platform_metrics.trino_query_complete
    WHERE
        MAKE_DATE(year, month, day) BETWEEN "{load_start_date}"
        AND "{load_end_date}"
        AND source = 'Tars'
),
joined AS (
    SELECT
        ann.id_query,
        ann.id_session,
        ann.user,
        ann.business_domain,
        ann.ts_started,
        ann.year,
        ann.month,
        ann.day,
        raw.datahub_urns
    FROM
        annotations AS ann
    INNER JOIN
        raw_urns AS raw
            ON ann.id_query = raw.id_query
),
exploded AS (
    SELECT
        joined.id_query,
        joined.id_session,
        joined.user,
        joined.business_domain,
        joined.ts_started,
        joined.year,
        joined.month,
        joined.day,
        urn
    FROM
        joined
    LATERAL VIEW OUTER EXPLODE(joined.datahub_urns) AS urn
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
