drop table if exists growth_staging.amplitude_active_users_yearly;
create table growth_staging.amplitude_active_users_yearly (
	_year integer,
	_month integer,
	_week integer,
	_day integer,
	region varchar(255),
	city varchar(255),
	partial boolean,
	yearly_count bigint
);