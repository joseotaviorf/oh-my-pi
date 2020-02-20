with tickets_filter as (
	select distinct * from datalake_clean.zendesk_tickets t
	where (t.ticket_via<>'api' or (t.ticket_via='api' and t.tags not like '%hsm%'))
        and dt_extracted = '{execution_date}'
),
last_updated_ticket as (
    select id_ticket, max(ts_updated) as ts_last_updated from tickets_filter group by 1
),
last_updated_ticket_fields as (
	select id_ticket_fields, max(ts_updated) as ts_last_updated from datalake_clean.zendesk_ticket_fields group by 1
),
parse_fields as (
    select tf.id_ticket,
        f1.field,
        regexp_extract(f1.field, '{{\\?"id\\?":"?(\d+)"?', 1) as id_field,
        nullif(regexp_extract(f1.field, '"value\\?":\\?"?#?([^\\?"|}}]+)', 1), 'null') as value
    from tickets_filter tf
    inner join last_updated_ticket l
        on tf.id_ticket=l.id_ticket
    cross join unnest(regexp_extract_all(tf.custom_fields, '{{[^}}]+[^,]+[^{{]+}}')) as f1(field)
)
select
    f.id_ticket,
    CAST(map_agg(tf.raw_title, f.value) AS json) as custom_fields
from parse_fields f
inner join last_updated_ticket_fields l
on l.id_ticket_fields = f.id_field
inner join datalake_clean.zendesk_ticket_fields tf
on l.id_ticket_fields = tf.id_ticket_fields and l.ts_last_updated=tf.ts_updated
where f.value is not null
group by 1
