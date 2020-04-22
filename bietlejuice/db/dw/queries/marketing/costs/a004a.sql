/*Share de custos com base na quantidade de prospects gerados no mes anterior com source = facebook
 Baseado na query em bi-etl-ejuice/bietlejuice/db/dw/queries/marketing/affiliates_costs/affiliates_national_campaigns_share.sql */

with affiliates as ( --Afiliado por source= facebook
    select distinct
        dua.sk_user_affiliate,
        du.sk_user
    from
        dim_user_affiliate dua
    join
        dim_user du
    on du.dados_afiliado_id = dua.sk_user_affiliate
    where
        tracking_source in ('facebook')
),
t_row_count as ( --contagem de prospects
    select
        dd.sk_date,
        cast(replace(dd.year_month, '/', '') as integer) as year_month,
        cast(to_char(dd.last_month, 'YYYYMM') as integer) as last_year_month,
        dr.city_group,
        count(1) as row_count
    from
        fact_house_listing_flows fhlf
    join affiliates af
        on af.sk_user = fhlf.sk_user_lead_affiliate
    join dim_region dr
        on dr.sk_region = fhlf.sk_region
    join dim_date dd
        on dd.sk_date = fhlf.sk_prospect_date
    where
        affiliate_type = 'Standard'
        and city_group is not null
    group by 1,2,3,4
),
temp as ( --Calculo do share por mes
	select distinct
	    year_month,
	    last_year_month,
	    city_group,
	    (sum(row_count) over (PARTITION by year_month, city_group)::float
	    /
		sum(row_count) over (PARTITION by year_month)::float
	   	) as current_share
	from t_row_count
	where sk_date>=20190101
),
share as (
	select
		*,
		lead(current_share,1) over (partition by city_group order by year_month desc) as share --pegando o share do ultimo mês
	from temp
),
dim_distinct as (
	select distinct
	 	dd.sk_date,
	 	cast(replace(dd.year_month, '/', '') as integer) as year_month,
	 	dr.city_group
	from
	 	dim_date dd, dim_region dr
)
select
	d.sk_date,
	d.city_group,
	coalesce(s.share,0) as share
from
	dim_distinct d
	join share s
		on d.year_month=s.year_month
		and d.city_group=s.city_group
