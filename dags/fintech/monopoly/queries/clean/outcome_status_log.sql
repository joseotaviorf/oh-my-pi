SELECT
    id,
    outcome_id AS id_outcome,
    external_payment_id AS id_external_payment,
    status,
    updated_by,
    occurrence_date AS dt_occurence,
    created_at AS ts_created
FROM
    datalake_monopoly_raw.outcome_status_log