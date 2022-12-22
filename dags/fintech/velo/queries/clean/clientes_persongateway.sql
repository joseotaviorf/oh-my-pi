SELECT
    id,
    userinsert AS id_user_insert,
    userupdate AS id_user_update,
    person AS id_person,
    gateway AS id_bank_gateway,
    customer AS id_invoice_customer,
    BOOLEAN(active) AS is_active,
    dateinsert AS ts_inserted,
    dateupdate AS ts_updated
FROM
    datalake_velo_raw.clientes_persongateway
