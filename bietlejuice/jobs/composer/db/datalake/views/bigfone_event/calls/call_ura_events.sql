drop view if exists datalake_bigfone_clean_prod.call_ura_events;
create or replace view datalake_bigfone_clean_prod.call_ura_events as 
with data_provided_events as (
    select * from datalake_bigfone_clean_prod.events 
    where event='call.data-provided'
),
extract_ura_custom_keys_from_metadata as (
    select
        *,
        -- Teravoz default keys start with lowercase, there is just one custom key for each event. 
        keys[1] as custom_key
    from (
        select
            *,
            map_keys(cast(json_parse(metadata) as map(varchar,json))) as keys
        from
            data_provided_events 
    )
    where regexp_like(keys[1], '^[A-Z].+')=true -- all ura custom events start with uppercase
    and keys[1] not in (
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
        lower(json_extract_scalar(metadata, concat('$.', custom_key))) like lower(concat(custom_key, '%'))
)
select
    ck.id,
    ck.id_call,
    step.custom_key as ura_step,
    ck.custom_key as name,
    json_extract_scalar(ck.metadata, concat('$.', ck.custom_key)) as digit_answer,
    ck.ts_created,
    ck.ts_created_local,
    ck.ts_received,
    ck.ts_received_local,
    date(concat(cast(ck.year as varchar(4)), '-', cast(ck.month as varchar(2)), '-', cast(ck.day as varchar(2)))) as dt_event
from extract_ura_custom_keys_from_metadata ck
left join events_with_ura_step step
on 
    ck.id_call=step.id_call
where 
    -- remove step events
    ck.custom_key<>step.custom_key; 