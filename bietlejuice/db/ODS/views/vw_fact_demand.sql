drop view if exists vw_fact_demand;
create view vw_fact_demand as
with _fact as (
	select
		hrf.id_house_rental_flow as ods_id,
		coalesce((hrf.id_house || lpad(coalesce(p."version"::varchar(3), '1'), 3, '0'))::bigint, -1::bigint) as sk_house,
	  coalesce(i.regiao_id, -1)as sk_region,
	  coalesce(hrf.id_rental_flow, -1) as sk_rental_flow,
	  coalesce(hrf.id_booking, -1) as sk_booking,
	  coalesce(hrf.id_owner, -1) as sk_owner,
	  coalesce(hrf.id_user_agent, -1) as sk_user_agent,
	  coalesce(hrf.id_client, -1) as sk_client,
	  coalesce(hrf.id_user_visit_agent, -1) as sk_user_visit_agent,
	  coalesce(hrf.id_visit, -1) as sk_visit,
	  coalesce(hrf.id_negotiation, -1) as sk_negotiation,
	  case
	    when hrf.id_offer > 0
	      then (hrf.id_offer * 100) + 2
	    when hrf.id_pre_proposal > 0
	      then (hrf.id_pre_proposal * 100) + 1
	    else -1
	  end as sk_offer,
	  coalesce(hrf.id_proposal, -1) as sk_proposal,
	  coalesce(hrf.id_contract, -1) as sk_contract,
	  hrf.visit_created_from_app,
	  hrf.visit_created_type,
	  hrf.visit_last_updated_from_app,
	  hrf.visit_last_updated_type,
	  now()::timestamp as dt_timestamp
	from house_rental_flow hrf
	left join imovel i
	  on i.id = hrf.id_house
	left join rental_flow rf
	  on hrf.id_rental_flow = rf.id
	left join property_listing p
	  on p.id = hrf.id_house
		  and coalesce(rf."criadoEm", '1900-01-01') between coalesce(p.min_version_time, '1900-01-01')
		                                              and coalesce(p.max_version_time, now())
),
calculated_dates as (
  select
    f.*,
    dof.dt_first_sent as offer_date,
    case
      when dof.status in ('Rejeitada', 'Aprovada')
        then dof.dt_updated
      else null::timestamp
    end as internal_analysis_date,
    dof.dt_approved as offer_approved_date,
    dpr.dt_credit_analysis_init as credit_analysis_init_date,
    dpr.dt_credit_analysis_end as credit_analysis_end_date,
    case
      when dpr.status in ('Rejeitada', 'Aprovada')
       then dpr.dt_updated
      else null::timestamp
    end as credit_analysis_date,
    dpr.dt_proposal_approved as proposal_approved_date,
    case
      when dct.contract_status in ('Ativo', 'Finalizado')
          then dt_signature
      else null::timestamp
    end as contract_date,
    dbo.dt_booking as visit_date,
    dbo.dt_created as booking_date
  from _fact f
  left join vw_dim_offer dof
    on f.sk_offer = dof.sk_offer
  left join vw_dim_proposal dpr
    on f.sk_proposal = dpr.sk_proposal
  left join vw_dim_contract dct
    on f.sk_contract = dct.sk_contract
  left join vw_dim_booking dbo
    on f.sk_booking = dbo.sk_booking
)
select
  ods_id,
  sk_house,
  sk_region,
  sk_rental_flow,
  sk_booking,
  sk_owner,
  sk_user_agent,
  sk_client,
  sk_user_visit_agent,
  sk_visit,
  sk_negotiation,
  sk_offer,
  sk_proposal,
  sk_contract,
  visit_created_from_app,
  visit_created_type,
  visit_last_updated_from_app,
  visit_last_updated_type,
  (date_part('day', visit_date - booking_date) * 24 +
    date_part('hour', visit_date - booking_date)) / 24.0 as booking_to_visit,
  (date_part('day', internal_analysis_date - offer_date) * 24 +
    date_part('hour', internal_analysis_date - offer_date)) / 24.0 as offer_to_internal_analyis,
  (date_part('day', credit_analysis_init_date - offer_approved_date) * 24 +
    date_part('hour', credit_analysis_init_date - offer_approved_date)) / 24.0 as offer_to_credit_analysis_init_date,
  (date_part('day', coalesce(credit_analysis_end_date, credit_analysis_date)  - credit_analysis_init_date) * 24 +
    date_part('hour', coalesce(credit_analysis_end_date, credit_analysis_date) - credit_analysis_init_date)) / 24.0 as credit_analysis_init_to_end,
  (date_part('day', contract_date - proposal_approved_date) * 24 +
    date_part('hour', contract_date - proposal_approved_date)) / 24.0 as proposal_approved_to_contract_signed,
  dt_timestamp
from calculated_dates
;