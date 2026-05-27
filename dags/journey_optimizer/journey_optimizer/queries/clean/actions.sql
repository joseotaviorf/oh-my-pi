SELECT
    action_id AS id_action,
    action_registry_id AS id_action_registry,
    business_case_id AS id_business_case,
    subject_id AS id_subject,
    confirmation_id AS id_confirmation,
    action_type,
    channel_type,
    action_payload,
    evaluation_ids,
    status,
    execution_status,
    constraint_resolution,
    is_aggregated,
    aggregation_deadline AS ts_aggregation_deadline,
    created_at AS ts_created,
    published_at AS ts_published,
    confirmed_at AS ts_confirmed
FROM
    datalake_journey_optimizer_raw.actions
