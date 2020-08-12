with
credit_evaluation_order as (
    select
        id_proposal,
        min(case when result in ('PRE_APPROVED', 'REGULAR') then ts_updated end) as ts_first_credit_evaluation_positive,
        max(case when result in ('PRE_APPROVED', 'REGULAR') then ts_updated end) as ts_last_credit_evaluation_positive,
        max(ts_updated) as ts_last_credit_evaluation_updated,
        max(ts_created) as ts_last_credit_evaluation_created,
        count(distinct id) as number_evaluations
    from datalake_docx_clean.credit_evaluation
    where status = 'FINISHED'
    group by 1
)
select
    ceo.id_proposal,
    ce.result as last_result,
    ceo.number_evaluations,
    ceo.ts_first_credit_evaluation_positive,
    ceo.ts_last_credit_evaluation_positive
from datalake_docx_clean.credit_evaluation ce
left join credit_evaluation_order ceo
    on ceo.id_proposal = ce.id_proposal
    and ceo.ts_last_credit_evaluation_updated = ce.ts_updated
    and ceo.ts_last_credit_evaluation_created = ce.ts_created
