create view 
select
  i.id as id_imovel,  
  a.id as id_schedule,  
  prop.id as id_owner,
  dc.usuario_id as id_user_realtor,
  daf.usuario_id as id_user_affiliate,
  uda.id as id_user_agent,
  v.visitante_id as id_user_visitor,
  udav.id as id_user_visit_agent,  
  vo_cr.isApp as visit_created_from_app,
  vo_cr.nome as visit_created_type,
  coalesce(vo_up.isApp, FALSE) as visit_last_updated_from_app,
  coalesce(vo_up.nome, FALSE) as visit_last_updated_type,
  n.id as id_negotiation,
  n.criadoEm as dt_negotiation,
  pp.id as id_pre_proposal,
  coalesce(p.id, p_n.id) as id_proposal,
  c.id as id_contract,
  c.dataRescisao as dt_contract_revocation
  -- count(1)
  -- *
  
from 
  Imovel i

left join
  Usuario prop
  on prop.id = i.usuario_id

-- DADOS CORRETOR
left join
  DadosCorretor dc
  on dc.id = i.dadosCorretor_id

-- DADOS AFILIADO
left join 
  DadosAfiliado daf
  on daf.id = i.dadosAfiliado_id

-- AGENDAMENTO
left join
  Agendamento a
  on a.imovel_id = i.id
  and a.tipo = 'Visita'
left join
  DadosAgente da
  on da.id = a.agente_id
left join 
  Usuario uda
  on uda.dadosAgente_id = da.id

-- VISITA
left join
  Visita v
  on v.id = a.visita_id
left join
  VisitaOrigem vo_cr
  on vo_cr.id = v.origemCriacao_id
left join
  VisitaOrigem vo_up
  on vo_up.id = v.origemUltimaAtualizacao_id
left join
  DadosAgente dav
  on dav.id = v.agente_id
left join 
  Usuario udav
  on udav.dadosAgente_id = da.id

-- FluxoLocacao
LEFT JOIN 
  FluxoLocacao fl
  on a.fluxoLocacao_id = fl.id

left join 
  Negociacao n
  on n.imovel_id = fl.imovel_id
  and n.proponente_id = fl.cliente_id

-- PreProposta
left join 
  PreProposta pp
  on pp.imovel_id = i.id
  and pp.usuario_id = fl.cliente_id

-- Proposta
left join 
  Proposta p
  on p.preProposta_id = pp.id
  
left JOIN
  Proposta p_n
  on p_n.negociacao_id = n.id

-- Contrato
left join 
  Contrato c
  on c.proposta_id = p.id
;


