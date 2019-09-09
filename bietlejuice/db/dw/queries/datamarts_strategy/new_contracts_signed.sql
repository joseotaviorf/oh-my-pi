-- Define new_contracts_signed
-- Contracts that Signed
-- Contracts of type DealOnly are considered

select
  coalesce(dc.ts_signature, dc.dt_start) as contract_signed_date,
  date_trunc('week',coalesce(dc.ts_signature, dc.dt_start)) as contract_week_start,
  date_trunc('month',coalesce(dc.ts_signature, dc.dt_start)) as contract_month_start,
  rf.sk_region,
  count(distinct dc.sk_contract) as new_contracts_signed_daily,
  sum(count(distinct dc.sk_contract)) over(partition by date_trunc('week',coalesce(dc.ts_signature, dc.dt_start)), rf.sk_region) as new_contracts_signed_weekly,
  sum(count(distinct dc.sk_contract)) over(partition by date_trunc('month',coalesce(dc.ts_signature, dc.dt_start)), rf.sk_region) as new_contracts_signed_monthly
from dim_contract dc
left join public.fact_listing_rent_flows rf
  on dc.sk_contract = rf.sk_contract
  where dc.status in ('Ativo', 'Finalizado') -- consider only contracts that are active or were active and ended
group by 1, 2, 3, 4
order by 1 desc, 2, 3, 4
