WITH
trato_feito_debts_ranked AS (
  SELECT
    d.id_external AS id_invoice,
    n.id_contract,
    IFNULL(CAST(n.id_negotiation_external AS BIGINT), n.id_negotiation_external) AS id_negotiation,
    'Trato Feito' AS source,
    1 AS priority,
    ROW_NUMBER() OVER (
      PARTITION BY n.id_contract, d.id_external, d.id_negotiation
      ORDER BY d.ts_created DESC
    ) AS rn
  FROM datalake_trato_feito_clean.debt AS d
  LEFT JOIN datalake_debt_recovery.negotiation AS n
    ON d.id_negotiation = n.id_negotiation
  WHERE
    d.id_negotiation IS NOT NULL
    AND n.debtor != 'velo_delinquency_tenant'
),
trato_feito_debts AS (
  SELECT
    id_invoice,
    id_contract,
    id_negotiation,
    source,
    priority
  FROM trato_feito_debts_ranked
  WHERE rn = 1
),
debt_negotiated_no_cyber_ranked AS (
  SELECT
    COALESCE(t.id_contract, r.id_contract) AS id_contract,
    COALESCE(t.id_invoice, r.id_invoice) AS id_invoice,
    CAST(COALESCE(t.id_negotiation, r.id_negotiation) AS STRING) AS id_negotiation,
    ROW_NUMBER() OVER (
      PARTITION BY
        COALESCE(t.id_contract, r.id_contract),
        COALESCE(t.id_invoice, r.id_invoice),
        CAST(COALESCE(t.id_negotiation, r.id_negotiation) AS STRING)
      ORDER BY COALESCE(t.priority, r.priority)
    ) AS rn
  FROM trato_feito_debts AS t
  FULL OUTER JOIN datalake_recupera.invoice_debt_negotiation AS r
    ON CAST(t.id_negotiation AS BIGINT) = CAST(r.id_negotiation AS BIGINT)
      AND t.id_invoice = r.id_invoice
),
debt_negotiated_no_cyber AS (
  SELECT
    id_contract,
    id_invoice,
    id_negotiation
  FROM debt_negotiated_no_cyber_ranked
  WHERE rn = 1
),
trato_feito_negotiation AS (
  SELECT
    COALESCE(CAST(n.id_negotiation_external AS BIGINT), n.id_negotiation_external) AS id_negotiation,
    n.id_contract,
    n.consultancy_name AS advisory,
    CASE
      WHEN UPPER(n.contact_type) IN ('IAPORTAL', 'IAWPP') THEN 'Matthew'
      WHEN n.consultancy_name = 'PORTAL_QUINTOANDAR' THEN 'Portal Auto Negociação'
      WHEN UPPER(n.consultancy_name) IN (
        'PASCHOALOTTO', 'MEETCALL', 'TRC', 'GRB', 'BULGARELLI',
        'MONEST', 'PELLON', 'PLC', 'GONDIM', 'NOVAQUEST'
      ) THEN 'Assessoria'
      WHEN n.consultancy_name = 'SERASA' THEN 'Serasa Digital'
      WHEN n.consultancy_name = 'COBRANÇA_INTERNA_QA' THEN 'Operador Interno'
    END AS origin_agreement,
    n.promisse_payment_method,
    n.status AS negotiation_status,
    n.down_payment_amount,
    n.negotiation_original_amount AS original_debt_amount,
    n.net_recovery_rate,
    DATE(n.ts_created_at) AS dt_promisse,
    DATE(n.ts_first_payment) AS dt_down_payment
  FROM datalake_debt_recovery.negotiation AS n
  WHERE n.debtor != 'velo_delinquency_tenant'
),
negotiation_no_cyber AS (
  SELECT DISTINCT
    COALESCE(tf.id_negotiation, rn.id_negotiation) AS id_negotiation,
    COALESCE(tf.id_contract, rn.id_contract) AS id_contract,
    COALESCE(rn.advisory, tf.advisory) AS advisory,
    COALESCE(rn.origin_agreement, tf.origin_agreement) AS origin_agreement,
    COALESCE(tf.down_payment_amount, rn.down_payment_amount) AS down_payment_amount,
    COALESCE(tf.original_debt_amount, rn.original_debt_amount) AS original_debt_amount,
    COALESCE(
      tf.net_recovery_rate,
      CAST(rn.down_payment_amount / NULLIF(rn.original_debt_amount, 0) AS DECIMAL(14,2))
    ) AS net_recovery_rate,
    COALESCE(tf.dt_promisse, rn.dt_promisse) AS dt_promisse,
    COALESCE(tf.dt_down_payment, rn.dt_down_payment) AS dt_down_payment,
    COALESCE(tf.negotiation_status, rn.negotiation_status) AS negotiation_status,
    UPPER(COALESCE(tf.promisse_payment_method, rn.promisse_payment_method)) AS promisse_payment_method
  FROM trato_feito_negotiation AS tf
  FULL OUTER JOIN datalake_recupera.negotiation_wallet AS rn
    ON tf.id_negotiation = rn.id_negotiation
      AND tf.id_contract = rn.id_contract
),
installment_no_cyber AS (
  SELECT
    CAST(n.id_negotiation_external AS BIGINT) AS id_negotiation,
    n.id_contract,
    CAST(di.id_invoice_extra AS BIGINT) AS id_invoice_extra,
    di.installment_number
  FROM datalake_debt_recovery.installment AS di
  INNER JOIN datalake_debt_recovery.negotiation AS n
    ON di.id_negotiation = n.id_negotiation
  WHERE
    n.debtor != 'velo_delinquency_tenant'
    AND di.id_invoice_extra IS NOT NULL
),
invoice_base AS (
  SELECT
    i.*,
    ii.invoice_user AS user,
    c.id_house,
    c.id_proposal,
    c.status AS contract_status,
    c.dt_termination AS dt_contract_annulled,
    c.dt_started AS dt_contract_start
  FROM datalake_retsuko.invoice AS i
  LEFT JOIN datalake_retsuko.invoice_info AS ii
    ON i.id_external = ii.id_invoice
  LEFT JOIN datalake_ebdb_contract.contract AS c
    ON c.id = i.id_contract_external
  WHERE
    i.due_amount < 0
    AND c.country_code = 'BR'
    AND ii.invoice_user = 'tenant'
),
negotiation_child_ranked AS (
  SELECT
    dn.id_invoice AS id_invoice,
    dn.id_negotiation AS id_negotiation_child,
    n.advisory AS agency,
    n.origin_agreement,
    n.down_payment_amount,
    n.original_debt_amount,
    n.net_recovery_rate,
    n.dt_promisse,
    ROW_NUMBER() OVER (
      PARTITION BY dn.id_invoice
      ORDER BY n.dt_promisse DESC
    ) AS rn
  FROM debt_negotiated_no_cyber AS dn
  LEFT JOIN negotiation_no_cyber AS n
    ON dn.id_negotiation = CAST(n.id_negotiation AS STRING)
      AND dn.id_contract = n.id_contract
  WHERE
    n.dt_down_payment IS NOT NULL
    AND n.negotiation_status IN ('offset', 'finished', 'broken-requested-by-client', 'broken')
),
negotiation_child AS (
  SELECT
    id_invoice,
    id_negotiation_child,
    agency,
    origin_agreement,
    down_payment_amount,
    original_debt_amount,
    net_recovery_rate,
    dt_promisse
  FROM negotiation_child_ranked
  WHERE rn = 1
),
negotiation_parent_ranked AS (
  SELECT
    ni.id_invoice_extra AS id_invoice,
    d.id_invoice AS id_invoice_parent,
    ni.id_negotiation AS id_negotiation_parent,
    ni.installment_number,
    n.promisse_payment_method,
    DATE(i.ts_due) AS dt_due_parent,
    i.dt_due_adjusted AS dt_due_adjusted_parent,
    n.dt_promisse,
    ROW_NUMBER() OVER (
      PARTITION BY ni.id_invoice_extra
      ORDER BY DATE(i.ts_due), ni.id_invoice_extra
    ) AS rn
  FROM installment_no_cyber AS ni
  LEFT JOIN negotiation_no_cyber AS n
    ON ni.id_negotiation = n.id_negotiation
      AND ni.id_contract = n.id_contract
  LEFT JOIN debt_negotiated_no_cyber AS d
    ON CAST(d.id_negotiation AS BIGINT) = ni.id_negotiation
      AND d.id_contract = ni.id_contract
  LEFT JOIN datalake_retsuko.invoice AS i
    ON d.id_invoice = i.id_external
      AND d.id_contract = i.id_contract_external
),
negotiation_parent AS (
  SELECT
    id_invoice,
    id_invoice_parent,
    id_negotiation_parent,
    installment_number,
    promisse_payment_method,
    dt_due_parent,
    dt_due_adjusted_parent,
    dt_promisse
  FROM negotiation_parent_ranked
  WHERE rn = 1
),
base_negotiation AS (
  SELECT DISTINCT
    i.id_contract_external AS id_contract,
    i.id_external AS id_invoice,
    parent.id_invoice_parent,
    parent.id_negotiation_parent,
    parent.promisse_payment_method,
    child.id_negotiation_child,
    child.agency AS child_negotiation_agency,
    child.origin_agreement,
    child.net_recovery_rate AS net_rate_recovery,
    parent.installment_number AS negotiation_installment_number,
    DATE(i.ts_due) AS dt_due,
    parent.dt_due_parent,
    parent.dt_due_adjusted_parent,
    parent.dt_promisse AS dt_created_negotiation_parent,
    child.dt_promisse AS dt_created_negotiation_child
  FROM invoice_base AS i
  LEFT JOIN negotiation_parent AS parent
    ON i.id_external = parent.id_invoice
  LEFT JOIN negotiation_child AS child
    ON child.id_invoice = i.id_external
  WHERE
    parent.id_negotiation_parent IS NOT NULL
    OR child.id_negotiation_child IS NOT NULL
),
contract_write_off AS (
  SELECT DISTINCT
    id_contract_external
  FROM invoice_base
  WHERE is_write_off IS TRUE
),
first_payment AS (
  SELECT
    id_contract_external,
    id_external,
    CASE
      WHEN ROW_NUMBER() OVER (
        PARTITION BY id_contract_external
        ORDER BY dt_due_adjusted, ts_created, id_external
      ) = 1 THEN TRUE
      ELSE FALSE
    END AS is_first_payment
  FROM invoice_base
  WHERE
    LOWER(status) != 'canceled'
    AND LOWER(contract_status) != 'cancelado'
),
first_invoice_contract AS (
  SELECT
    id_contract_external,
    id_external,
    CASE
      WHEN purpose IN ('monthly', 'onboarding')
        AND ROW_NUMBER() OVER (
          PARTITION BY id_contract_external
          ORDER BY dt_due_adjusted, ts_created, id_external
        ) = 1 THEN TRUE
      ELSE FALSE
    END AS is_first_invoice_contract
  FROM invoice_base
  WHERE LOWER(status) != 'canceled'
),
invoice_portfolio_no_cyber AS (
  SELECT
    b.id_external AS id_invoice,
    b.id_contract_external AS id_contract,
    bn.id_negotiation_parent,
    bn.id_negotiation_child,
    bn.negotiation_installment_number,
    IF(bn.id_negotiation_parent IS NOT NULL, TRUE, FALSE) AS is_child_negotiation,
    IF(bn.id_negotiation_child IS NOT NULL, TRUE, FALSE) AS has_child,
    b.user,
    b.status AS invoice_status,
    b.purpose,
    b.country_code,
    COALESCE(btf.negativate, TRUE) AS is_negative_eligible,
    bn.promisse_payment_method AS negotiation_promisse_payment_method,
    bn.net_rate_recovery,
    b.due_amount,
    IFNULL(fp.is_first_payment, FALSE) AS is_first_payment,
    IFNULL(fic.is_first_invoice_contract, FALSE) AS is_first_invoice_contract,
    bn.dt_due_parent AS dt_invoice_anchor,
    b.dt_contract_start,
    b.dt_contract_annulled,
    bn.dt_created_negotiation_parent,
    bn.dt_created_negotiation_child,
    b.ts_due,
    b.ts_paid,
    b.ts_created
  FROM invoice_base AS b
  LEFT JOIN contract_write_off AS cwo
    ON cwo.id_contract_external = b.id_contract_external
  LEFT JOIN first_payment AS fp
    ON fp.id_external = b.id_external
      AND fp.id_contract_external = b.id_contract_external
  LEFT JOIN first_invoice_contract AS fic
    ON fic.id_external = b.id_external
      AND fic.id_contract_external = b.id_contract_external
  LEFT JOIN base_negotiation AS bn
    ON bn.id_invoice = b.id_external
      AND bn.id_contract = b.id_contract_external
  LEFT JOIN datalake_trato_feito_clean.bill AS btf
    ON btf.id_external = b.id_external
),
base AS (
  SELECT
    i.id_invoice,
    i.id_contract,
    i.dt_contract_start,
    i.dt_contract_annulled,
    i.id_negotiation_parent,
    i.id_negotiation_child,
    i.is_child_negotiation,
    i.has_child,
    i.is_negative_eligible,
    i.is_first_payment,
    i.is_first_invoice_contract,
    i.net_rate_recovery,
    i.negotiation_installment_number,
    i.negotiation_promisse_payment_method,
    i.invoice_status,
    i.purpose,
    i.due_amount,
    DATEDIFF(DATE(i.dt_created_negotiation_parent), DATE(i.dt_invoice_anchor)) AS anchor_delay_from_deal,
    DATE(i.ts_due) AS dt_due,
    i.dt_invoice_anchor,
    i.dt_created_negotiation_parent,
    i.dt_created_negotiation_child,
    DATE(i.ts_paid) AS dt_paid,
    DATE(i.ts_created) AS dt_created,
    LEAST(DATE(i.ts_created), COALESCE(DATE(i.ts_paid), DATE(i.ts_created))) AS dt_begin
  FROM invoice_portfolio_no_cyber AS i
  WHERE i.invoice_status <> 'canceled'
    AND i.user = 'tenant'
    AND i.country_code = 'BR'
    AND (
      i.negotiation_installment_number IS NULL
      OR (
        i.negotiation_installment_number > 1
        AND COALESCE(i.negotiation_promisse_payment_method, 'UNFOUND') <> 'CREDIT-CARD'
      )
    )
),
days_array AS (
  SELECT
    id_contract,
    id_invoice,
    SEQUENCE(dt_begin, COALESCE(dt_paid, DATE('{load_end_date}'))) AS dt_reference_array
  FROM base
),
date_range AS (
  SELECT
    id_contract,
    id_invoice,
    dt_reference
  FROM days_array
  LATERAL VIEW EXPLODE(dt_reference_array) AS dt_reference
  WHERE dt_reference BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
),
invoice_timeline AS (
  SELECT
    asdt.id_contract,
    asdt.id_invoice,
    rdb.id_negotiation_parent,
    CASE
      WHEN rdb.dt_created_negotiation_child IS NOT NULL
        AND asdt.dt_reference >= DATE(rdb.dt_created_negotiation_child)
        THEN rdb.id_negotiation_child
      ELSE NULL
    END AS id_negotiation_child,
    rdb.is_child_negotiation,
    rdb.is_negative_eligible,
    CASE
      WHEN rdb.dt_created_negotiation_child IS NOT NULL
        AND asdt.dt_reference >= DATE(rdb.dt_created_negotiation_child)
        THEN rdb.has_child
      ELSE FALSE
    END AS has_child,
    rdb.negotiation_promisse_payment_method,
    CASE
      WHEN rdb.invoice_status IN ('not-payable', 'divergent-payment')
        THEN rdb.invoice_status
      WHEN asdt.dt_reference >= rdb.dt_paid
        AND rdb.invoice_status IN ('written-down', 'paid')
        THEN rdb.invoice_status
      WHEN rdb.invoice_status IN ('written-down', 'paid')
        THEN 'open'
      ELSE rdb.invoice_status
    END AS invoice_status,
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
    rdb.anchor_delay_from_deal,
    DATEDIFF(asdt.dt_reference, rdb.dt_due) AS delay_invoice_at_reference,
    CASE
      WHEN rdb.dt_created_negotiation_child IS NOT NULL
        AND asdt.dt_reference >= DATE(rdb.dt_created_negotiation_child)
        THEN rdb.net_rate_recovery
      ELSE NULL
    END AS net_rate_recovery,
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
    rdb.is_first_payment,
    rdb.is_first_invoice_contract,
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
    rdb.dt_contract_start,
    rdb.dt_contract_annulled
  FROM date_range AS asdt
  LEFT JOIN base AS rdb
    ON rdb.id_invoice = asdt.id_invoice
      AND rdb.id_contract = asdt.id_contract
),
contract_flags AS (
  SELECT
    id_contract,
    dt_reference,
    MAX(IF(is_child_negotiation, TRUE, FALSE)) AS has_negotiation_in_contract,
    MAX(CASE WHEN is_child_negotiation THEN anchor_delay_from_deal END) AS anchor_delay_contract
  FROM invoice_timeline
  GROUP BY 1, 2
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
  FROM invoice_timeline AS i
  LEFT JOIN contract_flags AS c
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
  GROUP BY 1, 2
)
SELECT
  MD5(CONCAT(i.id_invoice, i.id_contract, DATE_FORMAT(i.dt_reference, 'yyyyMMdd'))) AS id_invoice_wallet_timeline,
  i.id_contract,
  i.id_invoice,
  i.id_negotiation_parent,
  i.id_negotiation_child,
  i.dt_reference,
  i.is_child_negotiation,
  i.is_negative_eligible,
  i.has_child,
  i.negotiation_promisse_payment_method,
  i.invoice_status,
  i.payment_status,
  i.contract_status,
  i.invoice_type,
  i.anchor_delay_from_deal,
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
  i.is_first_payment,
  i.is_first_invoice_contract,
  i.anchor_delay_contract,
  i.invoice_delay_t1,
  i.invoice_delay_t2,
  c.contract_delay_t3 AS invoice_delay_t3,
  IF(i.invoice_delay_t1 > 0, i.recovered_amount, 0) AS overdue_recovered_amount_t1,
  IF(i.invoice_delay_t1 <= 0, i.recovered_amount, 0) AS on_time_paid_amount_t1,
  IF(i.invoice_delay_t2 > 0, i.recovered_amount, 0) AS overdue_recovered_amount_t2,
  IF(i.invoice_delay_t2 <= 0, i.recovered_amount, 0) AS on_time_paid_amount_t2,
  IF(c.contract_delay_t3 > 0, i.recovered_amount, 0) AS overdue_recovered_amount_t3,
  IF(c.contract_delay_t3 <= 0, i.recovered_amount, 0) AS on_time_paid_amount_t3,
  c.contract_delay_t1,
  c.contract_delay_t3,
  c.contract_delay_t3_losses,
  ROW_NUMBER() OVER (
    PARTITION BY i.id_contract, i.dt_reference
    ORDER BY i.invoice_delay_t2 DESC, i.dt_created ASC, i.id_invoice ASC
  ) AS order_invoice_wallet_risk,
  ROW_NUMBER() OVER (
    PARTITION BY i.id_contract, i.dt_reference
    ORDER BY i.invoice_delay_t1 DESC, i.dt_created ASC, i.id_invoice ASC
  ) AS order_invoice_wallet,
  i.dt_due,
  i.dt_invoice_anchor,
  i.dt_created_negotiation_parent,
  i.dt_paid,
  i.dt_paid_timeline,
  i.dt_created,
  i.dt_begin,
  i.dt_contract_start,
  i.dt_contract_annulled,
  YEAR(i.dt_reference) AS year,
  MONTH(i.dt_reference) AS month,
  DAY(i.dt_reference) AS day,
  NOW() AS ts_load
FROM delay_contamination_invoice AS i
LEFT JOIN delay_contamination_contract AS c
  ON c.id_contract = i.id_contract
    AND i.dt_reference = c.dt_reference
