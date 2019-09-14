select
    *,
    extract(year from event_timestamp)::int as year,
    extract(month from event_timestamp)::int as month,
    extract(day from event_timestamp)::int as day
from public."Event"
where 
    extract(year from event_timestamp) = {year} 
    and extract(month from event_timestamp) = {month}
    and extract(day from event_timestamp) = {day}