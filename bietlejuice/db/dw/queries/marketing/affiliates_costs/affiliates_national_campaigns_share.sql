with affiliates as (
    select distinct
        dua.sk_user_affiliate,
        du.sk_user,
        dua.tracking_source
    from
        dim_user_affiliate dua
    join
        dim_user du
    on du.dados_afiliado_id = dua.sk_user_affiliate
    where
        tracking_source in ('google', 'facebook')
),
t_row_count as (
    select
        cast(replace(dd.year_month, '/', '') as integer) as year_month,
        tracking_source,
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
        dd.year_month = to_char(cast('{execution_date}' as date), 'YYYY/MM')
        and affiliate_type = 'Standard'
        and city_group is not null
    group by 1,2,3
)
select
	year_month,
	tracking_source,
	city_group,
	TRUNC(
		row_count::numeric(10,4)
		/
		sum(row_count) over (partition by year_month, tracking_source)::numeric(10,4)
	, 4) as share
from t_row_count