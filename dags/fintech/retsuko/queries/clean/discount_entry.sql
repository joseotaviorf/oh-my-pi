SELECT
    id,
    discount_id AS id_discount,
    entry_external_id AS id_entry_external,
    timestamp(retsuko_created_at) AS ts_retsuko_created
FROM
    datalake_retsuko_raw.discount_entry
