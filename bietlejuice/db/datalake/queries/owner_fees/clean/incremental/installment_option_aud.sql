SELECT
    id AS id_installment_option,
    charge_delay_id AS id_charge_delay,
    installment_number,
    rev,
    revtype AS rev_type,
    revend AS rev_end,
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
    datalake_owner_fees_raw.installment_option_aud
WHERE
    year = {year}
    AND month = {month}
    AND day = {day}
