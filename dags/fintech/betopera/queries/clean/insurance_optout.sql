SELECT
    id,
    requester,
    insurance_id AS id_insurance,
    invoice_management_type,
    approver_user_id AS id_approver_user,
    status,
    canceller_user_id AS id_canceller_user,
    cancellation_reason,
    DATE(external_policy_start_date) AS dt_external_policy_start,
    DATE(external_policy_end_date) AS dt_external_policy_end,
    DATE(start_date) AS dt_start,
    DATE(end_date) AS dt_end,
    TIMESTAMP(approved_at) AS ts_approved,
    TIMESTAMP(cancelled_at) AS ts_cancelled,
    TIMESTAMP(created_at) AS ts_created,
    TIMESTAMP(updated_at) AS ts_updated,
    year,
    month,
    day
FROM
    datalake_betopera_raw.insurance_optout
