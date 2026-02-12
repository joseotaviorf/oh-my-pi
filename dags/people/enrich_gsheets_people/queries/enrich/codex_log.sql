WITH
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
    owner_l1_full_name,
    owner_l2_full_name,
    owner_l3_full_name,
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
    LAG(owner_l1_full_name) OVER w AS prev_owner_l1_full_name,
    LAG(owner_l2_full_name) OVER w AS prev_owner_l2_full_name,
    LAG(owner_l3_full_name) OVER w AS prev_owner_l3_full_name,
    LAG(headcount_type) OVER w AS prev_headcount_type,
    LAG(cost_center_code) OVER w IS NULL AS is_first_version
  FROM
    datalake_gsheets_people.codex
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
    owner_l1_full_name,
    owner_l2_full_name,
    owner_l3_full_name,
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
        OR owner_l1_full_name IS DISTINCT FROM prev_owner_l1_full_name
        OR owner_l2_full_name IS DISTINCT FROM prev_owner_l2_full_name
        OR owner_l3_full_name IS DISTINCT FROM prev_owner_l3_full_name
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
    owner_l1_full_name,
    owner_l2_full_name,
    owner_l3_full_name,
    headcount_type,
    dt_closing_month AS dt_valid_from,
    ts_load,
    version_num
  FROM
    with_version
  QUALIFY
    ROW_NUMBER() OVER (
      PARTITION BY cost_center_code, version_num
      ORDER BY dt_closing_month
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
  owner_l1_full_name,
  owner_l2_full_name,
  owner_l3_full_name,
  headcount_type,
  dt_valid_from,
  DATE_SUB(
    LEAD(dt_valid_from) OVER (PARTITION BY cost_center_code ORDER BY version_num),
    1
  ) AS dt_valid_to,
  LEAD(dt_valid_from) OVER (PARTITION BY cost_center_code ORDER BY version_num) IS NULL AS is_current,
  NOW() AS ts_load
FROM
  one_per_version
