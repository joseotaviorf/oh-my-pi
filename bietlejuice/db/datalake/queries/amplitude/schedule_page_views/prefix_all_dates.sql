with all_events as (
      select
        false as partial,
        extract(year from cast(regexp_extract(trim(event_time), '\d{4}-\d{2}-\d{2}') as date)) as _year,
        extract(month from cast(regexp_extract(trim(event_time), '\d{4}-\d{2}-\d{2}') as date)) as _month,
        extract(week from cast(regexp_extract(trim(event_time), '\d{4}-\d{2}-\d{2}') as date)) as _week,
        extract(day from cast(regexp_extract(trim(event_time), '\d{4}-\d{2}-\d{2}') as date)) as _day,
        trim(uuid) as uuid,
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
      where ym >= '2017-08' and ym <= '2018-12'
        and et = 'schedule_page_viewed'
        and trim(app) = '170698'
        and cast(regexp_extract(trim(event_time), '\d{4}-\d{2}-\d{2}') as date) >= cast('2017-08-23' as date)
        and cast(regexp_extract(trim(event_time), '\d{4}-\d{2}-\d{2}') as date) < cast(now() as date)
  union
      select
        false as partial,
        extract(year from cast(regexp_extract(trim(event_time), '\d{4}-\d{2}-\d{2}') as date)) as _year,
        extract(month from cast(regexp_extract(trim(event_time), '\d{4}-\d{2}-\d{2}') as date)) as _month,
        extract(week from cast(regexp_extract(trim(event_time), '\d{4}-\d{2}-\d{2}') as date)) as _week,
        extract(day from cast(regexp_extract(trim(event_time), '\d{4}-\d{2}-\d{2}') as date)) as _day,
        coalesce(uuid, '') as uuid,
        case
          when json_extract(event_properties, '$.house_id') is not null and regexp_extract(cast(json_extract(event_properties, '$.house_id') as varchar), '\d+') is not null
            then if(length(regexp_extract(cast(json_extract(event_properties, '$.house_id') as varchar), '\d+')) < 9,
                     892700000 + cast(cast(regexp_extract(cast(json_extract(event_properties, '$.house_id') as varchar), '\d+') as double) as integer),
                     cast(cast(regexp_extract(cast(json_extract(event_properties, '$.house_id') as varchar), '\d+') AS double) AS integer))
          when json_extract(event_properties, '$.Id_Imovel') is not null and regexp_extract(cast(json_extract(event_properties, '$.Id_Imovel') as varchar), '\d+') is not null
            then if(length(regexp_extract(cast(json_extract(event_properties, '$.Id_Imovel') as varchar), '\d+')) < 9,
                892700000 + cast(cast(regexp_extract(cast(json_extract(event_properties, '$.Id_Imovel') as varchar), '\d+') as double) as integer),
                cast(cast(regexp_extract(cast(json_extract(event_properties, '$.Id_Imovel') as varchar), '\d+') as double) as integer))
          when json_extract(event_properties, '$.imovel_id') is not null and regexp_extract(cast(json_extract(event_properties, '$.imovel_id') as varchar), '\d+') is not null
            then if(length(regexp_extract(cast(json_extract(event_properties, '$.imovel_id') as varchar), '\d+')) < 9,
                892700000 + cast(cast(regexp_extract(cast(json_extract(event_properties, '$.imovel_id') as varchar), '\d+') as double) as integer),
                cast(cast(regexp_extract(cast(json_extract(event_properties, '$.imovel_id') as varchar), '\d+') as double) as integer))
          when json_extract(event_properties, '$.Imovel_id') is not null and regexp_extract(cast(json_extract(event_properties, '$.Imovel_id') as varchar), '\d+') is not null
            then if(length(regexp_extract(cast(json_extract(event_properties, '$.Imovel_id') as varchar), '\d+')) < 9,
                892700000 + cast(cast(regexp_extract(cast(json_extract(event_properties, '$.Imovel_id') as varchar), '\d+') as double) as integer),
                cast(cast(regexp_extract(cast(json_extract(event_properties, '$.Imovel_id') as varchar), '\d+') as double) as integer))
        else -1
        end as house_id
      from datalake_amplitude_clean_prod.events
      where year >= 2019
            and event_type = 'schedule_page_viewed'
            and app = 170698
            and cast(regexp_extract(trim(event_time), '\d{4}-\d{2}-\d{2}') as date) >= cast('2017-08-23' as date)
            and cast(regexp_extract(trim(event_time), '\d{4}-\d{2}-\d{2}') as date) < cast(now() as date)

),
