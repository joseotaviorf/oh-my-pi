SELECT
    id,
    earning_id AS id_earning,
    external_author_id AS id_external_author,
    external_author_type,
    old_value,
    new_value,
    reason,
    TIMESTAMP(created_at) AS ts_created,
    year,
    month,
    day
FROM
    datalake_big_agent_raw.earning_remuneration_log