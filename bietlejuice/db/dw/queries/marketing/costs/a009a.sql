/*
 Rateio de acordo com os prospects da última semana, vindos de afiliados que entraram no mês do prospect (new_users),
 com tracking_source facebook ou google e campanha não branded
 */
with
count_prospects as (
	select
		dd_p.week_start,
		dr.city_group,
		case when dua.tracking_campaign ~* '(branded)|(institucional)' and dua.tracking_campaign !~* '(non-branded)' then true
			else false end  as campaign_is_branded,
		count(case when dd_p.year_month = dd_aff.year_month then 1 end) new_user_prospects
	from
		fact_house_listing_flows f
		join dim_date dd_p
			on dd_p.sk_date =f.sk_prospect_date
		join dim_user du
			on f.sk_user_lead_affiliate = du.sk_user
		join dim_user_affiliate dua
			on dua.sk_user_affiliate = du.dados_afiliado_id
		join dim_date dd_aff
			on dd_aff.date=date(du.dadosafiliado_inicio_atuacao)
		join dim_region dr
			on f.sk_region = dr.sk_region
	where
		f.mkt_origin = 'Indica Aí - General'
		and dua.tracking_source ~* '(google)|(facebook)'
		and f.sk_prospect_date>=20190101
		and dr.city_group is not null
	group by 1,2,3
	having campaign_is_branded = false
),
dim_distinct as ( --incluir combinações semana/cidade sem resultado
	select distinct
	 	dd.sk_date,
	 	dd.week_start,
	 	dr.city_group
	from
	 	dim_date dd, dim_region dr
	where
		dd.sk_date>=20190101
	    and dd.date < current_date
),
temp as ( --Calculo do share por semana
	select distinct
	    ddt.week_start,
	    ddt.city_group,
	    (sum(t.new_user_prospects) over (PARTITION by ddt.week_start, ddt.city_group)::float
	    /
		sum(t.new_user_prospects) over (PARTITION by ddt.week_start)::float
	   	) as current_share
	from
		dim_distinct ddt
		left join count_prospects t
			on ddt.week_start = t.week_start
			and ddt.city_group = t.city_group
),
share as (--pegando o share da ultima semana
	select
		*,
		lead(current_share,1) over (partition by city_group order by week_start desc) as share
	from temp
)
select
	d.sk_date,
	d.city_group,
	coalesce(s.share,0) as share
from
	dim_distinct d
	join share s
		on d.week_start=s.week_start
		and d.city_group=s.city_group