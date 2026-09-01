SELECT
    codigo AS id_qa_house,
    fkempresa AS id_company,
    fkimovel AS id_house,
    id_imovel_qa AS id_house_api,
    uid_imovel_qa AS uuid_qa_house,
    status,
    qa_status_sale,
    qa_status_rent,
    json AS json_payload,
    retorno AS feedback_message,
    datacad AS dt_registered,
    dataatua AS dt_updated
FROM
    datalake_union_cdc_raw.qa_imoveis
