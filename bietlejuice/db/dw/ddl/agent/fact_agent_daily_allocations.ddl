drop table if exists agent.fact_agent_daily_allocations ;
create table agent.fact_agent_daily_allocations (
  sk_agent integer,
  sk_slot_date integer,
  sk_agent_region varchar(20),
  sk_slot_date_agent bigint,
  id_work_contract integer,
  allocated_slots integer,
  allocated_slots_0 integer,
  max_slots_allocation_available integer,
  area varchar(10),
  ts_first_visit timestamp,
  ts_load timestamp default getdate()
);