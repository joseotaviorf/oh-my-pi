select
  changelog as change_log,
  expand,
  fields,
  id,
  key,
  self,
  year,
  month,
  day
from datalake_jira_raw.issues
where year = {year}
  and month = {month}
  and day = {day}