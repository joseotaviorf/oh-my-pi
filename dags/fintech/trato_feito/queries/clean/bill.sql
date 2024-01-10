SELECT
    id,
    contract_id AS id_contract,
    boleto_identifier AS id_boleto,
    sync_status,
    purpose,
    negativate,
    our_number,
    accrual_year_month,
    paid_amount,
    sent_at AS dt_sent,
    creation_date AS dt_creation,
    paid_date AS dt_paid,
    last_received_at AS dt_last_received
FROM datalake_trato_feito_raw.bill
