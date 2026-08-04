SELECT
    prompt_id,
    COUNT_IF(inference_status = 'missing') AS missing_count,
    COUNT_IF(inference_status = 'done') AS done_count,
    MAX(CASE WHEN inference_status = 'missing' THEN age_days END) AS oldest_missing_age_days
FROM
    datalake_vocs_machina_planning.vocs_machina_backfill_status
GROUP BY
    prompt_id
