WITH chargehub_allocation AS (
  SELECT DISTINCT
    dt_last_appearance,
    segment_name,
    audience_name,
    id_contract,
    id_audience,
    id_segment,
    ts_entered_segment,
    ts_entered_audience
  FROM datalake_debt_recovery.segmentation_distribution
  WHERE is_active
  QUALIFY ROW_NUMBER() OVER(PARTITION BY id_contract, dt_last_appearance ORDER BY ts_entered_segment DESC, ts_entered_audience DESC) = 1
),

month_view AS (
  SELECT
    DATE_TRUNC('month', m.dt_reference) AS month_ref,
    COALESCE(ch.audience_name, 'Unsegmented') AS segmentation,
    m.sk_invoice,
    FIRST(t.dt_pipe) AS dt_pipe,
    FIRST(m.sk_contract) AS sk_contract,
    FIRST(ch.segment_name) AS segment_name,
    MIN(m.dt_reference) AS dt_min_view,
    MAX(m.dt_reference) AS dt_max_view,
    MAX(m.due_amount) AS due_amount,
    MAX(m.recovered_amount) AS recovered_amount,
    MAX(CASE WHEN m.recovery_channel IN ('Negotiation - SSN', 'Paid in App','Paid outside App', 'Negotiation - Matthew', 'Negotiation of Installment - SSN') THEN m.recovered_amount ELSE NULL END) AS recovered_amount_digital,
    MAX(CASE WHEN m.recovery_channel IN ('Negotiation - Advisory','Paid Installment in App', 'Paid Installment outside App') THEN m.recovered_amount ELSE NULL END) AS recovered_amount_bpo,
    MAX(CASE WHEN m.recovery_channel IN ('Negotiation - Serasa') THEN m.recovered_amount ELSE NULL END) AS recovered_amount_dep,
    MAX(m.invoice_delay_t2) AS invoice_delay_t2,
    MAX(m.invoice_delay_t1) AS invoice_delay_t1,
    MIN(m.contract_status) AS min_reference_contract_status,
    MAX(m.contract_status) AS max_reference_contract_status
  FROM dw_collections_segmentation.fact_invoice_wallet_timeline AS m
  LEFT JOIN dw_collections_segmentation.fact_contract_features_timeline AS f ON f.dt_reference = m.dt_reference AND f.sk_contract = m.sk_contract
  LEFT JOIN dw_collections_segmentation.fact_contract_wallet_timeline AS t ON t.dt_reference = m.dt_reference AND t.sk_contract = m.sk_contract
  LEFT JOIN chargehub_allocation AS ch ON ch.dt_last_appearance = m.dt_reference AND ch.id_contract = m.sk_contract
  WHERE ch.dt_last_appearance IS NOT NULL
  GROUP BY 1,2,3
),

full_month_view AS (
  SELECT
    dd.date AS dt_reference,
    m.segmentation AS segment,
    FIRST(m.dt_pipe) AS dt_pipe,
    FIRST(ch.segment_name) AS segment_name,
    COUNT(DISTINCT CASE
        WHEN COALESCE(ch.audience_name, 'Unsegmented') = m.segmentation THEN f2.sk_contract
        ELSE NULL
    END) AS n_contracts_at_reference,
    COUNT(DISTINCT m.sk_contract) AS n_contracts_acc,
    COUNT(DISTINCT CASE
        WHEN COALESCE(ch.audience_name, 'Unsegmented') = m.segmentation THEN f.sk_invoice
        ELSE NULL
    END) AS n_invoices_at_reference,
    COUNT(DISTINCT m.sk_invoice) AS n_invoices_acc,
    SUM(ABS(m.due_amount)) AS total_due_amount_acc,
    SUM(CASE
        WHEN COALESCE(ch.audience_name, 'Unsegmented') = m.segmentation THEN ABS(m.due_amount)
        ELSE NULL
    END) AS total_due_amount_at_reference,
    SUM(CASE
        WHEN COALESCE(ch.audience_name, 'Unsegmented') = m.segmentation THEN f.recovered_amount
        ELSE NULL
    END) AS recovered_amount_at_reference,
    COUNT(DISTINCT CASE WHEN COALESCE(ch.audience_name, 'Unsegmented') = m.segmentation AND f.recovered_amount > 0 THEN f.sk_invoice ELSE NULL END) AS recovered_invoices_at_reference,
    COUNT(DISTINCT CASE
        WHEN dd.date <= m.dt_max_view AND f.recovered_amount > 0 THEN f.sk_invoice
        WHEN dd.date > m.dt_max_view AND m.recovered_amount > 0 THEN m.sk_invoice
        ELSE NULL END
        ) AS recovered_invoices_acc,
    COUNT(DISTINCT CASE WHEN COALESCE(ch.audience_name, 'Unsegmented') = m.segmentation AND f.recovered_amount > 0 THEN f.sk_contract ELSE NULL END) AS recovered_contracts_at_reference,
    COUNT(DISTINCT CASE
            WHEN dd.date <= m.dt_max_view AND f.recovered_amount > 0 THEN f.sk_contract
            WHEN dd.date > m.dt_max_view AND m.recovered_amount > 0 THEN m.sk_contract
            ELSE NULL END) AS recovered_contracts_acc,
    COUNT(DISTINCT CASE
        WHEN COALESCE(ch.audience_name, 'Unsegmented') = m.segmentation
            AND f.invoice_delay_t1 > 0 THEN f.sk_invoice
            ELSE NULL
    END) AS n_invoices_DT1_at_reference,
    COUNT(DISTINCT CASE
        WHEN dd.date <= m.dt_max_view AND f.invoice_delay_t1 > 0 THEN f.sk_invoice
        WHEN dd.date > m.dt_max_view AND m.invoice_delay_t1 > 0 THEN m.sk_invoice
        ELSE NULL END) AS n_invoices_DT1_acc,
    COUNT(DISTINCT CASE
        WHEN COALESCE(ch.audience_name, 'Unsegmented') = m.segmentation
            AND f.invoice_delay_t1 <= 0 THEN f.sk_invoice
            ELSE NULL
    END) AS n_invoices_OT1_at_reference,
    COUNT(DISTINCT CASE
        WHEN dd.date <= m.dt_max_view AND f.invoice_delay_t1 <= 0 THEN f.sk_invoice
        WHEN dd.date > m.dt_max_view AND m.invoice_delay_t1 <= 0 THEN m.sk_invoice
        ELSE NULL
    END) AS n_invoices_OT1_acc,
    SUM(CASE
        WHEN COALESCE(ch.audience_name, 'Unsegmented') = m.segmentation
        AND f.invoice_delay_t1 > 0 THEN ABS(m.due_amount)
        ELSE NULL
    END) AS due_amount_DT1_at_reference,
    SUM(CASE
        WHEN COALESCE(ch.audience_name, 'Unsegmented') = m.segmentation
        AND f.invoice_delay_t1 <= 0 THEN ABS(m.due_amount)
        ELSE NULL
    END) AS due_amount_OT1_at_reference,
    SUM(CASE
        WHEN COALESCE(ch.audience_name, 'Unsegmented') = m.segmentation
        AND f.invoice_delay_t1 > 0 THEN f.recovered_amount
        ELSE NULL
    END) AS recovered_amount_DT1_at_reference,
    SUM(CASE
        WHEN COALESCE(ch.audience_name, 'Unsegmented') = m.segmentation
        AND f.invoice_delay_t1 <= 0 THEN f.recovered_amount
        ELSE NULL
    END) AS recovered_amount_OT1_at_reference,
    SUM(CASE
        WHEN dd.date <= m.dt_max_view
            AND f.invoice_delay_t1 > 0 THEN f.recovered_amount
        WHEN dd.date > m.dt_max_view
            AND m.invoice_delay_t1 > 0 THEN m.recovered_amount
        ELSE NULL
    END) AS recovered_amount_DT1_acc,
    SUM(CASE
        WHEN dd.date <= m.dt_max_view
        AND f.invoice_delay_t1 <= 0 THEN f.recovered_amount
        WHEN dd.date > m.dt_max_view
            AND m.invoice_delay_t1 <= 0 THEN m.recovered_amount
        ELSE NULL
    END) AS recovered_amount_OT1_acc,
    COUNT(DISTINCT CASE
        WHEN COALESCE(ch.audience_name, 'Unsegmented') = m.segmentation
        AND f.recovered_amount > 0 AND f.invoice_delay_t1 > 0 THEN f.sk_invoice
        ELSE NULL
    END) AS recovered_invoices_DT1_at_reference,
    COUNT(DISTINCT CASE
        WHEN COALESCE(ch.audience_name, 'Unsegmented') = m.segmentation
        AND f.recovered_amount > 0 AND f.invoice_delay_t1 <= 0 THEN f.sk_invoice
        ELSE NULL
    END) AS recovered_invoices_OT1_at_reference,
    COUNT(DISTINCT CASE
        WHEN dd.date <= m.dt_max_view
            AND f.recovered_amount > 0
            AND f.invoice_delay_t1 > 0 THEN f.sk_invoice
        WHEN dd.date > m.dt_max_view
            AND m.recovered_amount > 0
            AND m.invoice_delay_t1 > 0 THEN m.sk_invoice
        ELSE NULL
    END) AS recovered_invoices_DT1_acc,
    COUNT(DISTINCT CASE
        WHEN dd.date <= m.dt_max_view
            AND f.recovered_amount > 0
            AND f.invoice_delay_t1 <= 0 THEN f.sk_invoice
        WHEN dd.date > m.dt_max_view
            AND m.recovered_amount > 0
            AND m.invoice_delay_t1 <= 0 THEN m.sk_invoice
        ELSE NULL
    END) AS recovered_invoices_OT1_acc,
    COUNT(DISTINCT CASE
        WHEN COALESCE(ch.audience_name, 'Unsegmented') = m.segmentation
            AND f.invoice_delay_t2 > 0 THEN f.sk_invoice
        ELSE NULL
    END) AS n_invoices_DT2_at_reference,
    COUNT(DISTINCT
        CASE WHEN dd.date <= m.dt_max_view AND f.invoice_delay_t2 > 0 THEN f.sk_invoice
        WHEN dd.date > m.dt_max_view
            AND m.invoice_delay_t2 > 0 THEN m.sk_invoice
        ELSE NULL
    END) AS n_invoices_DT2_acc,
    COUNT(DISTINCT CASE
        WHEN COALESCE(ch.audience_name, 'Unsegmented') = m.segmentation
            AND f.invoice_delay_t2 <= 0 THEN f.sk_invoice
        ELSE NULL
    END) AS n_invoices_OT2_at_reference,
    COUNT(DISTINCT CASE
        WHEN dd.date <= m.dt_max_view
            AND f.invoice_delay_t2 <= 0 THEN f.sk_invoice
        WHEN dd.date > m.dt_max_view
            AND m.invoice_delay_t2 <= 0 THEN m.sk_invoice
        ELSE NULL
    END) AS n_invoices_OT2_acc,
    SUM(CASE
        WHEN COALESCE(ch.audience_name, 'Unsegmented') = m.segmentation
        AND f.invoice_delay_t2 > 0 THEN ABS(m.due_amount)
        ELSE NULL END) AS due_amount_DT2_at_reference,
    SUM(CASE
        WHEN COALESCE(ch.audience_name, 'Unsegmented') = m.segmentation
        AND f.invoice_delay_t2 <= 0 THEN ABS(m.due_amount)
        ELSE NULL END) AS due_amount_OT2_at_reference,
    SUM(CASE
        WHEN dd.date <= m.dt_max_view
        AND f.invoice_delay_t2 <= 0 THEN ABS(m.due_amount)
        WHEN dd.date > m.dt_max_view
        AND m.invoice_delay_t2 <= 0 THEN ABS(m.due_amount)
        ELSE NULL END) AS due_amount_OT2_acc,
    SUM(CASE
        WHEN dd.date <= m.dt_max_view
        AND f.invoice_delay_t2 > 0 THEN ABS(m.due_amount)
        WHEN dd.date > m.dt_max_view
        AND m.invoice_delay_t2 > 0 THEN ABS(m.due_amount)
        ELSE NULL END) AS due_amount_DT2_acc,
    SUM(CASE
        WHEN dd.date <= m.dt_max_view
            AND f.invoice_delay_t2 > 0 THEN f.recovered_amount
        WHEN dd.date > m.dt_max_view
            AND m.recovered_amount > 0 THEN m.recovered_amount
        ELSE NULL END) AS recovered_amount_DT2_acc,
    SUM(CASE
        WHEN dd.date <= m.dt_max_view
            AND f.invoice_delay_t2 <= 0 THEN f.recovered_amount
        WHEN dd.date > m.dt_max_view
            AND m.recovered_amount > 0 THEN m.recovered_amount
        ELSE NULL
    END) AS recovered_amount_OT2_acc,
    COUNT(DISTINCT CASE
        WHEN COALESCE(ch.audience_name, 'Unsegmented') = m.segmentation
            AND f.recovered_amount > 0
            AND f.invoice_delay_t2 > 0 THEN f.sk_invoice
        ELSE NULL END) AS recovered_invoices_DT2_at_reference,
    COUNT(DISTINCT CASE
        WHEN COALESCE(ch.audience_name, 'Unsegmented') = m.segmentation
            AND f.recovered_amount > 0
            AND f.invoice_delay_t2 <= 0 THEN f.sk_invoice
        ELSE NULL END) AS recovered_invoices_OT2_at_reference,
    COUNT(DISTINCT CASE
        WHEN dd.date <= m.dt_max_view
            AND f.recovered_amount > 0
            AND f.invoice_delay_t2 > 0 THEN f.sk_invoice
        WHEN dd.date > m.dt_max_view
            AND m.recovered_amount > 0
            AND m.invoice_delay_t2 > 0 THEN m.sk_invoice
        ELSE NULL END) AS recovered_invoices_DT2_acc,
    COUNT(DISTINCT CASE
        WHEN dd.date <= m.dt_max_view
            AND f.recovered_amount > 0
            AND f.invoice_delay_t2 > 0 THEN f.sk_contract
        WHEN dd.date > m.dt_max_view
            AND m.recovered_amount > 0
            AND m.invoice_delay_t2 > 0 THEN m.sk_contract
        ELSE NULL
    END) AS recovered_contracts_DT2_acc,
    COUNT(DISTINCT CASE
        WHEN dd.date <= m.dt_max_view
                AND f.recovered_amount > 0
                AND f.invoice_delay_t2 <= 0 THEN f.sk_contract
        WHEN dd.date > m.dt_max_view
            AND m.recovered_amount > 0
            AND m.invoice_delay_t2 <= 0 THEN m.sk_contract
        ELSE NULL
    END) AS recovered_contracts_OT2_acc,
    SUM(CASE WHEN COALESCE(ch.audience_name, 'Unsegmented') = m.segmentation AND f.invoice_delay_t2 > 0 AND f.recovery_channel IN ('Negotiation - SSN', 'Paid in App','Paid outside App', 'Negotiation - Matthew', 'Negotiation of Installment - SSN') THEN f.recovered_amount ELSE NULL END) AS recovered_amount_DT2_Digital_at_reference,
    SUM(CASE
        WHEN COALESCE(ch.audience_name, 'Unsegmented') = m.segmentation
            AND f.invoice_delay_t1 > 0
            AND f.recovery_channel IN ('Negotiation - SSN', 'Paid in App','Paid outside App', 'Negotiation - Matthew', 'Negotiation of Installment - SSN') THEN f.recovered_amount
        ELSE NULL
    END) AS recovered_amount_DT1_Digital_at_reference,
    SUM(CASE
        WHEN COALESCE(ch.audience_name, 'Unsegmented') = m.segmentation
            AND f.invoice_delay_t2 <= 0
            AND f.recovery_channel IN ('Negotiation - SSN', 'Paid in App','Paid outside App', 'Negotiation - Matthew', 'Negotiation of Installment - SSN') THEN f.recovered_amount
        ELSE NULL
    END) AS recovered_amount_OT2_Digital_at_reference,
    SUM(CASE
        WHEN COALESCE(ch.audience_name, 'Unsegmented') = m.segmentation
            AND f.invoice_delay_t1 <= 0
            AND f.recovery_channel IN ('Negotiation - SSN', 'Paid in App','Paid outside App', 'Negotiation - Matthew', 'Negotiation of Installment - SSN') THEN f.recovered_amount
        ELSE NULL
    END) AS recovered_amount_OT1_Digital_at_reference,
    SUM(CASE
            WHEN dd.date < m.dt_max_view AND f.invoice_delay_t2 > 0 THEN 0
            WHEN dd.date >= m.dt_max_view AND m.invoice_delay_t2 > 0 THEN m.recovered_amount_digital
            ELSE NULL
    END) AS recovered_amount_DT2_Digital_acc,
    SUM(CASE
            WHEN dd.date < m.dt_max_view AND f.invoice_delay_t2 <= 0 THEN 0
            WHEN dd.date >= m.dt_max_view AND m.invoice_delay_t2 <= 0 THEN m.recovered_amount_digital
            ELSE NULL
    END) AS recovered_amount_OT2_Digital_acc,
    SUM(CASE
            WHEN dd.date < m.dt_max_view AND f.invoice_delay_t1 > 0 THEN 0
            WHEN dd.date >= m.dt_max_view AND m.invoice_delay_t1 > 0 THEN m.recovered_amount_digital
            ELSE NULL
    END) AS recovered_amount_DT1_Digital_acc,
    SUM(CASE
        WHEN dd.date < m.dt_max_view AND f.invoice_delay_t1 <= 0 THEN 0
        WHEN dd.date >= m.dt_max_view AND m.invoice_delay_t1 <= 0 THEN m.recovered_amount_digital
        ELSE NULL
    END) AS recovered_amount_OT1_Digital_acc,
    SUM(CASE
        WHEN COALESCE(ch.audience_name, 'Unsegmented') = m.segmentation
            AND f.recovery_channel IN ('Negotiation - SSN', 'Paid in App','Paid outside App', 'Negotiation - Matthew', 'Negotiation of Installment - SSN') THEN f.recovered_amount
        ELSE NULL
    END) AS recovered_amount_Digital_at_reference,
    SUM(CASE
        WHEN dd.date < m.dt_max_view THEN 0
        WHEN dd.date >= m.dt_max_view THEN m.recovered_amount_digital
        ELSE NULL
    END) AS recovered_amount_acc
  FROM dw_public.dim_date AS dd
  LEFT JOIN month_view AS m
    ON dd.date >= m.dt_min_view
    AND dd.month_start = m.month_ref
  LEFT JOIN dw_collections_segmentation.fact_invoice_wallet_timeline AS f
    ON dd.date = f.dt_reference
    AND f.sk_invoice = m.sk_invoice
  LEFT JOIN dw_collections_segmentation.fact_contract_features_timeline AS f2
    ON f2.dt_reference = f.dt_reference
    AND f2.sk_contract = f.sk_contract
  LEFT JOIN chargehub_allocation AS ch ON ch.dt_last_appearance = f.dt_reference AND ch.id_contract = f.sk_contract
WHERE
    dd.month_start >= DATE('2025-10-01')
    AND dd.date <= CURRENT_DATE
GROUP BY 1,2
)
SELECT
    segment,
    n_contracts_at_reference,
    n_contracts_acc,
    n_invoices_at_reference,
    n_invoices_acc,
    total_due_amount_acc,
    total_due_amount_at_reference,
    recovered_amount_at_reference,
    recovered_amount_acc,
    recovered_invoices_at_reference,
    recovered_invoices_acc,
    recovered_contracts_at_reference,
    recovered_contracts_acc,
    n_invoices_DT1_at_reference,
    n_invoices_DT1_acc,
    n_invoices_OT1_at_reference,
    n_invoices_OT1_acc,
    due_amount_DT1_at_reference,
    due_amount_OT1_at_reference,
    recovered_amount_DT1_at_reference,
    recovered_amount_OT1_at_reference,
    recovered_amount_DT1_acc,
    recovered_amount_OT1_acc,
    recovered_invoices_DT1_at_reference,
    recovered_invoices_OT1_at_reference,
    recovered_invoices_DT1_acc,
    recovered_invoices_OT1_acc,
    n_invoices_DT2_at_reference,
    n_invoices_DT2_acc,
    n_invoices_OT2_at_reference,
    n_invoices_OT2_acc,
    due_amount_DT2_at_reference,
    due_amount_OT2_at_reference,
    due_amount_OT2_acc,
    due_amount_DT2_acc,
    recovered_amount_DT2_acc,
    recovered_amount_OT2_acc,
    recovered_invoices_DT2_at_reference,
    recovered_invoices_OT2_at_reference,
    recovered_invoices_DT2_acc,
    recovered_contracts_DT2_acc,
    recovered_contracts_OT2_acc,
    recovered_amount_DT2_Digital_at_reference,
    recovered_amount_DT1_Digital_at_reference,
    recovered_amount_OT2_Digital_at_reference,
    recovered_amount_OT1_Digital_at_reference,
    recovered_amount_DT2_Digital_acc,
    recovered_amount_OT2_Digital_acc,
    recovered_amount_DT1_Digital_acc,
    recovered_amount_OT1_Digital_acc,
    recovered_amount_Digital_at_reference,
    recovered_amount_acc,
    DATE_DIFF(dt_reference, dt_pipe) AS days_to_pipe,
    dt_reference,
    DATE_TRUNC('month', dt_reference) AS dt_month_ref,
    segment_name,
    dt_pipe,
    NOW() AS ts_load
FROM full_month_view
WHERE segment IS NOT NULL
