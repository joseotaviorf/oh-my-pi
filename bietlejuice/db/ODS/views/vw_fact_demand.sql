drop view if exists vw_fact_demand;
create or replace view vw_fact_demand as
with _fact as (
	select
		hrf.id_house_rent_flow as ods_id,
		coalesce((hrf.id_house || lpad(coalesce(vdh."version"::varchar(3), '1'), 3, '0'))::bigint, -1::bigint) as sk_house,
		hrf.id_house,
		coalesce(to_char(hrf.dt_house_first_listing, 'YYYYMMDD')::integer, -1) as sk_house_first_listing_date,
		coalesce(to_char(vdh.min_version_time, 'YYYYMMDD')::integer, -1) as sk_house_listing_date,
		vdh.min_version_time as dt_house_listing,
		coalesce(to_char(vdh.de_publication_date, 'YYYYMMDD')::integer, -1) as sk_house_de_publication_date,
		coalesce(to_char(min(vdo.dt_created) over (partition by hrf.id_house), 'YYYYMMDD')::integer, -1) as sk_house_first_offer_submitted_date,
	  coalesce(vdh.regiao_id, -1) as sk_region,
	  coalesce(hrf.id_rent_flow, -1) as sk_rent_flow,
	  coalesce(hrf.id_booking, -1) as sk_booking,
	  coalesce(to_char(hrf.dt_booking_created, 'YYYYMMDD')::integer, -1) as sk_booking_created_date,
	  hrf.dt_booking_created,
	  coalesce(to_char(hrf.dt_visit, 'YYYYMMDD')::integer, -1) as sk_visit_date,
	  hrf.dt_visit,
	  hrf.visit_completed as flg_visit_completed,
	  coalesce(hrf.id_owner, -1) as sk_owner,
	  coalesce(hrf.id_user_agent, -1) as sk_user_agent,
	  coalesce(to_char(hrf.dt_agent_sign_up, 'YYYYMMDD')::integer, -1) as sk_agent_sign_up_date,
	  coalesce(hrf.id_client, -1) as sk_client,
	  coalesce(to_char(hrf.dt_client_sign_up, 'YYYYMMDD')::integer, -1) as sk_client_sign_up_date,
	  hrf.dt_client_sign_up,
	  coalesce(hrf.id_visit, -1) as sk_visit,
	  coalesce(vdo.sk_offer, -1) as sk_offer,
	  coalesce(to_char(vdo.dt_first_sent, 'YYYYMMDD')::integer, -1) as sk_offer_submitted_date,
	  vdo.dt_first_sent as dt_offer_submitted,
	  case
	    when vdo.status = 'Aprovada'
	      then coalesce(to_char(vdo.dt_analysis, 'YYYYMMDD')::integer, -1)
	    else -1
	  end as sk_offer_approved_date,
	  case
	    when vdo.status = 'Aprovada'
	      then vdo.dt_analysis
	    else null::timestamp
	  end as dt_offer_approved,
	  case
	    when vdo.status in ('Aprovada', 'Rejeitada')
	      then vdo.dt_analysis
	    else null::timestamp
	  end dt_internal_analysis,
	  coalesce(hrf.id_proposal, -1) as sk_proposal,
	  coalesce(to_char(hrf.dt_proposal_approved, 'YYYYMMDD')::integer, -1) as sk_proposal_approved_date,
	  hrf.dt_proposal_approved,
	  coalesce(to_char(vdp.dt_tenant_first_doc_sent, 'YYYYMMDD')::integer, -1) as sk_tenant_first_doc_sent_date,
	  coalesce(to_char(vdp.dt_tenant_auto_first_doc_sent, 'YYYYMMDD')::integer, -1) as sk_tenant_auto_first_doc_sent_date,
	  vdp.dt_tenant_first_doc_sent,
	  vdp.dt_tenant_auto_first_doc_sent,
	  case
      when vdp.status in ('Aprovada', 'Rejeitada')
       then vdp.dt_updated
      else null::timestamp
    end as dt_credit_analysis, -- old credit analysis date
	  coalesce(hrf.id_contract, -1) as sk_contract,
	  coalesce(to_char(hrf.dt_contract_created, 'YYYYMMDD')::integer, -1) as sk_contract_created_date,
	  hrf.dt_contract_created,
	  coalesce(to_char(hrf.dt_contract_signed, 'YYYYMMDD')::integer, -1) as sk_contract_signed_date,
	  hrf.dt_contract_signed,
	  coalesce(to_char(hrf.dt_contract_annulment, 'YYYYMMDD')::integer, -1) as sk_contract_annulment_date,
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
      when vdp.status_sortinghat = 'APPROVED' or vdp.status_doc_tenant = 'Aprovado'
        then coalesce(to_char(vdp.dt_credit_analysis_end, 'YYYYMMDD')::integer, -1)
      else -1
    end as sk_credit_analysis_approved_date,
    case
      when vdp.status_sortinghat = 'APPROVED' or vdp.status_doc_tenant = 'Aprovado'
        then vdp.dt_credit_analysis_end
      else null::timestamp
    end as dt_credit_analysis_approved,
	  hrf.visit_created_from_app as flg_visit_created_from_app,
	  hrf.visit_created_type,
	  hrf.visit_last_updated_from_app as flg_visit_last_updated_from_app,
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
  sk_offer,
  sk_offer_submitted_date,
  min(sk_offer_submitted_date) filter (where sk_offer_submitted_date != -1) over (partition by id_house) as sk_min_offer_submitted_date,
  sk_offer_approved_date,
  sk_proposal,
  sk_proposal_approved_date,
  sk_tenant_first_doc_sent_date,
  sk_tenant_auto_first_doc_sent_date,
  sk_contract,
  sk_contract_created_date,
  sk_contract_signed_date,
  sk_contract_annulment_date,
  sk_credit_analysis_init_date,
  sk_credit_analysis_end_date,
  sk_credit_analysis_approved_date,
  flg_visit_completed,
  flg_visit_created_from_app,
  visit_created_type,
  flg_visit_last_updated_from_app,
  visit_last_updated_type,
  ((date_part('day', dt_visit - dt_booking_created) * 1440 +
    date_part('hour', dt_visit - dt_booking_created) * 60 +
		date_part('minute', dt_visit - dt_booking_created)) / 1440.)::numeric(14,2) as booking_to_visit,
  ((date_part('day', dt_internal_analysis - dt_offer_submitted) * 1440 +
    date_part('hour', dt_internal_analysis - dt_offer_submitted) * 60 +
		date_part('minute', dt_internal_analysis - dt_offer_submitted)) / 1440.)::numeric(14,2) as offer_submitted_to_internal_analyis,
  ((date_part('day', coalesce(dt_tenant_auto_first_doc_sent, dt_tenant_first_doc_sent) - dt_offer_approved) * 1440 +
    date_part('hour', coalesce(dt_tenant_auto_first_doc_sent, dt_tenant_first_doc_sent) - dt_offer_approved) * 60 +
		date_part('minute', coalesce(dt_tenant_auto_first_doc_sent, dt_tenant_first_doc_sent) - dt_offer_approved)) / 1440.)::numeric(14,2) as offer_approved_to_doc_first_sent,
  ((date_part('day', coalesce(dt_credit_analysis_end, dt_credit_analysis) - coalesce(dt_tenant_auto_first_doc_sent, dt_tenant_first_doc_sent)) * 1440 +
    date_part('hour', coalesce(dt_credit_analysis_end, dt_credit_analysis) - coalesce(dt_tenant_auto_first_doc_sent, dt_tenant_first_doc_sent)) * 60 +
		date_part('minute', coalesce(dt_credit_analysis_end, dt_credit_analysis) - coalesce(dt_tenant_auto_first_doc_sent, dt_tenant_first_doc_sent))) / 1440.)::numeric(14,2) as doc_first_sent_to_credit_processed,
  ((date_part('day', dt_credit_analysis_init - coalesce(dt_tenant_auto_first_doc_sent, dt_tenant_first_doc_sent)) * 1440 +
    date_part('hour', dt_credit_analysis_init - coalesce(dt_tenant_auto_first_doc_sent, dt_tenant_first_doc_sent)) * 60 +
		date_part('minute', dt_credit_analysis_init - coalesce(dt_tenant_auto_first_doc_sent, dt_tenant_first_doc_sent))) / 1440.)::numeric(14,2) as doc_first_sent_to_doc_completed,
  ((date_part('day', coalesce(dt_credit_analysis_end, dt_credit_analysis) - dt_credit_analysis_init) * 1440 +
    date_part('hour', coalesce(dt_credit_analysis_end, dt_credit_analysis) - dt_credit_analysis_init) * 60 +
		date_part('minute', coalesce(dt_credit_analysis_end, dt_credit_analysis) - dt_credit_analysis_init)) / 1440.)::numeric(14,2) as doc_completed_to_credit_processed,
  ((date_part('day', dt_contract_created - dt_credit_analysis_approved) * 1440 +
    date_part('hour', dt_contract_created - dt_credit_analysis_approved) * 60 +
		date_part('minute', dt_contract_created - dt_credit_analysis_approved)) / 1440.)::numeric(14,2) as credit_approved_to_contract_created,
  ((date_part('day', dt_contract_signed - dt_credit_analysis_approved) * 1440 +
    date_part('hour', dt_contract_signed - dt_credit_analysis_approved) * 60 +
		date_part('minute', dt_contract_signed - dt_credit_analysis_approved)) / 1440.)::numeric(14,2) as credit_approved_to_contract_signed,
  ((date_part('day', dt_contract_signed - dt_contract_created) * 1440 +
    date_part('hour', dt_contract_signed - dt_contract_created) * 60 +
		date_part('minute', dt_contract_signed - dt_contract_created)) / 1440.)::numeric(14,2) as contract_created_to_contract_signed,
	date_part('day', dt_contract_signed - dt_booking_created)::integer as days_booking_to_contract_signed,
	date_part('day', dt_visit - dt_booking_created)::integer as days_booking_to_visit,
	date_part('day', dt_visit - dt_client_sign_up)::integer as days_user_creation_to_visit,
	date_part('day', dt_contract_signed - dt_visit)::integer as days_visit_to_contract_signed,
	date_part('day', dt_offer_submitted - dt_visit)::integer as days_visit_to_offer_submitted,
	date_part('day', dt_offer_submitted - dt_booking_created)::integer as days_booking_created_to_offer_submitted,
	date_part('day', dt_credit_analysis_approved - coalesce(dt_tenant_auto_first_doc_sent, dt_tenant_first_doc_sent))::integer as days_tenant_doc_sent_to_insurance_approval,
	date_part('day', dt_contract_signed - dt_credit_analysis_approved)::integer as days_insurance_approval_to_contract_signed,
	date_part('day', coalesce(dt_tenant_auto_first_doc_sent, dt_tenant_first_doc_sent) - dt_offer_approved)::integer as days_offer_approved_to_tenant_doc_sent,
	date_part('day', dt_offer_approved - dt_offer_submitted)::integer as days_offer_submitted_to_offer_approved,
	date_part('day', dt_credit_analysis_init - dt_offer_approved)::integer as days_offer_approved_to_credit_init,
	date_part('day', dt_contract_signed - dt_offer_submitted)::integer as days_offer_submitted_to_contract_signed,
	date_part('day', dt_credit_analysis_approved - dt_credit_analysis_init)::integer as days_tenant_doc_completed_to_credit_approved,
	date_part('day', dt_credit_analysis_init - coalesce(dt_tenant_auto_first_doc_sent, dt_tenant_first_doc_sent))::integer as days_tenant_doc_sent_to_doc_completed,
	date_part('day', dt_contract_created - dt_credit_analysis_approved)::integer as days_credit_approved_to_contract_created,
	date_part('day', dt_contract_signed - dt_credit_analysis_approved)::integer as days_credit_approved_to_contract_signed,
	date_part('day', dt_contract_signed - dt_contract_created)::integer as days_contract_created_to_contract_signed,
	date_part('day', dt_contract_signed - dt_house_listing)::integer as days_house_listing_to_contract_signed,
	date_part('day', dt_visit - dt_house_listing)::integer as days_house_listing_to_visit,
  dt_timestamp
from _fact
;