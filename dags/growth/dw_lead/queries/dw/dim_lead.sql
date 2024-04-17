WITH lead_b2b AS (
	SELECT DISTINCT
	    cl.id_converted_lead AS id_lead
	FROM datalake_lead.conversion_lead cl
	JOIN datalake_ebdb_clean.house h
	    ON cl.id_house = h.id
	JOIN datalake_ebdb_clean.partner_agent pa
	    ON h.id_user = pa.id_user
	LEFT JOIN datalake_ebdb_clean.partner p_b2b
    	ON p_b2b.id = pa.id_partner
    WHERE p_b2b.type = "PRIME"
),
b2b_prime_draft AS (
	SELECT
	    l.id AS id_lead
	FROM datalake_ebdb_clean.lead l
	JOIN datalake_ebdb_clean.user u_b2b
	    ON u_b2b.main_phone = l.advertiser_phone
	JOIN datalake_ebdb_clean.partner_agent pa_b2b
	    ON pa_b2b.id_user = u_b2b.id
	LEFT JOIN datalake_ebdb_clean.partner p_b2b
    	ON p_b2b.id = pa_b2b.id_partner
	WHERE l.source = 'OwnerPWA' AND p_b2b.type = 'PRIME'
	GROUP BY 1
)
SELECT DISTINCT -- [ODS] This table was migrated from ODS flow and needs a future refactoring to remove castings and renamings
    l.id AS sk_lead,
    l.id,
    l.id_external AS external_id,
    CAST(l.id_region AS INTEGER) AS region_id,
    l.country_code,
    l.total_area AS area_total,
    l.neighborhood AS bairro,
    NULLIF(l.zip_code, '') AS cep,
    l.city AS cidade,
    NULLIF(l.complement, '') AS complemento,
    l.address AS endereco,
    l.house_number AS numero,
    l.advertiser_name AS nome_anunciante,
    l.bathrooms AS numero_banheiros,
    l.bedrooms AS numero_quartos,
    l.suites AS numero_suites,
    l.ad_url AS url_anuncio,
    l.advertiser_phone AS telefone_anunciante,
    l.type AS tipo,
    NULLIF(l.email, '') as email,
    l.pick_up_email AS email_captador,
    l.pick_up_phone AS telefone_captador,
    l.lat,
    l.lng,
    l.condo_price AS condominio,
    l.iptu,
    l.unbounce_page_variant AS ub_page_variant,
    l.unbounce_page_name AS ub_page_name,
    l.reason,
    l.reason_detail,
    l.deadline_of_new_contact,
    l.status,
    l.source AS origem,
    NULLIF(l.lead_owner_name, '') AS proprietario_nome,
    NULLIF(l.lead_owner_email, '') AS proprietario_email,
    COALESCE(lo.affiliate_type, l.affiliate_type) AS affiliate_type,
    COALESCE(lo.affiliate_operation_city, l.affiliate_operation_city) AS dados_afiliado_cidade_atuacao,
    NULLIF(CASE WHEN lfet.id_lead IS NOT NULL THEN lfet.tracking_source else l.utm_source end, '') AS utm_source,
    NULLIF(CASE WHEN lfet.id_lead IS NOT NULL THEN lfet.tracking_medium else l.utm_medium end, '') AS utm_medium,
    NULLIF(CASE WHEN lfet.id_lead IS NOT NULL THEN lfet.tracking_campaign else l.utm_campaign end, '') AS utm_campaign,
    NULLIF(lfet.tracking_content, '') AS utm_content,
    NULLIF(lfet.tracking_term, '') AS utm_term,
    NULLIF(lfet.tracking_platform, '') AS tracking_platform,
    NULLIF(lfet.tracking_region, '') AS tracking_region,
    NULLIF(lfet.tracking_city, '') AS tracking_city,
    -- add the network of the campaign (currently only present for leads from the landing page), or network of the afiliado (if the lead was recommended by an affiliate)
    COALESCE(l.utm_source, hlan.network) AS network,
    CAST(COALESCE(lo.id_user_has_indicated, l.id_user_has_indicated) AS STRING) AS usuario_que_indicou_id,
    lsf.score_factor, -- TODO [ODS] this field is not used anymore and has wrong values in the Composer flow
    CASE
        WHEN COALESCE(lo.affiliate_type, l.affiliate_type) = 'B2BPartner'
            THEN 'online'
        WHEN COALESCE(lead_b2b.id_lead, b2b_prime_draft.id_lead) IS NOT NULL
            THEN 'prime'
    END AS b2b_type,
    lsc.sales_company,
    CAST(l.sale_price AS BIGINT) AS sale_price,
    CAST(l.has_automatically_discarded AS INTEGER) AS automatically_discarded,
    CAST(l.has_processed AS SMALLINT) AS processado,
    COALESCE(
        COALESCE(lo.affiliate_type, l.affiliate_type) = 'B2BPartner'
        OR COALESCE(lead_b2b.id_lead, b2b_prime_draft.id_lead) IS NOT NULL, FALSE
    ) AS is_b2b,
    l.is_for_rent,
    l.is_for_sale,
    CAST(l.is_inside_operation_area AS INTEGER) AS dentro_area_atuacao,
    l.is_enriched_data,
    CAST(l.is_to_be_mentioned AS INTEGER) AS mencionar,
    l.dt_picked_up AS captado_em,
    COALESCE(lo.ts_affiliate_operation_start, l.ts_affiliate_operation_start) AS dados_afiliado_inicio_atuacao,
    lsc.ts_sales_company_sent,
    l.ts_created AS criado_em,
    l.ts_updated AS atualizado_em,
    NOW() AS load_timestamp
FROM
  datalake_lead.lead l
LEFT JOIN datalake_lead.reprocessed_lead rl
    ON rl.id = l.id
LEFT JOIN datalake_lead.lead lo
    ON lo.id = rl.id_origin_lead
LEFT JOIN datalake_lead_tracking.lead_first_event_tracking lfet
	ON lfet.id_lead = l.id
LEFT JOIN datalake_crm_lead.lead_score_factor lsf
    ON lsf.id_lead = l.id
LEFT JOIN datalake_static_files_raw.historical_lead_app_network hlan
    ON l.id_user_has_indicated = hlan.user_id
LEFT join lead_b2b
	ON lead_b2b.id_lead = l.id
LEFT JOIN b2b_prime_draft
    ON b2b_prime_draft.id_lead = l.id
LEFT JOIN datalake_wololo_lead.lead_sales_company lsc
    ON lsc.id_lead = l.id

UNION 

SELECT
  CAST('-1' AS bigint) AS sk_lead,
  CAST(NULL AS bigint) AS id,
  CAST(NULL AS string) AS external_id,
  CAST(NULL AS int) AS region_id,
  CAST(NULL AS string) AS country_code,
  CAST(NULL AS int) AS area_total,
  CAST(NULL AS string) AS bairro,
  CAST(NULL AS string) AS cep,
  CAST(NULL AS string) AS cidade,
  CAST(NULL AS string) AS complemento,
  CAST(NULL AS string) AS endereco,
  CAST(NULL AS string) AS numero,
  CAST(NULL AS string) AS nome_anunciante,
  CAST(NULL AS int) AS numero_banheiros,
  CAST(NULL AS int) AS numero_quartos,
  CAST(NULL AS int) AS numero_suites,
  CAST(NULL AS string) AS url_anuncio,
  CAST(NULL AS string) AS telefone_anunciante,
  CAST(NULL AS string) AS tipo,
  CAST(NULL AS string) AS email,
  CAST(NULL AS string) AS email_captador,
  CAST(NULL AS string) AS telefone_captador,
  CAST(NULL AS decimal(10, 7)) AS lat,
  CAST(NULL AS decimal(10, 7)) AS lng,
  CAST(NULL AS int) AS condominio,
  CAST(NULL AS int) AS iptu,
  CAST(NULL AS string) AS ub_page_variant,
  CAST(NULL AS string) AS ub_page_name,
  CAST(NULL AS string) AS reason,
  CAST(NULL AS string) AS reason_detail,
  CAST(NULL AS string) AS deadline_of_new_contact,
  CAST(NULL AS string) AS status,
  CAST(NULL AS string) AS origem,
  CAST(NULL AS string) AS proprietario_nome,
  CAST(NULL AS string) AS proprietario_email,
  CAST(NULL AS string) AS affiliate_type,
  CAST(NULL AS string) AS dados_afiliado_cidade_atuacao,
  CAST(NULL AS string) AS utm_source,
  CAST(NULL AS string) AS utm_medium,
  CAST(NULL AS string) AS utm_campaign,
  CAST(NULL AS string) AS utm_content,
  CAST(NULL AS string) AS utm_term,
  CAST(NULL AS string) AS tracking_platform,
  CAST(NULL AS string) AS tracking_region,
  CAST(NULL AS string) AS tracking_city,
  CAST(NULL AS string) AS network,
  CAST(NULL AS string) AS usuario_que_indicou_id,
  CAST(NULL AS bigint) AS score_factor,
  CAST(NULL AS string) AS b2b_type,
  CAST(NULL AS string) AS sales_company,
  CAST(NULL AS bigint) AS sale_price,
  CAST(NULL AS int) AS automatically_discarded,
  CAST(NULL AS smallint) AS processado,
  CAST(NULL AS boolean) AS is_b2b,
  CAST(NULL AS boolean) AS is_for_rent,
  CAST(NULL AS boolean) AS is_for_sale,
  CAST(NULL AS int) AS dentro_area_atuacao,
  CAST(NULL AS boolean) AS is_enriched_data,
  CAST(NULL AS int) AS mencionar,
  CAST(NULL AS date) AS captado_em,
  CAST(NULL AS timestamp) AS dados_afiliado_inicio_atuacao,
  CAST(NULL AS timestamp) AS ts_sales_company_sent,
  CAST(NULL AS timestamp) AS criado_em,
  CAST(NULL AS timestamp) AS atualizado_em,
  CAST(NULL AS timestamp) AS load_timestamp