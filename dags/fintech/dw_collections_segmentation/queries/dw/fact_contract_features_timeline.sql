WITH
contract_info AS (
    SELECT
      c.sk_contract,
      ROUND(SUM(p.monthly_income), 2) AS monthly_income
    FROM dw_rent.dim_contract c
    LEFT JOIN dw_rent.fact_listing_rent_flows f
      ON c.sk_contract = f.sk_contract
      AND f.sk_contract <> -1
    LEFT JOIN datalake_sorting_hat_clean.proponent p
      ON p.id_proposal = f.sk_proposal
    GROUP BY
      c.sk_contract, f.sk_proposal, f.sk_proposal_approved_date,
      c.ts_canceled, c.guarantee
    QUALIFY ROW_NUMBER() OVER(PARTITION BY c.sk_contract ORDER BY f.sk_proposal DESC) = 1
),
essential_features AS (
    SELECT
        id_contract,
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
        is_blocklisted,
        n_anchor_invoices_not_negativable,
        array_open_invoices,
        array_paid_invoices,
        array_negotiated_invoices,
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
        qt_aco_desconto,
        n_invoices_in_wallet,
        dt_contract_start
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
        COALESCE(SUM(qt_aco_desconto) OVER (
            PARTITION BY id_contract
            ORDER BY dt_reference
            ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
                ), 0) AS acc_deals_principal_discount_lifetime,
        (12*(YEAR(dt_reference) - YEAR(dt_contract_start)) +
         (MONTH(dt_reference) - MONTH(dt_contract_start))) AS mob_months,
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
        CAST(COALESCE(MAX(CAST(has_overdue_balance_over0_t1_at_ending AS INT)) OVER (
            PARTITION BY id_contract
            ORDER BY dt_reference
            ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
        ), 0) AS INT) AS has_overdue_balance_over0_t1_at_ending_ffill,
        CAST(COALESCE(MAX(CAST(has_overdue_balance_over5_t1_at_ending AS INT)) OVER (
            PARTITION BY id_contract
            ORDER BY dt_reference
            ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
        ), 0) AS INT) AS has_overdue_balance_over5_t1_at_ending_ffill,
        COALESCE(SUM(n_monthly_invoices) OVER (
            PARTITION BY id_contract
            ORDER BY dt_reference
            ROWS BETWEEN 365 PRECEDING AND CURRENT ROW
        ), 0) AS acc_n_monthly_invoices_l12m,
        COALESCE(SUM(n_monthly_invoices_paid_ontime_t2) OVER (
            PARTITION BY id_contract
            ORDER BY dt_reference
            ROWS BETWEEN 365 PRECEDING AND CURRENT ROW
        ), 0) AS acc_n_monthly_invoices_paid_ontime_t2_l12m,
        COALESCE(SUM(n_monthly_invoices_paid_ontime_t1) OVER (
            PARTITION BY id_contract
            ORDER BY dt_reference
            ROWS BETWEEN 365 PRECEDING AND CURRENT ROW
        ), 0) AS acc_n_monthly_invoices_paid_ontime_t1_l12m,
        COALESCE(SUM(n_monthly_overdue_invoices_paid_t2) OVER (
            PARTITION BY id_contract
            ORDER BY dt_reference
            ROWS BETWEEN 365 PRECEDING AND CURRENT ROW
        ), 0) AS acc_n_monthly_overdue_invoices_paid_t2_l12m,
        COALESCE(SUM(n_monthly_overdue_invoices_paid_t1) OVER (
            PARTITION BY id_contract
            ORDER BY dt_reference
            ROWS BETWEEN 365 PRECEDING AND CURRENT ROW
        ), 0) AS acc_n_monthly_overdue_invoices_paid_t1_l12m,
        COALESCE(SUM(n_invoices_paid_ontime_t2) OVER (
            PARTITION BY id_contract
            ORDER BY dt_reference
            ROWS BETWEEN 365 PRECEDING AND CURRENT ROW
        ), 0) AS acc_n_invoices_paid_ontime_t2_l12m,
        COALESCE(SUM(n_invoices_paid_ontime_t1) OVER (
            PARTITION BY id_contract
            ORDER BY dt_reference
            ROWS BETWEEN 365 PRECEDING AND CURRENT ROW
        ), 0) AS acc_n_invoices_paid_ontime_t1_l12m,
        COALESCE(SUM(n_overdue_invoices_paid_t2) OVER (
            PARTITION BY id_contract
            ORDER BY dt_reference
            ROWS BETWEEN 365 PRECEDING AND CURRENT ROW
        ), 0) AS acc_n_overdue_invoices_paid_t2_l12m,
        COALESCE(SUM(n_overdue_invoices_paid_t1) OVER (
            PARTITION BY id_contract
            ORDER BY dt_reference
            ROWS BETWEEN 365 PRECEDING AND CURRENT ROW
        ), 0) AS acc_n_overdue_invoices_paid_t1_l12m,
        COALESCE(SUM(n_monthly_invoices_created) OVER (
            PARTITION BY id_contract
            ORDER BY dt_reference
            ROWS BETWEEN 365 PRECEDING AND CURRENT ROW
        ), 0) AS acc_count_monthly_invoices_created,
        COALESCE(SUM(n_monthly_invoices_paid_ontime_t1) OVER (
            PARTITION BY id_contract
            ORDER BY dt_reference
            ROWS BETWEEN 365 PRECEDING AND CURRENT ROW
        ), 0) AS acc_count_monthly_invoices_paid_ontime_t1,
        COALESCE(SUM(CASE WHEN max_delay_contaminated_contract_t2 > 0 THEN 1 ELSE 0 END) OVER (
            PARTITION BY id_contract
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
        c.monthly_income,
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
            WHEN f.is_blocklisted THEN 'BLOCKLIST'
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
                AND f.max_delay_contaminated_contract_t2 <= 3 THEN 'ALTISSIMA'
            WHEN f.reference_contract_status = 'Ativo'
                AND f.max_delay_contaminated_contract_t2 <= 30
                AND f.avg_days_overdue_invoices_paid_t1 <= 5 THEN 'ALTA'
            WHEN f.reference_contract_status = 'Ativo'
                AND f.max_delay_contaminated_contract_t2 <= 30
                AND f.avg_days_overdue_invoices_paid_t1 <= 20
                AND f.acc_broken_multiple_deals_lifetime <= 1.5 THEN 'ALTA'
            WHEN f.reference_contract_status = 'Ativo'
                AND f.max_delay_contaminated_contract_t2 <= 30
                AND f.avg_days_overdue_invoices_paid_t1 <= 20
                AND f.acc_broken_multiple_deals_lifetime > 1.5 THEN 'BAIXA'
            WHEN f.reference_contract_status = 'Ativo'
                AND f.max_delay_contaminated_contract_t2 <= 30
                AND f.avg_days_overdue_invoices_paid_t1 > 20 THEN 'BAIXA'
            WHEN f.reference_contract_status = 'Ativo'
                AND f.max_delay_contaminated_contract_t2 <= 30 THEN 'NULL PROB ACTIVE [1-30]'
            WHEN f.reference_contract_status = 'Ativo'
                AND f.max_delay_contaminated_contract_t2 > 30 THEN 'NULL PROB ACTIVE [31+]'
            WHEN f.reference_contract_status = 'Finalizado'
                AND f.max_delay_contaminated_contract_t2 <= 30
                AND f.avg_days_overdue_invoices_paid_t1 <= 11
                AND f.days_since_ending <= 30 THEN 'ALTA'
            WHEN f.reference_contract_status = 'Finalizado'
                AND f.max_delay_contaminated_contract_t2 <= 30
                AND f.avg_days_overdue_invoices_paid_t1 <= 11
                AND f.days_since_ending > 30
                AND (c.monthly_income <= 8100 OR c.monthly_income IS NULL) THEN 'BAIXA'
            WHEN f.reference_contract_status = 'Finalizado'
                AND f.max_delay_contaminated_contract_t2 <= 30
                AND f.avg_days_overdue_invoices_paid_t1 <= 11
                AND f.days_since_ending > 30
                AND c.monthly_income > 8100 THEN 'ALTA'
            WHEN f.reference_contract_status = 'Finalizado'
                AND f.max_delay_contaminated_contract_t2 <= 30
                AND f.avg_days_overdue_invoices_paid_t1 > 11
                AND f.acc_max_n_repairs = 0
                AND f.acc_broken_multiple_deals_lifetime = 0 THEN 'ALTA'
            WHEN f.reference_contract_status = 'Finalizado'
                AND f.max_delay_contaminated_contract_t2 <= 30
                AND f.avg_days_overdue_invoices_paid_t1 > 11
                AND f.acc_max_n_repairs = 0
                AND f.acc_broken_multiple_deals_lifetime > 0 THEN 'BAIXA'
            WHEN f.reference_contract_status = 'Finalizado'
                AND f.max_delay_contaminated_contract_t2 <= 30
                AND f.avg_days_overdue_invoices_paid_t1 > 11
                AND f.acc_max_n_repairs > 0 THEN 'BAIXA'
            WHEN f.reference_contract_status = 'Finalizado'
                AND f.max_delay_contaminated_contract_t2 <= 30 THEN 'NULL PROB ENDED [1-30]'
            WHEN f.reference_contract_status = 'Finalizado'
                AND f.max_delay_contaminated_contract_t2 > 30
                AND f.max_delay_contaminated_contract_t2 <= 90
                AND (
                    (f.n_rental_core_invoices = 0 AND f.n_acordo_invoices > 0) OR
                    (f.n_rental_core_invoices = 0 AND f.n_acordo_invoices = 0 AND f.acc_cpc_l90 > 0) OR
                    (f.n_rental_core_invoices > 0 AND f.n_reparos_invoices = 0 AND f.share_monthly_paid_ontime_t1 > 0.68)
                ) THEN 'ALTA'
            WHEN f.reference_contract_status = 'Finalizado'
                AND f.max_delay_contaminated_contract_t2 > 30
                AND f.max_delay_contaminated_contract_t2 <= 90
                AND (f.n_rental_core_invoices > 0 AND f.n_reparos_invoices > 0) THEN 'BAIXA'
            WHEN f.reference_contract_status = 'Finalizado'
                AND f.max_delay_contaminated_contract_t2 > 30
                AND f.max_delay_contaminated_contract_t2 <= 90 THEN 'BAIXA'
            WHEN f.reference_contract_status = 'Finalizado'
                AND f.max_delay_contaminated_contract_t2 > 90
                AND f.n_reparos_invoices = f.n_invoices_in_wallet THEN 'BAIXISSÍMA'
            WHEN f.reference_contract_status = 'Finalizado'
                AND f.max_delay_contaminated_contract_t2 > 90
                AND (
                    (f.n_rental_core_invoices = 0 AND f.n_acordo_invoices > 0) OR
                    (f.n_rental_core_invoices = 0 AND f.n_acordo_invoices = 0 AND f.acc_cpc_l90 > 0) OR
                    (f.n_rental_core_invoices > 0 AND f.n_reparos_invoices = 0 AND f.share_monthly_paid_ontime_t1 > 0.68)
                ) THEN 'ALTA'
            WHEN f.reference_contract_status = 'Finalizado'
                AND f.max_delay_contaminated_contract_t2 > 90
                AND (f.n_rental_core_invoices > 0 AND f.n_reparos_invoices > 0) THEN 'BAIXA'
            WHEN f.reference_contract_status = 'Finalizado'
                AND f.max_delay_contaminated_contract_t2 > 90 THEN 'BAIXA'
            ELSE 'NULL UNDEFINED'
        END AS prob_payment
    FROM
        calculate_monthly_payment_ratios AS f
    LEFT JOIN
        contract_info AS c
            ON c.sk_contract = f.id_contract
),
segmentation_features AS (
    SELECT
        p.*,
        CASE
            WHEN p.reference_contract_status = 'Ativo'
                AND p.max_delay_contaminated_contract_t2 <= 0 THEN 'active-current'
            WHEN p.reference_contract_status = 'Finalizado'
                AND p.max_delay_contaminated_contract_t2 <= 0 THEN 'ended-current'
            WHEN p.is_evictions THEN 'evictions'
            WHEN p.reference_contract_status = 'Ativo'
                AND p.has_fpd_in_wallet THEN 'active-new-defaulter-first-payment-default'
            WHEN p.reference_contract_status = 'Ativo'
                AND p.has_negotiation_in_contract
                AND p.max_delay_contaminated_contract_t1 <= 7 THEN 'active-ongoing-deal'
            WHEN p.reference_contract_status = 'Ativo'
                AND p.mob_months <= 3
                AND p.max_delay_contaminated_contract_t2 <= 15 THEN 'active-new-defaulter-under-mob3-early'
            WHEN p.reference_contract_status = 'Ativo'
                AND p.mob_months <= 3
                AND p.max_delay_contaminated_contract_t2 >= 16
                AND p.max_delay_contaminated_contract_t2 <= 45 THEN 'active-new-defaulter-under-mob3-late'
            WHEN p.reference_contract_status = 'Ativo'
                AND p.mob_months <= 6
                AND p.max_delay_contaminated_contract_t2 <= 30 THEN 'active-new-defaulter-under-mob6'
            WHEN p.reference_contract_status = 'Ativo'
                AND p.prob_payment = 'ALTISSIMA' THEN 'active-new-defaulter-early-very-high'
            WHEN p.reference_contract_status = 'Ativo'
                AND p.prob_payment = 'ALTA'
                AND p.max_delay_contaminated_contract_t2 <= 19 THEN 'active-new-defaulter-early-high'
            WHEN p.reference_contract_status = 'Ativo'
                AND p.prob_payment = 'ALTA'
                AND p.max_delay_contaminated_contract_t2 > 19
                AND p.max_delay_contaminated_contract_t2 <= 30 THEN 'active-new-defaulter-late-high'
            WHEN p.reference_contract_status = 'Ativo'
                AND p.prob_payment = 'BAIXA'
                AND p.max_delay_contaminated_contract_t2 <= 4 THEN 'active-new-defaulter-early-low'
            WHEN p.reference_contract_status = 'Ativo'
                AND p.prob_payment = 'BAIXA'
                AND p.max_delay_contaminated_contract_t2 > 4
                AND p.max_delay_contaminated_contract_t2 <= 30 THEN 'active-new-defaulter-late-low'
            WHEN p.reference_contract_status = 'Ativo'
                AND p.max_delay_contaminated_contract_t2 > 30
                AND p.n_overdue_monthlys_t1 <= 1 THEN 'active-stock-hold'
            WHEN p.reference_contract_status = 'Ativo'
                AND p.max_delay_contaminated_contract_t2 > 30
                AND (
                    (p.n_overdue_monthlys_t1 > 1) OR
                    ((p.has_negotiation_in_contract
                        AND (p.max_delay_original_invoices_t1 > 7
                            OR p.max_delay_deal_invoices_t1 > 7)))
                ) THEN 'active-stock-pre-evictions'
            WHEN p.reference_contract_status = 'Ativo' THEN 'UNCLASSIFIED-ACTIVE'
            WHEN p.reference_contract_status = 'Finalizado'
                AND p.has_negotiation_in_contract
                AND p.max_delay_contaminated_contract_t1 <= 7 THEN 'ended-ongoing-deal'
            WHEN p.reference_contract_status = 'Finalizado'
                AND p.acc_deals_principal_discount_lifetime > 0 THEN 'ended-had-forgiveness'
            WHEN p.reference_contract_status = 'Finalizado'
                AND p.max_delay_contaminated_contract_t2 <= 30
                AND p.prob_payment = 'ALTA' THEN 'ended-new-defaulter-high'
            WHEN p.reference_contract_status = 'Finalizado'
                AND p.max_delay_contaminated_contract_t2 <= 30
                AND p.prob_payment = 'BAIXA' THEN 'ended-new-defaulter-low'
            WHEN p.reference_contract_status = 'Finalizado'
                AND p.max_delay_contaminated_contract_t2 > 30
                AND p.max_delay_contaminated_contract_t2 <= 60
                AND p.prob_payment = 'ALTA' THEN 'ended-stock-roll1-high'
            WHEN p.reference_contract_status = 'Finalizado'
                AND p.max_delay_contaminated_contract_t2 > 30
                AND p.max_delay_contaminated_contract_t2 <= 60
                AND p.prob_payment = 'BAIXA' THEN 'ended-stock-roll1-low'
            WHEN p.reference_contract_status = 'Finalizado'
                AND p.max_delay_contaminated_contract_t2 > 60
                AND p.max_delay_contaminated_contract_t2 <= 90
                AND p.prob_payment = 'ALTA' THEN 'ended-stock-roll2-high'
            WHEN p.reference_contract_status = 'Finalizado'
                AND p.max_delay_contaminated_contract_t2 > 60
                AND p.max_delay_contaminated_contract_t2 <= 90
                AND p.prob_payment = 'BAIXA' THEN 'ended-stock-roll2-low'
            WHEN p.reference_contract_status = 'Finalizado'
                AND p.max_delay_contaminated_contract_t2 > 90
                AND p.max_delay_contaminated_contract_t2 <= 180
                AND p.prob_payment = 'ALTA' THEN 'ended-stock-roll3-high'
            WHEN p.reference_contract_status = 'Finalizado'
                AND p.max_delay_contaminated_contract_t2 > 90
                AND p.max_delay_contaminated_contract_t2 <= 180
                AND p.prob_payment = 'BAIXA' THEN 'ended-stock-roll3-low'
            WHEN p.reference_contract_status = 'Finalizado'
                AND p.max_delay_contaminated_contract_t2 > 90
                AND p.max_delay_contaminated_contract_t2 <= 180
                AND p.prob_payment = 'BAIXISSÍMA' THEN 'ended-stock-roll3-very-low'
            WHEN p.reference_contract_status = 'Finalizado'
                AND p.max_delay_contaminated_contract_t2 > 180
                AND p.max_delay_contaminated_contract_t2 <= 360
                AND p.prob_payment = 'ALTA' THEN 'ended-stock-roll4-high'
            WHEN p.reference_contract_status = 'Finalizado'
                AND p.max_delay_contaminated_contract_t2 > 180
                AND p.max_delay_contaminated_contract_t2 <= 360
                AND p.prob_payment = 'BAIXA' THEN 'ended-stock-roll4-low'
            WHEN p.reference_contract_status = 'Finalizado'
                AND p.max_delay_contaminated_contract_t2 > 180
                AND p.max_delay_contaminated_contract_t2 <= 360
                AND p.prob_payment = 'BAIXISSÍMA' THEN 'ended-stock-roll4-very-low'
            WHEN p.reference_contract_status = 'Finalizado'
                AND p.max_delay_contaminated_contract_t2 > 360
                AND p.max_delay_contaminated_contract_t2 <= 1440
                AND p.prob_payment = 'ALTA' THEN 'ended-stock-roll5-high'
            WHEN p.reference_contract_status = 'Finalizado'
                AND p.max_delay_contaminated_contract_t2 > 360
                AND p.max_delay_contaminated_contract_t2 <= 1440
                AND p.prob_payment = 'BAIXA' THEN 'ended-stock-roll5-low'
            WHEN p.reference_contract_status = 'Finalizado'
                AND p.max_delay_contaminated_contract_t2 > 360
                AND p.max_delay_contaminated_contract_t2 <= 1440
                AND p.prob_payment = 'BAIXISSÍMA' THEN 'ended-stock-roll5-very-low'
            WHEN p.reference_contract_status = 'Finalizado'
                AND p.max_delay_contaminated_contract_t2 > 1440
                AND p.prob_payment = 'ALTA' THEN 'ended-stock-roll6-high'
            WHEN p.reference_contract_status = 'Finalizado'
                AND p.max_delay_contaminated_contract_t2 > 1440
                AND p.prob_payment = 'BAIXA' THEN 'ended-stock-roll6-low'
            WHEN p.reference_contract_status = 'Finalizado'
                AND p.max_delay_contaminated_contract_t2 > 1440
                AND p.prob_payment = 'BAIXISSÍMA' THEN 'ended-stock-roll6-very-low'
            WHEN p.reference_contract_status = 'Finalizado' THEN 'UNCLASSIFIED-ENDED'
            ELSE 'MISTERY'
        END AS segmentation
    FROM
        prob_payment_calculation AS p
)
SELECT
    CAST(f.id_contract AS BIGINT) AS id_contract,
    f.dt_reference,
    f.reference_contract_status,
    f.segment_comms,
    f.prob_payment,
    f.segmentation,
    CAST(f.has_negotiation_in_contract AS BOOLEAN) AS has_negotiation_in_contract,
    CAST(f.has_overdue_balance_over0_t1_at_ending AS BOOLEAN) AS has_overdue_balance_over0_t1_at_ending,
    CAST(f.has_overdue_balance_over5_t1_at_ending AS BOOLEAN) AS has_overdue_balance_over5_t1_at_ending,
    CAST(f.has_overdue_balance_over0_t2_at_ending AS BOOLEAN) AS has_overdue_balance_over0_t2_at_ending,
    CAST(f.has_overdue_balance_over5_t2_at_ending AS BOOLEAN) AS has_overdue_balance_over5_t2_at_ending,
    CAST(f.has_overdue_balance_over0_t3_at_ending AS BOOLEAN) AS has_overdue_balance_over0_t3_at_ending,
    CAST(f.has_overdue_balance_over5_t3_at_ending AS BOOLEAN) AS has_overdue_balance_over5_t3_at_ending,
    CAST(f.has_overdue_balance_over0_t1_at_ending_ffill AS INT) AS has_overdue_balance_over0_t1_at_ending_ffill,
    CAST(f.has_overdue_balance_over5_t1_at_ending_ffill AS INT) AS has_overdue_balance_over5_t1_at_ending_ffill,
    CAST(f.is_evictions AS BOOLEAN) AS is_evictions,
    CAST(f.is_blocklisted AS BOOLEAN) AS is_blocklisted,
    CAST(f.has_fpd_in_wallet AS BOOLEAN) AS has_fpd_in_wallet,
    f.t1_delay_bucket,
    f.t2_delay_bucket,
    CAST(f.n_overdue_monthlys_t1 AS BIGINT) AS n_overdue_monthlys_t1,
    CAST(f.n_overdue_others_t1 AS BIGINT) AS n_overdue_others_t1,
    CAST(f.n_anchor_invoices_not_negativable AS BIGINT) AS n_anchor_invoices_not_negativable,
    CAST(f.n_first_invoices_open AS BIGINT) AS n_first_invoices_open,
    CAST(f.n_reparos_invoices AS BIGINT) AS n_reparos_invoices,
    CAST(f.n_monthly_invoices AS BIGINT) AS n_monthly_invoices,
    CAST(f.n_invoices_in_wallet AS BIGINT) AS n_invoices_in_wallet,
    CAST(f.n_invoices_paid AS BIGINT) AS n_invoices_paid,
    CAST(f.n_invoices_paid_ontime_t2 AS BIGINT) AS n_invoices_paid_ontime_t2,
    CAST(f.n_overdue_invoices_paid_t2 AS BIGINT) AS n_overdue_invoices_paid_t2,
    CAST(f.n_invoices_paid_ontime_t1 AS BIGINT) AS n_invoices_paid_ontime_t1,
    CAST(f.n_overdue_invoices_paid_t1 AS BIGINT) AS n_overdue_invoices_paid_t1,
    CAST(f.n_monthly_invoices_paid_ontime_t2 AS BIGINT) AS n_monthly_invoices_paid_ontime_t2,
    CAST(f.n_monthly_invoices_paid_ontime_t1 AS BIGINT) AS n_monthly_invoices_paid_ontime_t1,
    CAST(f.n_monthly_overdue_invoices_paid_t2 AS BIGINT) AS n_monthly_overdue_invoices_paid_t2,
    CAST(f.n_monthly_overdue_invoices_paid_t1 AS BIGINT) AS n_monthly_overdue_invoices_paid_t1,
    CAST(f.n_monthly_invoices_created AS BIGINT) AS n_monthly_invoices_created,
    CAST(f.n_rental_core_invoices AS BIGINT) AS n_rental_core_invoices,
    CAST(f.n_acordo_invoices AS BIGINT) AS n_acordo_invoices,
    CAST(f.n_days_over1_t2_l180 AS BIGINT) AS n_days_over1_t2_l180,
    CAST(f.n_evictions_processes_lifetime AS BIGINT) AS n_evictions_processes_lifetime,
    CAST(f.qt_acordo_quebrado AS BIGINT) AS qt_acordo_quebrado,
    CAST(f.acc_max_n_repairs AS BIGINT) AS acc_max_n_repairs,
    CAST(f.acc_cpc_l90 AS BIGINT) AS acc_cpc_l90,
    CAST(f.acc_broken_multiple_deals_lifetime AS BIGINT) AS acc_broken_multiple_deals_lifetime,
    CAST(f.acc_deals_principal_discount_lifetime AS BIGINT) AS acc_deals_principal_discount_lifetime,
    CAST(f.acc_count_monthly_overdue_invoices_paid_t1 AS BIGINT) AS acc_count_monthly_overdue_invoices_paid_t1,
    CAST(f.acc_sum_monthly_overdue_days_paid_t1 AS BIGINT) AS acc_sum_monthly_overdue_days_paid_t1,
    CAST(f.acc_n_monthly_invoices_l12m AS BIGINT) AS acc_n_monthly_invoices_l12m,
    CAST(f.acc_n_monthly_invoices_paid_ontime_t2_l12m AS BIGINT) AS acc_n_monthly_invoices_paid_ontime_t2_l12m,
    CAST(f.acc_n_monthly_invoices_paid_ontime_t1_l12m AS BIGINT) AS acc_n_monthly_invoices_paid_ontime_t1_l12m,
    CAST(f.acc_count_monthly_invoices_created AS BIGINT) AS acc_count_monthly_invoices_created,
    CAST(f.acc_count_monthly_invoices_paid_ontime_t1 AS BIGINT) AS acc_count_monthly_invoices_paid_ontime_t1,
    CAST(f.acc_n_monthly_overdue_invoices_paid_t2_l12m AS BIGINT) AS acc_n_monthly_overdue_invoices_paid_t2_l12m,
    CAST(f.acc_n_monthly_overdue_invoices_paid_t1_l12m AS BIGINT) AS acc_n_monthly_overdue_invoices_paid_t1_l12m,
    CAST(f.acc_n_invoices_paid_ontime_t2_l12m AS BIGINT) AS acc_n_invoices_paid_ontime_t2_l12m,
    CAST(f.acc_n_invoices_paid_ontime_t1_l12m AS BIGINT) AS acc_n_invoices_paid_ontime_t1_l12m,
    CAST(f.acc_n_overdue_invoices_paid_t2_l12m AS BIGINT) AS acc_n_overdue_invoices_paid_t2_l12m,
    CAST(f.acc_n_overdue_invoices_paid_t1_l12m AS BIGINT) AS acc_n_overdue_invoices_paid_t1_l12m,
    CAST(f.max_delay_contaminated_contract_t1 AS BIGINT) AS max_delay_contaminated_contract_t1,
    CAST(f.max_delay_contaminated_contract_t2 AS BIGINT) AS max_delay_contaminated_contract_t2,
    CAST(f.max_delay_original_invoices_t1 AS BIGINT) AS max_delay_original_invoices_t1,
    CAST(f.max_delay_deal_invoices_t1 AS BIGINT) AS max_delay_deal_invoices_t1,
    CAST(f.sum_monthly_overdue_days_paid_t1 AS BIGINT) AS sum_monthly_overdue_days_paid_t1,
    CAST(f.count_monthly_overdue_invoices_paid_t1 AS BIGINT) AS count_monthly_overdue_invoices_paid_t1,
    CAST(f.days_since_ending AS BIGINT) AS days_since_ending,
    CAST(f.days_since_contract_start AS BIGINT) AS days_since_contract_start,
    CAST(f.cpc AS BIGINT) AS cpc,
    CAST(f.id_process_evictions AS BIGINT) AS id_process_evictions,
    CAST(f.mob_months AS BIGINT) AS mob_months,
    f.avg_days_overdue_invoices_paid_t1,
    f.monthly_income,
    f.pct_monthly_paid_ontime_t2_l12m,
    f.pct_monthly_paid_ontime_t1_l12m,
    f.pct_invoices_paid_ontime_t2_l12m,
    f.pct_invoices_paid_ontime_t1_l12m,
    f.share_monthly_paid_ontime_t1,
    f.array_open_invoices,
    f.array_paid_invoices,
    f.array_negotiated_invoices,
    NOW() AS ts_load
FROM segmentation_features AS f
