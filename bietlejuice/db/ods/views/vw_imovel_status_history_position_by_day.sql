--drop view if exists vw_imovel_status_history_position_by_day;
--create view vw_imovel_status_history_position_by_day as
select
	id,
    date,
    status_time,
    status_history as status
from
	imovel_status_full_history
where
	last_position_date_flag
    and all_status_date_position_flag
;