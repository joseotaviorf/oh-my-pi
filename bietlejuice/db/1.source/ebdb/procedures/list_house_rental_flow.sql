drop procedure list_house_rental_flow;
create definer = 'QuintoAndarMain'@'%'
procedure list_house_rental_flow()
begin

set @rank=0;

select
  @rank := @rank+1 as id_house_rental_flow,
  id_house,
  id_rental_flow,
  id_owner,
  id_client,
  id_booking,
  id_user_agent,
  id_user_visit_agent,
  id_visit,
  visit_created_from_app,
  visit_created_type,
  visit_last_updated_from_app,
  visit_last_updated_type,
  id_negotiation,
  id_offer,
  id_pre_proposal,
  id_proposal,
  id_contract
from (
-- Offer
	select
		i.id as id_house,
	  a.id as id_booking,
	  i.usuario_id as id_owner,
	  dau.id as id_user_agent,
	  v.visitante_id as id_client,
	  dav.id as id_user_visit_agent,
	  v.id as id_visit,
	  vo_cr.isApp as visit_created_from_app,
	  vo_cr.nome as visit_created_type,
	  coalesce(vo_up.isApp, false) as visit_last_updated_from_app,
	  coalesce(vo_up.nome, false) as visit_last_updated_type,
	  fl.id as id_rental_flow,
	  _offer.o_id as id_offer,
	  null as id_pre_proposal,
	  null as id_negotiation,
	  p.id as id_proposal,
	  c.id as id_contract
	from Imovel i
	left join FluxoLocacao fl
		on i.id = fl.imovel_id
	left join Agendamento a
		on fl.imovel_id = a.imovel_id
			and fl.cliente_id = a.visitante_id
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
	  on dav.dadosAgente_id = a.agente_id
	left join (
		select
			o_id,
			fl_id,
			a_id,
			min(min_diff) as min_diff
		from (
			select
				o_id,
				case
					when sum(a_id) is not null
						then null
					else sum(fl_id)
				end as fl_id,
				sum(a_id) as a_id,
				min_diff
			from (
				select
					o_id,
					fl_id,
					a_id,
					min(_diff) as min_diff
				from (
					select
						o.id as o_id,
						o.criadoEm as o_created,
						fl.id as fl_id,
						fl.criadoEm as fl_created,
						null as a_id,
						null as a_created,
						timestampdiff(second, fl.criadoEm, o.criadoEm) as _diff
					from Offer o
					left join FluxoLocacao fl
						on o.house_id = fl.imovel_id
							and o.client_id = fl.cliente_id
					where o.expirationDate is not null
					union all
					select
						o.id as o_id,
						o.criadoEm as o_created,
						null as fl_id,
						null as fl_created,
						a.id as a_id,
						a.criadoEm as a_created,
						timestampdiff(second, a.criadoEm, o.criadoEm) as _diff
					from Offer o
					left join Agendamento a
						on a.visitante_id = o.client_id
							and a.imovel_id = o.house_id
							and a.tipo = 'Visita'
					where o.expirationDate is not null
				) int_min
			where _diff >= 0
			group by o_id, fl_id, a_id
			order by o_id, a_id, fl_id
			) int_consolidation
			group by o_id, min_diff
		) int_min
		group by o_id
	) _offer
		on _offer.a_id = a.id
			and _offer.a_id is not null
	left join Proposta p
	  on p.offer_id = _offer.o_id
	left join Contrato c
	  on c.proposta_id = p.id
	union all
	select
		i.id as id_house,
	  null as id_booking,
	  i.usuario_id as id_owner,
	  null as id_user_agent,
	  null as id_client,
	  null as id_user_visit_agent,
	  null as id_visit,
	  null as visit_created_from_app,
	  null as visit_created_type,
	  null as visit_last_updated_from_app,
	  null as visit_last_updated_type,
	  fl.id as id_rental_flow,
	  _offer.o_id as id_offer,
	  null as id_pre_proposal,
	  null as id_negotiation,
	  p.id as id_proposal,
	  c.id as id_contract
	from Imovel i
	left join FluxoLocacao fl
		on i.id = fl.imovel_id
	left join (
		select
			o_id,
			fl_id,
			a_id,
			min(min_diff) as min_diff
		from (
			select
				o_id,
				case
					when sum(a_id) is not null
						then null
					else sum(fl_id)
				end as fl_id,
				sum(a_id) as a_id,
				min_diff
			from (
				select
					o_id,
					fl_id,
					a_id,
					min(_diff) as min_diff
				from (
					select
						o.id as o_id,
						o.criadoEm as o_created,
						fl.id as fl_id,
						fl.criadoEm as fl_created,
						null as a_id,
						null as a_created,
						timestampdiff(second, fl.criadoEm, o.criadoEm) as _diff
					from Offer o
					left join FluxoLocacao fl
						on o.house_id = fl.imovel_id
							and o.client_id = fl.cliente_id
					where o.expirationDate is not null
					union all
					select
						o.id as o_id,
						o.criadoEm as o_created,
						null as fl_id,
						null as fl_created,
						a.id as a_id,
						a.criadoEm as a_created,
						timestampdiff(second, a.criadoEm, o.criadoEm) as _diff
					from Offer o
					left join Agendamento a
						on a.visitante_id = o.client_id
							and a.imovel_id = o.house_id
							and a.tipo = 'Visita'
					where o.expirationDate is not null
				) int_min
			where _diff >= 0
			group by o_id, fl_id, a_id
			order by o_id, a_id, fl_id
			) int_consolidation
			group by o_id, min_diff
		) int_min
		group by o_id
	) _offer
		on _offer.fl_id = fl.id
			and _offer.a_id is null
	left join Proposta p
	  on p.offer_id = _offer.o_id
	left join Contrato c
	  on c.proposta_id = p.id
	union all
	-- PreProposta
	select
		i.id as id_house,
	  a.id as id_booking,
	  i.usuario_id as id_owner,
	  dau.id as id_user_agent,
	  v.visitante_id as id_client,
	  dav.id as id_user_visit_agent,
	  v.id as id_visit,
	  vo_cr.isApp as visit_created_from_app,
	  vo_cr.nome as visit_created_type,
	  coalesce(vo_up.isApp, false) as visit_last_updated_from_app,
	  coalesce(vo_up.nome, false) as visit_last_updated_type,
	  fl.id as id_rental_flow,
	  null as id_offer,
	  _pre_proposal.pp_id as id_pre_proposal,
	  null as id_negotiation,
	  p.id as id_proposal,
	  c.id as id_contract
	from Imovel i
	left join FluxoLocacao fl
		on i.id = fl.imovel_id
	left join Agendamento a
		on fl.imovel_id = a.imovel_id
			and fl.cliente_id = a.visitante_id
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
	  on dav.dadosAgente_id = a.agente_id
	left join (
		select
			pp_id,
			fl_id,
			a_id,
			min(min_diff) as min_diff
		from (
			select
				pp_id,
				case
					when sum(a_id) is not null
						then null
					else sum(fl_id)
				end as fl_id,
				sum(a_id) as a_id,
				min_diff
			from (
				select
					pp_id,
					fl_id,
					a_id,
					min(_diff) as min_diff
				from (
					select
						pp.id as pp_id,
						pp.criadoEm as pp_created,
						fl.id as fl_id,
						fl.criadoEm as fl_created,
						null as a_id,
						null as a_created,
						timestampdiff(second, fl.criadoEm, pp.criadoEm) as _diff
					from PreProposta pp
					left join FluxoLocacao fl
						on pp.imovel_id = fl.imovel_id
							and pp.usuario_id = fl.cliente_id
					where pp.ultimoUpdateEdicao > 0
					union all
					select
						pp.id as pp_id,
						pp.criadoEm as pp_created,
						null as fl_id,
						null as fl_created,
						a.id as a_id,
						a.criadoEm as a_created,
						timestampdiff(second, a.criadoEm, pp.criadoEm) as _diff
					from PreProposta pp
					left join Agendamento a
						on a.visitante_id = pp.usuario_id
							and a.imovel_id = pp.imovel_id
							and a.tipo = 'Visita'
					where pp.ultimoUpdateEdicao > 0
				) int_min
			where _diff >= 0
			group by pp_id, fl_id, a_id
			order by pp_id, a_id, fl_id
			) int_consolidation
			group by pp_id, min_diff
		) int_min
		group by pp_id
	) _pre_proposal
		on _pre_proposal.a_id = a.id
			and _pre_proposal.a_id is not null
	left join Proposta p
	  on p.preProposta_id = _pre_proposal.pp_id
	left join Contrato c
	  on c.proposta_id = p.id
	union all
	select
		i.id as id_house,
	  null as id_booking,
	  i.usuario_id as id_owner,
	  null as id_user_agent,
	  null as id_client,
	  null as id_user_visit_agent,
	  null as id_visit,
	  null as visit_created_from_app,
	  null as visit_created_type,
	  null as visit_last_updated_from_app,
	  null as visit_last_updated_type,
	  fl.id as id_rental_flow,
	  null as id_offer,
	  _pre_proposal.pp_id as id_pre_proposal,
	  null as id_negotiation,
	  p.id as id_proposal,
	  c.id as id_contract
	from Imovel i
	left join FluxoLocacao fl
		on i.id = fl.imovel_id
	left join (
		select
			pp_id,
			fl_id,
			a_id,
			min(min_diff) as min_diff
		from (
			select
				pp_id,
				case
					when sum(a_id) is not null
						then null
					else sum(fl_id)
				end as fl_id,
				sum(a_id) as a_id,
				min_diff
			from (
				select
					pp_id,
					fl_id,
					a_id,
					min(_diff) as min_diff
				from (
					select
						pp.id as pp_id,
						pp.criadoEm as pp_created,
						fl.id as fl_id,
						fl.criadoEm as fl_created,
						null as a_id,
						null as a_created,
						timestampdiff(second, fl.criadoEm, pp.criadoEm) as _diff
					from PreProposta pp
					left join FluxoLocacao fl
						on pp.imovel_id = fl.imovel_id
							and pp.usuario_id = fl.cliente_id
					where pp.ultimoUpdateEdicao > 0
					union all
					select
						pp.id as pp_id,
						pp.criadoEm as pp_created,
						null as fl_id,
						null as fl_created,
						a.id as a_id,
						a.criadoEm as a_created,
						timestampdiff(second, a.criadoEm, pp.criadoEm) as _diff
					from PreProposta pp
					left join Agendamento a
						on a.visitante_id = pp.usuario_id
							and a.imovel_id = pp.imovel_id
							and a.tipo = 'Visita'
					where pp.ultimoUpdateEdicao > 0
				) int_min
			where _diff >= 0
			group by pp_id, fl_id, a_id
			order by pp_id, a_id, fl_id
			) int_consolidation
			group by pp_id, min_diff
		) int_min
		group by pp_id
	) _pre_proposal
		on _pre_proposal.fl_id = fl.id
			and _pre_proposal.a_id is null
	left join Proposta p
	  on p.preProposta_id = _pre_proposal.pp_id
	left join Contrato c
	  on c.proposta_id = p.id
	union all
	-- Negociacao
	select
		i.id as id_house,
	  a.id as id_booking,
	  i.usuario_id as id_owner,
	  dau.id as id_user_agent,
	  v.visitante_id as id_client,
	  dav.id as id_user_visit_agent,
	  v.id as id_visit,
	  vo_cr.isApp as visit_created_from_app,
	  vo_cr.nome as visit_created_type,
	  coalesce(vo_up.isApp, false) as visit_last_updated_from_app,
	  coalesce(vo_up.nome, false) as visit_last_updated_type,
	  fl.id as id_rental_flow,
	  null as id_offer,
	  null as id_pre_proposal,
	  _negotiation.n_id as id_negotiation,
	  p.id as id_proposal,
	  c.id as id_contract
	from Imovel i
	left join FluxoLocacao fl
		on i.id = fl.imovel_id
	left join Agendamento a
		on fl.imovel_id = a.imovel_id
			and fl.cliente_id = a.visitante_id
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
	  on dav.dadosAgente_id = a.agente_id
	left join (
		select
			n_id,
			fl_id,
			a_id,
			min(min_diff) as min_diff
		from (
			select
				n_id,
				case
					when sum(a_id) is not null
						then null
					else sum(fl_id)
				end as fl_id,
				sum(a_id) as a_id,
				min_diff
			from (
				select
					n_id,
					fl_id,
					a_id,
					min(_diff) as min_diff
				from (
					select
						n.id as n_id,
						n.criadoEm as n_created,
						fl.id as fl_id,
						fl.criadoEm as fl_created,
						null as a_id,
						null as a_created,
						timestampdiff(second, fl.criadoEm, n.criadoEm) as _diff
					from Negociacao n
					left join FluxoLocacao fl
						on n.imovel_id = fl.imovel_id
							and n.propostaAluguel = fl.cliente_id
					union all
					select
						n.id as n_id,
						n.criadoEm as n_created,
						null as fl_id,
						null as fl_created,
						a.id as a_id,
						a.criadoEm as a_created,
						timestampdiff(second, a.criadoEm, n.criadoEm) as _diff
					from Negociacao n
					left join Agendamento a
						on a.visitante_id = n.proponente_id
							and a.imovel_id = n.imovel_id
							and a.tipo = 'Visita'
				) int_min
			where _diff >= 0
			group by n_id, fl_id, a_id
			order by n_id, a_id, fl_id
			) int_consolidation
			group by n_id, min_diff
		) int_min
		group by n_id
	) _negotiation
		on _negotiation.a_id = a.id
			and _negotiation.a_id is not null
	left join Proposta p
	  on p.negociacao_id = _negotiation.n_id
	left join Contrato c
	  on c.proposta_id = p.id
	union all
	select
		i.id as id_house,
	  null as id_booking,
	  i.usuario_id as id_owner,
	  null as id_user_agent,
	  null as id_client,
	  null as id_user_visit_agent,
	  null as id_visit,
	  null as visit_created_from_app,
	  null as visit_created_type,
	  null as visit_last_updated_from_app,
	  null as visit_last_updated_type,
	  fl.id as id_rental_flow,
	  null as id_offer,
	  null as id_pre_proposal,
	  _negotiation.n_id as id_negotiation,
	  p.id as id_proposal,
	  c.id as id_contract
	from Imovel i
	left join FluxoLocacao fl
		on i.id = fl.imovel_id
	left join (
		select
			n_id,
			fl_id,
			a_id,
			min(min_diff) as min_diff
		from (
			select
				n_id,
				case
					when sum(a_id) is not null
						then null
					else sum(fl_id)
				end as fl_id,
				sum(a_id) as a_id,
				min_diff
			from (
				select
					n_id,
					fl_id,
					a_id,
					min(_diff) as min_diff
				from (
					select
						n.id as n_id,
						n.criadoEm as n_created,
						fl.id as fl_id,
						fl.criadoEm as fl_created,
						null as a_id,
						null as a_created,
						timestampdiff(second, fl.criadoEm, n.criadoEm) as _diff
					from Negociacao n
					left join FluxoLocacao fl
						on n.imovel_id = fl.imovel_id
							and n.propostaAluguel = fl.cliente_id
					union all
					select
						n.id as n_id,
						n.criadoEm as n_created,
						null as fl_id,
						null as fl_created,
						a.id as a_id,
						a.criadoEm as a_created,
						timestampdiff(second, a.criadoEm, n.criadoEm) as _diff
					from Negociacao n
					left join Agendamento a
						on a.visitante_id = n.proponente_id
							and a.imovel_id = n.imovel_id
							and a.tipo = 'Visita'
				) int_min
			where _diff >= 0
			group by n_id, fl_id, a_id
			order by n_id, a_id, fl_id
			) int_consolidation
			group by n_id, min_diff
		) int_min
		group by n_id
	) _negotiation
		on _negotiation.fl_id = fl.id
			and _negotiation.a_id is null
	left join Proposta p
	  on p.negociacao_id = _negotiation.n_id
	left join Contrato c
	  on c.proposta_id = p.id
	union all
	-- Old Data Proposta
	select
		i.id as id_house,
	  null as id_booking,
	  i.usuario_id as id_owner,
	  null as id_user_agent,
	  p.proponente_id as id_client,
	  null as id_user_visit_agent,
	  null as id_visit,
	  null as visit_created_from_app,
	  null as visit_created_type,
	  null as visit_last_updated_from_app,
	  null as visit_last_updated_type,
	  fl.id as id_rental_flow,
	  null as id_offer,
	  null as id_pre_proposal,
	  null as id_negotiation,
	  p.id as id_proposal,
	  c.id as id_contract
	from Proposta p
	join Imovel i
		on p.imovel_id = i.id
	join FluxoLocacao fl
		on p.imovel_id = fl.imovel_id
			and p.proponente_id = fl.cliente_id
	left join Contrato c
		on p.id = c.proposta_id
	where p.offer_id is null
		and p.preProposta_id is null
		and p.negociacao_id is null
	union all
	-- Old Data Contrato
	select
		i.id as id_house,
	  null as id_booking,
	  i.usuario_id as id_owner,
	  null as id_user_agent,
	  c.usuario_id as id_client,
	  null as id_user_visit_agent,
	  null as id_visit,
	  null as visit_created_from_app,
	  null as visit_created_type,
	  null as visit_last_updated_from_app,
	  null as visit_last_updated_type,
	  fl.id as id_rental_flow,
	  null as id_offer,
	  null as id_pre_proposal,
	  null as id_negotiation,
	  null as id_proposal,
	  c.id as id_contract
	from Contrato c
	join Imovel i
		on c.imovel_id = i.id
	join FluxoLocacao fl
		on c.imovel_id = fl.imovel_id
			and c.usuario_id = fl.cliente_id
	where c.proposta_id is null
) _result
;

end