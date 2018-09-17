DROP VIEW if exists public.vw_dim_lead;

CREATE VIEW public.vw_dim_lead as
 select
  id as sk_lead,
  id,
  anuncio_criado_em,
  area_total,
  bairro,
  captado_em,
  cep,
  cidade,
  complemento,
  endereco,
  endereco_captado,
  nome_anunciante,
  numero,
  numero_banheiros,
  numero_quartos,
  numero_suites,
  url_anuncio,
  valor,
  telefone_anunciante,
  valor_por_metro_quad,
  valor_por_quartos,
  tipo,
  email,
  email_captador,
  telefone_captador,
  hot,
  proximo_followup,
  gerado_a_partir_de_deduplicacao,
  dentro_area_atuacao,
  sistema_enviou_email_via_classificado,
  lat,
  lng,
  condominio,
  iptu,
  reason,
  reason_detail,
  status,
  envio_email_apresentacao_pos,
  envio_email_apresentacao_pre,
  processado,
  origem,
  external_id,
  mencionar,
  referencia,
  automatically_discarded,
  estado_nome,
  estado_abrev,
  lead_imobiliaria,
  proprietario_nome,
  proprietario_email,
  dados_corretor_tipo_afiliado,
  dados_corretor_nome,
  dados_corretor_email,
  dados_gerente_contas_nome,
  dados_gerente_contas_email,
  dados_afiliado_tipo_afiliado,
  dados_afiliado_inicio_atuacao,
  dados_afiliado_cidade_atuacao,
  region_id,
  atualizado_em,
  criado_em,
  url_source,
  utm_source,
  utm_medium,
  utm_campaign,
  coalesce(l.utm_source, an.network) as network, -- add the network of the campaign (currenlty only present for leads from the landing page), or network of the afiliado (if the lead was recommended by an affiliate)
  usuario_que_indicou_id,
  now() as load_timestamp
FROM
  public.lead l
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

  