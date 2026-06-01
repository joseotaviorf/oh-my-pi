SELECT
    CAST(NULLIF(nm_campaign, '') AS STRING) AS nm_campaign,
    CAST(NULLIF(phone_number, '') AS STRING) AS phone_number,
    CAST(NULLIF(source_environment,'') AS STRING) AS source_environment
FROM
    datalake_gsheets_raw.supply_inputs_click_to_whatsapp
