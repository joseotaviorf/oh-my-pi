drop table if exists unit_economics.base_ticket_task;

create table unit_economics.base_ticket_task (
  property_id int8 ,
  dt date,
  qt int,
  group_name varchar(255)
)