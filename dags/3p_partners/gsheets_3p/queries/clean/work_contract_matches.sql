SELECT
    NULLIF(id_hubspot, '') AS id_hubspot,
    NULLIF(3p_partner, '') AS 3p_partner
FROM
    datalake_gsheets_raw.work_contract_matches