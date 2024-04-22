SELECT
    id,
    external_id AS id_external,
    external_subscription_id AS id_external_subscription,
    external_user_id AS id_external_user,
    contract_id AS id_contract,
    status,
    cancel_reason,
    service_fee,
    charge_day,
    active_from_year_month,
    timestamp(inactive_from) AS ts_inactive_from,
    timestamp(activated_at) AS ts_activated,
    timestamp(canceled_at) AS ts_canceled,
    timestamp(event_at) AS ts_event,
    timestamp(created_at) AS ts_created
FROM
    datalake_retsuko_raw.recurrent_credit_card
