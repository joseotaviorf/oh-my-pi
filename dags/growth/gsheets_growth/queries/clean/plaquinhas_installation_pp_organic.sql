SELECT
    CAST(id_ticket AS INTEGER) AS id_ticket,
    CAST(id_house AS INTEGER) AS id_house, 
    client_type, 
    business_context,
    state, 
    TO_DATE(dt_install, "dd/MM/yy") AS dt_install
FROM
    datalake_gsheets_raw.plaquinhas_installation_pp_organic