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
    p.id_case,
    p.id_contract_cyber,
    p.id_contract,
    p.id_process,
    p.id_court,
    p.court_name,
    p.process_type,
    p.id_agency,
    p.agency_name,
    p.internal_lawyer,
    p.external_lawyer,
    p.supervising_lawyer,
    p.contract_evictions_status,
    p.evictions_label,
    p.eviction_step,
    p.eviction_law_firm,
    p.reason_eviction,
    p.process_start_comment,
    p.process_end_comment,
    p.case_comment,
    p.case_status,
    p.case_subtype,
    p.court_division,
    p.jurisdiction,
    p.case_result,
    p.case_result_description,
    p.case_final_result,
    p.case_final_description,
    p.case_amount,
    p.provisioned_value,
    p.updated_case_value,
    p.recovered_amount,
    p.dt_status_changed,
    p.dt_lawsuit,
    p.dt_case_acceptance,
    p.dt_case_completion,
    p.dt_agency_assignment,
    s.stage_distribuicao_arbitral_expense_amount,
    s.stage_distribuicao_arbitral_dt_start,
    s.stage_distribuicao_arbitral_dt_end,
    s.stage_citacao_arbitral_expense_amount,
    s.stage_citacao_arbitral_dt_start,
    s.stage_citacao_arbitral_dt_end,
    s.stage_sentenca_arbitral_expense_amount,
    s.stage_sentenca_arbitral_dt_start,
    s.stage_sentenca_arbitral_dt_end,
    s.stage_distribuicao_judicial_expense_amount,
    s.stage_distribuicao_judicial_dt_start,
    s.stage_distribuicao_judicial_dt_end,
    s.stage_decisao_citacao_judicial_expense_amount,
    s.stage_decisao_citacao_judicial_dt_start,
    s.stage_decisao_citacao_judicial_dt_end,
    s.stage_citacao_judicial_expense_amount,
    s.stage_citacao_judicial_dt_start,
    s.stage_citacao_judicial_dt_end,
    s.stage_decisao_coercitivo_expense_amount,
    s.stage_decisao_coercitivo_dt_start,
    s.stage_decisao_coercitivo_dt_end,
    s.stage_emissao_coercitivo_expense_amount,
    s.stage_emissao_coercitivo_dt_start,
    s.stage_emissao_coercitivo_dt_end
FROM datalake_cyber_legal_homolog.process AS p
LEFT JOIN get_stages_data AS s
    ON p.id_case = s.id_case
