WITH
essential_features AS (
    SELECT
        id_contract,
        dt_reference,
        reference_contract_status,
        max_delay_contaminated_contract_t1,
        sum_monthly_overdue_days_paid_t1,
        count_monthly_overdue_invoices_paid_t1,
        days_since_ending,
        n_reparos_invoices,
        cpc,
        qt_acordo_quebrado,
        id_process_evictions,
        has_overdue_balance_over0_t1_at_ending,
        has_overdue_balance_over5_t1_at_ending
    FROM dw_collections_segmentation.fact_contract_wallet_timeline
),
contract_features_with_acc AS (
    SELECT
        *,
        COALESCE(MAX(n_reparos_invoices) OVER (
            PARTITION BY id_contract
            ORDER BY dt_reference
            ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
        ), 0) AS acc_max_n_repairs,
        COALESCE(SUM(cpc) OVER (
            PARTITION BY id_contract
            ORDER BY dt_reference
            ROWS BETWEEN 90 PRECEDING AND CURRENT ROW
        ), 0) AS acc_cpc_l90,
        COALESCE(SUM(qt_acordo_quebrado) OVER (
            PARTITION BY id_contract
            ORDER BY dt_reference
            ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
        ), 0) AS acc_broken_multiple_deals_lifetime,
        SIZE(COLLECT_SET(id_process_evictions) OVER (
            PARTITION BY id_contract
            ORDER BY dt_reference
            ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
        )) AS n_evictions_processes_lifetime,
        COALESCE(SUM(sum_monthly_overdue_days_paid_t1) OVER (
            PARTITION BY id_contract
            ORDER BY dt_reference
            ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
        ), 0) AS acc_sum_monthly_overdue_days_paid_t1,
        COALESCE(SUM(count_monthly_overdue_invoices_paid_t1) OVER (
            PARTITION BY id_contract
            ORDER BY dt_reference
            ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
        ), 0) AS acc_count_monthly_overdue_invoices_paid_t1,
        COALESCE(MAX(CAST(has_overdue_balance_over0_t1_at_ending AS INT)) OVER (
            PARTITION BY id_contract
            ORDER BY dt_reference
            ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
        ), 0) AS has_overdue_balance_over0_t1_at_ending_ffill,
        COALESCE(MAX(CAST(has_overdue_balance_over5_t1_at_ending AS INT)) OVER (
            PARTITION BY id_contract
            ORDER BY dt_reference
            ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
        ), 0) AS has_overdue_balance_over5_t1_at_ending_ffill

    FROM essential_features
)
SELECT
    id_contract,
    reference_contract_status,
    max_delay_contaminated_contract_t1,
    sum_monthly_overdue_days_paid_t1,
    count_monthly_overdue_invoices_paid_t1,
    days_since_ending,
    acc_max_n_repairs,
    acc_cpc_l90,
    acc_broken_multiple_deals_lifetime,
    n_evictions_processes_lifetime,
    has_overdue_balance_over0_t1_at_ending_ffill,
    has_overdue_balance_over5_t1_at_ending_ffill,
    CASE
        WHEN acc_count_monthly_overdue_invoices_paid_t1 = 0 THEN 0
        ELSE acc_sum_monthly_overdue_days_paid_t1 / acc_count_monthly_overdue_invoices_paid_t1
    END AS avg_days_overdue_invoices_paid_t1,
    dt_reference,
    NOW() AS ts_load
FROM contract_features_with_acc
