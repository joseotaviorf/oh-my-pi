with
rent_flows_temp as (
	with
	proposal_main as (
	  select
	    p_aud.id_proposal as id_proposal,
	  -- It remains the same, and this result should be the same as the first date when statusDocumentacaoInq = 'Analise5a'
	    min(p_aud.ts_documentation_sent) as tenant_first_doc_sent,
	    count(distinct p_aud.ts_documentation_sent) as tenant_doc_sent_count,
	    -- New column to consider credit evaluation step
	    -- New column to consider credit evaluation started
	    min(
	      case
	        when from_unixtime(ure.ts_revision/1000) > date('2020-06-07')
	          then case when p_aud.tenant_documentation_status = 'AnaliseCredito' then from_unixtime(ure.ts_revision/1000) else null end
	        else
	          null
	      end
	    ) as credit_evaluation_first_init_date,
	    max(
	      case
	        when from_unixtime(ure.ts_revision/1000) > date('2020-06-07')
	          then case when p_aud.tenant_documentation_status = 'AnaliseCredito' then from_unixtime(ure.ts_revision/1000) else null end
	        else
	          null
	      end
	    ) as credit_evaluation_last_init_date,
	    -- New column to consider credit evaluation ended as negative
	    min(
	      case
	        when from_unixtime(ure.ts_revision/ 1000) > date('2020-06-07')
	          then case when (p_aud.tenant_documentation_status = 'RecusadoCredito' and rejection_reason = 'CreditEvaluationRejected') then  from_unixtime(ure.ts_revision/ 1000) else null end
	        else
	          null
	      end
	    ) as credit_evaluation_negative_first_date,
	    max(
	      case
	        when from_unixtime(ure.ts_revision/1000) > date('2020-06-07')
	          then case when (p_aud.tenant_documentation_status = 'RecusadoCredito' and rejection_reason = 'CreditEvaluationRejected') then from_unixtime(ure.ts_revision/ 1000) else null end
	        else
	          null
	      end
	    ) as credit_evaluation_negative_last_date,
	    -- For the new flow it's important to know when the doc analysis ended and was approved/rejected
	    min(
	     case
	        when from_unixtime(ure.ts_revision/ 1000) > date('2020-06-07')
	      then case when p_aud.tenant_documentation_status = 'Aprovado' then from_unixtime(ure.ts_revision/1000) else null end
	      else
	          null
	      end
	    ) as doc_analysis_first_approved_date,
	    max(
	     case
	        when from_unixtime(ure.ts_revision/ 1000) > date('2020-06-07')
	      then case when p_aud.tenant_documentation_status = 'Aprovado' then from_unixtime(ure.ts_revision/ 1000) else null end
	      else
	          null
	      end
	    ) as doc_analysis_last_approved_date,
	    min(
	     case
	        when from_unixtime(ure.ts_revision/ 1000) > date('2020-06-07')
	      then case when (p_aud.tenant_documentation_status = 'RecusadoCredito' and rejection_reason = 'TenantDocumentationRejected') then  from_unixtime(ure.ts_revision/1000) else null end
	      else
	          null
	      end
	    ) as doc_analysis_first_rejected_date,
	    max(
	     case
	        when from_unixtime(ure.ts_revision/ 1000) > date('2020-06-07')
	      then case when (p_aud.tenant_documentation_status = 'RecusadoCredito' and rejection_reason = 'TenantDocumentationRejected') then  from_unixtime(ure.ts_revision/1000) else null end
	      else
	          null
	      end
	    ) as doc_analysis_last_rejected_date
	  from datalake_ebdb_clean_prod.proposal_aud p_aud
	  join datalake_ebdb_clean_prod.user_revision_entity ure
	    on p_aud.rev = ure.id
	  group by p_aud.id_proposal
	),
	order_evalutaion as (
	select
	    *,
	    row_number() over(partition by proposal_id order by updated_at desc) as rn_last
	from datalake_docx_raw_prod.credit_evaluation
	where status <> 'PROCESSING'
	),
	evaluation_proposal as (
	select
	    proposal_id,
	    min(case when result in ('PRE_APPROVED','REGULAR') then updated_at end) as credit_evaluation_positive_first_date,
	    max(case when result in ('PRE_APPROVED','REGULAR') then updated_at end) as credit_evaluation_positive_last_date,
	    min(case when rn_last = 1 then result end) as result_last,
	    count(distinct id) as number_evaluations
	from order_evalutaion
	group by 1
	)
	select
	  rf.sk_house_listing,
	  rf.sk_region,
	  rf.sk_booking,
	  rf.sk_booking_created_date,
	  rf.sk_visit,
	  rf.sk_visit_date,
	  rf.flg_visit_completed,
	  case when (rf.sk_visit_date > 0 and rf.flg_visit_completed is true) then rf.sk_visit_date end as sk_visit_completed_date,
	  rf.sk_offer,
	  rf.sk_offer_submitted_date,
	  rf.sk_offer_approved_date,
	  rf.sk_proposal,
	  rf.sk_tenant_first_doc_sent_date,
	  coalesce(to_char(prop.credit_evaluation_first_init_date, 'YYYYMMDD')::integer, -1) as sk_first_credit_evaluation_init,
	  coalesce(to_char(prop.credit_evaluation_last_init_date, 'YYYYMMDD')::integer, -1) as sk_last_credit_evaluation_init,
	  coalesce(to_char(cast(ep.credit_evaluation_positive_first_date as timestamp), 'YYYYMMDD')::integer, -1) as sk_first_credit_evaluation_positive,
	  coalesce(to_char(cast(ep.credit_evaluation_positive_last_date as timestamp), 'YYYYMMDD')::integer, -1) as sk_last_credit_evaluation_positive,
	  coalesce(to_char(prop.credit_evaluation_negative_first_date, 'YYYYMMDD')::integer, -1) as sk_first_credit_evaluation_negative,
	  coalesce(to_char(prop.credit_evaluation_negative_last_date, 'YYYYMMDD')::integer, -1) as sk_last_credit_evaluation_negative,
	  ep.result_last as result_credit_evaluation,
	  coalesce(to_char(prop.doc_analysis_first_approved_date, 'YYYYMMDD')::integer, -1) as sk_first_doc_analysis_approved,
	  coalesce(to_char(prop.doc_analysis_last_approved_date, 'YYYYMMDD')::integer, -1) as sk_last_doc_analysis_approved,
	  coalesce(to_char(prop.doc_analysis_first_rejected_date, 'YYYYMMDD')::integer, -1) as sk_first_doc_analysis_rejected,
	  coalesce(to_char(prop.doc_analysis_last_rejected_date, 'YYYYMMDD')::integer, -1) as sk_last_doc_analysis_rejected,
    ep.number_evaluations as number_credit_evaluations,
    rf.sk_contract_created_date,
    rf.sk_contract_signed_date,
    rf.sk_contract
	from fact_listing_rent_flows rf
	left join proposal_main prop
	 on rf.sk_proposal = prop.id_proposal
	left join evaluation_proposal ep
	  on rf.sk_proposal = ep.proposal_id
)
select
	dd.date as booking_created,
	dr.city_group,
	count(distinct sk_booking) as booking_created,
	count(distinct case when sk_visit_date > 0 and flg_visit_completed is true then sk_booking end) as visit_completed,
	count(distinct case when sk_offer_submitted_date > 0 then sk_offer end) as offer_sent,
	count(distinct case when sk_offer_approved_date > 0 then sk_offer end) as offer_approved,
	count(distinct case when sk_first_credit_evaluation_init > 0 then sk_offer end) as credit_evaluation_started,
	count(distinct case when sk_last_credit_evaluation_positive > 0 then sk_offer end) as credit_evaluation_positive,
	count(distinct case when sk_tenant_first_doc_sent_date > 0 then sk_offer end) as doc_sent,
	count(distinct case when sk_last_doc_analysis_approved > 0 then sk_offer end) as doc_approved,
	count(distinct case when sk_last_doc_analysis_rejected > 0 then sk_offer end) as doc_rejected,
	count(distinct case when sk_contract_created_date > 0 then sk_contract end) as contract_created,
	count(distinct case when sk_contract_signed_date > 0 then sk_contract end) as contract_signed
from rent_flows_temp rft
left join dim_date dd
  on rft.sk_booking_created_date = dd.sk_date
left join dim_region dr
  on rft.sk_region = dr.sk_region
group by 1, 2