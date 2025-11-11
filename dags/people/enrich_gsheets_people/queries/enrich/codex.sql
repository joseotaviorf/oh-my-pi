WITH
organizations AS (
    SELECT
        codigo_dff AS cost_center_code,
        name AS cost_center_name,
        status AS cost_center_status,
        business,
        product,
        vertical,
        brand,
        structure,
        team,
        chapter,
        line,
        owner_leadership_layer_1_name,
        owner_leadership_layer_2_name,
        owner_leadership_layer_3_name,
        headcount_type
    FROM
        datalake_hr_system_clean.organizations AS org
    WHERE
        classification_code = 'DEPARTMENT'
    QUALIFY
        ROW_NUMBER() OVER (
            PARTITION BY
                codigo_dff
            ORDER BY
                status,
                dt_effective_end DESC,
                dt_effective_start DESC,
                ts_last_update DESC
            ) = 1
)
SELECT
    codex.id,
    codex.cost_center_code,
    org.cost_center_name,
    org.cost_center_status,
    codex.business,
    codex.product,
    codex.brand,
    codex.vertical,
    codex.structure,
    codex.team,
    codex.chapter,
    codex.line,
    codex.owner_l1_person_number,
    codex.owner_l2_person_number,
    codex.owner_l3_person_number,
    codex.owner_l1_full_name,
    codex.owner_l2_full_name,
    codex.owner_l3_full_name,
    codex.owner_l1_email,
    codex.owner_l2_email,
    codex.owner_l3_email,
    codex.headcount_type,
    (codex.dt_closing_month = MAX(codex.dt_closing_month) OVER (PARTITION BY codex.cost_center_code)) AS is_latest_version,
    org.cost_center_code IS NOT NULL AS is_present_in_system,
    CASE
        WHEN (
            org.cost_center_code IS NULL
            OR NOT is_latest_version
        ) THEN NULL
        ELSE (
        (codex.business IS DISTINCT FROM org.business)
        OR (codex.product IS DISTINCT FROM org.product)
        OR (codex.vertical IS DISTINCT FROM org.vertical)
        OR (codex.brand IS DISTINCT FROM org.brand)
        OR (codex.structure IS DISTINCT FROM org.structure)
        OR (codex.team IS DISTINCT FROM org.team)
        OR (codex.chapter IS DISTINCT FROM org.chapter)
        OR (codex.line IS DISTINCT FROM org.line)
        OR (codex.owner_l1_full_name IS DISTINCT FROM org.owner_leadership_layer_1_name)
        OR (codex.owner_l2_full_name IS DISTINCT FROM org.owner_leadership_layer_2_name)
        OR (codex.owner_l3_full_name IS DISTINCT FROM org.owner_leadership_layer_3_name)
        OR (codex.headcount_type IS DISTINCT FROM org.headcount_type)
        )
    END AS is_outdated_in_system,
    codex.dt_closing_month,
    codex.ts_load
FROM
    datalake_gsheets_people.codex_history_base AS codex
LEFT JOIN
  organizations AS org
    ON codex.cost_center_code = org.cost_center_code