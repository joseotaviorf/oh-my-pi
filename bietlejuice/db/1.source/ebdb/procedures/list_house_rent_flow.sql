drop procedure if exists list_house_rent_flow;
create definer = 'QuintoAndarMain'@'%'
procedure list_house_rent_flow()
begin

set @rank=0;

select
  @rank := @rank+1 as id_house_rent_flow,
	id_house,
	dt_house_first_listing,
  id_booking,
  dt_booking_created,
  dt_visit,
  id_owner,
  id_user_agent,
  id_client,
  dt_client_sign_up,
  dt_agent_sign_up,
  id_visit,
  visit_created_from_app,
  visit_created_type,
  visit_last_updated_from_app,
  visit_last_updated_type,
  id_rent_flow,
  dt_rent_flow_created,
  id_offer,
  id_pre_proposal,
  id_proposal,
  dt_proposal_approved,
  id_contract,
  dt_contract_created,
  dt_contract_signed,
  dt_contract_annulment
	from (
		select
			i.id as id_house,
			i.firstPublication as dt_house_first_listing,
		  a.id as id_booking,
		  a.criadoEm as dt_booking_created,
		  a.`data` as dt_visit,
		  i.usuario_id as id_owner,
		  dav.id as id_user_agent,
		  v.visitante_id as id_client,
		  dac.criadoEm as dt_client_sign_up,
		  dav.criadoEm as dt_agent_sign_up,
		  v.id as id_visit,
		  vo_cr.isApp as visit_created_from_app,
		  vo_cr.nome as visit_created_type,
		  coalesce(vo_up.isApp, false) as visit_last_updated_from_app,
		  coalesce(vo_up.nome, false) as visit_last_updated_type,
		  fl.id as id_rent_flow,
		  fl.criadoEm as dt_rent_flow_created,
		  _offer.o_id as id_offer,
		  _pre_proposal.pp_id as id_pre_proposal,
		  coalesce(po.id, pp.id) as id_proposal,
		  coalesce(po.dataAprovacao, pp.dataAprovacao) as dt_proposal_approved,
		  c.id as id_contract,
		  c.criadoEm as dt_contract_created,
		  c.dataAssinado as dt_contract_signed,
		  c.dataRescisao as dt_contract_annulment
		from Imovel i
		join FluxoLocacao fl
			on i.id = fl.imovel_id
		join Agendamento a
			on fl.imovel_id = a.imovel_id
				and fl.cliente_id = a.visitante_id
				and a.tipo = 'Visita'
		join Usuario dac
			on dac.id = a.visitante_id
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
				o_status,
				o_updated,
				a_id,
				min(min_diff) as min_diff
			from (
				select
					o_id,
					o_status,
					o_updated,
					sum(a_id) as a_id,
					min_diff
				from (
					select
						o_id,
						o_status,
						o_updated,
						a_id,
						min(_diff) as min_diff
					from (
						select
							o.id as o_id,
							o.criadoEm as o_created,
							o.status as o_status,
							o.atualizadoEm as o_updated,
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
				group by o_id, a_id
				order by o_id, a_id
				) int_consolidation
				group by o_id, min_diff
			) int_min
			group by o_id
		) _offer
			on _offer.a_id = a.id
				and _offer.a_id is not null
		left join (
			select
				pp_id,
				pp_last_editing_update,
				pp_approved,
				a_id,
				min(min_diff) as min_diff
			from (
				select
					pp_id,
					pp_last_editing_update,
					pp_approved,
					sum(a_id) as a_id,
					min_diff
				from (
					select
						pp_id,
						pp_last_editing_update,
						pp_approved,
						a_id,
						min(_diff) as min_diff
					from (
						select
							pp.id as pp_id,
							pp.criadoEm as pp_created,
							pp.ultimoUpdateEdicao as pp_last_editing_update,
							pp.dataAprovacao as pp_approved,
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
				group by pp_id, a_id
				order by pp_id, a_id
				) int_consolidation
				group by pp_id, min_diff
			) int_min
			group by pp_id
		) _pre_proposal
			on _pre_proposal.a_id = a.id
				and _pre_proposal.a_id is not null
		left join Proposta po
		  on po.offer_id = _offer.o_id
		left join Proposta pp
		  on pp.preProposta_id = _pre_proposal.pp_id
		left join Contrato c
		  on c.proposta_id = coalesce(po.id, pp.id)
) _result;

end
