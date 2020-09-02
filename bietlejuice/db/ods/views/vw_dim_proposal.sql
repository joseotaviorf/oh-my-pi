--drop view if exists vw_dim_proposal;
--create or replace view vw_dim_proposal as
with sortinghat_prop_prev as (
	select
		p.id,
		p.imovel_id,
		p.analysis_date,
		p.score_5a,
		p.score_5a_best_subset,
		p.score_cardif,
	  p.score_cardif_best_subset,
	  p.status,
	  p."comment",
	  p.analyst_name,
	  p.supervisor_name,
	  p.rent_value,
	  p.condo_value,
	  p.iptu_value,
	  p.created_at,
	  p.updated_at,
	  p.home_area,
	  p.home_bathrooms,
	  p.home_bedrooms,
	  p.home_city,
	  p.home_garages,
	  p.home_region,
	  p.home_suites,
	  p.home_type,
	  p.home_zipcode,
	  p.drive_id,
	  p.reason,
	  p.home_insurance_value,
	  p.risk_level,
	  p.risk_level_best_subset,
	  p.process_date,
	  pv.analysis_date as version_analysis_date,
		row_number() over (partition by p.id order by pv.id) as rn
	from sortinghat.proposal p
	left join sortinghat.proposalversion pv
		on p.id = pv.proposal_id
),
sortinghat_prop as (
  select
  	id,
  	imovel_id,
  	analysis_date,
  	score_5a,
  	score_5a_best_subset,
  	score_cardif,
    score_cardif_best_subset,
    status,
    "comment",
    analyst_name,
    supervisor_name,
    rent_value,
    condo_value,
    iptu_value,
    created_at,
    updated_at,
    home_area,
    home_bathrooms,
    home_bedrooms,
    home_city,
    home_garages,
    home_region,
    home_suites,
    home_type,
    home_zipcode,
    drive_id,
    reason,
    home_insurance_value,
    risk_level,
    risk_level_best_subset,
    process_date,
    coalesce(version_analysis_date, analysis_date) as first_analysis_date
  from sortinghat_prop_prev
  where rn = 1
),
credit_evaluation_order as (
select
	id_proposal,
	min(case when "result" in ('PRE_APPROVED','REGULAR') then ts_updated end) as credit_evaluation_positive_first_date,
	max(case when "result" in ('PRE_APPROVED','REGULAR') then ts_updated end) as credit_evaluation_positive_last_date,
	max(ts_updated) as credit_evaluation_last_updated_date,
	max(ts_created) as credit_evaluation_last_created_date,
	count(distinct id) as number_evaluations
from public.credit_evaluation
where status = 'FINISHED'
group by 1
),
credit_evaluation as (
select
    ceo.id_proposal,
    ceo.credit_evaluation_positive_first_date,
    ceo.credit_evaluation_positive_last_date,
    ce."result" as result_last,
    ceo.number_evaluations
from credit_evaluation_order ceo
join public.credit_evaluation ce
  on ceo.id_proposal = ce.id_proposal
    and ceo.credit_evaluation_last_updated_date = ce.ts_updated
    and ceo.credit_evaluation_last_created_date = ce.ts_created
)
select
  p.id as sk_proposal,
  p.id as id_proposal,
  p."dataProposta" as dt_proposal,
  p.garantia as guarantee,
  p."propostaAluguel" as renting_proposal_value,
  p.status,
  p."dataAprovacao" as dt_proposal_approved,
  p."inquilinoEnviouDocumentos" as tenant_document_sent,
  p."dataDocumentosEnviados" as dt_tenant_document_sent,
  p."proprietarioEnviouDocumentos" as owner_document_sent,
  p."dataDocumentosProprietarioEnviados" as dt_owner_document_sent,
  p."inquilinoAceitouContrato" as tenant_contract_accepted,
  p."proprietarioAceitouContrato" as owner_contract_accepted,
  p."statusDocumentacaoInq" as status_doc_tenant,
  p."statusDocumentacaoProp" as status_doc_owner,
  p.tenant_doc_sent_count,
  p."criadoEm" as dt_created,
  p."atualizadoEm" as dt_updated,
  now()::timestamp as dt_timestamp,
  date(p.tenant_first_doc_sent) as dt_tenant_first_document_sent,
  tenant_auto_first_doc_sent as dt_tenant_auto_first_doc_sent,
  p.credit_analysis_first_init_date as dt_credit_analysis_first_init,
  p.credit_analysis_last_init_date as dt_credit_analysis_last_init,
  case
    when cast(p."criadoEm" as date) < date('2020-01-02')
      then
        coalesce(shp.first_analysis_date, p.credit_analysis_last_init_date)
    else
      p.credit_analysis_last_init_date
  end as dt_credit_analysis_init,
  p.credit_analysis_first_end_date as dt_credit_analysis_first_end,
  p.credit_analysis_last_end_date as dt_credit_analysis_last_end,
  case
    when cast(p."criadoEm" as date) < date('2020-01-02')
      then
        coalesce(shp.process_date, p.credit_analysis_last_end_date, shp.analysis_date)
    else
      p.credit_analysis_last_end_date
  end as dt_credit_analysis_end,
  p.credit_approved_last_date as dt_credit_last_approved,
  p.tenant_first_doc_complete_date as dt_tenant_first_doc_complete,
  p.tenant_last_doc_complete_date as dt_tenant_last_doc_complete,
  p.tenant_last_doc_complete_date as dt_tenant_doc_complete,
  p.credit_evaluation_first_init_date as dt_first_credit_evaluation_init,
  p.credit_evaluation_last_init_date as dt_last_credit_evaluation_init,
  ce.credit_evaluation_positive_first_date as dt_first_credit_evaluation_positive,
  ce.credit_evaluation_positive_last_date as dt_last_credit_evaluation_positive,
  p.credit_evaluation_negative_first_date as dt_first_credit_evaluation_negative,
  p.credit_evaluation_negative_last_date as dt_last_credit_evaluation_negative,
  p.guarantee_date as dt_guarantee,
  p.doc_analysis_first_approved_date as dt_first_doc_analysis_approved,
  p.doc_analysis_last_approved_date as dt_last_doc_analysis_approved,
  p.doc_analysis_first_rejected_date as dt_first_doc_analysis_rejected,
  p.doc_analysis_last_rejected_date as dt_last_doc_analysis_rejected,
  p.garantiaPagaEm as dt_guarantee_paid,
  nullif(shp.status, '') as status_sortinghat,
  nullif(ce.result_last, '') as result_credit_evaluation,
  ce.number_evaluations as credit_evaluation_count,
  doc_reused as flg_doc_reused,
  p.ts_processed,
  p.rejection_reason,
  now()::timestamp as ts_load
from proposal p
left join sortinghat_prop shp
  on shp.id = p.id
left join credit_evaluation ce
  on p.id = ce.id_proposal
;
