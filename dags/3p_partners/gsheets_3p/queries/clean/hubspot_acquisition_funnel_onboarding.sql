SELECT
    NULLIF(company_name, '') AS company_name,
    NULLIF(id_company, '') AS id_company,
    NULLIF(cleaned_stage, '') AS cleaned_stage,
    NULLIF(current_stage, '') AS current_stage,
    NULLIF(account_manager_user, '') AS account_manager_user,
    CAST(NULLIF(dt_stage_started, '') AS DATE) AS dt_stage_started,
    CAST(NULLIF(dt_stage_ended, '') AS DATE) AS dt_stage_ended,
    CAST(NULLIF(days_in_stage, '') AS FLOAT) AS days_in_stage,
    CAST(NULLIF(aux_order, '') AS FLOAT) AS aux_order,
    CAST(NULLIF(dt_contract, '') AS DATE) AS dt_contract,
    NULLIF(stage, '') AS stage,
    CAST(NULLIF(is_flagged_as_leadgen, '') AS BOOLEAN) AS is_flagged_as_leadgen,
    NOW() AS ts_load
FROM
    datalake_gsheets_raw.hubspot_acquisition_funnel_onboarding