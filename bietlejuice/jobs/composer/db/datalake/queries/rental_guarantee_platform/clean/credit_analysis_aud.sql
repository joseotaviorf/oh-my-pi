SELECT
    id,
    contract_id AS id_contract,
    approved_value,
    decision_text,
    status,
    request,
    response,
    version,
    rev,
    revend AS rev_end,
    revtype AS rev_type,
    contract_id_mod AS mod_id_contract,
    approved_value_mod AS mod_approved_value,
    decision_text_mod AS mod_decision_text,
    status_mod AS mod_status,
    request_mod AS mod_request,
    response_mod AS mod_response,
    request_date_mod AS mod_ts_request,
    response_date_mod AS mod_ts_response,
    request_date AS ts_request,
    response_date AS ts_response,
    created_at AS ts_created,
    year,
    month,
    day
FROM
    datalake_rental_guarantee_platform_raw.credit_analysis_aud
WHERE
    year = {year}
    AND month = {month}
    AND day = {day}
