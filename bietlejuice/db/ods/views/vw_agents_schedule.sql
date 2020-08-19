--drop view if exists vw_agents_schedule;
--create view vw_agents_schedule as
SELECT
  row_number,
  agent_user_id,
  available_date,
  region_id,
  region_name,
  slot_id,
  slot_start,
  slot_end,
  slot_available,

  case
  	when slot_status in (
      'Available',
      'AgentHasAppointment',
      'InsufficientTimeWindow',
      'InTransit',
      'BestAvailable'
    ) then 'Available'
    when slot_status in (
      'UnavailableAgent',
      'UnavailableProperty'
    ) then 'Unavailable'
  end as slot_availability,

  slot_status,
  "timestamp"
FROM
  public.agents_schedule
;