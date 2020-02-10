with all_events as (
        select
            false as partial,
            extract(year from ts_event) as _year,
            extract(month from ts_event) as _month,
            extract(week from ts_event) as _week,
            extract(day from ts_event) as _day,
            coalesce(cast(id_amplitude as varchar), '') as amplitude_id,
            case
              when json_extract(event_properties, '$.house_id') is not null and regexp_extract(cast(json_extract(event_properties, '$.house_id') as varchar), '\d+') is not null
                then if(length(regexp_extract(cast(json_extract(event_properties, '$.house_id') as varchar), '\d+')) < 9,
                         892700000 + cast(cast(regexp_extract(cast(json_extract(event_properties, '$.house_id') as varchar), '\d+') as double) as integer),
                         if(length(regexp_extract(cast(json_extract(event_properties, '$.house_id') as varchar), '\d+')) > 9,
                             null,
                             cast(cast(regexp_extract(cast(json_extract(event_properties, '$.house_id') as varchar), '\d+') AS double) AS integer)
                         )
                      )
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
        where ((id_app = 170698 and event_type = 'listing_page_viewed' and cast
        (ts_event as date) >= cast('2017-08-23' as date))
              or (id_app = 157033 and event_type = 'Listing-View' and date(ts_event) < cast('2017-08-23' as date))
              or (id_app = 160023 and event_type = 'Listing-Views_listing' and date(ts_event) < cast('2017-08-23' as date))
              or (id_app = 156118 and event_type = 'Listing-View' and date(ts_event) < cast('2017-08-23' as date)))
            and date(ts_event) >= cast('2017-01-01' as date)
            and date(ts_event) < cast(now() as date)
),
