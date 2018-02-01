drop table if exists fact_growth;
create table fact_growth (
  sk_date integer,
  sk_week_start_date integer,
  funnel_step varchar,
  region varchar,
  city varchar,
  _year integer,
	_month integer,
	_week integer,
	prev_week_count integer,
	week_count integer,
	wow numeric(14,4),
	mtd integer,
	ytd integer,
	mom numeric(14,4),
	yoy numeric(14,4)
)
;