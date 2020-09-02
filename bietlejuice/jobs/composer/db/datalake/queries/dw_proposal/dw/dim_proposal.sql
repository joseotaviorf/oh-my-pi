with credit_evaluation as (
  -- following columns shouldn't differ among the same proposal
  -- however, if they do, we will get the most recent one
  select distinct
    id_proposal,
    ce.ts_proposal_first_credit_evaluation_positive,
    ce.ts_proposal_last_credit_evaluation_positive,
    ce.proposal_last_result,
    ce.proposal_number_evaluations,
    row_number() over (
      partition by id_proposal order by ts_updated desc, ts_created desc
    ) as proposal_credit_evaluation_row_number
  from
    datalake_docx.credit_evaluation ce
),
sorting_hat_proposal as (
  select
    p.id,
    p.status,
    row_number() over (
    -- TODO [ODS] Check if it makes sense to shift to last version instead of first
      partition by p.id order by pv.id
    ) as proposal_version_row_number
  from datalake_sorting_hat_clean.proposal p
	left join datalake_sorting_hat_clean.proposal_version pv
		on p.id = pv.id_proposal
)
select
  p.id as sk_proposal,
  p.id as id_proposal,
  p.guarantee,
  p.status,
  p.tenant_documentation_status,
  p.owner_documentation_status,
  p.rejection_reason,
  ce.proposal_last_result as result_last_credit_evaluation,
  nullif(sh.status, '') as sorting_hat_proposal_status,
  p.rent_proposal as renting_proposal_value,
  p.tenant_doc_sent_count as tenant_documentation_sent_count,
  ce.proposal_number_evaluations as credit_evaluation_count,
  p.has_tenant_sent_documentation,
  p.has_tenant_accepted_contract,
  p.has_owner_accepted_contract,
  p.has_owner_sent_documentation,
  p.is_doc_reused,
  p.ts_proposal,
  p.ts_approved,
  p.ts_processed,
  p.ts_created,
  p.ts_updated,
  p.ts_documentation_sent as ts_tenant_documentation_sent,
  p.ts_owner_documentation_sent,
  date_trunc('day', p.ts_tenant_first_doc_sent) as ts_tenant_first_doc_sent,
  p.ts_tenant_auto_first_doc_sent,
  p.ts_credit_analysis_first_init,
  p.ts_credit_analysis_last_init,
  p.ts_credit_analysis_first_end,
  p.ts_credit_analysis_last_end,
  p.ts_credit_approved_last,
  p.ts_tenant_first_doc_complete,
  p.ts_tenant_last_doc_complete,
  p.ts_credit_evaluation_first_init,
  p.ts_credit_evaluation_last_init,
  p.ts_credit_evaluation_first_negative,
  p.ts_credit_evaluation_last_negative,
  p.ts_guarantee,
  p.ts_doc_analysis_first_approved,
  p.ts_doc_analysis_last_approved,
  p.ts_doc_analysis_first_rejected,
  p.ts_doc_analysis_last_rejected,
  p.ts_guarantee_paid,
  ce.ts_proposal_first_credit_evaluation_positive,
  ce.ts_proposal_last_credit_evaluation_positive,
  now() as ts_load
from datalake_proposal.proposal p
left join credit_evaluation ce
  on ce.proposal_credit_evaluation_row_number = 1
     and p.id = ce.id_proposal
left join sorting_hat_proposal sh
  on sh.proposal_version_row_number = 1
     and sh.id = p.id