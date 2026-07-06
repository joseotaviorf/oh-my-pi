SELECT
    id,
    rev,
    revend AS rev_end,
    revtype AS rev_type,
    `type` AS related_as_type,
    updated_at AS ts_updated,
    type_mod AS mod_related_as_type,
    year,
    month,
    day
FROM
    datalake_owner_properties_listing_raw.tb_related_as_aud
