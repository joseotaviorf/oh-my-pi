--DROP VIEW if exists public.vw_dim_user_affiliate;
--CREATE VIEW public.vw_dim_user_affiliate as
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
 	ua.indicadoPor_id as sk_user_indicated_by,
	ua.inicioAtuacao as ts_joined_program,
	ua.ativo as is_active,
	ua.atualizadoEm as ts_updated,
	ua.criadoEm as ts_created,
	ua.origin as origin,
	case when ua.affiliateType = 'Doorman' and u.dados_agente_id is not null then 'Doorman & Agent'
		 when u.dados_agente_id is not null then 'Agent'
		 else ua.affiliateType end as "type",
	nullif(u.dadosagente_numero_creci, '') is not null as is_realstate_agent,
	u.dados_fotografo_id is not null as is_photographer,
	substring(u.telefone_principal,4,2) as ddd_telefone,
	uao.utm_source as tracking_source,
	uao.utm_medium as tracking_medium,
	uao.utm_campaign as tracking_campaign,
	uao.utm_content as tracking_content,
	uao.utm_term as tracking_term,
	lower(regexp_replace(remove_accentuation(uao.utm_campaign), '[^\w]+|_', '', 'g')) as city_campaign,
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
	city_group,
	cast(city_ddd as varchar) as ddd,
	regional
from staging.dim_region
WHERE level = 'Cidade'
),
region_city as (
select distinct
	city_name,
	city_group,
	regional
from staging.dim_region
WHERE level = 'Cidade'
), affiliate_mkt_city_group as (
select
    *,
    coalesce(
        case
            when af_mkt.city_campaign like '%riodejaneiro%' or city_campaign like '%rj%' then 'Rio de Janeiro'
            when af_mkt.city_campaign like '%belohorizonte%' then 'Belo Horizonte'
            when af_mkt.city_campaign like '%florian_polis%' then 'Florianópolis'
            when af_mkt.city_campaign like '%bras_lia%' then 'Brasília'
            when af_mkt.city_campaign like '%goi_nia%' then 'Goiânia'
            when af_mkt.city_campaign like '%portoalegre%' or city_campaign like 'rs%' then 'Porto Alegre'
            when af_mkt.city_campaign like '%curitiba%' then 'Curitiba'
            when af_mkt.city_campaign like '%campinas%' then 'Campinas'
            when af_mkt.city_campaign like '%s_opaulo%' then 'RMSP'
            when af_mkt.city_campaign like '%sp%' then 'RMSP' end,
            region_city.city_group, region_ddd.city_group) as marketing_city_group,
    coalesce(region_city.regional, region_ddd.regional) as regional_ddd_city
from afiliadosfull af_mkt
left join
	region_city on af_mkt.tracking_city = region_city.city_name
left join
	region_ddd on af_mkt.ddd_telefone = region_ddd.ddd
)
select
	aff_cityreg.sk_user_affiliate,
	aff_cityreg.id_user_affiliate,
	aff_cityreg.sk_user_indicated_by,
	aff_cityreg.ts_joined_program,
	aff_cityreg.is_active,
	aff_cityreg.ts_updated,
	aff_cityreg.ts_created,
	aff_cityreg.origin,
	aff_cityreg.type,
	aff_cityreg.marketing_city_group,
	coalesce(region_city_group.regional,aff_cityreg.regional_ddd_city) as regional,
	aff_cityreg.is_realstate_agent,
	aff_cityreg.is_photographer,
	aff_cityreg.tracking_source,
	aff_cityreg.tracking_medium,
	aff_cityreg.tracking_campaign,
	aff_cityreg.tracking_content,
	aff_cityreg.tracking_term,
	aff_cityreg.tracking_platform,
	aff_cityreg.tracking_device_type,
	aff_cityreg.tracking_country,
	aff_cityreg.tracking_state,
	aff_cityreg.tracking_city,
	now() as ts_load
from affiliate_mkt_city_group aff_cityreg
left join
    region_ddd as region_city_group
    on aff_cityreg.marketing_city_group = region_city_group.city_group