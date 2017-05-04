DROP PROCEDURE IF EXISTS ebdb.list_contacts_and_prospects;

CREATE DEFINER = 'QuintoAndarMain'@'%'
PROCEDURE ebdb.list_contacts_and_prospects()
BEGIN

SELECT
(@cnt := @cnt + 1) AS cap_id, -- creates the new contact and prospect ID (key)
lead_id,
imovel_id,
anuncio_criado_em,
area_total,
bairro,
cep,
cidade,
complemento,
endereco,
numero,
numero_banheiros,
numero_quartos,
numero_suites,
url_anuncio,
valor,
telefone_anunciante,
tipo,
email,
lat, 
lng,
condominio, 
iptu, 
reason,
status, 
envio_email_apresentacao_pos,
envio_email_apresentacao_pre,
processado, 
origem,
external_id,
mencionar,
automatically_discarded,
estado_nome,
estado_abrev,
dados_afiliado_tipo_afiliado,
dados_afiliado_inicio_atuacao,
dados_afiliado_cidade_atuacao,
region_id,
atualizado_em,
url_source,
utm_medium, -- add the network of the afiliado (if the lead was recommended by an affiliate), the utmSource (currenlty only present for leads from the landing page)
utm_campaign,
utm_source,
usuario_que_indicou_id,
usuario_que_cadastrou_id,
self_service,
attribution_type
FROM
(
  SELECT -- leads have a lead_id and self service have a a imovel id. the other values are null. this will allow us to match this table with the fact table in order to add the cap_id to it.

  -- the leads as in the lead table (does not include self service)
    -- autoincrement as cap_id
    l.id as lead_id,
    null as imovel_id,
    l.anuncioCriadoEm as anuncio_criado_em,
    l.areaTotal as area_total,
    l.bairro,
    -- l.captadoEm as captado_em,
    l.cep,
    l.cidade,
    l.complemento,
    l.endereco,
    -- l.enderecoCaptado as endereco_captado,
    -- l.nomeAnunciante as nome_anunciante,
    l.numero,
    l.numeroBanheiros as numero_banheiros,
    l.numeroQuartos as numero_quartos,
    l.numeroSuites as numero_suites,
    l.urlAnuncio as url_anuncio,
    l.valor,
    l.telefoneAnunciante as telefone_anunciante,
    -- l.valorPorMetroQuad as valor_por_metro_quad,
    -- l.valorPorQuartos as valor_por_quartos,
    l.tipo,
    l.email,
    -- l.emailCaptador as email_captador,
    -- l.telefoneCaptador  as telefone_captador,
    -- l.hot+0 as hot,
    -- l.proximoFollowup as proximo_followup,m
    -- l.geradoAPartirDeDuplicacao+0 as gerado_a_partir_de_deduplicacao,
    -- l.dentroAreaAtuacao+0 as dentro_area_atuacao,
    -- l.sistemaEnviouEmailViaClassificado+0 as sistema_enviou_email_via_classificado,
    l.lat, 
    l.lng,
    l.condominio, 
    l.iptu, 
    l.reason,
    l.status, 
    l.envioEmailApresentacaoPos as envio_email_apresentacao_pos,
    l.envioEmailApresentacaoPre as envio_email_apresentacao_pre,
    l.processado, 
    l.origem,
    l.externalId as external_id,
    l.mencionar+0 as mencionar,
    -- l.referencia,
    l.automaticallyDiscarded+0 as automatically_discarded,
    e.nome as estado_nome,
    e.abreviacao as estado_abrev,
    -- li.nome as lead_imobiliaria,
    -- pl.nome as proprietario_nome,
    -- pl.email as proprietario_email,
    -- dc.tipoAfiliado as dados_corretor_tipo_afiliado,
    -- udc.nome as dados_corretor_nome,
    -- udc.email as dados_corretor_email,
    -- udgc.nome as dados_gerente_contas_nome,
    -- udgc.email as dados_gerente_contas_email,
    da.tipoAfiliado as dados_afiliado_tipo_afiliado,
    da.inicioAtuacao as dados_afiliado_inicio_atuacao,
    da.cidadeAtuacao as dados_afiliado_cidade_atuacao,
    l.region_id,
    l.atualizadoEm  as atualizado_em,
    -- l.criadoEm  as criado_em,
    l.urlSource as url_source,
    l.utmMedium as utm_medium,
    l.utmCampaign as utm_campaign,
    l.utmSource as utm_source,
    uda.id as usuario_que_indicou_id, -- da.usuario_id is deprecated !!!
    null as usuario_que_cadastrou_id,
    0 as self_service,

    CASE 
      WHEN l.tipo='Afiliado' AND l.origem='App' THEN 'Affiliate App'
      WHEN l.tipo='Afiliado' AND l.origem='Form' THEN 'Affiliate Form'
      WHEN l.tipo='Afiliado' AND l.origem='Planilha' THEN 'Affiliate Spreadsheet'
      WHEN l.tipo='Afiliado' AND l.origem='Desconhecida' THEN 'Affiliate Unknown'
      WHEN l.tipo='Marketing' AND l.origem='Facebook' THEN 'Facebook' -- facebook link that gives us his info, so we can contact him
      WHEN l.origem='Landing' THEN 'Landing Page Leads'
      ELSE 'Other' 
    END AS attribution_type
    
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
  -- left join
    -- ProprietarioLead pl
    -- on pl.id = l.proprietarioLead_id
  -- left join
    -- AgrupamentoLeadsPorTelefone at
    -- on at.id = l.agrupamentoLeadsPorTelefone_id
  left join
    DadosAfiliado da
    on da.id = l.afiliadoQueIndicou_id
  left join
    Usuario uda
    on uda.dadosAfiliado_id = da.id
  -- limit 50

  UNION

  -- the imoveis that do not have a lead, which are the ones from self service amd the organic IS.
  SELECT
    -- autoincrement as cap_id -- the key referenced in the fact table
    null as lead_id, -- l.id
    i.id as imovel_id, --
    i.dataCriacao as anuncio_criado_em,
    i.areaTotal as area_total,
    i.bairro,
    -- l.captadoEm as captado_em, -- date of submitting to olx -- probably ignore this field too (rely on datacriacao)
    i.cep,
    i.cidade,
    i.complemento,
    i.endereco,
    -- l.enderecoCaptado as endereco_captado, -- not used in ebdb
    -- l.nomeAnunciante as nome_anunciante, -- by joining with usuario
    i.numero,
    i.numeroBanheiros as numero_banheiros,
    i.numeroQuartos as numero_quartos,
    i.numeroSuites as numero_suites,
    null as url_anuncio, -- used for leads coming from the crawler, null for self service and organic is
    i.aluguel as valor,
    u.telefonePrincipal as telefone_anunciante, -- by joining with usuario -- also ok for organic is ?
    -- probably not used :
    -- l.valorPorMetroQuad as valor_por_metro_quad, -- x
    -- l.valorPorQuartos as valor_por_quartos, -- x
    ----

    null as tipo, -- not to be trusted (or replace by null)
    u.email, -- by joining with usuario

    -- not used at all in ebdb :
    -- l.emailCaptador as email_captador, -- ?
    -- l.telefoneCaptador  as telefone_captador,
    -- l.hot+0 as hot,
    -- l.proximoFollowup as proximo_followup,
    -- l.geradoAPartirDeDuplicacao+0 as gerado_a_partir_de_deduplicacao,
    -- l.dentroAreaAtuacao+0 as dentro_area_atuacao,
    -- l.sistemaEnviouEmailViaClassificado+0 as sistema_enviou_email_via_classificado,
    ---- 

    i.lat, 
    i.lng,
    i.condominio, 
    i.iptu, 
    
    CASE
      WHEN ip.datePublication IS NOT NULL THEN NULL -- if already published, there is no reason.
      WHEN cl.tipo = 'InsideSales' then 'Unfinished Organic Inside Sales Process'
      ELSE 'Unfinished Self-Service Process'
    END as reason,
    -- null as reason, -- does not exist for imoveis. null for ss
    null as status, -- i.status and l.status are the same thing ? new, in prospection, converted for leads VS rented, published, edition. see with catach for rule to get the status
    null as envio_email_apresentacao_pos, -- always null for ss
    null as envio_email_apresentacao_pre, -- always null for ss
    null as processado, -- ss has only the checks built into the app
    
    CASE
      WHEN cl.tipo = 'InsideSales' then 'Organic Inside Sales'
      ELSE 'Prop app'-- fix the origin for ss.
    END as origem,

    null as external_id, -- reference to the crawled leads. never the case for self service
    null as mencionar, -- null for ss
    -- l.referencia, -- same as i. referencias? -- not used at all
    0 as automatically_discarded, -- fix as 0? yes
    e.nome as estado_nome, 
    e.abreviacao as estado_abrev,
    -- li.nome as lead_imobiliaria, -- not used at all

    -- duplicated, delete from the dw
    -- pl.nome as proprietario_nome,
    -- pl.email as proprietario_email,
  ---

    -- null as dados_corretor_tipo_afiliado, -- ignore
    -- null as dados_corretor_nome,-- ignore
    -- null as dados_corretor_email,-- ignore
    -- null as dados_gerente_contas_nome, -- ignore
    -- null as dados_gerente_contas_email, -- ignore

    null as dados_afiliado_tipo_afiliado,
    null as dados_afiliado_inicio_atuacao,
    null as dados_afiliado_cidade_atuacao,
    i.regiao_id as region_id,
    i.atualizadoEm  as atualizado_em,
    -- l.criadoEm  as criado_em, -- delete field for leads and ss (same as dataCriacao)
    null as url_source,
    null as utm_medium, -- add the network of the afiliado (if the lead was recommended by an affiliate), the utmSource (currenlty only present for leads from the landing page)
    null as utm_campaign,
    null as utm_source, -- network will be known later, when we have the list of amplitude events in ods
    null as usuario_que_indicou_id,
    i.usuario_id as usuario_que_cadastrou_id,

    CASE
      WHEN cl.tipo = 'InsideSales' then 0
      ELSE 1
    END as self_service,

    CASE
      WHEN cl.tipo = 'InsideSales' then 'Organic Inside Sales'
      ELSE 'Owner app' 
    END as attribution_type


  FROM
    Imovel i
  LEFT JOIN ConversaoLead cl
    on cl.imovel_id = i.id
  left join
    Estado e
    on e.id = i.estado_id
  left join
    Usuario u
    on i.usuario_id = u.id

  LEFT JOIN 
    (
    SELECT id, min(REV) as REV, datePublication
    FROM v_ImovelStatusHistory
    WHERE published = 1
    group by id
    ) ip
    on ip.id = i.id

  WHERE cl.leadConvertido_id is null -- select only the immoveis that are not already selected by what precedes the union

) t CROSS JOIN (SELECT @cnt := 0) AS dummy
;
END