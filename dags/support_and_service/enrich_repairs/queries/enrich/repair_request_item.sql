WITH repairs_tree AS (
  SELECT
    reg2.id AS id_category,
    reg.id AS id_group,
    re.id AS id_repair,
    reg2.repair_group_name AS repair_category_name,
    reg.repair_group_name,
    re.repair_name
  FROM
    datalake_repairs_clean.repair_expense_group AS reg
  LEFT JOIN
    datalake_repairs_clean.repair_expense_group AS reg2
      ON reg.id_parent = reg2.id
      AND reg2.id_parent IS NULL
  LEFT JOIN
    datalake_repairs_clean.repair_expense AS re
      ON reg.id = re.id_expense_group
  WHERE
    reg.id_parent IS NOT NULL
)
SELECT
  cri.id_repair_request AS id_request,
  cri.id_expense,
  rt.id_category,
  rt.id_group,
  rt.id_repair,
  rt.repair_category_name,
  rt.repair_group_name,
  rt.repair_name,
  cri.ts_created
FROM
  datalake_repairs_clean.repair_request_item AS cri
LEFT JOIN
  repairs_tree AS rt
    ON cri.id_expense = rt.id_repair