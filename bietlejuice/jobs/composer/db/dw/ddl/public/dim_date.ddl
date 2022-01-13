drop table if exists public.dim_date;

create table public.dim_date (
  sk_date bigint,
  date date,
  year string,
  month int,
  month_name string,
  day int,
  day_of_year string,
  week_day int,
  weekday_name string,
  calendar_week int,
  working_days_in_month bigint,
  total_working_days_in_month bigint,
  brz_date string,
  usa_date string,
  universal_date string,
  quarter string,
  year_quarter string,
  year_month sting,
  year_calendar_week string,
  weekend string,
  is_brz_holiday string,
  week_start date,
  week_end date,
  month_start date,
  month_end date,
  last_day date,
  last_week date,
  last_2_weeks date,
  last_4_weeks date,
  last_month date,
  last_quarter date,
  last_year date
)

ALTER TABLE public.dim_date OWNER TO databricks;
