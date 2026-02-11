SELECT
    id,
    provider,
    provider_code,
    name,
    description,
    category_key,
    category_label_pt,
    sub_category_key,
    sub_category_label_pt,
    mapped_status,
    version,
    is_active,
    terminal AS is_terminal,
    retryable AS is_retryable,
    documentation_url,
    TIMESTAMP(created_at) AS ts_created,
    TIMESTAMP(updated_at) AS ts_updated,
    TIMESTAMP(disabled_at) AS ts_disabled
FROM
    datalake_payout_system_raw.reason
