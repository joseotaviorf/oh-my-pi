SELECT
    id,
    boleto_id AS id_invoice,
    previous_boleto_status,
    new_boleto_status,
    channel,
    author_identifier,
    created_at AS ts_created
FROM
    datalake_rental_management_raw.boleto_audit_log
