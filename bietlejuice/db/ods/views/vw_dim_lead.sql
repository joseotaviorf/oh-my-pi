DROP VIEW if exists public.vw_dim_lead;

CREATE VIEW public.vw_dim_lead as
 select
  distinct
  l.id as sk_lead,
  l.id,
  l.anuncio_criado_em,
  l.area_total,
  l.bairro,
  l.captado_em,
  l.cep,
  l.cidade,
  l.complemento,
  l.endereco,
  l.endereco_captado,
  l.nome_anunciante,
  l.numero,
  l.numero_banheiros,
  l.numero_quartos,
  l.numero_suites,
  l.url_anuncio,
  l.valor,
  l.telefone_anunciante,
  l.valor_por_metro_quad,
  l.valor_por_quartos,
  l.tipo,
  l.email,
  l.email_captador,
  l.telefone_captador,
  l.hot,
  l.proximo_followup,
  l.gerado_a_partir_de_deduplicacao,
  l.dentro_area_atuacao,
  l.sistema_enviou_email_via_classificado,
  l.lat,
  l.lng,
  l.condominio,
  l.iptu,
  l.reason,
  l.reason_detail,
  l.status,
  l.envio_email_apresentacao_pos,
  l.envio_email_apresentacao_pre,
  l.processado,
  l.origem,
  l.external_id,
  l.mencionar,
  l.referencia,
  l.automatically_discarded,
  l.estado_nome,
  l.estado_abrev,
  l.lead_imobiliaria,
  l.proprietario_nome,
  l.proprietario_email,
  l.dados_corretor_tipo_afiliado,
  l.dados_corretor_nome,
  l.dados_corretor_email,
  l.dados_gerente_contas_nome,
  l.dados_gerente_contas_email,
  coalesce(lo.dados_afiliado_tipo_afiliado, l.dados_afiliado_tipo_afiliado) as dados_afiliado_tipo_afiliado,
  coalesce(lo.dados_afiliado_inicio_atuacao, l.dados_afiliado_inicio_atuacao) as dados_afiliado_inicio_atuacao,
  l.region_id,
  l.atualizado_em,
  l.criado_em,
  l.url_source,
  l.utm_source,
  l.utm_medium,
  l.utm_campaign,
  coalesce(l.utm_source, an.network) as network, -- add the network of the campaign (currenlty only present for leads from the landing page), or network of the afiliado (if the lead was recommended by an affiliate)
  coalesce(lo.usuario_que_indicou_id, l.usuario_que_indicou_id) as usuario_que_indicou_id,
  l.flg_city_served,
  l.flg_latlng_served,
  l.flg_location_served,
  now() as load_timestamp
FROM
  public.lead l
LEFT JOIN
    public.reprocessed_lead rl
    on rl.id = l.id
LEFT JOIN
    public.lead lo
    on lo.id = rl.id_origin_lead
left join lateral
(
  select 
   	*
  from
  	app_network an
  where
  	l.usuario_que_indicou_id::integer = an.user_id
  limit 1
)  an
  on true;

  