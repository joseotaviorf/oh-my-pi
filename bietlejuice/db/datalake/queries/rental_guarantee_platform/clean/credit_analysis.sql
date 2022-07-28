SELECT
    id,
    contract_id AS id_contract,
    approved_value,
    decision_text,
    status,
    request,
    response,
    version,
    request_date AS ts_request,
    response_date AS ts_response,
    created_at AS ts_created,
    updated_at AS ts_updated,
    year,
    month,
    day
FROM
    datalake_rental_guarantee_platform_raw.credit_analysis
WHERE
    year = {year}
    AND month = {month}
    AND day = {day}