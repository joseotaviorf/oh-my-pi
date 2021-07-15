with
proposal_metrics as (
    select
        id_proposal,
        min(case when result in ('PRE_APPROVED', 'REGULAR') then ts_updated end) as ts_first_credit_evaluation_positive,
        max(case when result in ('PRE_APPROVED', 'REGULAR') then ts_updated end) as ts_last_credit_evaluation_positive,
        count(distinct id) as number_evaluations
    from datalake_docx_clean.credit_evaluation
    where status = 'FINISHED'
    group by 1
),
proposal_result as (
    select
        id_proposal,
        id,
        result,
        row_number() over (
            partition by id_proposal order by ts_updated desc, ts_created desc
        ) as latest_proposal_credit_evaluation_rn
    from datalake_docx_clean.credit_evaluation
    where status = 'FINISHED'
)
select
    ce.id,
    ce.id_proposal,
    ce.id_house,
    ce.id_user,
    ce.reason,
    ce.result,
    ce.status,
    ce.ts_created,
    ce.ts_updated,
    pr.result as proposal_last_result,
    pm.number_evaluations as proposal_number_evaluations,
    pm.ts_first_credit_evaluation_positive as ts_proposal_first_credit_evaluation_positive,
    pm.ts_last_credit_evaluation_positive as ts_proposal_last_credit_evaluation_positive
from datalake_docx_clean.credit_evaluation ce
left join proposal_metrics pm
    on pm.id_proposal = ce.id_proposal
left join proposal_result pr
    on pr.id_proposal = ce.id_proposal
    and pr.latest_proposal_credit_evaluation_rn = 1