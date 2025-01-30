SELECT
    id,
    sales_flow_id AS id_sales_flow,
    inviter_id AS id_inviter,
    invitee_id AS id_invitee,
    folder_id AS id_folder,
    type,
    name,
    email,
    status,
    created_at AS ts_created,
    updated_at AS ts_updated,
    year,
    month,
    day
FROM
    datalake_sales_flow_test_raw.sales_flow_invite