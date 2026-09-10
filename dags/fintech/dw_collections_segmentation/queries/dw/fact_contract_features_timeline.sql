WITH deduplication_score AS (
  SELECT
    *
  FROM (
    SELECT
      *,
      ROW_NUMBER() OVER (PARTITION BY id_contract, dt_reference ORDER BY ts_inference DESC) AS _w
    FROM datalake_collections_score_batch_inference_clean.collections_score_v3_output AS m
  ) AS _t
  WHERE
    _w = 1
), essential_features AS (
  SELECT
    m.sk_contract,
    m.dt_reference,
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
    has_fpd_in_wallet_general,
    qt_acordo_quebrado,
    qt_promessa_quebrada_fp,
    qt_aco_desconto,
    n_invoices_in_wallet,
    wallet_overdue_t2,
    debts_in_income_share_t1,
    debts_in_income_share_t2,
    overdue_recovered_amount_t1,
    overdue_recovered_amount_t2,
    open_wallet_overdue_t1,
    open_wallet_to_due_deals,
    package_amount,
    dt_contract_start,
    CASE
      WHEN has_negotiation_in_contract
      AND (
        max_delay_original_invoices_t1 > 0 OR max_delay_deal_invoices_t1 > 0
      )
      THEN TRUE
      ELSE FALSE
    END AS flag_broken_global_deal,
    CASE
      WHEN has_negotiation_in_contract AND max_delay_deal_invoices_t1 > 0
      THEN TRUE
      ELSE FALSE
    END AS flag_broken_installment_deal,
    CASE
      WHEN has_negotiation_in_contract AND max_delay_original_invoices_t1 > 0
      THEN TRUE
      ELSE FALSE
    END AS flag_broken_deal_by_new_original_debt,
    s.payment_probability,
    s.flag_source
  FROM dw_collections_segmentation.fact_contract_wallet_timeline AS m
  LEFT JOIN deduplication_score AS s
    ON s.id_contract = m.sk_contract AND s.dt_reference = m.dt_reference
), contract_features_with_acc AS (
  SELECT
    *,
    COALESCE(
      MAX(n_reparos_invoices) OVER (PARTITION BY sk_contract ORDER BY dt_reference ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW),
      0
    ) AS acc_max_n_repairs,
    COALESCE(
      SUM(cpc) OVER (PARTITION BY sk_contract ORDER BY dt_reference ROWS BETWEEN 90 PRECEDING AND CURRENT ROW),
      0
    ) AS acc_cpc_l90,
    COALESCE(
      SUM(qt_acordo_quebrado) OVER (PARTITION BY sk_contract ORDER BY dt_reference ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW),
      0
    ) AS acc_broken_multiple_deals_lifetime,
    COALESCE(
      SUM(qt_promessa_quebrada_fp) OVER (PARTITION BY sk_contract ORDER BY dt_reference ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW),
      0
    ) AS acc_broken_promessas_lifetime,
    COALESCE(
      SUM(qt_aco_desconto) OVER (PARTITION BY sk_contract ORDER BY dt_reference ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW),
      0
    ) AS acc_deals_principal_discount_lifetime,
    (
      12 * (
        YEAR(TO_DATE(dt_reference)) - YEAR(TO_DATE(dt_contract_start))
      ) + (
        MONTH(TO_DATE(dt_reference)) - MONTH(TO_DATE(dt_contract_start))
      )
    ) AS mob_months,
    SIZE(
      COLLECT_SET(id_process_evictions) OVER (PARTITION BY sk_contract ORDER BY dt_reference ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW)
    ) AS n_evictions_processes_lifetime,
    COALESCE(
      SUM(sum_monthly_overdue_days_paid_t1) OVER (PARTITION BY sk_contract ORDER BY dt_reference ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW),
      0
    ) AS acc_sum_monthly_overdue_days_paid_t1,
    COALESCE(
      SUM(count_monthly_overdue_invoices_paid_t1) OVER (PARTITION BY sk_contract ORDER BY dt_reference ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW),
      0
    ) AS acc_count_monthly_overdue_invoices_paid_t1,
    CAST(COALESCE(
      MAX(CAST(has_overdue_balance_over0_t1_at_ending AS INT)) OVER (PARTITION BY sk_contract ORDER BY dt_reference ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW),
      0
    ) AS INT) AS has_overdue_balance_over0_t1_at_ending_ffill,
    CAST(COALESCE(
      MAX(CAST(has_overdue_balance_over5_t1_at_ending AS INT)) OVER (PARTITION BY sk_contract ORDER BY dt_reference ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW),
      0
    ) AS INT) AS has_overdue_balance_over5_t1_at_ending_ffill,
    COALESCE(
      SUM(n_monthly_invoices) OVER (PARTITION BY sk_contract ORDER BY dt_reference ROWS BETWEEN 365 PRECEDING AND CURRENT ROW),
      0
    ) AS acc_n_monthly_invoices_l12m,
    COALESCE(
      SUM(n_monthly_invoices_paid_ontime_t2) OVER (PARTITION BY sk_contract ORDER BY dt_reference ROWS BETWEEN 365 PRECEDING AND CURRENT ROW),
      0
    ) AS acc_n_monthly_invoices_paid_ontime_t2_l12m,
    COALESCE(
      SUM(n_monthly_invoices_paid_ontime_t1) OVER (PARTITION BY sk_contract ORDER BY dt_reference ROWS BETWEEN 365 PRECEDING AND CURRENT ROW),
      0
    ) AS acc_n_monthly_invoices_paid_ontime_t1_l12m,
    COALESCE(
      SUM(n_monthly_overdue_invoices_paid_t2) OVER (PARTITION BY sk_contract ORDER BY dt_reference ROWS BETWEEN 365 PRECEDING AND CURRENT ROW),
      0
    ) AS acc_n_monthly_overdue_invoices_paid_t2_l12m,
    COALESCE(
      SUM(n_monthly_overdue_invoices_paid_t1) OVER (PARTITION BY sk_contract ORDER BY dt_reference ROWS BETWEEN 365 PRECEDING AND CURRENT ROW),
      0
    ) AS acc_n_monthly_overdue_invoices_paid_t1_l12m,
    COALESCE(
      SUM(n_invoices_paid_ontime_t2) OVER (PARTITION BY sk_contract ORDER BY dt_reference ROWS BETWEEN 365 PRECEDING AND CURRENT ROW),
      0
    ) AS acc_n_invoices_paid_ontime_t2_l12m,
    COALESCE(
      SUM(n_invoices_paid_ontime_t1) OVER (PARTITION BY sk_contract ORDER BY dt_reference ROWS BETWEEN 365 PRECEDING AND CURRENT ROW),
      0
    ) AS acc_n_invoices_paid_ontime_t1_l12m,
    COALESCE(
      SUM(n_overdue_invoices_paid_t2) OVER (PARTITION BY sk_contract ORDER BY dt_reference ROWS BETWEEN 365 PRECEDING AND CURRENT ROW),
      0
    ) AS acc_n_overdue_invoices_paid_t2_l12m,
    COALESCE(
      SUM(n_overdue_invoices_paid_t1) OVER (PARTITION BY sk_contract ORDER BY dt_reference ROWS BETWEEN 365 PRECEDING AND CURRENT ROW),
      0
    ) AS acc_n_overdue_invoices_paid_t1_l12m,
    COALESCE(
      SUM(n_monthly_invoices_created) OVER (PARTITION BY sk_contract ORDER BY dt_reference ROWS BETWEEN 365 PRECEDING AND CURRENT ROW),
      0
    ) AS acc_count_monthly_invoices_created,
    COALESCE(
      SUM(n_monthly_invoices_paid_ontime_t1) OVER (PARTITION BY sk_contract ORDER BY dt_reference ROWS BETWEEN 365 PRECEDING AND CURRENT ROW),
      0
    ) AS acc_count_monthly_invoices_paid_ontime_t1,
    COALESCE(
      SUM(CASE WHEN max_delay_contaminated_contract_t2 > 0 THEN 1 ELSE 0 END) OVER (PARTITION BY sk_contract ORDER BY dt_reference ROWS BETWEEN 180 PRECEDING AND CURRENT ROW),
      0
    ) AS n_days_over1_t2_l180,
    SUM(
      CASE
        WHEN COALESCE(overdue_recovered_amount_t1, 0) > 0
        AND COALESCE(open_wallet_overdue_t1, 0) = 0
        THEN 1
        ELSE 0
      END
    ) OVER (PARTITION BY sk_contract ORDER BY dt_reference ROWS BETWEEN 0 FOLLOWING AND 23 FOLLOWING) AS lead_23_n_quitacao_t1
  FROM essential_features
), calculate_avg_days_overdue_invoice_paid_t1 AS (
  SELECT
    *,
    CASE
      WHEN acc_count_monthly_overdue_invoices_paid_t1 = 0
      THEN 0
      ELSE acc_sum_monthly_overdue_days_paid_t1 / acc_count_monthly_overdue_invoices_paid_t1
    END AS avg_days_overdue_invoices_paid_t1,
    CASE
      WHEN acc_count_monthly_invoices_created = 0
      THEN 0
      ELSE acc_count_monthly_invoices_paid_ontime_t1 / acc_count_monthly_invoices_created
    END AS share_monthly_paid_ontime_t1
  FROM contract_features_with_acc
), calculate_monthly_payment_ratios AS (
  SELECT
    *,
    CASE
      WHEN acc_n_monthly_invoices_l12m = 0
      THEN NULL
      ELSE ROUND(acc_n_monthly_invoices_paid_ontime_t2_l12m / acc_n_monthly_invoices_l12m, 4)
    END AS pct_monthly_paid_ontime_t2_l12m,
    CASE
      WHEN acc_n_monthly_invoices_l12m = 0
      THEN NULL
      ELSE ROUND(acc_n_monthly_invoices_paid_ontime_t1_l12m / acc_n_monthly_invoices_l12m, 4)
    END AS pct_monthly_paid_ontime_t1_l12m,
    CASE
      WHEN (
        acc_n_invoices_paid_ontime_t2_l12m + acc_n_overdue_invoices_paid_t2_l12m
      ) = 0
      THEN NULL
      ELSE ROUND(
        acc_n_invoices_paid_ontime_t2_l12m / (
          acc_n_invoices_paid_ontime_t2_l12m + acc_n_overdue_invoices_paid_t2_l12m
        ),
        4
      )
    END AS pct_invoices_paid_ontime_t2_l12m,
    CASE
      WHEN (
        acc_n_invoices_paid_ontime_t1_l12m + acc_n_overdue_invoices_paid_t1_l12m
      ) = 0
      THEN NULL
      ELSE ROUND(
        acc_n_invoices_paid_ontime_t1_l12m / (
          acc_n_invoices_paid_ontime_t1_l12m + acc_n_overdue_invoices_paid_t1_l12m
        ),
        4
      )
    END AS pct_invoices_paid_ontime_t1_l12m,
    CASE WHEN n_reparos_invoices = n_invoices_in_wallet THEN TRUE ELSE FALSE END AS flag_full_repair,
    CASE
        WHEN reference_contract_status = 'Ativo' AND max_delay_contaminated_contract_t2 <= 0
            THEN 'active-current'
        WHEN reference_contract_status = 'Finalizado'
            AND max_delay_contaminated_contract_t2 <= 0
            THEN 'ended-current'
        WHEN is_evictions
            THEN 'evictions'
        WHEN reference_contract_status = 'Ativo'
            AND has_negotiation_in_contract
            AND max_delay_contaminated_contract_t1 <= 0
            THEN 'active-ongoing-deal'
        WHEN reference_contract_status = 'Ativo'
            AND (
                n_overdue_monthlys_t1 > 1
                OR flag_broken_global_deal
            )
            THEN 'active-stock-pre-evictions'
        WHEN reference_contract_status = 'Ativo'
            AND has_fpd_in_wallet_general
            AND max_delay_contaminated_contract_t2 <= 30
            THEN 'active-new-defaulter-first-payment-default'
        WHEN reference_contract_status = 'Ativo'
            AND mob_months <= 3
            AND max_delay_contaminated_contract_t2 <= 30
            THEN 'active-new-defaulter-under-mob3'
        WHEN reference_contract_status = 'Ativo'
            AND (n_days_over1_t2_l180 - 3) <= 0
            AND max_delay_contaminated_contract_t2 <= 3
            THEN 'active-new-defaulter-special'
        WHEN reference_contract_status = 'Ativo' AND max_delay_contaminated_contract_t2 <= 30
            THEN 'active-new-defaulter'
        WHEN reference_contract_status = 'Ativo'
            AND max_delay_contaminated_contract_t2 > 30
            AND n_overdue_monthlys_t1 <= 1
            THEN 'active-stock-hold'
        WHEN reference_contract_status = 'Ativo'
            THEN 'UNCLASSIFIED'
        WHEN reference_contract_status = 'Finalizado'
            AND has_negotiation_in_contract
            AND max_delay_contaminated_contract_t1 <= 0
            THEN 'ended-ongoing-deal'
        WHEN reference_contract_status = 'Finalizado'
            AND max_delay_contaminated_contract_t2 <= 30
            THEN 'ended-new-defaulter'
        WHEN reference_contract_status = 'Finalizado'
            AND max_delay_contaminated_contract_t2 > 30
            AND max_delay_contaminated_contract_t2 <= 90
            THEN 'ended-stock-31to90'
        WHEN reference_contract_status = 'Finalizado'
            AND max_delay_contaminated_contract_t2 > 90
            AND max_delay_contaminated_contract_t2 <= 180
            THEN 'ended-stock-91to180'
        WHEN reference_contract_status = 'Finalizado'
            AND max_delay_contaminated_contract_t2 > 180
            AND max_delay_contaminated_contract_t2 <= 360
            THEN 'ended-stock-181to360'
        WHEN reference_contract_status = 'Finalizado'
            AND max_delay_contaminated_contract_t2 > 360
            THEN 'ended-stock-361over'
        ELSE 'UNCLASSIFIED'
    END AS macro_segmentation,
    COALESCE(
      LAST_VALUE(payment_probability) IGNORE NULLS OVER (PARTITION BY sk_contract ORDER BY dt_reference),
      -1
    ) AS payment_probability_propagated
  FROM calculate_avg_days_overdue_invoice_paid_t1
), prob_payment_calculation AS (
  SELECT
    f.*,
    CASE
      WHEN f.max_delay_contaminated_contract_t1 <= 0
      THEN 'a. Current'
      WHEN f.max_delay_contaminated_contract_t1 <= 30
      THEN 'b. 1-30'
      WHEN f.max_delay_contaminated_contract_t1 <= 60
      THEN 'c. 31-60'
      WHEN f.max_delay_contaminated_contract_t1 <= 90
      THEN 'd. 61-90'
      WHEN f.max_delay_contaminated_contract_t1 <= 180
      THEN 'g. 91-180'
      ELSE 'h. acima de 180'
    END AS t1_delay_bucket,
    CASE
      WHEN f.max_delay_contaminated_contract_t2 <= 0
      THEN 'a. Current'
      WHEN f.max_delay_contaminated_contract_t2 <= 30
      THEN 'b. 1-30'
      WHEN f.max_delay_contaminated_contract_t2 <= 60
      THEN 'c. 31-60'
      WHEN f.max_delay_contaminated_contract_t2 <= 90
      THEN 'd. 61-90'
      WHEN f.max_delay_contaminated_contract_t2 <= 180
      THEN 'g. 91-180'
      ELSE 'h. acima de 180'
    END AS t2_delay_bucket,
    CASE
      WHEN f.max_delay_contaminated_contract_t2 <= 0
      AND f.reference_contract_status = 'Ativo'
      THEN 'ACTIVE - CURRENT'
      WHEN f.max_delay_contaminated_contract_t2 <= 0
      AND f.reference_contract_status = 'Finalizado'
      THEN 'ENDED - CURRENT'
      WHEN f.days_since_contract_start <= 35
      THEN 'FPD'
      WHEN f.max_delay_contaminated_contract_t2 > 0
      AND f.max_delay_original_invoices_t1 <= 0
      AND f.max_delay_deal_invoices_t1 <= 0
      THEN 'CORLEONES'
      WHEN COALESCE(f.is_evictions, FALSE) = TRUE
      THEN 'EVEX'
      WHEN f.reference_contract_status = 'Finalizado'
      AND f.max_delay_contaminated_contract_t2 >= 90
      THEN 'TITANIC ENDED'
      WHEN f.max_delay_contaminated_contract_t2 <= 15
      AND NOT f.has_negotiation_in_contract
      AND f.n_anchor_invoices_not_negativable = 0
      AND f.reference_contract_status = 'Ativo'
      THEN 'NEW DEFAULTER - ACTIVE'
      WHEN f.max_delay_contaminated_contract_t2 <= 15
      AND NOT f.has_negotiation_in_contract
      AND f.n_anchor_invoices_not_negativable = 0
      AND f.reference_contract_status = 'Finalizado'
      THEN 'NEW DEFAULTER - ENDED'
      WHEN f.max_delay_contaminated_contract_t2 <= 15
      AND NOT f.has_negotiation_in_contract
      AND f.n_anchor_invoices_not_negativable > 0
      THEN 'NEW DEFAULTER - NEFN'
      WHEN f.reference_contract_status = 'Ativo'
      AND f.max_delay_contaminated_contract_t2 > 15
      AND f.n_anchor_invoices_not_negativable > 0
      THEN 'OVER 15 - ACTIVE - NEFN'
      WHEN f.reference_contract_status = 'Ativo'
      AND f.max_delay_contaminated_contract_t2 > 15
      AND NOT f.has_negotiation_in_contract
      AND (
        f.n_overdue_monthlys_t1 <= 1
        OR (
          f.n_overdue_monthlys_t1 = 0 AND f.n_overdue_others_t1 > 1
        )
      )
      THEN 'PURGATORIUM'
      WHEN f.reference_contract_status = 'Ativo'
      AND f.has_negotiation_in_contract
      AND (
        f.max_delay_original_invoices_t1 <= 7 AND f.max_delay_deal_invoices_t1 <= 7
      )
      THEN 'SLIPPERS'
      WHEN f.reference_contract_status = 'Ativo'
      AND (
        (
          f.has_negotiation_in_contract
          AND (
            f.max_delay_original_invoices_t1 > 7 OR f.max_delay_deal_invoices_t1 > 7
          )
        )
        OR (
          f.n_overdue_monthlys_t1 >= 2
        )
      )
      THEN 'SNOWBALL'
      WHEN f.reference_contract_status = 'Finalizado'
      AND f.max_delay_contaminated_contract_t2 < 90
      AND f.n_anchor_invoices_not_negativable = 0
      THEN 'SINKING ENDED'
      WHEN f.reference_contract_status = 'Finalizado'
      AND f.max_delay_contaminated_contract_t2 < 90
      AND f.n_anchor_invoices_not_negativable > 0
      THEN 'SINKING ENDED - NEFN'
      ELSE NULL
    END AS segment_comms,
    CASE
      WHEN f.reference_contract_status = 'Ativo'
      AND f.max_delay_contaminated_contract_t2 <= 3
      THEN 'TREE 0'
      WHEN f.reference_contract_status = 'Ativo'
      AND f.max_delay_contaminated_contract_t2 > 3
      AND f.max_delay_contaminated_contract_t2 <= 30
      THEN 'TREE 1'
      WHEN f.reference_contract_status = 'Ativo'
      AND f.max_delay_contaminated_contract_t2 > 30
      THEN 'TREE 2'
      WHEN f.reference_contract_status = 'Finalizado'
      AND f.max_delay_contaminated_contract_t2 <= 30
      THEN 'TREE 3'
      WHEN f.reference_contract_status = 'Finalizado'
      AND f.max_delay_contaminated_contract_t2 >= 31
      THEN 'TREE 4'
      ELSE 'NO_TREE'
    END AS tree_class,
    CASE
      WHEN f.reference_contract_status = 'Ativo'
      THEN CASE
        WHEN (
          f.n_days_over1_t2_l180 - 3
        ) <= 0
        AND f.max_delay_contaminated_contract_t2 <= 3
        THEN 'VERY_HIGH'
        WHEN f.max_delay_contaminated_contract_t2 <= 30
        THEN CASE
          WHEN f.avg_days_overdue_invoices_paid_t1 <= 5 AND f.debts_in_income_share_t1 <= 0.4
          THEN 'HIGH'
          WHEN f.avg_days_overdue_invoices_paid_t1 <= 20
          AND f.acc_broken_promessas_lifetime <= 1.5
          AND f.debts_in_income_share_t1 <= 0.4
          THEN 'MEDIUM'
          WHEN f.avg_days_overdue_invoices_paid_t1 > 20
          OR (
            f.avg_days_overdue_invoices_paid_t1 <= 20
            AND f.acc_broken_promessas_lifetime > 1.5
          )
          OR f.debts_in_income_share_t1 > 0.4
          THEN 'LOW'
          ELSE 'NULL PROB ACTIVE [1-30]'
        END
        WHEN f.max_delay_contaminated_contract_t2 > 30
        THEN CASE
          WHEN f.avg_days_overdue_invoices_paid_t1 <= 5
          OR f.avg_days_overdue_invoices_paid_t1 > 40
          OR (
            f.n_evictions_processes_lifetime >= 1 AND f.mob_months <= 6
          )
          THEN 'LOW'
          WHEN f.mob_months <= 12
          OR (
            f.n_evictions_processes_lifetime >= 1
            AND f.mob_months > 12
            AND f.avg_days_overdue_invoices_paid_t1 > 30
          )
          THEN 'MEDIUM'
          WHEN (
            f.n_evictions_processes_lifetime >= 1
            AND f.mob_months > 12
            AND f.avg_days_overdue_invoices_paid_t1 <= 30
          )
          OR (
            f.n_evictions_processes_lifetime = 0 AND f.mob_months > 12
          )
          THEN 'HIGH'
          ELSE 'NULL PROB ACTIVE [31+]'
        END
      END
      WHEN f.reference_contract_status = 'Finalizado'
      THEN CASE
        WHEN f.max_delay_contaminated_contract_t2 <= 30
        THEN CASE
          WHEN f.acc_n_overdue_invoices_paid_t2_l12m > 1
          AND f.acc_broken_promessas_lifetime <= 0.50
          AND (
            f.avg_days_overdue_invoices_paid_t1 <= 5 OR f.debts_in_income_share_t1 <= 0.2
          )
          THEN 'HIGH'
          ELSE 'LOW'
        END
        WHEN f.max_delay_contaminated_contract_t2 > 30
        THEN CASE
          WHEN f.max_delay_contaminated_contract_t2 <= 90
          AND f.n_reparos_invoices = f.n_invoices_in_wallet
          THEN 'LOW'
          WHEN f.max_delay_contaminated_contract_t2 > 90
          AND f.n_reparos_invoices = f.n_invoices_in_wallet
          THEN 'VERY_LOW'
          WHEN f.debts_in_income_share_t1 <= 0.2
          OR (
            f.n_rental_core_invoices = 0 AND f.n_acordo_invoices > 0
          )
          OR (
            f.n_rental_core_invoices = 0 AND f.n_acordo_invoices = 0 AND f.acc_cpc_l90 > 0
          )
          OR (
            f.n_rental_core_invoices > 0
            AND f.n_reparos_invoices = 0
            AND f.share_monthly_paid_ontime_t1 > 0.68
          )
          THEN 'HIGH'
          ELSE 'LOW'
        END
      END
      ELSE 'NULL UNDEFINED'
    END AS legacy_prob_payment_at_dt_reference,
    CASE
        WHEN COALESCE(f.is_evictions, FALSE) = TRUE
            THEN CASE
                WHEN f.payment_probability_propagated >= 0.223
                    THEN 'HIGH'
                WHEN f.payment_probability_propagated < 0.223
                    THEN 'LOW'
            END
        WHEN f.reference_contract_status = 'Ativo'
            THEN CASE
                WHEN f.max_delay_contaminated_contract_t2 > 30
                    OR f.macro_segmentation = 'active-stock-pre-evictions'
                    THEN CASE
                        WHEN f.payment_probability_propagated >= 0.38
                            THEN 'HIGH'
                        WHEN f.payment_probability_propagated < 0.38
                            THEN 'LOW'
                        ELSE 'NULL PROB ACTIVE [31+]'
                    END
                WHEN f.max_delay_contaminated_contract_t2 <= 30
                    THEN CASE
                        WHEN (f.n_days_over1_t2_l180 - 3) <= 0
                            AND f.max_delay_contaminated_contract_t2 <= 3
                            THEN 'VERY_HIGH'
                        WHEN f.payment_probability_propagated >= 0.838
                            THEN 'HIGH'
                        WHEN f.payment_probability_propagated >= 0.645
                            THEN 'MEDIUM'
                        WHEN f.payment_probability_propagated < 0.645
                            THEN 'LOW'
                        ELSE 'NULL PROB ACTIVE [1-30]'
                    END
            END
        WHEN f.reference_contract_status = 'Finalizado'
            THEN CASE
                WHEN f.max_delay_contaminated_contract_t2 <= 30
                    THEN CASE
                        WHEN f.payment_probability_propagated >= 0.7
                            THEN 'HIGH'
                        WHEN f.payment_probability_propagated < 0.7
                            THEN 'LOW'
                        ELSE 'NULL UNDEFINED'
                    END
                WHEN f.max_delay_contaminated_contract_t2 <= 90
                    THEN CASE
                        WHEN f.n_reparos_invoices = f.n_invoices_in_wallet
                            THEN 'VERY_LOW'
                        WHEN f.payment_probability_propagated >= 0.186
                            THEN 'HIGH'
                        WHEN f.payment_probability_propagated < 0.186
                            THEN 'LOW'
                        ELSE 'NULL UNDEFINED'
                    END
                WHEN f.max_delay_contaminated_contract_t2 <= 180
                    THEN CASE
                        WHEN f.n_reparos_invoices = f.n_invoices_in_wallet
                            THEN 'VERY_LOW'
                        WHEN f.payment_probability_propagated >= 0.091
                            THEN 'HIGH'
                        WHEN f.payment_probability_propagated < 0.091
                            THEN 'LOW'
                        ELSE 'NULL UNDEFINED'
                    END
                WHEN f.max_delay_contaminated_contract_t2 > 180
                    THEN CASE
                        WHEN f.max_delay_contaminated_contract_t2 <= 360
                            AND f.n_reparos_invoices = f.n_invoices_in_wallet
                            THEN 'VERY_LOW'
                        WHEN f.payment_probability_propagated >= 0.06
                            THEN 'HIGH'
                        WHEN f.payment_probability_propagated < 0.06
                            THEN 'LOW'
                        ELSE 'NULL UNDEFINED'
                    END
            END
        ELSE 'NULL UNDEFINED'
    END AS prob_payment_at_dt_reference,
    CAST(DATE_TRUNC('MONTH', dt_reference) AS DATE) AS dt_month_start
  FROM calculate_monthly_payment_ratios AS f
), islands_prep AS (
  SELECT
    *,
    ROW_NUMBER() OVER (PARTITION BY sk_contract ORDER BY dt_reference ASC) AS rn_total,
    ROW_NUMBER() OVER (PARTITION BY sk_contract, macro_segmentation ORDER BY dt_reference ASC) AS rn_segment
  FROM prob_payment_calculation
), calculate_tree_aux AS (
  SELECT
    *,
    ROW_NUMBER() OVER (PARTITION BY sk_contract, macro_segmentation, (
      rn_total - rn_segment
    ) ORDER BY dt_reference ASC) AS rn_prob_payment_by_tree,
    (
      rn_total - rn_segment
    ) AS macro_island_id,
    LAG(macro_segmentation, 1) OVER (PARTITION BY sk_contract ORDER BY dt_reference ASC) AS last_tree,
    LEAD(macro_segmentation, 1) OVER (PARTITION BY sk_contract ORDER BY dt_reference ASC) AS next_tree
  FROM islands_prep
), calculate_the_correct_prob_order AS (
  SELECT
    *,
    CASE
      WHEN COALESCE(last_tree, 'x') <> COALESCE(macro_segmentation, 'y')
      THEN TRUE
      ELSE FALSE
    END AS flag_first_day_new_macro_segment,
    CASE
      WHEN COALESCE(next_tree, 'x') <> COALESCE(macro_segmentation, 'y')
      THEN TRUE
      ELSE FALSE
    END AS flag_last_day_macro_segment,
    CASE
      WHEN COALESCE(last_tree, 'x') <> COALESCE(macro_segmentation, 'y')
      AND rn_prob_payment_by_tree <> 1
      THEN 1
      ELSE rn_prob_payment_by_tree
    END AS rn_prob_payment_by_tree_entrance
  FROM calculate_tree_aux
), calculate_frozen_prob_payment AS (
  SELECT
    *,
    CASE
        WHEN macro_segmentation = 'UNCLASSIFIED'
            THEN NULL
        WHEN macro_segmentation IN ('active-current', 'ended-current')
            THEN prob_payment_at_dt_reference
        ELSE FIRST_VALUE(prob_payment_at_dt_reference) OVER (PARTITION BY sk_contract, macro_segmentation, macro_island_id ORDER BY dt_reference ASC)
    END AS prob_payment,
    CASE
        WHEN macro_segmentation = 'UNCLASSIFIED'
            THEN NULL
        WHEN macro_segmentation IN ('active-current', 'ended-current')
            THEN payment_probability_propagated
        ELSE FIRST_VALUE(payment_probability_propagated) OVER (PARTITION BY sk_contract, macro_segmentation, macro_island_id ORDER BY dt_reference ASC)
    END AS payment_probability_at_entrance
  FROM calculate_the_correct_prob_order
), segmentation_features AS (
  SELECT
    *,
    CASE
        WHEN reference_contract_status = 'Ativo' AND max_delay_contaminated_contract_t2 <= 0
            THEN 'active-current'
        WHEN reference_contract_status = 'Finalizado'
            AND max_delay_contaminated_contract_t2 <= 0
            THEN 'ended-current'
        WHEN macro_segmentation = 'evictions'
            AND rn_prob_payment_by_tree > 30
            THEN 'evictions-late'
        WHEN macro_segmentation = 'evictions'
            AND payment_probability_at_entrance < 0.223
            THEN 'evictions-early-low'
        WHEN macro_segmentation = 'evictions'
            AND payment_probability_at_entrance >= 0.223
            AND n_evictions_processes_lifetime > 1
            THEN 'evictions-early-reincident-high'
        WHEN macro_segmentation = 'evictions'
            AND payment_probability_at_entrance >= 0.223
            AND n_evictions_processes_lifetime <= 1
            THEN 'evictions-early-first-high'
        WHEN macro_segmentation = 'evictions'
            THEN 'evictions-undefined'
        WHEN reference_contract_status = 'Ativo'
            AND has_negotiation_in_contract
            AND max_delay_contaminated_contract_t1 <= 0
            THEN 'active-ongoing-deal'
        WHEN reference_contract_status = 'Ativo'
            AND macro_segmentation = 'active-stock-pre-evictions'
            AND flag_broken_global_deal
            AND flag_broken_deal_by_new_original_debt
            THEN 'active-stock-risk-deal-new-monthly'
        WHEN reference_contract_status = 'Ativo'
            AND macro_segmentation = 'active-stock-pre-evictions'
            AND flag_broken_global_deal
            AND flag_broken_installment_deal
            THEN 'active-stock-risk-deal-unpaid'
        WHEN reference_contract_status = 'Ativo'
            AND macro_segmentation = 'active-stock-pre-evictions'
            AND NOT flag_broken_global_deal
            AND prob_payment_at_dt_reference = 'LOW'
            THEN 'active-stock-risk-nodeal-low'
        WHEN reference_contract_status = 'Ativo'
            AND macro_segmentation = 'active-stock-pre-evictions'
            AND NOT flag_broken_global_deal
            AND prob_payment_at_dt_reference IN ('HIGH', 'MEDIUM')
            THEN 'active-stock-risk-nodeal-high'
        WHEN reference_contract_status = 'Ativo'
            AND max_delay_contaminated_contract_t2 > 30
            AND (
                n_overdue_monthlys_t1 > 1
                OR flag_broken_global_deal
            )
            THEN 'active-stock-pre-evictions-legacy'
        WHEN reference_contract_status = 'Ativo'
            AND has_fpd_in_wallet_general
            AND max_delay_contaminated_contract_t2 <= 30
            THEN 'active-new-defaulter-first-payment-default'
        WHEN reference_contract_status = 'Ativo'
            AND mob_months <= 3
            AND max_delay_contaminated_contract_t2 <= 15
            THEN 'active-new-defaulter-under-mob3-early'
        WHEN reference_contract_status = 'Ativo'
            AND mob_months <= 3
            AND max_delay_contaminated_contract_t2 >= 16
            AND max_delay_contaminated_contract_t2 <= 30
            THEN 'active-new-defaulter-under-mob3-late'
        WHEN reference_contract_status = 'Ativo'
            AND max_delay_contaminated_contract_t2 <= 30
            AND prob_payment_at_dt_reference = 'VERY_HIGH'
            THEN 'active-new-defaulter-good-payers'
        WHEN reference_contract_status = 'Ativo'
            AND prob_payment_at_dt_reference = 'HIGH'
            AND max_delay_contaminated_contract_t2 <= 30
            THEN 'active-new-defaulter-high'
        WHEN reference_contract_status = 'Ativo'
            AND prob_payment_at_dt_reference = 'MEDIUM'
            AND max_delay_contaminated_contract_t2 <= 30
            THEN 'active-new-defaulter-medium'
        WHEN reference_contract_status = 'Ativo'
            AND prob_payment_at_dt_reference = 'LOW'
            AND max_delay_contaminated_contract_t2 <= 4
            THEN 'active-new-defaulter-early-low'
        WHEN reference_contract_status = 'Ativo'
            AND prob_payment_at_dt_reference = 'LOW'
            AND max_delay_contaminated_contract_t2 > 4
            AND max_delay_contaminated_contract_t2 <= 30
            THEN 'active-new-defaulter-late-low'
        WHEN reference_contract_status = 'Ativo'
            AND max_delay_contaminated_contract_t2 > 30
            AND n_overdue_monthlys_t1 <= 1
            THEN 'active-stock-hold'
        WHEN reference_contract_status = 'Ativo'
            THEN 'UNCLASSIFIED-ACTIVE'
        WHEN reference_contract_status = 'Finalizado'
            AND has_negotiation_in_contract
            AND max_delay_contaminated_contract_t1 <= 7
            THEN 'ended-ongoing-deal'
        WHEN reference_contract_status = 'Finalizado'
            AND max_delay_contaminated_contract_t2 <= 30
            AND prob_payment_at_dt_reference = 'HIGH'
            THEN 'ended-new-defaulter-high'
        WHEN reference_contract_status = 'Finalizado'
            AND max_delay_contaminated_contract_t2 <= 30
            AND prob_payment_at_dt_reference = 'LOW'
            THEN 'ended-new-defaulter-low'
        WHEN reference_contract_status = 'Finalizado'
            AND max_delay_contaminated_contract_t2 > 30
            AND max_delay_contaminated_contract_t2 <= 90
            AND prob_payment_at_dt_reference = 'HIGH'
            THEN 'ended-stock-31-90-high'
        WHEN reference_contract_status = 'Finalizado'
            AND max_delay_contaminated_contract_t2 > 30
            AND max_delay_contaminated_contract_t2 <= 90
            AND prob_payment_at_dt_reference = 'LOW'
            THEN 'ended-stock-31-90-low'
        WHEN reference_contract_status = 'Finalizado'
            AND max_delay_contaminated_contract_t2 > 30
            AND max_delay_contaminated_contract_t2 <= 90
            AND prob_payment_at_dt_reference = 'VERY_LOW'
            THEN 'ended-stock-31-90-repair'
        WHEN reference_contract_status = 'Finalizado'
            AND max_delay_contaminated_contract_t2 > 90
            AND max_delay_contaminated_contract_t2 <= 180
            AND prob_payment_at_dt_reference = 'HIGH'
            THEN 'ended-stock-91-180-high'
        WHEN reference_contract_status = 'Finalizado'
            AND max_delay_contaminated_contract_t2 > 90
            AND max_delay_contaminated_contract_t2 <= 180
            AND prob_payment_at_dt_reference = 'LOW'
            THEN 'ended-stock-91-180-low'
        WHEN reference_contract_status = 'Finalizado'
            AND max_delay_contaminated_contract_t2 > 90
            AND max_delay_contaminated_contract_t2 <= 180
            AND prob_payment_at_dt_reference = 'VERY_LOW'
            THEN 'ended-stock-91-180-repair'
        WHEN reference_contract_status = 'Finalizado'
            AND max_delay_contaminated_contract_t2 > 180
            AND max_delay_contaminated_contract_t2 <= 360
            AND prob_payment_at_dt_reference = 'HIGH'
            THEN 'ended-stock-181-360-high'
        WHEN reference_contract_status = 'Finalizado'
            AND max_delay_contaminated_contract_t2 > 180
            AND max_delay_contaminated_contract_t2 <= 360
            AND prob_payment_at_dt_reference = 'LOW'
            THEN 'ended-stock-181-360-low'
        WHEN reference_contract_status = 'Finalizado'
            AND max_delay_contaminated_contract_t2 > 180
            AND max_delay_contaminated_contract_t2 <= 360
            AND prob_payment_at_dt_reference = 'VERY_LOW'
            THEN 'ended-stock-181-360-repair'
        WHEN reference_contract_status = 'Finalizado'
            AND max_delay_contaminated_contract_t2 > 360
            AND max_delay_contaminated_contract_t2 <= 1440
            THEN 'ended-stock-361-1440'
        WHEN reference_contract_status = 'Finalizado'
            AND max_delay_contaminated_contract_t2 > 1440
            THEN 'ended-stock-over1440'
        WHEN reference_contract_status = 'Finalizado'
            THEN 'UNCLASSIFIED-ENDED'
        ELSE 'MISTERY'
    END AS segmentation_with_prob_payment_at_dt_reference,
    CASE
        WHEN reference_contract_status = 'Ativo' AND max_delay_contaminated_contract_t2 <= 0
            THEN 'active-current'
        WHEN reference_contract_status = 'Finalizado'
            AND max_delay_contaminated_contract_t2 <= 0
            THEN 'ended-current'
        WHEN macro_segmentation = 'evictions'
            AND rn_prob_payment_by_tree > 30
            THEN 'evictions-late'
        WHEN macro_segmentation = 'evictions'
            AND payment_probability_at_entrance < 0.223
            THEN 'evictions-early-low'
        WHEN macro_segmentation = 'evictions'
            AND payment_probability_at_entrance >= 0.223
            AND n_evictions_processes_lifetime > 1
            THEN 'evictions-early-reincident-high'
        WHEN macro_segmentation = 'evictions'
            AND payment_probability_at_entrance >= 0.223
            AND n_evictions_processes_lifetime <= 1
            THEN 'evictions-early-first-high'
        WHEN macro_segmentation = 'evictions'
            THEN 'evictions-undefined'
        WHEN reference_contract_status = 'Ativo'
            AND has_negotiation_in_contract
            AND max_delay_contaminated_contract_t1 <= 0
            THEN 'active-ongoing-deal'
        WHEN reference_contract_status = 'Ativo'
            AND macro_segmentation = 'active-stock-pre-evictions'
            AND flag_broken_global_deal
            AND flag_broken_deal_by_new_original_debt
            THEN 'active-stock-risk-deal-new-monthly'
        WHEN reference_contract_status = 'Ativo'
            AND macro_segmentation = 'active-stock-pre-evictions'
            AND flag_broken_global_deal
            AND flag_broken_installment_deal
            THEN 'active-stock-risk-deal-unpaid'
        WHEN reference_contract_status = 'Ativo'
            AND macro_segmentation = 'active-stock-pre-evictions'
            AND NOT flag_broken_global_deal
            AND prob_payment = 'LOW'
            THEN 'active-stock-risk-nodeal-low'
        WHEN reference_contract_status = 'Ativo'
            AND macro_segmentation = 'active-stock-pre-evictions'
            AND NOT flag_broken_global_deal
            AND prob_payment IN ('HIGH', 'MEDIUM')
            THEN 'active-stock-risk-nodeal-high'
        WHEN reference_contract_status = 'Ativo'
            AND max_delay_contaminated_contract_t2 > 30
            AND (
                n_overdue_monthlys_t1 > 1
                OR flag_broken_global_deal
            )
            THEN 'active-stock-pre-evictions-legacy'
        WHEN reference_contract_status = 'Ativo'
            AND has_fpd_in_wallet_general
            AND max_delay_contaminated_contract_t2 <= 30
            THEN 'active-new-defaulter-first-payment-default'
        WHEN reference_contract_status = 'Ativo'
            AND mob_months <= 3
            AND max_delay_contaminated_contract_t2 <= 15
            THEN 'active-new-defaulter-under-mob3-early'
        WHEN reference_contract_status = 'Ativo'
            AND mob_months <= 3
            AND max_delay_contaminated_contract_t2 >= 16
            AND max_delay_contaminated_contract_t2 <= 30
            THEN 'active-new-defaulter-under-mob3-late'
        WHEN reference_contract_status = 'Ativo'
            AND max_delay_contaminated_contract_t2 <= 30
            AND prob_payment = 'VERY_HIGH'
            THEN 'active-new-defaulter-good-payers'
        WHEN reference_contract_status = 'Ativo'
            AND prob_payment = 'HIGH'
            AND max_delay_contaminated_contract_t2 <= 30
            THEN 'active-new-defaulter-high'
        WHEN reference_contract_status = 'Ativo'
            AND prob_payment = 'MEDIUM'
            AND max_delay_contaminated_contract_t2 <= 30
            THEN 'active-new-defaulter-medium'
        WHEN reference_contract_status = 'Ativo'
            AND prob_payment = 'LOW'
            AND max_delay_contaminated_contract_t2 <= 4
            THEN 'active-new-defaulter-early-low'
        WHEN reference_contract_status = 'Ativo'
            AND prob_payment = 'LOW'
            AND max_delay_contaminated_contract_t2 > 4
            AND max_delay_contaminated_contract_t2 <= 30
            THEN 'active-new-defaulter-late-low'
        WHEN reference_contract_status = 'Ativo'
            AND max_delay_contaminated_contract_t2 > 30
            AND n_overdue_monthlys_t1 <= 1
            THEN 'active-stock-hold'
        WHEN reference_contract_status = 'Ativo'
            THEN 'UNCLASSIFIED-ACTIVE'
        WHEN reference_contract_status = 'Finalizado'
            AND has_negotiation_in_contract
            AND max_delay_contaminated_contract_t1 <= 7
            THEN 'ended-ongoing-deal'
        WHEN reference_contract_status = 'Finalizado'
            AND max_delay_contaminated_contract_t2 <= 30
            AND prob_payment = 'HIGH'
            THEN 'ended-new-defaulter-high'
        WHEN reference_contract_status = 'Finalizado'
            AND max_delay_contaminated_contract_t2 <= 30
            AND prob_payment = 'LOW'
            THEN 'ended-new-defaulter-low'
        WHEN reference_contract_status = 'Finalizado'
            AND max_delay_contaminated_contract_t2 > 30
            AND max_delay_contaminated_contract_t2 <= 90
            AND prob_payment = 'HIGH'
            THEN 'ended-stock-31-90-high'
        WHEN reference_contract_status = 'Finalizado'
            AND max_delay_contaminated_contract_t2 > 30
            AND max_delay_contaminated_contract_t2 <= 90
            AND prob_payment = 'LOW'
            THEN 'ended-stock-31-90-low'
        WHEN reference_contract_status = 'Finalizado'
            AND max_delay_contaminated_contract_t2 > 30
            AND max_delay_contaminated_contract_t2 <= 90
            AND prob_payment = 'VERY_LOW'
            THEN 'ended-stock-31-90-repair'
        WHEN reference_contract_status = 'Finalizado'
            AND max_delay_contaminated_contract_t2 > 90
            AND max_delay_contaminated_contract_t2 <= 180
            AND prob_payment = 'HIGH'
            THEN 'ended-stock-91-180-high'
        WHEN reference_contract_status = 'Finalizado'
            AND max_delay_contaminated_contract_t2 > 90
            AND max_delay_contaminated_contract_t2 <= 180
            AND prob_payment = 'LOW'
            THEN 'ended-stock-91-180-low'
        WHEN reference_contract_status = 'Finalizado'
            AND max_delay_contaminated_contract_t2 > 90
            AND max_delay_contaminated_contract_t2 <= 180
            AND prob_payment = 'VERY_LOW'
            THEN 'ended-stock-91-180-repair'
        WHEN reference_contract_status = 'Finalizado'
            AND max_delay_contaminated_contract_t2 > 180
            AND max_delay_contaminated_contract_t2 <= 360
            AND prob_payment = 'HIGH'
            THEN 'ended-stock-181-360-high'
        WHEN reference_contract_status = 'Finalizado'
            AND max_delay_contaminated_contract_t2 > 180
            AND max_delay_contaminated_contract_t2 <= 360
            AND prob_payment = 'LOW'
            THEN 'ended-stock-181-360-low'
        WHEN reference_contract_status = 'Finalizado'
            AND max_delay_contaminated_contract_t2 > 180
            AND max_delay_contaminated_contract_t2 <= 360
            AND prob_payment = 'VERY_LOW'
            THEN 'ended-stock-181-360-repair'
        WHEN reference_contract_status = 'Finalizado'
            AND max_delay_contaminated_contract_t2 > 360
            AND max_delay_contaminated_contract_t2 <= 1440
            THEN 'ended-stock-361-1440'
        WHEN reference_contract_status = 'Finalizado'
            AND max_delay_contaminated_contract_t2 > 1440
            THEN 'ended-stock-over1440'
        WHEN reference_contract_status = 'Finalizado'
            THEN 'UNCLASSIFIED-ENDED'
        ELSE 'MISTERY'
    END AS segmentation
  FROM calculate_frozen_prob_payment
), micro_islands_prep AS (
  SELECT
    *,
    ROW_NUMBER() OVER (PARTITION BY sk_contract, segmentation ORDER BY dt_reference ASC) AS rn_micro_segment
  FROM segmentation_features
), final_features_with_days AS (
  SELECT
    *,
    ROW_NUMBER() OVER (PARTITION BY sk_contract, segmentation, (
      rn_total - rn_micro_segment
    ) ORDER BY dt_reference ASC) AS days_in_segmentation
  FROM micro_islands_prep
)
SELECT
  MD5(CONCAT(sk_contract, DATE_FORMAT(dt_reference, 'yyyyMMdd'))) AS sk_contract_features_timeline,
  CAST(sk_contract AS BIGINT) AS sk_contract,
  dt_reference,
  reference_contract_status,
  tree_class,
  segment_comms,
  legacy_prob_payment_at_dt_reference,
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
  package_amount,
  open_wallet_to_due_deals,
  flag_broken_installment_deal,
  flag_broken_deal_by_new_original_debt,
  flag_broken_global_deal,
  CAST(rn_prob_payment_by_tree AS BIGINT) AS days_in_macro_segmentation,
  CAST(days_in_segmentation AS BIGINT) AS days_in_segmentation,
  macro_segmentation,
  next_tree AS next_macro_segmentation,
  last_tree AS last_macro_segmentation,
  flag_first_day_new_macro_segment,
  flag_last_day_macro_segment,
  payment_probability_propagated,
  payment_probability,
  flag_source,
  flag_full_repair,
  pct_monthly_paid_ontime_t2_l12m,
  pct_monthly_paid_ontime_t1_l12m,
  pct_invoices_paid_ontime_t2_l12m,
  pct_invoices_paid_ontime_t1_l12m,
  share_monthly_paid_ontime_t1,
  CASE
      WHEN macro_segmentation IN ('active-new-defaulter-special')
          THEN 'active-new-defaulter'
      ELSE macro_segmentation
  END AS major_segmentation,
  CASE
      WHEN segmentation IN (
          'active-new-defaulter-first-payment-default', 'active-new-defaulter-good-payers',
          'active-new-defaulter-under-mob3-early', 'active-new-defaulter-under-mob3-late',
          'active-new-defaulter-high', 'active-new-defaulter-medium',
          'active-new-defaulter-early-low', 'active-new-defaulter-late-low',
          'active-stock-hold', 'active-stock-risk-deal-unpaid', 'active-stock-risk-deal-new-monthly',
          'active-stock-risk-nodeal-high', 'active-stock-risk-nodeal-low',
          'active-ongoing-deal'
      )
          THEN 'active-segments'
      WHEN segmentation IN (
          'ended-new-defaulter-high', 'ended-new-defaulter-low',
          'ended-stock-31-90-high', 'ended-stock-31-90-low', 'ended-stock-31-90-repair',
          'ended-stock-91-180-high', 'ended-stock-91-180-low', 'ended-stock-91-180-repair',
          'ended-stock-181-360-high', 'ended-stock-181-360-low', 'ended-stock-181-360-repair',
          'ended-stock-361-1440', 'ended-stock-over1440', 'ended-ongoing-deal'
      )
          THEN 'ended-segments'
      WHEN macro_segmentation IN ('evictions')
          THEN 'evictions'
      ELSE segmentation
  END AS hyper_segmentation,
  CASE
      WHEN segmentation = 'evictions-late'
          THEN 'evictions-late'
      WHEN segmentation IN (
          'evictions-early-low',
          'evictions-early-reincident-high',
          'evictions-early-first-high'
      )
          THEN 'evictions-early'
      WHEN segmentation IN (
          'active-new-defaulter-under-mob3-early',
          'active-new-defaulter-under-mob3-late'
      )
          THEN 'active-new-defaulter-under-mob3'
      WHEN segmentation IN (
          'active-new-defaulter-early-low',
          'active-new-defaulter-late-low'
      )
          THEN 'active-new-defaulter-low'
      WHEN segmentation IN (
          'active-new-defaulter-good-payers'
      )
          THEN 'active-new-defaulter-high'
      WHEN segmentation IN (
          'active-stock-risk-deal-unpaid',
          'active-stock-risk-deal-new-monthly'
      )
          THEN 'active-stock-risk-deal'
      WHEN segmentation IN (
          'active-stock-risk-nodeal-high',
          'active-stock-risk-nodeal-low'
      )
          THEN 'active-stock-risk-nodeal'
      ELSE segmentation
  END AS clustered_segmentation,
  payment_probability_at_entrance,
  array_open_invoices,
  array_paid_invoices,
  array_negotiated_invoices,
  dt_month_start,
  dt_contract_start,
  lead_23_n_quitacao_t1,
  YEAR(TO_DATE(dt_reference)) AS year,
  MONTH(TO_DATE(dt_reference)) AS month,
  DAY(TO_DATE(dt_reference)) AS day,
  NOW() AS ts_load
FROM final_features_with_days
WHERE
  dt_reference >= CAST('{load_start_date}' AS DATE)
  AND dt_reference <= CAST('{load_end_date}' AS DATE)
