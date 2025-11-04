WITH
essential_features AS (
    SELECT
        sk_contract,
        dt_reference,
        reference_contract_status,
        max_delay_contaminated_contract_t1,
        max_delay_contaminated_contract_t2,
        max_delay_original_invoices_t1,
        max_delay_deal_invoices_t1,
        n_overdue_monthlys_t1,
        n_overdue_others_t1,
        has_negotiation_in_contract,
        sum_monthly_overdue_days_paid_t1,
        count_monthly_overdue_invoices_paid_t1,
        days_since_ending,
        days_since_contract_start,
        n_reparos_invoices,
        cpc,
        qt_acordo_quebrado,
        id_process_evictions,
        has_overdue_balance_over0_t1_at_ending,
        has_overdue_balance_over5_t1_at_ending,
        has_overdue_balance_over0_t2_at_ending,
        has_overdue_balance_over5_t2_at_ending,
        has_overdue_balance_over0_t3_at_ending,
        has_overdue_balance_over5_t3_at_ending,
        is_evictions,
        n_anchor_invoices_not_negativable,
        array_open_invoices,
        array_paid_invoices,
        array_negotiated_invoices,
        monthly_income,
        n_monthly_invoices,
        n_invoices_paid,
        n_invoices_paid_ontime_t2,
        n_overdue_invoices_paid_t2,
        n_invoices_paid_ontime_t1,
        n_overdue_invoices_paid_t1,
        n_monthly_invoices_paid_ontime_t2,
        n_monthly_invoices_paid_ontime_t1,
        n_monthly_overdue_invoices_paid_t2,
        n_monthly_overdue_invoices_paid_t1,
        n_monthly_invoices_created,
        n_rental_core_invoices,
        n_acordo_invoices,
        n_reparos_invoices,
        days_since_contract_start,
        n_first_invoices_open,
        has_fpd_in_wallet,
        qt_acordo_quebrado,
        qt_promessa_quebrada_fp,
        qt_aco_desconto,
        n_invoices_in_wallet,
        wallet_overdue_t2,
        debts_in_income_share_t1,
        debts_in_income_share_t2,
        overdue_recovered_amount_t2,
        dt_contract_start
    FROM dw_collections_segmentation.fact_contract_wallet_timeline
),
contract_features_with_acc AS (
    SELECT
        *,
        COALESCE(MAX(n_reparos_invoices) OVER (
            PARTITION BY sk_contract
            ORDER BY dt_reference
            ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
        ), 0) AS acc_max_n_repairs,
        COALESCE(SUM(cpc) OVER (
            PARTITION BY sk_contract
            ORDER BY dt_reference
            ROWS BETWEEN 90 PRECEDING AND CURRENT ROW
        ), 0) AS acc_cpc_l90,
        COALESCE(SUM(qt_acordo_quebrado) OVER (
            PARTITION BY sk_contract
            ORDER BY dt_reference
            ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
        ), 0) AS acc_broken_multiple_deals_lifetime,
        COALESCE(SUM(qt_promessa_quebrada_fp) OVER (
            PARTITION BY sk_contract
            ORDER BY dt_reference
            ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
        ), 0) AS acc_broken_promessas_lifetime,
        COALESCE(SUM(qt_aco_desconto) OVER (
            PARTITION BY sk_contract
            ORDER BY dt_reference
            ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
                ), 0) AS acc_deals_principal_discount_lifetime,
        (12*(YEAR(dt_reference) - YEAR(dt_contract_start)) +
         (MONTH(dt_reference) - MONTH(dt_contract_start))) AS mob_months,
        SIZE(COLLECT_SET(id_process_evictions) OVER (
            PARTITION BY sk_contract
            ORDER BY dt_reference
            ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
        )) AS n_evictions_processes_lifetime,
        COALESCE(SUM(sum_monthly_overdue_days_paid_t1) OVER (
            PARTITION BY sk_contract
            ORDER BY dt_reference
            ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
        ), 0) AS acc_sum_monthly_overdue_days_paid_t1,
        COALESCE(SUM(count_monthly_overdue_invoices_paid_t1) OVER (
            PARTITION BY sk_contract
            ORDER BY dt_reference
            ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
        ), 0) AS acc_count_monthly_overdue_invoices_paid_t1,
        CAST(COALESCE(MAX(CAST(has_overdue_balance_over0_t1_at_ending AS INT)) OVER (
            PARTITION BY sk_contract
            ORDER BY dt_reference
            ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
        ), 0) AS INT) AS has_overdue_balance_over0_t1_at_ending_ffill,
        CAST(COALESCE(MAX(CAST(has_overdue_balance_over5_t1_at_ending AS INT)) OVER (
            PARTITION BY sk_contract
            ORDER BY dt_reference
            ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
        ), 0) AS INT) AS has_overdue_balance_over5_t1_at_ending_ffill,
        COALESCE(SUM(n_monthly_invoices) OVER (
            PARTITION BY sk_contract
            ORDER BY dt_reference
            ROWS BETWEEN 365 PRECEDING AND CURRENT ROW
        ), 0) AS acc_n_monthly_invoices_l12m,
        COALESCE(SUM(n_monthly_invoices_paid_ontime_t2) OVER (
            PARTITION BY sk_contract
            ORDER BY dt_reference
            ROWS BETWEEN 365 PRECEDING AND CURRENT ROW
        ), 0) AS acc_n_monthly_invoices_paid_ontime_t2_l12m,
        COALESCE(SUM(n_monthly_invoices_paid_ontime_t1) OVER (
            PARTITION BY sk_contract
            ORDER BY dt_reference
            ROWS BETWEEN 365 PRECEDING AND CURRENT ROW
        ), 0) AS acc_n_monthly_invoices_paid_ontime_t1_l12m,
        COALESCE(SUM(n_monthly_overdue_invoices_paid_t2) OVER (
            PARTITION BY sk_contract
            ORDER BY dt_reference
            ROWS BETWEEN 365 PRECEDING AND CURRENT ROW
        ), 0) AS acc_n_monthly_overdue_invoices_paid_t2_l12m,
        COALESCE(SUM(n_monthly_overdue_invoices_paid_t1) OVER (
            PARTITION BY sk_contract
            ORDER BY dt_reference
            ROWS BETWEEN 365 PRECEDING AND CURRENT ROW
        ), 0) AS acc_n_monthly_overdue_invoices_paid_t1_l12m,
        COALESCE(SUM(n_invoices_paid_ontime_t2) OVER (
            PARTITION BY sk_contract
            ORDER BY dt_reference
            ROWS BETWEEN 365 PRECEDING AND CURRENT ROW
        ), 0) AS acc_n_invoices_paid_ontime_t2_l12m,
        COALESCE(SUM(n_invoices_paid_ontime_t1) OVER (
            PARTITION BY sk_contract
            ORDER BY dt_reference
            ROWS BETWEEN 365 PRECEDING AND CURRENT ROW
        ), 0) AS acc_n_invoices_paid_ontime_t1_l12m,
        COALESCE(SUM(n_overdue_invoices_paid_t2) OVER (
            PARTITION BY sk_contract
            ORDER BY dt_reference
            ROWS BETWEEN 365 PRECEDING AND CURRENT ROW
        ), 0) AS acc_n_overdue_invoices_paid_t2_l12m,
        COALESCE(SUM(n_overdue_invoices_paid_t1) OVER (
            PARTITION BY sk_contract
            ORDER BY dt_reference
            ROWS BETWEEN 365 PRECEDING AND CURRENT ROW
        ), 0) AS acc_n_overdue_invoices_paid_t1_l12m,
        COALESCE(SUM(n_monthly_invoices_created) OVER (
            PARTITION BY sk_contract
            ORDER BY dt_reference
            ROWS BETWEEN 365 PRECEDING AND CURRENT ROW
        ), 0) AS acc_count_monthly_invoices_created,
        COALESCE(SUM(n_monthly_invoices_paid_ontime_t1) OVER (
            PARTITION BY sk_contract
            ORDER BY dt_reference
            ROWS BETWEEN 365 PRECEDING AND CURRENT ROW
        ), 0) AS acc_count_monthly_invoices_paid_ontime_t1,
        COALESCE(SUM(CASE WHEN max_delay_contaminated_contract_t2 > 0 THEN 1 ELSE 0 END) OVER (
            PARTITION BY sk_contract
            ORDER BY dt_reference
            ROWS BETWEEN 180 PRECEDING AND CURRENT ROW
        ), 0) AS n_days_over1_t2_l180

    FROM essential_features
),
calculate_avg_days_overdue_invoice_paid_t1 AS (
    SELECT
        *,
        CASE
            WHEN acc_count_monthly_overdue_invoices_paid_t1 = 0 THEN 0
            ELSE acc_sum_monthly_overdue_days_paid_t1 / acc_count_monthly_overdue_invoices_paid_t1
        END AS avg_days_overdue_invoices_paid_t1,
        CASE
            WHEN acc_count_monthly_invoices_created = 0 THEN 0
            ELSE acc_count_monthly_invoices_paid_ontime_t1 / acc_count_monthly_invoices_created
        END AS share_monthly_paid_ontime_t1
    FROM contract_features_with_acc

),
calculate_monthly_payment_ratios AS (
    SELECT
        *,
        CASE
            WHEN acc_n_monthly_invoices_l12m = 0 THEN NULL
            ELSE ROUND(acc_n_monthly_invoices_paid_ontime_t2_l12m / acc_n_monthly_invoices_l12m, 4)
        END AS pct_monthly_paid_ontime_t2_l12m,
        CASE
            WHEN acc_n_monthly_invoices_l12m = 0 THEN NULL
            ELSE ROUND(acc_n_monthly_invoices_paid_ontime_t1_l12m / acc_n_monthly_invoices_l12m, 4)
        END AS pct_monthly_paid_ontime_t1_l12m,
        CASE
            WHEN (acc_n_invoices_paid_ontime_t2_l12m + acc_n_overdue_invoices_paid_t2_l12m) = 0 THEN NULL
            ELSE ROUND(acc_n_invoices_paid_ontime_t2_l12m / (acc_n_invoices_paid_ontime_t2_l12m + acc_n_overdue_invoices_paid_t2_l12m), 4)
        END AS pct_invoices_paid_ontime_t2_l12m,
        CASE
            WHEN (acc_n_invoices_paid_ontime_t1_l12m + acc_n_overdue_invoices_paid_t1_l12m) = 0 THEN NULL
            ELSE ROUND(acc_n_invoices_paid_ontime_t1_l12m / (acc_n_invoices_paid_ontime_t1_l12m + acc_n_overdue_invoices_paid_t1_l12m), 4)
        END AS pct_invoices_paid_ontime_t1_l12m
    FROM calculate_avg_days_overdue_invoice_paid_t1
),
prob_payment_calculation AS (
    SELECT
        f.*,
        CASE
            WHEN f.max_delay_contaminated_contract_t1 <= 0 THEN 'a. Current'
            WHEN f.max_delay_contaminated_contract_t1 <= 30 THEN 'b. 1-30'
            WHEN f.max_delay_contaminated_contract_t1 <= 60 THEN 'c. 31-60'
            WHEN f.max_delay_contaminated_contract_t1 <= 90 THEN 'd. 61-90'
            WHEN f.max_delay_contaminated_contract_t1 <= 180 THEN 'g. 91-180'
            ELSE 'h. acima de 180'
        END AS t1_delay_bucket,
        CASE
            WHEN f.max_delay_contaminated_contract_t2 <= 0 THEN 'a. Current'
            WHEN f.max_delay_contaminated_contract_t2 <= 30 THEN 'b. 1-30'
            WHEN f.max_delay_contaminated_contract_t2 <= 60 THEN 'c. 31-60'
            WHEN f.max_delay_contaminated_contract_t2 <= 90 THEN 'd. 61-90'
            WHEN f.max_delay_contaminated_contract_t2 <= 180 THEN 'g. 91-180'
            ELSE 'h. acima de 180'
        END AS t2_delay_bucket,
        CASE
            WHEN f.max_delay_contaminated_contract_t2 <= 0
                AND f.reference_contract_status = 'Ativo' THEN 'ACTIVE - CURRENT'
            WHEN f.max_delay_contaminated_contract_t2 <= 0
                AND f.reference_contract_status = 'Finalizado' THEN 'ENDED - CURRENT'
            WHEN f.days_since_contract_start <= 35 THEN 'FPD'
            WHEN f.max_delay_contaminated_contract_t2 > 0
                AND f.max_delay_original_invoices_t1 <= 0
                AND f.max_delay_deal_invoices_t1 <= 0 THEN 'CORLEONES'
            WHEN COALESCE(f.is_evictions, FALSE) = TRUE THEN 'EVEX'
            WHEN f.reference_contract_status = 'Finalizado'
                AND f.max_delay_contaminated_contract_t2 >= 90 THEN 'TITANIC ENDED'
            WHEN f.max_delay_contaminated_contract_t2 <= 15
                AND NOT f.has_negotiation_in_contract
                AND f.n_anchor_invoices_not_negativable = 0
                AND f.reference_contract_status = 'Ativo' THEN 'NEW DEFAULTER - ACTIVE'
            WHEN f.max_delay_contaminated_contract_t2 <= 15
                AND NOT f.has_negotiation_in_contract
                AND f.n_anchor_invoices_not_negativable = 0
                AND f.reference_contract_status = 'Finalizado' THEN 'NEW DEFAULTER - ENDED'
            WHEN f.max_delay_contaminated_contract_t2 <= 15
                AND NOT f.has_negotiation_in_contract
                AND f.n_anchor_invoices_not_negativable > 0 THEN 'NEW DEFAULTER - NEFN'
            WHEN f.reference_contract_status = 'Ativo'
                AND f.max_delay_contaminated_contract_t2 > 15
                AND f.n_anchor_invoices_not_negativable > 0 THEN 'OVER 15 - ACTIVE - NEFN'
            WHEN f.reference_contract_status = 'Ativo'
                AND f.max_delay_contaminated_contract_t2 > 15
                AND NOT f.has_negotiation_in_contract
                AND (f.n_overdue_monthlys_t1 <= 1
                    OR (f.n_overdue_monthlys_t1 = 0
                        AND f.n_overdue_others_t1 > 1)) THEN 'PURGATORIUM'
            WHEN f.reference_contract_status = 'Ativo'
                AND f.has_negotiation_in_contract
                AND (f.max_delay_original_invoices_t1 <= 7
                    AND f.max_delay_deal_invoices_t1 <= 7) THEN 'SLIPPERS'
            WHEN f.reference_contract_status = 'Ativo'
                AND ((f.has_negotiation_in_contract
                    AND (f.max_delay_original_invoices_t1 > 7
                        OR f.max_delay_deal_invoices_t1 > 7))
                    OR (f.n_overdue_monthlys_t1 >= 2)) THEN 'SNOWBALL'
            WHEN f.reference_contract_status = 'Finalizado'
                AND f.max_delay_contaminated_contract_t2 < 90
                AND f.n_anchor_invoices_not_negativable = 0 THEN 'SINKING ENDED'
            WHEN f.reference_contract_status = 'Finalizado'
                AND f.max_delay_contaminated_contract_t2 < 90
                AND f.n_anchor_invoices_not_negativable > 0 THEN 'SINKING ENDED - NEFN'
            ELSE NULL
        END AS segment_comms,
        CASE
            WHEN f.reference_contract_status = 'Ativo'
                AND (f.n_days_over1_t2_l180 - 3) <= 0
                AND f.max_delay_contaminated_contract_t2 <= 3 THEN 'VERY_HIGH'
            WHEN f.reference_contract_status = 'Ativo'
                AND f.max_delay_contaminated_contract_t2 <= 30
                AND f.avg_days_overdue_invoices_paid_t1 <= 5
                AND debts_in_income_share_t1 <= 0.4
                THEN 'HIGH'
            WHEN f.reference_contract_status = 'Ativo'
                AND f.max_delay_contaminated_contract_t2 <= 30
                AND f.avg_days_overdue_invoices_paid_t1 <= 5
                AND debts_in_income_share_t1 > 0.4
                THEN 'LOW'
            WHEN f.reference_contract_status = 'Ativo'
                AND f.max_delay_contaminated_contract_t2 <= 30
                AND f.avg_days_overdue_invoices_paid_t1 <= 20
                AND f.acc_broken_promessas_lifetime <= 1.5
                AND debts_in_income_share_t1 <= 0.4
                THEN 'MEDIUM'
            WHEN f.reference_contract_status = 'Ativo'
                AND f.max_delay_contaminated_contract_t2 <= 30
                AND f.avg_days_overdue_invoices_paid_t1 <= 20
                AND f.acc_broken_promessas_lifetime <= 1.5
                AND debts_in_income_share_t1 > 0.4
                THEN 'LOW'
            WHEN f.reference_contract_status = 'Ativo'
                AND f.max_delay_contaminated_contract_t2 <= 30
                AND f.avg_days_overdue_invoices_paid_t1 <= 20
                AND f.acc_broken_promessas_lifetime > 1.5 THEN 'LOW'
            WHEN f.reference_contract_status = 'Ativo'
                AND f.max_delay_contaminated_contract_t2 <= 30
                AND f.avg_days_overdue_invoices_paid_t1 > 20 THEN 'LOW'
            WHEN f.reference_contract_status = 'Ativo'
                AND f.max_delay_contaminated_contract_t2 <= 30 THEN 'NULL PROB ACTIVE [1-30]'
            WHEN f.reference_contract_status = 'Ativo'
                AND f.max_delay_contaminated_contract_t2 > 30 THEN 'NULL PROB ACTIVE [31+]'
            WHEN f.reference_contract_status = 'Finalizado'
                AND f.max_delay_contaminated_contract_t2 <= 30
                AND acc_n_overdue_invoices_paid_t2_l12m > 1
                AND acc_broken_promessas_lifetime <= 0.50
                AND avg_days_overdue_invoices_paid_t1 <= 5
                THEN 'HIGH'
            WHEN f.reference_contract_status = 'Finalizado'
                AND f.max_delay_contaminated_contract_t2 <= 30
                AND acc_n_overdue_invoices_paid_t2_l12m > 1
                AND acc_broken_promessas_lifetime <= 0.50
                AND avg_days_overdue_invoices_paid_t1 > 5
                AND debts_in_income_share_t1 <= 0.2
                THEN 'HIGH'
            WHEN f.reference_contract_status = 'Finalizado'
                AND f.max_delay_contaminated_contract_t2 <= 30
                AND acc_n_overdue_invoices_paid_t2_l12m > 1
                AND acc_broken_promessas_lifetime <= 0.50
                AND avg_days_overdue_invoices_paid_t1 > 5
                AND debts_in_income_share_t1 > 0.2
                THEN 'LOW'
            WHEN f.reference_contract_status = 'Finalizado'
                AND f.max_delay_contaminated_contract_t2 <= 30
                AND acc_n_overdue_invoices_paid_t2_l12m > 1
                AND acc_broken_promessas_lifetime > 0.50
                THEN 'LOW'
            WHEN  f.reference_contract_status = 'Finalizado'
                AND f.max_delay_contaminated_contract_t2 <= 30
                AND acc_n_overdue_invoices_paid_t2_l12m <= 1
                THEN 'LOW'
            WHEN f.reference_contract_status = 'Finalizado'
                AND f.max_delay_contaminated_contract_t2 <= 30 THEN 'LOW'

            WHEN f.reference_contract_status = 'Finalizado'
                AND f.max_delay_contaminated_contract_t2 > 30
                AND f.max_delay_contaminated_contract_t2 <= 90
                AND f.n_reparos_invoices = f.n_invoices_in_wallet
                THEN 'LOW'
    
            WHEN f.reference_contract_status = 'Finalizado'
                AND f.max_delay_contaminated_contract_t2 > 90
                AND f.n_reparos_invoices = f.n_invoices_in_wallet
                THEN 'VERY_LOW'
            WHEN f.reference_contract_status = 'Finalizado'
                AND f.max_delay_contaminated_contract_t2 > 30
                AND debts_in_income_share_t1 <= 0.2
                THEN 'HIGH'
            WHEN f.reference_contract_status = 'Finalizado'
                AND f.max_delay_contaminated_contract_t2 > 30
                AND (
                    (f.n_rental_core_invoices = 0 AND f.n_acordo_invoices > 0) OR
                    (f.n_rental_core_invoices = 0 AND f.n_acordo_invoices = 0 AND f.acc_cpc_l90 > 0) OR
                    (f.n_rental_core_invoices > 0 AND f.n_reparos_invoices = 0 AND f.share_monthly_paid_ontime_t1 > 0.68)
                ) THEN 'HIGH'
            WHEN f.reference_contract_status = 'Finalizado'
                AND f.max_delay_contaminated_contract_t2 > 30
                AND (f.n_rental_core_invoices > 0 AND f.n_reparos_invoices > 0) THEN 'LOW'
            WHEN f.reference_contract_status = 'Finalizado'
                AND f.max_delay_contaminated_contract_t2 > 30
                THEN 'LOW'
            ELSE 'NULL UNDEFINED'
        END AS prob_payment_at_dt_reference,
        CASE
            WHEN f.reference_contract_status = 'Ativo'
                AND f.max_delay_contaminated_contract_t2 <= 3 THEN 'TREE 0'
            WHEN f.reference_contract_status = 'Ativo'
                AND f.max_delay_contaminated_contract_t2 > 3
                AND f.max_delay_contaminated_contract_t2 <= 30 THEN 'TREE 1'
            WHEN f.reference_contract_status = 'Finalizado'
                AND f.max_delay_contaminated_contract_t2 <= 30 THEN 'TREE 2'
            WHEN f.reference_contract_status = 'Finalizado'
                AND f.max_delay_contaminated_contract_t2 >=31
                THEN 'TREE 3'
            ELSE 'NO_TREE'
        END AS tree_class,
        DATE(DATE_TRUNC('MONTH', dt_reference)) AS dt_month_start
    FROM
        calculate_monthly_payment_ratios AS f

),
calculate_tree_aux AS (
    SELECT
        *,
        ROW_NUMBER() OVER(PARTITION BY sk_contract, dt_month_start, tree_class ORDER BY dt_reference ASC) AS rn_prob_payment_by_tree,
        LAG(tree_class, 1) OVER(PARTITION BY sk_contract ORDER BY dt_reference ASC) AS last_tree
    FROM prob_payment_calculation
),
calculate_the_correct_prob_order AS (
    SELECT
        *,
        CASE
            WHEN last_tree <> tree_class
                AND rn_prob_payment_by_tree <> 1 THEN 1
            ELSE rn_prob_payment_by_tree
        END AS rn_prob_payment_by_tree_entrance
    FROM calculate_tree_aux
),
calculate_frozen_prob_payment AS (
    SELECT
        *,
        LAST_VALUE(
            CASE
                WHEN rn_prob_payment_by_tree_entrance <> 1 OR tree_class = 'NO_TREE' THEN NULL
                ELSE prob_payment_at_dt_reference
            END
            ,TRUE)OVER (PARTITION BY sk_contract, dt_month_start ORDER BY dt_reference) AS prob_payment
    FROM calculate_the_correct_prob_order
),
segmentation_features AS (
    SELECT
        *,
        CASE
            WHEN reference_contract_status = 'Ativo'
                AND max_delay_contaminated_contract_t2 <= 0 THEN 'active-current'
            WHEN reference_contract_status = 'Finalizado'
                AND max_delay_contaminated_contract_t2 <= 0 THEN 'ended-current'
            WHEN is_evictions THEN 'evictions'
            WHEN reference_contract_status = 'Ativo'
                AND has_fpd_in_wallet THEN 'active-new-defaulter-first-payment-default'
            WHEN reference_contract_status = 'Ativo'
                AND has_negotiation_in_contract
                AND max_delay_contaminated_contract_t1 <= 7 THEN 'active-ongoing-deal'
            WHEN reference_contract_status = 'Ativo'
                AND mob_months <= 3
                AND max_delay_contaminated_contract_t2 <= 15 THEN 'active-new-defaulter-under-mob3-early'
            WHEN reference_contract_status = 'Ativo'
                AND mob_months <= 3
                AND max_delay_contaminated_contract_t2 >= 16
                AND max_delay_contaminated_contract_t2 <= 45 THEN 'active-new-defaulter-under-mob3-late'
            WHEN reference_contract_status = 'Ativo'
                AND mob_months <= 6
                AND max_delay_contaminated_contract_t2 <= 30 THEN 'active-new-defaulter-under-mob6'
            WHEN reference_contract_status = 'Ativo'
                AND max_delay_contaminated_contract_t2 <= 30
                AND prob_payment_at_dt_reference = 'VERY_HIGH' THEN 'active-new-defaulter-early-very-high'
            WHEN reference_contract_status = 'Ativo'
                AND prob_payment_at_dt_reference = 'HIGH'
                AND max_delay_contaminated_contract_t2 <= 19 THEN 'active-new-defaulter-early-high'
            WHEN reference_contract_status = 'Ativo'
                AND prob_payment_at_dt_reference = 'HIGH'
                AND max_delay_contaminated_contract_t2 > 19
                AND max_delay_contaminated_contract_t2 <= 30 THEN 'active-new-defaulter-late-high'
            WHEN reference_contract_status = 'Ativo'
                AND prob_payment_at_dt_reference = 'MEDIUM'
                AND max_delay_contaminated_contract_t2 <= 19 THEN 'active-new-defaulter-early-medium'
            WHEN reference_contract_status = 'Ativo'
                AND prob_payment_at_dt_reference = 'MEDIUM'
                AND max_delay_contaminated_contract_t2 > 19
                AND max_delay_contaminated_contract_t2 <= 30 THEN 'active-new-defaulter-late-medium'
            WHEN reference_contract_status = 'Ativo'
                AND prob_payment_at_dt_reference = 'LOW'
                AND max_delay_contaminated_contract_t2 <= 4 THEN 'active-new-defaulter-early-low'
            WHEN reference_contract_status = 'Ativo'
                AND prob_payment_at_dt_reference = 'LOW'
                AND max_delay_contaminated_contract_t2 > 4
                AND max_delay_contaminated_contract_t2 <= 30 THEN 'active-new-defaulter-late-low'
            WHEN reference_contract_status = 'Ativo'
                AND max_delay_contaminated_contract_t2 > 30
                AND (
                    (n_overdue_monthlys_t1 > 1) OR
                    ((has_negotiation_in_contract
                        AND (max_delay_original_invoices_t1 > 7
                            OR max_delay_deal_invoices_t1 > 7)))
                ) THEN 'active-stock-pre-evictions'
            WHEN reference_contract_status = 'Ativo'
                AND max_delay_contaminated_contract_t2 > 30
                AND n_overdue_monthlys_t1 <= 1 THEN 'active-stock-hold'
            WHEN reference_contract_status = 'Ativo' THEN 'UNCLASSIFIED-ACTIVE'
            WHEN reference_contract_status = 'Finalizado'
                AND has_negotiation_in_contract
                AND max_delay_contaminated_contract_t1 <= 7 THEN 'ended-ongoing-deal'
            WHEN reference_contract_status = 'Finalizado'
                AND acc_deals_principal_discount_lifetime > 0 THEN 'ended-had-forgiveness'
            WHEN reference_contract_status = 'Finalizado'
                AND max_delay_contaminated_contract_t2 <= 30
                AND prob_payment_at_dt_reference = 'HIGH' THEN 'ended-new-defaulter-high'
            WHEN reference_contract_status = 'Finalizado'
                AND max_delay_contaminated_contract_t2 <= 30
                AND prob_payment_at_dt_reference = 'LOW' THEN 'ended-new-defaulter-low'
            WHEN reference_contract_status = 'Finalizado'
                AND max_delay_contaminated_contract_t2 > 30
                AND max_delay_contaminated_contract_t2 <= 60
                AND prob_payment_at_dt_reference = 'HIGH' THEN 'ended-stock-roll1-high'
            WHEN reference_contract_status = 'Finalizado'
                AND max_delay_contaminated_contract_t2 > 30
                AND max_delay_contaminated_contract_t2 <= 60
                AND prob_payment_at_dt_reference = 'LOW' THEN 'ended-stock-roll1-low'
            WHEN reference_contract_status = 'Finalizado'
                AND max_delay_contaminated_contract_t2 > 60
                AND max_delay_contaminated_contract_t2 <= 90
                AND prob_payment_at_dt_reference = 'HIGH' THEN 'ended-stock-roll2-high'
            WHEN reference_contract_status = 'Finalizado'
                AND max_delay_contaminated_contract_t2 > 60
                AND max_delay_contaminated_contract_t2 <= 90
                AND prob_payment_at_dt_reference = 'LOW' THEN 'ended-stock-roll2-low'
            WHEN reference_contract_status = 'Finalizado'
                AND max_delay_contaminated_contract_t2 > 90
                AND max_delay_contaminated_contract_t2 <= 180
                AND prob_payment_at_dt_reference = 'HIGH' THEN 'ended-stock-roll3-high'
            WHEN reference_contract_status = 'Finalizado'
                AND max_delay_contaminated_contract_t2 > 90
                AND max_delay_contaminated_contract_t2 <= 180
                AND prob_payment_at_dt_reference = 'LOW' THEN 'ended-stock-roll3-low'
            WHEN reference_contract_status = 'Finalizado'
                AND max_delay_contaminated_contract_t2 > 90
                AND max_delay_contaminated_contract_t2 <= 180
                AND prob_payment_at_dt_reference = 'VERY_LOW' THEN 'ended-stock-roll3-very-low'
            WHEN reference_contract_status = 'Finalizado'
                AND max_delay_contaminated_contract_t2 > 180
                AND max_delay_contaminated_contract_t2 <= 360
                AND prob_payment_at_dt_reference = 'HIGH' THEN 'ended-stock-roll4-high'
            WHEN reference_contract_status = 'Finalizado'
                AND max_delay_contaminated_contract_t2 > 180
                AND max_delay_contaminated_contract_t2 <= 360
                AND prob_payment_at_dt_reference = 'LOW' THEN 'ended-stock-roll4-low'
            WHEN reference_contract_status = 'Finalizado'
                AND max_delay_contaminated_contract_t2 > 180
                AND max_delay_contaminated_contract_t2 <= 360
                AND prob_payment_at_dt_reference = 'VERY_LOW' THEN 'ended-stock-roll4-very-low'
            WHEN reference_contract_status = 'Finalizado'
                AND max_delay_contaminated_contract_t2 > 360
                AND max_delay_contaminated_contract_t2 <= 1440
                AND prob_payment_at_dt_reference = 'HIGH' THEN 'ended-stock-roll5-high'
            WHEN reference_contract_status = 'Finalizado'
                AND max_delay_contaminated_contract_t2 > 360
                AND max_delay_contaminated_contract_t2 <= 1440
                AND prob_payment_at_dt_reference = 'LOW' THEN 'ended-stock-roll5-low'
            WHEN reference_contract_status = 'Finalizado'
                AND max_delay_contaminated_contract_t2 > 360
                AND max_delay_contaminated_contract_t2 <= 1440
                AND prob_payment_at_dt_reference = 'VERY_LOW' THEN 'ended-stock-roll5-very-low'
            WHEN reference_contract_status = 'Finalizado'
                AND max_delay_contaminated_contract_t2 > 1440
                AND prob_payment_at_dt_reference = 'HIGH' THEN 'ended-stock-roll6-high'
            WHEN reference_contract_status = 'Finalizado'
                AND max_delay_contaminated_contract_t2 > 1440
                AND prob_payment_at_dt_reference = 'LOW' THEN 'ended-stock-roll6-low'
            WHEN reference_contract_status = 'Finalizado'
                AND max_delay_contaminated_contract_t2 > 1440
                AND prob_payment_at_dt_reference = 'VERY_LOW' THEN 'ended-stock-roll6-very-low'
            WHEN reference_contract_status = 'Finalizado' THEN 'UNCLASSIFIED-ENDED'
            ELSE 'MISTERY'
        END AS segmentation_with_prob_payment_at_dt_reference,
        CASE
            WHEN reference_contract_status = 'Ativo'
                AND max_delay_contaminated_contract_t2 <= 0 THEN 'active-current'
            WHEN reference_contract_status = 'Finalizado'
                AND max_delay_contaminated_contract_t2 <= 0 THEN 'ended-current'
            WHEN is_evictions THEN 'evictions'
            WHEN reference_contract_status = 'Ativo'
                AND has_fpd_in_wallet THEN 'active-new-defaulter-first-payment-default'
            WHEN reference_contract_status = 'Ativo'
                AND has_negotiation_in_contract
                AND max_delay_contaminated_contract_t1 <= 7 THEN 'active-ongoing-deal'
            WHEN reference_contract_status = 'Ativo'
                AND mob_months <= 3
                AND max_delay_contaminated_contract_t2 <= 15 THEN 'active-new-defaulter-under-mob3-early'
            WHEN reference_contract_status = 'Ativo'
                AND mob_months <= 3
                AND max_delay_contaminated_contract_t2 >= 16
                AND max_delay_contaminated_contract_t2 <= 45 THEN 'active-new-defaulter-under-mob3-late'
            WHEN reference_contract_status = 'Ativo'
                AND mob_months <= 6
                AND max_delay_contaminated_contract_t2 <= 30 THEN 'active-new-defaulter-under-mob6'
            WHEN reference_contract_status = 'Ativo'
                AND max_delay_contaminated_contract_t2 <= 30
                AND prob_payment = 'VERY_HIGH' THEN 'active-new-defaulter-early-very-high'
            WHEN reference_contract_status = 'Ativo'
                AND prob_payment = 'HIGH'
                AND max_delay_contaminated_contract_t2 <= 19 THEN 'active-new-defaulter-early-high'
            WHEN reference_contract_status = 'Ativo'
                AND prob_payment = 'HIGH'
                AND max_delay_contaminated_contract_t2 > 19
                AND max_delay_contaminated_contract_t2 <= 30 THEN 'active-new-defaulter-late-high'
            WHEN reference_contract_status = 'Ativo'
                AND prob_payment = 'MEDIUM'
                AND max_delay_contaminated_contract_t2 <= 19 THEN 'active-new-defaulter-early-medium'
            WHEN reference_contract_status = 'Ativo'
                AND prob_payment = 'MEDIUM'
                AND max_delay_contaminated_contract_t2 > 19
                AND max_delay_contaminated_contract_t2 <= 30 THEN 'active-new-defaulter-late-medium'
            WHEN reference_contract_status = 'Ativo'
                AND prob_payment = 'LOW'
                AND max_delay_contaminated_contract_t2 <= 4 THEN 'active-new-defaulter-early-low'
            WHEN reference_contract_status = 'Ativo'
                AND prob_payment = 'LOW'
                AND max_delay_contaminated_contract_t2 > 4
                AND max_delay_contaminated_contract_t2 <= 30 THEN 'active-new-defaulter-late-low'
            WHEN reference_contract_status = 'Ativo'
                AND max_delay_contaminated_contract_t2 > 30
                AND (
                    (n_overdue_monthlys_t1 > 1) OR
                    ((has_negotiation_in_contract
                        AND (max_delay_original_invoices_t1 > 7
                            OR max_delay_deal_invoices_t1 > 7)))
                ) THEN 'active-stock-pre-evictions'
            WHEN reference_contract_status = 'Ativo'
                AND max_delay_contaminated_contract_t2 > 30
                AND n_overdue_monthlys_t1 <= 1 THEN 'active-stock-hold'
            WHEN reference_contract_status = 'Ativo' THEN 'UNCLASSIFIED-ACTIVE'
            WHEN reference_contract_status = 'Finalizado'
                AND has_negotiation_in_contract
                AND max_delay_contaminated_contract_t1 <= 7 THEN 'ended-ongoing-deal'
            WHEN reference_contract_status = 'Finalizado'
                AND acc_deals_principal_discount_lifetime > 0 THEN 'ended-had-forgiveness'
            WHEN reference_contract_status = 'Finalizado'
                AND max_delay_contaminated_contract_t2 <= 30
                AND prob_payment = 'HIGH' THEN 'ended-new-defaulter-high'
            WHEN reference_contract_status = 'Finalizado'
                AND max_delay_contaminated_contract_t2 <= 30
                AND prob_payment = 'LOW' THEN 'ended-new-defaulter-low'
            WHEN reference_contract_status = 'Finalizado'
                AND max_delay_contaminated_contract_t2 > 30
                AND max_delay_contaminated_contract_t2 <= 60
                AND prob_payment = 'HIGH' THEN 'ended-stock-roll1-high'
            WHEN reference_contract_status = 'Finalizado'
                AND max_delay_contaminated_contract_t2 > 30
                AND max_delay_contaminated_contract_t2 <= 60
                AND prob_payment = 'LOW' THEN 'ended-stock-roll1-low'
            WHEN reference_contract_status = 'Finalizado'
                AND max_delay_contaminated_contract_t2 > 60
                AND max_delay_contaminated_contract_t2 <= 90
                AND prob_payment = 'HIGH' THEN 'ended-stock-roll2-high'
            WHEN reference_contract_status = 'Finalizado'
                AND max_delay_contaminated_contract_t2 > 60
                AND max_delay_contaminated_contract_t2 <= 90
                AND prob_payment = 'LOW' THEN 'ended-stock-roll2-low'
            WHEN reference_contract_status = 'Finalizado'
                AND max_delay_contaminated_contract_t2 > 90
                AND max_delay_contaminated_contract_t2 <= 180
                AND prob_payment = 'HIGH' THEN 'ended-stock-roll3-high'
            WHEN reference_contract_status = 'Finalizado'
                AND max_delay_contaminated_contract_t2 > 90
                AND max_delay_contaminated_contract_t2 <= 180
                AND prob_payment = 'LOW' THEN 'ended-stock-roll3-low'
            WHEN reference_contract_status = 'Finalizado'
                AND max_delay_contaminated_contract_t2 > 90
                AND max_delay_contaminated_contract_t2 <= 180
                AND prob_payment = 'VERY_LOW' THEN 'ended-stock-roll3-very-low'
            WHEN reference_contract_status = 'Finalizado'
                AND max_delay_contaminated_contract_t2 > 180
                AND max_delay_contaminated_contract_t2 <= 360
                AND prob_payment = 'HIGH' THEN 'ended-stock-roll4-high'
            WHEN reference_contract_status = 'Finalizado'
                AND max_delay_contaminated_contract_t2 > 180
                AND max_delay_contaminated_contract_t2 <= 360
                AND prob_payment = 'LOW' THEN 'ended-stock-roll4-low'
            WHEN reference_contract_status = 'Finalizado'
                AND max_delay_contaminated_contract_t2 > 180
                AND max_delay_contaminated_contract_t2 <= 360
                AND prob_payment = 'VERY_LOW' THEN 'ended-stock-roll4-very-low'
            WHEN reference_contract_status = 'Finalizado'
                AND max_delay_contaminated_contract_t2 > 360
                AND max_delay_contaminated_contract_t2 <= 1440
                AND prob_payment = 'HIGH' THEN 'ended-stock-roll5-high'
            WHEN reference_contract_status = 'Finalizado'
                AND max_delay_contaminated_contract_t2 > 360
                AND max_delay_contaminated_contract_t2 <= 1440
                AND prob_payment = 'LOW' THEN 'ended-stock-roll5-low'
            WHEN reference_contract_status = 'Finalizado'
                AND max_delay_contaminated_contract_t2 > 360
                AND max_delay_contaminated_contract_t2 <= 1440
                AND prob_payment = 'VERY_LOW' THEN 'ended-stock-roll5-very-low'
            WHEN reference_contract_status = 'Finalizado'
                AND max_delay_contaminated_contract_t2 > 1440
                AND prob_payment = 'HIGH' THEN 'ended-stock-roll6-high'
            WHEN reference_contract_status = 'Finalizado'
                AND max_delay_contaminated_contract_t2 > 1440
                AND prob_payment = 'LOW' THEN 'ended-stock-roll6-low'
            WHEN reference_contract_status = 'Finalizado'
                AND max_delay_contaminated_contract_t2 > 1440
                AND prob_payment = 'VERY_LOW' THEN 'ended-stock-roll6-very-low'
            WHEN reference_contract_status = 'Finalizado' THEN 'UNCLASSIFIED-ENDED'
            ELSE 'MISTERY'
        END AS segmentation
    FROM
        calculate_frozen_prob_payment
)
SELECT
    MD5(CONCAT(sk_contract, DATE_FORMAT(dt_reference, 'yyyyMMdd'))) AS sk_contract_features_timeline,
    CAST(sk_contract AS BIGINT) AS sk_contract,
    dt_reference,
    reference_contract_status,
    tree_class,
    segment_comms,
    prob_payment_at_dt_reference,
    prob_payment,
    segmentation_with_prob_payment_at_dt_reference,
    segmentation,
    CAST(has_negotiation_in_contract AS BOOLEAN) AS has_negotiation_in_contract,
    CAST(has_overdue_balance_over0_t1_at_ending AS BOOLEAN) AS has_overdue_balance_over0_t1_at_ending,
    CAST(has_overdue_balance_over5_t1_at_ending AS BOOLEAN) AS has_overdue_balance_over5_t1_at_ending,
    CAST(has_overdue_balance_over0_t2_at_ending AS BOOLEAN) AS has_overdue_balance_over0_t2_at_ending,
    CAST(has_overdue_balance_over5_t2_at_ending AS BOOLEAN) AS has_overdue_balance_over5_t2_at_ending,
    CAST(has_overdue_balance_over0_t3_at_ending AS BOOLEAN) AS has_overdue_balance_over0_t3_at_ending,
    CAST(has_overdue_balance_over5_t3_at_ending AS BOOLEAN) AS has_overdue_balance_over5_t3_at_ending,
    CAST(has_overdue_balance_over0_t1_at_ending_ffill AS INT) AS has_overdue_balance_over0_t1_at_ending_ffill,
    CAST(has_overdue_balance_over5_t1_at_ending_ffill AS INT) AS has_overdue_balance_over5_t1_at_ending_ffill,
    CAST(is_evictions AS BOOLEAN) AS is_evictions,
    CAST(has_fpd_in_wallet AS BOOLEAN) AS has_fpd_in_wallet,
    t1_delay_bucket,
    t2_delay_bucket,
    CAST(n_overdue_monthlys_t1 AS BIGINT) AS n_overdue_monthlys_t1,
    CAST(n_overdue_others_t1 AS BIGINT) AS n_overdue_others_t1,
    CAST(n_anchor_invoices_not_negativable AS BIGINT) AS n_anchor_invoices_not_negativable,
    CAST(n_first_invoices_open AS BIGINT) AS n_first_invoices_open,
    CAST(n_reparos_invoices AS BIGINT) AS n_reparos_invoices,
    CAST(n_monthly_invoices AS BIGINT) AS n_monthly_invoices,
    CAST(n_invoices_in_wallet AS BIGINT) AS n_invoices_in_wallet,
    CAST(n_invoices_paid AS BIGINT) AS n_invoices_paid,
    CAST(n_invoices_paid_ontime_t2 AS BIGINT) AS n_invoices_paid_ontime_t2,
    CAST(n_overdue_invoices_paid_t2 AS BIGINT) AS n_overdue_invoices_paid_t2,
    CAST(n_invoices_paid_ontime_t1 AS BIGINT) AS n_invoices_paid_ontime_t1,
    CAST(n_overdue_invoices_paid_t1 AS BIGINT) AS n_overdue_invoices_paid_t1,
    CAST(n_monthly_invoices_paid_ontime_t2 AS BIGINT) AS n_monthly_invoices_paid_ontime_t2,
    CAST(n_monthly_invoices_paid_ontime_t1 AS BIGINT) AS n_monthly_invoices_paid_ontime_t1,
    CAST(n_monthly_overdue_invoices_paid_t2 AS BIGINT) AS n_monthly_overdue_invoices_paid_t2,
    CAST(n_monthly_overdue_invoices_paid_t1 AS BIGINT) AS n_monthly_overdue_invoices_paid_t1,
    CAST(n_monthly_invoices_created AS BIGINT) AS n_monthly_invoices_created,
    CAST(n_rental_core_invoices AS BIGINT) AS n_rental_core_invoices,
    CAST(n_acordo_invoices AS BIGINT) AS n_acordo_invoices,
    CAST(n_days_over1_t2_l180 AS BIGINT) AS n_days_over1_t2_l180,
    CAST(n_evictions_processes_lifetime AS BIGINT) AS n_evictions_processes_lifetime,
    CAST(qt_acordo_quebrado AS BIGINT) AS qt_acordo_quebrado,
    CAST(acc_max_n_repairs AS BIGINT) AS acc_max_n_repairs,
    CAST(acc_cpc_l90 AS BIGINT) AS acc_cpc_l90,
    CAST(acc_broken_multiple_deals_lifetime AS BIGINT) AS acc_broken_multiple_deals_lifetime,
    CAST(acc_broken_promessas_lifetime AS BIGINT) AS acc_broken_promessas_lifetime,
    CAST(acc_deals_principal_discount_lifetime AS BIGINT) AS acc_deals_principal_discount_lifetime,
    CAST(acc_count_monthly_overdue_invoices_paid_t1 AS BIGINT) AS acc_count_monthly_overdue_invoices_paid_t1,
    CAST(acc_sum_monthly_overdue_days_paid_t1 AS BIGINT) AS acc_sum_monthly_overdue_days_paid_t1,
    CAST(acc_n_monthly_invoices_l12m AS BIGINT) AS acc_n_monthly_invoices_l12m,
    CAST(acc_n_monthly_invoices_paid_ontime_t2_l12m AS BIGINT) AS acc_n_monthly_invoices_paid_ontime_t2_l12m,
    CAST(acc_n_monthly_invoices_paid_ontime_t1_l12m AS BIGINT) AS acc_n_monthly_invoices_paid_ontime_t1_l12m,
    CAST(acc_count_monthly_invoices_created AS BIGINT) AS acc_count_monthly_invoices_created,
    CAST(acc_count_monthly_invoices_paid_ontime_t1 AS BIGINT) AS acc_count_monthly_invoices_paid_ontime_t1,
    CAST(acc_n_monthly_overdue_invoices_paid_t2_l12m AS BIGINT) AS acc_n_monthly_overdue_invoices_paid_t2_l12m,
    CAST(acc_n_monthly_overdue_invoices_paid_t1_l12m AS BIGINT) AS acc_n_monthly_overdue_invoices_paid_t1_l12m,
    CAST(acc_n_invoices_paid_ontime_t2_l12m AS BIGINT) AS acc_n_invoices_paid_ontime_t2_l12m,
    CAST(acc_n_invoices_paid_ontime_t1_l12m AS BIGINT) AS acc_n_invoices_paid_ontime_t1_l12m,
    CAST(acc_n_overdue_invoices_paid_t2_l12m AS BIGINT) AS acc_n_overdue_invoices_paid_t2_l12m,
    CAST(acc_n_overdue_invoices_paid_t1_l12m AS BIGINT) AS acc_n_overdue_invoices_paid_t1_l12m,
    CAST(max_delay_contaminated_contract_t1 AS BIGINT) AS max_delay_contaminated_contract_t1,
    CAST(max_delay_contaminated_contract_t2 AS BIGINT) AS max_delay_contaminated_contract_t2,
    CAST(max_delay_original_invoices_t1 AS BIGINT) AS max_delay_original_invoices_t1,
    CAST(max_delay_deal_invoices_t1 AS BIGINT) AS max_delay_deal_invoices_t1,
    CAST(sum_monthly_overdue_days_paid_t1 AS BIGINT) AS sum_monthly_overdue_days_paid_t1,
    CAST(count_monthly_overdue_invoices_paid_t1 AS BIGINT) AS count_monthly_overdue_invoices_paid_t1,
    CAST(days_since_ending AS BIGINT) AS days_since_ending,
    CAST(days_since_contract_start AS BIGINT) AS days_since_contract_start,
    CAST(cpc AS BIGINT) AS cpc,
    CAST(id_process_evictions AS BIGINT) AS id_process_evictions,
    CAST(mob_months AS BIGINT) AS mob_months,
    wallet_overdue_t2,
    overdue_recovered_amount_t2,
    avg_days_overdue_invoices_paid_t1,
    monthly_income,
    pct_monthly_paid_ontime_t2_l12m,
    pct_monthly_paid_ontime_t1_l12m,
    pct_invoices_paid_ontime_t2_l12m,
    pct_invoices_paid_ontime_t1_l12m,
    share_monthly_paid_ontime_t1,
    array_open_invoices,
    array_paid_invoices,
    array_negotiated_invoices,
    dt_month_start,
    dt_contract_start,
    YEAR(dt_reference) AS year,
    MONTH(dt_reference) AS month,
    DAY(dt_reference) AS day,
    NOW() AS ts_load
FROM segmentation_features
WHERE dt_reference >= DATE('{load_start_date}')
    AND dt_reference <= DATE('{load_end_date}')
