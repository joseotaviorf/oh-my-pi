
with filtered_chats as (
  select
    *
  from {db}.chats c
  where
    year={year} and month={month} and day={day}
),
parsed_data as (
  select
      egm.id,
      c.id as id_chat,
      egm.agent_full_name,
      egm.agent_name,
      egm.timestamp ts_engagement,
      egm.assigned as is_assigned,
      egm.duration,
      egm.accepted as is_accepted,
      egm.comment,
      egm.rating,
      egm.skills_requested,
      egm.skills_fulfilled as has_skills_fulfilled,
      egm.count as engagement_count,
      egm.started_by as started_by,
      egm.agent_id as id_agent,
      egm.response_time as response_time,
      egm.department_id as id_department,
      c.department_name,
      c.year,
      c.month,
      c.day
  FROM filtered_chats c
  LATERAL VIEW explode (
        from_json(
          engagements,
          'array<struct<id:string, agent_full_name:string,agent_name:string,timestamp:string,assigned:string,duration:string,accepted:string,comment:string,rating:string,skills_requested:string,skills_fulfilled:string,count:string,started_by:string,agent_id:string,response_time:string,department_id:string>>')
      ) as egm
),
calculate_started as (
  select
    pd.*,
    from_utc_timestamp(pd.ts_engagement, 'GMT') as ts_started_utc,
    from_utc_timestamp(pd.ts_engagement, 'GMT-3') as ts_started_local
  from parsed_data pd
)
select
  cs.*,
  from_utc_timestamp(from_unixtime(unix_timestamp(cs.ts_started_utc, 'yyyy-MM-dd HH:mm:ss') + duration, 'yyyy-MM-dd HH:mm:ss'), 'GMT')  as ts_ended_utc,
  from_utc_timestamp(from_unixtime(unix_timestamp(cs.ts_started_local, 'yyyy-MM-dd HH:mm:ss') + duration, 'yyyy-MM-dd HH:mm:ss'), 'GMT')  as ts_ended_local
from calculate_started cs

