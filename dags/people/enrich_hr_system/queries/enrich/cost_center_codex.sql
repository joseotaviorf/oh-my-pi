WITH
cost_center_headcount_type AS (
  SELECT DISTINCT
    cost_center_code,
    cost_center_detail AS headcount_type
  FROM
    datalake_gsheets_people_clean.codex_cost_informations
  WHERE
    cost_center_detail IN ('Capacity', 'Overhead')
  QUALIFY
    ROW_NUMBER() OVER(PARTITION BY cost_center_code ORDER BY year DESC, month DESC) = 1
),
employee_ids AS (
  SELECT
    work_email,
    person_number,
    INITCAP(
      TRIM(REGEXP_REPLACE(REGEXP_REPLACE(full_name, '[^a-zA-ZÀ-ÿ ]', ''), ' +', ' '))
    ) AS full_name
  FROM
    datalake_employee_registration.identifier_mapping
  WHERE
    person_number IS NOT NULL
    AND assignment_type IN ('E', 'C')
  QUALIFY
    row_number() OVER (
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
codex_enrich AS (
  SELECT
    codex_cc.cost_center_code AS cost_center_code,
    codex_cc.cost_center_full_name,
    codex_cc.business,
    codex_cc.product,
    codex_cc.brand,
    CASE
      WHEN codex_cc.structure IN ('Sales','Operations','Marketing','Guarantees') THEN 'Ops'
      WHEN codex_cc.structure IN ('Finance','People','Legal','Administrative') THEN 'Corp'
      WHEN codex_cc.structure = 'Product' THEN 'Tech'
    END AS vertical,
    codex_cc.structure,
    codex_cc.team,
    codex_cc.chapter,
    codex_cc.line,
    codex_cc.owner_l1_email,
    codex_cc.owner_l2_email,
    codex_cc.owner_l3_email,
    codex_hctp.headcount_type
  FROM
    datalake_gsheets_people_clean.codex_cost_centers AS codex_cc
  LEFT JOIN
    cost_center_headcount_type AS codex_hctp
      ON codex_cc.cost_center_code = codex_hctp.cost_center_code
  QUALIFY
    ROW_NUMBER() OVER(
      PARTITION BY
        codex_cc.cost_center_code
      ORDER BY
        codex_cc.year DESC,
        codex_cc.month DESC,
        (
          + CAST((codex_cc.chapter IS NOT NULL) AS INT)
          + CAST((codex_cc.line IS NOT NULL) AS INT)
          + CAST((codex_cc.owner_l1_email IS NOT NULL) AS INT)
          + CAST((codex_cc.owner_l2_email IS NOT NULL) AS INT)
          + CAST((codex_cc.owner_l3_email IS NOT NULL) AS INT)
          + CAST((codex_hctp.headcount_type IS NOT NULL) AS INT)
        ) DESC
      ) = 1
    )

SELECT
  codex.cost_center_code,
  codex.cost_center_full_name,
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
  emp_id1.full_name AS owner_l1_full_name,
  emp_id2.full_name AS owner_l2_full_name,
  emp_id3.full_name AS owner_l3_full_name,
  codex.owner_l1_email,
  codex.owner_l2_email,
  codex.owner_l3_email,
  codex.headcount_type,
  CASE
    WHEN org.codigo_dff IS NULL THEN NULL
    ELSE (
      (codex.business IS DISTINCT FROM org.business)
      OR (codex.product IS DISTINCT FROM org.product)
      OR (codex.vertical IS DISTINCT FROM org.vertical)
      OR (codex.brand IS DISTINCT FROM org.brand)
      OR (codex.structure IS DISTINCT FROM org.structure)
      OR (codex.team IS DISTINCT FROM org.team)
      OR (codex.chapter IS DISTINCT FROM org.chapter)
      OR (codex.line IS DISTINCT FROM org.line)
      OR (emp_id1.full_name IS DISTINCT FROM org.owner_leadership_layer_1_name)
      OR (emp_id2.full_name IS DISTINCT FROM org.owner_leadership_layer_2_name)
      OR (emp_id3.full_name IS DISTINCT FROM org.owner_leadership_layer_3_name)
      OR (codex.headcount_type IS DISTINCT FROM org.headcount_type)
    )
  END AS is_outdated_in_system,
  NOW() AS ts_load
FROM
  codex_enrich AS codex
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
  datalake_hr_system_clean.organizations AS org
    ON codex.cost_center_code = org.codigo_dff