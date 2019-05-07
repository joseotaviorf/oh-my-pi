select count(prd.*)
from zendesk.fact_ticket_metrics prd
join staging.zendesk_fact_ticket_metrics stg
    on stg.sk_ticket = prd.sk_ticket
where prd.ts_load = stg.ts_load
;