WITH dirty_invoices AS (
  SELECT DISTINCT id_invoice
  FROM (
    SELECT
      id_external AS id_invoice
    FROM datalake_retsuko.invoice
    WHERE
      ts_retsuko_updated >= TIMESTAMP('{load_start_date}')
      AND ts_retsuko_updated < TIMESTAMP('{load_end_date}')
    UNION
    SELECT
      i.id_external AS id_invoice
    FROM datalake_retsuko.entry AS e
    INNER JOIN datalake_retsuko.invoice AS i
      ON e.id_invoice = i.id
    WHERE
      e.ts_retsuko_updated >= TIMESTAMP('{load_start_date}')
      AND e.ts_retsuko_updated < TIMESTAMP('{load_end_date}')
  )
),
get_invoices_with_balance AS (
  SELECT
    bi.id_invoice,
    bi.bill_item_cluster_name,
    SUM(bi.value_sign_bill_item) AS bill_item_balance
  FROM datalake_retsuko.bill_items AS bi
  INNER JOIN dirty_invoices AS d
    ON bi.id_invoice = d.id_invoice
  WHERE
    bi.due_amount <= 0
    AND bi.payment_status IN ('open', 'paid', 'canceled', 'written-down')
  GROUP BY 1, 2
  HAVING bill_item_balance > 0
),
add_bill_items_flags AS (
  SELECT
    id_invoice,
    MAX(IF(bill_item_cluster_name = 'CONDOMINIO', TRUE, FALSE)) AS has_bill_item_condominio,
    MAX(IF(bill_item_cluster_name = 'MULTA-RECISORIA', TRUE, FALSE)) AS has_bill_item_multa_recisoria,
    MAX(IF(bill_item_cluster_name = 'ACORDO', TRUE, FALSE)) AS has_bill_item_acordo,
    MAX(IF(bill_item_cluster_name = 'RENTAL-CORE', TRUE, FALSE)) AS has_bill_item_rental_core,
    MAX(IF(bill_item_cluster_name = 'REPAROS', TRUE, FALSE)) AS has_bill_item_reparos,
    MAX(IF(bill_item_cluster_name = 'MULTAS ONGOING', TRUE, FALSE)) AS has_bill_item_multas_ongoing,
    MAX(IF(bill_item_cluster_name = 'UTILIDADES', TRUE, FALSE)) AS has_bill_item_utilidades,
    MAX(IF(bill_item_cluster_name = 'OUTROS', TRUE, FALSE)) AS has_bill_item_outros,
    SUM(IF(bill_item_cluster_name = 'CONDOMINIO', bill_item_balance, 0)) AS balance_bill_item_condominio,
    SUM(IF(bill_item_cluster_name = 'MULTA-RECISORIA', bill_item_balance, 0)) AS balance_bill_item_multa_recisoria,
    SUM(IF(bill_item_cluster_name = 'ACORDO', bill_item_balance, 0)) AS balance_bill_item_acordo,
    SUM(IF(bill_item_cluster_name = 'RENTAL-CORE', bill_item_balance, 0)) AS balance_bill_item_rental_core,
    SUM(IF(bill_item_cluster_name = 'REPAROS', bill_item_balance, 0)) AS balance_bill_item_reparos,
    SUM(IF(bill_item_cluster_name = 'MULTAS ONGOING', bill_item_balance, 0)) AS balance_bill_item_multas_ongoing,
    SUM(IF(bill_item_cluster_name = 'UTILIDADES', bill_item_balance, 0)) AS balance_bill_item_utilidades,
    SUM(IF(bill_item_cluster_name = 'OUTROS', bill_item_balance, 0)) AS balance_bill_item_outros
  FROM get_invoices_with_balance
  GROUP BY 1
),
invoices_without_positive_balance AS (
  SELECT
    d.id_invoice
  FROM dirty_invoices AS d
  LEFT JOIN add_bill_items_flags AS f
    ON d.id_invoice = f.id_invoice
  WHERE f.id_invoice IS NULL
)
SELECT
  id_invoice,
  has_bill_item_condominio,
  has_bill_item_multa_recisoria,
  has_bill_item_acordo,
  has_bill_item_rental_core,
  has_bill_item_reparos,
  has_bill_item_multas_ongoing,
  has_bill_item_utilidades,
  has_bill_item_outros,
  balance_bill_item_condominio,
  balance_bill_item_multa_recisoria,
  balance_bill_item_acordo,
  balance_bill_item_rental_core,
  balance_bill_item_reparos,
  balance_bill_item_multas_ongoing,
  balance_bill_item_utilidades,
  balance_bill_item_outros,
  NOW() AS ts_load
FROM add_bill_items_flags
UNION ALL
SELECT
  id_invoice,
  FALSE AS has_bill_item_condominio,
  FALSE AS has_bill_item_multa_recisoria,
  FALSE AS has_bill_item_acordo,
  FALSE AS has_bill_item_rental_core,
  FALSE AS has_bill_item_reparos,
  FALSE AS has_bill_item_multas_ongoing,
  FALSE AS has_bill_item_utilidades,
  FALSE AS has_bill_item_outros,
  0 AS balance_bill_item_condominio,
  0 AS balance_bill_item_multa_recisoria,
  0 AS balance_bill_item_acordo,
  0 AS balance_bill_item_rental_core,
  0 AS balance_bill_item_reparos,
  0 AS balance_bill_item_multas_ongoing,
  0 AS balance_bill_item_utilidades,
  0 AS balance_bill_item_outros,
  NOW() AS ts_load
FROM invoices_without_positive_balance
