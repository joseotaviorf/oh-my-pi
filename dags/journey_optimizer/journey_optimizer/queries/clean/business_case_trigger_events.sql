SELECT
    trigger_binding_id AS id_trigger_binding,
    business_case_id AS id_business_case,
    trigger_event_code,
    trigger_type,
    trigger_context_extractors,
    condition,
    priority,
    is_active,
    created_at AS ts_created
FROM
    datalake_journey_optimizer_raw.business_case_trigger_events
