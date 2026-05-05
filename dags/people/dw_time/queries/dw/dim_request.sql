WITH requests_subtypes AS (
    SELECT
        XXHASH64(
            TRIM(CAST(id_request_subtype AS STRING))
        ) AS sk_request,
        id_request_subtype,
        subtype_name,
        subtype_name_key,
        translation_key,
        hours_calculation_type,
        is_active,
        is_paid_subtype,
        is_discount_dsr,
        ts_updated,
        ts_load
    FROM
        datalake_oitchau_clean.requests_types_subtypes
    WHERE
        MAKE_DATE(year, month, day) BETWEEN DATE('{load_start_date}')
            AND DATE('{load_end_date}')
    QUALIFY
        ROW_NUMBER() OVER (
            PARTITION BY
                id_request_subtype
            ORDER BY
                ts_load DESC NULLS LAST,
                year DESC,
                month DESC,
                day DESC
        ) = 1
),
request_subtypes_seen_in_requests AS (
    SELECT DISTINCT
        rq.id_request_subtype
    FROM
        datalake_oitchau_clean.requests AS rq
    WHERE
        MAKE_DATE(rq.year, rq.month, rq.day) BETWEEN DATE('{load_start_date}')
            AND DATE('{load_end_date}')
        AND rq.id_request_subtype IS NOT NULL
),
request_subtypes_missing_from_catalog AS (
    SELECT
        rx.id_request_subtype
    FROM
        request_subtypes_seen_in_requests AS rx
    WHERE
        NOT EXISTS (
            SELECT
                1
            FROM
                requests_subtypes AS rs
            WHERE
                rs.id_request_subtype = rx.id_request_subtype
        )
),
request_subtypes_synthetic AS (
    SELECT
        XXHASH64(
            TRIM(CAST(mx.id_request_subtype AS STRING))
        ) AS sk_request,
        mx.id_request_subtype,
        CAST(NULL AS STRING) AS subtype_name,
        CAST(NULL AS STRING) AS subtype_name_key,
        CAST(NULL AS STRING) AS translation_key,
        CAST(NULL AS STRING) AS hours_calculation_type,
        FALSE AS is_active,
        FALSE AS is_paid_subtype,
        FALSE AS is_discount_dsr,
        CAST(NULL AS TIMESTAMP) AS ts_updated,
        CURRENT_TIMESTAMP() AS ts_load
    FROM
        request_subtypes_missing_from_catalog AS mx
)
SELECT
    rs.sk_request,
    rs.id_request_subtype,
    rs.subtype_name,
    rs.subtype_name_key,
    rs.translation_key,
    rs.hours_calculation_type,
    rs.is_active,
    rs.is_paid_subtype,
    rs.is_discount_dsr,
    DATE(rs.ts_updated) AS dt_updated,
    rs.ts_updated,
    rs.ts_load
FROM
    requests_subtypes AS rs
UNION ALL
SELECT
    sx.sk_request,
    sx.id_request_subtype,
    sx.subtype_name,
    sx.subtype_name_key,
    sx.translation_key,
    sx.hours_calculation_type,
    sx.is_active,
    sx.is_paid_subtype,
    sx.is_discount_dsr,
    DATE(sx.ts_updated) AS dt_updated,
    sx.ts_updated,
    sx.ts_load
FROM
    request_subtypes_synthetic AS sx
