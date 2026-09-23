-- Google Drive findings deep-dive aggregate contract for the Base44 dashboard's Deep
-- dive tab, ported from production-deep-dive-queries.sql (Trino) to this repo's Spark
-- SQL dialect.
-- Forbidden columns (never select as a raw value): id_resource, resource_name,
-- source_raw_payload. top_external_users (shared_with[].email) and top_owners
-- (actor_email) are the one approved exception -- Privacy signed off on emitting
-- these two panels as raw addresses (CORESEC-73): they are internal/partner
-- Workspace accounts, not customer PII. Every other panel stays count-only.
-- source_metadata is a JSON-encoded STRING column, parsed here with
-- get_json_object (scalars) and from_json(get_json_object(...), 'ARRAY<STRUCT<...>>')
-- (the shared_with[] array) -- see dags/growth/dw_alias and
-- dags/conversational_xp/enrich_concierge_audience for the same pattern already in
-- this repo.
--
-- Real-data caveats (see production-deep-dive-queries.sql for the Trino exploration
-- this was validated against -- do not silently "fix" these back without re-verifying):
--   - sharing_state has exactly one distinct value in this table today, so
--     riskiest_combinations and exposure_matrix are keyed on an EXTERNAL_GRANTEE /
--     INTERNAL_ONLY flag derived from shared_with[].email domain instead.
--   - actor_email is 0% populated today (shared-drive-only scan scope); top_owners is
--     production-ready and will populate once file-owner identity is captured.
-- Array ordering, mix pivoting, and top-N label formatting are applied downstream in
-- load_deep_dive_to_s3.py, not here -- Spark collect_list does not guarantee order.
-- Cluster session timezone is pinned to UTC (see cluster.yml).
WITH base AS (
    SELECT
        risk_level,
        pii_types_detected,
        actor_email,
        ts_classified,
        get_json_object(source_metadata, '$.mime_type') AS mime_type,
        get_json_object(source_metadata, '$.parent_drive_name') AS parent_drive_name,
        get_json_object(source_metadata, '$.ou_path') AS ou_path,
        from_json(
            get_json_object(source_metadata, '$.shared_with'),
            'ARRAY<STRUCT<email:STRING,role:STRING>>'
        ) AS shared_with,
        MAX(ts_classified) OVER () AS as_of_ts
    FROM
        datalake_security_data_gateway_clean.security_findings
),
base_ext AS (
    SELECT
        *,
        size(pii_types_detected) > 0 AS has_pii,
        -- COALESCE matters: Spark's EXISTS(NULL, ...) returns NULL, not FALSE, and
        -- shared_with is NULL whenever source_metadata has no shared_with key (or
        -- fails to parse) -- a real, expected case, not just a hypothetical. Without
        -- this, has_external is NULL for those rows, which crashes the Python job's
        -- has_external -> sharing-state dict lookup downstream. Default to FALSE
        -- (no grantees = INTERNAL_ONLY), matching production-deep-dive-queries.sql's
        -- Trino reference (LEFT JOIN + COALESCE, see caveat 1 there).
        COALESCE(
            EXISTS(
                shared_with,
                g -> g.email IS NOT NULL AND g.email != ''
                    AND NOT g.email RLIKE '(?i)@(quintoandar\.com\.br|quintoandar\.com|ext\.quintoandar\.com\.br)$'
                    AND NOT g.email RLIKE '(?i)\.iam\.gserviceaccount\.com$'
            ),
            FALSE
        ) AS has_external
    FROM
        base
),
kpis AS (
    SELECT
        COUNT(DISTINCT NULLIF(ou_path, '')) AS org_units_with_findings,
        COUNT(DISTINCT NULLIF(parent_drive_name, '')) AS shared_drives_affected,
        COUNT(*) AS total_findings,
        SUM(CASE WHEN has_pii THEN 1 ELSE 0 END) AS pii_findings_total,
        SUM(CASE WHEN has_external THEN 1 ELSE 0 END) AS exposed_beyond_domain,
        MAX(as_of_ts) AS as_of_ts
    FROM
        base_ext
),
external_users_kpi AS (
    SELECT
        COUNT(DISTINCT lower(g.email)) AS external_users_with_pii_access
    FROM
        base_ext b
    LATERAL VIEW explode(b.shared_with) exploded_grantee AS g
    WHERE
        b.has_pii
        AND g.email IS NOT NULL AND g.email != ''
        AND NOT g.email RLIKE '(?i)@(quintoandar\.com\.br|quintoandar\.com|ext\.quintoandar\.com\.br)$'
        AND NOT g.email RLIKE '(?i)\.iam\.gserviceaccount\.com$'
),
by_mime_type_breakdown AS (
    SELECT
        mime_type AS label,
        risk_level,
        COUNT(*) AS cnt
    FROM
        base_ext
    WHERE
        mime_type IS NOT NULL AND mime_type != ''
    GROUP BY
        mime_type, risk_level
),
shared_drive_totals AS (
    SELECT
        parent_drive_name AS label,
        COUNT(*) AS cnt
    FROM
        base_ext
    WHERE
        parent_drive_name IS NOT NULL AND parent_drive_name != ''
    GROUP BY
        parent_drive_name
    ORDER BY
        cnt DESC
    LIMIT 10
),
top_shared_drives_breakdown AS (
    SELECT
        parent_drive_name AS label,
        risk_level,
        COUNT(*) AS cnt
    FROM
        base_ext
    WHERE
        parent_drive_name IN (SELECT label FROM shared_drive_totals)
    GROUP BY
        parent_drive_name, risk_level
),
external_user_totals AS (
    SELECT
        lower(g.email) AS email,
        COUNT(*) AS cnt
    FROM
        base_ext b
    LATERAL VIEW explode(b.shared_with) exploded_grantee AS g
    WHERE
        b.has_pii
        AND g.email IS NOT NULL AND g.email != ''
        AND NOT g.email RLIKE '(?i)@(quintoandar\.com\.br|quintoandar\.com|ext\.quintoandar\.com\.br)$'
        AND NOT g.email RLIKE '(?i)\.iam\.gserviceaccount\.com$'
    GROUP BY
        lower(g.email)
    ORDER BY
        cnt DESC
    LIMIT 10
),
top_external_users_breakdown AS (
    -- Raw email, not hashed -- Privacy-approved exception (CORESEC-73): these are
    -- internal/partner Workspace accounts, not customer PII.
    SELECT
        lower(g.email) AS label,
        b.risk_level,
        COUNT(*) AS cnt
    FROM
        base_ext b
    LATERAL VIEW explode(b.shared_with) exploded_grantee AS g
    WHERE
        b.has_pii
        AND g.email IS NOT NULL AND g.email != ''
        AND NOT g.email RLIKE '(?i)@(quintoandar\.com\.br|quintoandar\.com|ext\.quintoandar\.com\.br)$'
        AND NOT g.email RLIKE '(?i)\.iam\.gserviceaccount\.com$'
        AND lower(g.email) IN (SELECT email FROM external_user_totals)
    GROUP BY
        lower(g.email), b.risk_level
),
owner_totals AS (
    -- Forward-looking panel: actor_email is 0% populated today (shared-drive-only
    -- scan scope); this returns zero rows now and that is expected, not a bug.
    SELECT
        lower(actor_email) AS email,
        COUNT(*) AS cnt
    FROM
        base_ext
    WHERE
        has_pii AND actor_email IS NOT NULL AND actor_email != ''
    GROUP BY
        lower(actor_email)
    ORDER BY
        cnt DESC
    LIMIT 10
),
top_owners_breakdown AS (
    -- Raw email, not hashed -- Privacy-approved exception (CORESEC-73): file
    -- owners are internal Workspace accounts, not customer PII.
    SELECT
        lower(actor_email) AS label,
        risk_level,
        COUNT(*) AS cnt
    FROM
        base_ext
    WHERE
        has_pii AND actor_email IS NOT NULL AND actor_email != ''
        AND lower(actor_email) IN (SELECT email FROM owner_totals)
    GROUP BY
        lower(actor_email), risk_level
),
by_org_unit_breakdown AS (
    SELECT
        COALESCE(NULLIF(ou_path, ''), '(empty)') AS label,
        risk_level,
        COUNT(*) AS cnt
    FROM
        base_ext
    GROUP BY
        COALESCE(NULLIF(ou_path, ''), '(empty)'), risk_level
),
riskiest_combinations_raw AS (
    SELECT
        pii.pii_type AS pii_type,
        has_external,
        COUNT(*) AS cnt
    FROM
        base_ext
    LATERAL VIEW explode(pii_types_detected) exploded_pii AS pii
    WHERE
        pii.pii_type IS NOT NULL
    GROUP BY
        pii.pii_type, has_external
),
exposure_matrix_raw AS (
    SELECT
        has_external,
        risk_level,
        COUNT(*) AS cnt
    FROM
        base_ext
    GROUP BY
        has_external, risk_level
)
SELECT
    '1' AS schema_version,
    date_format(k.as_of_ts, "yyyy-MM-dd'T'HH:mm:ss'Z'") AS as_of,
    k.org_units_with_findings,
    k.shared_drives_affected,
    eu.external_users_with_pii_access,
    k.exposed_beyond_domain,
    k.pii_findings_total,
    k.total_findings,
    -- named_struct fields inherit non-null from their source columns; Delta forbids a
    -- NOT NULL constraint nested inside an array, so cast to an explicitly nullable
    -- struct type before collect_list (see DELTA_NESTED_NOT_NULL_CONSTRAINT).
    (SELECT collect_list(CAST(named_struct('label', label, 'risk_level', risk_level, 'count', cnt) AS STRUCT<label: STRING, risk_level: STRING, count: BIGINT>)) FROM by_mime_type_breakdown) AS by_mime_type,
    (SELECT collect_list(CAST(named_struct('label', label, 'risk_level', risk_level, 'count', cnt) AS STRUCT<label: STRING, risk_level: STRING, count: BIGINT>)) FROM top_shared_drives_breakdown) AS top_shared_drives,
    (SELECT collect_list(CAST(named_struct('label', label, 'risk_level', risk_level, 'count', cnt) AS STRUCT<label: STRING, risk_level: STRING, count: BIGINT>)) FROM top_external_users_breakdown) AS top_external_users,
    (SELECT collect_list(CAST(named_struct('label', label, 'risk_level', risk_level, 'count', cnt) AS STRUCT<label: STRING, risk_level: STRING, count: BIGINT>)) FROM top_owners_breakdown) AS top_owners,
    (SELECT collect_list(CAST(named_struct('label', label, 'risk_level', risk_level, 'count', cnt) AS STRUCT<label: STRING, risk_level: STRING, count: BIGINT>)) FROM by_org_unit_breakdown) AS by_org_unit,
    (SELECT collect_list(CAST(named_struct('pii_type', pii_type, 'has_external', has_external, 'count', cnt) AS STRUCT<pii_type: STRING, has_external: BOOLEAN, count: BIGINT>)) FROM riskiest_combinations_raw) AS riskiest_combinations,
    (SELECT collect_list(CAST(named_struct('has_external', has_external, 'risk_level', risk_level, 'count', cnt) AS STRUCT<has_external: BOOLEAN, risk_level: STRING, count: BIGINT>)) FROM exposure_matrix_raw) AS exposure_matrix
FROM
    kpis k
CROSS JOIN
    external_users_kpi eu
