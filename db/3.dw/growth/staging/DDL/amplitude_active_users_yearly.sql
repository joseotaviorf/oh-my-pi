drop table if exists growth_staging.amplitude_active_users_all_year;
create table growth_staging.amplitude_active_users_all_year (
	_year integer,
	_month integer,
	_week integer,
	_day integer,
	region varchar(255),
	city varchar(255),
	partial boolean,
	yearly_count bigint
);