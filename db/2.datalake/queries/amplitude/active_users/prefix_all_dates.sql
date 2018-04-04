with all_events as (
  select
    false as partial,
    extract(year from cast(regexp_extract(trim(event_time), '\d{4}-\d{2}-\d{2}') as date)) as _year,
    extract(month from cast(regexp_extract(trim(event_time), '\d{4}-\d{2}-\d{2}') as date)) as _month,
    extract(week from cast(regexp_extract(trim(event_time), '\d{4}-\d{2}-\d{2}') as date)) as _week,
    extract(day from cast(regexp_extract(trim(event_time), '\d{4}-\d{2}-\d{2}') as date)) as _day,
    trim(amplitude_id) as amplitude_id,
    'QuintoAndar' as region,
    'QuintoAndar' as city
  from datalake_clean.amplitude_events
  where ym >= '2017-01'
    -- top events
    and ((trim(app) = '170698' and et like '%_page_viewed' and cast(regexp_extract(trim(event_time), '\d{4}-\d{2}-\d{2}') as date) >= cast('2017-08-23' as date))
      or (trim(app) = '157033' and et in (
        'Listing-Swipes_photos',
        'Preview-Swipes_photos',
        'Listing-Full_screen_swipes',
        'Map-Price_flag_click',
        'Address-Inputs_address',
        'Listing-View',
        'Preview-Close',
        'App_close',
        'Listing-Back',
        'Preview-Goes_to_listing'
      ) and cast(regexp_extract(trim(event_time), '\d{4}-\d{2}-\d{2}') as date) < cast('2017-08-23' as date))
      or (trim(app) = '160023' and et in (
        'Listing-Views_listing',
        'listing_photo_viewed',
        'Map-Views_map_filtered',
        'listing_tab_changed',
        'listing_photosphere_opened',
        'Map-Views_map',
        'listing_page_viewed',
        'Home-Views_home',
        'Home-Clicks_find_property',
        'Close_onboarding'
      ) and cast(regexp_extract(trim(event_time), '\d{4}-\d{2}-\d{2}') as date) < cast('2017-08-23' as date))
      or (trim(app) = '156118' and et in (
        'Filter-More_options',
        'Preview-Swipes_photos',
        'Map-Address_input_results',
        'Map-Filter_results',
        'Listing-View',
        'App_open',
        'session_start',
        'session_end',
        'Map-Filter_click',
        'Menu-Favorites',
        'Favorites-Go_to_listing'
      ) and cast(regexp_extract(trim(event_time), '\d{4}-\d{2}-\d{2}') as date) < cast('2017-08-23' as date)))
    and cast(regexp_extract(trim(event_time), '\d{4}-\d{2}-\d{2}') as date) >= cast('2017-01-01' as date)
    and cast(regexp_extract(trim(event_time), '\d{4}-\d{2}-\d{2}') as date) < cast(now() as date)
)
