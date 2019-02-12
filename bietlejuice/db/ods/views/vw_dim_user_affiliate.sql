DROP VIEW if exists public.vw_dim_user_affiliate;

CREATE VIEW public.vw_dim_user_affiliate as
 select
 	ua.id as sk_user_affiliate,
 	ua.id as id_user_affiliate,
	ua.inicioAtuacao as ts_joined_program,
	ua.tipoAfiliado as category,
	ua.cidadeAtuacao  as work_city,
	ua.ativo as is_active,
	ua.atualizadoEm as ts_updated,
	ua.criadoEm as ts_created,
	ua.numeroCreci as creci_number,
	ua.origin as origin,
	ua.affiliateType as "type",
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
;
  