SELECT
    CAST(id_do_bairro AS INTEGER) AS id_region,
    CAST(hub AS STRING) AS hub_name, 
    CAST(subhub AS STRING) AS subhub_name
FROM
    datalake_gsheets_raw.subhub_regions