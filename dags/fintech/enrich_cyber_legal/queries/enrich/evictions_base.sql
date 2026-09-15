WITH
get_completed_case_status AS (
    SELECT
        id_case,
        closure_reason,
        closure_result,
        dt_status_changed,
        ROW_NUMBER() OVER (
            PARTITION BY id_case
            ORDER BY dt_status_changed
        ) AS completion_order
    FROM datalake_cyber_legal_historical_clean.historical_case_status
    WHERE case_status = 'Completed'
),
get_first_process_closure AS (
    SELECT
        first_completion.id_case,
        CASE
            WHEN first_completion.closure_reason = 'L_RES51'
                AND next_completion.id_case IS NOT NULL
            THEN next_completion.closure_reason
            ELSE first_completion.closure_reason
        END AS closure_reason,
        CASE
            WHEN first_completion.closure_reason = 'L_RES51'
                AND next_completion.id_case IS NOT NULL
            THEN next_completion.closure_result
            ELSE first_completion.closure_result
        END AS closure_result,
        first_completion.dt_status_changed AS dt_first_closure
    FROM get_completed_case_status AS first_completion
    LEFT JOIN get_completed_case_status AS next_completion
        ON first_completion.id_case = next_completion.id_case
        AND next_completion.completion_order = 2
    WHERE first_completion.completion_order = 1
),
get_process_stages AS (
    SELECT DISTINCT
        id_case,
        stage_order,
        stage_description,
        expense_amount,
        dt_start,
        dt_end
    FROM datalake_cyber_legal.process_stages
),
ranked_process_stages AS (
    SELECT
        id_case,
        stage_description,
        ROW_NUMBER() OVER (
            PARTITION BY id_case
            ORDER BY stage_order DESC
        ) AS rn
    FROM get_process_stages
    WHERE dt_start IS NOT NULL
),
get_last_process_stage AS (
    SELECT
        id_case,
        stage_description
    FROM ranked_process_stages
    WHERE rn = 1
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

    FROM (
        SELECT
            id_case,
            stage_description,
            expense_amount,
            dt_start,
            dt_end
        FROM get_process_stages
    )
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
)

SELECT DISTINCT
    p.id_case AS id_process,
    p.id_court_case,
    p.id_contract AS contract,
    p.id_process AS process,
    p.input_type,
    p.case_subtype AS action_type,
    p.original_process_type AS action,
    CASE
        WHEN p.agency_name IN ('PLC', 'LLC') THEN 'LLC'
        ELSE p.agency_name
    END AS office,
    p.court_name AS chamber,
    p.state AS region,
    p.city,
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
    s.stage_decisao_imissao_posse_expense_amount AS possession_imission_decision_expense_amount,
    s.stage_emissao_imissao_posse_expense_amount AS possession_imission_issuance_expense_amount,
    s.stage_requerimento_execucao_expense_amount AS execution_requirement_expense_amount,
    s.stage_arresto_cautelar_expense_amount AS prejudgment_attachment_expense_amount,
    s.stage_citacao_execucao_expense_amount AS execution_citation_expense_amount,
    s.stage_penhora_expense_amount AS asset_attachment_expense_amount,
    s.stage_avaliacao_bens_expense_amount AS asset_evaluation_expense_amount,
    s.stage_satisfacao_credito_expense_amount AS credit_satisfaction_expense_amount,
    CASE WHEN COUNT(*) OVER (PARTITION BY BIGINT(id_contract)) > 1 THEN TRUE ELSE FALSE END AS is_reincident,
    IF(p.case_status = 'Active' AND fpc.dt_first_closure IS NOT NULL, TRUE, FALSE) AS is_reopened,
    CASE
        WHEN s.stage_distribuicao_judicial_dt_start IS NULL THEN 'Arbitral'
        WHEN s.stage_distribuicao_judicial_dt_start IS NOT NULL THEN 'Judicial'
    END AS procedure,
    p.case_result_description AS consolidated_reason,
    p.case_final_description AS standardized_reason,
    FIRST(vl.value_description) AS first_consolidated_reason,
    FIRST(vl1.value_description) AS first_standardized_reason,
    CASE
        WHEN p.case_result_description IN (
            'Despejo Coercitivo',
            'Imissao na Posse',
            'Quitacao Escritorio',
            'Rescisao Escritorio'
        ) THEN 'Jurídico'
        ELSE 'Amigável'
    END AS result,
    'not_in_cyber_legal' AS succumbency_fee,
    p.ldt_stock,
    CASE
        WHEN p.ldt_stock BETWEEN 0 AND 120 THEN '<120D'
        WHEN p.ldt_stock BETWEEN 121 AND 240 THEN '120-240D'
        WHEN p.ldt_stock BETWEEN 241 AND 360 THEN '240-360D'
        WHEN p.ldt_stock BETWEEN 361 AND 5000 THEN '>360D'
        ELSE NULL
    END AS stock_range,
    CASE
        WHEN DATE(p.dt_case_acceptance) > DATE(fpc.dt_first_closure) THEN 0
        WHEN fpc.dt_first_closure IS NOT NULL THEN DATEDIFF(LAST_DAY(ADD_MONTHS(fpc.dt_first_closure, 0)), p.dt_case_acceptance)
    ELSE NULL END AS ldt_resolution,
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
    s.stage_decisao_imissao_posse_dt_start AS dt_possession_imission_decision_start,
    s.stage_decisao_imissao_posse_dt_end AS dt_possession_imission_decision_end,
    s.stage_emissao_imissao_posse_dt_start AS dt_possession_imission_issuance_start,
    s.stage_emissao_imissao_posse_dt_end AS dt_possession_imission_issuance_end,
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
    fpc.dt_first_closure AS dt_closure,
    p.ts_updated
FROM
    datalake_cyber_legal.process AS p
LEFT JOIN
    get_stages_data AS s
    ON p.id_case = s.id_case
LEFT JOIN
    get_last_process_stage AS ps
    ON p.id_case = ps.id_case
LEFT JOIN
    get_first_process_closure AS fpc
    ON p.id_case = fpc.id_case
LEFT JOIN
    datalake_cyber_legal_clean.values_list vl
        ON fpc.closure_result = vl.value_code
LEFT JOIN
    datalake_cyber_legal_clean.values_list vl1
        ON fpc.closure_reason = vl1.value_code
        AND (
            fpc.closure_result = 'LRES_10'
            OR fpc.closure_result = vl1.id_value
        )
GROUP BY 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 32, 33, 34, 35, 38, 39, 40, 41, 42, 43, 44, 45, 46, 47, 48, 49, 50, 51, 52, 53, 54, 55, 56, 57, 58, 59, 60, 61, 62, 63, 64, 65, 66, 67, 68, 69, 70, 71, 72, 73, 74, 75, 76, 77, 78, 79, 80, 81, 82, 83, 84, 85, 86
