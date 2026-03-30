SELECT
    id,
    external_condition_id AS id_external_condition,
    external_condition_type,
    incentive_system,
    status,
    TIMESTAMP(validity_start_at) AS ts_validity_started,
    TIMESTAMP(validity_end_at) AS ts_validity_ended,
    TIMESTAMP(created_at) AS ts_created,
    TIMESTAMP(updated_at) AS ts_updated,
    year,
    month,
    day
FROM
    datalake_big_agent_raw.incentive_engine