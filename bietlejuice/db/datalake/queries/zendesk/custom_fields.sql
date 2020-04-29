with tickets_filter as (
	select distinct * from datalake_clean.zendesk_tickets t
	where (t.ticket_via<>'api' or (t.ticket_via='api' and t.tags not like '%hsm%'))
        and dt_extracted = '{execution_date}'
),
parse_fields as (
    select tf.id_ticket,
        f1.field,
        json_extract_scalar(f1.field, '$.id') as id_field,
        json_extract(f1.field, '$.value') as value,
        tf.ts_updated
    from tickets_filter tf
    cross join unnest(regexp_extract_all(tf.custom_fields, '{{(.*?)}}')) as f1(field)
    where regexp_like(json_format(json_extract(f1.field, '$.value')), '\"?null\"?') = false
)
select
    f.id_ticket,
    cast(map_agg(f.id_field, f.value) as json) as custom_fields,
    f.ts_updated
from parse_fields f
group by 1,3