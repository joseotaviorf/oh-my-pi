select  -- count(1)
  l.id,
  l.anuncioCriadoEm as anuncio_criado_em,
  l.areaTotal as area_total,
  l.bairro,
  l.captadoEm as captado_em,
  l.cep,
  l.cidade,
  l.complemento,
  l.endereco,
  l.enderecoCaptado as endereco_captado,
  l.nomeAnunciante as nome_anunciante,
  l.numero,
  l.numeroBanheiros as numero_banheiros,
  l.numeroQuartos as numero_quartos,
  l.numeroSuites as numero_suites,
  l.urlAnuncio as url_anuncio,
  l.valor,
  l.telefoneAnunciante as telefone_anunciante,
  l.valorPorMetroQuad	as valor_por_metro_quad,
  l.valorPorQuartos	as valor_por_quartos,
  l.tipo,
  l.email,
  l.emailCaptador as email_captador,
  l.telefoneCaptador	as telefone_captador,
  l.hot+0 as hot,
  l.proximoFollowup as proximo_followup,
  l.geradoAPartirDeDuplicacao+0 as gerado_a_partir_de_deduplicacao,
  l.dentroAreaAtuacao+0 as dentro_area_atuacao,
  l.sistemaEnviouEmailViaClassificado+0	as sistema_enviou_email_via_classificado,
  l.lat,
  l.lng,
  l.condominio,
  l.iptu,
  coalesce(lr.reason, l.reason) as reason,
  lr.reason_detail as reason_detail,
  l.status,
  l.envioEmailApresentacaoPos	as envio_email_apresentacao_pos,
  l.envioEmailApresentacaoPre	as envio_email_apresentacao_pre,
  l.processado,
  l.origem,
  l.externalId as external_id,
  l.mencionar+0 as mencionar,
  l.referencia,
  l.automaticallyDiscarded+0 as automatically_discarded,
  e.nome as estado_nome,
  e.abreviacao as estado_abrev,
  li.nome as lead_imobiliaria,
  pl.nome as proprietario_nome,
  pl.email as proprietario_email,
  dc.tipoAfiliado as dados_corretor_tipo_afiliado,
  udc.nome as dados_corretor_nome,
  udc.email as dados_corretor_email,
  udgc.nome as dados_gerente_contas_nome,
  udgc.email as dados_gerente_contas_email,
  da.tipoAfiliado as dados_afiliado_tipo_afiliado,
  da.inicioAtuacao as dados_afiliado_inicio_atuacao,
  da.cidadeAtuacao as dados_afiliado_cidade_atuacao,
  l.region_id,
  l.atualizadoEm	as atualizado_em,
  l.criadoEm	as criado_em,
  l.urlSource as url_source,
  l.utmMedium as utm_medium,
  l.utmCampaign as utm_campaign,
  l.utmSource as utm_source,
  ua.id as usuario_que_indicou_id,
  l.codigoImobiliaria as codigo_imobiliaria,
  case
    when SUBSTRING_INDEX(infosExtras,';',1) REGEXP '^-?[0-9]+$'
    then SUBSTRING_INDEX(infosExtras,';',1)
    else NULL
  end as reprocessed_lead_id
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
  DadosGerenteContas dgc
  on dgc.id = l.gerenteContas_id
left join Usuario udgc
  on udgc.id = dgc.usuario_id
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
 left join vw_lead_reason lr
      	on l.reason = lr.reason_detail
where DATE(coalesce(l.criadoEm, '1900-01-01 00:00:00')) <= DATE('{}')