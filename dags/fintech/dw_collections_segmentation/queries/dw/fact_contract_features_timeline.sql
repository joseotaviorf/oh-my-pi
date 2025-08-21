WITH
contract_info AS (
    SELECT
        c.sk_contract,
        ROUND(SUM(p.monthly_income), 2) AS monthly_income
    FROM dw_rent.dim_contract c
    LEFT JOIN dw_rent.fact_listing_rent_flows f ON c.sk_contract = f.sk_contract
    LEFT JOIN datalake_sorting_hat_clean.proponent p ON p.id_proposal = f.sk_proposal
    WHERE f.sk_contract <> -1
      AND p.is_going_to_reside = TRUE
    GROUP BY c.sk_contract
),
essential_features AS (
    SELECT
        id_contract,
        dt_reference,
        reference_contract_status,
        max_delay_contaminated_contract_t1,
        max_delay_contaminated_contract_t2,
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
        array_negotiated_invoices
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
),
calculate_avg_days_overdue_invoice_paid_t1 AS (
    SELECT
        *,
        CASE
            WHEN acc_count_monthly_overdue_invoices_paid_t1 = 0 THEN 0
            ELSE acc_sum_monthly_overdue_days_paid_t1 / acc_count_monthly_overdue_invoices_paid_t1
        END AS avg_days_overdue_invoices_paid_t1
    FROM contract_features_with_acc

),
segmentation_features AS (
    SELECT
        f.*,
        c.monthly_income,
        CASE
            WHEN reference_contract_status = 'Ativo'
                AND max_delay_contaminated_contract_t1 <= 1
                AND COALESCE(avgd.avg_days_overdue_invoices_paid_t1, 0) <= 5
            THEN 'af - ALTA'
            WHEN reference_contract_status = 'Ativo'
                AND max_delay_contaminated_contract_t1 <= 1
                AND COALESCE(avgd.avg_days_overdue_invoices_paid_t1, 0) <= 20
            THEN 'af - MEDIA'
            WHEN reference_contract_status = 'Ativo'
                AND max_delay_contaminated_contract_t1 <= 1
                AND COALESCE(avgd.avg_days_overdue_invoices_paid_t1, 0) > 20
            THEN 'af - BAIXA'
            WHEN reference_contract_status = 'Ativo'
                AND max_delay_contaminated_contract_t1 > 30
            THEN 'UNDEFINED'
            WHEN reference_contract_status = 'Finalizado'
                AND max_delay_contaminated_contract_t1 <= 29
                AND COALESCE(avgd.avg_days_overdue_invoices_paid_t1, 0) <= 11
                AND days_since_ending <= 30
            THEN 'F1-30 - ALTA'
            WHEN reference_contract_status = 'Finalizado'
                AND max_delay_contaminated_contract_t1 <= 29
                AND COALESCE(avgd.avg_days_overdue_invoices_paid_t1, 0) <= 11
                AND days_since_ending > 30
                AND COALESCE(monthly_income, 0) <= 8100
            THEN 'F1-30 - BAIXA'
            WHEN reference_contract_status = 'Finalizado'
                AND max_delay_contaminated_contract_t1 <= 29
                AND COALESCE(avgd.avg_days_overdue_invoices_paid_t1, 0) <= 11
                AND days_since_ending > 30
                AND COALESCE(monthly_income, 0) > 8100
            THEN 'F1-30 - MEDIA'
            WHEN reference_contract_status = 'Finalizado'
                AND max_delay_contaminated_contract_t1 <= 29
                AND COALESCE(avgd.avg_days_overdue_invoices_paid_t1, 0) > 11
                AND acc_max_n_repairs = 0
                AND acc_broken_multiple_deals_lifetime = 0
            THEN 'F1-30 - MEDIA'
            WHEN reference_contract_status = 'Finalizado'
                AND max_delay_contaminated_contract_t1 <= 29
                AND COALESCE(avgd.avg_days_overdue_invoices_paid_t1, 0) > 11
                AND acc_max_n_repairs = 0
                AND acc_broken_multiple_deals_lifetime > 0
            THEN 'F1-30 - BAIXA'
            WHEN reference_contract_status = 'Finalizado'
                AND max_delay_contaminated_contract_t1 <= 29
                AND COALESCE(avgd.avg_days_overdue_invoices_paid_t1, 0) > 11
                AND acc_max_n_repairs > 0
            THEN 'F1-30 - BAIXA'
            WHEN reference_contract_status = 'Finalizado'
                AND max_delay_contaminated_contract_t1 >= 30
                AND max_delay_contaminated_contract_t1 <= 90
                AND COALESCE(avgd.avg_days_overdue_invoices_paid_t1, 0) <= 25
                AND acc_cpc_l90 = 0
                AND has_overdue_balance_over5_t1_at_ending_ffill = 0
            THEN 'F30-90 - BAIXA'
            WHEN reference_contract_status = 'Finalizado'
                AND max_delay_contaminated_contract_t1 >= 30
                AND max_delay_contaminated_contract_t1 <= 90
                AND COALESCE(avg_days_overdue_invoices_paid_t1, 0) <= 25
                AND acc_cpc_l90 = 0
                AND has_overdue_balance_over5_t1_at_ending_ffill > 0
                AND max_delay_contaminated_contract_t1 <= 59
            THEN 'F30-90 - BAIXA'
            WHEN reference_contract_status = 'Finalizado'
                AND max_delay_contaminated_contract_t1 >= 30
                AND max_delay_contaminated_contract_t1 <= 90
                AND COALESCE(avg_days_overdue_invoices_paid_t1, 0) <= 25
                AND acc_cpc_l90 = 0
                AND has_overdue_balance_over5_t1_at_ending_ffill > 0
                AND max_delay_contaminated_contract_t1 >= 60
            THEN 'F30-90 - BAIXISSIMA'
            WHEN reference_contract_status = 'Finalizado'
                AND max_delay_contaminated_contract_t1 >= 30
                AND max_delay_contaminated_contract_t1 <= 90
                AND COALESCE(avg_days_overdue_invoices_paid_t1, 0) <= 25
                AND acc_cpc_l90 > 0
                AND has_overdue_balance_over0_t1_at_ending_ffill = 0
            THEN 'F30-90 - MEDIA'
            WHEN reference_contract_status = 'Finalizado'
                AND max_delay_contaminated_contract_t1 >= 30
                AND max_delay_contaminated_contract_t1 <= 90
                AND COALESCE(avg_days_overdue_invoices_paid_t1, 0) <= 25
                AND acc_cpc_l90 > 0
                AND has_overdue_balance_over0_t1_at_ending_ffill > 0
                AND has_overdue_balance_over5_t1_at_ending_ffill = 0
            THEN 'F30-90 - ALTA'
            WHEN reference_contract_status = 'Finalizado'
                AND max_delay_contaminated_contract_t1 >= 30
                AND max_delay_contaminated_contract_t1 <= 90
                AND COALESCE(avg_days_overdue_invoices_paid_t1, 0) <= 25
                AND acc_cpc_l90 > 0
                AND has_overdue_balance_over0_t1_at_ending_ffill > 0
                AND has_overdue_balance_over5_t1_at_ending_ffill > 0
            THEN 'F30-90 - BAIXA'
            WHEN reference_contract_status = 'Finalizado'
                AND max_delay_contaminated_contract_t1 >= 30
                AND max_delay_contaminated_contract_t1 <= 90
                AND COALESCE(avg_days_overdue_invoices_paid_t1, 0) > 25
                AND n_evictions_processes_lifetime <= 0
                AND acc_max_n_repairs = 0
            THEN 'F30-90 - ALTA'
            WHEN reference_contract_status = 'Finalizado'
                AND max_delay_contaminated_contract_t1 >= 30
                AND max_delay_contaminated_contract_t1 <= 90
                AND COALESCE(avg_days_overdue_invoices_paid_t1, 0) > 25
                AND n_evictions_processes_lifetime <= 0
                AND acc_max_n_repairs > 0
            THEN 'F30-90 - MEDIA'
            WHEN reference_contract_status = 'Finalizado'
                AND max_delay_contaminated_contract_t1 >= 30
                AND max_delay_contaminated_contract_t1 <= 90
                AND COALESCE(avg_days_overdue_invoices_paid_t1, 0) > 25
                AND n_evictions_processes_lifetime > 0
            THEN 'F30-90 - MEDIA'
            ELSE NULL
        END AS segments_risk,
        CASE
            WHEN max_delay_contaminated_contract_t1 <= 0 THEN 'a. Current'
            WHEN max_delay_contaminated_contract_t1 <= 30 THEN 'b. 1-30'
            WHEN max_delay_contaminated_contract_t1 <= 60 THEN 'c. 31-60'
            WHEN max_delay_contaminated_contract_t1 <= 90 THEN 'd. 61-90'
            WHEN max_delay_contaminated_contract_t1 <= 180 THEN 'g. 91-180'
            ELSE 'h. acima de 180'
        END AS t1_delay_bucket,
        CASE
            WHEN max_delay_contaminated_contract_t2 <= 0 THEN 'a. Current'
            WHEN max_delay_contaminated_contract_t2 <= 30 THEN 'b. 1-30'
            WHEN max_delay_contaminated_contract_t2 <= 60 THEN 'c. 31-60'
            WHEN max_delay_contaminated_contract_t2 <= 90 THEN 'd. 61-90'
            WHEN max_delay_contaminated_contract_t2 <= 180 THEN 'g. 91-180'
            ELSE 'h. acima de 180'
        END AS t2_delay_bucket,
        CASE
            WHEN is_blocklisted THEN 'BLOCKLIST'
            WHEN max_delay_contaminated_contract_t2 <= 0 AND reference_contract_status = 'Ativo' THEN 'ACTIVE - CURRENT'
            WHEN max_delay_contaminated_contract_t2 <= 0 AND reference_contract_status = 'Finalizado' THEN 'ENDED - CURRENT'
            WHEN days_since_contract_start <= 35 THEN 'FPD'
            WHEN COALESCE(is_evictions, FALSE) = TRUE THEN 'EVEX'
            WHEN reference_contract_status = 'Finalizado' AND max_delay_contaminated_contract_t2 >= 90 THEN 'TITANIC ENDED'
            WHEN max_delay_contaminated_contract_t2 <= 15 AND n_anchor_invoices_not_negativable = 0 AND reference_contract_status = 'Ativo' THEN 'NEW DEFAULTER - ACTIVE'
            WHEN max_delay_contaminated_contract_t2 <= 15 AND n_anchor_invoices_not_negativable = 0 AND reference_contract_status = 'Finalizado' THEN 'NEW DEFAULTER - ENDED'
            WHEN max_delay_contaminated_contract_t2 <= 15 AND n_anchor_invoices_not_negativable > 0 THEN 'NEW DEFAULTER - NEFN'
            WHEN reference_contract_status = 'Ativo' AND max_delay_contaminated_contract_t2 > 15 AND n_anchor_invoices_not_negativable > 0 THEN 'OVER 15 - ACTIVE - NEFN'
            WHEN reference_contract_status = 'Finalizado' AND max_delay_contaminated_contract_t2 < 90 AND n_anchor_invoices_not_negativable = 0 THEN 'SINKING ENDED'
            WHEN reference_contract_status = 'Finalizado' AND max_delay_contaminated_contract_t2 < 90 AND n_anchor_invoices_not_negativable > 0 THEN 'SINKING ENDED - NEFN'
            ELSE NULL
        END AS segment_comms
    FROM
        contract_features_with_acc AS f
    LEFT JOIN
        contract_info AS c
            ON c.sk_contract = f.id_contract
    LEFT JOIN
        calculate_avg_days_overdue_invoice_paid_t1 AS avgd
            ON avgd.id_contract = f.id_contract
                AND avgd.dt_reference = f.dt_reference
),
forward_fill_features AS (
    SELECT
        *,
        LAST_VALUE(segments_risk, TRUE) OVER (
            PARTITION BY id_contract
            ORDER BY dt_reference
            ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
        ) AS segments_risk_ffill,
        LAST_VALUE(segment_comms, TRUE) OVER (
            PARTITION BY id_contract
            ORDER BY dt_reference
            ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
        ) AS segment_comms_ffill

    FROM segmentation_features
)
SELECT
    f.id_contract,
    f.dt_reference,
    f.reference_contract_status,
    f.max_delay_contaminated_contract_t1,
    f.max_delay_contaminated_contract_t2,
    f.sum_monthly_overdue_days_paid_t1,
    f.count_monthly_overdue_invoices_paid_t1,
    f.days_since_ending,
    f.days_since_contract_start,
    f.n_reparos_invoices,
    f.cpc,
    f.qt_acordo_quebrado,
    f.id_process_evictions,
    f.has_overdue_balance_over0_t1_at_ending,
    f.has_overdue_balance_over5_t1_at_ending,
    f.has_overdue_balance_over0_t2_at_ending,
    f.has_overdue_balance_over5_t2_at_ending,
    f.has_overdue_balance_over0_t3_at_ending,
    f.has_overdue_balance_over5_t3_at_ending,
    f.is_evictions,
    f.is_blocklisted,
    f.n_anchor_invoices_not_negativable,
    f.array_open_invoices,
    f.array_paid_invoices,
    f.array_negotiated_invoices,
    f.acc_max_n_repairs,
    f.acc_cpc_l90,
    f.acc_broken_multiple_deals_lifetime,
    f.n_evictions_processes_lifetime,
    f.has_overdue_balance_over0_t1_at_ending_ffill,
    f.has_overdue_balance_over5_t1_at_ending_ffill,
    f.acc_count_monthly_overdue_invoices_paid_t1,
    f.acc_sum_monthly_overdue_days_paid_t1,
    f.avg_days_overdue_invoices_paid_t1, -- na media de faturas atrasadas em t1 quantos dias ela demora pra ser paga.
    f.monthly_income,
    f.segments_risk,
    f.segments_risk_ffill,
    f.t1_delay_bucket,
    f.t2_delay_bucket,
    f.segment_comms,
    f.segment_comms_ffill,
    NOW() AS ts_load
FROM forward_fill_features AS f
