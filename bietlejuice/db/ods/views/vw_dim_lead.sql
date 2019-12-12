drop view if exists vw_dim_lead;
create or replace view vw_dim_lead as
 select distinct
  l.id as sk_lead,
  l.id,
  l.area_total,
  l.bairro,
  l.captado_em,
  l.cep,
  l.cidade,
  l.complemento,
  l.endereco,
  l.nome_anunciante,
  l.numero,
  l.numero_banheiros,
  l.numero_quartos,
  l.numero_suites,
  l.url_anuncio,
  l.telefone_anunciante,
  l.tipo,
  l.email,
  l.email_captador,
  l.telefone_captador,
  l.dentro_area_atuacao,
  l.lat,
  l.lng,
  l.condominio,
  l.iptu,
  l.reason,
  l.reason_detail,
  l.status,
  l.processado,
  l.origem,
  l.external_id,
  l.mencionar,
  l.automatically_discarded,
  l.proprietario_nome,
  l.proprietario_email,
  coalesce(lo.affiliate_type, l.affiliate_type) as affiliate_type,
  coalesce(lo.dados_afiliado_inicio_atuacao, l.dados_afiliado_inicio_atuacao) as dados_afiliado_inicio_atuacao,
  coalesce(lo.dados_afiliado_cidade_atuacao, l.dados_afiliado_cidade_atuacao) as dados_afiliado_cidade_atuacao,
  l.region_id,
  l.atualizado_em,
  l.criado_em,
  coalesce(lfet.tracking_source, l.utm_source) as utm_source,
  coalesce(lfet.tracking_medium, l.utm_medium) as utm_medium,
  coalesce(lfet.tracking_campaign, l.utm_campaign) as utm_campaign,
  lfet.tracking_content as utm_content,
  lfet.tracking_term as utm_term,
  lfet.tracking_platform,
  lfet.tracking_region,
  lfet.tracking_city,
  coalesce(l.utm_source, an.network) as network, -- add the network of the campaign (currenlty only present for leads from the landing page), or network of the afiliado (if the lead was recommended by an affiliate)
  coalesce(lo.usuario_que_indicou_id, l.usuario_que_indicou_id) as usuario_que_indicou_id,
  lsf.score_factor,
  coalesce(coalesce(lo.affiliate_type, l.affiliate_type) = 'B2BPartner'
  	or coalesce(b2b_prime.id_lead, b2b_prime_draft.id_lead) is not null
  	or coalesce(lo.codigo_imobiliaria, l.codigo_imobiliaria) is not null
  	or lo.flg_b2b or l.flg_b2b, false) as is_b2b,
  case
    when coalesce(lo.affiliate_type, l.affiliate_type) = 'B2BPartner'
     then 'online'
    when coalesce(b2b_prime.id_lead, b2b_prime_draft.id_lead) is not null
     then 'prime'
  end as b2b_type,
  lsc.sales_company,
  lsc.ts_sales_company_sent,
  l.sale_price,
  l.is_for_rent::integer::boolean as is_for_rent,
  l.is_for_sale::integer::boolean as is_for_sale,
  now() as load_timestamp
FROM
  public.lead l
LEFT JOIN
    public.reprocessed_lead rl
    on rl.id = l.id
LEFT JOIN
    public.lead lo
    on lo.id = rl.id_origin_lead
left join
	public.lead_first_event_tracking lfet
	on lfet.id_lead = l.id
LEFT JOIN
    public.lead_score_factor lsf
    on lsf.lead_id = l.id
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
  on true
left join (
	select
		lc.id_lead
	from lead_conversion lc
	join house h
		on lc.id_house = h.id
	join partner_agent pa
		on h.usuario_id = pa.user_id
	group by 1
) b2b_prime
	on b2b_prime.id_lead = l.id
left join (
	select
	    l.id as id_lead
	from lead l
	join usuario u_b2b
		on u_b2b.telefone_principal = l.telefone_anunciante
	join partner_agent pa_b2b
		on pa_b2b.user_id = u_b2b.id
	where l.origem = 'OwnerPWA'
	group by 1
) b2b_prime_draft
  on b2b_prime_draft.id_lead = l.id
left join
    lead_sales_company lsc
    on lsc.id_lead = l.id
;