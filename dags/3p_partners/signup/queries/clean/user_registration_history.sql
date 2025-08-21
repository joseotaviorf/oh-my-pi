SELECT
    id,
    requester_person_uuid AS uuid_person_requester,
    target_person_uuid AS uuid_person_target,
    operation,
    reason,
    additional_comment,
    channel,
    executed_at AS ts_executed,
    year,
    month,
    day
FROM
    datalake_signup_raw.user_registration_history