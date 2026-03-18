SELECT
    id,
    external_id AS id_external,
    agreement_external_id AS id_agreement_external,
    from_entry_external_id AS id_from_entry_external,
    to_entry_external_id AS id_to_entry_external,
    installment_number,
    accrual_year_month,
    status,
    timestamp(published_at) AS ts_published,
    timestamp(created_at) AS ts_created,
    timestamp(updated_at) AS ts_updated,
    timestamp(retsuko_created_at) AS ts_retsuko_created,
    timestamp(retsuko_updated_at) AS ts_retsuko_updated
FROM
    datalake_retsuko_raw.agreement_entry
