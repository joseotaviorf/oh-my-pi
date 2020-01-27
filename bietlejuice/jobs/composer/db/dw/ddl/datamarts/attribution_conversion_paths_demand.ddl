CREATE TABLE datamarts.attribution_conversion_paths_demand (
	sk_conversion_date int NULL,
	unique_conversion_id bigint NULL,
	path_utm_source_medium varchar(20000) NULL,
	path_utm_source_medium_branded varchar(20000) NULL,
	path_utm_source varchar(20000) NULL,
	path_utm_medium varchar(20000) NULL,
	path_utm_campaign varchar(20000) NULL,
	path_utm_content varchar(20000) NULL,
	path_utm_term varchar(20000) NULL
)
