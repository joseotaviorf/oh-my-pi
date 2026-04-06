WITH
employee_ids AS (
  SELECT
    work_email,
    person_number,
    name
  FROM
    datalake_people.identifier_mapping
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
    emp_ids.name
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
    name
  FROM
    employee_ids
  WHERE
    work_email IS NOT NULL

  UNION ALL

  SELECT
    work_email,
    person_number,
    name
  FROM
    new_emails_from_mapping
),
codex AS (
  SELECT
    codex.cost_center_code,
    codex.business,
    codex.product,
    codex.brand,
    codex.vertical,
    codex.structure,
    codex.team,
    codex.chapter,
    codex.line,
    emp_id1.name AS owner_l1_name,
    emp_id2.name AS owner_l2_name,
    emp_id3.name AS owner_l3_name,
    codex.headcount_type,
    codex.dt_closing_month,
    codex.ts_load
  FROM
    datalake_people.codex_history_base AS codex
  LEFT JOIN
    employee_ids_enrich AS emp_id1
      ON codex.owner_l1_email = emp_id1.work_email
  LEFT JOIN
    employee_ids_enrich AS emp_id2
      ON codex.owner_l2_email = emp_id2.work_email
  LEFT JOIN
    employee_ids_enrich AS emp_id3
      ON codex.owner_l3_email = emp_id3.work_email
),
codex_ordered AS (
  SELECT
    cost_center_code,
    business,
    product,
    brand,
    vertical,
    structure,
    team,
    chapter,
    line,
    owner_l1_name,
    owner_l2_name,
    owner_l3_name,
    headcount_type,
    dt_closing_month,
    ts_load,
    LAG(business) OVER w AS prev_business,
    LAG(product) OVER w AS prev_product,
    LAG(brand) OVER w AS prev_brand,
    LAG(vertical) OVER w AS prev_vertical,
    LAG(structure) OVER w AS prev_structure,
    LAG(team) OVER w AS prev_team,
    LAG(chapter) OVER w AS prev_chapter,
    LAG(line) OVER w AS prev_line,
    LAG(owner_l1_name) OVER w AS prev_owner_l1_name,
    LAG(owner_l2_name) OVER w AS prev_owner_l2_name,
    LAG(owner_l3_name) OVER w AS prev_owner_l3_name,
    LAG(headcount_type) OVER w AS prev_headcount_type,
    LAG(cost_center_code) OVER w IS NULL AS is_first_version
  FROM
    codex
  WINDOW
    w AS (PARTITION BY cost_center_code ORDER BY dt_closing_month)
),
with_version AS (
  SELECT
    cost_center_code,
    business,
    product,
    brand,
    vertical,
    structure,
    team,
    chapter,
    line,
    owner_l1_name,
    owner_l2_name,
    owner_l3_name,
    headcount_type,
    dt_closing_month,
    ts_load,
    SUM(
      CASE
        WHEN is_first_version
        OR business IS DISTINCT FROM prev_business
        OR product IS DISTINCT FROM prev_product
        OR brand IS DISTINCT FROM prev_brand
        OR vertical IS DISTINCT FROM prev_vertical
        OR structure IS DISTINCT FROM prev_structure
        OR team IS DISTINCT FROM prev_team
        OR chapter IS DISTINCT FROM prev_chapter
        OR line IS DISTINCT FROM prev_line
        OR owner_l1_name IS DISTINCT FROM prev_owner_l1_name
        OR owner_l2_name IS DISTINCT FROM prev_owner_l2_name
        OR owner_l3_name IS DISTINCT FROM prev_owner_l3_name
        OR headcount_type IS DISTINCT FROM prev_headcount_type
        THEN 1
        ELSE 0
      END
    ) OVER (PARTITION BY cost_center_code ORDER BY dt_closing_month) AS version_num
  FROM
    codex_ordered
),
one_per_version AS (
  SELECT
    cost_center_code,
    business,
    product,
    brand,
    vertical,
    structure,
    team,
    chapter,
    line,
    owner_l1_name,
    owner_l2_name,
    owner_l3_name,
    headcount_type,
    dt_closing_month AS dt_valid_from,
    ts_load,
    version_num
  FROM
    with_version
  QUALIFY
    ROW_NUMBER() OVER (
      PARTITION BY
        cost_center_code,
        version_num
      ORDER BY
        dt_closing_month
    ) = 1
)
SELECT
  cost_center_code,
  business,
  product,
  brand,
  vertical,
  structure,
  team,
  chapter,
  line,
  owner_l1_name,
  owner_l2_name,
  owner_l3_name,
  headcount_type,
  CAST(dt_valid_from AS DATE) AS dt_valid_from,
  CAST(
    DATE_SUB(
      LEAD(dt_valid_from) OVER (PARTITION BY cost_center_code ORDER BY version_num),
      1
    ) AS DATE
  ) AS dt_valid_to,
  LEAD(dt_valid_from) OVER (PARTITION BY cost_center_code ORDER BY version_num) IS NULL AS is_current,
  NOW() AS ts_load
FROM
  one_per_version
