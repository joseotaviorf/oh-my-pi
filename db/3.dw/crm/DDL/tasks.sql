drop table if exists crm.tasks;
create table if not exists crm.tasks
(
  _id varchar(25),  
  type varchar(100),
  start_date timestamp,
  performed_date timestamp,
  property_id integer,
  author_id integer,
  author_name varchar(255),
  assignee_id integer,
  assignee_name varchar(255),
  workgroup_id varchar(50),
  workgroup_title varchar(255),
  recipient_id integer,
  status varchar(50),
  description varchar(255),
  title varchar(255)
)