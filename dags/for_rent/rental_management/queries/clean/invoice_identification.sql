SELECT
    id,
    boleto_id AS id_invoice,
    status,
    status_reason,
    version,
    identified_at AS ts_identified,
    created_at AS ts_created,
    updated_at AS ts_updated
FROM
    datalake_rental_management_raw.boleto_identification
