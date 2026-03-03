WITH
employee_ids AS (
  SELECT
    work_email,
    person_number,
    full_name
  FROM
    datalake_people_core.identifier_mapping
  WHERE
    person_number IS NOT NULL
    AND assignment_type IN ('E', 'C')
  QUALIFY
    ROW_NUMBER() OVER (
        PARTITION BY
          person_number
        ORDER BY
          assignment_number DESC
      ) = 1
),
new_emails_from_mapping AS (
  SELECT
    emp_map.work_email,
    emp_ids.person_number,
    emp_ids.full_name
  FROM
    datalake_gsheets_people_clean.email_employee_mapping AS emp_map
  INNER JOIN
    employee_ids AS emp_ids
      ON emp_map.person_number = emp_ids.person_number
  LEFT ANTI JOIN
    employee_ids AS existing_emails
      ON emp_map.work_email = existing_emails.work_email
),
employee_ids_enrich AS (
  SELECT
    work_email,
    person_number,
    full_name
  FROM
    employee_ids
  WHERE
    work_email IS NOT NULL

  UNION ALL

  SELECT
    work_email,
    person_number,
    full_name
  FROM
    new_emails_from_mapping
),
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
    emp_id1.person_number AS owner_l1_person_number,
    emp_id2.person_number AS owner_l2_person_number,
    emp_id3.person_number AS owner_l3_person_number,
    COALESCE(emp_id1.full_name, '-') AS owner_l1_full_name,
    COALESCE(emp_id2.full_name, '-') AS owner_l2_full_name,
    COALESCE(emp_id3.full_name, '-') AS owner_l3_full_name,
    codex.owner_l1_email,
    codex.owner_l2_email,
    codex.owner_l3_email,
    codex.headcount_type,
    (codex.dt_closing_month = MAX(codex.dt_closing_month) OVER (PARTITION BY codex.cost_center_code)) AS is_current,
    org.cost_center_code IS NOT NULL AS is_present_in_system,
    CASE
        WHEN (
            org.cost_center_code IS NULL
            OR NOT (codex.dt_closing_month = MAX(codex.dt_closing_month) OVER (PARTITION BY codex.cost_center_code))
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
        OR (COALESCE(emp_id1.full_name, '-') IS DISTINCT FROM org.owner_leadership_layer_1_name)
        OR (COALESCE(emp_id2.full_name, '-') IS DISTINCT FROM org.owner_leadership_layer_2_name)
        OR (COALESCE(emp_id3.full_name, '-') IS DISTINCT FROM org.owner_leadership_layer_3_name)
        OR (codex.headcount_type IS DISTINCT FROM org.headcount_type)
        )
    END AS is_outdated_in_system,
    codex.dt_closing_month,
    codex.ts_load
FROM
    datalake_gsheets_people.codex_history_base AS codex
LEFT JOIN
  employee_ids_enrich AS emp_id1
    ON codex.owner_l1_email = emp_id1.work_email
LEFT JOIN
  employee_ids_enrich AS emp_id2
    ON codex.owner_l2_email = emp_id2.work_email
LEFT JOIN
  employee_ids_enrich AS emp_id3
    ON codex.owner_l3_email = emp_id3.work_email
LEFT JOIN
  organizations AS org
    ON codex.cost_center_code = org.cost_center_code
