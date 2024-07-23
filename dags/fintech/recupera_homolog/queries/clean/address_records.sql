SELECT
    id_creditor,
    id_customer,
    CAST(id_sequence_number AS INT) AS id_sequence_number,
    address_description,
    address_number,
    address_add_on,
    neighborhood,
    address_city,
    address_state,
    address_zip_code,
    ts_load
FROM
    datalake_recupera_homolog_raw.address_records
