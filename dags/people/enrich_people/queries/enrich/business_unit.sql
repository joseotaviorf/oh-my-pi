WITH base AS (
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
        AND dt_effective_started <= CURRENT_DATE
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
    id_organization,
    id_legal_entity,
    organization_code,
    business_unit_name,
    legislation_code,
    organization_type,
    created_by,
    updated_by,
    version_order,
    is_active,
    CASE
        WHEN dt_valid_from <= CURRENT_DATE
            AND version_order = MAX(
                CASE
                    WHEN dt_valid_from <= CURRENT_DATE THEN version_order
                END
            ) OVER (
                PARTITION BY id_organization
            )
        THEN TRUE
        ELSE FALSE
    END AS is_current,
    dt_valid_from,
    dt_valid_to,
    ts_created,
    ts_updated,
    ts_load
FROM
    consolidated_with_recency
