drop table if exists teravoz.fact_call_queues;
create table if not exists teravoz.fact_call_queues (
    sk_call_queued bigint,
    sk_call varchar,
    sk_queue smallint,
    sk_user bigint, 
    sk_call_date bigint,
    sk_call_date_local bigint,
    queue_number smallint,
    queue_name varchar,
    seconds_queue_waiting_duration bigint,
    is_same_queue_transferred boolean,
    is_blind_transfer boolean,
    is_call_abandoned_in_queue boolean,
    ts_queue_joined timestamp,
    ts_queue_joined_local timestamp,
    ts_blinded_transfer timestamp,
    ts_blinded_transfer_local timestamp,
    ts_call_abandoned_in_queue timestamp,
    ts_call_abandoned_in_queue_local timestamp,
    ts_queue_left timestamp,
    ts_queue_left_local timestamp,
    ts_load timestamp
)


