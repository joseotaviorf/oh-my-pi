SELECT
    id,
    sales_flow_id AS id_sales_flow,
    user_id AS id_user,
    type,
    is_original_user,
    rev,
    revtype,
    revend,
    sales_flow_id_mod AS mod_id_sales_flow,
    user_id_mod AS mod_id_user,
    type_mod AS mod_type,
    is_original_user_mod AS mod_is_original_user,
    created_at AS ts_created,
    updated_at AS ts_updated,
    year,
    month,
    day
FROM
    datalake_sales_flow_raw.sales_flow_users_aud

