SELECT
    id,
    rev,
    revtype AS rev_type,
    revend AS rev_end,
    ccv_flow_id AS id_ccv_flow,
    ccv_flow_id_mod AS mod_id_ccv_flow,
    name,
    name_mod AS mod_name,
    storage_hash_token,
    storage_hash_token_mod AS mod_storage_hash_token,
    deleted_at AS ts_deleted,
    deleted_at_mod AS mod_ts_deleted,
    created_at AS ts_created,
    updated_at AS ts_updated,
    year,
    month,
    day
FROM
    datalake_sales_flow_raw.ccv_additional_file_aud
