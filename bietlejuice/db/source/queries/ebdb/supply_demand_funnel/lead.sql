select distinct
  l.id,
  l.areaTotal as area_total,
  l.bairro,
  l.captadoEm as captado_em,
  l.cep,
  l.cidade,
  l.complemento,
  l.endereco,
  l.nomeAnunciante as nome_anunciante,
  l.numero,
  l.numeroBanheiros as numero_banheiros,
  l.numeroQuartos as numero_quartos,
  l.numeroSuites as numero_suites,
  l.urlAnuncio as url_anuncio,
  l.telefoneAnunciante as telefone_anunciante,
  l.tipo,
  l.email,
  l.emailCaptador as email_captador,
  l.telefoneCaptador	as telefone_captador,
  l.dentroAreaAtuacao+0 as dentro_area_atuacao,
  l.lat,
  l.lng,
  l.condominio,
  l.iptu,
  l.unbouncePageVariant as ub_page_variant,
  l.unbouncePageName as ub_page_name,
  coalesce(lr.reason, l.reason) as reason,
  -- Consider Old and New reasons
  lr.reason_detail as reason_detail,
  l.status,
  l.processado,
  l.origem,
  l.isEnrichedData+0 as is_enriched_data,
  l.externalId as external_id,
  l.mencionar+0 as mencionar,
  l.automaticallyDiscarded+0 as automatically_discarded,
  pl.id as id_lead_owner,
  pl.nome as proprietario_nome,
  pl.email as proprietario_email,
  l.affiliateType as affiliate_type,
  da.inicioAtuacao as dados_afiliado_inicio_atuacao,
  da.cidadeAtuacao as dados_afiliado_cidade_atuacao,
  l.region_id,
  l.atualizadoEm	as atualizado_em,
  l.criadoEm	as criado_em,
  l.utmMedium as utm_medium,
  l.utmCampaign as utm_campaign,
  l.utmSource as utm_source,
  ua.id as usuario_que_indicou_id,
  l.codigoImobiliaria as codigo_imobiliaria,
  coalesce(infosExtras like '%source=b2b_%', 0) as flg_b2b,
  l.salePrice as sale_price,
  coalesce(l.forRent+0, 1) as is_for_rent,
  l.forSale+0 as is_for_sale,
  l.dadosAgente_id as lead_agent_id
from
  Lead l
left join
  Estado e
  on e.id = l.estado_id
left join
  LeadImobiliaria li
  on li.id = l.imobiliaria_id
left join
  DadosCorretor dc
  on dc.id = l.corretorQueIndicou_id
left JOIN
  Usuario udc
  on udc.id = dc.usuario_id
left join
  ProprietarioLead pl
  on pl.id = l.proprietarioLead_id
left join
  AgrupamentoLeadsPorTelefone at
  on at.id = l.agrupamentoLeadsPorTelefone_id
left join
  DadosAfiliado da
  on da.id = l.afiliadoQueIndicou_id
left join
   Usuario ua
   on da.id=ua.dadosAfiliado_id
left join
 	vw_lead_reason lr
     	on l.reason = lr.reason_detail
where DATE(coalesce(l.criadoEm, '1900-01-01 00:00:00')) <= DATE('{}')
