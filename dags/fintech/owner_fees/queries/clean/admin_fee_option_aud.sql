SELECT
    id AS id_admin_fee_option,
    rev,
    revtype AS rev_type,
    revend AS rev_end,
    admin_fee,
    starts_at AS dt_start,
    created_at AS ts_created,
    updated_at AS ts_updated
FROM
    datalake_owner_fees_raw.admin_fee_option_aud
