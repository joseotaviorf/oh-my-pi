with agent_names as (
	select distinct
		agent_name,
		agent_id
	from
	growth.agents_performance_ranking
),
total as (
	select
		a.agent_name as "Nome Agente",
		(
			coalesce(s12.yellow_flag ,0) +
			coalesce(s11.yellow_flag ,0) +
			coalesce(s10.yellow_flag ,0) +
			coalesce(s9.yellow_flag ,0) +
			coalesce(s8.yellow_flag ,0) +
			coalesce(s7.yellow_flag ,0) +
			coalesce(s6.yellow_flag ,0) +
			coalesce(s5.yellow_flag ,0) +
			coalesce(s4.yellow_flag ,0) +
			coalesce(s3.yellow_flag ,0) +
			coalesce(s2.yellow_flag ,0) +
			coalesce(s1.yellow_flag ,0)
		) as "Total",
		(
			coalesce(s4.yellow_flag ,0) +
			coalesce(s3.yellow_flag ,0) +
			coalesce(s2.yellow_flag ,0) +
			coalesce(s1.yellow_flag ,0)
		) as "Total - 4 Semanas Recentes",
		s12.yellow_flag as "2017-11-20",
		s11.yellow_flag as "2017-11-27",
		s10.yellow_flag as "2017-12-04",
		s9.yellow_flag as "2017-12-11",
		s8.yellow_flag as "2017-12-18",
		s7.yellow_flag as "2017-12-25",
		s6.yellow_flag as "2018-01-01",
		s5.yellow_flag as "2018-01-08",
		s4.yellow_flag as "2018-01-15",
		s3.yellow_flag as "2018-01-22",
		s2.yellow_flag as "2018-01-29",
		s1.yellow_flag as "2018-02-05"
	from
		agent_names a
	left join
		growth.agents_performance_ranking s1
		on s1.agent_id = a.agent_id and s1.dt_ranking='2018-02-05'::date
	left join
		growth.agents_performance_ranking s2
		on s2.agent_id = a.agent_id and s2.dt_ranking='2018-01-29'::date
	left join
		growth.agents_performance_ranking s3
		on s3.agent_id = a.agent_id and s3.dt_ranking='2018-01-22'::date
	left join
		growth.agents_performance_ranking s4
		on s4.agent_id = a.agent_id and s4.dt_ranking='2018-01-15'::date
	left join
		growth.agents_performance_ranking s5
		on s5.agent_id = a.agent_id and s5.dt_ranking='2018-01-08'::date
	left join
		growth.agents_performance_ranking s6
		on s6.agent_id = a.agent_id and s6.dt_ranking='2018-01-01'::date
	left join
		growth.agents_performance_ranking s7
		on s7.agent_id = a.agent_id and s7.dt_ranking='2017-12-25'::date
	left join
		growth.agents_performance_ranking s8
		on s8.agent_id = a.agent_id and s8.dt_ranking='2017-12-18'::date
	left join
		growth.agents_performance_ranking s9
		on s9.agent_id = a.agent_id and s9.dt_ranking='2017-12-11'::date
	left join
		growth.agents_performance_ranking s10
		on s10.agent_id = a.agent_id and s10.dt_ranking='2017-12-04'::date
	left join
		growth.agents_performance_ranking s11
		on s11.agent_id = a.agent_id and s11.dt_ranking='2017-11-27'::date
	left join
		growth.agents_performance_ranking s12
		on s12.agent_id = a.agent_id and s12.dt_ranking='2017-11-20'::date
)
select
	*
from
	total
order by
	"Total" desc