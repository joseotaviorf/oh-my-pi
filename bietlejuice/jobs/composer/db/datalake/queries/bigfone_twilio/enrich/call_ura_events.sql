with data_provided_events as (
    select * from datalake_bigfone_events.events
    where event='call.data-provided'
),
extract_ura_custom_keys_from_metadata as (
    select *
    from (
        select
            *,
            regexp_extract(metadata_items.key_value, '\\"(\\w+)\\" *:') as custom_key,
            regexp_extract(metadata_items.key_value, ': *\\"(\\w+)\\"') as custom_key_value
        from
            data_provided_events
            lateral view explode(split(regexp_replace(data_provided_events.metadata, ',','}},{{'), ',')) metadata_items as
            key_value
    )
    where custom_key rlike '^[A-Z].+' -- all ura custom events start with uppercase
    and custom_key not in (
        'CSat1', 'CSat2', 'Resposta', -- csat events
        'OutOfService', 'MAX_RETRIES_REACHED' -- system events
    )
),
-- almost all events of step have json key = json value, but there is an exception "DEFAULT":"default_else",
-- so we analyze if the beginning of the string is equal json_key like 'json_value%'.
events_with_ura_step as (
    select
        id,
        id_call,
        custom_key
    from extract_ura_custom_keys_from_metadata
    where
        lower(custom_key_value) like lower(concat(custom_key, '%'))
)
select
    ck.id,
    ck.id_call,
    step.custom_key as ura_step,
    ck.custom_key as name,
    ck.custom_key_value as digit_selection,
    ck.ts_created,
    ck.ts_created_local,
    ck.ts_received,
    ck.ts_received_local,
    date(concat(cast(ck.year as varchar(4)), '-', cast(ck.month as varchar(2)), '-', cast(ck.day as varchar(2)))) as dt_event,
    year,
    month,
    day
from extract_ura_custom_keys_from_metadata ck
left join events_with_ura_step step
on
    ck.id_call=step.id_call
where
    -- remove step events
    ck.custom_key<>step.custom_key
    and year={year} and month={month} and day={day}
