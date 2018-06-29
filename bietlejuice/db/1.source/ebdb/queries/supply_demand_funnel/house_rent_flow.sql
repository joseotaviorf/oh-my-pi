select
  CAST(@rank := @rank+1 AS UNSIGNED) as id_house_rent_flow,
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
  visit_completed,
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
		(select
			o.id_house,
			o.dt_house_first_listing,
		 	o.id_booking,
		  	o.dt_booking_created,
		  	o.dt_visit,
		  	o.visit_completed,
	  	  	o.id_owner,
		  	o.id_user_agent,
		  	o.id_client,
		  	o.dt_client_sign_up,
		  	o.dt_agent_sign_up,
			o.id_visit,
			o.visit_created_from_app,
			o.visit_created_type,
			o.visit_last_updated_from_app,
			o.visit_last_updated_type,
			o.id_rent_flow,
			o.dt_rent_flow_created,
			o.id_offer,
		  	pp.id_pre_proposal,
		  	o.id_contract as o,
		  	pp.id_contract as pp,
		  	coalesce(o.id_proposal, pp.id_proposal) as id_proposal,
		  	coalesce(o.dt_proposal_approved, pp.dt_proposal_approved) as dt_proposal_approved,
		  	coalesce(o.id_contract, pp.id_contract) as id_contract,
		  	coalesce(o.dt_contract_created, pp.dt_contract_created) as dt_contract_created,
		  	coalesce(o.dt_contract_signed, pp.dt_contract_signed) as dt_contract_signed,
		  	coalesce(o.dt_contract_annulment, pp.dt_contract_annulment) as dt_contract_annulment
			from (
				select distinct
				  id_house,
				  dt_house_first_listing,
				  id_booking,
				  dt_booking_created,
				  dt_visit,
				  visit_completed,
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
					  coalesce(a.fupVisita in ('VaiNegociar', 'NaoGostou', 'VisitouSozinho', 'Talvez'), false) as visit_completed,
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
							on a.fluxoLocacao_id = o.rentFlow_id
						join (
							select
								o_id,
								coalesce(
									min(if(_diff >= 0, _diff, null)),
									max(if(_diff < 0, _diff, null))
								) as min_diff
							from (
								select
									o.id as o_id,
									timestampdiff(second, a.criadoEm, o.criadoEm) as _diff
								from Offer o
								join Agendamento a
									on a.fluxoLocacao_id = o.rentFlow_id
								where o.expirationDate is not null
									and a.tipo = 'Visita'
							) int_diff
							group by 1
						) int_offer
							on int_offer.o_id = o.id
								and min_diff = timestampdiff(second, a.criadoEm, o.criadoEm)
						where o.expirationDate is not null
							and a.tipo = 'Visita'
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
			) o
		  left join (
			  select distinct
			  	id_house,
				id_booking,
				id_rent_flow,
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
					  coalesce(a.fupVisita in ('VaiNegociar', 'NaoGostou', 'VisitouSozinho', 'Talvez'), false) as visit_completed,
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
						join (
							select
								pp_id,
								coalesce(
									min(if(_diff >= 0, _diff, null)),
									max(if(_diff < 0, _diff, null))
								) as min_diff
							from (
								select
									pp.id as pp_id,
									timestampdiff(second, a.criadoEm, pp.criadoEm) as _diff
								from PreProposta pp
								join Agendamento a
									on a.visitante_id = pp.usuario_id
										and a.imovel_id = pp.imovel_id
								where pp.ultimoUpdateEdicao > 0
									and a.tipo = 'Visita'
							) int_diff
							group by 1
						) int_pre_proposal
							on int_pre_proposal.pp_id = pp.id
								and min_diff = timestampdiff(second, a.criadoEm, pp.criadoEm)
						where pp.ultimoUpdateEdicao > 0
							and a.tipo = 'Visita'
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
		) pp
		on pp.id_house = o.id_house
			and (if(pp.id_booking is not null, pp.id_booking = o.id_booking, true))
			and pp.id_rent_flow = o.id_rent_flow
	)
	union
	(
		select
			c_new.imovel_id as id_house,
			null as dt_house_first_listing,
		 	null as id_booking,
		  	null as dt_booking_created,
		  	null as dt_visit,
		  	null as visit_completed,
	  	  	null as id_owner,
		  	null as id_user_agent,
		  	fl.cliente_id as id_client,
		    null as dt_client_sign_up,
		  	null as dt_agent_sign_up,
			null as id_visit,
			null as visit_created_from_app,
			null as visit_created_type,
			null as visit_last_updated_from_app,
			null as visit_last_updated_type,
			fl.id as id_rent_flow,
			fl.criadoEm as dt_rent_flow_created,
			p.offer_id as id_offer,
		  	p.preProposta_id as id_pre_proposal,
		  	null as o,
		  	c_new.id as pp,
		  	c_new.proposta_id as id_proposal,
		  	p.dataAprovacao as dt_proposal_approved,
		  	c_new.id as id_contract,
		  	c_new.criadoEm as dt_contract_created,
    		c_new.dataAssinado as dt_contract_signed,
			c_new.dataRescisao as dt_contract_annulment
		from
			Contrato c_new
		join FluxoLocacao fl
			on    c_new.imovel_id = fl.imovel_id
			and c_new.usuario_id = fl.cliente_id
		left join Proposta p
			on c_new.proposta_id = p.id
		where (p.id is null) or
		(p.id is not null and p.offer_id is null and p.preProposta_id is null)
	)
) _result, (SELECT @rank:=0) AS dummy