SELECT
    id,
    pulse_id AS id_pulse,
    card_id AS id_card,
    position,
    include_csv AS has_csv_included,
    include_xls AS has_xls_included
FROM
    datalake_metabase_raw.pulse_card
