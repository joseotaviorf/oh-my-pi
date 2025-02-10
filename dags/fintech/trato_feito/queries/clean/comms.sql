SELECT
    id,
    client_id AS id_client,
    debtor_external_id AS id_debtor_external,
    bill_external_id AS id_bill_external,
    debtor_id AS id_debtor,
    experiment,
    experiment_group,
    strategy,
    should_receive_comms,
    start_date AS dt_start,
    end_date AS dt_end,
    created_at AS ts_created,
    updated_at AS ts_updated
FROM datalake_trato_feito_raw.comms
