SELECT
    CAST(id_realstate_legacy AS BIGINT) AS id_realstate_legacy,
    CAST(id_real_state_new AS BIGINT) AS id_real_state_new
FROM
    datalake_gsheets_raw.velo_legacy_realstate_ids
