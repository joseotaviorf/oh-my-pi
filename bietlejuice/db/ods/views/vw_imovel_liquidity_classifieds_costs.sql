drop view if exists vw_imovel_liquidity_classifieds_costs;
create or replace view vw_imovel_liquidity_classifieds_costs as
with costs as
(
  select
    "Date"::date as date,
	date_part('year',"Date") as year,
	date_part('month',"Date") as month,
    trim(REPLACE("Total",',',''))::decimal(14,4) as total,
    trim(REPLACE("Total",',',''))::decimal(14,4)
      / f_get_days_in_month("Date") as daily_cost
  from
    files.classified_costs c
  where
    "Date" is not null
),
published_listings as
(
  select distinct
  	i.status_date,
  	date_part('year', i.status_date) as year_status_date,
    date_part('month', i.status_date) as month_status_date,
    i.id,
    version
  from
  	imovel_status_full_history i
  inner join
	property_listing p
	on p.id = i.id
	and i.date between coalesce(p.min_version_time, '1900-01-01') and coalesce(p.max_version_time, now()) 
  where
    i.status_history = 'publicado'
    and i.last_position_date_flag
)
select
	c.year,
    c.month,
    p.status_date as listing_date,
    p.id,
    p.version,
    c.daily_cost,
    c.total,
    count(1) over (partition by p.status_date) as qt_listings_date,
    c.daily_cost / count(1) over (partition by p.status_date) as classified_cost
from
  costs c
inner join
  published_listings p
  on p.year_status_date = c.year
  and p.month_status_date = c.month
;

/*
select
    sum(classified_cost)
 from vw_imovel_liquidity_classifieds_costs
where
	year = 2016
group by
	id
*/
