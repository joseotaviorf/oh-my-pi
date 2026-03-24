SELECT
    id,
    external_id AS id_external,
    contract_external_id AS id_contract_external,
    from_account_external_id AS id_from_account_external,
    to_account_external_id AS id_to_account_external,
    description,
    amount,
    initial_year_month,
    installments,
    bill_item,
    source,
    normality_control,
    timestamp(canceled_at) AS ts_canceled,
    timestamp(created_at) AS ts_created,
    timestamp(published_at) AS ts_published,
    timestamp(retsuko_created_at) AS ts_retsuko_created,
    timestamp(retsuko_updated_at) AS ts_retsuko_updated
FROM
    datalake_retsuko_raw.recurring_expense
