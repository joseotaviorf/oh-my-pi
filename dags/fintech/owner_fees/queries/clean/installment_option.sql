SELECT
    id,
    charge_delay_id AS id_charge_delay,
    installment_number,
    percentage_of_entry,
    premium_fee,
    valid_from AS dt_valid_from,
    valid_until AS dt_valid_until,
    created_at AS ts_created,
    updated_at AS ts_updated,
    year,
    month,
    day
FROM
    datalake_owner_fees_raw.installment_option
