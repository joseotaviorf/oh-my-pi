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
        stage_emissao_coercitivo_dt_end
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
            'Emissao Coercitivo' AS stage_emissao_coercitivo
            )
        )
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
    s.stage_distribuicao_arbitral_expense_amount,
    s.stage_citacao_arbitral_expense_amount,
    s.stage_sentenca_arbitral_expense_amount,
    s.stage_distribuicao_judicial_expense_amount,
    s.stage_decisao_citacao_judicial_expense_amount,
    s.stage_citacao_judicial_expense_amount,
    s.stage_decisao_coercitivo_expense_amount,
    s.stage_emissao_coercitivo_expense_amount,
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
    DATE_DIFF(DAY, DATE(p.dt_case_acceptance), DATE(s.stage_distribuicao_arbitral_dt_start)) AS ldt_arbitral_distribution,
    DATE_DIFF(DAY, DATE(p.dt_case_acceptance), DATE(s.stage_sentenca_arbitral_dt_start)) AS ldt_arbitral_award,
    DATE_DIFF(DAY, DATE(p.dt_case_acceptance), DATE(s.stage_distribuicao_judicial_dt_start)) AS ldt_judiciary_distribution,
    DATE_DIFF(DAY, DATE(p.dt_case_acceptance), DATE(s.stage_decisao_citacao_judicial_dt_start)) AS ldt_judicial_summons_decision,
    DATE_DIFF(DAY, DATE(p.dt_case_acceptance), DATE(s.stage_decisao_coercitivo_dt_start)) AS ldt_coercive_decision,
    DATE_DIFF(DAY, DATE(p.dt_case_acceptance), DATE(s.stage_emissao_coercitivo_dt_start)) AS ldt_coercive_order_issuance_decision,
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
    IF(p.case_status = 'Completed', p.dt_status_changed, NULL) AS dt_elaw_closure,
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
