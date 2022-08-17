SELECT 
    CAST(id_business_unit_teams AS BIGINT) AS id_business_unit_teams,
    NULLIF(hub_name_teams, '') AS hub_name_teams,
    NULLIF(hub_name_wc, '') AS hub_name_wc,
    NULLIF(hub_name_bur, '') AS hub_name_bur,
    NOW() AS ts_load
FROM
    datalake_gsheets_raw.sale_business_unit_standardization
    
