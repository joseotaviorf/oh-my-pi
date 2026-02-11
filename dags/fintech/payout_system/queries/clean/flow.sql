SELECT
    id,
    requester_id AS id_requester,
    code,
    name,
    description,
    transaction_type,
    auto_approval AS is_auto_approval,
    auto_approval_rules,
    is_active,
    auto_send AS is_auto_send,
    auto_send_rules,
    version,
    required_metadata,
    company_use_rules,
    TIMESTAMP(created_at) AS ts_created,
    TIMESTAMP(updated_at) AS ts_updated,
    TIMESTAMP(disabled_at) AS ts_disabled
FROM
    datalake_payout_system_raw.flow
