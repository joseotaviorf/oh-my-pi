SELECT
    id,
    rev,
    revend AS rev_end,
    revtype AS rev_type,
    `type` AS source_type,
    updated_at AS ts_updated,
    type_mod AS mod_source_type,
    year,
    month,
    day
FROM
    datalake_owner_properties_listing_raw.tb_source_type_aud
