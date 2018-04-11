DROP TABLE IF EXISTS growth.agents_performance_ranking;
CREATE TABLE growth.agents_performance_ranking (
  sk_date int8,
	agent_id int8,
	agent_name varchar(255),
	greater_region varchar(100),
	bookings numeric(10,4),
	contracts numeric(10,4),
	conversion numeric(10,4),
	ranking numeric(10,4),
	average_conversion numeric(10,4),
	top_percentile numeric(10,4),
	yellow_flag int4,
	commission numeric(10,4),
	gold_threshold numeric(10,4),
	silver_threshold numeric(10,4),
	yellow_flag_threshold numeric(10,4),
	dt_ranking date
) ;
