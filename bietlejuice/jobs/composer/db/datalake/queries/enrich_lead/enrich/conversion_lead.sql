SELECT
    id,
    id_house,
    id_converted_lead,
    id_sales_rep,
    id_account_manager,
    is_validated,
    status,
    type,
    ts_conversion,
    coalesce(ts_created, ts_conversion) as ts_converted,
    ts_created,
    ts_updated
FROM
    datalake_ebdb_clean.conversion_lead