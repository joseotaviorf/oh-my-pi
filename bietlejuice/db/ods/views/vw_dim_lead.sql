--drop view if exists vw_dim_lead;
--create or replace view vw_dim_lead as
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
  l.ub_page_variant,
  l.reason,
  l.reason_detail,
  case
		when l.reason_detail in ('CONTACT_ON_BLOCK_LIST', 'CONTACT_KNOW_OWNER','CONTACT_WASNT_THE_HOUSE_OWNER','CONTACT_DIDNT_EXIST','OWNER_DIDNT_ANSWER_PHONE','HOUSE_ONLY_FOR_SELLING',
					'HOUSE_WITH_BAD_CONDITIONS','HOUSE_WAS_A_BUSINESS_REAL_ESTATE','HOUSE_PRICE_WAS_OUT_OF_BOUNDS','HOUSE_WAS_OUT_OF_HOUSE_RENTING_REGIONS',
					'HOUSE_WAS_OUT_OF_HOUSE_SALES_REGIONS','HOUSE_ALREADY_SOLD','HOUSE_ALREADY_PUBLISHED','DUPLICATED_LEAD') then 'Nunca'
		when l.reason_detail in ('ISSUES_WITH_HOUSE_ENTRANCE_CONDITIONS','HOUSE_UNDER_EXCLUSIVITY_CONTRACT','OWNER_WITH_PRIME_PROFILE','OWNER_DIDNT_WANT_ADMINISTRATION',
					'OWNER_CONSIDERED_ADMINISTRATION_FEE_TOO_HIGH','OWNER_CONSIDERED_BROKERAGE_FEE_TOO_HIGH') then 'Curto Prazo'
		when l.reason_detail in ('SEASONAL_RENT','ONLY_PART_OF_THE_HOUSE_WAS_AVAILABLE_FOR_RENTING','ISSUES_WITH_HOUSE_DOCUMENTATION','HOUSE_UNDER_MAJOR_RENOVATION','HOUSE_ALREADY_RENTED',
					'OWNER_GAVE_UP_RENTING','OWNER_DISAGREE_CHARGES_PAYMENTS','OWNER_DIDNT_LISTEN_TO_PITCH') then 'Longo Prazo'
		end as deadline_of_new_contact,
  l.status,
  l.processado,
  l.origem,
  l.is_enriched_data::integer::boolean as is_enriched_data,
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
  case when lfet.id_lead is not null then lfet.tracking_source else l.utm_source end as utm_source,
  case when lfet.id_lead is not null then lfet.tracking_medium else l.utm_medium end as utm_medium,
  case when lfet.id_lead is not null then lfet.tracking_campaign else l.utm_campaign end as utm_campaign,
  lfet.tracking_content as utm_content,
  lfet.tracking_term as utm_term,
  lfet.tracking_platform,
  lfet.tracking_region,
  lfet.tracking_city,
  coalesce(l.utm_source, an.network) as network, -- add the network of the campaign (currenlty only present for leads from the landing page), or network of the afiliado (if the lead was recommended by an affiliate)
  coalesce(lo.usuario_que_indicou_id, l.usuario_que_indicou_id) as usuario_que_indicou_id,
  lsf.score_factor,
  coalesce(coalesce(lo.affiliate_type, l.affiliate_type) = 'B2BPartner'
  	or coalesce(lead_b2b.id, b2b_prime_draft.id_lead) is not null
    , false) as is_b2b,
  case
    when coalesce(lo.affiliate_type, l.affiliate_type) = 'B2BPartner'
     then 'online'
    when coalesce(lead_b2b.id, b2b_prime_draft.id_lead) is not null
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
LEFT join (
	select distinct lc.id_lead as id
	from lead_conversion lc
	join house h
	    on lc.id_house = h.id
	join partner_agent pa
	    on h.usuario_id = pa.user_id
	left join partner p_b2b
    	on p_b2b.id = pa.partner_id
    where p_b2b."type" = 'PRIME'
) lead_b2b
	on lead_b2b.id = l.id
left join (
	select
	    l.id as id_lead
	from lead l
	join usuario u_b2b
		on u_b2b.telefone_principal = l.telefone_anunciante
	join partner_agent pa_b2b
		on pa_b2b.user_id = u_b2b.id
	left join partner p_b2b
    	on p_b2b.id = pa_b2b.partner_id
	where l.origem = 'OwnerPWA' and p_b2b.type = 'PRIME'
	group by 1
) b2b_prime_draft
  on b2b_prime_draft.id_lead = l.id
left join
    lead_sales_company lsc
    on lsc.id_lead = l.id
;
