drop table if exists agent.fact_agent_hourly_allocations ;
create table agent.fact_agent_hourly_allocations (
  sk_agent integer,
  sk_slot_date integer,
  sk_slot_date_hour bigint,
  sk_agent_region varchar(20),
  sk_slot_date_agent bigint,
  id_work_contract integer,
  ts_slot_hour timestamp,
  allocated_slots integer,
  allocated_slots_0 integer,
  is_allocation_available boolean,
  area varchar(10),
  ts_first_visit timestamp,
  ts_load timestamp default getdate()
);