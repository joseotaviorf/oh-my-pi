SELECT
    id,
    external_id         AS id_external,
    file_url,
    due_amount,
    status,
    business_context,
    raw_request,
    raw_response,
    code,
    version,
    due_date            AS dt_due,
    paid_at             AS ts_paid,
    credit_at           AS ts_credit,
    created_at          AS ts_created,
    updated_at          AS ts_updated,
    year,
    month,
    day

FROM
    datalake_rental_guarantee_platform_raw.boleto

QUALIFY
    ROW_NUMBER() OVER (PARTITION BY id ORDER BY updated_at DESC) = 1
