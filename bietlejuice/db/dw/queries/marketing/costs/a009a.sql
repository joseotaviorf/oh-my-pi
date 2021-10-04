/*
 Rateio de acordo com os prospects da última semana, vindos de afiliados que entraram no mês do prospect (new_users),
 com tracking_source facebook ou google e campanha não branded
 */
with total_prospects as (
    with rent_prospects as(
        select
            f.sk_prospect_date,
            f.mkt_origin,
            f.sk_user_lead_affiliate,
            f.sk_region,
            f.sk_house_listing_flow
        from
            fact_house_listing_flows f
        left join sale.fact_listing_flows sf
            on f.sk_house_listing_flow = sf.sk_house_listing_flow
            and f.sk_prospect_date = sf.sk_prospect_date
        where f.sk_prospect_date>0
        and sf.sk_house_listing is null
    ),
    sale_prospects as(
        select
            sf.sk_prospect_date,
            sf.mkt_origin,
            sf.sk_user_lead_affiliate,
            sf.sk_region,
            sf.sk_house_listing_flow
        from
            sale.fact_listing_flows sf
        left join fact_house_listing_flows f
            on f.sk_house_listing_flow = sf.sk_house_listing_flow
            and f.sk_prospect_date = sf.sk_prospect_date
        where sf.sk_prospect_date>=20211001 --A regra passa a considerar prospects de ForSale apenas a partir de Out-2021
        and f.sk_house_listing is null
    ),
    hybrid_prospects as(
        select
            f.sk_prospect_date,
            f.mkt_origin,
            f.sk_user_lead_affiliate,
            f.sk_region,
            f.sk_house_listing_flow
        from
            fact_house_listing_flows f
        left join sale.fact_listing_flows sf
            on f.sk_house_listing_flow = sf.sk_house_listing_flow
            and f.sk_prospect_date = sf.sk_prospect_date
        where f.sk_prospect_date>0
        and sf.sk_house_listing is not null
    )
    select * from rent_prospects
    union all
    select * from sale_prospects
    union all
    select * from hybrid_prospects
),
count_prospects as (
	select
		dd_p.week_start,
		dr.city_group,
		case when dua.tracking_campaign ~* '(branded)|(institucional)' and dua.tracking_campaign !~* '(non-branded)' then true
			else false end  as campaign_is_branded,
		count(case when dd_p.year_month = dd_aff.year_month then 1 end) new_user_prospects
	from
		total_prospects  t
		join dim_date dd_p
			on dd_p.sk_date = t.sk_prospect_date
		join dim_user du
			on t.sk_user_lead_affiliate = du.sk_user
		join dim_user_affiliate dua
			on dua.sk_user_affiliate = du.dados_afiliado_id
		join dim_date dd_aff
			on dd_aff.date=date(du.dadosafiliado_inicio_atuacao)
		join dim_region dr
			on t.sk_region = dr.sk_region
	where
		t.mkt_origin = 'Indica Aí - General'
		and dua.tracking_source ~* '(google)|(facebook)'
		and t.sk_prospect_date>=20190101
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