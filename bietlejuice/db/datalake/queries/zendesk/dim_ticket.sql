with parse_fields as (
    select zt.id,
        f1.field,
        regexp_extract(f1.field, '.*{\\"id\\":(\d+)', 1) as field_id,
        replace(regexp_extract(f1.field, '.*"value\\":(.+)}"}', 1), '\"') as value
    from datalake_clean.zendesk_tickets zt
    cross join unnest(regexp_extract_all(zt.custom_fields, '{[^}]+[^,]+[^{]+}')) as f1(field)
),
fields_map as (
    select f.id,
        map_agg(cf.raw_title, f.value) as cols
    from parse_fields f
    left join datalake_clean.zendesk_ticket_fields cf
       on cf.id = f.field_id
    group by f.id
),
last_rows as (
    select
        id,
        max(dt_extraction) as dt
    from datalake_clean.zendesk_tickets
    group by 1
)
select distinct
       t.id as sk_ticket,
       t.subject,
       t.description,
       t.channel,
       zg.name as box,
       t.priority,
       t.recipient,
       t.tags,
       t.satisfaction_rating,
       c.cols['Tipo de Solicitação'] as request_type,
       c.cols['Tipo de Cliente'] as client_type,
       date_parse(regexp_extract(t.description, 'Chat started: (\d+.\d+.\d+ \d+:\d+ \wM)', 1), '%Y-%m-%d %h:%i %p') as chat_started_at,
       t.created_at,
       current_timestamp as ts_load
from datalake_clean.zendesk_tickets t
join last_rows lr
    on lr.id = t.id and lr.dt = t.dt_extraction
left join fields_map c
    on c.id = t.id
left join datalake_clean.ods_dim_house_listing dhl
     on c.cols['Código do Imóvel'] = dhl.short_id_house
        and cast(from_iso8601_timestamp(t.created_at) as timestamp)
        between cast(regexp_extract(dhl.ts_listing_version_start, '\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}') as timestamp)
         and (case
                when dhl.ts_listing_version_end = ''
                  then now()
                else cast(regexp_extract(dhl.ts_listing_version_end, '\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}') as timestamp)
              end)
left join datalake_clean.zendesk_groups zg
    on zg.id = t.group_id