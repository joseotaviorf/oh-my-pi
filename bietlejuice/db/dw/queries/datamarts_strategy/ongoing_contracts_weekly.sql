-- Define ongoing contracts weekly
-- Contracts that signed
-- Contracts of type DealOnly should only be considered in the first month as a ongoing contract

select
  dd.week_start,
  dr.sk_region,
  count(distinct dc.sk_contract) as ongoing_contracts_weekly
from dim_contract dc
join dim_date dd
  on dd.date between date(coalesce(coalesce(dc.ts_signature,dc.dt_start),dc.dt_entrance)) and (coalesce(dc.dt_annulment, CURRENT_DATE) - 1)
left join fact_listing_rent_flows rf
  on dc.sk_contract = rf.sk_contract
left join dim_region dr
  on rf.sk_region = dr.sk_region
where (dc.dt_annulment < current_date OR dc.dt_annulment is null) -- we know we may have future dates for dt_annulment
  and dc.status in ('Ativo','Finalizado') -- consider only contracts that are active or were active and ended
  and dd.weekday_name = 'Sunday'
group by 1, 2
order by 1 desc, 2