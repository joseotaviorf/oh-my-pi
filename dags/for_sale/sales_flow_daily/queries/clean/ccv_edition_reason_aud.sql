SELECT
    id,
    ccv_id AS id_ccv,
    rev,
    revtype AS rev_type,
    revend AS rev_end,
    edition_reason,
    edition_reason_mod AS mod_edition_reason,
    ccv_id_mod AS mod_id_ccv,
    created_at AS ts_created,
    updated_at AS ts_updated,
    year,
    month,
    day
FROM
    datalake_sales_flow_raw.ccv_edition_reason_aud

