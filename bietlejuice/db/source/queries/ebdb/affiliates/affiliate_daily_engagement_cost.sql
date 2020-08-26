-- INDICAÇÕES DE IMÓVEL
select
	date_format(substring(occ.dataOperacao, 1, 10), '%Y-%m-%d') as dt_cost,
	cast(u.id as SIGNED) 										as sk_user,
	cast(i.regiao_id as SIGNED) 								as sk_region,
	u.dadosAfiliado_id 											as sk_user_affiliate,
	l.dadosAgente_id 											as sk_user_agent,
	case
		when l.affiliateType = 'Doorman'
			and l.dadosAgente_id is not null    then 'Doorman & Agent'
		when l.dadosAgente_id is not null       then 'Agent'
		else coalesce(l.affiliateType, 'N/A')
	end 														as affiliate_type,
	occ.tipo 													as commission_type,
	sum(occ.valor) 												as value_brl,
	timestamp('{str_date}')										as ts_load
from
	OperacaoContaCorrente occ
left join
	Usuario u on
		u.ContaCorrente_id = occ.ContaCorrente_id
join
	Imovel i on
		i.id = occ.imovel_id
left join
	ConversaoLead cl on
		cl.imovel_id = occ.imovel_id
join
	Lead l on
		l.id = cl.leadConvertido_id
where
	occ.tipo in ('valorFixoPorIndicacaoDeImovel',
		'porcentagemPorIndicacaoDeImovel',
		'comissaoUnicaSobreAfiliadoIndicado')
	and date(occ.dataCriacao) = date('{str_date}')
group by
	1, 2, 3, 4, 5, 6, 7

union all

-- MEMBER GET MEMBER
select
	date_format(substring(res.date_operation, 1, 10), '%Y-%m-%d') 	as dt_cost,
	cast(res.user_id as SIGNED) 									as sk_user,
	cast(res.region_id as SIGNED) 									as sk_region,
	res.dadosafiliado_id 											as sk_user_affiliate,
	u.dadosagente_id												as dadosagente_id,
	case
		when da.affiliateType = 'Doorman'
			and u.dadosagente_id is not null 	then 'Doorman & Agent'
		when u.dadosagente_id is not null 		then 'Agent'
		else coalesce(da.affiliateType, 'N/A')
	end 															as affiliate_type,
	'comissaoSobreAfiliadoIndicado' 								as commission_type,
	sum(res.value_brl * 0.1) 										as value_brl,
	timestamp('{str_date}')											as ts_load
from
	(
	select
		resf.date_operation		as date_operation,
		uqi.id 					as "user_id",
		resf.region_id			as region_id,
		uqi.dadosAfiliado_id 	as dadosafiliado_id,
		sum(resf.value_brl) 	as value_brl
	from
		(
		select
			occ.dataOperacao 	as date_operation,
			u.id 				as user_id,
			i.regiao_id 		as region_id,
			u.dadosAfiliado_id 	as dadosafiliado_id,
			u.dadosagente_id 	as dadosagente_id,
			(
			select
				max(da_aud_int.REV)
			from
				DadosAfiliado_AUD da_aud_int
			join UsuarioRevisionEntity da_ure_int on
				da_aud_int.REV = da_ure_int.id
			where
				da_aud_int.id = u.dadosAfiliado_id
				and from_unixtime(da_ure_int.timestamp / 1000) <= occ.dataOperacao
			) as da_max_rev,
			sum(occ.valor) as value_brl
		from
			OperacaoContaCorrente occ
		left join Usuario u on
			u.ContaCorrente_id = occ.ContaCorrente_id
		join Imovel i on
			i.id = occ.imovel_id
		where
			occ.tipo in ('valorFixoPorIndicacaoDeImovel',
			'porcentagemPorIndicacaoDeImovel')
			and date(occ.dataCriacao) = date('{str_date}')
		group by
			1, 2, 3, 4, 5, 6
		) resf
	join DadosAfiliado_AUD da_aud on
		da_aud.id = resf.dadosAfiliado_id
		and da_aud.REV = resf.da_max_rev
		and resf.date_operation <= DATE_ADD(da_aud.inicioAtuacao, INTERVAL 6 MONTH)
	join Usuario uqi on
		uqi.id = da_aud.indicadoPor_id
	group by
		1, 2, 3, 4
	) res
join
	Usuario u on
		u.id = res.user_id
join
	DadosAfiliado da on
		da.id = res.dadosafiliado_id
group by
	1, 2, 3, 4, 5, 6, 7