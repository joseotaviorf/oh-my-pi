SELECT
    CAST(NULLIF(TRIM(id_contract), '') AS BIGINT) AS id_contract,
    CAST(NULLIF(TRIM(rollout_phase), '') AS BIGINT) AS rollout_phase,
    NOW() AS ts_load
FROM
    datalake_gsheets_raw.pix_rollout_contracts
