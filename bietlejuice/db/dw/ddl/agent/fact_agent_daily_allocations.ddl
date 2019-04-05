drop table if exists agent.fact_agent_daily_allocations ;
create table agent.fact_agent_daily_allocations (
  sk_agent integer,
  sk_slot_date integer,
  allocated_slots integer,
  allocated_slots_0 integer,
  max_slots_allocation_available integer,
  area varchar(10),
  sk_agent_region varchar(20),
  sk_slot_date_agent bigint,
  ts_first_visit timestamp,
  sk_contract_type integer,
  ts_load timestamp default getdate()
);