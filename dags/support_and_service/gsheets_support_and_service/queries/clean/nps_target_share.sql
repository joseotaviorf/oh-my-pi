SELECT
    apoio AS support
    ,campaign_group
    ,customer_journey
    ,target
    ,share
    ,quarter
    ,TO_DATE(data_inicio, 'dd/MM/yyyy') AS dt_start
    ,TO_DATE(data_fim, 'dd/MM/yyyy') AS dt_end
    ,ano AS year
    ,macro_customer_journey
    ,share_macro
    ,share_nps_global
FROM datalake_gsheets_raw.target_share_nps

