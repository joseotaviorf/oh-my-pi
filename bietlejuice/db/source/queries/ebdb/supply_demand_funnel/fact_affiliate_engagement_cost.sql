select
	res.data_operacao,
	res.usuario_id,
	res.dadosafiliado_id,
	res.dadosagente_id,
	res.region_id,
	da_aud.ativo as afiliado_ativo,
	case when da_aud.affiliateType = 'Doorman' and u_aud.dadosagente_id is not null then 'Doorman & Agent'
	     when u_aud.dadosagente_id is not null then 'Agent'
		 else da_aud.affiliateType end as "affiliate_type",
	res.tipo_comissao,
	sum(case when res.tipo_comissao = 'valorFixoPorIndicacaoDeImovel' then res.valor_comissao end) as comissao_lead,
	sum(case when res.tipo_comissao = 'porcentagemPorIndicacaoDeImovel' then res.valor_comissao end) as comissao_por_locacao,
	sum(case when res.tipo_comissao = 'comissaoSobreAfiliadoIndicado' then res.valor_comissao end) as comissao_indicacao_afiliado,
	sum(res.valor_comissao) as comissao_total
from (
	select
		occ.tipo as "tipo_comissao",
		occ.dataOperacao as "data_operacao",
		u.id as "usuario_id",
		i.regiao_id as "region_id",
		u.dadosAfiliado_id as "dadosafiliado_id",
		u.dadosagente_id as "dadosagente_id",
		(select max(da_aud_int.REV)
		 from DadosAfiliado_AUD da_aud_int
		 join UsuarioRevisionEntity da_ure_int
		   on da_aud_int.REV = da_ure_int.id
	     where da_aud_int.id = u.dadosAfiliado_id
		   and from_unixtime(da_ure_int.timestamp/1000) <= occ.dataOperacao) as da_max_rev,
        (select max(ua_aud_int.REV)
         from Usuario_AUD ua_aud_int
         join UsuarioRevisionEntity ua_ure_int
           on ua_aud_int.REV = ua_ure_int.id
		 where ua_aud_int.id = u.id
		   and from_unixtime(ua_ure_int.timestamp/1000) <= occ.dataOperacao) as u_max_rev,
		sum(occ.valor) as "valor_comissao"
	from OperacaoContaCorrente occ
	join Usuario u on u.ContaCorrente_id = occ.ContaCorrente_id
	join Imovel i on i.id = occ.imovel_id
	where occ.tipo in ('valorFixoPorIndicacaoDeImovel', 'porcentagemPorIndicacaoDeImovel')
	group by 1,2,3,4,5,6,7,8
	union all
	select
		'comissaoSobreAfiliadoIndicado' as "tipo_comissao",
		occ.dataOperacao as "data_operacao",
		uqi.id as "usuario_id",
		i.regiao_id as "region_id",
		uqi.dadosAfiliado_id as "dadosafiliado_id",
		uqi.dadosagente_id as "dadosagente_id",
		(select max(da_aud_int.REV)
		 from DadosAfiliado_AUD da_aud_int
		 join UsuarioRevisionEntity da_ure_int
		   on da_aud_int.REV = da_ure_int.id
	     where da_aud_int.id = uqi.dadosAfiliado_id
		   and from_unixtime(da_ure_int.timestamp/1000) <= occ.dataOperacao) as da_max_rev,
        (select max(ua_aud_int.REV)
         from Usuario_AUD ua_aud_int
         join UsuarioRevisionEntity ua_ure_int
           on ua_aud_int.REV = ua_ure_int.id
		 where ua_aud_int.id = uqi.id
		   and from_unixtime(ua_ure_int.timestamp/1000) <= occ.dataOperacao) as u_max_rev,
		sum(occ.valor * 0.1) as "valor_comissao"
	from OperacaoContaCorrente occ
	join Usuario u on u.ContaCorrente_id = occ.ContaCorrente_id
	join DadosAfiliado da on da.id = u.dadosAfiliado_id
	join Imovel i on i.id = occ.imovel_id
	join Usuario uqi on uqi.id = da.indicadoPor_id
	where occ.tipo in ('valorFixoPorIndicacaoDeImovel', 'porcentagemPorIndicacaoDeImovel')
	group by 1,2,3,4,5,6,7,8
) res
join DadosAfiliado_AUD da_aud on da_aud.id = res.dadosAfiliado_id and da_aud.REV = res.da_max_rev
join Usuario_AUD u_aud on u_aud.id = res.usuario_id and u_aud.REV = res.u_max_rev
group by 1, 2, 3, 4, 5, 6, 7, 8