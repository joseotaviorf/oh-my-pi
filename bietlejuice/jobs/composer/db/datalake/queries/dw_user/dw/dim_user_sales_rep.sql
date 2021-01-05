SELECT
    id_user_sales_rep AS sk_user_sales_rep,
    name,
    email,
    phone_number,
    admin_type,
    sales_company,
    is_sales_rep_active,
    dt_sales_rep_started,
    NOW() as ts_load
FROM
    datalake_ebdb_user.user_sales_rep
