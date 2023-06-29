SELECT
    name as metric_name,
    acronym as meetric_acronym,
    description as metric_description,
    businessStage as business_stage,
    calculation as metric_calculation,
    companyLine as company_line,
    cast(hasDatamart as boolean) as has_datamart,
    datamartName as datamart_name,
    cast(isAdditive as boolean) as is_additive,
    hierarchyLevel as hierarchy_level,
    linkToMetric as link_to_metric,
    approvedBy as approved_by,
    createdBy as created_by,
    observations,
    maturityLevel as maturity_level,
    ts_load
FROM
    datalake_gsheets_raw.atribuicao_de_maturidade_e_validacao_do_cadastro
