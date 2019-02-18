DROP VIEW if exists public.vw_dim_user_affiliate;

CREATE VIEW public.vw_dim_user_affiliate as
 with vistorias as (
 select
 		distinct b.agente_id
 	 from
 	 	booking b
 	 where b.tipo = 'Vistoria'
 )
 select
 	ua.id as sk_user_affiliate,
 	ua.id as id_user_affiliate,
	ua.inicioAtuacao as ts_joined_program,
	ua.tipoAfiliado as category,
	ua.ativo as is_active,
	ua.atualizadoEm as ts_updated,
	ua.criadoEm as ts_created,
	ua.numeroCreci as creci_number,
	ua.origin as origin,
	case when ua.affiliateType = 'Doorman' and u.dados_agente_id is not null then 'Doorman & Agent'
		 when u.dados_agente_id is not null then 'Agent'
		 else ua.affiliateType end as "type",
	v.agente_id is not null as is_inspector,
	nullif(u.dadosagente_numero_creci, '') is not null as is_realstate_agent,
	u.dados_fotografo_id is not null as is_photographer,
	uao.utm_source as tracking_source,
	uao.utm_medium as tracking_medium,
	uao.utm_campaign as tracking_campaign,
	uao.platform as tracking_platform,
	uao.device_type as tracking_device_type,
	uao.country as tracking_country,
	uao.region as tracking_state,
	uao.city as tracking_city,
	now() as ts_load
 from user_affiliate ua
 left join
 	  user_affiliate_origin uao on ua.user_id = uao.user_id
 left join
 	  usuario u on u.dados_afiliado_id = ua.id and lower(u.tipo_admin) <> 'sudo'
 left join
	  vistorias v on v.agente_id = ua.id
  