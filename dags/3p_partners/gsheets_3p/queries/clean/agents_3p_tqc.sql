SELECT
    NULLIF(id_agent, '') AS id_agent,
    NULLIF(id_user, '') AS id_user,
    NULLIF(rollout_phase, '') AS rollout_phase,
    IF(is_currently_active = 'TRUE', TRUE, FALSE) AS is_currently_active,
    CAST(dt_start AS DATE) AS dt_start,
    CAST(dt_end AS DATE) AS dt_end
FROM
    datalake_gsheets_raw.agents_3p_tqc
