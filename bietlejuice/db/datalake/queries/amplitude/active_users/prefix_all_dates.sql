with all_events as (
      select
         extract(year from ts_event) as _year,
         extract(month from ts_event) as _month,
         extract(week from ts_event) as _week,
         extract(day from ts_event) as _day,
         coalesce(cast(id_amplitude as varchar), '') as amplitude_id,
         false as partial
      from {db}.events
      where event_type in ('listing_page_viewed',
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
                           'session_start')
         and ((id_app = 170698 and date(ts_event) >= cast('2017-08-23' as date))
          or (id_app = 157033 and date(ts_event) < cast('2017-08-23' as date))
          or (id_app = 160023 and date(ts_event) < cast('2017-08-23' as date))
          or (id_app = 156118 and date(ts_event) < cast('2017-08-23' as date)))
         and date(ts_event) < cast(now() as date)
         and date(ts_event) >= cast('2017-01-01' as date)
),
