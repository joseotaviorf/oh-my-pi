SELECT
    codigo AS id_portal_lead,
    fkempresa AS id_company,
    fkportal AS id_portal,
    pk_portal_mensagem AS portal_message_template_id,
    pk_emails_leads_portais2 AS portal_leads_email_template_id,
    nome AS name,
    email,
    dddtelefone AS phone_area_code,
    telefone AS phone,
    msg AS message,
    codigo_importacao AS import_code,
    inf_referencia AS reference_info,
    status,
    data_lead AS dt_lead,
    datacad AS dt_registered
FROM
    datalake_union_cdc_raw.leads_portais
