--drop view if exists vw_dim_rent_flow_taxonomy;
--create view vw_dim_rent_flow_taxonomy as
select
	cast(id as bigint) as sk_rent_flow_taxonomy,
	cast(id as bigint) as id_rent_flow_taxonomy,
	Category as mkt_category,
	Flow as mkt_flow,
	Completion as mkt_completion,
	Origin as mkt_origin,
	Channel as mkt_channel,
	Medium as mkt_medium,
	Source as mkt_source,
	Platform as mkt_platform,
	now()::timestamp as ts_load
from gsheets.taxonomy_demand
;