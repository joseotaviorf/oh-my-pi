SELECT
    id,
    feedback_batch_id AS id_feedback_batch,
    field_name,
    user_selection,
    saved_value,
    assessment_display_type,
    assessment_consolidated_status,
    observation_id AS id_observation,
    trace_id,
    comment,
    status,
    error_message,
    created_at AS ts_created,
    updated_at AS ts_updated,
    year,
    month,
    day
FROM
    datalake_legalops_raw.contract_analysis_feedback_observations
