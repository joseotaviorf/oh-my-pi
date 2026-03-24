WITH
cost_center_headcount_type AS (
  SELECT DISTINCT
    cost_center_code,
    cost_center_detail AS headcount_type,
    dt_updated
  FROM
    datalake_gsheets_people_clean.codex_cost_informations
  WHERE
    cost_center_detail IN ('Capacity', 'Overhead')
)
SELECT
  MD5(
    CONCAT(
      codex.cost_center_code,
      DATE_FORMAT(codex.dt_updated, 'yyyyMM')
    )
  ) AS id,
  codex.cost_center_code,
  codex.business,
  codex.product,
  codex.brand,
  CASE
    WHEN codex.structure IN ('Sales', 'Operations', 'Marketing', 'Guarantees') THEN 'Ops'
    WHEN codex.structure IN ('Finance', 'People', 'Legal', 'Administrative') THEN 'Corp'
    WHEN codex.structure = 'Product' THEN 'Tech'
  END AS vertical,
  codex.structure,
  codex.team,
  codex.chapter,
  codex.line,
  codex.owner_l1_email,
  codex.owner_l2_email,
  codex.owner_l3_email,
  cc_hctype.headcount_type,
  codex.dt_updated AS dt_closing_month,
  codex.ts_load
FROM
  datalake_gsheets_people_clean.codex_cost_centers AS codex
LEFT JOIN
  cost_center_headcount_type AS cc_hctype
    ON codex.cost_center_code = cc_hctype.cost_center_code
    AND codex.dt_updated = cc_hctype.dt_updated
WHERE
  codex.cost_center_code IS NOT NULL
QUALIFY
  ROW_NUMBER() OVER(
    PARTITION BY
      codex.cost_center_code,
      DATE_FORMAT(codex.dt_updated, 'yyyyMM')
    ORDER BY
      codex.ts_load DESC,
      (
        + CAST((codex.chapter IS NOT NULL) AS INT)
        + CAST((codex.line IS NOT NULL) AS INT)
        + CAST((codex.owner_l1_email IS NOT NULL) AS INT)
        + CAST((codex.owner_l2_email IS NOT NULL) AS INT)
        + CAST((codex.owner_l3_email IS NOT NULL) AS INT)
        + CAST((cc_hctype.headcount_type IS NOT NULL) AS INT)
      ) DESC
    ) = 1
