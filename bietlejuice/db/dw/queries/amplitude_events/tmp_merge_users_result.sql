create table amplitude_events.tmp_merge_users_result as (
with amplitude_events_not_empty as (
  select
    case when device_id is null or device_id = '' then null else device_id end as device_id,
    case when amplitude_id is null or amplitude_id = '' then null else amplitude_id end as amplitude_id,
    case when user_id is null or user_id = '' then null else user_id end as user_id
    from datalake_clean.amplitude_events
  where ym = '{0}'
),
user_nulls as (
  select device_id, amplitude_id, user_id
    from amplitude_events_not_empty
  where user_id is null
),
user_not_nulls as (
  select device_id, amplitude_id, user_id
    from amplitude_events_not_empty
  where user_id is not null
),
result_out_merge as (
  select
    coalesce(n.device_id, nn.device_id) as device_id,
    coalesce(n.amplitude_id, nn.amplitude_id) as amplitude_id,
    case
      when n.device_id is not null
            and nn.device_id is not null
            and n.amplitude_id is not null
            and nn.amplitude_id is not null
        then nn.user_id
      else coalesce(nn.user_id, n.user_id)
    end as user_id
    from user_nulls n
  full outer join user_not_nulls nn
    on n.device_id = nn.device_id
     and n.amplitude_id = nn.amplitude_id
)
select distinct rom.device_id, rom.amplitude_id, rom.user_id
  from amplitude_events.merged_users mu
right join result_out_merge rom
  on mu.device_id = rom.device_id
     and mu.amplitude_id = rom.amplitude_id::varchar
     and mu.user_id = rom.user_id
where mu.device_id is null
      and mu.amplitude_id is null
      and mu.user_id is null
)