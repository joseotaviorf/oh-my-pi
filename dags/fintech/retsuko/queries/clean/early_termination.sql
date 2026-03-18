SELECT
    id,
    external_id AS id_external,
    contract_external_id AS id_contract_external,
    from_account_id AS id_from_account,
    to_account_id AS id_to_account,
    dont_charge_adm_fee,
    prior_notice,
    fee_amount_agreed,
    version,
    source,
    normality_control,
    initial_year_month,
    timestamp(canceled_at) AS ts_canceled,
    timestamp(created_at) AS ts_created,
    timestamp(published_at) AS ts_published,
    timestamp(retsuko_created_at) AS ts_retsuko_created,
    timestamp(retsuko_updated_at) AS ts_retsuko_updated
FROM
    datalake_retsuko_raw.early_termination
