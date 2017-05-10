DROP VIEW IF EXISTS vw_fact_liquidity_ga_kpis;
CREATE VIEW vw_fact_liquidity_ga_kpis
as
SELECT
  date as sk_date,
  "deviceCategory" as device_category,
  account_name,
  property_name,
  profile_name,
  users::integer,
  sessions::integer,
  bounces::integer,
  "bounceRate"::decimal(18,4) as bounce_rate,
  pageviews::integer,
  "uniquePageviews"::integer as unique_pageviews,
  exits::integer,
  "exitRate"::decimal(18,4) as exit_rate,
  "timeOnScreen"::decimal(18,4) as time_on_screen,
  "avgTimeOnPage"::decimal(18,4) as avg_time_on_page,
  processed_date
FROM
  public.ga_kpis
where
  processed_date is null
order by
	1
;

-- select * into fact_liquidity_ga_kpis from vw_fact_liquidity_ga_kpis



