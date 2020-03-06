-- Some fields are JSON strings. We're using REGEX because it's not possible to use get_json_object because of the special characters.

select
    -- format: {{"$oid": "5b9ffb4da939ee6a2c873276"}}
    regexp_extract(_id, '(\\w+\\d+)', 1) as _id,
    boolean(active) as is_active,
    business_context,
    cloudsearch_criteria,
    timestamp(created_at) as ts_created,
    date(date) as dt_alert_triggered,
    days,
    device_id as id_device,
    filters,
    grandpa_user_id as id_grandpa_user,
    house_id as id_house,
    house_ids as ids_house,
    houses_ids as ids_houses,
    houses_sent, 
    boolean(is_auto_scheduling_possible) as is_auto_scheduling_possible,
    -- format {{"$date": "2019-05-01T10:00:00Z" }}
    cast(regexp_extract(lastActivation, '(\\d{{4}}-\\d{{2}}-\\d{{2}}\\w{{1}}\\d{{2}}:\\d{{2}}:\\d{{2}})', 1) as timestamp) as ts_last_activation,
    -- format {{"$date": "2019-05-01T10:00:00Z" }}
    cast(regexp_extract(last_day_sent, '(\\d{{4}}-\\d{{2}}-\\d{{2}}\\w{{1}}\\d{{2}}:\\d{{2}}:\\d{{2}})', 1) as timestamp) as ts_last_day_sent,
    timestamp(last_email_run) as ts_last_email_run,
    lead_id as id_lead,
    name,
    notifications_sent_agent,
    -- format: {{"$oid": "5b9ffb4da939ee6a2c873276"}}
    regexp_extract(profile_id, '(\\w+\\d+)', 0) as id_profile,
    push_user_id as id_push_user,
    quintoandar_id as id_quintoandar,
    results, 
    source,
    type,
    -- format {{"$date": "2019-05-01T10:00:00Z" }}
    timestamp(updated_at) as ts_updated,
    user_id as id_user,
    visit_code,
    -- format {{"$date": "2019-05-01T10:00:00Z" }}
    cast(regexp_extract(visit_day_time, '(\\d{{4}}-\\d{{2}}-\\d{{2}}\\w{{1}}\\d{{2}}:\\d{{2}}:\\d{{2}})', 1) as timestamp) as ts_visited
from
    datalake_cidade_alerta_raw.alert
where
    year={year} and month={month} and day={day}