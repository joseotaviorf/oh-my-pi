SELECT
    codigo AS id_casamineira_lead,
    fkempresa AS id_company,
    fkimovel AS id_house,
    codigo_cliente_portal AS id_portal_client,
    idlead AS id_portal_lead,
    imovel AS property_description,
    nombre AS name,
    email,
    ddd_telefono AS phone_area_code,
    telefono AS phone,
    mensaje AS message,
    tipo_evento AS event_type,
    json AS json_payload,
    data AS dt_lead,
    paratime AS dt_paratime
FROM
    datalake_union_cdc_raw.leads_casamineira
