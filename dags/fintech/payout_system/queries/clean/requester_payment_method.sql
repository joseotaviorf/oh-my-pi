SELECT
    id,
    requester_id AS id_requester,
    payment_method_id AS id_payment_method,
    is_enabled,
    config_overrides,
    TIMESTAMP(created_at) AS ts_created,
    TIMESTAMP(updated_at) AS ts_updated,
    TIMESTAMP(disabled_at) AS ts_disabled
FROM
    datalake_payout_system_raw.requester_payment_method
