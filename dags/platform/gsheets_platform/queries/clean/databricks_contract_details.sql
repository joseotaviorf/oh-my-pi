SELECT
    sku AS cluster_compute_type,
    dbu_price,
    dt_contract_started,
    dt_contract_ended
FROM
    datalake_gsheets_raw.databricks_contract_details
