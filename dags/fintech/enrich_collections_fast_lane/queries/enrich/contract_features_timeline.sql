WITH
score_ranked AS (
  SELECT
    id_contract,
    dt_reference,
    payment_probability,
    ROW_NUMBER() OVER (
      PARTITION BY id_contract, dt_reference
      ORDER BY ts_inference DESC
    ) AS row_number
  FROM datalake_collections_score_batch_inference_clean.collections_score_v3_output
),
deduplicated_score AS (
  SELECT
    id_contract,
    dt_reference,
    payment_probability
  FROM score_ranked
  WHERE row_number = 1
),
essential_features AS (
  SELECT
    wallet.id_contract,
    wallet.dt_reference,
    wallet.reference_contract_status,
    wallet.max_delay_contaminated_contract_t1,
    wallet.max_delay_contaminated_contract_t2,
    wallet.max_delay_original_invoices_t1,
    wallet.max_delay_deal_invoices_t1,
    wallet.n_overdue_monthlys_t1,
    wallet.has_negotiation_in_contract,
    wallet.sum_monthly_overdue_days_paid_t1,
    wallet.count_monthly_overdue_invoices_paid_t1,
    wallet.id_process_evictions,
    wallet.is_evictions,
    wallet.n_reparos_invoices,
    wallet.n_invoices_in_wallet,
    wallet.dt_contract_start,
    wallet.has_fpd_in_wallet_general,
    wallet.qt_aco_desconto,
    CASE
      WHEN wallet.has_negotiation_in_contract
        AND (
          wallet.max_delay_original_invoices_t1 > 0
          OR wallet.max_delay_deal_invoices_t1 > 0
        ) THEN TRUE
      ELSE FALSE
    END AS flag_broken_global_deal,
    CASE
      WHEN wallet.has_negotiation_in_contract AND wallet.max_delay_deal_invoices_t1 > 0 THEN TRUE
      ELSE FALSE
    END AS flag_broken_installment_deal,
    CASE
      WHEN wallet.has_negotiation_in_contract AND wallet.max_delay_original_invoices_t1 > 0 THEN TRUE
      ELSE FALSE
    END AS flag_broken_deal_by_new_original_debt,
    CASE
      WHEN wallet.n_reparos_invoices = wallet.n_invoices_in_wallet THEN TRUE
      ELSE FALSE
    END AS flag_full_repair,
    wallet.n_monthly_invoices,
    wallet.n_monthly_invoices_paid_ontime_t1,
    wallet.n_monthly_invoices_created,
    wallet.has_overdue_balance_over5_t1_at_ending,
    score.payment_probability
  FROM datalake_collections_fast_lane.contract_wallet_timeline AS wallet
  LEFT JOIN deduplicated_score AS score
    ON score.id_contract = wallet.id_contract
    AND score.dt_reference = wallet.dt_reference
  WHERE wallet.dt_reference BETWEEN DATE_SUB(DATE('{load_start_date}'), 365) AND DATE('{load_end_date}')
),
accumulated_features AS (
  SELECT
    id_contract,
    dt_reference,
    reference_contract_status,
    max_delay_contaminated_contract_t1,
    max_delay_contaminated_contract_t2,
    n_overdue_monthlys_t1,
    has_negotiation_in_contract,
    is_evictions,
    n_reparos_invoices,
    n_invoices_in_wallet,
    has_fpd_in_wallet_general,
    flag_broken_global_deal,
    flag_broken_installment_deal,
    flag_broken_deal_by_new_original_debt,
    flag_full_repair,
    payment_probability,
    (
      12 * (YEAR(dt_reference) - YEAR(dt_contract_start))
      + (MONTH(dt_reference) - MONTH(dt_contract_start))
    ) AS mob_months,
    SIZE(
      COLLECT_SET(id_process_evictions) OVER (
        PARTITION BY id_contract
        ORDER BY dt_reference
        ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
      )
    ) AS n_evictions_processes_lifetime,
    COALESCE(
      SUM(sum_monthly_overdue_days_paid_t1) OVER (
        PARTITION BY id_contract
        ORDER BY dt_reference
        ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
      ),
      0
    ) AS acc_sum_monthly_overdue_days_paid_t1,
    COALESCE(
      SUM(count_monthly_overdue_invoices_paid_t1) OVER (
        PARTITION BY id_contract
        ORDER BY dt_reference
        ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
      ),
      0
    ) AS acc_count_monthly_overdue_invoices_paid_t1,
    COALESCE(
      SUM(qt_aco_desconto) OVER (
        PARTITION BY id_contract
        ORDER BY dt_reference
        ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
      ),
      0
    ) AS acc_deals_principal_discount_lifetime,
    COALESCE(
      SUM(
        CASE
          WHEN max_delay_contaminated_contract_t2 > 0 THEN 1
          ELSE 0
        END
      ) OVER (
        PARTITION BY id_contract
        ORDER BY dt_reference
        ROWS BETWEEN 180 PRECEDING AND CURRENT ROW
      ),
      0
    ) AS n_days_over1_t2_l180,
    CAST(
      COALESCE(
        MAX(CAST(has_overdue_balance_over5_t1_at_ending AS INT)) OVER (
          PARTITION BY id_contract
          ORDER BY dt_reference
          ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
        ),
        0
      ) AS INT
    ) AS has_overdue_balance_over5_t1_at_ending_ffill,
    COALESCE(
      SUM(n_monthly_invoices_created) OVER (
        PARTITION BY id_contract
        ORDER BY dt_reference
        ROWS BETWEEN 365 PRECEDING AND CURRENT ROW
      ),
      0
    ) AS acc_count_monthly_invoices_created,
    COALESCE(
      SUM(n_monthly_invoices_paid_ontime_t1) OVER (
        PARTITION BY id_contract
        ORDER BY dt_reference
        ROWS BETWEEN 365 PRECEDING AND CURRENT ROW
      ),
      0
    ) AS acc_count_monthly_invoices_paid_ontime_t1,
    COALESCE(
      SUM(n_monthly_invoices) OVER (
        PARTITION BY id_contract
        ORDER BY dt_reference
        ROWS BETWEEN 365 PRECEDING AND CURRENT ROW
      ),
      0
    ) AS acc_n_monthly_invoices_l12m,
    COALESCE(
      SUM(n_monthly_invoices_paid_ontime_t1) OVER (
        PARTITION BY id_contract
        ORDER BY dt_reference
        ROWS BETWEEN 365 PRECEDING AND CURRENT ROW
      ),
      0
    ) AS acc_n_monthly_invoices_paid_ontime_t1_l12m
  FROM essential_features
),
derived_features AS (
  SELECT
    id_contract,
    dt_reference,
    reference_contract_status,
    max_delay_contaminated_contract_t1,
    max_delay_contaminated_contract_t2,
    n_overdue_monthlys_t1,
    has_negotiation_in_contract,
    is_evictions,
    n_reparos_invoices,
    n_invoices_in_wallet,
    has_fpd_in_wallet_general,
    flag_broken_global_deal,
    flag_broken_installment_deal,
    flag_broken_deal_by_new_original_debt,
    flag_full_repair,
    has_overdue_balance_over5_t1_at_ending_ffill,
    acc_count_monthly_overdue_invoices_paid_t1,
    payment_probability,
    mob_months,
    n_evictions_processes_lifetime,
    acc_deals_principal_discount_lifetime,
    n_days_over1_t2_l180,
    CASE
      WHEN acc_count_monthly_overdue_invoices_paid_t1 = 0 THEN 0
      ELSE acc_sum_monthly_overdue_days_paid_t1 / acc_count_monthly_overdue_invoices_paid_t1
    END AS avg_days_overdue_invoices_paid_t1,
    CASE
      WHEN acc_count_monthly_invoices_created = 0 THEN 0
      ELSE acc_count_monthly_invoices_paid_ontime_t1 / acc_count_monthly_invoices_created
    END AS share_monthly_paid_ontime_t1,
    CASE
      WHEN acc_n_monthly_invoices_l12m = 0 THEN NULL
      ELSE ROUND(acc_n_monthly_invoices_paid_ontime_t1_l12m / acc_n_monthly_invoices_l12m, 4)
    END AS pct_monthly_paid_ontime_t1_l12m
  FROM accumulated_features
),
macro_features AS (
  SELECT
    id_contract,
    dt_reference,
    reference_contract_status,
    max_delay_contaminated_contract_t1,
    max_delay_contaminated_contract_t2,
    n_overdue_monthlys_t1,
    has_negotiation_in_contract,
    is_evictions,
    n_reparos_invoices,
    n_invoices_in_wallet,
    has_fpd_in_wallet_general,
    flag_broken_global_deal,
    has_overdue_balance_over5_t1_at_ending_ffill,
    acc_count_monthly_overdue_invoices_paid_t1,
    pct_monthly_paid_ontime_t1_l12m,
    share_monthly_paid_ontime_t1,
    flag_full_repair,
    flag_broken_deal_by_new_original_debt,
    flag_broken_installment_deal,
    payment_probability,
    mob_months,
    n_evictions_processes_lifetime,
    acc_deals_principal_discount_lifetime,
    n_days_over1_t2_l180,
    avg_days_overdue_invoices_paid_t1,
    CASE
      WHEN reference_contract_status = 'Ativo' AND max_delay_contaminated_contract_t2 <= 0 THEN 'active-current'
      WHEN reference_contract_status = 'Finalizado' AND max_delay_contaminated_contract_t2 <= 0 THEN 'ended-current'
      WHEN is_evictions THEN 'evictions'
      WHEN reference_contract_status = 'Ativo' AND has_negotiation_in_contract AND max_delay_contaminated_contract_t1 <= 0 THEN 'active-ongoing-deal'
      WHEN reference_contract_status = 'Ativo'
        AND (n_overdue_monthlys_t1 > 1 OR flag_broken_global_deal)
        THEN 'active-stock-pre-evictions'
      WHEN reference_contract_status = 'Ativo' AND has_fpd_in_wallet_general AND max_delay_contaminated_contract_t2 <= 30 THEN 'active-new-defaulter-first-payment-default'
      WHEN reference_contract_status = 'Ativo' AND mob_months <= 3 AND max_delay_contaminated_contract_t2 <= 30 THEN 'active-new-defaulter-under-mob3'
      WHEN reference_contract_status = 'Ativo' AND (n_days_over1_t2_l180 - 3) <= 0 AND max_delay_contaminated_contract_t2 <= 3 THEN 'active-new-defaulter-special'
      WHEN reference_contract_status = 'Ativo' AND max_delay_contaminated_contract_t2 <= 30 THEN 'active-new-defaulter'
      WHEN reference_contract_status = 'Ativo' AND max_delay_contaminated_contract_t2 > 30 AND n_overdue_monthlys_t1 <= 1 THEN 'active-stock-hold'
      WHEN reference_contract_status = 'Ativo' THEN 'UNCLASSIFIED'
      WHEN reference_contract_status = 'Finalizado' AND has_negotiation_in_contract AND max_delay_contaminated_contract_t1 <= 0 THEN 'ended-ongoing-deal'
      WHEN reference_contract_status = 'Finalizado' AND max_delay_contaminated_contract_t2 <= 30 THEN 'ended-new-defaulter'
      WHEN reference_contract_status = 'Finalizado' AND max_delay_contaminated_contract_t2 > 30 AND max_delay_contaminated_contract_t2 <= 90 THEN 'ended-stock-31to90'
      WHEN reference_contract_status = 'Finalizado' AND max_delay_contaminated_contract_t2 > 90 AND max_delay_contaminated_contract_t2 <= 180 THEN 'ended-stock-91to180'
      WHEN reference_contract_status = 'Finalizado' AND max_delay_contaminated_contract_t2 > 180 AND max_delay_contaminated_contract_t2 <= 360 THEN 'ended-stock-181to360'
      WHEN reference_contract_status = 'Finalizado' AND max_delay_contaminated_contract_t2 > 360 THEN 'ended-stock-361over'
      ELSE 'UNCLASSIFIED'
    END AS macro_segmentation,
    COALESCE(
      LAST_VALUE(payment_probability, TRUE) OVER (
        PARTITION BY id_contract
        ORDER BY dt_reference
      ),
      -1
    ) AS payment_probability_propagated
  FROM derived_features
),
payment_classification AS (
  SELECT
    id_contract,
    dt_reference,
    reference_contract_status,
    max_delay_contaminated_contract_t1,
    max_delay_contaminated_contract_t2,
    n_overdue_monthlys_t1,
    has_negotiation_in_contract,
    is_evictions,
    n_reparos_invoices,
    n_invoices_in_wallet,
    has_fpd_in_wallet_general,
    flag_broken_global_deal,
    has_overdue_balance_over5_t1_at_ending_ffill,
    acc_count_monthly_overdue_invoices_paid_t1,
    pct_monthly_paid_ontime_t1_l12m,
    share_monthly_paid_ontime_t1,
    flag_full_repair,
    flag_broken_deal_by_new_original_debt,
    flag_broken_installment_deal,
    payment_probability,
    payment_probability_propagated,
    mob_months,
    n_evictions_processes_lifetime,
    acc_deals_principal_discount_lifetime,
    n_days_over1_t2_l180,
    avg_days_overdue_invoices_paid_t1,
    macro_segmentation,
    CASE
      WHEN is_evictions THEN
        CASE
          WHEN payment_probability_propagated >= 0.223 THEN 'HIGH'
          WHEN payment_probability_propagated < 0.223 THEN 'LOW'
        END
      WHEN reference_contract_status = 'Ativo' THEN
        CASE
          WHEN max_delay_contaminated_contract_t2 > 30 OR macro_segmentation = 'active-stock-pre-evictions' THEN
            CASE
              WHEN payment_probability_propagated >= 0.38 THEN 'HIGH'
              WHEN payment_probability_propagated < 0.38 THEN 'LOW'
              ELSE 'NULL PROB ACTIVE [31+]'
            END
          WHEN max_delay_contaminated_contract_t2 <= 30 THEN
            CASE
              WHEN (n_days_over1_t2_l180 - 3) <= 0 AND max_delay_contaminated_contract_t2 <= 3 THEN 'VERY_HIGH'
              WHEN payment_probability_propagated >= 0.838 THEN 'HIGH'
              WHEN payment_probability_propagated >= 0.645 THEN 'MEDIUM'
              WHEN payment_probability_propagated < 0.645 THEN 'LOW'
              ELSE 'NULL PROB ACTIVE [1-30]'
            END
        END
      WHEN reference_contract_status = 'Finalizado' THEN
        CASE
          WHEN max_delay_contaminated_contract_t2 <= 30 THEN
            CASE
              WHEN payment_probability_propagated >= 0.7 THEN 'HIGH'
              WHEN payment_probability_propagated < 0.7 THEN 'LOW'
              ELSE 'NULL UNDEFINED'
            END
          WHEN max_delay_contaminated_contract_t2 <= 90 THEN
            CASE
              WHEN n_reparos_invoices = n_invoices_in_wallet THEN 'VERY_LOW'
              WHEN payment_probability_propagated >= 0.186 THEN 'HIGH'
              WHEN payment_probability_propagated < 0.186 THEN 'LOW'
              ELSE 'NULL UNDEFINED'
            END
          WHEN max_delay_contaminated_contract_t2 <= 180 THEN
            CASE
              WHEN n_reparos_invoices = n_invoices_in_wallet THEN 'VERY_LOW'
              WHEN payment_probability_propagated >= 0.091 THEN 'HIGH'
              WHEN payment_probability_propagated < 0.091 THEN 'LOW'
              ELSE 'NULL UNDEFINED'
            END
          WHEN max_delay_contaminated_contract_t2 > 180 THEN
            CASE
              WHEN max_delay_contaminated_contract_t2 <= 360 AND n_reparos_invoices = n_invoices_in_wallet THEN 'VERY_LOW'
              WHEN payment_probability_propagated >= 0.06 THEN 'HIGH'
              WHEN payment_probability_propagated < 0.06 THEN 'LOW'
              ELSE 'NULL UNDEFINED'
            END
        END
      ELSE 'NULL UNDEFINED'
    END AS prob_payment_at_dt_reference
  FROM macro_features
),
macro_island_prep AS (
  SELECT
    id_contract,
    dt_reference,
    reference_contract_status,
    max_delay_contaminated_contract_t1,
    max_delay_contaminated_contract_t2,
    n_overdue_monthlys_t1,
    has_negotiation_in_contract,
    is_evictions,
    has_fpd_in_wallet_general,
    flag_broken_global_deal,
    has_overdue_balance_over5_t1_at_ending_ffill,
    acc_count_monthly_overdue_invoices_paid_t1,
    pct_monthly_paid_ontime_t1_l12m,
    share_monthly_paid_ontime_t1,
    flag_full_repair,
    flag_broken_deal_by_new_original_debt,
    flag_broken_installment_deal,
    payment_probability,
    payment_probability_propagated,
    mob_months,
    acc_deals_principal_discount_lifetime,
    macro_segmentation,
    n_days_over1_t2_l180,
    avg_days_overdue_invoices_paid_t1,
    n_evictions_processes_lifetime,
    prob_payment_at_dt_reference,
    ROW_NUMBER() OVER (PARTITION BY id_contract ORDER BY dt_reference) AS rn_total,
    ROW_NUMBER() OVER (PARTITION BY id_contract, macro_segmentation ORDER BY dt_reference) AS rn_macro
  FROM payment_classification
),
frozen_probability AS (
  SELECT
    id_contract,
    dt_reference,
    reference_contract_status,
    max_delay_contaminated_contract_t1,
    max_delay_contaminated_contract_t2,
    n_overdue_monthlys_t1,
    has_negotiation_in_contract,
    is_evictions,
    has_fpd_in_wallet_general,
    flag_broken_global_deal,
    has_overdue_balance_over5_t1_at_ending_ffill,
    acc_count_monthly_overdue_invoices_paid_t1,
    pct_monthly_paid_ontime_t1_l12m,
    share_monthly_paid_ontime_t1,
    flag_full_repair,
    flag_broken_deal_by_new_original_debt,
    flag_broken_installment_deal,
    payment_probability,
    payment_probability_propagated,
    mob_months,
    acc_deals_principal_discount_lifetime,
    macro_segmentation,
    n_evictions_processes_lifetime,
    n_days_over1_t2_l180,
    avg_days_overdue_invoices_paid_t1,
    rn_total,
    (rn_total - rn_macro) AS macro_island_id,
    ROW_NUMBER() OVER (
      PARTITION BY id_contract, macro_segmentation, (rn_total - rn_macro)
      ORDER BY dt_reference
    ) AS days_in_macro_segmentation,
    CASE
      WHEN macro_segmentation = 'UNCLASSIFIED' THEN NULL
      WHEN macro_segmentation IN ('active-current', 'ended-current') THEN prob_payment_at_dt_reference
      ELSE FIRST_VALUE(prob_payment_at_dt_reference) OVER (
        PARTITION BY id_contract, macro_segmentation, (rn_total - rn_macro)
        ORDER BY dt_reference
      )
    END AS prob_payment,
    CASE
      WHEN macro_segmentation = 'UNCLASSIFIED' THEN NULL
      WHEN macro_segmentation IN ('active-current', 'ended-current') THEN payment_probability_propagated
      ELSE FIRST_VALUE(payment_probability_propagated) OVER (
        PARTITION BY id_contract, macro_segmentation, (rn_total - rn_macro)
        ORDER BY dt_reference
      )
    END AS payment_probability_at_entrance
  FROM macro_island_prep
),
segmentation_features AS (
  SELECT
    id_contract,
    dt_reference,
    payment_probability,
    payment_probability_propagated,
    macro_segmentation,
    reference_contract_status,
    max_delay_contaminated_contract_t2,
    max_delay_contaminated_contract_t1,
    n_overdue_monthlys_t1,
    has_negotiation_in_contract,
    has_fpd_in_wallet_general,
    mob_months,
    prob_payment,
    flag_broken_global_deal,
    days_in_macro_segmentation,
    payment_probability_at_entrance,
    rn_total,
    CASE
      WHEN reference_contract_status = 'Ativo' AND max_delay_contaminated_contract_t2 <= 0 THEN 'active-current'
      WHEN reference_contract_status = 'Finalizado' AND max_delay_contaminated_contract_t2 <= 0 THEN 'ended-current'
      WHEN macro_segmentation = 'evictions' AND days_in_macro_segmentation > 30 THEN 'evictions-late'
      WHEN macro_segmentation = 'evictions' AND payment_probability_at_entrance < 0.223 THEN 'evictions-early-low'
      WHEN macro_segmentation = 'evictions' AND payment_probability_at_entrance >= 0.223 AND n_evictions_processes_lifetime > 1 THEN 'evictions-early-reincident-high'
      WHEN macro_segmentation = 'evictions' AND payment_probability_at_entrance >= 0.223 AND n_evictions_processes_lifetime <= 1 THEN 'evictions-early-first-high'
      WHEN macro_segmentation = 'evictions' THEN 'evictions-undefined'
      WHEN reference_contract_status = 'Ativo' AND has_negotiation_in_contract AND max_delay_contaminated_contract_t1 <= 0 THEN 'active-ongoing-deal'
      WHEN reference_contract_status = 'Ativo' AND macro_segmentation = 'active-stock-pre-evictions' AND flag_broken_global_deal AND flag_broken_deal_by_new_original_debt THEN 'active-stock-risk-deal-new-monthly'
      WHEN reference_contract_status = 'Ativo' AND macro_segmentation = 'active-stock-pre-evictions' AND flag_broken_global_deal AND flag_broken_installment_deal THEN 'active-stock-risk-deal-unpaid'
      WHEN reference_contract_status = 'Ativo' AND macro_segmentation = 'active-stock-pre-evictions' AND NOT flag_broken_global_deal AND prob_payment = 'LOW' THEN 'active-stock-risk-nodeal-low'
      WHEN reference_contract_status = 'Ativo' AND macro_segmentation = 'active-stock-pre-evictions' AND NOT flag_broken_global_deal AND prob_payment IN ('HIGH', 'MEDIUM') THEN 'active-stock-risk-nodeal-high'
      WHEN reference_contract_status = 'Ativo' AND max_delay_contaminated_contract_t2 > 30 AND (n_overdue_monthlys_t1 > 1 OR flag_broken_global_deal) THEN 'active-stock-pre-evictions-legacy'
      WHEN reference_contract_status = 'Ativo' AND has_fpd_in_wallet_general AND max_delay_contaminated_contract_t2 <= 30 THEN 'active-new-defaulter-first-payment-default'
      WHEN reference_contract_status = 'Ativo' AND mob_months <= 3 AND max_delay_contaminated_contract_t2 <= 15 THEN 'active-new-defaulter-under-mob3-early'
      WHEN reference_contract_status = 'Ativo' AND mob_months <= 3 AND max_delay_contaminated_contract_t2 >= 16 AND max_delay_contaminated_contract_t2 <= 30 THEN 'active-new-defaulter-under-mob3-late'
      WHEN reference_contract_status = 'Ativo' AND max_delay_contaminated_contract_t2 <= 30 AND prob_payment = 'VERY_HIGH' THEN 'active-new-defaulter-good-payers'
      WHEN reference_contract_status = 'Ativo' AND prob_payment = 'HIGH' AND max_delay_contaminated_contract_t2 <= 30 THEN 'active-new-defaulter-high'
      WHEN reference_contract_status = 'Ativo' AND prob_payment = 'MEDIUM' AND max_delay_contaminated_contract_t2 <= 30 THEN 'active-new-defaulter-medium'
      WHEN reference_contract_status = 'Ativo' AND prob_payment = 'LOW' AND max_delay_contaminated_contract_t2 <= 4 THEN 'active-new-defaulter-early-low'
      WHEN reference_contract_status = 'Ativo' AND prob_payment = 'LOW' AND max_delay_contaminated_contract_t2 > 4 AND max_delay_contaminated_contract_t2 <= 30 THEN 'active-new-defaulter-late-low'
      WHEN reference_contract_status = 'Ativo' AND max_delay_contaminated_contract_t2 > 30 AND n_overdue_monthlys_t1 <= 1 THEN 'active-stock-hold'
      WHEN reference_contract_status = 'Ativo' THEN 'UNCLASSIFIED-ACTIVE'
      WHEN reference_contract_status = 'Finalizado' AND has_negotiation_in_contract AND max_delay_contaminated_contract_t1 <= 7 THEN 'ended-ongoing-deal'
      WHEN reference_contract_status = 'Finalizado' AND max_delay_contaminated_contract_t2 <= 30 AND prob_payment = 'HIGH' THEN 'ended-new-defaulter-high'
      WHEN reference_contract_status = 'Finalizado' AND max_delay_contaminated_contract_t2 <= 30 AND prob_payment = 'LOW' THEN 'ended-new-defaulter-low'
      WHEN reference_contract_status = 'Finalizado' AND max_delay_contaminated_contract_t2 > 30 AND max_delay_contaminated_contract_t2 <= 90 AND prob_payment = 'HIGH' THEN 'ended-stock-31-90-high'
      WHEN reference_contract_status = 'Finalizado' AND max_delay_contaminated_contract_t2 > 30 AND max_delay_contaminated_contract_t2 <= 90 AND prob_payment = 'LOW' THEN 'ended-stock-31-90-low'
      WHEN reference_contract_status = 'Finalizado' AND max_delay_contaminated_contract_t2 > 30 AND max_delay_contaminated_contract_t2 <= 90 AND prob_payment = 'VERY_LOW' THEN 'ended-stock-31-90-repair'
      WHEN reference_contract_status = 'Finalizado' AND max_delay_contaminated_contract_t2 > 90 AND max_delay_contaminated_contract_t2 <= 180 AND prob_payment = 'HIGH' THEN 'ended-stock-91-180-high'
      WHEN reference_contract_status = 'Finalizado' AND max_delay_contaminated_contract_t2 > 90 AND max_delay_contaminated_contract_t2 <= 180 AND prob_payment = 'LOW' THEN 'ended-stock-91-180-low'
      WHEN reference_contract_status = 'Finalizado' AND max_delay_contaminated_contract_t2 > 90 AND max_delay_contaminated_contract_t2 <= 180 AND prob_payment = 'VERY_LOW' THEN 'ended-stock-91-180-repair'
      WHEN reference_contract_status = 'Finalizado' AND max_delay_contaminated_contract_t2 > 180 AND max_delay_contaminated_contract_t2 <= 360 AND prob_payment = 'HIGH' THEN 'ended-stock-181-360-high'
      WHEN reference_contract_status = 'Finalizado' AND max_delay_contaminated_contract_t2 > 180 AND max_delay_contaminated_contract_t2 <= 360 AND prob_payment = 'LOW' THEN 'ended-stock-181-360-low'
      WHEN reference_contract_status = 'Finalizado' AND max_delay_contaminated_contract_t2 > 180 AND max_delay_contaminated_contract_t2 <= 360 AND prob_payment = 'VERY_LOW' THEN 'ended-stock-181-360-repair'
      WHEN reference_contract_status = 'Finalizado' AND max_delay_contaminated_contract_t2 > 360 AND max_delay_contaminated_contract_t2 <= 1440 THEN 'ended-stock-361-1440'
      WHEN reference_contract_status = 'Finalizado' AND max_delay_contaminated_contract_t2 > 1440 THEN 'ended-stock-over1440'
      WHEN reference_contract_status = 'Finalizado' THEN 'UNCLASSIFIED-ENDED'
      ELSE 'MISTERY'
    END AS segmentation,
    n_evictions_processes_lifetime,
    acc_deals_principal_discount_lifetime,
    n_days_over1_t2_l180,
    avg_days_overdue_invoices_paid_t1,
    has_overdue_balance_over5_t1_at_ending_ffill,
    acc_count_monthly_overdue_invoices_paid_t1,
    pct_monthly_paid_ontime_t1_l12m,
    share_monthly_paid_ontime_t1,
    flag_full_repair,
    flag_broken_deal_by_new_original_debt,
    flag_broken_installment_deal
  FROM frozen_probability
),
micro_island_prep AS (
  SELECT
    id_contract,
    dt_reference,
    payment_probability,
    payment_probability_propagated,
    macro_segmentation,
    payment_probability_at_entrance,
    reference_contract_status,
    max_delay_contaminated_contract_t2,
    prob_payment,
    flag_broken_global_deal,
    has_overdue_balance_over5_t1_at_ending_ffill,
    acc_count_monthly_overdue_invoices_paid_t1,
    pct_monthly_paid_ontime_t1_l12m,
    share_monthly_paid_ontime_t1,
    flag_full_repair,
    flag_broken_deal_by_new_original_debt,
    flag_broken_installment_deal,
    days_in_macro_segmentation,
    rn_total,
    n_evictions_processes_lifetime,
    acc_deals_principal_discount_lifetime,
    n_days_over1_t2_l180,
    avg_days_overdue_invoices_paid_t1,
    segmentation,
    ROW_NUMBER() OVER (PARTITION BY id_contract, segmentation ORDER BY dt_reference) AS rn_micro
  FROM segmentation_features
)
SELECT
  CAST(id_contract AS BIGINT) AS id_contract,
  segmentation,
  macro_segmentation,
  CAST(
    ROW_NUMBER() OVER (
      PARTITION BY id_contract, segmentation, (rn_total - rn_micro)
      ORDER BY dt_reference
    ) AS BIGINT
  ) AS days_in_segmentation,
  CAST(days_in_macro_segmentation AS BIGINT) AS days_in_macro_segmentation,
  payment_probability,
  reference_contract_status,
  max_delay_contaminated_contract_t2,
  prob_payment,
  payment_probability_at_entrance,
  payment_probability_propagated,
  n_evictions_processes_lifetime,
  acc_deals_principal_discount_lifetime,
  n_days_over1_t2_l180,
  avg_days_overdue_invoices_paid_t1,
  has_overdue_balance_over5_t1_at_ending_ffill,
  acc_count_monthly_overdue_invoices_paid_t1,
  pct_monthly_paid_ontime_t1_l12m,
  share_monthly_paid_ontime_t1,
  flag_full_repair,
  flag_broken_global_deal,
  flag_broken_deal_by_new_original_debt,
  flag_broken_installment_deal,
  CASE
    WHEN macro_segmentation IN ('active-new-defaulter-special') THEN 'active-new-defaulter'
    ELSE macro_segmentation
  END AS major_segmentation,
  CASE
    WHEN segmentation IN (
      'active-new-defaulter-first-payment-default',
      'active-new-defaulter-good-payers',
      'active-new-defaulter-under-mob3-early',
      'active-new-defaulter-under-mob3-late',
      'active-new-defaulter-high',
      'active-new-defaulter-medium',
      'active-new-defaulter-early-low',
      'active-new-defaulter-late-low',
      'active-stock-hold',
      'active-stock-risk-deal-unpaid',
      'active-stock-risk-deal-new-monthly',
      'active-stock-risk-nodeal-high',
      'active-stock-risk-nodeal-low',
      'active-ongoing-deal'
    ) THEN 'active-segments'
    WHEN segmentation IN (
      'ended-new-defaulter-high',
      'ended-new-defaulter-low',
      'ended-stock-31-90-high',
      'ended-stock-31-90-low',
      'ended-stock-31-90-repair',
      'ended-stock-91-180-high',
      'ended-stock-91-180-low',
      'ended-stock-91-180-repair',
      'ended-stock-181-360-high',
      'ended-stock-181-360-low',
      'ended-stock-181-360-repair',
      'ended-stock-361-1440',
      'ended-stock-over1440',
      'ended-ongoing-deal'
    ) THEN 'ended-segments'
    WHEN macro_segmentation IN ('evictions') THEN 'evictions'
    ELSE segmentation
  END AS hyper_segmentation,
  CASE
    WHEN segmentation IN (
      'active-new-defaulter-under-mob3-early',
      'active-new-defaulter-under-mob3-late'
    ) THEN 'active-new-defaulter-under-mob3'
    WHEN segmentation IN (
      'active-new-defaulter-early-low',
      'active-new-defaulter-late-low'
    ) THEN 'active-new-defaulter-low'
    WHEN segmentation IN ('active-new-defaulter-good-payers') THEN 'active-new-defaulter-high'
    WHEN segmentation IN (
      'active-stock-risk-deal-unpaid',
      'active-stock-risk-deal-new-monthly'
    ) THEN 'active-stock-risk-deal'
    WHEN segmentation IN (
      'active-stock-risk-nodeal-high',
      'active-stock-risk-nodeal-low'
    ) THEN 'active-stock-risk-nodeal'
    ELSE segmentation
  END AS clustered_segmentation,
  dt_reference,
  YEAR(dt_reference) AS year,
  MONTH(dt_reference) AS month,
  DAY(dt_reference) AS day,
  NOW() AS ts_load
FROM micro_island_prep
WHERE
  dt_reference >= DATE('{load_start_date}')
  AND dt_reference <= DATE('{load_end_date}')
