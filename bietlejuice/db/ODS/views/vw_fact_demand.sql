drop view if exists vw_fact_demand;
create or replace view vw_fact_demand as
with _fact as (
	select
		hrf.id_house_rent_flow as ods_id,
		coalesce((hrf.id_house || lpad(coalesce(vdh."version"::varchar(3), '1'), 3, '0'))::bigint, -1::bigint) as sk_house,
		coalesce(to_char(hrf.dt_house_first_listing, 'YYYYMMDD')::integer, -1) as sk_house_first_listing_date,
		coalesce(to_char(vdh.min_version_time, 'YYYYMMDD')::integer, -1) as sk_house_listing_date,
		coalesce(to_char(vdh.de_publication_date, 'YYYYMMDD')::integer, -1) as sk_house_de_publication_date,
		coalesce(to_char(min(vdo.dt_created) over (partition by hrf.id_house), 'YYYYMMDD')::integer, -1) as sk_house_first_offer_submitted_date,
	  coalesce(vdh.regiao_id, -1) as sk_region,
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
	  vdo.sk_offer,
	  coalesce(to_char(vdo.dt_first_sent, 'YYYYMMDD')::integer, -1) as sk_offer_submitted_date,
	  vdo.dt_first_sent as dt_offer_submitted,
	  coalesce(to_char(vdo.dt_approved, 'YYYYMMDD')::integer, -1) as sk_offer_approved_date,
	  vdo.dt_approved as dt_offer_approved,
	  case
	    when vdo.status in ('Aprovada', 'Rejeitada')
	      then vdp.dt_updated
	    else null::timestamp
	  end dt_internal_analysis,
	  coalesce(hrf.id_proposal, -1) as sk_proposal,
	  coalesce(to_char(hrf.dt_proposal_approved, 'YYYYMMDD')::integer, -1) as sk_proposal_approved_date,
	  hrf.dt_proposal_approved,
	  coalesce(to_char(vdp.dt_tenant_first_document_sent, 'YYYYMMDD')::integer, -1) as sk_tenant_first_document_sent_date,
	  vdp.dt_tenant_first_document_sent,
	  case
      when vdp.status in ('Aprovada', 'Rejeitada')
       then vdp.dt_updated
      else null::timestamp
    end as dt_credit_analysis, -- old credit analysis date
	  coalesce(hrf.id_contract, -1) as sk_contract,
	  coalesce(to_char(hrf.dt_contract_created, 'YYYYMMDD')::integer, -1) as sk_contract_created_date,
	  coalesce(to_char(hrf.dt_contract_signed, 'YYYYMMDD')::integer, -1) as sk_contract_signed_date,
	  coalesce(to_char(hrf.dt_annulment, 'YYYYMMDD')::integer, -1) as sk_contract_annulment_date,
	  case
      when c.status in ('Ativo', 'Finalizado')
          then "dataAssinado"
      else null::timestamp
    end as dt_contract,
    coalesce(to_char(vdp.dt_credit_analysis_init, 'YYYYMMDD')::integer, -1) as sk_credit_analysis_init_date,
    vdp.dt_credit_analysis_init,
    coalesce(to_char(vdp.dt_credit_analysis_end, 'YYYYMMDD')::integer, -1) as sk_credit_analysis_end_date,
    vdp.dt_credit_analysis_end,
    case
      when vdp.status_sortinghat = 'APPROVED'
        then coalesce(to_char(vdp.dt_credit_analysis_end, 'YYYYMMDD')::integer, -1)
      else -1
    end as sk_credit_analysis_approved_date,
    case
      when vdp.status_sortinghat = 'APPROVED'
        then vdp.dt_credit_analysis_end
      else null::timestamp
    end as dt_credit_analysis_approved,
	  hrf.visit_created_from_app,
	  hrf.visit_created_type,
	  hrf.visit_last_updated_from_app,
	  hrf.visit_last_updated_type,
	  now()::timestamp as dt_timestamp
	from house_rent_flow hrf
	left join vw_dim_property vdh
	  on vdh.id = hrf.id_house
	  	and coalesce(hrf.dt_rent_flow_created, '1900-01-01') between coalesce(vdh.min_version_time, '1900-01-01')
		                                              and coalesce(vdh.max_version_time, now())
  left join vw_dim_offer vdo
    on vdo.sk_offer = case
                        when hrf.id_offer > 0
                          then (hrf.id_offer * 100) + 2
                        when hrf.id_pre_proposal > 0
                          then (hrf.id_pre_proposal * 100) + 1
                        else -1
                      end
      and vdo.sk_offer != -1
  left join pre_proposal pp
    on hrf.id_pre_proposal = pp.id
  left join vw_dim_proposal vdp
    on hrf.id_proposal = vdp.id_proposal
  left join contract c
    on hrf.id_contract = c.id
)
select
  ods_id,
  sk_house,
  sk_house_first_listing_date,
  sk_house_listing_date,
  sk_house_de_publication_date,
  sk_house_first_offer_submitted_date,
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
  sk_tenant_first_document_sent_date,
  sk_contract,
  sk_contract_created_date,
  sk_contract_signed_date,
  sk_contract_annulment_date,
  sk_credit_analysis_init_date,
  sk_credit_analysis_end_date,
  sk_credit_analysis_approved_date,
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