SELECT
    id,
    boleto_id AS id_invoice,
    uf,
    city,
    zip_code,
    street,
    version,
    created_at AS ts_created,
    updated_at AS ts_updated
FROM
    datalake_rental_management_raw.boleto_address
