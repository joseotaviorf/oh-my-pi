SELECT
    id,
    code,
    name,
    description,
    required_fields,
    is_active,
    version,
    TIMESTAMP(created_at) AS ts_created,
    TIMESTAMP(updated_at) AS ts_updated,
    TIMESTAMP(disabled_at) AS ts_disabled
FROM
    datalake_payout_system_raw.payment_method_config
