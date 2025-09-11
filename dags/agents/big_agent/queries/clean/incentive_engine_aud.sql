SELECT
    id,
    rev,
    revtype AS rev_type,
    revend AS rev_end,
    external_condition_id AS id_external_condition,
    external_condition_type,
    incentive_system,
    status,
    external_condition_id_mod AS mod_id_external_condition,
    external_condition_type_mod AS mod_external_condition_type,
    incentive_system_mod AS mod_incentive_system,
    status_mod AS mod_status,
    validity_start_at_mod AS mod_ts_validity_start,
    validity_end_at_mod AS mod_ts_validity_end,
    TIMESTAMP(validity_start_at) AS ts_validity_start,
    TIMESTAMP(validity_end_at) AS ts_validity_end,
    TIMESTAMP(created_at) AS ts_created,
    TIMESTAMP(updated_at) AS ts_updated,
    year,
    month,
    day
FROM
    datalake_big_agent_raw.incentive_engine_aud