WITH aux_calendar AS (
    SELECT
        d.sk_date,
        d.month_start,
        d.month_end,
        d.date,
        d.quarter,
        d.weekend,
        d.is_brz_holiday,
        CASE WHEN d.date BETWEEN DATE('2025-12-22') AND DATE('2026-01-02') THEN True ELSE False END AS arbitration_recess,
        CASE WHEN d.date BETWEEN DATE('2025-12-20') and DATE('2026-01-19') THEN True ELSE False END AS judicial_recess
    FROM DW_public.dim_date AS d
        WHERE d.month_start <= DATE(DATE_TRUNC('month',CURRENT_DATE()))
)

SELECT DISTINCT
    e.id_process AS sk_process,
    e.contract AS sk_contract,
    e.id_court_case,
    e.id_anonymized,
    e.id_contract_cyber,
    'cyber_legal' AS source,
    e.process,
    e.input_type,
    e.action_type,
    e.action,
    e.office,
    e.collection_agency,
    e.chamber,
    e.region,
    e.city,
    e.contract_status,
    e.cyber_status,
    e.last_stage,
    e.arbitral_distribution_expense_amount,
    e.arbitral_citation_expense_amount,
    e.arbitral_sentence_expense_amount,
    e.judiciary_distribution_expense_amount,
    e.judicial_summons_decision_expense_amount,
    e.judicial_summons_expense_amount,
    e.coercive_decision_expense_amount,
    e.coercive_issuance_expense_amount,
    e.judicial_petition_expense_amount,
    e.possession_imission_decision_expense_amount,
    e.possession_imission_issuance_expense_amount,
    e.execution_requirement_expense_amount,
    e.prejudgment_attachment_expense_amount,
    e.execution_citation_expense_amount,
    e.asset_attachment_expense_amount,
    e.asset_evaluation_expense_amount,
    e.credit_satisfaction_expense_amount,
    e.passage_status,
    e.procedure,
    e.consolidated_reason,
    e.standardized_reason,
    e.result,
    CASE
        WHEN cwt.open_wallet_overdue_t1 IS NULL THEN 'Adimplente'
        WHEN cwt.has_fpd_in_wallet = True THEN 'FPD'
        WHEN cwt.open_acordo_balance > 0 THEN 'Acordo Ativo'
        WHEN cwt.n_monthly_invoices > 0 THEN 'Mensal'
        WHEN cwt.open_wallet_overdue_t1 IS NOT NULL THEN 'Demais Inadimplentes'
        ELSE 'Outros'
    END AS contract_category_at_registration,
    cwt.max_delay_original_invoices_t1 AS overdue_days_at_registration,
    e.succumbency_fee,
    cwt.package_amount AS total_package,
    cwt.wallet_overdue_t1 AS total_due_amount,
    e.ldt_stock,
    e.stock_range,
    e.ldt_resolution,
    e.resolution_range,
    e.ldt_coercive,
    e.last_occurrence,
    DATE_DIFF(DAY, DATE(e.dt_registered), e.dt_closure) AS real_ldt_resolution,
        --leadtimes despejo
    COUNT(DISTINCT
        CASE
            WHEN DATE(e.dt_registered) <= d.date AND DATE(e.dt_registered) IS NOT NULL
            AND d.is_brz_holiday = "No holiday" AND d.weekend = 'Weekday' AND d.arbitration_recess = False
            AND(
              (DATE(e.dt_arbitral_distribution_start) IS NOT NULL AND DATE(e.dt_arbitral_distribution_start) >= d.date) OR
              (DATE(e.dt_arbitral_distribution_start) IS NULL AND CURRENT_DATE() >= d.date)
              ) THEN d.sk_date END) AS ldt_arbitral_distribution,
    COUNT(DISTINCT
            CASE
                WHEN DATE(e.dt_arbitral_distribution_start) <= d.date AND DATE(e.dt_arbitral_distribution_start) IS NOT NULL
                AND d.is_brz_holiday = "No holiday" AND d.weekend = 'Weekday' AND d.arbitration_recess = False
                AND(
                  (DATE(e.dt_arbitral_citation_start) IS NOT NULL AND DATE(e.dt_arbitral_citation_start) >= d.date) OR
                  (DATE(e.dt_arbitral_citation_start) IS NULL AND CURRENT_DATE() >= d.date)
                  ) THEN d.sk_date END) AS ldt_arbitral_citation,
    COUNT(DISTINCT
            CASE
                WHEN DATE(e.dt_arbitral_distribution_start) <= d.date AND DATE(e.dt_arbitral_distribution_start) IS NOT NULL
                AND d.is_brz_holiday = "No holiday" AND d.weekend = 'Weekday' AND d.arbitration_recess = False
                AND(
                  (DATE(e.dt_arbitral_sentence_start) IS NOT NULL AND DATE(e.dt_arbitral_sentence_start) >= d.date) OR
                  (DATE(e.dt_arbitral_sentence_start) IS NULL AND CURRENT_DATE() >= d.date)
                  ) THEN d.sk_date END) AS ldt_arbitral_award,
    COUNT(DISTINCT
            CASE
                WHEN DATE(e.dt_arbitral_sentence_start) <= d.date AND DATE(e.dt_arbitral_sentence_start) IS NOT NULL
                AND d.is_brz_holiday = "No holiday" AND d.weekend = 'Weekday' AND d.arbitration_recess = False
                AND(
                  (DATE(e.dt_judiciary_distribution_start) IS NOT NULL AND DATE(e.dt_judiciary_distribution_start) >= d.date) OR
                  (DATE(e.dt_judiciary_distribution_start) IS NULL AND CURRENT_DATE() >= d.date)
                  ) THEN d.sk_date END) AS ldt_judiciary_distribution,
    COUNT(DISTINCT
            CASE
                WHEN DATE(e.dt_judiciary_distribution_start) <= d.date AND DATE(e.dt_judiciary_distribution_start) IS NOT NULL
                AND d.is_brz_holiday = "No holiday" AND d.weekend = 'Weekday' AND d.arbitration_recess = False
                AND(
                  (DATE(e.dt_judicial_summons_decision_start) IS NOT NULL AND DATE(e.dt_judicial_summons_decision_start) >= d.date) OR
                  (DATE(e.dt_judicial_summons_decision_start) IS NULL AND CURRENT_DATE() >= d.date)
                  ) THEN d.sk_date END) AS ldt_judicial_summons_decision,
    COUNT(DISTINCT
            CASE
                WHEN DATE(e.dt_judicial_summons_decision_start) <= d.date AND DATE(e.dt_judicial_summons_decision_start) IS NOT NULL
                AND d.is_brz_holiday = "No holiday" AND d.weekend = 'Weekday' AND d.arbitration_recess = False
                AND(
                  (DATE(e.dt_judicial_summons_start) IS NOT NULL AND DATE(e.dt_judicial_summons_start) >= d.date) OR
                  (DATE(e.dt_judicial_summons_start) IS NULL AND CURRENT_DATE() >= d.date)
                  ) THEN d.sk_date END) AS ldt_judicial_summons,
    COUNT(DISTINCT
            CASE
                WHEN DATE(e.dt_judicial_summons_decision_start) <= d.date AND DATE(e.dt_judicial_summons_decision_start) IS NOT NULL
                AND d.is_brz_holiday = "No holiday" AND d.weekend = 'Weekday' AND d.arbitration_recess = False
                AND(
                  (DATE(e.dt_coercive_decision_start) IS NOT NULL AND DATE(e.dt_coercive_decision_start) >= d.date) OR
                  (DATE(e.dt_coercive_decision_start) IS NULL AND CURRENT_DATE() >= d.date)
                  ) THEN d.sk_date END) AS ldt_coercive_decision,
    COUNT(DISTINCT
            CASE
                WHEN DATE(e.dt_coercive_decision_start) <= d.date AND DATE(e.dt_coercive_decision_start) IS NOT NULL
                AND d.is_brz_holiday = "No holiday" AND d.weekend = 'Weekday' AND d.arbitration_recess = False
                AND(
                  (DATE(e.dt_coercive_issuance_start) IS NOT NULL AND DATE(e.dt_coercive_issuance_start) >= d.date) OR
                  (DATE(e.dt_coercive_issuance_start) IS NULL AND CURRENT_DATE() >= d.date)
                  ) THEN d.sk_date END) AS ldt_coercive_order_issuance_decision,
    --leadtimes reivindicatoria
    COUNT(DISTINCT
            CASE
                WHEN DATE(e.dt_judicial_summons_start) <= d.date AND DATE(e.dt_judicial_summons_start) IS NOT NULL
                AND d.is_brz_holiday = "No holiday" AND d.weekend = 'Weekday' AND d.arbitration_recess = False
                AND(
                  (DATE(e.dt_possession_imission_decision_start) IS NOT NULL AND DATE(e.dt_possession_imission_decision_start) >= d.date) OR
                  (DATE(e.dt_possession_imission_decision_start) IS NULL AND CURRENT_DATE() >= d.date)
                  ) THEN d.sk_date END) AS ldt_possesion_imission_decisions,
    COUNT(DISTINCT
            CASE
                WHEN DATE(e.dt_possession_imission_decision_start) <= d.date AND DATE(e.dt_possession_imission_decision_start) IS NOT NULL
                AND d.is_brz_holiday = "No holiday" AND d.weekend = 'Weekday' AND d.arbitration_recess = False
                AND(
                  (DATE(e.dt_possession_imission_issuance_start) IS NOT NULL AND DATE(e.dt_possession_imission_issuance_start) >= d.date) OR
                  (DATE(e.dt_possession_imission_issuance_start) IS NULL AND CURRENT_DATE() >= d.date)
                  ) THEN d.sk_date END) AS ldt_possesion_imission_issuance,
    COUNT(DISTINCT
            CASE
                WHEN DATE(e.dt_possession_imission_issuance_start) <= d.date AND DATE(e.dt_possession_imission_issuance_start) IS NOT NULL
                AND d.is_brz_holiday = "No holiday" AND d.weekend = 'Weekday' AND d.arbitration_recess = False
                AND(
                  (DATE(e.dt_judicial_petition_start) IS NOT NULL AND DATE(e.dt_judicial_petition_start) >= d.date) OR
                  (DATE(e.dt_judicial_petition_start) IS NULL AND CURRENT_DATE() >= d.date)
                  ) THEN d.sk_date END) AS ldt_judicial_petition,
    --leadtimes execucao
    COUNT(DISTINCT
            CASE
                WHEN DATE(e.dt_registered) <= d.date AND DATE(e.dt_registered) IS NOT NULL
                AND d.is_brz_holiday = "No holiday" AND d.weekend = 'Weekday' AND d.arbitration_recess = False
                AND(
                  (DATE(e.dt_execution_requirement_start) IS NOT NULL AND DATE(e.dt_execution_requirement_start) >= d.date) OR
                  (DATE(e.dt_execution_requirement_start) IS NULL AND CURRENT_DATE() >= d.date)
                  ) THEN d.sk_date END) AS ldt_execution_requirement_decision,
    COUNT(DISTINCT
            CASE
                WHEN DATE(e.dt_execution_requirement_start) <= d.date AND DATE(e.dt_execution_requirement_start) IS NOT NULL
                AND d.is_brz_holiday = "No holiday" AND d.weekend = 'Weekday' AND d.arbitration_recess = False
                AND(
                  (DATE(e.dt_prejudgment_attachment_start) IS NOT NULL AND DATE(e.dt_prejudgment_attachment_start) >= d.date) OR
                  (DATE(e.dt_prejudgment_attachment_start) IS NULL AND CURRENT_DATE() >= d.date)
                  ) THEN d.sk_date END) AS ldt_prejudgment_attachment,
    COUNT(DISTINCT
            CASE
                WHEN DATE(e.dt_prejudgment_attachment_start) <= d.date AND DATE(e.dt_prejudgment_attachment_start) IS NOT NULL
                AND d.is_brz_holiday = "No holiday" AND d.weekend = 'Weekday' AND d.arbitration_recess = False
                AND(
                  (DATE(e.dt_execution_citation_start) IS NOT NULL AND DATE(e.dt_execution_citation_start) >= d.date) OR
                  (DATE(e.dt_execution_citation_start) IS NULL AND CURRENT_DATE() >= d.date)
                  ) THEN d.sk_date END) AS ldt_executed_citation,
    COUNT(DISTINCT
            CASE
                WHEN DATE(e.dt_execution_citation_start) <= d.date AND DATE(e.dt_execution_citation_start) IS NOT NULL
                AND d.is_brz_holiday = "No holiday" AND d.weekend = 'Weekday' AND d.arbitration_recess = False
                AND(
                  (DATE(e.dt_asset_attachment_start) IS NOT NULL AND DATE(e.dt_asset_attachment_start) >= d.date) OR
                  (DATE(e.dt_asset_attachment_start) IS NULL AND CURRENT_DATE() >= d.date)
                  ) THEN d.sk_date END) AS ldt_asset_attachment,
    COUNT(DISTINCT
            CASE
                WHEN DATE(e.dt_asset_attachment_start) <= d.date AND DATE(e.dt_asset_attachment_start) IS NOT NULL
                AND d.is_brz_holiday = "No holiday" AND d.weekend = 'Weekday' AND d.arbitration_recess = False
                AND(
                  (DATE(e.dt_asset_evaluation_start) IS NOT NULL AND DATE(e.dt_asset_evaluation_start) >= d.date) OR
                  (DATE(e.dt_asset_evaluation_start) IS NULL AND CURRENT_DATE() >= d.date)
                  ) THEN d.sk_date END) AS ldt_asset_evaluation,
    COUNT(DISTINCT
            CASE
                WHEN DATE(e.dt_asset_evaluation_start) <= d.date AND DATE(e.dt_asset_evaluation_start) IS NOT NULL
                AND d.is_brz_holiday = "No holiday" AND d.weekend = 'Weekday' AND d.arbitration_recess = False
                AND(
                  (DATE(e.dt_credit_satisfaction_start) IS NOT NULL AND DATE(e.dt_credit_satisfaction_start) >= d.date) OR
                  (DATE(e.dt_credit_satisfaction_start) IS NULL AND CURRENT_DATE() >= d.date)
                  ) THEN d.sk_date END) AS ldt_redit_satisfaction,
    e.has_arbitration_defense,
    e.has_redistribution,
    e.is_reincident,
    e.dt_registered,
    e.dt_arbitral_distribution_start,
    e.dt_arbitral_distribution_end,
    e.dt_arbitral_citation_start,
    e.dt_arbitral_citation_end,
    e.dt_arbitral_contestation,
    e.dt_arbitral_sentence_start,
    e.dt_arbitral_sentence_end,
    e.dt_judiciary_pre_registration,
    e.dt_judiciary_distribution_start,
    e.dt_judiciary_distribution_end,
    e.dt_judicial_summons_decision_start,
    e.dt_judicial_summons_decision_end,
    e.dt_judicial_summons_start,
    e.dt_judicial_summons_end,
    e.dt_judicial_defense,
    e.dt_coercive_decision_start,
    e.dt_coercive_decision_end,
    e.dt_coercive_issuance_start,
    e.dt_coercive_issuance_end,
    e.dt_judicial_petition_start,
    e.dt_judicial_petition_end,
    e.dt_possession_imission_decision_start,
    e.dt_possession_imission_decision_end,
    e.dt_possession_imission_issuance_start,
    e.dt_possession_imission_issuance_end,
    e.dt_execution_requirement_start,
    e.dt_execution_requirement_end,
    e.dt_prejudgment_attachment_start,
    e.dt_prejudgment_attachment_end,
    e.dt_execution_citation_start,
    e.dt_execution_citation_end,
    e.dt_asset_attachment_start,
    e.dt_asset_attachment_end,
    e.dt_asset_evaluation_start,
    e.dt_asset_evaluation_end,
    e.dt_credit_satisfaction_start,
    e.dt_credit_satisfaction_end,
    e.dt_closure,
    e.ts_updated,
    NOW() AS ts_load
FROM
    datalake_cyber_legal_homolog.evictions_base e
LEFT JOIN
    dw_collections_segmentation.fact_contract_wallet_timeline cwt
    ON e.contract = cwt.sk_contract
    AND e.dt_registered = cwt.dt_reference
LEFT JOIN
    aux_calendar d
    ON e.dt_registered <= d.date AND (e.dt_closure >= d.date OR e.dt_closure IS NULL)
GROUP BY ALL
