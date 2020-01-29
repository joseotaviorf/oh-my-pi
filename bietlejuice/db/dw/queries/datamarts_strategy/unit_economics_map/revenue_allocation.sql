with
invoice_ as (
select
  date_trunc('month', date(substring(i.due_date,1,10))) as due_month,
  c.external_id as contract_id,
  sum(i.due_amount) as due_amount,
  sum(case when i.status = 'paid' then i.paid_amount end) as paid_amount,
  sum(case when i.status = 'open' then i.due_amount end) as open_amount_month
from datalake_retsuko_raw_prod.invoice i
join datalake_retsuko_raw_prod.account a
  on a.id = i.account_id
inner join datalake_retsuko_raw_prod.contract c
  on c.id = i.contract_id
where a.type = 'tenant'
group by 1,2
), revenues as (
select
    due_month,
    contract_id,
    due_amount,
    paid_amount,
    open_amount_month,
    sum(open_amount_month) over(partition by contract_id order by due_month) as open_amount_cumsum
from invoice_
where due_month < current_date
group by 1,2,3,4,5
)
select
    rf.sk_house_listing,
    dc.sk_contract,
    dc.dt_start,
    dc.ts_signature,
    r.due_month,
    r.due_amount,
    r.paid_amount,
    r.open_amount_month,
    r.open_amount_cumsum
from revenues r
join datalake_clean.ods_fact_listing_rent_flows rf
  on cast(r.contract_id as varchar) = rf.sk_contract
join datalake_clean.ods_dim_contract dc
  on cast(r.contract_id as varchar) = dc.sk_contract
order by 2,5
