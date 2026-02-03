WITH
get_process_stages AS (
    SELECT DISTINCT
        id_case,
        stage_description,
        stage_order,
        expense_amount,
        dt_start,
        dt_end
    FROM datalake_cyber_legal_homolog.process_stages
),
get_last_process_stage AS (
  SELECT
    id_case,
    stage_description
  FROM get_process_stages
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
        MAX(COALESCE(dt_start, DATE('1999-01-01'))) AS dt_start,
        MAX(COALESCE(dt_end, DATE('1999-01-01'))) AS dt_end
        FOR stage_description IN (
            'Distribuição Arbitral' AS stage_distribuicao_arbitral,
            'Citação Arbitral' AS stage_citacao_arbitral,
            'Sentença Arbitral' AS stage_sentenca_arbitral,
            'Distribuição Judicial' AS stage_distribuicao_judicial,
            'Decisão de Citação Judicial' AS stage_decisao_citacao_judicial,
            'Citação Judicial' AS stage_citacao_judicial,
            'Decisão Coercitivo' AS stage_decisao_coercitivo,
            'Emissão Coercitivo' AS stage_emissao_coercitivo
        )
    )
)

SELECT
    p.id_case AS id_anonymized,
    p.id_contract_cyber,
    p.id_contract AS contract,
    p.id_process AS process,
    p.evictions_label AS input_type,
    NULL AS contract_category_at_registration,
    NULL AS action_type,
    p.process_type AS action,
    p.agency_name AS office,
    p.id_court,
    p.court_name AS chamber,
    p.state AS region,
    p.city,
    p.contract_status,
    p.case_status AS elaw_status,
    ps.stage_description AS last_stage,
    s.stage_distribuicao_arbitral_expense_amount,
    s.stage_citacao_arbitral_expense_amount,
    s.stage_sentenca_arbitral_expense_amount,
    s.stage_distribuicao_judicial_expense_amount,
    s.stage_decisao_citacao_judicial_expense_amount,
    s.stage_citacao_judicial_expense_amount,
    s.stage_decisao_coercitivo_expense_amount,
    s.stage_emissao_coercitivo_expense_amount,
    NULL AS passage_status,
    NULL AS procedure,
    NULL AS result,
    NULL AS total_package,
    NULL AS total_due_amount,
    NULL AS overdue_days_at_registration,
    NULL AS ldt_stock,
    NULL AS stock_range,
    NULL AS ldt_resolution,
    NULL AS resolution_range,
    NULL AS real_ldt_resolution,
    NULL AS ldt_arbitral_distribution,
    NULL AS ldt_arbitral_award,
    NULL AS ldt_judiciary_distribution,
    NULL AS ldt_judicial_summons_decision,
    NULL AS ldt_coercive_decision,
    NULL AS ldt_coercive_order_issuance_decision,
    NULL AS ldt_coercive,
    NULL AS last_occurrence,
    NULL AS has_arbitration_defense,
    NULL AS has_redistribution,
    p.dt_case_acceptance AS dt_registered,
    s.stage_distribuicao_arbitral_dt_start AS dt_arbitral_distribution_start,
    s.stage_distribuicao_arbitral_dt_end AS dt_arbitral_distribution_end,
    s.stage_citacao_arbitral_dt_start AS dt_arbitral_citation_start,
    s.stage_citacao_arbitral_dt_end AS dt_arbitral_citation_end,
    NULL AS dt_arbitral_contestation,
    s.stage_sentenca_arbitral_dt_start AS dt_arbitral_sentence_start,
    s.stage_sentenca_arbitral_dt_end AS dt_arbitral_sentence_end,
    NULL AS dt_judiciary_pre_registration,
    s.stage_distribuicao_judicial_dt_start AS dt_judiciary_distribution_start,
    s.stage_distribuicao_judicial_dt_end AS dt_judiciary_distribution_end,
    s.stage_decisao_citacao_judicial_dt_start AS dt_judicial_summons_decision_start,
    s.stage_decisao_citacao_judicial_dt_end AS dt_judicial_summons_decision_end,
    s.stage_citacao_judicial_dt_start AS dt_judicial_summons_start,
    s.stage_citacao_judicial_dt_end AS dt_judicial_summons_end,
    NULL AS dt_judicial_defense,
    s.stage_decisao_coercitivo_dt_start AS dt_coercive_decision_start,
    s.stage_decisao_coercitivo_dt_end AS dt_coercive_decision_end,
    s.stage_emissao_coercitivo_dt_start AS dt_coercive_issuance_start,
    s.stage_emissao_coercitivo_dt_end AS dt_coercive_issuance_end,
    IF(p.case_status = 'Completed', p.dt_status_changed, NULL) AS dt_elaw_closure,
    p.ts_updated
FROM datalake_cyber_legal_homolog.process AS p
LEFT JOIN get_stages_data AS s
    ON p.id_case = s.id_case
LEFT JOIN get_last_process_stage AS ps
    ON p.id_case = ps.id_case
