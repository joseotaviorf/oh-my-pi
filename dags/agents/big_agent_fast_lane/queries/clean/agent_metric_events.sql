SELECT
    id,
    event_id AS id_event,
    person_uuid AS uuid_person,
    user_id AS id_user,
    reference_date AS dt_reference,
    metric_name,
    metric_value,
    TIMESTAMP(source_created_at) AS ts_source_created,
    TIMESTAMP(source_updated_at) AS ts_source_updated,
    revision,
    TIMESTAMP(created_at) AS ts_created,
    year,
    month,
    day
FROM
    datalake_big_agent_raw.agent_metric_events
