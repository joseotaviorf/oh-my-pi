insert into fact_growth
select
	sk_date,
	sk_week_start_date,
	'visits_booked' as measure,
	null as team,
	_year,
	_month,
	_week,
	_day,
	region,
	city,
	daily_count,
	prev_weekly_count,
	weekly_count,
	monthly_count,
	yearly_count,
	wow,
	mtd,
	ytd,
	mom,
	yoy,
	1 as flg_predicted
from growth.prediction_visits_booked

union all

select
	sk_date,
	sk_week_start_date,
	'visits_completed' as measure,
	null as team,
	_year,
	_month,
	_week,
	_day,
	region,
	city,
	daily_count,
	prev_weekly_count,
	weekly_count,
	monthly_count,
	yearly_count,
	wow,
	mtd,
	ytd,
	mom,
	yoy,
	1 as flg_predicted
from growth.prediction_visits_completed

union all

select
	sk_date,
	sk_week_start_date,
	'offers_submitted' as measure,
	null as team,
	_year,
	_month,
	_week,
	_day,
	region,
	city,
	daily_count,
	prev_weekly_count,
	weekly_count,
	monthly_count,
	yearly_count,
	wow,
	mtd,
	ytd,
	mom,
	yoy,
	1 as flg_predicted
from growth.prediction_offers_submitted

union all

select
	sk_date,
	sk_week_start_date,
	'offers_approved' as measure,
	null as team,
	_year,
	_month,
	_week,
	_day,
	region,
	city,
	daily_count,
	prev_weekly_count,
	weekly_count,
	monthly_count,
	yearly_count,
	wow,
	mtd,
	ytd,
	mom,
	yoy,
	1 as flg_predicted
from growth.prediction_offers_approved

union all

select
	sk_date,
	sk_week_start_date,
	'documentation_sent' as measure,
	null as team,
	_year,
	_month,
	_week,
	_day,
	region,
	city,
	daily_count,
	prev_weekly_count,
	weekly_count,
	monthly_count,
	yearly_count,
	wow,
	mtd,
	ytd,
	mom,
	yoy,
	1 as flg_predicted
from growth.prediction_documentation_sent

union all

select
	sk_date,
	sk_week_start_date,
	'approved_by_insurer' as measure,
	null as team,
	_year,
	_month,
	_week,
	_day,
	region,
	city,
	daily_count,
	prev_weekly_count,
	weekly_count,
	monthly_count,
	yearly_count,
	wow,
	mtd,
	ytd,
	mom,
	yoy,
	1 as flg_predicted
from growth.prediction_approved_by_insurer

union all

select
	sk_date,
	sk_week_start_date,
	'tenants' as measure,
	null as team,
	_year,
	_month,
	_week,
	_day,
	region,
	city,
	daily_count,
	prev_weekly_count,
	weekly_count,
	monthly_count,
	yearly_count,
	wow,
	mtd,
	ytd,
	mom,
	yoy,
	1 as flg_predicted
from growth.prediction_tenants
;