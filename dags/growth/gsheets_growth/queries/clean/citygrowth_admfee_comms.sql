SELECT
    enviar_email AS is_send_email,
    _email_do_proprietario AS email_owner,
    id_imovel AS id_house,
    cidade AS city_name,
    variavel_email AS email_variable_content,
    ts_load
FROM
    datalake_gsheets_raw.citygrowth_admfee_comms
