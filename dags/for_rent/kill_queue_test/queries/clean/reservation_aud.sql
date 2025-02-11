SELECT
    id,
    house_id AS id_house,
    rent_flow_id AS id_rent_flow,
    tenant_id AS id_tenant,
    rev,
    revtype as rev_type,
    revend as rev_end,
    attempt,
    cancellation_reason,
    mundipagg_token,
    status,
    value,
    CAST(attempt_mod AS BOOLEAN) AS mod_has_attempt,
    CAST(cancellation_reason_mod AS BOOLEAN) AS mod_has_cancellation_reason,
    CAST(mundipagg_token_mod AS BOOLEAN) AS mod_has_mundipagg_token,
    CAST(status_mod AS BOOLEAN) AS mod_has_status,
    CAST(value_mod AS BOOLEAN) AS mod_has_value
FROM
    datalake_kill_queue_test_raw.reservation_aud