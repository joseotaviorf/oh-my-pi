SELECT
    id,
    payee_id AS id_payee,
    bank_code,
    agency_number,
    account_number,
    account_type,
    is_savings,
    TIMESTAMP(created_at) AS ts_created,
    TIMESTAMP(updated_at) AS ts_updated,
    TIMESTAMP(disabled_at) AS ts_disabled
FROM
    datalake_payout_system_raw.payee_account
