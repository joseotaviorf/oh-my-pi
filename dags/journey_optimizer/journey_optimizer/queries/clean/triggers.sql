SELECT
    trigger_event_id AS id_trigger_event,
    business_case_id AS id_business_case,
    subject_id AS id_subject,
    trigger_event_code,
    subject_type,
    state_snapshot,
    trigger_context,
    occurred_at AS ts_occurred,
    created_at AS ts_created
FROM
    datalake_journey_optimizer_raw.triggers
