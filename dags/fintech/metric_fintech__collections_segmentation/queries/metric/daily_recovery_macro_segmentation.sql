WITH contract_features_normalized AS (
    SELECT
        sk_contract,
        dt_reference,
        major_segmentation AS segmentation
    FROM
        dw_collections_segmentation.fact_contract_features_timeline
    WHERE
        MAKE_DATE(year, month, day) >= DATE_TRUNC('month', CURRENT_DATE) - INTERVAL '6' MONTHS
        AND segmentation NOT IN ('active-current', 'ended-current')
),
invoice_month_boundaries AS (
    SELECT
        DATE_TRUNC('month', iwt.dt_reference) AS month_ref,
        cfn.segmentation,
        iwt.sk_invoice,
        FIRST(cwt.dt_pipe) AS dt_pipe,
        FIRST(iwt.sk_contract) AS sk_contract,
        MIN(iwt.dt_reference) AS dt_min_view,
        MAX(iwt.dt_reference) AS dt_max_view,
        MAX(iwt.due_amount) AS due_amount,
        MAX(iwt.recovered_amount) AS recovered_amount,
        MAX(iwt.invoice_delay_t2) AS invoice_delay_t2
    FROM
        dw_collections_segmentation.fact_invoice_wallet_timeline AS iwt
    LEFT JOIN
        dw_collections_segmentation.fact_contract_wallet_timeline AS cwt
            ON cwt.dt_reference = iwt.dt_reference
            AND cwt.sk_contract = iwt.sk_contract
            AND MAKE_DATE(cwt.year, cwt.month, cwt.day) >= DATE_TRUNC('month', CURRENT_DATE) - INTERVAL '6' MONTHS
    INNER JOIN
        contract_features_normalized AS cfn
            ON cfn.dt_reference = iwt.dt_reference
            AND cfn.sk_contract = iwt.sk_contract
    WHERE
        MAKE_DATE(iwt.year, iwt.month, iwt.day) >= DATE_TRUNC('month', CURRENT_DATE) - INTERVAL '6' MONTHS
        AND cwt.wallet > 0
    GROUP BY 1, 2, 3
),
daily_accumulation AS (
    SELECT
        dd.date AS dt_reference,
        imb.segmentation AS segment,
        FIRST(imb.dt_pipe) AS dt_pipe,
        -- Contracts
        COUNT(DISTINCT
            CASE
                WHEN COALESCE(cfn.segmentation, 'Unsegmented') = imb.segmentation THEN iwt.sk_contract
                ELSE NULL
            END
        ) AS n_contracts_at_reference,
        COUNT(DISTINCT imb.sk_contract) AS n_contracts_acc,
        -- Invoices in delay-T2
        COUNT(DISTINCT
            CASE
                WHEN COALESCE(cfn.segmentation, 'Unsegmented') = imb.segmentation
                 AND iwt.invoice_delay_t2 > 0 THEN iwt.sk_invoice
                ELSE NULL
            END
        ) AS n_invoices_DT2_at_reference,
        COUNT(DISTINCT
            CASE
                WHEN dd.date <= imb.dt_max_view AND iwt.invoice_delay_t2 > 0 THEN iwt.sk_invoice
                WHEN dd.date > imb.dt_max_view AND imb.invoice_delay_t2 > 0 THEN imb.sk_invoice
                ELSE NULL
            END
        ) AS n_invoices_DT2_acc,
        COUNT(DISTINCT
            CASE
                WHEN dd.date <= imb.dt_max_view
                 AND iwt.recovered_amount > 0
                 AND iwt.invoice_delay_t2 > 0 THEN iwt.sk_invoice
                WHEN dd.date > imb.dt_max_view
                 AND imb.recovered_amount > 0
                 AND imb.invoice_delay_t2 > 0 THEN imb.sk_invoice
                ELSE NULL
            END
        ) AS recovered_invoices_DT2_acc,
        -- Due / recovered amount in delay-T2
        SUM(
            CASE
                WHEN COALESCE(cfn.segmentation, 'Unsegmented') = imb.segmentation
                 AND iwt.invoice_delay_t2 > 0 THEN ABS(imb.due_amount)
                ELSE NULL
            END
        ) AS due_amount_DT2_at_reference,
        SUM(
            CASE
                WHEN dd.date <= imb.dt_max_view AND iwt.invoice_delay_t2 > 0 THEN ABS(iwt.due_amount)
                WHEN dd.date > imb.dt_max_view AND imb.invoice_delay_t2 > 0 THEN ABS(imb.due_amount)
                ELSE NULL
            END
        ) AS due_amount_DT2_acc,
        SUM(
            CASE
                WHEN dd.date <= imb.dt_max_view AND iwt.invoice_delay_t2 > 0 THEN iwt.recovered_amount
                WHEN dd.date > imb.dt_max_view AND imb.invoice_delay_t2 > 0 THEN imb.recovered_amount
                ELSE NULL
            END
        ) AS recovered_amount_DT2_acc
    FROM
        dw_public.dim_date AS dd
    LEFT JOIN
        invoice_month_boundaries AS imb
            ON dd.date >= imb.dt_min_view
            AND dd.month_start = imb.month_ref
    LEFT JOIN
        dw_collections_segmentation.fact_invoice_wallet_timeline AS iwt
            ON iwt.dt_reference = dd.date
            AND iwt.sk_invoice = imb.sk_invoice
            AND MAKE_DATE(iwt.year, iwt.month, iwt.day) >= DATE_TRUNC('month', CURRENT_DATE) - INTERVAL '6' MONTHS
    LEFT JOIN
        contract_features_normalized AS cfn
            ON cfn.dt_reference = iwt.dt_reference
            AND cfn.sk_contract = iwt.sk_contract
    WHERE
        dd.month_start >= DATE_TRUNC('month', CURRENT_DATE) - INTERVAL '6' MONTHS
        AND dd.date <= CURRENT_DATE
    GROUP BY 1, 2
),
business_day_context AS (
    SELECT
        da.segment,
        DATE_DIFF(da.dt_reference, da.dt_pipe) AS days_to_pipe,
        COUNT(
            CASE
                WHEN da.dt_reference >= da.dt_pipe AND dd.is_brz_fintech_business_day THEN da.dt_reference
                ELSE NULL
            END
        ) OVER (
            PARTITION BY da.segment, DATE_TRUNC('month', da.dt_reference)
            ORDER BY da.dt_reference ASC
            ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
        ) - 1 AS n_business_days_since_pipe,
        da.n_contracts_at_reference,
        da.n_contracts_acc,
        da.n_invoices_DT2_at_reference,
        da.n_invoices_DT2_acc,
        da.recovered_invoices_DT2_acc,
        da.due_amount_DT2_at_reference,
        da.due_amount_DT2_acc,
        da.recovered_amount_DT2_acc,
        COALESCE(
            da.recovered_amount_DT2_acc / NULLIF(da.due_amount_DT2_acc, 0),
            0
        ) AS recovery_rate_amount_t2,
        dd.is_brz_fintech_business_day,
        dd.next_brz_fintech_business_day,
        DATE_TRUNC('month', da.dt_reference) AS dt_month_ref,
        da.dt_pipe,
        da.dt_reference
    FROM
        daily_accumulation AS da
    LEFT JOIN
        dw_public.dim_date AS dd
            ON dd.date = da.dt_reference
),
final_ordering AS (
    SELECT
        bdc.segment,
        ROW_NUMBER() OVER (
            PARTITION BY bdc.n_business_days_since_pipe, bdc.dt_month_ref, bdc.segment
            ORDER BY bdc.dt_reference DESC
        ) AS rn_business_day,
        bdc.n_business_days_since_pipe,
        bdc.days_to_pipe,
        bdc.n_contracts_at_reference,
        bdc.n_contracts_acc,
        bdc.n_invoices_DT2_at_reference,
        bdc.n_invoices_DT2_acc,
        bdc.recovered_invoices_DT2_acc,
        bdc.due_amount_DT2_at_reference,
        bdc.due_amount_DT2_acc,
        bdc.recovered_amount_DT2_acc,
        bdc.recovery_rate_amount_t2,
        bdc.is_brz_fintech_business_day,
        bdc.next_brz_fintech_business_day,
        bdc.dt_month_ref,
        bdc.dt_pipe,
        bdc.dt_reference
    FROM
        business_day_context AS bdc
)
SELECT
    segment,
    rn_business_day,
    n_business_days_since_pipe,
    days_to_pipe,
    n_contracts_at_reference,
    n_contracts_acc,
    n_invoices_DT2_at_reference,
    n_invoices_DT2_acc,
    recovered_invoices_DT2_acc,
    due_amount_DT2_at_reference,
    due_amount_DT2_acc,
    recovered_amount_DT2_acc,
    recovery_rate_amount_t2,
    is_brz_fintech_business_day,
    next_brz_fintech_business_day,
    dt_month_ref,
    dt_pipe,
    dt_reference,
    NOW() AS ts_load
FROM
    final_ordering
WHERE
    segment IS NOT NULL
