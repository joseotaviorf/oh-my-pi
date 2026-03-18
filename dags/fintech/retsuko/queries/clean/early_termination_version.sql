SELECT
    id,
    external_id AS id_external,
    early_termination_external_id AS id_early_termination_external,
    version_type,
    active AS is_active,
    fee_amount_agreed,
    fee_amount_original,
    number_of_installments,
    timestamp(base_due_date) AS ts_base_due,
    timestamp(created_at) AS ts_created,
    timestamp(published_at) AS ts_published,
    timestamp(retsuko_created_at) AS ts_retsuko_created,
    timestamp(retsuko_updated_at) AS ts_retsuko_updated
FROM
    datalake_retsuko_raw.early_termination_version
