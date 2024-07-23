SELECT
    id_creditor,
    id_customer,
    id_digital_channel,
    distribution_param_code,
    relocation_code,
    CAST(distribution_shipment_number AS INT) AS distribution_shipment_number,
    DATE(dt_expiry_token) AS dt_expiry_token,
    dt_current_registration AS ts_current_registration,
    ts_load,
    year,
    month,
    day
FROM
    datalake_recupera_homolog_raw.records_distributed_channels
WHERE
    year = {year}
    AND month = {month}
    AND day = {day}
