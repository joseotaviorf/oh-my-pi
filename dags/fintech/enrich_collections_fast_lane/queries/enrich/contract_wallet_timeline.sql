WITH
invoice_reparos AS (
  SELECT DISTINCT
    id_invoice
  FROM datalake_retsuko.bill_items
  WHERE
    bill_item_cluster_name = 'REPAROS'
    AND due_amount <= 0
    AND payment_status IN ('open', 'paid', 'canceled', 'written-down')
),
contract_features AS (
  SELECT
    iwt.dt_reference,
    iwt.id_contract,
    CAST(MAX(iwt.has_negotiation_in_contract) AS BOOLEAN) AS has_negotiation_in_contract,
    COUNT(DISTINCT IF(ir.id_invoice IS NOT NULL, iwt.id_invoice, NULL)) AS n_reparos_invoices,
    COUNT(CASE WHEN iwt.is_first_invoice_contract THEN iwt.id_invoice ELSE NULL END) AS n_first_invoices,
    COUNT(
      CASE
        WHEN iwt.invoice_type IN ('monthly', 'onboarding')
          AND iwt.invoice_delay_t1 > 0
        THEN iwt.id_invoice
      END
    ) AS n_overdue_monthlys_t1,
    MAX(IF(NOT iwt.is_child_negotiation, iwt.invoice_delay_t1, 0)) AS max_delay_original_invoices_t1,
    MAX(IF(iwt.is_child_negotiation, iwt.invoice_delay_t1, 0)) AS max_delay_deal_invoices_t1,
    MAX(iwt.invoice_delay_t2) AS max_delay_contaminated_contract_t2,
    MAX(iwt.invoice_delay_t1) AS max_delay_contaminated_contract_t1,
    SUM(
      CASE
        WHEN iwt.is_invoice_overdue_t1
          AND iwt.overdue_recovered_amount_t1 > 0
          AND iwt.invoice_type IN ('monthly')
        THEN iwt.invoice_delay_t1
        ELSE 0
      END
    ) AS sum_monthly_overdue_days_paid_t1,
    COUNT(
      DISTINCT CASE
        WHEN iwt.is_invoice_overdue_t1
          AND iwt.overdue_recovered_amount_t1 > 0
          AND iwt.invoice_type IN ('monthly')
        THEN iwt.id_invoice
      END
    ) AS count_monthly_overdue_invoices_paid_t1,
    COUNT(DISTINCT iwt.id_invoice) AS n_invoices_in_wallet_total,
    SUM(
      IF(iwt.payment_status = 'open' AND iwt.is_invoice_overdue_t1, ABS(iwt.due_amount), 0)
    ) AS open_wallet_overdue_t1,
    MAX(IF(iwt.payment_status = 'open', iwt.invoice_delay_t1, 0)) AS max_open_delay_contaminated_contract_t1,
    COUNT(CASE WHEN iwt.invoice_type IN ('monthly') THEN iwt.id_invoice ELSE NULL END) AS n_monthly_invoices,
    COUNT(
      CASE
        WHEN iwt.payment_status IN ('paid', 'written-down')
          AND iwt.invoice_type IN ('monthly')
          AND iwt.invoice_delay_t1 <= 0
        THEN iwt.id_invoice
        ELSE NULL
      END
    ) AS n_monthly_invoices_paid_ontime_t1,
    COUNT(
      CASE
        WHEN iwt.invoice_type IN ('monthly')
          AND iwt.dt_reference = iwt.dt_begin
        THEN iwt.id_invoice
        ELSE NULL
      END
    ) AS n_monthly_invoices_created
  FROM datalake_collections_fast_lane.invoice_wallet_timeline AS iwt
  LEFT JOIN invoice_reparos AS ir
    ON iwt.id_invoice = ir.id_invoice
  WHERE iwt.dt_reference BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
  GROUP BY 1, 2
),
get_invoice_date_range AS (
  SELECT
    id_contract,
    MAX(dt_contract_start) AS dt_contract_start,
    MAX(dt_contract_annulled) AS dt_contract_end,
    MIN(dt_reference) AS dt_first_invoice,
    MAX(dt_reference) AS dt_last_invoice
  FROM datalake_collections_fast_lane.invoice_wallet_timeline
  GROUP BY 1
),
get_date_interval AS (
  SELECT
    id_contract,
    dt_contract_start,
    dt_contract_end,
    GREATEST(dt_first_invoice, DATE('{load_start_date}')) AS dt_start_interval,
    IF(
      dt_contract_end IS NOT NULL,
      LEAST(
        GREATEST(DATE_ADD(dt_contract_end, 90), dt_last_invoice),
        DATE('{load_end_date}')
      ),
      DATE('{load_end_date}')
    ) AS dt_end_interval
  FROM get_invoice_date_range
),
get_date_array AS (
  SELECT
    id_contract,
    dt_contract_start,
    dt_contract_end,
    SEQUENCE(dt_start_interval, dt_end_interval) AS dt_reference_array
  FROM get_date_interval
  WHERE dt_end_interval BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
),
contract_date_references AS (
  SELECT
    id_contract,
    dt_contract_end,
    dt_contract_start,
    dt_reference
  FROM get_date_array
  LATERAL VIEW EXPLODE(dt_reference_array) AS dt_reference
),
base_evictions AS (
  SELECT
    id_process,
    process,
    CAST(contract AS BIGINT) AS id_contract,
    DATE(dt_registered) AS dt_registered,
    DATE(dt_arbitral_distribution_start) AS dt_arbitral_distribution,
    DATE(dt_closure) AS dt_elaw_closure,
    LEAST(DATE(dt_registered), DATE(dt_arbitral_distribution_start)) AS dt_begin
  FROM datalake_cyber_legal.evictions_base
  WHERE
    DATE(dt_registered) IS NOT NULL
    AND (
      DATE(dt_closure) > LEAST(DATE(dt_registered), DATE(dt_arbitral_distribution_start))
      OR DATE(dt_closure) IS NULL
    )
),
evictions_with_date_array AS (
  SELECT
    id_process,
    process,
    id_contract,
    dt_registered,
    dt_arbitral_distribution,
    dt_elaw_closure,
    dt_begin,
    SEQUENCE(
      GREATEST(dt_begin, DATE('{load_start_date}')),
      LEAST(COALESCE(DATE(dt_elaw_closure), DATE('{load_end_date}')), DATE('{load_end_date}'))
    ) AS dt_reference_array
  FROM base_evictions
  WHERE GREATEST(dt_begin, DATE('{load_start_date}'))
    <= LEAST(COALESCE(DATE(dt_elaw_closure), DATE('{load_end_date}')), DATE('{load_end_date}'))
),
date_expansion AS (
  SELECT
    dt_reference,
    id_process,
    process,
    id_contract,
    dt_registered,
    dt_arbitral_distribution,
    dt_elaw_closure,
    dt_begin
  FROM evictions_with_date_array
  LATERAL VIEW EXPLODE(dt_reference_array) AS dt_reference
),
timeline_addition AS (
  SELECT
    dt_reference,
    id_process,
    process,
    id_contract,
    dt_registered,
    dt_arbitral_distribution,
    dt_elaw_closure,
    dt_begin,
    IF(dt_registered > dt_reference, NULL, dt_registered) AS dt_registered_timeline,
    IF(dt_arbitral_distribution > dt_reference, NULL, dt_arbitral_distribution) AS dt_arbitral_distribution_timeline,
    IF(dt_elaw_closure > dt_reference, NULL, dt_elaw_closure) AS dt_elaw_closure_timeline
  FROM date_expansion
),
status_timeline_evic AS (
  SELECT
    dt_reference,
    id_process,
    process,
    id_contract,
    dt_registered,
    dt_arbitral_distribution,
    dt_elaw_closure,
    dt_begin,
    dt_registered_timeline,
    dt_arbitral_distribution_timeline,
    dt_elaw_closure_timeline,
    CASE
      WHEN dt_elaw_closure_timeline IS NOT NULL THEN 'EVENDED'
      WHEN dt_registered_timeline IS NULL
        AND dt_arbitral_distribution_timeline IS NOT NULL
        AND dt_elaw_closure_timeline IS NULL THEN 'EVEX'
      WHEN dt_registered_timeline IS NOT NULL
        AND dt_arbitral_distribution_timeline IS NOT NULL
        AND dt_elaw_closure_timeline IS NULL THEN 'EVEX'
      WHEN dt_registered_timeline IS NOT NULL
        AND dt_arbitral_distribution_timeline IS NULL
        AND dt_elaw_closure_timeline IS NULL THEN 'EVPD'
      ELSE 'EV-UNDEFINED'
    END AS status_time
  FROM timeline_addition
),
evictions_timeline_ranked AS (
  SELECT
    id_contract,
    id_process,
    TRUE AS is_evictions,
    dt_reference,
    ROW_NUMBER() OVER (PARTITION BY id_contract, dt_reference ORDER BY id_process) AS rn
  FROM status_timeline_evic
  WHERE status_time IN ('EVEX', 'EVPD')
),
evictions_timeline AS (
  SELECT
    id_contract,
    id_process,
    is_evictions,
    dt_reference
  FROM evictions_timeline_ranked
  WHERE rn = 1
),
negotiations AS (
  SELECT
    DATE(dt_promisse) AS dt_reference,
    id_contract,
    COUNT(
      DISTINCT CASE
        WHEN discount_to_original_amount > 50
          AND dt_down_payment IS NOT NULL
        THEN id_negotiation
      END
    ) AS qt_aco_desconto
  FROM datalake_collections_quintoandar.negotiation
  WHERE
    negotiation_status IN (
      'broken-requested-by-client',
      'started',
      'offset',
      'broken',
      'finished',
      'canceled'
    )
    AND DATE(dt_promisse) <= DATE('{load_end_date}')
  GROUP BY 1, 2
),
contract_static_info_ranked AS (
  SELECT
    id AS id_contract,
    CASE
      WHEN UPPER(guarantee_type) = 'SEGUROFAIRFAX' THEN 'FAIRFAX'
      WHEN UPPER(guarantee_type) = 'PRO_GUARANTOR' THEN 'PRO_GUARANTOR'
      WHEN UPPER(guarantee_type) = 'RENTALGUARANTEE' THEN 'RENTAL_GUARANTEE'
      WHEN UPPER(guarantee_type) = 'RENTALDEPOSIT' OR guarantee_type = 'DEPOSITO' THEN 'RENTAL_DEPOSIT'
      WHEN UPPER(guarantee_type) IN ('STANDALONE', 'THIRDPARTYGUARANTEE') THEN 'BROKERAGE_ONLY'
      ELSE 'OTHERS'
    END AS contract_guarantee,
    ROW_NUMBER() OVER (PARTITION BY id ORDER BY ts_updated DESC) AS rn
  FROM datalake_ebdb_contract.contract
),
contract_static_info AS (
  SELECT
    id_contract,
    contract_guarantee
  FROM contract_static_info_ranked
  WHERE rn = 1
),
contract_timeline AS (
  SELECT
    m.id_contract,
    m.dt_reference,
    m.dt_contract_start,
    m.dt_contract_end,
    CASE
      WHEN m.dt_contract_end IS NULL
        OR m.dt_contract_end > m.dt_reference THEN 'Ativo'
      ELSE 'Finalizado'
    END AS reference_contract_status,
    COALESCE(f.has_negotiation_in_contract, FALSE) AS has_negotiation_in_contract,
    COALESCE(f.n_reparos_invoices, 0) AS n_reparos_invoices,
    COALESCE(f.n_first_invoices, 0) AS n_first_invoices,
    COALESCE(f.n_overdue_monthlys_t1, 0) AS n_overdue_monthlys_t1,
    COALESCE(f.max_delay_original_invoices_t1, 0) AS max_delay_original_invoices_t1,
    COALESCE(f.max_delay_deal_invoices_t1, 0) AS max_delay_deal_invoices_t1,
    COALESCE(f.max_delay_contaminated_contract_t2, 0) AS max_delay_contaminated_contract_t2,
    COALESCE(f.max_delay_contaminated_contract_t1, 0) AS max_delay_contaminated_contract_t1,
    COALESCE(f.sum_monthly_overdue_days_paid_t1, 0) AS sum_monthly_overdue_days_paid_t1,
    COALESCE(f.count_monthly_overdue_invoices_paid_t1, 0) AS count_monthly_overdue_invoices_paid_t1,
    COALESCE(f.n_invoices_in_wallet_total, 0) AS n_invoices_in_wallet_total,
    COALESCE(f.open_wallet_overdue_t1, 0) AS open_wallet_overdue_t1,
    COALESCE(f.max_open_delay_contaminated_contract_t1, 0) AS max_open_delay_contaminated_contract_t1,
    COALESCE(f.n_monthly_invoices, 0) AS n_monthly_invoices,
    COALESCE(f.n_monthly_invoices_paid_ontime_t1, 0) AS n_monthly_invoices_paid_ontime_t1,
    COALESCE(f.n_monthly_invoices_created, 0) AS n_monthly_invoices_created
  FROM contract_date_references AS m
  LEFT JOIN contract_features AS f
    ON m.id_contract = f.id_contract
    AND m.dt_reference = f.dt_reference
),
contract_enhanced AS (
  SELECT
    m.id_contract,
    m.dt_reference,
    m.dt_contract_start,
    m.dt_contract_end,
    m.reference_contract_status,
    m.has_negotiation_in_contract,
    m.n_reparos_invoices,
    m.n_first_invoices,
    m.n_overdue_monthlys_t1,
    m.max_delay_original_invoices_t1,
    m.max_delay_deal_invoices_t1,
    m.max_delay_contaminated_contract_t2,
    m.max_delay_contaminated_contract_t1,
    m.sum_monthly_overdue_days_paid_t1,
    m.count_monthly_overdue_invoices_paid_t1,
    m.n_invoices_in_wallet_total,
    m.open_wallet_overdue_t1,
    m.max_open_delay_contaminated_contract_t1,
    m.n_monthly_invoices,
    m.n_monthly_invoices_paid_ontime_t1,
    m.n_monthly_invoices_created,
    COALESCE(csi.contract_guarantee, 'OTHERS') AS contract_guarantee,
    COALESCE(e.is_evictions, FALSE) AS is_evictions,
    e.id_process AS id_process_evictions,
    COALESCE(d.qt_aco_desconto, 0) AS qt_aco_desconto
  FROM contract_timeline AS m
  LEFT JOIN evictions_timeline AS e
    ON e.dt_reference = m.dt_reference
    AND e.id_contract = m.id_contract
  LEFT JOIN negotiations AS d
    ON d.id_contract = m.id_contract
    AND d.dt_reference = m.dt_reference
  LEFT JOIN contract_static_info AS csi
    ON csi.id_contract = m.id_contract
)
SELECT
  CAST(id_contract AS BIGINT) AS id_contract,
  dt_reference,
  reference_contract_status,
  CAST(max_delay_contaminated_contract_t1 AS BIGINT) AS max_delay_contaminated_contract_t1,
  CAST(max_delay_contaminated_contract_t2 AS BIGINT) AS max_delay_contaminated_contract_t2,
  CAST(max_delay_original_invoices_t1 AS BIGINT) AS max_delay_original_invoices_t1,
  CAST(max_delay_deal_invoices_t1 AS BIGINT) AS max_delay_deal_invoices_t1,
  CAST(n_overdue_monthlys_t1 AS BIGINT) AS n_overdue_monthlys_t1,
  CAST(has_negotiation_in_contract AS BOOLEAN) AS has_negotiation_in_contract,
  CAST(sum_monthly_overdue_days_paid_t1 AS BIGINT) AS sum_monthly_overdue_days_paid_t1,
  CAST(count_monthly_overdue_invoices_paid_t1 AS BIGINT) AS count_monthly_overdue_invoices_paid_t1,
  CAST(id_process_evictions AS BIGINT) AS id_process_evictions,
  CAST(is_evictions AS BOOLEAN) AS is_evictions,
  CAST(n_reparos_invoices AS BIGINT) AS n_reparos_invoices,
  CAST(n_invoices_in_wallet_total AS BIGINT) AS n_invoices_in_wallet,
  dt_contract_start,
  IF(n_first_invoices > 0 AND contract_guarantee <> 'BROKERAGE_ONLY', TRUE, FALSE) AS has_fpd_in_wallet_general,
  CAST(qt_aco_desconto AS BIGINT) AS qt_aco_desconto,
  CAST(n_monthly_invoices AS BIGINT) AS n_monthly_invoices,
  CAST(n_monthly_invoices_paid_ontime_t1 AS BIGINT) AS n_monthly_invoices_paid_ontime_t1,
  CAST(n_monthly_invoices_created AS BIGINT) AS n_monthly_invoices_created,
  CAST(
    CASE
      WHEN DATE_TRUNC('MONTH', dt_contract_end) = DATE_TRUNC('MONTH', dt_reference)
        AND open_wallet_overdue_t1 > 0
        AND max_open_delay_contaminated_contract_t1 > 5
      THEN TRUE
      ELSE FALSE
    END AS BOOLEAN
  ) AS has_overdue_balance_over5_t1_at_ending,
  YEAR(dt_reference) AS year,
  MONTH(dt_reference) AS month,
  DAY(dt_reference) AS day,
  NOW() AS ts_load
FROM contract_enhanced
WHERE
  dt_reference >= DATE('{load_start_date}')
  AND dt_reference <= DATE('{load_end_date}')
