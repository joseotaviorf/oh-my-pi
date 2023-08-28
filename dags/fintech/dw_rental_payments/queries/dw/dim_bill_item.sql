SELECT
  id_invoice AS sk_invoice,
  bill_item,
  bill_item_description,
  bill_item_cluster_name AS bill_item_group,
  value_sign_bill_item AS bill_item_due_amount,
  NOW() AS ts_load
FROM
  datalake_retsuko.bill_items
WHERE
  payment_status IN ('open', 'paid', 'canceled', 'written-down')
  AND due_amount <= 0
