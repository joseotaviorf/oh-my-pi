SELECT
    INT(sk_request) AS sk_request,
    INT(sk_contract) AS sk_contract,
    BIGINT(sk_house) AS sk_house,
    agent_email,
    origin_form,
    charge,
    requester,
    recipient,
    installment_type,
    installments,
    origin_request,
    comment,
    is_canceled,
    SLA,
    FLOAT(value) AS value,
    DATE(reference_month) AS reference_month,
    DATE(due_date) AS due_date,
    TIMESTAMP(ts_request) AS ts_request,
    TIMESTAMP(ts_request_execution) AS ts_request_execution
FROM
    datalake_gsheets_raw.payments_deals_and_discounts
