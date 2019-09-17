with
end_dates as (
select
    c_aud.id as contract_id,
    c_aud.imovel_id,
    c_aud.rev,
	cast(regexp_substr(c_aud.datarescisao, '\\d{4}-\\d{2}-\\d{2}') as date) as datarescisao,
	lag(regexp_substr(c_aud.datarescisao, '\\d{4}-\\d{2}-\\d{2}')) over(partition by c_aud.id order by c_aud.rev) as previous_datarescisao,
    from_unixtime(cast(u.timestamp as bigint)/1000) as ts_analista,
    c_aud.datarescisao_mod
from datalake_ebdb_raw_prod.contrato_aud c_aud
join datalake_ebdb_raw_prod.usuariorevisionentity u
  on c_aud.rev = u.id
order by 1,2
),
end_dates_changes as (
select
	ed.contract_id,
	ed.imovel_id,
    ed.rev,
    row_number() over(partition by ed.contract_id order by ed.ts_analista desc) as rn,
    count(ed.rev) over(partition by ed.contract_id) as count_changes,
	ed.datarescisao,
    ed.ts_analista,
    ed.datarescisao_mod,
    datediff('day', ed.datarescisao , ed.ts_analista) as diff_annulment_analyst
from end_dates as ed
where (ed.datarescisao <> ed.previous_datarescisao or (ed.datarescisao is not null and ed.previous_datarescisao is null))
)
select
	edc.datarescisao as dt_annulment,
	coalesce(dr.sk_region, -1) as sk_region,
	count(distinct case when edc.diff_annulment_analyst <= 3 then edc.contract_id end) as ended_rentals_until_3d,
	count(distinct case when edc.diff_annulment_analyst > 3 then edc.contract_id end) as ended_rentals_over_3d
from end_dates_changes edc
left join fact_house_listings fhl
  on edc.contract_id = fhl.sk_contract
left join dim_region dr
  on fhl.sk_region = dr.sk_region
where rn = 1
group by 1, 2

