DROP PROCEDURE IF EXISTS list_property_scheduling;

SET NAMES 'utf8';

USE ebdb;


DELIMITER $$

--
-- Create procedure "list_property_schedule"
--
CREATE DEFINER = 'QuintoAndarMain'@'%'
PROCEDURE list_property_scheduling()
BEGIN

SET @rank=0;

select
	_all.id_property_scheduling,
	_all.id_imovel,
	_all.id_scheduling,
	_all.id_owner,
	_all.id_user_affiliate,
	_all.id_user_agent,
	_all.id_user_visitor,
	_all.id_user_visit_agent,
	_all.id_visit,
	_all.visit_created_from_app,
	_all.visit_created_type,
	_all.visit_last_updated_from_app,
	_all.visit_last_updated_type,
	_all.id_rental_flow,
	if(coalesce(offer_preproposal.minutes_diff, negotiation.minutes_diff) is null, null, _all.id_negotiation) as id_negotiation,
	if(coalesce(offer_preproposal.minutes_diff, negotiation.minutes_diff) is null, null, _all.dt_negotiation) as dt_negotiation,
	if(coalesce(offer_preproposal.minutes_diff, negotiation.minutes_diff) is null, null, _all.id_offer) as id_offer,
	if(coalesce(offer_preproposal.minutes_diff, negotiation.minutes_diff) is null, null, _all.id_pre_proposal) as id_pre_proposal,
	if(coalesce(offer_preproposal.minutes_diff, negotiation.minutes_diff) is null, null, _all.id_proposal) as id_proposal,
	if(coalesce(offer_preproposal.minutes_diff, negotiation.minutes_diff) is null, null, _all.id_contract) as id_contract,
	if(coalesce(offer_preproposal.minutes_diff, negotiation.minutes_diff) is null, null, _all.dt_contract_anullment) as dt_contract_anullment
from (
	select
	  @rank := @rank+1 as id_property_scheduling,
	  i.id as id_imovel,
	  a.id as id_scheduling,
	  prop.id as id_owner,
	  -1 as id_user_affiliate,
	  dau.id as id_user_agent,
	  v.visitante_id as id_user_visitor,
	  dav.id as id_user_visit_agent,
	  v.id as id_visit,
	  vo_cr.isApp as visit_created_from_app,
	  vo_cr.nome as visit_created_type,
	  coalesce(vo_up.isApp, FALSE) as visit_last_updated_from_app,
	  coalesce(vo_up.nome, FALSE) as visit_last_updated_type,
	  fl.id as id_rental_flow,
	  n.id as id_negotiation,
	  n.criadoEm as dt_negotiation,
	  abs(timestampdiff(minute, n.criadoEm, a.dataFupVisita)) as negotiation_minutes_diff,
	  o.id as id_offer,
	  pp.id as id_pre_proposal,
	  abs(timestampdiff(minute, coalesce(o.criadoEm, pp.criadoEm), coalesce(a.dataFupVisita, a.atualizadoEm))) as offer_preproposal_minutes_diff,
	  coalesce(p1.id, p2.id, p_n.id) as id_proposal,
	  if(coalesce(p1.id, p2.id, p_n.id) is null, null, c.id) as id_contract,
	  if(coalesce(p1.id, p2.id, p_n.id) is null, null, c.dataRescisao) as dt_contract_anullment
	from Imovel i
	left join Usuario prop
	  on prop.id = i.usuario_id
	-- AGENDAMENTO
	left join Agendamento a
	  on a.imovel_id = i.id
	  and a.tipo = 'Visita'
	left join Usuario dau
	  on dau.dadosAgente_id = a.agente_id
	-- VISITA
	left join Visita v
	  on v.id = a.visita_id
	left join VisitaOrigem vo_cr
	  on vo_cr.id = v.origemCriacao_id
	left join VisitaOrigem vo_up
	  on vo_up.id = v.origemUltimaAtualizacao_id
	left join Usuario dav
	  on dav.dadosAgente_id = v.agente_id
	-- FLUXOLOCACAO
	left join FluxoLocacao fl
	  on a.fluxoLocacao_id = fl.id
	left join Negociacao n
	  on n.imovel_id = fl.imovel_id
	  and n.proponente_id = fl.cliente_id
	-- PRE-PROPOSTA
	left join PreProposta pp
	  on pp.imovel_id = i.id
	  and pp.usuario_id = fl.cliente_id
	  and pp.ultimoUpdateEdicao > 0
	-- OFFER
	left join Offer o
	  on o.house_id = i.id
	    and o.client_id = fl.cliente_id
	-- PROPOSTA
	left join Proposta p1
	  on p1.offer_id = o.id
	left join Proposta p2
	  on p2.preProposta_id = pp.id
	left join Proposta p_n
	  on p_n.negociacao_id = n.id
	left join Proposta p_fl
	  on p_fl.imovel_id = i.id
	  and p_fl.proponente_id = fl.cliente_id
	-- CONTRATO
	left join
	  Contrato c
	  on c.proposta_id = coalesce(p1.id, p2.id, p_fl.id, p_n.id)
	) _all
left join
	(
	select
		 i.id as id_imovel,
		 prop.id as id_owner,
		 v.visitante_id as id_user_visitor,
		 fl.id as id_rental_flow,
		 a.id as booking_id,
		 min(abs(timestampdiff(minute, n.criadoEm, a.dataFupVisita))) as minutes_diff
	from Imovel i
	left join Usuario prop
	  on prop.id = i.usuario_id
	-- AGENDAMENTO
	left join Agendamento a
	  on a.imovel_id = i.id
	  	and a.tipo = 'Visita'
 	  	and a.status = 'Realizado'
			and a.fupVisita in ('VaiNegociar', 'VisitouSozinho', 'NaoGostou', 'Talvez')
	left join Usuario dau
	  on dau.dadosAgente_id = a.agente_id
	-- VISITA
	left join Visita v
	  on v.id = a.visita_id
	-- FLUXOLOCACAO
	left join FluxoLocacao fl
	  on a.fluxoLocacao_id = fl.id
	left join Negociacao n
	  on n.imovel_id = fl.imovel_id
	  and n.proponente_id = fl.cliente_id
	group by i.id, prop.id, v.visitante_id, fl.id, n.id
) negotiation
	on _all.id_imovel = negotiation.id_imovel
		and _all.id_owner = negotiation.id_owner
		and _all.id_user_visitor = negotiation.id_user_visitor
		and _all.id_rental_flow = negotiation.id_rental_flow
		and _all.negotiation_minutes_diff = negotiation.minutes_diff
left join
	(
	select
		 i.id as id_imovel,
		 prop.id as id_owner,
		 v.visitante_id as id_user_visitor,
		 fl.id as id_rental_flow,
		 a.id as booking_id,
		 min(abs(timestampdiff(minute, coalesce(o.criadoEm, pp.criadoEm), coalesce(a.dataFupVisita, a.atualizadoEm)))) as minutes_diff
	from Imovel i
	left join Usuario prop
	  on prop.id = i.usuario_id
	-- AGENDAMENTO
	left join Agendamento a
	  on a.imovel_id = i.id
		  and a.tipo = 'Visita'
 		  and a.status = 'Realizado'
			and a.fupVisita in ('VaiNegociar', 'VisitouSozinho', 'NaoGostou', 'Talvez')
	left join Usuario dau
	  on dau.dadosAgente_id = a.agente_id
	-- VISITA
	left join Visita v
	  on v.id = a.visita_id
	-- FLUXOLOCACAO
	left join FluxoLocacao fl
	  on a.fluxoLocacao_id = fl.id
	-- PRE-PROPOSTA
	left join PreProposta pp
	  on pp.imovel_id = i.id
	  and pp.usuario_id = fl.cliente_id
	  and pp.ultimoUpdateEdicao > 0
	-- OFFER
	left join Offer o
	  on o.house_id = i.id
	    and o.client_id = fl.cliente_id
	group by i.id, prop.id, v.visitante_id, fl.id, coalesce(o.id, pp.id)
) offer_preproposal
	on _all.id_imovel = offer_preproposal.id_imovel
		and _all.id_owner = offer_preproposal.id_owner
		and _all.id_user_visitor = offer_preproposal.id_user_visitor
		and _all.id_rental_flow = offer_preproposal.id_rental_flow
		and _all.offer_preproposal_minutes_diff = offer_preproposal.minutes_diff

union all

select
  @rank := @rank+1 as id_property_scheduling,
  i.id as id_imovel,
  -1 as id_scheduling,
  i.usuario_id as id_owner,
  ##
  -1 as id_user_affiliate,
  ##
  -1 as id_user_agent,
  -1 as id_user_visitor,
  -1 as id_user_visit_agent,
  -1 as id_visit,
  null as visit_created_from_app,
  '' as visit_created_type,
  false as visit_last_updated_from_app,
  false as visit_last_updated_type,
  fl.id as id_rental_flow,
  coalesce(n.id, -1) as id_negotiation,
  n.criadoEm as dt_negotiation,
  coalesce(o.id, -1) as id_offer,
  coalesce(pp.id, -1) as id_pre_proposal,
  coalesce(p_fl.id, -1) as id_proposal,
  c.id as id_contract,
  c.dataRescisao as dt_contract_anullment
  from Contrato c

    join Imovel i
      on c.imovel_id = i.id

    left join Agendamento a
      on c.imovel_id = a.imovel_id
      and c.usuario_id = a.visitante_id

    join FluxoLocacao fl
      on c.imovel_id = fl.imovel_id
      and c.usuario_id = fl.cliente_id

    left join
      Negociacao n
      on n.imovel_id = fl.imovel_id
      and n.proponente_id = fl.cliente_id

    left join
      PreProposta pp
      on pp.imovel_id = i.id
      and pp.usuario_id = fl.cliente_id
      and pp.ultimoUpdateEdicao > 0

    left join
      Offer o
      on o.house_id = i.id
        and o.client_id = fl.cliente_id

    left join
      Proposta p_fl
      on (p_fl.imovel_id = i.id
      and p_fl.proponente_id = fl.cliente_id) or (p_fl.id = c.proposta_id)

    where (a.id is null or a.visita_id is null)
      and c.status != 'Cancelado';

END
$$

DELIMITER ;