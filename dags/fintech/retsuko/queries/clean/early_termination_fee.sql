SELECT
    id,
    external_id AS id_external,
    version_external_id AS id_version_external,
    early_termination_external_id AS id_early_termination_external,
    manual_entry_external_id AS id_manual_entry_external,
    reversed_entry_external_id AS id_external_reversed_entry,
    version_type,
    accrual_year_month,
    due_amount,
    installment_number,
    invoice_external_id AS id_invoice_external,
    timestamp(due_date) AS ts_due,
    timestamp(published_at) AS ts_published,
    timestamp(retsuko_created_at) AS ts_retsuko_created,
    timestamp(retsuko_updated_at) AS ts_retsuko_updated
FROM
    datalake_retsuko_raw.early_termination_fee
