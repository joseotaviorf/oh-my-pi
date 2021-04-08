--DROP VIEW IF EXISTS vw_dim_region;
--CREATE OR REPLACE VIEW vw_dim_region as
SELECT
  r.id as sk_region,
  coalesce(r.id, ar.id) as id,
  r.nivel as level,
  coalesce(r.nome,ar.neighbourhood) as name,
  r."macroId" as macro_id,
  r."macroNome" as macro_name,
  r."cidadeId" as city_id,
  coalesce(ar.city, r."cidadeNome") as city_name,
  ar.city_group,
  ar.ddd as city_ddd,
  ar.region_code as region_code,
  ar.region_code_deprecated as region_code_deprecated,
  ar.region_code_inspector as region_code_inspector,
	ar.state as short_region_name,
	case
		when coalesce(r."cidadeNome", ar.city) in ('Rio de Janeiro') then coalesce(r."cidadeNome", ar.city)
		when coalesce(r."cidadeNome", ar.city) in ('Campinas') then coalesce(r."cidadeNome", ar.city)
		when coalesce(r."cidadeNome", ar.city) in
			('São Paulo',
			'São Bernardo do Campo',
			'São Caetano do Sul',
			'Santo André',
			'Guarulhos',
			'Osasco',
			'Barueri') then 'Grande São Paulo'
		else NULL
	end as greater_region,
  ar.regional as regional,
  ar.regional_deprecated as regional_depreacted,
  ar.tier,
  ar.regional_inspection,
  r."criadaEm" as dt_created,
  r."atualizadoEm" as dt_updated,
  r.dt_timestamp::date as dt_timestamp,
  i.dt_first_property_created,
  age.dt_first_booking
FROM
  public.region r
left join
	(
		select
	    	h.regiao_id,
	        min(h.data_criacao) as dt_first_property_created
	    from
		    house h
	    where
	    	h.regiao_id is not null
	    group by
	    	h.regiao_id
	) i
  on i.regiao_id = r.id
left join
	gsheets.aux_regiao ar
	on r.id = ar.id
left join
	(
		select
			h.regiao_id,
			min(b."data") as dt_first_booking
		from
			booking b
		left join
			house h
			on b.imovel_id = h.id
		left join
			region r
			on r.id = h.regiao_id
		group by h.regiao_id
	) age
	on age.regiao_id = r.id
;
