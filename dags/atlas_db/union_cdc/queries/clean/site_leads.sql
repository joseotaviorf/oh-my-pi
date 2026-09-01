SELECT
    codigo AS id_site_lead,
    fkempresa AS id_company,
    fkimovel AS id_house,
    fkcliente AS id_client,
    pkmensagem AS message_template_id,
    imovel_referencia AS property_reference,
    nome AS name,
    email,
    dddtelefone AS phone_area_code,
    telefone AS phone,
    resposta AS reply,
    msg AS message,
    ip AS ip_address,
    temporada AS is_seasonal_rental,
    acomodacoes AS guest_count,
    status,
    data_entrada AS dt_check_in,
    data_saida AS dt_check_out,
    datacad AS dt_registered
FROM
    datalake_union_cdc_raw.leads_site
