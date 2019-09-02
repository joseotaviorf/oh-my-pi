select 
  smallint(st.agent) as id_agent,
  smallint(pe.peer) as internal_phone_number,
  smallint(ifnull(pe.queue, st.queue)) as queue_number,
  ifnull(pe.name, st.fullName) as name,
  smallint(pe.answered) as calls_answered,
  smallint(pe.notAnswered) as calls_missed,
  int(date_format(pe.averageServiceTime, "HH")*3600 +
      date_format(pe.averageServiceTime, "mm")*60 + 
       date_format(pe.averageServiceTime, "ss")) as seconds_average_attendance,
  int(date_format(pe.longestServiceTime, "HH")*3600 +
      date_format(pe.longestServiceTime, "mm")*60 + 
      date_format(pe.longestServiceTime, "ss")) as seconds_maximum_attendance,
  int(date_format(pe.minimumServiceTime, "HH")*3600 +
      date_format(pe.minimumServiceTime, "mm")*60 + 
      date_format(pe.minimumServiceTime, "ss")) as seconds_minimum_attendance,
  int(date_format(st.availableTime, "HH")*3600 +
      date_format(st.availableTime, "mm")*60 + 
      date_format(st.availableTime, "ss")) as seconds_available_agent,
  int(date_format(st.loggedOutTime, "HH")*3600 +
      date_format(st.loggedOutTime, "mm")*60 + 
      date_format(st.loggedOutTime, "ss")) as seconds_agent_logged_out,
  int(date_format(st.loggedTime, "HH")*3600 +
      date_format(st.loggedTime, "mm")*60 + 
      date_format(st.loggedTime, "ss")) as seconds_agent_logged,
  int(date_format(st.pausedTime, "HH")*3600 +
      date_format(st.pausedTime, "mm")*60 + 
      date_format(st.pausedTime, "ss")) as seconds_agent_paused,
   int(date_format(st.talkTime, "HH")*3600 +
      date_format(st.talkTime, "mm")*60 + 
      date_format(st.talkTime, "ss")) as seconds_agent_talked,
  current_timestamp as ts_load,
  ifnull(pe.year, st.year) as year,
  ifnull(pe.month, st.month) as month,
  ifnull(pe.day, st.day) as day
from 
  (select queue, year, month, day, inline(peer) from datalake_teravoz_raw.report_agent_performance 
      where year="{year}" and month="{month}" and day="{day}") pe 
full join 
  (select queue, year, month, day, inline(agents) from datalake_teravoz_raw.report_agent_status
      where year="{year}" and month="{month}" and day="{day}") st 
on pe.queue=st.queue and pe.name=st.fullName