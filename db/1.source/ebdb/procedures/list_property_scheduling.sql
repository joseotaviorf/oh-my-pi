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

select distinct
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
	_all.id_negotiation,
	_all.dt_negotiation,
	_offer.id_offer,
	_offer.id_pre_proposal,
	id_proposal as id_proposal,
	id_contract as id_contract,
	dt_contract_anullment as dt_contract_anullment
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
	  o.id as id_offer,
	  pp.id as id_pre_proposal,
	  coalesce(p1.id, p2.id, p_n.id) as id_proposal,
	  c.id as id_contract,
	  c.dataRescisao as dt_contract_anullment
	from Imovel i
	left join Usuario prop
	  on prop.id = i.usuario_id
	left join Agendamento a
	  on a.imovel_id = i.id
	  and a.tipo = 'Visita'
	left join Usuario dau
	  on dau.dadosAgente_id = a.agente_id
	left join Visita v
	  on v.id = a.visita_id
	left join VisitaOrigem vo_cr
	  on vo_cr.id = v.origemCriacao_id
	left join VisitaOrigem vo_up
	  on vo_up.id = v.origemUltimaAtualizacao_id
	left join Usuario dav
	  on dav.dadosAgente_id = v.agente_id
	left join FluxoLocacao fl
	  on a.fluxoLocacao_id = fl.id
	left join Negociacao n
	  on n.imovel_id = fl.imovel_id
	    and n.proponente_id = fl.cliente_id
	left join PreProposta pp
	  on pp.imovel_id = i.id
	    and pp.usuario_id = fl.cliente_id
	    and pp.ultimoUpdateEdicao > 0
	left join Offer o
	  on o.house_id = i.id
	    and o.client_id = fl.cliente_id
	    and o.expirationDate is not null
	left join Proposta p1
	  on p1.offer_id = o.id
	left join Proposta p2
	  on p2.preProposta_id = pp.id
	left join Proposta p_n
	  on p_n.negociacao_id = n.id
	left join Proposta p_fl
	  on p_fl.imovel_id = i.id
	    and p_fl.proponente_id = fl.cliente_id
	left join Contrato c
	  on c.proposta_id = coalesce(p1.id, p2.id, p_fl.id, p_n.id)
) _all
left join (
	select
		id_rental_flow,
		id_negotiation,
		min(minutes_diff) as min_minutes_diff
	from (
		select
			fl.id as id_rental_flow,
			n.id as id_negotiation,
			timestampdiff(second, a.criadoEm, n.criadoEm) as minutes_diff
		from Imovel i
		join Usuario prop
		  on prop.id = i.usuario_id
		join Agendamento a
		  on a.imovel_id = i.id
			  and a.tipo = 'Visita'
		join Usuario dau
		  on dau.dadosAgente_id = a.agente_id
		join FluxoLocacao fl
		  on a.fluxoLocacao_id = fl.id
		left join Negociacao n
	 	  on n.imovel_id = fl.imovel_id
	  	  and n.proponente_id = fl.cliente_id
		where timestampdiff(second, a.criadoEm, n.criadoEm) >= 0
	) _int_table
	group by id_rental_flow, id_negotiation
) _negotiation
	on _all.id_rental_flow = _negotiation.id_rental_flow
		and _all.id_negotiation = _negotiation.id_negotiation
left join (
	select
		id_rental_flow,
		null as id_offer,
		id_pre_proposal,
		min(minutes_diff) as min_minutes_diff
	from (
		select
			fl.id as id_rental_flow,
			pp.id as id_pre_proposal,
			a.id as id_scheduling,
			timestampdiff(second, a.criadoEm, pp.criadoEm) as minutes_diff
		from Imovel i
		join Usuario prop
		  on prop.id = i.usuario_id
		join Agendamento a
		  on a.imovel_id = i.id
			  and a.tipo = 'Visita'
		join Usuario dau
		  on dau.dadosAgente_id = a.agente_id
		join FluxoLocacao fl
		  on a.fluxoLocacao_id = fl.id
		left join PreProposta pp
		  on pp.imovel_id = i.id
				and pp.usuario_id = fl.cliente_id
		 	 	and pp.ultimoUpdateEdicao > 0
		where timestampdiff(second, a.criadoEm, pp.criadoEm) >= 0
	) _int_table
	group by id_rental_flow, id_pre_proposal

	union all

	select
		id_rental_flow,
		id_offer,
		null as id_pre_proposal,
		min(minutes_diff) as min_minutes_diff
	from (
		select
			fl.id as id_rental_flow,
			o.id as id_offer,
			a.id as id_scheduling,
			timestampdiff(second, a.criadoEm, o.criadoEm) as minutes_diff
		from Imovel i
		join Usuario prop
		  on prop.id = i.usuario_id
		join Agendamento a
		  on a.imovel_id = i.id
			  and a.tipo = 'Visita'
		join Usuario dau
		  on dau.dadosAgente_id = a.agente_id
		join FluxoLocacao fl
		  on a.fluxoLocacao_id = fl.id
		left join Offer o
		  on o.house_id = i.id
		    and o.client_id = fl.cliente_id
		    and o.expirationDate is not null
		where timestampdiff(second, a.criadoEm, o.criadoEm) >= 0
	) _int_table
	group by id_rental_flow, id_offer
) _offer
	on _all.id_rental_flow = _offer.id_rental_flow
		and (_all.id_offer = _offer.id_offer
			or _all.id_pre_proposal = _offer.id_pre_proposal
		)

union all

select
  @rank := @rank+1 as id_property_scheduling,
  i.id as id_imovel,
  -1 as id_scheduling,
  i.usuario_id as id_owner,
  -1 as id_user_affiliate,
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
  left join Negociacao n
    on n.imovel_id = fl.imovel_id
      and n.proponente_id = fl.cliente_id
  left join PreProposta pp
    on pp.imovel_id = i.id
      and pp.usuario_id = fl.cliente_id
      and pp.ultimoUpdateEdicao > 0
  left join Offer o
    on o.house_id = i.id
      and o.client_id = fl.cliente_id
      and o.expirationDate is not null
  left join Proposta p_fl
    on (p_fl.imovel_id = i.id
      and p_fl.proponente_id = fl.cliente_id) or (p_fl.id = c.proposta_id)
  where (a.id is null or a.visita_id is null)
    and c.status != 'Cancelado';

END
$$

DELIMITER ;