-- list of leads and prospects we want to keep for the test set

create view vw_select_lead AS
select l.id from Lead l
WHERE
	l.criadoEm > '2017-01-01'
limit 100


create view vw_select_prospect AS
select im.id
FROM 
	Imovel im
	join ConversaoLead cl
		on cl.imovel_id = im.id 
	where cl.leadConvertido_id is null
	limit 10

-- creating the views, filtering on the leads and prospects we listed above

create view vw_Imovel_test AS
select * from Imovel i
where i.id in 
	(
		select im.id
		FROM
			vw_select_lead sl
			inner join ConversaoLead cl
				on cl.leadConvertido_id = sl.id
			inner join Imovel im 
				on cl.imovel_id = im.id
		
		UNION
		
		select sp.id
		FROM 
			vw_select_prospect sp
	) 

create view vw_Lead_test AS
select * from Lead l
where l.id in 
	(
		select sl.id
		FROM
			vw_select_lead sl
	) 
	
create view vw_Agendamento_test AS
select * from Agendamento a
where a.id in 
	(
		select ag.id
		FROM	
			Agendamento ag
			inner join vw_Imovel_test i
				on i.id = ag.imovel_id
				
	) 