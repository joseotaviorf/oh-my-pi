-- DROP VIEW IF EXISTS public.vw_dim_user_affiliate;
-- CREATE VIEW public.vw_dim_user_affiliate AS 
WITH 
vistorias AS (
	SELECT
		DISTINCT b.agente_id
	FROM
		booking b
	WHERE
		b.tipo = 'Vistoria' 
),
afiliados_full AS (
	SELECT
		ua.id AS sk_user_affiliate,
		ua.id AS id_user_affiliate,
		ua.indicadoPor_id AS sk_user_indicated_by,
		ua.inicioAtuacao AS ts_joined_program,
		ua.ativo AS is_active,
		ua.atualizadoEm AS ts_updated,
		ua.criadoEm AS ts_created,
		ua.origin AS origin,
		CASE
			WHEN ua.affiliateType = 'Doorman' AND u.dados_agente_id IS NOT NULL THEN 'Doorman & Agent'
			WHEN u.dados_agente_id IS NOT NULL THEN 'Agent'
			ELSE ua.affiliateType END AS "type",
		NULLIF(u.dadosagente_numero_creci,'') IS NOT NULL AS is_realstate_agent,
		u.dados_fotografo_id IS NOT NULL AS is_photographer,
		SUBSTRING(u.telefone_principal, 4, 2) AS ddd_telefone,
		uao.utm_source AS tracking_source,
		uao.utm_medium AS tracking_medium,
		uao.utm_campaign AS tracking_campaign,
		uao.utm_content AS tracking_content,
		uao.utm_term AS tracking_term,
		LOWER(regexp_replace(remove_accentuation(uao.utm_campaign), '[^\w]+|_', '', 'g')) AS city_campaign,
		uao.platform AS tracking_platform,
		uao.device_type AS tracking_device_type,
		uao.country AS tracking_country,
		uao.region AS tracking_state,
		uao.city AS tracking_city
	FROM
		user_affiliate ua
		JOIN usuario u 
			ON u.dados_afiliado_id = ua.id
		LEFT JOIN user_affiliate_origin uao 
			ON u.id = uao.user_id
		LEFT JOIN vistorias v 
			ON v.agente_id = ua.id 
),
region_ddd AS (
	SELECT DISTINCT 
		city_group,
		CAST(city_ddd AS VARCHAR) AS ddd,
		regional
	FROM
		staging.dim_region
	WHERE
		LEVEL = 'Cidade' 
),
region_city AS (
	SELECT
		DISTINCT city_name,
		city_group,
		regional
	FROM
		staging.dim_region
	WHERE
		LEVEL = 'Cidade' 
),
affiliate_mkt_city_group AS (
	SELECT
		*,
		COALESCE(
			CASE 
				WHEN af_mkt.city_campaign LIKE '%riodejaneiro%' OR city_campaign LIKE '%rj%' THEN 'Rio de Janeiro'
				WHEN af_mkt.city_campaign LIKE '%belohorizonte%' THEN 'Belo Horizonte'
				WHEN af_mkt.city_campaign LIKE '%florian_polis%' THEN 'Florianópolis'
				WHEN af_mkt.city_campaign LIKE '%bras_lia%' THEN 'Brasília'
				WHEN af_mkt.city_campaign LIKE '%goi_nia%' THEN 'Goiânia'
				WHEN af_mkt.city_campaign LIKE '%portoalegre%' OR city_campaign LIKE 'rs%' THEN 'Porto Alegre'
				WHEN af_mkt.city_campaign LIKE '%curitiba%' THEN 'Curitiba'
				WHEN af_mkt.city_campaign LIKE '%campinas%' THEN 'Campinas'
				WHEN af_mkt.city_campaign LIKE '%s_opaulo%' THEN 'RMSP'
				WHEN af_mkt.city_campaign LIKE '%sp%' THEN 'RMSP'
			END,
			region_city.city_group,
			region_ddd.city_group) AS marketing_city_group,
		COALESCE(region_city.regional, region_ddd.regional) AS regional_ddd_city
	FROM
		afiliados_full af_mkt
	LEFT JOIN region_city 
		ON af_mkt.tracking_city = region_city.city_name
	LEFT JOIN region_ddd 
		ON af_mkt.ddd_telefone = region_ddd.ddd
),
aff_citygrp_with_region AS (
	SELECT
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
		COALESCE(region_city_group.regional,aff_cityreg.regional_ddd_city) AS regional,
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
		aff_cityreg.tracking_city
	FROM
		affiliate_mkt_city_group aff_cityreg
	LEFT JOIN region_ddd AS region_city_group 
		ON aff_cityreg.marketing_city_group = region_city_group.city_group
),
taxonomy AS(
	SELECT
		NULLIF(affiliate_type, '')::VARCHAR affiliate_type,
		NULLIF(tracking_medium, '')::VARCHAR tracking_medium,
		NULLIF(tracking_source, '')::VARCHAR tracking_source,
		NULLIF(tracking_campaign, '')::VARCHAR tracking_campaign,
		NULLIF(mkt_origin, '')::VARCHAR mkt_origin,
		NULLIF(mkt_channel, '')::VARCHAR mkt_channel,
		NULLIF(mkt_medium, '')::VARCHAR mkt_medium,
		NULLIF(mkt_source, '')::VARCHAR mkt_source
	FROM
		gsheets.taxonomy_affiliates
),
applied_taxonomy AS (
	SELECT
		du.sk_user,
		acg.*,
		COALESCE(tax.mkt_origin, 'Other') AS mkt_origin,
		COALESCE(tax.mkt_channel, 'Not Mapped') AS mkt_channel,
		COALESCE(tax.mkt_medium, 'Not Mapped') AS mkt_medium,
		COALESCE(tax.mkt_source, 'Not Mapped') AS mkt_source
	FROM
		aff_citygrp_with_region acg
		JOIN staging.dim_user du
			ON du.dados_afiliado_id = dua.sk_user_affiliate
		LEFT JOIN taxonomy tax 
			ON COALESCE(tax.affiliate_type, '') = COALESCE(dua.type, '')
			AND COALESCE(tax.tracking_medium, '') = COALESCE(dua.tracking_medium, '')
			AND COALESCE(tax.tracking_source, '') = COALESCE(dua.tracking_source, '')
			AND COALESCE(tax.tracking_campaign, '') = COALESCE(dua.tracking_campaign, '')
)
SELECT
	atax.sk_user_affiliate,
	atax.sk_user,
	atax.id_user_affiliate,
	atax.sk_user_indicated_by,
	atax.ts_joined_program,
	atax.is_active,
	atax.ts_updated,
	atax.ts_created,
	atax.origin,
	atax.type,
	atax.marketing_city_group,
	atax.regional,
	atax.is_realstate_agent,
	atax.is_photographer,
	atax.tracking_source,
	atax.tracking_medium,
	atax.tracking_campaign,
	atax.tracking_content,
	atax.tracking_term,
	atax.tracking_platform,
	atax.tracking_device_type,
	atax.tracking_country,
	atax.tracking_state,
	atax.tracking_city,
	atax.mkt_origin,
	atax.mkt_channel,
	atax.mkt_medium,
	atax.mkt_source,
	now() AS ts_load
FROM
	applied_taxonomy atax