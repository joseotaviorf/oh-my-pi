drop table if exists growth.amplitude_engaged_users;
create table growth.amplitude_engaged_users (
	_year integer,
	_month integer,
	_week integer,
	_day integer,
	region varchar(255),
	city varchar(255),
	partial boolean,
	daily_count bigint,
	weekly_count bigint,
	monthly_count bigint,
	yearly_count bigint
);