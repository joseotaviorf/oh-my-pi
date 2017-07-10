DROP PROCEDURE IF EXISTS ebdb.list_contacts_and_prospects;

CREATE DEFINER = 'QuintoAndarMain'@'%'
PROCEDURE ebdb.list_contacts_and_prospects()
BEGIN

SELECT
CAST((@cnt := @cnt + 1) AS UNSIGNED)AS cap_id, -- creates the new contact and prospect ID (key)
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
attribution_type,
flow
FROM
(
  SELECT -- leads have a lead_id and self service have a a imovel id. the other values are null. this will allow us to match this table with the fact table in order to add the cap_id to it.

  -- the leads as in the lead table (does not include self service)
    l.id as lead_id,
    null as imovel_id,
    l.anuncioCriadoEm as anuncio_criado_em,
    l.areaTotal as area_total,
    l.bairro,
    l.cep,
    l.cidade,
    l.complemento,
    l.endereco,
    l.numero,
    l.numeroBanheiros as numero_banheiros,
    l.numeroQuartos as numero_quartos,
    l.numeroSuites as numero_suites,
    l.urlAnuncio as url_anuncio,
    l.valor,
    l.telefoneAnunciante as telefone_anunciante,
    l.tipo,
    l.email,
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
    l.automaticallyDiscarded+0 as automatically_discarded,
    e.nome as estado_nome,
    e.abreviacao as estado_abrev,
    da.tipoAfiliado as dados_afiliado_tipo_afiliado,
    da.inicioAtuacao as dados_afiliado_inicio_atuacao,
    da.cidadeAtuacao as dados_afiliado_cidade_atuacao,
    l.region_id,
    l.atualizadoEm  as atualizado_em,
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
    END AS attribution_type,

    "Lead Flow" as flow
    
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
    DadosAfiliado da
    on da.id = l.afiliadoQueIndicou_id
  left join
    Usuario uda
    on uda.dadosAfiliado_id = da.id
  -- limit 50

  UNION

  -- the imoveis that do not have a lead, which are the ones from self service amd the organic IS.
  SELECT
    null as lead_id, -- l.id
    i.id as imovel_id, --
    i.dataCriacao as anuncio_criado_em,
    i.areaTotal as area_total,
    i.bairro,
    i.cep,
    i.cidade,
    i.complemento,
    i.endereco,
    i.numero,
    i.numeroBanheiros as numero_banheiros,
    i.numeroQuartos as numero_quartos,
    i.numeroSuites as numero_suites,
    null as url_anuncio, -- used for leads coming from the crawler, null for self service and organic is
    i.aluguel as valor,
    u.telefonePrincipal as telefone_anunciante, -- by joining with usuario -- also ok for organic is ?

    null as tipo, -- not to be trusted (or replace by null)
    u.email, -- by joining with usuario

    i.lat, 
    i.lng,
    i.condominio, 
    i.iptu, 
    
--    CASE
--      WHEN ip.datePublication IS NOT NULL THEN NULL -- if already published, there is no reason.
--      WHEN cl.tipo = 'InsideSales' then 'Unfinished Organic Inside Sales Process'
--      ELSE 'Unfinished Self-Service Process'
--    END as reason,
    null as reason, -- added later on the view

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
    0 as automatically_discarded, -- fix as 0? yes
    e.nome as estado_nome, 
    e.abreviacao as estado_abrev,

    null as dados_afiliado_tipo_afiliado,
    null as dados_afiliado_inicio_atuacao,
    null as dados_afiliado_cidade_atuacao,
    i.regiao_id as region_id,
    i.atualizadoEm  as atualizado_em,
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
      WHEN cl.imovel_id is NULL AND i.usuario_id=i.usuarioQueCadastrou_id and u.tipoAdmin='Normal' then 'Owner app'
      ELSE 'Other'
    END as attribution_type,

    CASE
      WHEN cl.tipo = 'InsideSales' then 'Lead Flow'
      WHEN cl.imovel_id is NULL AND i.usuario_id=i.usuarioQueCadastrou_id and u.tipoAdmin='Normal' then 'App Flow'
      ELSE 'Other Flow'
    END as flow


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

  WHERE cl.leadConvertido_id is null -- select only the immoveis that are not already selected by what precedes the union

) t CROSS JOIN (SELECT @cnt := 0) AS dummy
;
END