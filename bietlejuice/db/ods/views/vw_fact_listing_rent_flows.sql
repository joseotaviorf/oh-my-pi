drop view if exists vw_fact_listing_rent_flows;
create or replace view vw_fact_listing_rent_flows as
with _fact as (
	select
	  hrf.id_house_rent_flow as ods_id,
	  coalesce((hrf.id_house || lpad(coalesce(vdh."version"::varchar(3), '1'), 3, '0'))::bigint, -1::bigint) as sk_house_listing,
	  hrf.id_house,
	  coalesce(to_char(hrf.dt_house_first_listing, 'YYYYMMDD')::integer, -1) as sk_house_first_listing_date,
	  coalesce(to_char(vdh.ts_listing_version_start, 'YYYYMMDD')::integer, -1) as sk_house_listing_date,
	  vdh.ts_listing_version_start as dt_house_listing,
	  coalesce(to_char(vdh.ts_de_publication, 'YYYYMMDD')::integer, -1) as sk_house_listing_de_publication_date,
	  coalesce(to_char(min(vdo.dt_created) over (partition by hrf.id_house), 'YYYYMMDD')::integer, -1) as sk_house_listing_first_offer_submitted_date,
	  coalesce(vfhl.sk_region, -1) as sk_region,
	  coalesce(hrf.id_rent_flow, -1) as sk_rent_flow,
	  coalesce(hrf.id_booking, -1) as sk_booking,
	  coalesce(to_char(hrf.dt_booking_created, 'YYYYMMDD')::integer, -1) as sk_booking_created_date,
	  hrf.dt_booking_created,
	  coalesce(to_char(hrf.dt_visit, 'YYYYMMDD')::integer, -1) as sk_visit_date,
	  hrf.dt_visit,
	  hrf.visit_completed as flg_visit_completed,
	  hrf.visit_performed as flg_visit_performed,
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
	  coalesce(to_char(vdp.dt_tenant_first_document_sent, 'YYYYMMDD')::integer, -1) as sk_tenant_manual_first_doc_sent_date,
	  coalesce(to_char(vdp.dt_tenant_auto_first_doc_sent, 'YYYYMMDD')::integer, -1) as sk_tenant_auto_first_doc_sent_date,
	  vdp.dt_tenant_first_document_sent as dt_tenant_manual_first_doc_sent,
	  vdp.dt_tenant_auto_first_doc_sent,
	  coalesce(vdp.dt_tenant_auto_first_doc_sent, dt_tenant_first_document_sent) as dt_tenant_first_doc_sent,
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
          then c.ts_signature
      else null::timestamp
    end as ts_contract_valid_signature,
    coalesce(to_char(c.ts_canceled, 'YYYYMMDD')::integer, -1) as sk_contract_canceled_date,
    c.ts_canceled as ts_contract_canceled,
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
    coalesce(to_char(vdp.ts_processed, 'YYYYMMDD')::integer, -1) as sk_proposal_processed_date,
    vdp.ts_processed as ts_proposal_processed,
    vdp.status as proposal_status,
    vdp.tenant_document_sent as has_tenant_sent_doc,
	  hrf.visit_created_from_app as flg_visit_created_from_app,
	  hrf.visit_created_type,
	  hrf.visit_last_updated_from_app as flg_visit_last_updated_from_app,
	  hrf.visit_last_updated_type,
	  coalesce(to_char(ar.dt_rating, 'YYYYMMDD')::integer, -1) as sk_agent_review_rating_date,
	  now()::timestamp as ts_load
	from house_rent_flow hrf
	left join vw_dim_house_listing vdh
	  on vdh.id_house = hrf.id_house
	  	and coalesce(hrf.dt_rent_flow_created, '1900-01-01') between coalesce(vdh.ts_listing_version_start, '1900-01-01')
		                                              and coalesce(vdh.ts_listing_version_end, now())
  left join vw_fact_house_listings vfhl
    on vfhl.sk_house_listing = vdh.sk_house_listing
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
  left join vw_dim_contract c
    on hrf.id_contract = c.id_contract
  left join agent_review ar
    on hrf.id_booking = ar.id_booking
)
select
  ods_id,
  sk_house_listing,
  sk_house_first_listing_date,
  sk_house_listing_date,
  sk_house_listing_de_publication_date,
  sk_house_listing_first_offer_submitted_date,
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
  sk_proposal_processed_date,
  case when sk_tenant_auto_first_doc_sent_date = -1 then sk_tenant_manual_first_doc_sent_date else sk_tenant_auto_first_doc_sent_date end as sk_tenant_first_doc_sent_date,
  sk_tenant_manual_first_doc_sent_date,
  sk_tenant_auto_first_doc_sent_date,
  sk_contract,
  sk_contract_created_date,
  sk_contract_signed_date,
  sk_contract_annulment_date,
  sk_contract_canceled_date,
  sk_credit_analysis_init_date,
  sk_credit_analysis_end_date,
  sk_credit_analysis_approved_date,
  flg_visit_completed,
  flg_visit_performed,
  flg_visit_created_from_app,
  visit_created_type,
  flg_visit_last_updated_from_app,
  visit_last_updated_type,
  ((date_part('day', dt_visit - dt_booking_created) * 1440 +
    date_part('hour', dt_visit - dt_booking_created) * 60 +
		date_part('minute', dt_visit - dt_booking_created)) / 1440.)::numeric(14,2) as days_booking_to_visit,
  ((date_part('day', dt_visit - dt_client_sign_up) * 1440 +
    date_part('hour', dt_visit - dt_client_sign_up) * 60 +
		date_part('minute', dt_visit - dt_client_sign_up)) / 1440.)::numeric(14,2) as days_user_creation_to_visit,
  ((date_part('day', dt_internal_analysis - dt_offer_submitted) * 1440 +
    date_part('hour', dt_internal_analysis - dt_offer_submitted) * 60 +
		date_part('minute', dt_internal_analysis - dt_offer_submitted)) / 1440.)::numeric(14,2) as days_offer_submitted_to_internal_analyis,
  ((date_part('day', dt_tenant_first_doc_sent - dt_offer_approved) * 1440 +
    date_part('hour', dt_tenant_first_doc_sent - dt_offer_approved) * 60 +
		date_part('minute', dt_tenant_first_doc_sent - dt_offer_approved)) / 1440.)::numeric(14,2) as days_offer_approved_to_doc_first_sent,
  ((date_part('day', coalesce(dt_credit_analysis_end, dt_credit_analysis) - dt_tenant_first_doc_sent) * 1440 +
    date_part('hour', coalesce(dt_credit_analysis_end, dt_credit_analysis) - dt_tenant_first_doc_sent) * 60 +
		date_part('minute', coalesce(dt_credit_analysis_end, dt_credit_analysis) - dt_tenant_first_doc_sent)) / 1440.)::numeric(14,2) as days_doc_first_sent_to_credit_processed,
  ((date_part('day', dt_credit_analysis_init - dt_tenant_first_doc_sent) * 1440 +
    date_part('hour', dt_credit_analysis_init - dt_tenant_first_doc_sent) * 60 +
		date_part('minute', dt_credit_analysis_init - dt_tenant_first_doc_sent)) / 1440.)::numeric(14,2) as days_doc_first_sent_to_doc_completed,
  ((date_part('day', coalesce(dt_credit_analysis_end, dt_credit_analysis) - dt_credit_analysis_init) * 1440 +
    date_part('hour', coalesce(dt_credit_analysis_end, dt_credit_analysis) - dt_credit_analysis_init) * 60 +
		date_part('minute', coalesce(dt_credit_analysis_end, dt_credit_analysis) - dt_credit_analysis_init)) / 1440.)::numeric(14,2) as days_doc_completed_to_credit_processed,
  ((date_part('day', dt_contract_created - dt_credit_analysis_approved) * 1440 +
    date_part('hour', dt_contract_created - dt_credit_analysis_approved) * 60 +
		date_part('minute', dt_contract_created - dt_credit_analysis_approved)) / 1440.)::numeric(14,2) as days_credit_approved_to_contract_created,
  ((date_part('day', dt_contract_signed - dt_credit_analysis_approved) * 1440 +
    date_part('hour', dt_contract_signed - dt_credit_analysis_approved) * 60 +
		date_part('minute', dt_contract_signed - dt_credit_analysis_approved)) / 1440.)::numeric(14,2) as days_credit_approved_to_contract_signed,
  ((date_part('day', dt_contract_signed - dt_contract_created) * 1440 +
    date_part('hour', dt_contract_signed - dt_contract_created) * 60 +
		date_part('minute', dt_contract_signed - dt_contract_created)) / 1440.)::numeric(14,2) as days_contract_created_to_contract_signed,
  ((date_part('day', dt_contract_signed - dt_booking_created) * 1440 +
    date_part('hour', dt_contract_signed - dt_booking_created) * 60 +
		date_part('minute', dt_contract_signed - dt_booking_created)) / 1440.)::numeric(14,2) as days_booking_to_contract_signed,
  ((date_part('day', dt_contract_signed - dt_visit) * 1440 +
    date_part('hour', dt_contract_signed - dt_visit) * 60 +
		date_part('minute', dt_contract_signed - dt_visit)) / 1440.)::numeric(14,2) as days_visit_to_contract_signed,
  ((date_part('day', dt_offer_submitted - dt_visit) * 1440 +
    date_part('hour', dt_offer_submitted - dt_visit) * 60 +
		date_part('minute', dt_offer_submitted - dt_visit)) / 1440.)::numeric(14,2) as days_visit_to_offer_submitted,
  ((date_part('day', dt_offer_submitted - dt_booking_created) * 1440 +
    date_part('hour', dt_offer_submitted - dt_booking_created) * 60 +
		date_part('minute', dt_offer_submitted - dt_booking_created)) / 1440.)::numeric(14,2) as days_booking_created_to_offer_submitted,
  ((date_part('day', dt_credit_analysis_approved - dt_tenant_first_doc_sent) * 1440 +
    date_part('hour', dt_credit_analysis_approved - dt_tenant_first_doc_sent) * 60 +
		date_part('minute', dt_credit_analysis_approved - dt_tenant_first_doc_sent)) / 1440.)::numeric(14,2) as days_tenant_doc_sent_to_insurance_approval,
  ((date_part('day', dt_contract_signed - dt_credit_analysis_approved) * 1440 +
    date_part('hour', dt_contract_signed - dt_credit_analysis_approved) * 60 +
		date_part('minute', dt_contract_signed - dt_credit_analysis_approved)) / 1440.)::numeric(14,2) as days_insurance_approval_to_contract_signed,
  ((date_part('day', coalesce(dt_tenant_auto_first_doc_sent, dt_offer_approved) - dt_credit_analysis_approved) * 1440 +
    date_part('hour', coalesce(dt_tenant_auto_first_doc_sent, dt_offer_approved) - dt_credit_analysis_approved) * 60 +
		date_part('minute', coalesce(dt_tenant_auto_first_doc_sent, dt_offer_approved) - dt_credit_analysis_approved)) / 1440.)::numeric(14,2) as days_offer_approved_to_tenant_doc_sent,
  ((date_part('day', dt_offer_approved - dt_offer_submitted) * 1440 +
    date_part('hour', dt_offer_approved - dt_offer_submitted) * 60 +
		date_part('minute', dt_offer_approved - dt_offer_submitted)) / 1440.)::numeric(14,2) as days_offer_submitted_to_offer_approved,
  ((date_part('day', dt_credit_analysis_init - dt_offer_approved) * 1440 +
    date_part('hour', dt_credit_analysis_init - dt_offer_approved) * 60 +
		date_part('minute', dt_credit_analysis_init - dt_offer_approved)) / 1440.)::numeric(14,2) as days_offer_approved_to_credit_init,
  ((date_part('day', dt_contract_signed - dt_offer_submitted) * 1440 +
    date_part('hour', dt_contract_signed - dt_offer_submitted) * 60 +
		date_part('minute', dt_contract_signed - dt_offer_submitted)) / 1440.)::numeric(14,2) as days_offer_submitted_to_contract_signed,
  ((date_part('day', dt_credit_analysis_approved - dt_credit_analysis_init) * 1440 +
    date_part('hour', dt_credit_analysis_approved - dt_credit_analysis_init) * 60 +
		date_part('minute', dt_credit_analysis_approved - dt_credit_analysis_init)) / 1440.)::numeric(14,2) as days_tenant_doc_completed_to_credit_approved,
  ((date_part('day', dt_credit_analysis_init - dt_tenant_first_doc_sent) * 1440 +
    date_part('hour', dt_credit_analysis_init - dt_tenant_first_doc_sent) * 60 +
		date_part('minute', dt_credit_analysis_init - dt_tenant_first_doc_sent)) / 1440.)::numeric(14,2) as days_tenant_doc_sent_to_doc_completed,
  ((date_part('day', dt_contract_signed - dt_house_listing) * 1440 +
    date_part('hour', dt_contract_signed - dt_house_listing) * 60 +
		date_part('minute', dt_contract_signed - dt_house_listing)) / 1440.)::numeric(14,2) as days_house_listing_to_contract_signed,
  ((date_part('day', dt_visit - dt_house_listing) * 1440 +
    date_part('hour', dt_visit - dt_house_listing) * 60 +
		date_part('minute', dt_visit - dt_house_listing)) / 1440.)::numeric(14,2) as days_house_listing_to_visit,
  ((date_part('day', coalesce(ts_contract_valid_signature, ts_contract_canceled, ts_proposal_processed) - dt_credit_analysis_approved) * 1440 +
    date_part('hour', coalesce(ts_contract_valid_signature, ts_contract_canceled, ts_proposal_processed) - dt_credit_analysis_approved) * 60 +
		date_part('minute', coalesce(ts_contract_valid_signature, ts_contract_canceled, ts_proposal_processed) - dt_credit_analysis_approved)) / 1440.)::numeric(14,2) as days_credit_approved_to_closing_processed,
  ((date_part('day', coalesce(dt_tenant_first_doc_sent, case when proposal_status = 'Rejeitada' and has_tenant_sent_doc = 0 then ts_proposal_processed else null end) - dt_offer_approved) * 1440 +
    date_part('hour', coalesce(dt_tenant_first_doc_sent, case when proposal_status = 'Rejeitada' and has_tenant_sent_doc = 0 then ts_proposal_processed else null end) - dt_offer_approved) * 60 +
		date_part('minute', coalesce(dt_tenant_first_doc_sent, case when proposal_status = 'Rejeitada' and has_tenant_sent_doc = 0 then ts_proposal_processed else null end) - dt_offer_approved)) / 1440.)::numeric(14,2) as days_offer_approved_to_doc_contact,
	sk_agent_review_rating_date,
    ts_load
from _fact
;
