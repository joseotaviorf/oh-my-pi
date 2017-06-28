/*

select available_date, count(1) from agents_schedule 
where available_date in ('2017-05-08', '2017-05-15', '2017-05-01') 
group by available_date; -- , '2017-05-04', '2017-05-05', '2017-05-06', '2017-05-07');

*/
-- delete
 select count(1)
from agents_schedule 
where available_date 
in ('2017-05-23');

insert into public.agents_schedule
SELECT 
	"row_number", 
	agent_user_id, 
	available_date + '7 days'::interval as available_date, 
	region_id, 
	region_name, 
	slot_id, 
	slot_start, 
	slot_end, 
	slot_available, 
	slot_status, 
	"timestamp" + '7 days'::interval  as "timestamp"
FROM public.agents_schedule
where available_date in ('2017-05-16');


