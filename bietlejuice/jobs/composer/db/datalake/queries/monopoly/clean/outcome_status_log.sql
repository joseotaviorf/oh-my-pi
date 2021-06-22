SELECT
    id,
    outcome_id AS id_outcome,
    status,
    updated_by,
    occurrence_date AS dt_occurence,
    created_at AS ts_created
FROM
    datalake_monopoly_raw.outcome_status_log