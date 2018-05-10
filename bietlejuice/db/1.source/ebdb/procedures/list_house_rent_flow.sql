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
		select distinct
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
	  	if(id_offer is null, null, id_proposal) as id_proposal,
	  	if(id_offer is null, null, dt_proposal_approved) as dt_proposal_approved,
	  	if(id_offer is null, null, id_contract) as id_contract,
	  	if(id_offer is null, null, dt_contract_created) as dt_contract_created,
	  	if(id_offer is null, null, dt_contract_signed) as dt_contract_signed,
	  	if(id_offer is null, null, dt_contract_annulment) as dt_contract_annulment
		from (
			select
				i.id as id_house,
				i.firstPublication as dt_house_first_listing,
			  a.id as id_booking,
			  a.criadoEm as dt_booking_created,
			  a.`data` as dt_visit,
			  i.usuario_id as id_owner,
			  dav.id as id_user_agent,
			  fl.cliente_id as id_client,
			  dac.criadoEm as dt_client_sign_up,
			  dav.criadoEm as dt_agent_sign_up,
			  v.id as id_visit,
			  vo_cr.isApp as visit_created_from_app,
			  vo_cr.nome as visit_created_type,
			  coalesce(vo_up.isApp, false) as visit_last_updated_from_app,
			  coalesce(vo_up.nome, false) as visit_last_updated_type,
			  fl.id as id_rent_flow,
			  fl.criadoEm as dt_rent_flow_created,
			  case
			  	when _offer.o_id is not null
			  		then if(_offer.o_id != o.id or (_offer.o_id != o.id) is null, null, _offer.o_id)
			  	when o.id is not null and a.id is not null
			  		then null
			    else o.id
			  end as id_offer,
			  null as id_pre_proposal,
			  coalesce(poa.id, pof.id) as id_proposal,
			  coalesce(poa.dataAprovacao, pof.dataAprovacao) as dt_proposal_approved,
			  c.id as id_contract,
			  c.criadoEm as dt_contract_created,
				c.dataAssinado as dt_contract_signed,
				c.dataRescisao as dt_contract_annulment
			from Imovel i
			join FluxoLocacao fl
				on i.id = fl.imovel_id
			left join Agendamento a
				on fl.id = a.fluxoLocacao_id
					and a.tipo = 'Visita'
			left join Usuario dac
				on dac.id = fl.cliente_id
			left join Visita v
			  on v.id = a.visita_id
			left join VisitaOrigem vo_cr
			  on vo_cr.id = v.origemCriacao_id
			left join VisitaOrigem vo_up
			  on vo_up.id = v.origemUltimaAtualizacao_id
			left join Usuario dav
			  on dav.dadosAgente_id = a.agente_id
			left join Offer o
				on o.rentFlow_id = fl.id
					and o.expirationDate is not null
			left join (
				select
					o.id as o_id,
					a.id as a_id
				from Offer o
				join Agendamento a
					on a.visitante_id = o.client_id
								and a.imovel_id = o.house_id
								and a.tipo = 'Visita'
				join (
					select
						o_id,
						created_at,
						min(_diff) as min_diff
					from (
						select
							o.id as o_id,
							a.id as a_id,
							o.criadoEm as created_at,
							timestampdiff(second, a.criadoEm, o.criadoEm) as _diff,
							count(*) as _count,
							count(timestampdiff(second, a.criadoEm, o.criadoEm) < 0) as negative_count
						from Offer o
						join Agendamento a
							on a.visitante_id = o.client_id
								and a.imovel_id = o.house_id
								and a.tipo = 'Visita'
						where o.expirationDate is not null
						group by 1, 2, 3, 4
					) int_min
					where _diff >= 0
						or (_count = negative_count)
					group by o_id, created_at
				) int_offer
					on int_offer.o_id = o.id
						and min_diff = timestampdiff(second, a.criadoEm, int_offer.created_at)
				where o.expirationDate is not null
			) _offer
				on _offer.a_id = a.id
			left join Proposta pof
			  on pof.offer_id = o.id
			left join Proposta poa
				on poa.offer_id = _offer.o_id
			left join Contrato c
			  on c.proposta_id = coalesce(poa.id, pof.id)
			where (_offer.o_id = o.id) is null
				or _offer.o_id = o.id
		) int_offer
	  union
	  select distinct
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
	  	if(id_pre_proposal is null, null, id_proposal) as id_proposal,
	  	if(id_pre_proposal is null, null, dt_proposal_approved) as dt_proposal_approved,
	  	if(id_pre_proposal is null, null, id_contract) as id_contract,
	  	if(id_pre_proposal is null, null, dt_contract_created) as dt_contract_created,
	  	if(id_pre_proposal is null, null, dt_contract_signed) as dt_contract_signed,
	  	if(id_pre_proposal is null, null, dt_contract_annulment) as dt_contract_annulment
	  from (
	    select
				i.id as id_house,
				i.firstPublication as dt_house_first_listing,
			  a.id as id_booking,
			  a.criadoEm as dt_booking_created,
			  a.`data` as dt_visit,
		  	i.usuario_id as id_owner,
			  dav.id as id_user_agent,
			  fl.cliente_id as id_client,
			  dac.criadoEm as dt_client_sign_up,
			  dav.criadoEm as dt_agent_sign_up,
			  v.id as id_visit,
			  vo_cr.isApp as visit_created_from_app,
			  vo_cr.nome as visit_created_type,
			  coalesce(vo_up.isApp, false) as visit_last_updated_from_app,
			  coalesce(vo_up.nome, false) as visit_last_updated_type,
			  fl.id as id_rent_flow,
			  fl.criadoEm as dt_rent_flow_created,
			  null as id_offer,
			  case
			  	when _pre_proposal.pp_id is not null
			  		then if(_pre_proposal.pp_id != prep.id or (_pre_proposal.pp_id != prep.id) is null, null, _pre_proposal.pp_id)
			    when prep.id is not null and a.id is not null
			    	then null
			    else prep.id
			  end as id_pre_proposal,
			  coalesce(ppa.id, ppf.id) as id_proposal,
			  coalesce(ppa.dataAprovacao, ppf.dataAprovacao) as dt_proposal_approved,
			  c.id as id_contract,
			  c.criadoEm as dt_contract_created,
			  c.dataAssinado as dt_contract_signed,
			  c.dataRescisao as dt_contract_annulment
			from Imovel i
			join FluxoLocacao fl
				on i.id = fl.imovel_id
			left join Agendamento a
				on fl.id = a.fluxoLocacao_id
					and a.tipo = 'Visita'
			left join Usuario dac
				on dac.id = fl.cliente_id
			left join Visita v
			  on v.id = a.visita_id
			left join VisitaOrigem vo_cr
			  on vo_cr.id = v.origemCriacao_id
			left join VisitaOrigem vo_up
			  on vo_up.id = v.origemUltimaAtualizacao_id
			left join Usuario dav
			  on dav.dadosAgente_id = a.agente_id
			left join PreProposta prep
				on prep.usuario_id = fl.cliente_id
					and prep.imovel_id = fl.imovel_id
					and prep.ultimoUpdateEdicao > 0
			left join (
				select
					pp.id as pp_id,
					a.id as a_id
				from PreProposta pp
				join Agendamento a
					on a.visitante_id = pp.usuario_id
								and a.imovel_id = pp.imovel_id
								and a.tipo = 'Visita'
				join (
					select
						pp_id,
						created_at,
						min(_diff) as min_diff
					from (
						select
							pp.id as pp_id,
							a.id as a_id,
							pp.criadoEm as created_at,
							timestampdiff(second, a.criadoEm, pp.criadoEm) as _diff,
							count(*) as _count,
							count(timestampdiff(second, a.criadoEm, pp.criadoEm) < 0) as negative_count
						from PreProposta pp
						left join Agendamento a
							on a.visitante_id = pp.usuario_id
								and a.imovel_id = pp.imovel_id
								and a.tipo = 'Visita'
						where pp.ultimoUpdateEdicao > 0
						group by 1, 2, 3, 4
					) int_min
					where _diff >= 0
						or (_count = negative_count)
					group by pp_id, created_at
				) int_pre_proposal
					on int_pre_proposal.pp_id = pp.id
						and min_diff = timestampdiff(second, a.criadoEm, int_pre_proposal.created_at)
				where pp.ultimoUpdateEdicao > 0
			) _pre_proposal
				on _pre_proposal.a_id = a.id
			left join Proposta ppf
			  on ppf.preProposta_id = prep.id
		  left join Proposta ppa
			  on ppa.preProposta_id = _pre_proposal.pp_id
			left join Contrato c
			  on c.proposta_id = coalesce(ppa.id, ppf.id)
			where (_pre_proposal.pp_id = prep.id) is null
				or _pre_proposal.pp_id = prep.id
		) int_pre_proposal
) _result
;

end