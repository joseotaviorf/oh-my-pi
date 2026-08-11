WITH bu_legislation_counts AS (
    SELECT
        a.id_business_unit,
        le.legislation_code,
        COUNT(*) AS assignment_count
    FROM
        datalake_pin_core_clean.all_assignments AS a
    INNER JOIN
        datalake_pin_core_clean.hr_organization AS le
            ON le.id_organization = a.id_legal_entity
            AND le.classification_code = 'HCM_LEMP'
            AND le.dt_effective_ended = DATE('9999-12-31')
    WHERE
        a.is_primary = TRUE
        AND a.is_active = TRUE
        AND a.dt_effective_started <= DATE('{load_start_date}')
        AND a.dt_effective_ended >= DATE('{load_start_date}')
    GROUP BY
        a.id_business_unit,
        le.legislation_code
),
bu_legislation_ranked AS (
    SELECT
        id_business_unit,
        legislation_code,
        ROW_NUMBER() OVER (
            PARTITION BY id_business_unit
            ORDER BY assignment_count DESC, legislation_code ASC
        ) AS rn
    FROM
        bu_legislation_counts
),
bu_legislation AS (
    SELECT
        id_business_unit,
        legislation_code
    FROM
        bu_legislation_ranked
    WHERE
        rn = 1
),
base AS (
    SELECT
        id_organization,
        id_legal_entity,
        organization_code,
        name AS business_unit_name,
        legislation_code,
        organization_type,
        created_by,
        updated_by,
        is_active,
        dt_effective_started AS dt_valid_from,
        dt_effective_ended AS dt_valid_to,
        ts_created,
        ts_updated
    FROM
        datalake_pin_core_clean.hr_organization
    WHERE
        classification_code = 'FUN_BUSINESS_UNIT'
        AND dt_effective_started <= DATE('{load_start_date}')
),
with_prev_dt_valid_to AS (
    SELECT
        id_organization,
        id_legal_entity,
        organization_code,
        business_unit_name,
        legislation_code,
        organization_type,
        created_by,
        updated_by,
        is_active,
        dt_valid_from,
        dt_valid_to,
        ts_created,
        ts_updated,
        LAG(dt_valid_to) OVER (
            PARTITION BY
                id_organization,
                id_legal_entity,
                organization_code,
                business_unit_name,
                legislation_code,
                organization_type,
                created_by,
                updated_by,
                is_active
            ORDER BY
                dt_valid_from
        ) AS prev_dt_valid_to
    FROM
        base
),
contiguous_validity_periods AS (
    SELECT
        id_organization,
        id_legal_entity,
        organization_code,
        business_unit_name,
        legislation_code,
        organization_type,
        created_by,
        updated_by,
        is_active,
        dt_valid_from,
        dt_valid_to,
        ts_created,
        ts_updated,
        SUM(
            CASE
                WHEN prev_dt_valid_to IS NULL
                    OR dt_valid_from > prev_dt_valid_to + 1
                THEN 1
                ELSE 0
            END
        ) OVER (
            PARTITION BY
                id_organization,
                id_legal_entity,
                organization_code,
                business_unit_name,
                legislation_code,
                organization_type,
                created_by,
                updated_by,
                is_active
            ORDER BY
                dt_valid_from
        ) AS validity_period_group_id
    FROM
        with_prev_dt_valid_to
),
consolidated AS (
    SELECT
        id_organization,
        id_legal_entity,
        organization_code,
        business_unit_name,
        legislation_code,
        organization_type,
        created_by,
        updated_by,
        is_active,
        MIN(dt_valid_from) AS dt_valid_from,
        MAX(dt_valid_to) AS dt_valid_to,
        MIN(ts_created) AS ts_created,
        MAX(ts_updated) AS ts_updated,
        NOW() AS ts_load
    FROM
        contiguous_validity_periods
    GROUP BY
        id_organization,
        id_legal_entity,
        organization_code,
        business_unit_name,
        legislation_code,
        organization_type,
        created_by,
        updated_by,
        is_active,
        validity_period_group_id
),
consolidated_with_recency AS (
    SELECT
        id_organization,
        id_legal_entity,
        organization_code,
        business_unit_name,
        legislation_code,
        organization_type,
        created_by,
        updated_by,
        is_active,
        dt_valid_from,
        dt_valid_to,
        ts_created,
        ts_updated,
        ts_load,
        ROW_NUMBER() OVER (
            PARTITION BY id_organization
            ORDER BY
                dt_valid_from ASC,
                dt_valid_to ASC
        ) AS version_order
    FROM
        consolidated
)
SELECT
    cwr.id_organization,
    cwr.id_legal_entity,
    cwr.organization_code,
    cwr.business_unit_name,
    /* Temporary workaround: PIN has country names in legislative_data_group, but we have
    not modeled that lookup yet. Map legislation_code to English country names in a CASE.
    The first two branches override business units whose legal employer is registered
    under a legislation other than the country where the employees actually work. */
    CASE
        WHEN cwr.business_unit_name = 'Deel - QuintoAndar' THEN 'United States'
        WHEN cwr.business_unit_name = 'Benvi MX' THEN 'Mexico'
        WHEN COALESCE(cwr.legislation_code, bl.legislation_code) = 'PE' THEN 'Peru'
        WHEN COALESCE(cwr.legislation_code, bl.legislation_code) = 'EC' THEN 'Ecuador'
        WHEN COALESCE(cwr.legislation_code, bl.legislation_code) = 'PA' THEN 'Panama'
        WHEN COALESCE(cwr.legislation_code, bl.legislation_code) = 'MX' THEN 'Mexico'
        WHEN COALESCE(cwr.legislation_code, bl.legislation_code) = 'AR' THEN 'Argentina'
        WHEN COALESCE(cwr.legislation_code, bl.legislation_code) = 'UY' THEN 'Uruguay'
        WHEN COALESCE(cwr.legislation_code, bl.legislation_code) = 'PT' THEN 'Portugal'
        WHEN COALESCE(cwr.legislation_code, bl.legislation_code) = 'BR' THEN 'Brazil'
        WHEN COALESCE(cwr.legislation_code, bl.legislation_code) = 'US' THEN 'United States'
        ELSE NULL
    END AS country,
    COALESCE(cwr.legislation_code, bl.legislation_code) AS legislation_code,
    cwr.organization_type,
    cwr.created_by,
    cwr.updated_by,
    cwr.version_order,
    cwr.is_active,
    CASE
        WHEN cwr.dt_valid_from <= DATE('{load_start_date}')
            AND cwr.version_order = MAX(
                CASE
                    WHEN cwr.dt_valid_from <= DATE('{load_start_date}') THEN cwr.version_order
                END
            ) OVER (
                PARTITION BY cwr.id_organization
            )
        THEN TRUE
        ELSE FALSE
    END AS is_current,
    cwr.dt_valid_from,
    cwr.dt_valid_to,
    cwr.ts_created,
    cwr.ts_updated,
    cwr.ts_load
FROM
    consolidated_with_recency AS cwr
LEFT JOIN
    bu_legislation AS bl
        ON bl.id_business_unit = cwr.id_organization
