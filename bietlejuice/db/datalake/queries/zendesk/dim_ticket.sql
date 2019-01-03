with parse_fields as (
    select zt.id,
        cf.raw_title,
        regexp_extract(f1.field, 'id\\":(\d+).*value\\":([^}]+)', 2) as value
    from datalake_clean.zendesk_tickets zt
    cross join unnest(regexp_extract_all(zt.custom_fields, '{[^}]+[^,]+[^{]+}')) as f1(field)
    left join datalake_clean.zendesk_ticket_fields as cf
        on cast(cf.id as varchar) = regexp_extract(f1.field, 'id\\":(\d+).*value\\":([^}]+)', 1)
),
fields_map as (
    select id,
        map_agg(raw_title, regexp_extract(value, '\d+')) as cols
    from parse_fields
    group by id
)
select t.id as sk_ticket,
       t.subject,
       t.description,
       t.channel,
       t.priority,
       t.recipient,
       t.satisfaction_rating,
       c.cols['Tipo de Solicitação'] as request_type,
       c.cols['Tipo de Cliente'] as client_type,
       t.created_at,
       current_timestamp as ts_load
from datalake_clean.zendesk_tickets t
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