/******************************************************************************************************************
    The data migration from Asterisk to Teravoz and the integration with BigFone was completed in September 2019. 
    Because of this, we are filtering all call data from that date.
******************************************************************************************************************/
drop view if exists dw_teravoz_prod.fact_call_ura_paths;
create or replace view  dw_teravoz_prod.fact_call_ura_paths as
with ura as (
    select distinct * from datalake_bigfone_clean_prod.call_ura_events 
    where dt_event >= date('2019-09-01')
),
/*
    ura_interactions = time diff between the next event immediately after the ura event selected and ura event selected 
    A call can have multiple ura events. So we find the pair (ura_event_selected, next_event_after_ura_event_selected) when:
    1. the events compared are different  
    2. min(ts_next_event) >= ts_event_selected, and ts_next_event is the closest to ts_event_selected
    3. id_call is the same
*/
ura_interactions as (
    select
        ura_1.id,
        ura_1.id_call,
        ura_1.ts_created as ts_created_ura_step_event,
        min(ura_2.ts_created) as ts_created_next_ura_step_event
    from ura ura_1
    inner join ura ura_2
    on ura_1.id_call=ura_2.id_call 
    and ura_1.ts_created <= ura_2.ts_created 
    and ura_1.id<>ura_2.id
    group by 1,2,3
)
select
    u.id_call as sk_call,
    u.id as sk_flow_step,
    u.dt_event as sk_started,
    cast(date_format(u.ts_created, '%Y%m%d') as bigint) as sk_call_date,
    cast(date_format(u.ts_created_local, '%Y%m%d') as bigint) as sk_call_date_local,
    u.ura_step as flow_step_name,
    u.name as ura_step_name,
    u.digit_answer as option_answered,
    date_diff('second',u2.ts_created_ura_step_event,u2.ts_created_next_ura_step_event) as seconds_ura_step_duration,
    u.ts_created,
    u.ts_created_local
from ura u
inner join ura_interactions u2
on u.id=u2.id;