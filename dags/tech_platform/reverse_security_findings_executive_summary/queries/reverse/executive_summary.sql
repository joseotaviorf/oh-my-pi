-- Allowlisted aggregate contract from IDPLATF-8282: KPI counts and breakdowns only.
-- Forbidden columns (never select): emails, id_resource, resource_name, shared_with,
-- actor_email, source_raw_payload.
-- Array ordering (risk-level rank, count desc, day asc) is applied downstream in
-- load_executive_summary_to_s3.py, not here — Spark collect_list does not guarantee order.
-- as_of is MAX(ts_classified), not wall-clock now — classified_last_30d and the day
-- spine are both relative to it, matching the IDPLATF-8282 reference Trino query.
-- Cluster session timezone is pinned to UTC (see cluster.yml) so CAST(... AS DATE)
-- truncates the same way the reference query's `AT TIME ZONE 'UTC'` does.
WITH base AS (
    SELECT
        source,
        resource_type,
        risk_level,
        ts_classified,
        pii_types_detected,
        MAX(ts_classified) OVER () AS as_of_ts
    FROM
        datalake_security_data_gateway_clean.security_findings
),
kpis AS (
    SELECT
        COUNT(*) AS total,
        SUM(CASE WHEN risk_level = 'CRITICAL' THEN 1 ELSE 0 END) AS critical,
        SUM(CASE WHEN risk_level IN ('HIGH', 'CRITICAL') THEN 1 ELSE 0 END) AS high_plus_critical,
        SUM(
            CASE
                WHEN CAST(ts_classified AS DATE) >= date_sub(CAST(as_of_ts AS DATE), 29)
                    THEN 1
                ELSE 0
            END
        ) AS classified_last_30d,
        MAX(as_of_ts) AS as_of_ts
    FROM
        base
),
by_risk_level_counts AS (
    SELECT
        risk_level,
        COUNT(*) AS cnt
    FROM
        base
    GROUP BY
        risk_level
),
by_pii_type_counts AS (
    SELECT
        pii.pii_type AS pii_type,
        COUNT(*) AS cnt
    FROM
        base
    LATERAL VIEW explode(pii_types_detected) exploded_pii AS pii
    WHERE
        pii.pii_type IS NOT NULL
    GROUP BY
        pii.pii_type
),
by_resource_type_counts AS (
    SELECT
        resource_type,
        COUNT(*) AS cnt
    FROM
        base
    GROUP BY
        resource_type
),
by_source_counts AS (
    SELECT
        source,
        COUNT(*) AS cnt
    FROM
        base
    GROUP BY
        source
),
calendar AS (
    SELECT
        explode(sequence(date_sub(CAST(k.as_of_ts AS DATE), 29), CAST(k.as_of_ts AS DATE), INTERVAL 1 DAY)) AS dt
    FROM
        kpis AS k
),
classified_by_day_counts AS (
    SELECT
        c.dt AS dt,
        COALESCE(d.day_cnt, 0) AS cnt
    FROM
        calendar AS c
    LEFT JOIN (
        SELECT
            CAST(ts_classified AS DATE) AS dt_classified,
            COUNT(*) AS day_cnt
        FROM
            base
        GROUP BY
            CAST(ts_classified AS DATE)
    ) AS d
        ON c.dt = d.dt_classified
)
SELECT
    '1' AS schema_version,
    date_format(k.as_of_ts, "yyyy-MM-dd'T'HH:mm:ss'Z'") AS as_of,
    'one table row; lake contract is (source, id_resource)' AS grain,
    k.total,
    k.critical,
    k.high_plus_critical,
    k.classified_last_30d,
    -- named_struct fields inherit non-null from their source columns; Delta forbids a
    -- NOT NULL constraint nested inside an array, so cast to an explicitly nullable
    -- struct type before collect_list (see DELTA_NESTED_NOT_NULL_CONSTRAINT).
    (SELECT collect_list(CAST(named_struct('risk_level', risk_level, 'count', cnt) AS STRUCT<risk_level: STRING, count: BIGINT>)) FROM by_risk_level_counts) AS by_risk_level,
    (SELECT collect_list(CAST(named_struct('pii_type', pii_type, 'count', cnt) AS STRUCT<pii_type: STRING, count: BIGINT>)) FROM by_pii_type_counts) AS by_pii_type,
    (SELECT collect_list(CAST(named_struct('resource_type', resource_type, 'count', cnt) AS STRUCT<resource_type: STRING, count: BIGINT>)) FROM by_resource_type_counts) AS by_resource_type,
    (SELECT collect_list(CAST(named_struct('source', source, 'count', cnt) AS STRUCT<source: STRING, count: BIGINT>)) FROM by_source_counts) AS by_source,
    (SELECT collect_list(CAST(named_struct('dt', dt, 'count', cnt) AS STRUCT<dt: DATE, count: BIGINT>)) FROM classified_by_day_counts) AS classified_by_day
FROM
    kpis AS k
