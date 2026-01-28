SELECT
    id,
    rev,
    revtype AS rev_type,
    revend AS rev_end,
    earning_id AS id_earning,
    replaced_by AS id_replaced_by,
    author,
    reason,
    earning_id_mod AS mod_id_earning,
    replaced_by_mod AS mod_id_replaced_by,
    author_mod AS mod_author,
    reason_mod AS mod_reason,
    invalidated_at_mod AS mod_ts_invalidated,
    TIMESTAMP(invalidated_at) AS ts_invalidated,
    TIMESTAMP(created_at) AS ts_created,
    TIMESTAMP(updated_at) AS ts_updated,
    year,
    month,
    day
FROM
    datalake_big_agent_raw.earning_invalidations_aud