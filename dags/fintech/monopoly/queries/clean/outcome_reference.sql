SELECT
    id,
    outcome_id AS id_outcome,
    to AS outcome_to,
    amount,
    outcome_date AS dt_outcome,
    created_at AS ts_created,
    updated_at AS ts_updated
FROM
    datalake_monopoly_raw.outcome_reference