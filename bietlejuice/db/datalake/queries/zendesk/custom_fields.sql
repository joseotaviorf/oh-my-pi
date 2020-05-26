with tickets_filter as (
    select distinct * from datalake_clean.zendesk_tickets t
	where (t.ticket_via<>'api' or (t.ticket_via='api' and t.tags not like '%hsm%'))
        and dt_extracted = '{execution_date}'
),
-- if the same ticket was updated 2x on the same day and its custom_fields had changed
distinct_tickets as (
    with last_updated_ticket as (
        select 
            id_ticket, 
            max(ts_updated) as ts_last_updated 
        from tickets_filter 
        group by 1
    )
    select 
        tf.id_ticket, 
        tf.custom_fields, 
        tf.ts_updated 
    from tickets_filter tf
    inner join last_updated_ticket lt
    on tf.id_ticket=lt.id_ticket
       and tf.ts_updated=lt.ts_last_updated
),
parse_fields as (
    select 
        df.id_ticket,
        f1.field,
        json_extract_scalar(f1.field, '$.id') as id_field,
        json_extract(f1.field, '$.value') as value,
        df.ts_updated
    from distinct_tickets df
    cross join unnest(regexp_extract_all(df.custom_fields, '{{(.*?)}}')) as f1(field)
    where regexp_like(json_format(json_extract(f1.field, '$.value')), '\"?null\"?') = false
)
select
    f.id_ticket,
    cast(map_agg(f.id_field, f.value) as json) as custom_fields,
    f.ts_updated
from parse_fields f
where f.value is not null
group by 1,3