WITH
get_invoices_with_balance AS (
  SELECT
    id_invoice,
    bill_item_cluster_name,
    SUM(value_sign_bill_item) AS bill_item_balance
  FROM datalake_retsuko.bill_items
  WHERE
    due_amount <= 0
    AND payment_status IN ('open', 'paid', 'canceled', 'written-down')
  GROUP BY 1,2
  HAVING bill_item_balance > 0
),
add_bill_items_flags AS (
    SELECT
        id_invoice,
        MAX(CASE WHEN bill_item_cluster_name = 'CONDOMINIO'       THEN 1 ELSE 0 END) AS has_bill_item_condominio,
        MAX(CASE WHEN bill_item_cluster_name = 'MULTA-RECISORIA'  THEN 1 ELSE 0 END) AS has_bill_item_multa_recisoria,
        MAX(CASE WHEN bill_item_cluster_name = 'ACORDO'           THEN 1 ELSE 0 END) AS has_bill_item_acordo,
        MAX(CASE WHEN bill_item_cluster_name = 'RENTAL-CORE'      THEN 1 ELSE 0 END) AS has_bill_item_rental_core,
        MAX(CASE WHEN bill_item_cluster_name = 'REPAROS'          THEN 1 ELSE 0 END) AS has_bill_item_reparos,
        MAX(CASE WHEN bill_item_cluster_name = 'MULTAS ONGOING'   THEN 1 ELSE 0 END) AS has_bill_item_multas_ongoing,
        MAX(CASE WHEN bill_item_cluster_name = 'UTILIDADES'       THEN 1 ELSE 0 END) AS has_bill_item_utilidades,
        MAX(CASE WHEN bill_item_cluster_name = 'OUTROS'           THEN 1 ELSE 0 END) AS has_bill_item_outros,
        SUM(CASE WHEN bill_item_cluster_name = 'CONDOMINIO'       THEN bill_item_balance ELSE 0 END) AS balance_bill_item_condominio,
        SUM(CASE WHEN bill_item_cluster_name = 'MULTA-RECISORIA'  THEN bill_item_balance ELSE 0 END) AS balance_bill_item_multa_recisoria,
        SUM(CASE WHEN bill_item_cluster_name = 'ACORDO'           THEN bill_item_balance ELSE 0 END) AS balance_bill_item_acordo,
        SUM(CASE WHEN bill_item_cluster_name = 'RENTAL-CORE'      THEN bill_item_balance ELSE 0 END) AS balance_bill_item_rental_core,
        SUM(CASE WHEN bill_item_cluster_name = 'REPAROS'          THEN bill_item_balance ELSE 0 END) AS balance_bill_item_reparos,
        SUM(CASE WHEN bill_item_cluster_name = 'MULTAS ONGOING'   THEN bill_item_balance ELSE 0 END) AS balance_bill_item_multas_ongoing,
        SUM(CASE WHEN bill_item_cluster_name = 'UTILIDADES'       THEN bill_item_balance ELSE 0 END) AS balance_bill_item_utilidades,
        SUM(CASE WHEN bill_item_cluster_name = 'OUTROS'           THEN bill_item_balance ELSE 0 END) AS balance_bill_item_outros
    FROM get_invoices_with_balance
    GROUP BY 1
),
base AS (
    SELECT
        i.id_invoice,
        i.id_contract,
        i.dt_contract_annulled,
        i.id_negotiation_parent,
        i.id_negotiation_child,
        i.is_child_negotiation,
        i.has_child,
        i.is_negative_eligible,
        i.net_rate_recovery,
        i.negotiation_installment_number,
        i.negotiation_promisse_payment_method,
        i.invoice_status,
        i.purpose,
        i.recovery_channel,
        i.due_amount,
        COALESCE(d.has_bill_item_condominio, 0) as has_bill_item_condominio,
        COALESCE(d.has_bill_item_multa_recisoria, 0) as has_bill_item_multa_recisoria,
        COALESCE(d.has_bill_item_acordo, 0) as has_bill_item_acordo,
        COALESCE(d.has_bill_item_rental_core, 0) as has_bill_item_rental_core,
        COALESCE(d.has_bill_item_reparos, 0) as has_bill_item_reparos,
        COALESCE(d.has_bill_item_multas_ongoing, 0) as has_bill_item_multas_ongoing,
        COALESCE(d.has_bill_item_utilidades, 0) as has_bill_item_utilidades,
        COALESCE(d.has_bill_item_outros, 0) as has_bill_item_outros,
        COALESCE(d.balance_bill_item_condominio, 0) as balance_bill_item_condominio,
        COALESCE(d.balance_bill_item_multa_recisoria, 0) as balance_bill_item_multa_recisoria,
        COALESCE(d.balance_bill_item_acordo, 0) as balance_bill_item_acordo,
        COALESCE(d.balance_bill_item_rental_core, 0) as balance_bill_item_rental_core,
        COALESCE(d.balance_bill_item_reparos, 0) as balance_bill_item_reparos,
        COALESCE(d.balance_bill_item_multas_ongoing, 0) as balance_bill_item_multas_ongoing,
        COALESCE(d.balance_bill_item_utilidades, 0) as balance_bill_item_utilidades,
        COALESCE(d.balance_bill_item_outros, 0) as balance_bill_item_outros,
        DATEDIFF(DATE(i.dt_created_negotiation_parent), DATE(i.dt_invoice_anchor)) AS anchor_delay_from_deal,
        DATE(i.ts_due) AS dt_due,
        i.dt_invoice_anchor,
        i.dt_created_negotiation_parent,
        DATE(i.ts_paid) AS dt_paid,
        DATE(i.ts_created) AS dt_created,
        CASE
            WHEN i.ts_paid IS NOT NULL THEN LEAST(DATE(i.ts_created), DATE(i.ts_paid))
            ELSE DATE(i.ts_created)
        END AS dt_begin
    FROM datalake_collections_quintoandar.invoice_portfolio AS i
    LEFT JOIN add_bill_items_flags as d
        ON d.id_invoice = i.id_invoice
    WHERE i.invoice_status <> 'canceled'
      AND i.user = 'tenant'
      AND i.country_code = 'BR'
      AND (i.negotiation_installment_number IS NULL
        OR (i.negotiation_installment_number > 1
            AND COALESCE(i.negotiation_promisse_payment_method, 'UNFOUND') <> 'CREDIT-CARD'))
),
days_array AS (
    SELECT
        id_contract,
        id_invoice,
        SEQUENCE(dt_begin, COALESCE(dt_paid, CURRENT_DATE())) AS dt_reference_array
    FROM base
),
date_range AS (
    SELECT
        id_contract,
        id_invoice,
        dt_reference
    FROM days_array
    LATERAL VIEW EXPLODE(dt_reference_array) AS dt_reference
),
invoice_timeline AS (
    SELECT
        asdt.id_contract,
        asdt.id_invoice,
        rdb.id_negotiation_parent,
        rdb.id_negotiation_child,
        rdb.is_child_negotiation,
        rdb.is_negative_eligible,
        rdb.has_child,
        rdb.negotiation_promisse_payment_method,
        rdb.invoice_status,
        CASE
            WHEN rdb.invoice_status = 'not-payable' THEN 'not-payable'
            WHEN rdb.invoice_status = 'divergent-payment' THEN 'divergent-payment'
            WHEN asdt.dt_reference >= rdb.dt_paid
              AND rdb.invoice_status = 'written-down' THEN 'written-down'
            WHEN asdt.dt_reference >= rdb.dt_paid
              AND rdb.invoice_status = 'paid' THEN 'paid'
            ELSE 'open'
        END AS payment_status,
        CASE
            WHEN rdb.dt_contract_annulled IS NULL
              OR rdb.dt_contract_annulled > asdt.dt_reference THEN 'Ativo'
            ELSE 'Finalizado'
        END AS contract_status,
        rdb.purpose AS invoice_type,
        rdb.recovery_channel,
        rdb.anchor_delay_from_deal,
        CASE
            WHEN rdb.dt_paid IS NOT NULL
              AND rdb.dt_paid > asdt.dt_reference THEN NULL
            ELSE rdb.recovery_channel
        END AS recovery_channel_timeline,
        DATEDIFF(asdt.dt_reference, rdb.dt_due) AS delay_invoice_at_reference,
        rdb.net_rate_recovery,
        rdb.negotiation_installment_number,
        rdb.due_amount,
        CASE
            WHEN rdb.dt_paid IS NOT NULL
              AND rdb.dt_paid > asdt.dt_reference THEN 0
            WHEN rdb.dt_paid IS NOT NULL
              AND rdb.dt_paid <= asdt.dt_reference
              AND rdb.invoice_status = 'written-down'
              AND rdb.net_rate_recovery IS NOT NULL
              THEN LEAST(rdb.net_rate_recovery, 1) * ABS(rdb.due_amount)
            WHEN rdb.dt_paid IS NOT NULL
              AND rdb.dt_paid <= asdt.dt_reference
              AND rdb.invoice_status IN ('paid', 'written-down')
              THEN ABS(rdb.due_amount)
            ELSE 0
        END AS recovered_amount,
        rdb.has_bill_item_condominio,
        rdb.has_bill_item_multa_recisoria,
        rdb.has_bill_item_acordo,
        rdb.has_bill_item_rental_core,
        rdb.has_bill_item_reparos,
        rdb.has_bill_item_multas_ongoing,
        rdb.has_bill_item_utilidades,
        rdb.has_bill_item_outros,
        rdb.balance_bill_item_condominio,
        rdb.balance_bill_item_multa_recisoria,
        rdb.balance_bill_item_acordo,
        rdb.balance_bill_item_rental_core,
        rdb.balance_bill_item_reparos,
        rdb.balance_bill_item_multas_ongoing,
        rdb.balance_bill_item_utilidades,
        rdb.balance_bill_item_outros,
        asdt.dt_reference,
        rdb.dt_due,
        rdb.dt_invoice_anchor,
        rdb.dt_created_negotiation_parent,
        rdb.dt_paid,
        CASE
          WHEN rdb.dt_paid IS NOT NULL
            AND rdb.dt_paid > asdt.dt_reference THEN NULL
          ELSE rdb.dt_paid
        END AS dt_paid_timeline,
        rdb.dt_created,
        rdb.dt_begin,
        rdb.dt_contract_annulled
    FROM date_range AS asdt
    LEFT JOIN base rdb
      ON rdb.id_invoice = asdt.id_invoice AND rdb.id_contract = asdt.id_contract
    WHERE asdt.dt_reference >= DATE('2023-01-01')
),
contract_flags AS (
    SELECT
        id_contract,
        dt_reference,
        MAX(IF(is_child_negotiation, TRUE,FALSE)) AS has_negotiation_in_contract,
        MAX(CASE WHEN is_child_negotiation THEN anchor_delay_from_deal END) AS anchor_delay_contract
    FROM invoice_timeline
    GROUP BY 1,2
),
base_with_contract_flags AS (
    SELECT
        i.*,
        COALESCE(c.has_negotiation_in_contract, FALSE) AS has_negotiation_in_contract,
        COALESCE(c.anchor_delay_contract, 0) AS anchor_delay_contract,
        CASE
            WHEN i.is_child_negotiation
              AND i.delay_invoice_at_reference > 0 THEN 'DEAL IN DELAY'
            WHEN i.is_child_negotiation
              AND i.delay_invoice_at_reference <= 0 THEN 'DEAL ON TIME. DELAY AT ANCHOR'
            ELSE 'NOT-DEAL'
        END AS deal_status_on_delay
    FROM invoice_timeline i
    LEFT JOIN contract_flags c
      ON i.dt_reference = c.dt_reference
        AND i.id_contract = c.id_contract
),
delay_contamination_invoice AS (
    SELECT
        *,
        delay_invoice_at_reference AS invoice_delay_t1,
        CASE
            WHEN is_child_negotiation
              AND deal_status_on_delay = 'DEAL IN DELAY' THEN delay_invoice_at_reference + anchor_delay_contract
            WHEN is_child_negotiation
              AND deal_status_on_delay = 'DEAL ON TIME. DELAY AT ANCHOR' THEN anchor_delay_from_deal
            WHEN NOT is_child_negotiation
              AND has_negotiation_in_contract
              AND delay_invoice_at_reference > 0 THEN delay_invoice_at_reference + anchor_delay_contract
            WHEN NOT is_child_negotiation
              AND has_negotiation_in_contract
              AND delay_invoice_at_reference <= 0 THEN delay_invoice_at_reference
            ELSE delay_invoice_at_reference
        END AS invoice_delay_t2
    FROM base_with_contract_flags
),
delay_contamination_contract AS (
    SELECT
        dt_reference,
        id_contract,
        MAX(invoice_delay_t2) AS contract_delay_t3,
        MAX(IF(payment_status IN ('open', 'written-down'), invoice_delay_t2, NULL)) AS contract_delay_t3_losses,
        MAX(invoice_delay_t1) AS contract_delay_t1
        FROM delay_contamination_invoice
    GROUP BY 1,2
)
SELECT
    i.id_contract,
    i.id_invoice,
    i.id_negotiation_parent,
    i.id_negotiation_child,
    i.is_child_negotiation,
    i.is_negative_eligible,
    i.has_child,
    i.negotiation_promisse_payment_method,
    i.invoice_status,
    i.payment_status,
    i.contract_status,
    i.invoice_type,
    i.recovery_channel,
    i.anchor_delay_from_deal,
    i.recovery_channel_timeline,
    i.has_negotiation_in_contract,
    i.deal_status_on_delay,
    IF(i.invoice_delay_t1 > 0, TRUE, FALSE) AS is_invoice_overdue_t1,
    IF(i.invoice_delay_t2 > 0, TRUE, FALSE) AS is_invoice_overdue_t2,
    IF(c.contract_delay_t3 > 0, TRUE, FALSE) AS is_invoice_overdue_t3,
    i.delay_invoice_at_reference,
    i.net_rate_recovery,
    i.negotiation_installment_number,
    i.due_amount,
    i.recovered_amount,
    i.has_bill_item_condominio,
    i.has_bill_item_multa_recisoria,
    i.has_bill_item_acordo,
    i.has_bill_item_rental_core,
    i.has_bill_item_reparos,
    i.has_bill_item_multas_ongoing,
    i.has_bill_item_utilidades,
    i.has_bill_item_outros,
    i.balance_bill_item_condominio,
    i.balance_bill_item_multa_recisoria,
    i.balance_bill_item_acordo,
    i.balance_bill_item_rental_core,
    i.balance_bill_item_reparos,
    i.balance_bill_item_multas_ongoing,
    i.balance_bill_item_utilidades,
    i.balance_bill_item_outros,
    i.anchor_delay_contract,
    i.invoice_delay_t1,
    i.invoice_delay_t2,
    c.contract_delay_t3 as invoice_delay_t3,
    IF(i.invoice_delay_t1 > 0, i.recovered_amount, 0) AS overdue_recovered_amount_t1,
    IF(i.invoice_delay_t1 < =0, i.recovered_amount, 0) AS on_time_paid_amount_t1,
    IF(i.invoice_delay_t2 > 0, i.recovered_amount, 0) AS overdue_recovered_amount_t2,
    IF(i.invoice_delay_t2 <= 0, i.recovered_amount, 0) AS on_time_paid_amount_t2,
    IF(c.contract_delay_t3 > 0, i.recovered_amount, 0) AS overdue_recovered_amount_t3,
    IF(c.contract_delay_t3 <=0, i.recovered_amount, 0) AS on_time_paid_amount_t3,
    c.contract_delay_t1,
    c.contract_delay_t3,
    c.contract_delay_t3_losses,
    ROW_NUMBER() OVER (PARTITION BY i.id_contract, i.dt_reference ORDER BY i.invoice_delay_t2 DESC, i.dt_created ASC, i.id_invoice ASC) AS order_invoice_wallet_risk,
    ROW_NUMBER() OVER (PARTITION BY i.id_contract, i.dt_reference ORDER BY i.invoice_delay_t1 DESC, i.dt_created ASC, i.id_invoice ASC) AS order_invoice_wallet,
    i.dt_reference,
    i.dt_due,
    i.dt_invoice_anchor,
    i.dt_created_negotiation_parent,
    i.dt_paid,
    i.dt_paid_timeline,
    i.dt_created,
    i.dt_begin,
    i.dt_contract_annulled,
    NOW() AS ts_load
FROM
    delay_contamination_invoice AS i
LEFT JOIN delay_contamination_contract AS c
    ON c.id_contract = i.id_contract AND i.dt_reference = c.dt_reference
