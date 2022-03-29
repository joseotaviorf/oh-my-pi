-- DEPRECATED. Please use `datalake_ebdb_agents.agent_contract`
-- composer/db/datalake/queries/enrich_ebdb_agents/enrich/agent_contract.sql
select
	aud.id,
	from_unixtime(ure.TIMESTAMP/1000) as timestamp,
	workContract_id
from DadosAgente_AUD aud
join UsuarioRevisionEntity ure on aud.REV = ure.id
order by 1, 2