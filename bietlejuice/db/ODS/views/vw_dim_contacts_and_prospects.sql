DROP VIEW IF EXISTS public.vw_dim_contacts_and_prospects;
CREATE or replace VIEW public.vw_dim_contacts_and_prospects
AS
with base_doorman as (
	select
		"Status" as status,
		892700000 + "Cod Imóvel"::float::bigint as imovel_id
	from
		files.porteiros_legado
	where
		"Status" in ('Listing', 'Alugado', 'Foto', 'Foto com problema', 'Lead')
	and
		"Cod Imóvel" is not null
)
select
  cap.cap_id as sk_cap_id,
  cap.lead_id,
  cap.anuncio_criado_em,
  cap.area_total,
  cap.bairro,
  cap.cep,
  cap.cidade,
  cap.complemento,
  cap.endereco,
  cap.numero,
  cap.numero_banheiros,
  cap.numero_quartos,
  cap.numero_suites,
  cap.url_anuncio,
  cap.valor,
  cap.telefone_anunciante,
  cap.tipo,
  cap.email,
  cap.lat,
  cap.lng,
  cap.condominio,
  cap.iptu,
  CASE
    WHEN cap.imovel_id IS NOT NULL THEN(
    CASE
        WHEN ip.date_publication IS NOT NULL THEN NULL -- if already published, there is no reason.
        WHEN cl.tipo = 'InsideSales' then 'Unfinished Organic Inside Sales Process'
        ELSE 'Unfinished Self-Service Process'
    END)
    ELSE cap.reason
  END as reason,
  cap.status,
  cap.envio_email_apresentacao_pos,
  cap.envio_email_apresentacao_pre,
  cap.processado,
  cap.origem,
  cap.external_id,
  cap.mencionar,
  cap.automatically_discarded,
  cap.estado_nome,
  cap.estado_abrev,
  cap.dados_afiliado_tipo_afiliado,
  cap.dados_afiliado_inicio_atuacao,
  cap.dados_afiliado_cidade_atuacao,
  cap.region_id,
  cap.atualizado_em,
  cap.url_source,
  cap.utm_medium,
  cap.utm_campaign,
  coalesce(cap.utm_source, an1.network, an2.network) as network,
  cap.usuario_que_indicou_id,
  cap.usuario_que_cadastrou_id,
  cap.self_service,
  case
  	when usuario_que_indicou_id=279289 then 'Doorman'
  	when d.imovel_id is not null then 'Doorman'
  	else cap.attribution_type
  end::varchar(100) as attribution_type,
  cap.flow,
  now() as load_timestamp
FROM
  public.contacts_and_prospects cap
left join
  app_network an1
  on cap."usuario_que_indicou_id" = an1.user_id
left join
  app_network an2
  on cap."usuario_que_cadastrou_id" = an2.user_id
left join
  (
  SELECT id, min("datePublication") as date_publication
  FROM imovel_status_history
  WHERE published = 1
  group by id
  ) ip
  on ip.id = cap.imovel_id and cap.imovel_id is not null
left join lead_conversion cl
  on cl.imovel_id = cap.imovel_id and cap.imovel_id is not null
left join base_doorman d
	on cap.imovel_id = d.imovel_id
