WITH  mob_array AS (
  SELECT
    EXPLODE(ARRAY(0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12)) AS col_mob
),
invoice_status_sign AS (
  SELECT
    *,
    IF(col_mob>=mob_paid_by_created_date,1,0) AS signal_paid_mob,
    IF(col_mob>=mob_canceled_by_created_date,1,0) AS signal_canceled_mob,
    IF(col_mob>=mob_due_by_created_date,1,0) AS signal_due_mob,
    IF(col_mob<mob_due_by_created_date,1,0) AS signal_to_due_mob,
    'CREATED DATE' AS reference_date_mob
  FROM dw_retsuko.fact_bill_item_cluster_at_invoice_mobs as ic
  CROSS JOIN mob_array AS mac
  WHERE mac.col_mob <= ic.mobs_possible_invoice_by_created_date
  UNION ALL
  SELECT
    *,
    IF(col_mob>=mob_paid_by_due_date,1,0) AS signal_paid_mob,
    IF(col_mob>=mob_canceled_by_due_date,1,0) AS signal_canceled_mob,
    IF(col_mob>=mob_due_by_due_date,1,0) AS signal_due_mob,
    IF(col_mob<mob_due_by_due_date,1,0) AS signal_to_due_mob,
    'DUE DATE' AS reference_date_mob
  FROM dw_retsuko.fact_bill_item_cluster_at_invoice_mobs as ic
  CROSS JOIN mob_array AS mad
  WHERE mad.col_mob <= ic.mobs_possible_invoice_by_due_date
),
building_status_invoices AS (
  SELECT
    *,
    CASE
      WHEN ss.signal_canceled_mob = 1 THEN 'CANCELADA'
      WHEN ss.signal_paid_mob = 1 THEN 'PAGA'
      WHEN ss.signal_to_due_mob = 1 THEN 'A VENCER'
      ELSE 'VENCIDA'
    END AS status_temporal
  FROM invoice_status_sign AS ss
),
building_status_invoices_values AS (
  SELECT
    *,
    IF(bsi.status_temporal='CANCELADA',value_bill_item_cluster,0) AS value_canceled,
    IF(bsi.status_temporal='PAGA',value_bill_item_cluster,0) AS value_paid,
    IF(bsi.status_temporal='VENCIDA',value_bill_item_cluster,0) AS value_due,
    IF(bsi.status_temporal='A VENCER',value_bill_item_cluster,0) AS value_to_due
  FROM building_status_invoices AS bsi
)
SELECT
  sk_invoice,
  sk_contract,
  sk_junk_bill_items_cluster,
  reference_date_mob,
  status_temporal,
  col_mob,
  mobs_possible_invoice_by_created_date,
  mobs_possible_invoice_by_due_date,
  mob_paid_by_created_date,
  mob_canceled_by_created_date,
  mob_paid_by_due_date,
  mob_canceled_by_due_date,
  mob_due_by_created_date,
  mob_due_by_due_date,
  signal_paid_mob,
  signal_canceled_mob,
  signal_due_mob,
  signal_to_due_mob,
  value_bill_item_cluster,
  value_canceled,
  value_paid,
  value_due,
  value_to_due,
  DATE(ts_safra_per_dt_due) AS dt_safra_per_dt_due,
  DATE(ts_safra_per_dt_created) AS dt_safra_per_dt_created
FROM building_status_invoices_values
