with
invoice_ as (
select
  date_trunc('month', date(substring(i.ts_due,1,10))) as due_month,
  c.id_external as id_contract,
  sum(i.due_amount) as due_amount,
  sum(case when i.status = 'paid' then i.paid_amount end) as paid_amount,
  sum(case when i.status = 'open' then i.due_amount end) as open_amount_month
from datalake_retsuko_clean_prod.invoice i
join datalake_retsuko_clean_prod.account a
  on a.id = i.id_account
inner join datalake_retsuko_clean_prod.contract c
  on c.id = i.id_contract
where a.type = 'tenant'
group by 1,2
), revenues as (
select
    due_month,
    id_contract,
    due_amount,
    paid_amount,
    open_amount_month,
    sum(open_amount_month) over(partition by id_contract order by due_month rows between 1 following and 1 following) as open_amount_cumsum
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
  on cast(r.id_contract as varchar) = rf.sk_contract
join datalake_clean.ods_dim_contract dc
  on cast(r.id_contract as varchar) = dc.sk_contract
order by 2,5