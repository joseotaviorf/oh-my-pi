SELECT
    id,
    rev,
    revtype as rev_type,
    revend as rev_end,
    attempt,
    attempt_mod as is_attempt_mod,
    mundipagg_token,
    mundipagg_token_mod as is_mundipagg_token_mod,
    rent_flow_id as id_rent_flow,
    status,
    status_mod as is_status_mod,
    tenant_id as id_tenant,
    value,
    value_mod as is_value_mod,
    house_id as id_house,
    cancellation_reason,
    cancellation_reason_mod as is_cancellation_reason_mod
FROM
    datalake_kill_queue_raw.reservation_aud