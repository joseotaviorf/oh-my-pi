SELECT
    id,
    comms_id AS id_comms,
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
    comms_created_at AS ts_comms_created,
    comms_updated_at AS ts_comms_updated,
    created_at AS ts_created
FROM datalake_trato_feito_raw.comms_aud
