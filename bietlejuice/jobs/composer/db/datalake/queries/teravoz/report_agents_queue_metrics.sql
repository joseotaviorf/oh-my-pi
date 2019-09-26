select
    st.agent as extension_number,
    st.queue as queue_number,
    ifnull(st.fullName, pe.name) as agent_name,
    format_number(float(split(st.availableTime, ":")[0] +
      split(st.availableTime, ":")[1]/60 +
      split(st.availableTime, ":")[2]/3600), 2) as hours_available_agent,
    format_number(float(split(st.loggedOutTime, ":")[0] +
      split(st.loggedOutTime, ":")[1]/60 +
      split(st.loggedOutTime, ":")[2]/3600), 2) as hours_agent_logged_out,
    format_number(float(split(st.loggedTime, ":")[0] +
      split(st.loggedTime, ":")[1]/60 +
      split(st.loggedTime, ":")[2]/3600), 2) as hours_agent_logged,
    format_number(float(split(st.pausedTime, ":")[0] +
      split(st.pausedTime, ":")[1]/60 +
      split(st.pausedTime, ":")[2]/3600), 2) as hours_agent_paused,
    format_number(float(split(st.talkTime, ":")[0] +
      split(st.talkTime, ":")[1]/60 +
      split(st.talkTime, ":")[2]/3600), 2) as hours_agent_talked,
    smallint(pe.answered) as calls_answered,
    smallint(pe.notAnswered) as calls_missed,
    int(split(pe.averageServiceTime, ":")[0]*3600 +
      split(pe.averageServiceTime, ":")[1]*60 +
       split(pe.averageServiceTime, ":")[2]) as seconds_average_service_time,
    int(split(pe.longestServiceTime, ":")[0]*3600 +
      split(pe.longestServiceTime, ":")[1]*60 +
      split(pe.longestServiceTime, ":")[2]) as seconds_maximum_service_time,
    int(split(pe.minimumServiceTime, ":")[0]*3600 +
      split(pe.minimumServiceTime, ":")[1]*60 +
      split(pe.minimumServiceTime, ":")[2]) as seconds_minimum_service_time,
    current_timestamp as ts_load,
    date(concat(st.year,"-",st.month,"-",st.day)) as dt_created,
    smallint(st.year) as year,
    tinyint(st.month) as month,
    tinyint(st.day) as day
from
    (select queue, year, month, day, inline(agents)
    from datalake_teravoz_raw.report_agent_status
    where year="{year}" and month="{month}" and day="{day}") st
    left join
    (select queue, year, month, day, inline(peer)
    from datalake_teravoz_raw.report_agent_performance
    where year="{year}" and month="{month}" and day="{day}") pe
    on st.queue=pe.queue and st.fullName=pe.name and st.agent=pe.peer