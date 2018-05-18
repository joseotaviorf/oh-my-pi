with all_events as (
  select
    true as partial,
    extract(year from cast(regexp_extract(trim(event_time), '\d{4}-\d{2}-\d{2}') as date)) as _year,
    extract(month from cast(regexp_extract(trim(event_time), '\d{4}-\d{2}-\d{2}') as date)) as _month,
    extract(week from cast(regexp_extract(trim(event_time), '\d{4}-\d{2}-\d{2}') as date)) as _week,
    extract(day from cast(regexp_extract(trim(event_time), '\d{4}-\d{2}-\d{2}') as date)) as _day,
    trim(amplitude_id) as amplitude_id,
    case
      when trim(e_house_id) != '' and regexp_extract(trim(e_house_id), '\d+') is not null
        then if(length(regexp_extract(trim(e_house_id), '\d+')) < 9, 892700000 + cast(cast(regexp_extract(trim(e_house_id), '\d+') as double) as integer), cast(cast(regexp_extract(trim(e_house_id), '\d+') as double) as integer))
      when trim(e__id__imovel) != '' and regexp_extract(trim(e__id__imovel), '\d+') is not null
        then if(length(regexp_extract(trim(e__id__imovel), '\d+')) < 9, 892700000 + cast(cast(regexp_extract(trim(e__id__imovel), '\d+') as double) as integer), cast(cast(regexp_extract(trim(e__id__imovel), '\d+') as double) as integer))
      when trim(e_imovel_id) != '' and regexp_extract(trim(e_imovel_id), '\d+') is not null
        then if(length(regexp_extract(trim(e_imovel_id), '\d+')) < 9, 892700000 + cast(cast(regexp_extract(trim(e_imovel_id), '\d+') as double) as integer), cast(cast(regexp_extract(trim(e_imovel_id), '\d+') as double) as integer))
      when trim(e__imovel_id) != '' and regexp_extract(trim(e__imovel_id), '\d+') is not null
        then if(length(regexp_extract(trim(e__imovel_id), '\d+')) < 9, 892700000 + cast(cast(regexp_extract(trim(e__imovel_id), '\d+') as double) as integer), cast(cast(regexp_extract(trim(e__imovel_id), '\d+') as double) as integer))
      else -1
    end as house_id
  from datalake_clean.amplitude_events
  where ym >= '2017-08'
    and et = 'schedule_page_viewed'
    and trim(app) = '170698'
    and extract(year from cast(regexp_extract(trim(event_time), '\d{4}-\d{2}-\d{2}') as date)) = extract(year from (now() - interval '1' month))
    and extract(month from cast(regexp_extract(trim(event_time), '\d{4}-\d{2}-\d{2}') as date)) = extract(month from (now() - interval '1' month))
    and extract(day from cast(regexp_extract(trim(event_time), '\d{4}-\d{2}-\d{2}') as date)) < extract(day from now())
),
