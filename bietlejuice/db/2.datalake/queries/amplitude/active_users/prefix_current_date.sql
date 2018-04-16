with all_events as (
  select
    extract(year from cast(regexp_extract(trim(event_time), '\d{4}-\d{2}-\d{2}') as date)) as _year,
    extract(month from cast(regexp_extract(trim(event_time), '\d{4}-\d{2}-\d{2}') as date)) as _month,
    extract(week from cast(regexp_extract(trim(event_time), '\d{4}-\d{2}-\d{2}') as date)) as _week,
    extract(day from cast(regexp_extract(trim(event_time), '\d{4}-\d{2}-\d{2}') as date)) as _day,
    trim(amplitude_id) as amplitude_id,
    true as partial
  from datalake_clean.amplitude_events
  where ym >= '2017-01'
    and et in ('listing_page_viewed',
               'search_results_page_viewed',
               'schedule_page_viewed',
               'offer_submission_page_viewed',
               'offer_conditions_page_viewed',
               'login_page_viewed',
               'documentation_page_viewed',
               'home_page_viewed',
               'Listing-View',
               'Listing-Views_listing',
               'listing_photo_viewed',
               'Map-Views_map',
               'Home-Views_home',
               'Listing-View',
               'App_open',
               'session_start'
       )
     and ((trim(app) = '170698' and cast(regexp_extract(trim(event_time), '\d{4}-\d{2}-\d{2}') as date) >= cast('2017-08-23' as date))
      or (trim(app) = '157033' and cast(regexp_extract(trim(event_time), '\d{4}-\d{2}-\d{2}') as date) < cast('2017-08-23' as date))
      or (trim(app) = '160023' and cast(regexp_extract(trim(event_time), '\d{4}-\d{2}-\d{2}') as date) < cast('2017-08-23' as date))
      or (trim(app) = '156118' and cast(regexp_extract(trim(event_time), '\d{4}-\d{2}-\d{2}') as date) < cast('2017-08-23' as date)))
    and extract(year from cast(regexp_extract(trim(event_time), '\d{4}-\d{2}-\d{2}') as date)) = extract(year from (now() - interval '1' month))
    and extract(month from cast(regexp_extract(trim(event_time), '\d{4}-\d{2}-\d{2}') as date)) = extract(month from (now() - interval '1' month))
    and extract(day from cast(regexp_extract(trim(event_time), '\d{4}-\d{2}-\d{2}') as date)) < extract(day from now())
),