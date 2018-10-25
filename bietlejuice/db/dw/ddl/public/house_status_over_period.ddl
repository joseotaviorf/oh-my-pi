drop table if exists dim_house_listing_status_over_period;
create table dim_house_listing_status_over_period
(
	sk_house_listing bigint NULL,
	id int NULL,
	publication_date date NULL,
	"version" int NULL,
	days varchar(8) NULL,
	"date" date NULL,
	status varchar(30) NULL
);

comment on 
table dim_house_listing_status_over_period
is 'Contains each status version of properties over time. Used only in models that have status history'
