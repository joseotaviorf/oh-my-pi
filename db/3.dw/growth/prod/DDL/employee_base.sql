--drop table if exists growth.employee_base;
create table growth.employee_base(
	name varchar(255),
	category varchar(255),
	dt_updated date
)