SELECT
    id,
    rev,
    revend AS rev_end,
    revtype AS rev_type,
    fee,
    name,
    version,
    created_at_mod AS mod_created_at,
    updated_at_mod AS mod_updated_at,
    fee_mod AS mod_fee,
    name_mod AS mod_name,
    version_mod AS mod_version,
    TIMESTAMP(created_at) AS ts_created,
    TIMESTAMP(updated_at) AS ts_updated,
    year,
    month,
    day
FROM
    datalake_betopera_raw.billing_fee_type_aud
