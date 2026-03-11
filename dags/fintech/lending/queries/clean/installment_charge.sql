SELECT
    id,
    installment_id AS id_installment,
    type,
    charge_info,
    created_at AS ts_created,
    updated_at AS ts_updated
FROM
    datalake_lending_raw.installment_charge
