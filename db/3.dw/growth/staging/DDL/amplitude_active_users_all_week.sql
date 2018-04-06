drop table if exists growth_staging.amplitude_active_users_all_week;
create table growth_staging.amplitude_active_users_all_week (
	_year integer,
	_month integer,
	_week integer,
	_day integer,
	region varchar(255),
	city varchar(255),
	partial boolean,
	weekly_count bigint
);