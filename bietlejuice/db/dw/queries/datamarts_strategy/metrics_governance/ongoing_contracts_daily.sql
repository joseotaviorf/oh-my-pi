select
  dd.date,
  hl.sk_region,
  count(distinct dc.sk_contract) as ongoing_contracts_daily
from dim_contract dc
join dim_date dd
  on dd.date between date(coalesce(coalesce(dc.ts_signature,dc.dt_start),dc.dt_entrance)) and (coalesce(dc.dt_annulment, CURRENT_DATE) - 1)
left join fact_house_listings hl
  on dc.sk_contract = hl.sk_contract
where (dc.dt_annulment < current_date OR dc.dt_annulment is null) -- we know we may have future dates for dt_annulment
  and dc.status in ('Ativo','Finalizado') -- consider only contracts that are active or were active and ended
  and type <> 'DealOnly' -- this type of contract should only be considered for new contracts signed
group by 1, 2
order by 1 desc, 2