truncate fact_growth;
insert into fact_growth (
	select
		sk_date,
	  sk_week_start_date,
	  'lead' as funnel_step,
	  region,
	  city,
	  _year,
	  _month,
	  _week,
		count_prev_week,
		_count,
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
	  'prospect' as funnel_step,
	  region,
	  city,
	  _year,
	  _month,
	  _week,
		count_prev_week,
		_count,
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
	  'qualified' as funnel_step,
	  region,
	  city,
	  _year,
	  _month,
	  _week,
		count_prev_week,
		_count,
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
	  'opportunity' as funnel_step,
	  region,
	  city,
	  _year,
	  _month,
	  _week,
		count_prev_week,
		_count,
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
	  cast('new_listing' as varchar) as funnel_step,
	  cast(region as varchar),
	  cast(city as varchar),
	  _year,
	  _month,
	  _week,
		count_prev_week,
		_count,
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
		'tenant_prospects' as funnel_step,
		region,
		city,
		_year,
	  _month,
	  _week,
		count_prev_week,
		_count,
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
	  'visitors' as funnel_step,
	  region,
	  city,
	  _year,
	  _month,
	  _week,
		count_prev_week,
		_count,
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
	  'offerers' as funnel_step,
	  region,
	  city,
	  _year,
	  _month,
	  _week,
		count_prev_week,
		_count,
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
	  'offerers_approved' as funnel_step,
	  region,
	  city,
	  _year,
	  _month,
	  _week,
		count_prev_week,
		_count,
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
	  'offerers_sent_doc' as funnel_step,
	  region,
	  city,
	  _year,
	  _month,
	  _week,
		count_prev_week,
		_count,
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
	  'approved_by_insurer' as funnel_step,
	  region,
	  city,
	  _year,
	  _month,
	  _week,
		count_prev_week,
		_count,
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
	  'tenants' as funnel_step,
	  region,
	  city,
	  _year,
	  _month,
	  _week,
		count_prev_week,
		_count,
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
	  'visits_booked' as funnel_step,
	  region,
	  city,
	  _year,
	  _month,
	  _week,
		count_prev_week,
		_count,
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
	  'visits_completed' as funnel_step,
	  region,
	  city,
	  _year,
	  _month,
	  _week,
		count_prev_week,
		_count,
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
	  'offers_submitted' as funnel_step,
	  region,
	  city,
	  _year,
	  _month,
	  _week,
		count_prev_week,
		_count,
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
	  'offers_approved' as funnel_step,
	  region,
	  city,
	  _year,
	  _month,
	  _week,
		count_prev_week,
		_count,
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
	  'documentation_sent' as funnel_step,
	  region,
	  city,
	  _year,
	  _month,
	  _week,
		count_prev_week,
		_count,
		wow,
		mtd,
		ytd,
		mom,
		yoy
	from growth.documentation_sent
)
