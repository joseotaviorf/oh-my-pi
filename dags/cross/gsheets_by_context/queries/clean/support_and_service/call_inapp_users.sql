SELECT
    id_experiment,
    sk_user AS id_user,
    telefone_principal AS main_phone_number,
    dt_inclusao AS dt_included
FROM
    datalake_gsheets_raw.call_inapp_users
