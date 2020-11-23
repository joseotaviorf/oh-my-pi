with share_local_holidays_by_city_group as (
with holidays_by_city_name as (
	select distinct
		dd.date,
		dd.week_start,
		coalesce(hs.weekday_name, dd.weekday_name) as weekday_name,
		coalesce(nullif(lh.city_group, ''), dr.city_group) as city_group,
		coalesce(nullif(lh.city_name, ''), dr.city_name) as city_name,
		coalesce(max(cast(replace(cs.share,',','') as float)), 0) as share_city_name,
		case when dd.is_brz_holiday = 'Holiday' or nullif(lh.city_group, '') is not null then cast(replace(hs.prospect,',','') as float)
			 else null end as prospect_share_holiday,
		case when dd.is_brz_holiday = 'Holiday' or nullif(lh.city_group, '') is not null then cast(replace(hs.qualified,',','') as float)
			 else null end as qualified_share_holiday,
		case when dd.is_brz_holiday = 'Holiday' or nullif(lh.city_group, '') is not null then cast(replace(hs.opportunity,',','') as float)
			 else null end as opportunity_share_holiday,
		case when dd.is_brz_holiday = 'Holiday' or nullif(lh.city_group, '') is not null then cast(replace(hs.first_listings,',','') as float)
			 else null end as first_listings_share_holiday
	from dim_date dd
	cross join dim_region dr
	left join datalake_raw.gsheets_local_holidays lh
	  on dd.date = cast(replace(lh.date,'-','') as date) and (lh.short_region_name = dr.short_region_name or lh.city_group = dr.city_group)  
	left join datalake_raw.gsheets_city_share cs
	  on coalesce(nullif(lh.city_name, ''), dr.city_name) = nullif(cs.city_name, '')
	left join datalake_raw.gsheets_weekday_holiday_share hs
	  on hs.weekday_name = dd.weekday_name 
	where dd.date between '2018-12-31' and current_date + interval '6 months'
	group by dd.date,
		dd.week_start,
		lh.city_group,
		dr.city_group,
		lh.city_name,
		dr.city_name,
		hs.weekday_name,
		dd.weekday_name,
		dd.is_brz_holiday,
		hs.prospect,
		hs.qualified,
		hs.opportunity,
		hs.first_listings
	)
	SELECT 
		date,
		week_start,
		weekday_name,
		city_group,
		sum(share_city_name * coalesce(prospect_share_holiday,1)) as share_holiday_prospect,
		sum(share_city_name * coalesce(qualified_share_holiday,1)) as share_holiday_qualified,
		sum(share_city_name * coalesce(opportunity_share_holiday,1)) as share_holiday_opportunity,
		sum(share_city_name * coalesce(first_listings_share_holiday,1)) as share_holiday_first_listings
	from holidays_by_city_name
	where city_group is not null
	group by 1, 2, 3, 4
 ), final_shares as (
select distinct
	lhc.date,
	lhc.week_start,
	wscs.city_group,
	wscs.mkt_channel,
	wscs.lead_context,
	cast(replace(wscs.prospect,',','') as float) as final_share_wo_holiday_prospect,
	cast(replace(wscs.prospect,',','') as float) * lhc.share_holiday_prospect as final_share_prospect,
	cast(replace(wscs.qualified,',','') as float) as final_share_wo_holiday_qualified,
	cast(replace(wscs.qualified,',','') as float) * lhc.share_holiday_qualified as final_share_qualified,
	cast(replace(wscs.opportunity,',','') as float) as final_share_wo_holiday_opportunity,
	cast(replace(wscs.opportunity,',','') as float) * lhc.share_holiday_opportunity as final_share_opportunity,
	cast(replace(wscs.first_listing,',','') as float) as final_share_wo_holiday_first_listings,
	cast(replace(wscs.first_listing,',','') as float) * lhc.share_holiday_first_listings as final_share_first_listings
from share_local_holidays_by_city_group lhc
left join datalake_raw.gsheets_weekday_supply_channel_share wscs
  on wscs.weekday = lhc.weekday_name and wscs.city_group = lhc.city_group 
), diff_w_and_wo_holiday_share as (
select
	fsh.date,
	fsh.week_start,
	fsh.city_group,
	fsh.mkt_channel,
	gwvs.mkt_origin,
	fsh.lead_context,
	sum(fsh.final_share_prospect * cast(replace(gwvs.prospect,',','') as float)) as prospect_1,
	sum(fsh.final_share_prospect * cast(replace(gwvs.prospect,',','') as float)) over(partition by fsh.week_start, fsh.city_group, fsh.mkt_channel, gwvs.mkt_origin, fsh.lead_context) as total_prospect_daily,
	sum(fsh.final_share_wo_holiday_prospect * cast(replace(gwvs.prospect,',','') as float)) over(partition by fsh.week_start, fsh.city_group, fsh.mkt_channel, gwvs.mkt_origin, fsh.lead_context) as total_prospect_daily_wo_holiday,
	sum(fsh.final_share_qualified * cast(replace(gwvs.qualified,',','') as float)) as qualified_1,
	sum(fsh.final_share_qualified * cast(replace(gwvs.qualified,',','') as float)) over(partition by fsh.week_start, fsh.city_group, fsh.mkt_channel, gwvs.mkt_origin, fsh.lead_context) as total_qualified_daily,
	sum(fsh.final_share_wo_holiday_qualified * cast(replace(gwvs.qualified,',','') as float)) over(partition by fsh.week_start, fsh.city_group, fsh.mkt_channel, gwvs.mkt_origin, fsh.lead_context) as total_qualified_daily_wo_holiday,
	sum(fsh.final_share_opportunity * cast(replace(gwvs.opportunity,',','') as float)) as opportunity_1,
	sum(fsh.final_share_opportunity * cast(replace(gwvs.opportunity,',','') as float)) over(partition by fsh.week_start, fsh.city_group, fsh.mkt_channel, gwvs.mkt_origin, fsh.lead_context) as total_opportunity_daily,
	sum(fsh.final_share_wo_holiday_opportunity * cast(replace(gwvs.opportunity,',','') as float)) over(partition by fsh.week_start, fsh.city_group, fsh.mkt_channel, gwvs.mkt_origin, fsh.lead_context) as total_opportunity_daily_wo_holiday,
	sum(fsh.final_share_first_listings * cast(replace(gwvs.first_listing,',','') as float)) as first_listing_1,
	sum(fsh.final_share_first_listings * cast(replace(gwvs.first_listing,',','') as float)) over(partition by fsh.week_start, fsh.city_group, fsh.mkt_channel, gwvs.mkt_origin, fsh.lead_context) as total_first_listing_daily,
	sum(fsh.final_share_wo_holiday_first_listings * cast(replace(gwvs.first_listing,',','') as float)) over(partition by fsh.week_start, fsh.city_group, fsh.mkt_channel, gwvs.mkt_origin, fsh.lead_context) as total_first_listing_daily_wo_holiday
from final_shares fsh
join datalake_raw.gsheets_week_volumes_supply gwvs
  on fsh.mkt_channel = gwvs.mkt_channel
  	and fsh.lead_context = gwvs.lead_context
  	and fsh.week_start = gwvs.week_start
  	and fsh.city_group = gwvs.city_group
group by 1,2,3,4,5,6,
	fsh.final_share_prospect,
	gwvs.prospect,
	fsh.final_share_wo_holiday_prospect,
	fsh.final_share_qualified,
	gwvs.qualified,
	fsh.final_share_wo_holiday_qualified,
	fsh.final_share_opportunity,
	gwvs.opportunity,
	fsh.final_share_wo_holiday_opportunity,
	fsh.final_share_first_listings,
	gwvs.first_listing,
	fsh.final_share_wo_holiday_first_listings
), daily_target_shares as (
SELECT 
	date,
	week_start,
	city_group,
	mkt_channel,
	mkt_origin,
	lead_context,
	prospect_1 + case when total_prospect_daily > 0 then (total_prospect_daily_wo_holiday - total_prospect_daily) * prospect_1 / total_prospect_daily else 0 end as prospect,
	qualified_1 + case when total_qualified_daily > 0 then (total_qualified_daily_wo_holiday - total_qualified_daily) * qualified_1 / total_qualified_daily else 0 end as qualified,
	opportunity_1 + case when total_opportunity_daily > 0 then (total_opportunity_daily_wo_holiday - total_opportunity_daily) * opportunity_1 / total_opportunity_daily else 0 end as opportunity,
	first_listing_1 + case when total_first_listing_daily > 0 then (total_first_listing_daily_wo_holiday - total_first_listing_daily) * first_listing_1 / total_first_listing_daily else 0 end as first_listing
from diff_w_and_wo_holiday_share 
), gsheets_supply_target_adjusted as (
WITH
supply_targets AS (
	SELECT * FROM datalake_raw.gsheets_supply_targets_2021 
    UNION ALL
    	SELECT * FROM datalake_raw.gsheets_supply_targets_2020 
    UNION ALL
        SELECT * FROM datalake_raw.gsheets_supply_targets_2019
)
SELECT
  	cast(replace(date,'-','') as date) as date,
	cast(replace(week_start,'-','') as date) as week_start,
	nullif(city_group, '') as city_group,
	nullif(supply_channel, '') as mkt_channel,
	nullif(supply_origin, '') as mkt_origin,
	nullif(lead_context, '') as lead_context,
	cast(replace(prospects,',','') as float) as prospect,
	cast(replace(qualifieds,',','') as float) as qualified,
	cast(replace(opportunities,',','') as float) as opportunity,
	cast(replace(first_listings,',','') as float) as first_listing
FROM supply_targets
where date_trunc('month', cast(replace(date,'-','') as date)) <= date_trunc('month', current_date)
), past_targets as (
select
	week_start,
	city_group,
	mkt_channel,
	mkt_origin,
	lead_context,
	sum(prospect) as pp_congelado,
	sum(qualified) as ql_congelado,
	sum(opportunity) as op_congelado,
	sum(first_listing) as fl_congelado
from gsheets_supply_target_adjusted
group by 1,2,3,4,5
), calculated_targets as (
select
	week_start,
	city_group,
	mkt_channel,
	mkt_origin,
	lead_context,
	sum(prospect) as pp_calculado,
	sum(qualified) as ql_calculado,
	sum(opportunity) as op_calculado,
	sum(first_listing) as fl_calculado
from daily_target_shares
group by 1,2,3,4,5
), targets_diff as (
select
	ct.week_start,
	ct.city_group,
	ct.mkt_channel,
	ct.mkt_origin,
	ct.lead_context,
	coalesce(ct.pp_calculado,0) - coalesce(pt.pp_congelado,0) as diff_pp,
	coalesce(ct.ql_calculado,0) - coalesce(pt.ql_congelado,0) as diff_ql,
	coalesce(ct.op_calculado,0) - coalesce(pt.op_congelado,0) as diff_op,
	coalesce(ct.fl_calculado,0) - coalesce(pt.fl_congelado,0) as diff_fl
from calculated_targets ct
left join past_targets pt
  on ct.week_start = pt.week_start
    and ct.city_group = pt.city_group
	and ct.mkt_channel = pt.mkt_channel
	and ct.mkt_origin = pt.mkt_origin
	and ct.lead_context = pt.lead_context
), calculated_targets_week_month as (
SELECT
	date,
	week_start,
	city_group,
	mkt_channel,
	mkt_origin,
	lead_context,
	sum(prospect) as pp_calculado,
	sum(case when date_trunc('month', date) >= date_trunc('month', current_date) then prospect else 0 end) over(partition by week_start, city_group, mkt_channel, mkt_origin, lead_context) as pp_total_week,
	sum(qualified) as ql_calculado,
	sum(case when date_trunc('month', date) >= date_trunc('month', current_date) then qualified else 0 end) over(partition by week_start, city_group, mkt_channel, mkt_origin, lead_context) as ql_total_week,
	sum(opportunity) as op_calculado,
	sum(case when date_trunc('month', date) >= date_trunc('month', current_date) then opportunity else 0 end) over(partition by week_start, city_group, mkt_channel, mkt_origin, lead_context) as op_total_week,
	sum(first_listing) as fl_calculado,
	sum(case when date_trunc('month', date) >= date_trunc('month', current_date) then first_listing else 0 end) over(partition by week_start, city_group, mkt_channel, mkt_origin, lead_context) as fl_total_week
from daily_target_shares
group by 1, 2, 3, 4, 5, 6, prospect, qualified, opportunity, first_listing
), daily_target_shares_adjusted as (
select distinct
	coalesce(g.date, d.date) as date,
	coalesce(g.week_start, d.week_start) as week_start,
	coalesce(g.city_group, d.city_group) as city_group,
	coalesce(g.mkt_channel, d.mkt_channel) as mkt_channel,
	coalesce(g.mkt_origin, d.mkt_origin) as mkt_origin,
	coalesce(g.lead_context, d.lead_context) as lead_context,
	case when date_trunc('month', coalesce(g.date, d.date)) <= date_trunc('month', current_date) then g.prospect
			when date_trunc('month', coalesce(g.date, d.date)) > date_trunc('month', current_date) and wm.pp_total_week != 0 and td.diff_pp != 0 then td.diff_pp * coalesce(wm.pp_calculado,0)/wm.pp_total_week::float
			when date_trunc('month', coalesce(g.date, d.date)) > date_trunc('month', current_date) and wm.pp_total_week = 0 and td.diff_pp != 0 then td.diff_pp
			else d.prospect end as prospect,
	case when date_trunc('month', coalesce(g.date, d.date)) <= date_trunc('month', current_date) then g.qualified
			when date_trunc('month', coalesce(g.date, d.date)) > date_trunc('month', current_date) and wm.ql_total_week != 0 and td.diff_ql != 0 then td.diff_ql * coalesce(wm.ql_calculado,0)/wm.ql_total_week::float
			when date_trunc('month', coalesce(g.date, d.date)) > date_trunc('month', current_date) and wm.ql_total_week = 0 and td.diff_ql != 0 then td.diff_ql
			else d.qualified end as qualified,
	case when date_trunc('month', coalesce(g.date, d.date)) <= date_trunc('month', current_date) then g.opportunity
			when date_trunc('month', coalesce(g.date, d.date)) > date_trunc('month', current_date) and wm.op_total_week != 0 and td.diff_op != 0 then td.diff_op * coalesce(wm.op_calculado,0)/wm.op_total_week::float
			when date_trunc('month', coalesce(g.date, d.date)) > date_trunc('month', current_date) and wm.op_total_week = 0 and td.diff_op != 0 then td.diff_op
			else d.opportunity end as opportunity,
	case when date_trunc('month', coalesce(g.date, d.date)) <= date_trunc('month', current_date) then g.first_listing
			when date_trunc('month', coalesce(g.date, d.date)) > date_trunc('month', current_date) and wm.fl_total_week != 0 and td.diff_fl != 0 then td.diff_fl * coalesce(wm.fl_calculado,0)/wm.fl_total_week::float
			when date_trunc('month', coalesce(g.date, d.date)) > date_trunc('month', current_date) and wm.fl_total_week = 0 and td.diff_fl != 0 then td.diff_fl
			else d.first_listing end as first_listing
from daily_target_shares d
full outer join gsheets_supply_target_adjusted g
  on d.date = g.date
	and d.week_start = g.week_start
	and d.city_group = g.city_group
	and d.mkt_channel = g.mkt_channel
	and d.mkt_origin = g.mkt_origin
	and d.lead_context = g.lead_context
left join targets_diff td
  on td.week_start = d.week_start
    and d.city_group = td.city_group
	and d.mkt_channel = td.mkt_channel
	and d.mkt_origin = td.mkt_origin
	and d.lead_context = td.lead_context
left join calculated_targets_week_month wm
  on wm.date = d.date
    and wm.week_start = d.week_start
    and wm.city_group = d.city_group
    and wm.mkt_channel = d.mkt_channel
    and wm.mkt_origin = d.mkt_origin
    and wm.lead_context = d.lead_context
), negative_targets as (
select
	date,
	sum(case when prospect < 0 then prospect end) as pp_negative,
	sum(case when qualified < 0 then qualified end) as ql_negative,
	sum(case when opportunity < 0 then opportunity end) as op_negative,
	sum(case when first_listing < 0 then first_listing end) as fl_negative
from daily_target_shares_adjusted
group by 1
)
select
	dt.date,
	week_start,
	city_group,
	mkt_channel as supply_channel,
	mkt_origin as supply_origin,
	lead_context,
	case when prospect <= 0 then 0 else prospect + coalesce(nt.pp_negative,0) * prospect/(sum(case when prospect > 0 then prospect end) over(partition by dt.date)) end as prospect,
	case when qualified <= 0 then 0 else qualified + coalesce(nt.ql_negative,0) * qualified/(sum(case when qualified > 0 then qualified end) over(partition by dt.date)) end as qualified,
	case when opportunity <= 0 then 0 else opportunity + coalesce(nt.op_negative,0) * opportunity/(sum(case when opportunity > 0 then opportunity end) over(partition by dt.date)) end as opportunity,
	case when first_listing <= 0 then 0 else first_listing + coalesce(nt.fl_negative,0) * first_listing/(sum(case when first_listing > 0 then first_listing end) over(partition by dt.date)) end as first_listing
from daily_target_shares_adjusted dt
join negative_targets nt
  on dt.date = nt.date;