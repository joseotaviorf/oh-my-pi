create table fact_growth as
select
  sk_date,
	sk_week_start_date,
  'leads' as measure,
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
from growth.leads_all

union all

select
	sk_date,
	sk_week_start_date,
	'prospects' as measure,
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
from growth.prospects_all

union all

select
	sk_date,
	sk_week_start_date,
	'qualifieds' as measure,
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
from growth.qualifieds_all

union all

select
	sk_date,
	sk_week_start_date,
	'opportunities' as measure,
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
from growth.opportunities_all

union all

select
	sk_date,
	sk_week_start_date,
	'new_listings' as measure,
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
from growth.new_listings_all

union all

select
	sk_date,
	sk_week_start_date,
	'tenant_prospects' as measure,
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
from growth.tenant_prospects_all

union all

select
	sk_date,
	sk_week_start_date,
	'visitors' as measure,
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
from growth.visitors_all

union all

select
	sk_date,
	sk_week_start_date,
	'offerers' as measure,
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
from growth.offerers_all

union all

select
	sk_date,
	sk_week_start_date,
	'offerers_approved' as measure,
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
from growth.offerers_approved_all

union all

select
	sk_date,
	sk_week_start_date,
	'offerers_sent_doc' as measure,
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
from growth.offerers_sent_doc_all

union all

select
	sk_date,
	sk_week_start_date,
	'approved_by_insurer' as measure,
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
from growth.approved_by_insurer_all

union all

select
	sk_date,
	sk_week_start_date,
	'tenants' as measure,
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
from growth.tenants_all

union all

select
	sk_date,
	sk_week_start_date,
	'visits_booked' as measure,
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
from growth.visits_booked_all

union all

select
	sk_date,
	sk_week_start_date,
	'visits_completed' as measure,
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
from growth.visits_completed_all

union all

select
	sk_date,
	sk_week_start_date,
	'offers_submitted' as measure,
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
from growth.offers_submitted_all

union all

select
	sk_date,
	sk_week_start_date,
	'offers_approved' as measure,
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
from growth.offers_approved_all

union all

select
	sk_date,
	sk_week_start_date,
	'documentation_sent' as measure,
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
from growth.documentation_sent_all

union all

select
	sk_date,
	sk_week_start_date,
	'ongoing_contracts' as measure,
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
from growth.ongoing_contracts_all