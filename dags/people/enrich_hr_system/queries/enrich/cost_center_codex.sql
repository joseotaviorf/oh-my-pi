WITH cost_center_headcount_type AS (
  SELECT DISTINCT
    id_cost_center_current AS id_cost_center,
    cost_center_detail AS headcount_type
  FROM
    datalake_gsheets_people_clean.codex_cost_informations
  WHERE
    cost_center_detail IN ('Capacity', 'Overhead')
  
  UNION ALL

  SELECT DISTINCT
    id_cost_center_legacy AS id_cost_center,
    cost_center_detail AS headcount_type
  FROM
    datalake_gsheets_people_clean.codex_cost_informations
  WHERE
    cost_center_detail IN ('Capacity', 'Overhead')
)
SELECT
  ccc.id_cost_center_current AS id_cost_center,
  ccc.cost_center_name,
  ccc.cost_center_full_name,
  ccc.business,
  ccc.product,
  ccc.brand,
  CASE
    WHEN ccc.structure IN ('Sales','Operations','Marketing','Guarantees') THEN 'Ops'
    WHEN ccc.structure IN ('Finance','People','Legal','Administrative') THEN 'Corp'
    WHEN ccc.structure = 'Product' THEN 'Tech'
  END AS vertical,
  ccc.structure,
  ccc.team,
  ccc.chapter,
  ccc.line,
  ccc.owner_l1_email,
  ccc.owner_l2_email,
  ccc.owner_l3_email,
  ccc.owner_finance_email,
  ccht.headcount_type,
  ccc.team_code,
  ccc.sort_number,
  CASE
    WHEN ccc.cost_center_status = 'Active' THEN TRUE
    WHEN ccc.cost_center_status = 'End' THEN FALSE
  END AS is_active,
  FALSE AS is_legacy_code
FROM
  datalake_gsheets_people_clean.codex_cost_centers AS ccc
LEFT JOIN
  cost_center_headcount_type AS ccht
    ON ccc.id_cost_center_current = ccht.id_cost_center

UNION ALL

SELECT
  ccc.id_cost_center_legacy AS id_cost_center,
  ccc.cost_center_name,
  ccc.cost_center_full_name,
  ccc.business,
  ccc.product,
  ccc.brand,
  CASE
    WHEN ccc.structure IN ('Sales','Operations','Marketing','Guarantees') THEN 'Ops'
    WHEN ccc.structure IN ('Finance','People','Legal','Administrative') THEN 'Corp'
    WHEN ccc.structure = 'Product' THEN 'Tech'
  END AS vertical,
  ccc.structure,
  ccc.team,
  ccc.chapter,
  ccc.line,
  ccc.owner_l1_email,
  ccc.owner_l2_email,
  ccc.owner_l3_email,
  ccc.owner_finance_email,
  ccht.headcount_type,
  ccc.team_code,
  ccc.sort_number,
  CASE
    WHEN ccc.cost_center_status = 'Active' THEN TRUE
    WHEN ccc.cost_center_status = 'End' THEN FALSE
  END AS is_active,
  TRUE AS is_legacy_code
FROM
  datalake_gsheets_people_clean.codex_cost_centers AS ccc
LEFT JOIN
  cost_center_headcount_type AS ccht
    ON ccc.id_cost_center_current = ccht.id_cost_center
QUALIFY
  ROW_NUMBER() OVER(
    PARTITION BY
      id_cost_center
    ORDER BY
      (
        CAST((ccc.cost_center_status = 'Active') AS INT) * 100
        + CAST((ccc.chapter IS NOT NULL) AS INT)
        + CAST((ccc.line IS NOT NULL) AS INT)
        + CAST((ccc.owner_l1_email IS NOT NULL) AS INT)
        + CAST((ccc.owner_l2_email IS NOT NULL) AS INT)
        + CAST((ccc.owner_l2_email IS NOT NULL) AS INT)
        + CAST((ccht.headcount_type IS NOT NULL) AS INT)
      ) DESC,
      ccc.sort_number
    ) = 1