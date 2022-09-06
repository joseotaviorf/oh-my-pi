SELECT
    id AS id_specialist,
    sales_flow_id AS id_sales_flow,
    main_user_id AS id_main_user,
    user_id AS id_user,
    kind,
    email,
    name AS specialist_name,
    created_at AS ts_created,
    updated_at AS ts_updated
FROM
    datalake_sales_flow_raw.specialist
