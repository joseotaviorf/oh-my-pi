DROP VIEW IF EXISTS vw_fact_liquidity_ga_confirmed_visits;
CREATE VIEW vw_fact_liquidity_ga_confirmed_visits AS
SELECT
  date as sk_date,
  campaign,
  split_part("sourceMedium",' / ',1) as source,
  split_part("sourceMedium",' / ',2) as medium,
  "operatingSystem" as operating_system,
  "mobileDeviceModel" as device_model,
  "mobileDeviceMarketingName" as device_marketing_name,
  "deviceCategory" as device_category,
  account_name,
  property_name,
  profile_name,
  case when date < '2016-10-01' then "goal2Starts" else "goal10Starts" end::decimal(18,4)  as confirmed_visit_starts,
  case when date < '2016-10-01' then "goal2Completions" else "goal10Completions" end::decimal(18,4) as confirmed_visit_completions,
  case when date < '2016-10-01' then "goal2Value" else "goal10Value" end::decimal(18,4) as confirmed_visit_values,
  case when date < '2016-10-01' then "goal2ConversionRate" else "goal10ConversionRate" end::decimal(18,4) as confirmed_visit_conversion_rate
FROM
  public.ga_confirmed_visits
 where
  processed_date is null
order by
  date
;

-- select * into fact_liquidity_ga_confirmed_visits from vw_fact_liquidity_ga_confirmed_visits

-- select count(1) from ga_confirmed_visits where  processed_date is null


