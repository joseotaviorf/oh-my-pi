select distinct
    coalesce(mu.device_id, tmur.device_id) as device_id,
    coalesce(mu.amplitude_id, tmur.amplitude_id::varchar) as amplitude_id,
    case
    when mu.device_id is not null
          and tmur.device_id is not null
          and mu.amplitude_id is not null
          and tmur.amplitude_id is not null
        then tmur.user_id
        else coalesce(mu.user_id, tmur.user_id)
        end as user_id
    from
        amplitude_events.merged_users mu
    full outer join
        amplitude_events.tmp_merge_users_result tmur
        on mu.device_id = tmur.device_id
        and mu.amplitude_id = tmur.amplitude_id
    where mu.device_id is null
        and mu.amplitude_id is null
        and mu.user_id is null