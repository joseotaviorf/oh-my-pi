with all_events as (
  select
    false as partial,
    extract(year from ts_event) as _year,
    extract(month from ts_event) as _month,
    extract(week from ts_event) as _week,
    extract(day from ts_event) as _day,
    coalesce(uuid, '') as uuid,
    case
      when ep_house_id is not null and regexp_extract(ep_house_id, '\d+') is not null
        then if(length(regexp_extract(ep_house_id, '\d+')) < 9,
            892700000 + cast(regexp_extract(ep_house_id, '\d+') as integer),
            cast(regexp_extract(ep_house_id, '\d+') as integer))
      else -1
    end as house_id
  from {db}."170698_schedule_page_viewed_events"
  where cast(ts_event as date) >= cast('2017-08-23' as date)
        and cast(ts_event as date) < cast(now() as date)
),
