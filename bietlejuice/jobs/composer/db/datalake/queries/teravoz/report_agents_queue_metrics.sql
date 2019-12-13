with report_agent_status as (
    select 
        queue, 
        explode(agents) as agents,
        year, month, day
    from datalake_teravoz_raw.report_agent_status
    where year={year} and month={month} and day={day}
),
report_agent_performance as (
    select 
        queue,  
        explode(peer) as peers
    from datalake_teravoz_raw.report_agent_performance
    where year={year} and month={month} and day={day}
)
select
    smallint(st.agents.agent) as extension_number,
    smallint(ifnull(st.queue, pe.queue)) as queue_number,
    ifnull(st.agents.fullName, pe.peers.name) as agent_name,
    format_number(float(split(st.agents.availableTime, ':')[0] +
      split(st.agents.availableTime, ':')[1]/60 +
      split(st.agents.availableTime, ':')[2]/3600), 2) as hours_available_agent,
    format_number(float(split(st.agents.loggedOutTime, ':')[0] +
      split(st.agents.loggedOutTime, ':')[1]/60 +
      split(st.agents.loggedOutTime, ':')[2]/3600), 2) as hours_agent_logged_out,
    format_number(float(split(st.agents.loggedTime, ':')[0] +
      split(st.agents.loggedTime, ':')[1]/60 +
      split(st.agents.loggedTime, ':')[2]/3600), 2) as hours_agent_logged,
    format_number(float(split(st.agents.pausedTime, ':')[0] +
      split(st.agents.pausedTime, ':')[1]/60 +
      split(st.agents.pausedTime, ':')[2]/3600), 2) as hours_agent_paused,
    format_number(float(split(st.agents.talkTime, ':')[0] +
      split(st.agents.talkTime, ':')[1]/60 +
      split(st.agents.talkTime, ':')[2]/3600), 2) as hours_agent_talked,
    smallint(pe.peers.answered) as calls_answered,
    smallint(pe.peers.notAnswered) as calls_missed,
    int(split(pe.peers.averageServiceTime, ':')[0]*3600 +
      split(pe.peers.averageServiceTime, ':')[1]*60 +
       split(pe.peers.averageServiceTime, ':')[2]) as seconds_average_service_time,
    int(split(pe.peers.longestServiceTime, ':')[0]*3600 +
      split(pe.peers.longestServiceTime, ':')[1]*60 +
      split(pe.peers.longestServiceTime, ':')[2]) as seconds_maximum_service_time,
    int(split(pe.peers.minimumServiceTime, ':')[0]*3600 +
      split(pe.peers.minimumServiceTime, ':')[1]*60 +
      split(pe.peers.minimumServiceTime, ':')[2]) as seconds_minimum_service_time,
    current_timestamp as ts_load,
    date(concat(st.year,'-',st.month,'-',st.day)) as dt_created,
    smallint(st.year) as year,
    tinyint(st.month) as month,
    tinyint(st.day) as day
from
    report_agent_status st
    left join
    report_agent_performance pe
    on st.queue=pe.queue and st.agents.fullName=pe.peers.name and st.agents.agent=pe.peers.peer