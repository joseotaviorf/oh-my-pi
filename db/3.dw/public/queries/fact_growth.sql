create table fact_growth as
select
  sk_date,
	sk_week_start_date,
  'leads' as measure,
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
	yoy
from growth.leads

union all

select
	sk_date,
	sk_week_start_date,
	'prospects' as measure,
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
	yoy
from growth.prospects

union all

select
	sk_date,
	sk_week_start_date,
	'qualifieds' as measure,
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
	yoy
from growth.qualifieds

union all

select
	sk_date,
	sk_week_start_date,
	'opportunities' as measure,
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
	yoy
from growth.opportunities

union all

select
	sk_date,
	sk_week_start_date,
	'new_listings' as measure,
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
	yoy
from growth.new_listings

union all

select
	sk_date,
	sk_week_start_date,
	'tenant_prospects' as measure,
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
	yoy
from growth.tenant_prospects

union all

select
	sk_date,
	sk_week_start_date,
	'visitors' as measure,
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
	yoy
from growth.visitors

union all

select
	sk_date,
	sk_week_start_date,
	'offerers' as measure,
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
	yoy
from growth.offerers

union all

select
	sk_date,
	sk_week_start_date,
	'offerers_approved' as measure,
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
	yoy
from growth.offerers_approved

union all

select
	sk_date,
	sk_week_start_date,
	'offerers_sent_doc' as measure,
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
	yoy
from growth.offerers_sent_doc

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
	yoy
from growth.approved_by_insurer

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
	yoy
from growth.tenants

union all

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
	yoy
from growth.visits_booked

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
	yoy
from growth.visits_completed

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
	yoy
from growth.offers_submitted

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
	yoy
from growth.offers_approved

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
	yoy
from growth.documentation_sent

union all

select
	sk_date,
	sk_week_start_date,
	'ongoing_contracts' as measure,
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
	yoy
from growth.ongoing_contracts

union all

select
	sk_date,
	sk_week_start_date,
	'employees' as measure,
	team,
	_year,
	_month,
	_week,
	_day,
	null as region,
	null as city,
	0 as daily_count,
	prev_weekly_count,
	weekly_count,
	monthly_count,
	0 as yearly_count,
	0 as wow,
	mtd,
	ytd,
	0 as mom,
	0 as yoy
from growth.employees

union all

select
	sk_date,
	sk_week_start_date,
	'engaged_users' as measure,
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
	yoy
from growth.amplitude_engaged_users

union all

select
	sk_date,
	sk_week_start_date,
	'ticket_resolution' as measure,
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
	yoy
from growth.ticket_resolution

union all

select
	sk_date,
	sk_week_start_date,
	'tickets' as measure,
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
	yoy
from growth.tickets
;