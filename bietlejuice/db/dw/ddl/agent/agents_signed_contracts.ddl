drop table if exists agent.agents_signed_contracts;
create table agent.agents_signed_contracts (
	sk_contract_signed_date integer,
	sk_house_listing integer,
	sk_contract integer,
	agent_name varchar(255),
	owner_name varchar(255),
	owner_cpf varchar(255),
	dt_contract_signed date,
	contract_status varchar(50),
	short_id_property integer,
	property_region varchar(255),
	number_of_agents_contract integer,
	renting_value numeric(10,4),
	name_visitor varchar(255),
	contract_commission numeric(10,4),
	endereco varchar(255)
)
;