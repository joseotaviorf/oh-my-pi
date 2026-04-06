WITH
codex_current AS (
  SELECT
    cost_center_code,
    business AS codex_business,
    product AS codex_product,
    brand AS codex_brand,
    vertical AS codex_vertical,
    structure AS codex_structure,
    team AS codex_team,
    chapter AS codex_chapter,
    line AS codex_line,
    owner_l1_name AS codex_owner_l1_name,
    owner_l2_name AS codex_owner_l2_name,
    owner_l3_name AS codex_owner_l3_name,
    headcount_type AS codex_headcount_type
  FROM
    datalake_people.codex_log
  WHERE
    is_current = true
),
pin_current AS (
  SELECT
    a.cost_center_code,
    o.name AS pin_organization_name,
    o.status AS pin_organization_status,
    a.business AS pin_business,
    a.product AS pin_product,
    a.brand AS pin_brand,
    a.vertical AS pin_vertical,
    a.structure AS pin_structure,
    a.team AS pin_team,
    a.chapter AS pin_chapter,
    a.line AS pin_line,
    a.headcount_type AS pin_headcount_type,
    a.name_owner_l1 AS pin_name_owner_l1,
    a.name_owner_l2 AS pin_name_owner_l2,
    a.name_owner_l3 AS pin_name_owner_l3
  FROM
    datalake_pin_core_clean.all_organization_units AS a
  INNER JOIN
    datalake_pin_core_clean.hr_organization AS o
      ON o.id_organization = a.id_organization
      AND o.classification_code = 'DEPARTMENT'
  WHERE
    a.cost_center_code IS NOT NULL
    AND CURRENT_DATE >= a.dt_effective_started
    AND CURRENT_DATE <= a.dt_effective_ended
    AND CURRENT_DATE >= o.dt_effective_started
    AND CURRENT_DATE <= o.dt_effective_ended
  QUALIFY
    ROW_NUMBER() OVER (
      PARTITION BY
        TRIM(a.cost_center_code)
      ORDER BY
        a.ts_updated DESC NULLS LAST,
        o.ts_updated DESC NULLS LAST,
        o.id_organization
    ) = 1
)
SELECT
  c.cost_center_code AS cost_center_code,
  c.codex_business,
  p.pin_business,
  c.codex_product,
  p.pin_product,
  c.codex_brand,
  p.pin_brand,
  c.codex_vertical,
  p.pin_vertical,
  c.codex_structure,
  p.pin_structure,
  c.codex_team,
  p.pin_team,
  c.codex_chapter,
  p.pin_chapter,
  c.codex_line,
  p.pin_line,
  c.codex_headcount_type,
  p.pin_headcount_type,
  c.codex_owner_l1_name,
  p.pin_name_owner_l1,
  c.codex_owner_l2_name,
  p.pin_name_owner_l2,
  c.codex_owner_l3_name,
  p.pin_name_owner_l3,
  p.pin_organization_name,
  p.pin_organization_status,
  c.codex_business IS DISTINCT FROM p.pin_business AS is_drift_business,
  c.codex_product IS DISTINCT FROM p.pin_product AS is_drift_product,
  c.codex_brand IS DISTINCT FROM p.pin_brand AS is_drift_brand,
  c.codex_vertical IS DISTINCT FROM p.pin_vertical AS is_drift_vertical,
  c.codex_structure IS DISTINCT FROM p.pin_structure AS is_drift_structure,
  c.codex_team IS DISTINCT FROM p.pin_team AS is_drift_team,
  c.codex_chapter IS DISTINCT FROM p.pin_chapter AS is_drift_chapter,
  c.codex_line IS DISTINCT FROM p.pin_line AS is_drift_line,
  c.codex_headcount_type IS DISTINCT FROM p.pin_headcount_type AS is_drift_headcount_type,
  c.codex_owner_l1_name IS DISTINCT FROM p.pin_name_owner_l1 AS is_drift_owner_l1,
  c.codex_owner_l2_name IS DISTINCT FROM p.pin_name_owner_l2 AS is_drift_owner_l2,
  c.codex_owner_l3_name IS DISTINCT FROM p.pin_name_owner_l3 AS is_drift_owner_l3,
  (
    c.codex_business IS DISTINCT FROM p.pin_business
    OR c.codex_product IS DISTINCT FROM p.pin_product
    OR c.codex_brand IS DISTINCT FROM p.pin_brand
    OR c.codex_vertical IS DISTINCT FROM p.pin_vertical
    OR c.codex_structure IS DISTINCT FROM p.pin_structure
    OR c.codex_team IS DISTINCT FROM p.pin_team
    OR c.codex_chapter IS DISTINCT FROM p.pin_chapter
    OR c.codex_line IS DISTINCT FROM p.pin_line
    OR c.codex_headcount_type IS DISTINCT FROM p.pin_headcount_type
    OR c.codex_owner_l1_name IS DISTINCT FROM p.pin_name_owner_l1
    OR c.codex_owner_l2_name IS DISTINCT FROM p.pin_name_owner_l2
    OR c.codex_owner_l3_name IS DISTINCT FROM p.pin_name_owner_l3
  ) AS is_any_drift,
  NOW() AS ts_load
FROM
  codex_current AS c
INNER JOIN
  pin_current AS p
    ON TRIM(c.cost_center_code) = TRIM(p.cost_center_code)
