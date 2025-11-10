SELECT
    codex.id,
    codex.cost_center_code,
    org.name AS cost_center_name,
    org.status AS cost_center_status,
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
    CASE
        WHEN (
            org.codigo_dff IS NULL
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
INNER JOIN
  datalake_hr_system_clean.organizations AS org
    ON codex.cost_center_code = org.codigo_dff
    AND org.classification_code = 'DEPARTMENT'