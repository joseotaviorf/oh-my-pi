SELECT
    id_offer,
    id_anunciante_zap AS id_advertiser_zap,
    `código_id_anuncio_zap` AS id_listing_zap,
    `id_imovel_crm_imobiliária` AS id_by_real_estate,
    sk_company,
    cnpj,
    nome_do_anunciante AS advertiser_name,
    link_perfil_anunciante AS advertiser_profile_url,
    tipo_imovel AS house_type,
    link_do_anuncio_do_imovel AS listing_url,
    bairro AS neighborhood,
    cep AS zip_code,
    tipo_negocio AS business_context,
    imovel_usado AS house_usage_status,
    status_de_membros AS member_status,
    gc_leads,
    gc_views,
    `data_criação_anuncio`::DATE AS dt_listing_created,
    `data_ultima_atualização_do_anuncio`::DATE AS dt_listing_updated,
    `data_geração`::DATE AS dt_generated,
    execution_date AS dt_execution,
    year,
    month,
    day
FROM
    datalake_growth_lab_raw.supply_recurrence
WHERE
    MAKE_DATE(year, month, day) BETWEEN '{load_start_date}' AND '{load_end_date}'