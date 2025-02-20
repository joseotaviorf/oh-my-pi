SELECT
  id,
  expense_group_id AS id_expense_group,
  name AS repair_name,
  description AS repair_description,
  instant_approval,
  responsible_after_grace,
  responsible_before_grace,
  created_at AS ts_created,
  updated_at AS ts_updated
FROM
  datalake_repairs_test_raw.repair_expense