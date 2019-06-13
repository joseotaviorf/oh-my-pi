with daily as (
select
	date,
	replace(dau.date,'-','')::bigint as sk_date,
	coalesce(dr.city_group, 'Not Mapped') as city_group,
	coalesce(city, 'Not Mapped') as city,
	mkt_category,
	mkt_flow,
	mkt_completion,
	mkt_origin,
	mkt_channel,
	mkt_medium,
	mkt_source,
	mkt_platform,
	utm_campaign,
	utm_content,
	utm_term,
	count(id_amplitude) as daily_count
from datalake_clean.amplitude_daily_active_users dau
left join datalake_clean.ods_dim_region dr
    on dau.city = dr.name
    and level = 'Cidade'
where app = 'supply'
group by 1,2,3,4,5,6,7,8,9,10,11,12,13,14,15
), weekly as (
select
	date,
	replace(dau.date,'-','')::bigint as sk_date,
	coalesce(dr.city_group, 'Not Mapped') as city_group,
	coalesce(city, 'Not Mapped') as city,
	mkt_category,
	mkt_flow,
	mkt_completion,
	mkt_origin,
	mkt_channel,
	mkt_medium,
	mkt_source,
	mkt_platform,
	utm_campaign,
	utm_content,
	utm_term,
	count(id_amplitude) as weekly_count
from datalake_clean.amplitude_weekly_active_users dau
left join datalake_clean.ods_dim_region dr
    on dau.city = dr.name
    and level = 'Cidade'
where app = 'supply'
group by 1,2,3,4,5,6,7,8,9,10,11,12,13,14,15
), monthly as (
select
	date,
	replace(dau.date,'-','')::bigint as sk_date,
	coalesce(dr.city_group, 'Not Mapped') as city_group,
	coalesce(city, 'Not Mapped') as city,
	mkt_category,
	mkt_flow,
	mkt_completion,
	mkt_origin,
	mkt_channel,
	mkt_medium,
	mkt_source,
	mkt_platform,
	utm_campaign,
	utm_content,
	utm_term,
	count(id_amplitude) as monthly_count
from datalake_clean.amplitude_monthly_active_users dau
left join datalake_clean.ods_dim_region dr
    on dau.city = dr.name
    and level = 'Cidade'
where app = 'supply'
group by 1,2,3,4,5,6,7,8,9,10,11,12,13,14,15
),
dim_date as (
SELECT
	sk_date,
	replace(dd.week_start,'-','')::bigint as sk_week_start,
	replace(dd.month_start,'-','')::bigint as sk_month_start
from
	datalake_clean.ods_dim_date dd
WHERE sk_date > 20180101
), t_union as (
    select
        daily.*,
        weekly.weekly_count,
        monthly.monthly_count,
        0 as yearly_count
    from daily
    join dim_date dd
    	on daily.sk_date = dd.sk_date
    left join weekly
        on  dd.sk_week_start = weekly.sk_date and
            daily.city = weekly.city and
            daily.mkt_category = weekly.mkt_category and
            daily.mkt_flow = weekly.mkt_flow and
            daily.mkt_completion = weekly.mkt_completion and
            daily.mkt_channel = weekly.mkt_channel and
            daily.mkt_medium = weekly.mkt_medium and
            daily.mkt_source = weekly.mkt_source and
            daily.mkt_platform = weekly.mkt_platform and
            coalesce(daily.utm_campaign, '') = coalesce(weekly.utm_campaign, '') and
            coalesce(daily.utm_content, '') = coalesce(weekly.utm_content, '') and
            coalesce(daily.utm_term, '') = coalesce(weekly.utm_term, '')
    left join monthly
        on  dd.sk_month_start = monthly.sk_date and
            daily.city = monthly.city and
            daily.mkt_category = monthly.mkt_category and
            daily.mkt_flow = monthly.mkt_flow and
            daily.mkt_completion = monthly.mkt_completion and
            daily.mkt_channel = monthly.mkt_channel and
            daily.mkt_medium = monthly.mkt_medium and
            daily.mkt_source = monthly.mkt_source and
            daily.mkt_platform = monthly.mkt_platform and
            coalesce(daily.utm_campaign, '') = coalesce(monthly.utm_campaign, '') and
            coalesce(daily.utm_content, '') = coalesce(monthly.utm_content, '') and
            coalesce(daily.utm_term, '') = coalesce(monthly.utm_term, '')
),
all_dates as (
  select distinct
    date_part('year', to_date(tu.date::varchar, 'YYYY-MM-DD')) as _year,
    date_part('month', to_date(tu.date::varchar, 'YYYY-MM-DD')) as _month,
    date_part('week', to_date(tu.date::varchar, 'YYYY-MM-DD')) as _week,
    date_part('day', to_date(tu.date::varchar, 'YYYY-MM-DD')) as _day,
    city_group as city_group,
    city as city,
    mkt_category,
	mkt_flow,
	mkt_completion,
	mkt_origin,
	mkt_channel,
	mkt_medium,
	mkt_source,
	mkt_platform,
	utm_campaign,
	utm_content,
	utm_term,
	daily_count,
	weekly_count,
	monthly_count,
	yearly_count
	from t_union tu
	where tu.sk_date::bigint
	    between 20180101 and to_char(current_date - 1, 'YYYYMMDD')::integer
  order by 1, 2, 3, 4
),