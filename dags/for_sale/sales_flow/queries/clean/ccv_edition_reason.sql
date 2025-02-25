SELECT
    id,
    ccv_id AS id_ccv,
    edition_reason,
    created_at AS ts_created,
    updated_at AS ts_updated,
    year,
    month,
    day
FROM
    datalake_sales_flow_raw.ccv_edition_reason

