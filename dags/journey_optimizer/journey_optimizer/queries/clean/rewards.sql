SELECT
    reward_id AS id_reward,
    trigger_event_id AS id_trigger_event,
    business_case_id AS id_business_case,
    reward_registry_id AS id_reward_registry,
    subject_id AS id_subject,
    trigger_event_code,
    subject_type,
    state_snapshot,
    trigger_context,
    reward_type,
    reward_metadata,
    reward_value,
    occurred_at AS ts_occurred,
    created_at AS ts_created
FROM
    datalake_journey_optimizer_raw.rewards
