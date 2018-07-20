drop table if exists growth_staging.amplitude_listings_unique_page_views;
create table growth_staging.amplitude_listings_unique_page_views (
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