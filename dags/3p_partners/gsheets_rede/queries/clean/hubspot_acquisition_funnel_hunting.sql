SELECT
    NULLIF(company_name, '') AS company_name,
    NULLIF(id_company, '') AS id_company,
    NULLIF(account_manager_user, '') AS account_manager_user,
    NULLIF(cleaned_stage, '') AS cleaned_stage,
    NULLIF(city, '') AS city,
    CAST(NULLIF(days_in_stage, '') AS FLOAT) AS days_in_stage,
    CAST(NULLIF(dt_stage_started, '') AS DATE) AS dt_stage_started,
    CAST(NULLIF(dt_stage_ended, '') AS DATE) AS dt_stage_ended,
    CAST(NULLIF(dt_first_contract, '') AS DATE) AS dt_first_contract,
    CAST(NULLIF(dt_nutrition, '') AS DATE) AS dt_nutrition,
    CAST(NULLIF(aux_order, '') AS FLOAT) AS aux_order,
    NULLIF(stage, '') AS stage,
    NOW() AS ts_load
FROM
    datalake_gsheets_raw.hubspot_acquisition_funnel_hunting