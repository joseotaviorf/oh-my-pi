SELECT
    id,
    boleto_user_id AS id_invoice_user,
    boleto_issuer_id AS id_invoice_issuer,
    contract_id AS id_contract,
    request_status,
    version,
    monitoring_start_date AS dt_monitoring_started,
    due_date AS dt_due,
    created_at AS ts_created,
    updated_at AS ts_updated,
    last_received_event_at AS ts_last_received_event
FROM
    datalake_rental_management_raw.boleto_user_issuer
