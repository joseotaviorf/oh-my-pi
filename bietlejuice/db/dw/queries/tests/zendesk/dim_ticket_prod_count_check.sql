select count(prd.*)
from zendesk.dim_ticket prd
join staging.zendesk_dim_ticket stg
    on stg.sk_ticket = prd.sk_ticket
where prd.ts_load = stg.ts_load
;