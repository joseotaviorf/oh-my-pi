SELECT
    id AS id_charge_delay,
    rev,
    revtype AS rev_type,
    revend AS rev_end,
    waiting_period,
    created_at AS ts_created,
    updated_at AS ts_updated,
    year,
    month,
    day
FROM
    datalake_owner_fees_homolog_raw.charge_delay_aud
WHERE
    MAKE_DATE(year,month,day) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
