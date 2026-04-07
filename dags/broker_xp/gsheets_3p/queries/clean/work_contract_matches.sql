SELECT
    NULLIF(id_hubspot, '') AS id_hubspot,
    NULLIF(3p_partner, '') AS 3p_partner,
    TRUE AS has_3p_access_control
FROM
    datalake_gsheets_raw.work_contract_matches