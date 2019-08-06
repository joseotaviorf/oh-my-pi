with all_events as (
      select
        true as partial,
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
      where ym >= '2017-08'
        and et = 'schedule_page_viewed'
        and trim(app) = '170698'
        and extract(year from cast(regexp_extract(trim(event_time), '\d{4}-\d{2}-\d{2}') as date)) = extract(year from (now() - interval '1' month))
        and extract(month from cast(regexp_extract(trim(event_time), '\d{4}-\d{2}-\d{2}') as date)) = extract(month from (now() - interval '1' month))
        and extract(day from cast(regexp_extract(trim(event_time), '\d{4}-\d{2}-\d{2}') as date)) < extract(day from now())
     union
      select
        true as partial,
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
      from datalake_clean_spark.amplitude_events
      where year >= 2019
            and event_type = 'schedule_page_viewed'
            and app = 170698
            and extract(year from cast(regexp_extract(trim(event_time), '\d{4}-\d{2}-\d{2}') as date)) = extract(year from (now() - interval '1' month))
		    and extract(month from cast(regexp_extract(trim(event_time), '\d{4}-\d{2}-\d{2}') as date)) = extract(month from (now() - interval '1' month))
		    and extract(day from cast(regexp_extract(trim(event_time), '\d{4}-\d{2}-\d{2}') as date)) < extract(day from now())
),
