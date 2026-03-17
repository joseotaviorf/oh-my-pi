SELECT
    id,
    installment_id AS id_installment,
    settlement_provider,
    settlement_info,
    status,
    created_at AS ts_created,
    updated_at AS ts_updated
FROM
    datalake_lending_raw.installment_settlement
