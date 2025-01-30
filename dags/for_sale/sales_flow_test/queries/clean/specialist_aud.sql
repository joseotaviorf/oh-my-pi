SELECT
    id AS id_specialist_aud,
    sales_flow_id AS id_sales_flow,
    main_user_id AS id_main_user,
    user_id AS id_user,
    rev,
    revtype AS rev_type,
    revend AS rev_end,
    kind,
    email,
    name AS specialist_name,
    sales_flow_id_mod AS mod_id_sales_flow,
    main_user_id_mod AS mod_id_main_used,
    user_id_mod AS mod_id_user,
    kind_mod AS mod_kind,
    email_mod AS mod_email,
    name_mod AS mod_specialist_name,
    created_at AS ts_created,
    updated_at AS ts_updated,
    year,
    month,
    day
FROM
    datalake_sales_flow_test_raw.specialist_aud