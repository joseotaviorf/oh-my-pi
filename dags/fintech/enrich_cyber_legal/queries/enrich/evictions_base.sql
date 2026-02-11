WITH
get_process_stages AS (
    SELECT DISTINCT
        id_case,
        stage_description,
        expense_amount,
        dt_start,
        dt_end
    FROM datalake_cyber_legal_homolog.process_stages
),
get_last_process_stage AS (
    SELECT
        id_case,
        stage_description
    FROM datalake_cyber_legal_homolog.process_stages
    WHERE dt_start IS NOT NULL
    QUALIFY ROW_NUMBER() OVER(PARTITION BY id_case ORDER BY stage_order DESC) = 1
),
get_stages_data AS (
    SELECT
        id_case,
        stage_distribuicao_arbitral_expense_amount,
        stage_distribuicao_arbitral_dt_start,
        stage_distribuicao_arbitral_dt_end,

        stage_citacao_arbitral_expense_amount,
        stage_citacao_arbitral_dt_start,
        stage_citacao_arbitral_dt_end,

        stage_sentenca_arbitral_expense_amount,
        stage_sentenca_arbitral_dt_start,
        stage_sentenca_arbitral_dt_end,

        stage_distribuicao_judicial_expense_amount,
        stage_distribuicao_judicial_dt_start,
        stage_distribuicao_judicial_dt_end,

        stage_decisao_citacao_judicial_expense_amount,
        stage_decisao_citacao_judicial_dt_start,
        stage_decisao_citacao_judicial_dt_end,

        stage_citacao_judicial_expense_amount,
        stage_citacao_judicial_dt_start,
        stage_citacao_judicial_dt_end,

        stage_decisao_coercitivo_expense_amount,
        stage_decisao_coercitivo_dt_start,
        stage_decisao_coercitivo_dt_end,

        stage_emissao_coercitivo_expense_amount,
        stage_emissao_coercitivo_dt_start,
        stage_emissao_coercitivo_dt_end,

        stage_peticao_judicial_expense_amount,
        stage_peticao_judicial_dt_start,
        stage_peticao_judicial_dt_end,

        stage_decisao_imissao_posse_expense_amount,
        stage_decisao_imissao_posse_dt_start,
        stage_decisao_imissao_posse_dt_end,

        stage_emissao_imissao_posse_expense_amount,
        stage_emissao_imissao_posse_dt_start,
        stage_emissao_imissao_posse_dt_end,

        stage_requerimento_execucao_expense_amount,
        stage_requerimento_execucao_dt_start,
        stage_requerimento_execucao_dt_end,

        stage_arresto_cautelar_expense_amount,
        stage_arresto_cautelar_dt_start,
        stage_arresto_cautelar_dt_end,

        stage_citacao_execucao_expense_amount,
        stage_citacao_execucao_dt_start,
        stage_citacao_execucao_dt_end,

        stage_penhora_expense_amount,
        stage_penhora_dt_start,
        stage_penhora_dt_end,

        stage_avaliacao_bens_expense_amount,
        stage_avaliacao_bens_dt_start,
        stage_avaliacao_bens_dt_end,

        stage_satisfacao_credito_expense_amount,
        stage_satisfacao_credito_dt_start,
        stage_satisfacao_credito_dt_end

    FROM get_process_stages
        PIVOT(
            SUM(COALESCE(expense_amount,0)) AS expense_amount,
            MAX(dt_start) AS dt_start,
            MAX(dt_end) AS dt_end
            FOR stage_description IN (
            'Distribuicao Arbitral' AS stage_distribuicao_arbitral,
            'Citacao Arbitral' AS stage_citacao_arbitral,
            'Sentenca Arbitral' AS stage_sentenca_arbitral,
            'Distribuicao Judicial' AS stage_distribuicao_judicial,
            'Decisao de Citacao Judicial' AS stage_decisao_citacao_judicial,
            'Citacao Judicial' AS stage_citacao_judicial,
            'Decisao Coercitivo' AS stage_decisao_coercitivo,
            'Emissao Coercitivo' AS stage_emissao_coercitivo,

            'Peticao Judicial' AS stage_peticao_judicial,
            'Decisao Imissao na Posse' AS stage_decisao_imissao_posse,
            'Emissao Imissao na Posse' AS stage_emissao_imissao_posse,
            'Requerimento da Execucao' AS stage_requerimento_execucao,
            'Arresto Cautelar' AS stage_arresto_cautelar,
            'Citacao do Executado' AS stage_citacao_execucao,
            'Penhora' AS stage_penhora,
            'Avaliacao dos Bens' AS stage_avaliacao_bens,
            'Satisfacao do Credito' AS stage_satisfacao_credito
            )
        )
),
aux_calendar AS (
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
    CAST(NULL AS INTEGER) AS id_process,
    p.id_court_case,
    p.id_case AS id_anonymized,
    p.id_contract_cyber,
    p.id_contract AS contract,
    p.id_process AS process,
    p.input_type,
    CASE
        WHEN cwt.open_wallet_overdue_t1 IS NULL THEN 'Adimplente'
        WHEN cwt.has_fpd_in_wallet = True THEN 'FPD'
        WHEN cwt.open_acordo_balance > 0 THEN 'Acordo Ativo'
        WHEN cwt.n_monthly_invoices > 0 THEN 'Mensal'
        WHEN cwt.open_wallet_overdue_t1 IS NOT NULL THEN 'Demais Inadimplentes'
        ELSE 'Outros'
    END AS contract_category_at_registration,
    p.case_subtype AS action_type,
    p.original_process_type AS action,
    p.agency_name AS office,
    p.collection_agency_name AS collection_agency,
    p.court_name AS chamber,
    p.state AS region,
    p.city,
    p.contract_status,
    p.case_status AS cyber_status,
    ps.stage_description AS last_stage,
    s.stage_distribuicao_arbitral_expense_amount AS arbitral_distribution_expense_amount,
    s.stage_citacao_arbitral_expense_amount AS arbitral_citation_expense_amount,
    s.stage_sentenca_arbitral_expense_amount AS arbitral_sentence_expense_amount,
    s.stage_distribuicao_judicial_expense_amount AS judiciary_distribution_expense_amount,
    s.stage_decisao_citacao_judicial_expense_amount AS judicial_summons_decision_expense_amount,
    s.stage_citacao_judicial_expense_amount AS judicial_summons_expense_amount,
    s.stage_decisao_coercitivo_expense_amount AS coercive_decision_expense_amount,
    s.stage_emissao_coercitivo_expense_amount AS coercive_issuance_expense_amount,
    s.stage_peticao_judicial_expense_amount AS judicial_petition_expense_amount,
    s.stage_decisao_imissao_posse_expense_amount AS possesion_imission_decision_expense_amount,
    s.stage_emissao_imissao_posse_expense_amount AS possesion_imission_issuance_expense_amount,
    s.stage_requerimento_execucao_expense_amount AS execution_requirement_expense_amount,
    s.stage_arresto_cautelar_expense_amount AS prejudgment_attachment_expense_amount,
    s.stage_citacao_execucao_expense_amount AS execution_citation_expense_amount,
    s.stage_penhora_expense_amount AS asset_attachment_expense_amount,
    s.stage_avaliacao_bens_expense_amount AS asset_evaluation_expense_amount,
    s.stage_satisfacao_credito_expense_amount AS credit_satisfaction_expense_amount,
    CASE
        WHEN p.contract_status = 'Finalizando' AND p.dt_status_changed IS NULL THEN 'Em finalização'
        WHEN p.case_final_description IN ('IMISSÃO NA POSSE', 'DESPEJO COERCITIVO') AND p.ts_contract_end IS NULL THEN 'Em finalização'
        WHEN p.dt_status_changed IS NULL AND p.original_process_type IN ('Execucao') THEN 'Execução'
        WHEN p.dt_status_changed IS NULL THEN 'Ativo'
        WHEN p.dt_status_changed IS NOT NULL AND p.case_final_description IN ('Quitacao') THEN 'Quitado'
        WHEN p.dt_status_changed IS NOT NULL AND p.case_final_description IN ('Rescisao') THEN 'Finalizado'
        WHEN p.dt_status_changed IS NOT NULL AND p.case_status = 'Completed' THEN 'Encerrado'
    ELSE NULL END AS passage_status,
    CASE WHEN COUNT(*) OVER (PARTITION BY BIGINT(id_contract)) > 1 THEN TRUE ELSE FALSE END AS is_reincident,
    'not_in_cyber_legal' AS procedure,
    p.case_result_description AS consolidated_reason,
    p.case_final_description AS standardized_reason,
    'not_in_cyber_legal' AS result,
    'not_in_cyber_legal' AS succumbency_fee,
    p.total_package_amount AS total_package,
    p.overdue_amount AS total_due_amount,
    cwt.max_delay_original_invoices_t1 AS overdue_days_at_registration,
    p.ldt_stock,
    CASE
        WHEN p.ldt_stock BETWEEN 0 AND 120 THEN '<120D'
        WHEN p.ldt_stock BETWEEN 121 AND 240 THEN '120-240D'
        WHEN p.ldt_stock BETWEEN 241 AND 360 THEN '240-360D'
        WHEN p.ldt_stock BETWEEN 361 AND 5000 THEN '>360D'
        ELSE NULL
    END AS stock_range,
    p.ldt_resolution,
    CASE
        WHEN p.ldt_resolution BETWEEN 0 AND 120 THEN '<120D'
        WHEN p.ldt_resolution BETWEEN 121 AND 240 THEN '120-240D'
        WHEN p.ldt_resolution BETWEEN 241 AND 360 THEN '240-360D'
        WHEN p.ldt_resolution BETWEEN 361 AND 5000 THEN '>360D'
        ELSE NULL
    END AS resolution_range,
    DATE_DIFF(DAY, DATE(p.dt_case_acceptance), DATE(CASE WHEN p.case_status = 'Completed' THEN p.dt_status_changed ELSE NULL END)) AS real_ldt_resolution,
    COUNT(DISTINCT
        CASE
            WHEN DATE(p.dt_case_acceptance) <= d.date AND DATE(p.dt_case_acceptance) IS NOT NULL
            AND d.is_brz_holiday = "No holiday" AND d.weekend = 'Weekday' AND d.arbitration_recess = False
            AND(
              (DATE(s.stage_distribuicao_arbitral_dt_start) IS NOT NULL AND DATE(s.stage_distribuicao_arbitral_dt_start) >= d.date) OR
              (DATE(s.stage_distribuicao_arbitral_dt_start) IS NULL AND CURRENT_DATE() >= d.date)
              ) THEN d.sk_date END) AS ldt_arbitral_distribution,
    COUNT(DISTINCT
            CASE
                WHEN DATE(s.stage_distribuicao_arbitral_dt_start) <= d.date AND DATE(s.stage_distribuicao_arbitral_dt_start) IS NOT NULL
                AND d.is_brz_holiday = "No holiday" AND d.weekend = 'Weekday' AND d.arbitration_recess = False
                AND(
                  (DATE(s.stage_sentenca_arbitral_dt_start) IS NOT NULL AND DATE(s.stage_sentenca_arbitral_dt_start) >= d.date) OR
                  (DATE(s.stage_sentenca_arbitral_dt_start) IS NULL AND CURRENT_DATE() >= d.date)
                  ) THEN d.sk_date END) AS ldt_arbitral_award,
    COUNT(DISTINCT
            CASE
                WHEN DATE(s.stage_sentenca_arbitral_dt_start) <= d.date AND DATE(s.stage_sentenca_arbitral_dt_start) IS NOT NULL
                AND d.is_brz_holiday = "No holiday" AND d.weekend = 'Weekday' AND d.arbitration_recess = False
                AND(
                  (DATE(s.stage_distribuicao_judicial_dt_start) IS NOT NULL AND DATE(s.stage_distribuicao_judicial_dt_start) >= d.date) OR
                  (DATE(s.stage_distribuicao_judicial_dt_start) IS NULL AND CURRENT_DATE() >= d.date)
                  ) THEN d.sk_date END) AS ldt_judiciary_distribution,
    COUNT(DISTINCT
            CASE
                WHEN DATE(s.stage_distribuicao_judicial_dt_start) <= d.date AND DATE(s.stage_distribuicao_judicial_dt_start) IS NOT NULL
                AND d.is_brz_holiday = "No holiday" AND d.weekend = 'Weekday' AND d.arbitration_recess = False
                AND(
                  (DATE(s.stage_decisao_citacao_judicial_dt_start) IS NOT NULL AND DATE(s.stage_decisao_citacao_judicial_dt_start) >= d.date) OR
                  (DATE(s.stage_decisao_citacao_judicial_dt_start) IS NULL AND CURRENT_DATE() >= d.date)
                  ) THEN d.sk_date END) AS ldt_judicial_summons_decision,
    COUNT(DISTINCT
            CASE
                WHEN DATE(s.stage_decisao_citacao_judicial_dt_start) <= d.date AND DATE(s.stage_decisao_citacao_judicial_dt_start) IS NOT NULL
                AND d.is_brz_holiday = "No holiday" AND d.weekend = 'Weekday' AND d.arbitration_recess = False
                AND(
                  (DATE(s.stage_decisao_coercitivo_dt_start) IS NOT NULL AND DATE(s.stage_decisao_coercitivo_dt_start) >= d.date) OR
                  (DATE(s.stage_decisao_coercitivo_dt_start) IS NULL AND CURRENT_DATE() >= d.date)
                  ) THEN d.sk_date END) AS ldt_coercive_decision,
    COUNT(DISTINCT
            CASE
                WHEN DATE(s.stage_decisao_coercitivo_dt_start) <= d.date AND DATE(s.stage_decisao_coercitivo_dt_start) IS NOT NULL
                AND d.is_brz_holiday = "No holiday" AND d.weekend = 'Weekday' AND d.arbitration_recess = False
                AND(
                  (DATE(s.stage_emissao_coercitivo_dt_start) IS NOT NULL AND DATE(s.stage_emissao_coercitivo_dt_start) >= d.date) OR
                  (DATE(s.stage_emissao_coercitivo_dt_start) IS NULL AND CURRENT_DATE() >= d.date)
                  ) THEN d.sk_date END) AS ldt_coercive_order_issuance_decision,
    'not_in_cyber_legal' AS ldt_coercive,
    'not_in_cyber_legal' AS last_occurrence,
    'not_in_cyber_legal' AS has_arbitration_defense,
    'not_in_cyber_legal' AS has_redistribution,
    p.dt_case_acceptance AS dt_registered,
    s.stage_distribuicao_arbitral_dt_start AS dt_arbitral_distribution_start,
    s.stage_distribuicao_arbitral_dt_end AS dt_arbitral_distribution_end,
    s.stage_citacao_arbitral_dt_start AS dt_arbitral_citation_start,
    s.stage_citacao_arbitral_dt_end AS dt_arbitral_citation_end,
    'not_in_cyber_legal' AS dt_arbitral_contestation,
    s.stage_sentenca_arbitral_dt_start AS dt_arbitral_sentence_start,
    s.stage_sentenca_arbitral_dt_end AS dt_arbitral_sentence_end,
    'not_in_cyber_legal' AS dt_judiciary_pre_registration,
    s.stage_distribuicao_judicial_dt_start AS dt_judiciary_distribution_start,
    s.stage_distribuicao_judicial_dt_end AS dt_judiciary_distribution_end,
    s.stage_decisao_citacao_judicial_dt_start AS dt_judicial_summons_decision_start,
    s.stage_decisao_citacao_judicial_dt_end AS dt_judicial_summons_decision_end,
    s.stage_citacao_judicial_dt_start AS dt_judicial_summons_start,
    s.stage_citacao_judicial_dt_end AS dt_judicial_summons_end,
    'not_in_cyber_legal' AS dt_judicial_defense,
    s.stage_decisao_coercitivo_dt_start AS dt_coercive_decision_start,
    s.stage_decisao_coercitivo_dt_end AS dt_coercive_decision_end,
    s.stage_emissao_coercitivo_dt_start AS dt_coercive_issuance_start,
    s.stage_emissao_coercitivo_dt_end AS dt_coercive_issuance_end,
    s.stage_peticao_judicial_dt_start AS dt_judicial_petition_start,
    s.stage_peticao_judicial_dt_end AS dt_judicial_petition_end,
    s.stage_decisao_imissao_posse_dt_start AS dt_possesion_imission_decision_start,
    s.stage_decisao_imissao_posse_dt_end AS dt_possesion_imission_decision_end,
    s.stage_emissao_imissao_posse_dt_start AS dt_possesion_imission_decision_start,
    s.stage_emissao_imissao_posse_dt_end AS dt_possesion_imission_decision_end,
    s.stage_requerimento_execucao_dt_start AS dt_execution_requirement_start,
    s.stage_requerimento_execucao_dt_end AS dt_execution_requirement_end,
    s.stage_arresto_cautelar_dt_start AS dt_prejudgment_attachment_start,
    s.stage_arresto_cautelar_dt_end AS dt_prejudgment_attachment_end,
    s.stage_citacao_execucao_dt_start AS dt_execution_citation_start,
    s.stage_citacao_execucao_dt_end AS dt_execution_citation_end,
    s.stage_penhora_dt_start AS dt_asset_attachment_start,
    s.stage_penhora_dt_end AS dt_asset_attachment_end,
    s.stage_avaliacao_bens_dt_start AS dt_asset_evaluation_start,
    s.stage_avaliacao_bens_dt_end AS dt_asset_evaluation_end,
    s.stage_satisfacao_credito_dt_start AS dt_credit_satisfaction_start,
    s.stage_satisfacao_credito_dt_end AS dt_credit_satisfaction_end,
    IF(p.case_status = 'Completed', p.dt_status_changed, NULL) AS dt_closure,
    p.ts_updated
FROM
    datalake_cyber_legal_homolog.process AS p
LEFT JOIN
    get_stages_data AS s
    ON p.id_case = s.id_case
LEFT JOIN
    get_last_process_stage AS ps
    ON p.id_case = ps.id_case
LEFT JOIN
    dw_collections_segmentation.fact_contract_wallet_timeline cwt
    ON p.id_contract = cwt.sk_contract
    AND p.dt_case_acceptance = cwt.dt_reference
LEFT JOIN
    aux_calendar d
    ON p.dt_case_acceptance <= d.date AND (IF(p.case_status = 'Completed', p.dt_status_changed, NULL) >= d.date OR p.dt_status_changed IS NULL)
