DROP VIEW if exists public.vw_dim_user_affiliate;

CREATE VIEW public.vw_dim_user_affiliate as
 with vistorias as (
 select
 		distinct b.agente_id
 	 from
 	 	booking b
 	 where b.tipo = 'Vistoria'
 ),
 afiliadosfull as (
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
	case when ua.affiliateType = 'Doorman' and u.dados_agente_id is not null then 'Doorman & Agent'
		 when u.dados_agente_id is not null then 'Agent'
		 else ua.affiliateType end as "type",
	v.agente_id is not null as is_inspector,
	nullif(u.dadosagente_numero_creci, '') is not null as is_realstate_agent,
	u.dados_fotografo_id is not null as is_photographer,
	substring(u.telefone_principal,4,2) as ddd_telefone,
	uao.utm_source as tracking_source,
	uao.utm_medium as tracking_medium,
	uao.utm_campaign as tracking_campaign,
	regexp_replace(remove_accentuation(uao.utm_campaign), '\[^a-zA-Z]', '') as city_campaign,
	uao.platform as tracking_platform,
	uao.device_type as tracking_device_type,
	uao.country as tracking_country,
	uao.region as tracking_state,
	uao.city as tracking_city
from user_affiliate ua
 join
 	  usuario u on u.dados_afiliado_id = ua.id
 left join
 	  user_affiliate_origin uao on u.id = uao.user_id
 left join
	  vistorias v on v.agente_id = ua.id
),
region_ddd as (
select distinct
	cast(city_ddd as varchar) as ddd,
	regional
from public.vw_dim_region
),
region_city as (
select distinct
	city_name,
	city_group,
	regional
from public.vw_dim_region
)
select
	afl.sk_user_affiliate,
	afl.id_user_affiliate,
	afl.ts_joined_program,
	afl.category,
	afl.work_city,
	afl.is_active,
	afl.ts_updated,
	afl.ts_created,
	afl.creci_number,
	afl.origin,
	afl.type,
	coalesce(
	case
		when city_campaign like '%riodejaneiro%' or city_campaign like '%rj%' then 'Rio de Janeiro'
		when city_campaign like '%belohorizonte%' then 'Belo Horizonte'
		when city_campaign like '%florian_polis%' then 'Florianópolis'
		when city_campaign like '%bras_lia%' then 'Brasília'
		when city_campaign like '%goi_nia%' then 'Goiânia'
		when city_campaign like '%portoalegre%' or city_campaign like 'rs%' then 'Porto Alegre'
		when city_campaign like '%curitiba%' then 'Curitiba'
		when city_campaign like '%campinas%' then 'Campinas'
		when city_campaign like '%s_opaulo%' then 'RMSP'
		when city_campaign like '%sp%' then 'RMSP' end,
	    region_city.city_group) as marketing_city_group,
	coalesce(region_city.regional, region_ddd.regional) as regional,
	afl.is_inspector,
	afl.is_realstate_agent,
	afl.is_photographer,
	afl.tracking_source,
	afl.tracking_medium,
	afl.tracking_campaign,
	afl.tracking_platform,
	afl.tracking_device_type,
	afl.tracking_country,
	afl.tracking_state,
	afl.tracking_city,
	now() as ts_load
from afiliadosfull afl
left join
	region_city on afl.tracking_city = region_city.city_name
left join
	region_ddd on afl.ddd_telefone = region_ddd.ddd