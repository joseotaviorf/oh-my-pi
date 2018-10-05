drop table if exists experiments;
create table experiments (
	experiment_name varchar(255),
	experiment_type varchar(5),
	status varchar(10),
	details varchar(50),
	sessions int,
	start_date date SORTKEY, 
	end_date date,
	dt_timestamp timestamp
);

