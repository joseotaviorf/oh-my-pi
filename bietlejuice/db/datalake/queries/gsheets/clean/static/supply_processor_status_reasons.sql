SELECT
    CAST(id_reason AS INT) AS id_reason,
    NULLIF(reason_name, '') AS reason_name,
    NULLIF(reason_type, '') AS reason_type
FROM
    datalake_gsheets_raw.supply_processor_status_reasons