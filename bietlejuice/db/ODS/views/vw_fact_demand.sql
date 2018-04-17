drop view if exists vw_fact_demand;
create view vw_fact_demand as
with _fact as (
	select
		hrf.id_house_rent_flow as ods_id,
		coalesce((hrf.id_house || lpad(coalesce(pl."version"::varchar(3), '1'), 3, '0'))::bigint, -1::bigint) as sk_house,
		coalesce(to_char(hrf.dt_house_first_listing, 'YYYYMMDD')::integer, -1) as sk_house_first_listing,
	  coalesce(i.regiao_id, -1) as sk_region,
	  coalesce(hrf.id_rent_flow, -1) as sk_rent_flow,
	  coalesce(hrf.id_booking, -1) as sk_booking,
	  coalesce(to_char(hrf.dt_booking_created, 'YYYYMMDD')::integer, -1) as sk_booking_created_date,
	  hrf.dt_booking_created,
	  coalesce(to_char(hrf.dt_visit, 'YYYYMMDD')::integer, -1) as sk_visit_date,
	  hrf.dt_visit,
	  coalesce(hrf.id_owner, -1) as sk_owner,
	  coalesce(hrf.id_user_agent, -1) as sk_user_agent,
	  coalesce(to_char(hrf.dt_agent_sign_up, 'YYYYMMDD')::integer, -1) as sk_agent_sign_up_date,
	  coalesce(hrf.id_client, -1) as sk_client,
	  coalesce(to_char(hrf.dt_client_sign_up, 'YYYYMMDD')::integer, -1) as sk_client_sign_up_date,
	  coalesce(hrf.id_visit, -1) as sk_visit,
	  coalesce(hrf.id_negotiation, -1) as sk_negotiation,
	  case
	    when hrf.id_offer > 0
	      then (hrf.id_offer * 100) + 2
	    when hrf.id_pre_proposal > 0
	      then (hrf.id_pre_proposal * 100) + 1
	    else -1
	  end as sk_offer,
	  case
	    when hrf.id_offer > 0
	      then coalesce(to_char(o.first_sent_at, 'YYYYMMDD')::integer, -1)
	    when hrf.id_pre_proposal > 0
	      then coalesce(to_char(pp."dataPrimerioEnvio", 'YYYYMMDD')::integer, -1)
	    else -1
	  end as sk_offer_submitted_date,
	  case
	    when hrf.id_offer > 0
	      then o.first_sent_at
	    when hrf.id_pre_proposal > 0
	      then pp."dataPrimerioEnvio"
	    else null::timestamp
	  end as dt_offer_submitted,
	  case
	    when hrf.id_offer > 0
	      then coalesce(to_char(hrf.dt_offer_approved, 'YYYYMMDD')::integer, -1)
	    when hrf.id_pre_proposal > 0
	      then coalesce(to_char(hrf.dt_pre_proposal_approved, 'YYYYMMDD')::integer, -1)
	    else -1
	  end as sk_offer_approved_date,
	  case
	    when hrf.id_offer > 0
	      then hrf.dt_offer_approved
	    when hrf.id_pre_proposal > 0
	      then hrf.dt_pre_proposal_approved
	    else null::timestamp
	  end as dt_offer_approved,
	  case
	    when hrf.id_offer > 0
	      then case when o.status in ('Rejeitada', 'Aprovada') then o.atualizado_em else null::timestamp end
	    when hrf.id_pre_proposal > 0
	      then case when pp.status in ('Rejeitada', 'Aprovada') then pp."atualizadoEm" else null::timestamp end
	    else null::timestamp
	  end as dt_internal_analysis,
	  coalesce(hrf.id_proposal, -1) as sk_proposal,
	  coalesce(to_char(hrf.dt_proposal_approved, 'YYYYMMDD')::integer, -1) as sk_proposal_approved_date,
	  hrf.dt_proposal_approved,
	  case
      when vp.status in ('Rejeitada', 'Aprovada')
       then vp.dt_updated
      else null::timestamp
    end as dt_credit_analysis,
	  coalesce(hrf.id_contract, -1) as sk_contract,
	  coalesce(to_char(hrf.dt_contract_created, 'YYYYMMDD')::integer, -1) as sk_contract_created_date,
	  coalesce(to_char(hrf.dt_contract_signed, 'YYYYMMDD')::integer, -1) as sk_contract_signed_date,
	  coalesce(to_char(hrf.dt_annulment, 'YYYYMMDD')::integer, -1) as sk_contract_annulment_date,
	  case
      when c.status in ('Ativo', 'Finalizado')
          then "dataAssinado"
      else null::timestamp
    end as dt_contract,
    vp.dt_credit_analysis_init,
    vp.dt_credit_analysis_end,
	  hrf.visit_created_from_app,
	  hrf.visit_created_type,
	  hrf.visit_last_updated_from_app,
	  hrf.visit_last_updated_type,
	  now()::timestamp as dt_timestamp
	from house_rent_flow hrf
	left join imovel i
	  on i.id = hrf.id_house
	left join property_listing pl
	  on pl.id = hrf.id_house
		  and coalesce(hrf.dt_rent_flow_created, '1900-01-01') between coalesce(pl.min_version_time, '1900-01-01')
		                                              and coalesce(pl.max_version_time, now())
  left join offer o
    on hrf.id_offer = o.id
  left join pre_proposal pp
    on hrf.id_pre_proposal = pp.id
  left join vw_dim_proposal vp
    on hrf.id_proposal = vp.id_proposal
  left join contract c
    on hrf.id_contract = c.id
)
select
  ods_id,
	sk_house,
	sk_house_first_listing,
	sk_region,
	sk_rent_flow,
	sk_booking,
	sk_booking_created_date,
	sk_visit_date,
	sk_owner,
	sk_user_agent,
	sk_agent_sign_up_date,
	sk_client,
	sk_client_sign_up_date,
	sk_visit,
	sk_negotiation,
	sk_offer,
	sk_offer_submitted_date,
	sk_offer_approved_date,
	sk_proposal,
	sk_proposal_approved_date,
	sk_contract,
	sk_contract_created_date,
	sk_contract_signed_date,
	sk_contract_annulment_date,
	visit_created_from_app,
	visit_created_type,
	visit_last_updated_from_app,
	visit_last_updated_type,
  (date_part('day', dt_visit - dt_booking_created) * 24 +
    date_part('hour', dt_visit - dt_booking_created)) / 24.0 as booking_to_visit,
  (date_part('day', dt_internal_analysis - dt_offer_submitted) * 24 +
    date_part('hour', dt_internal_analysis - dt_offer_submitted)) / 24.0 as offer_to_internal_analyis,
  (date_part('day', dt_credit_analysis_init - dt_offer_approved) * 24 +
    date_part('hour', dt_credit_analysis_init - dt_offer_approved)) / 24.0 as offer_to_credit_analysis_init_date,
  (date_part('day', coalesce(dt_credit_analysis_end, dt_credit_analysis) - dt_credit_analysis_init) * 24 +
    date_part('hour', coalesce(dt_credit_analysis_end, dt_credit_analysis) - dt_credit_analysis_init)) / 24.0 as credit_analysis_init_to_end,
  (date_part('day', dt_contract - dt_proposal_approved) * 24 +
    date_part('hour', dt_contract - dt_proposal_approved)) / 24.0 as proposal_approved_to_contract_signed,
  dt_timestamp
from _fact
;