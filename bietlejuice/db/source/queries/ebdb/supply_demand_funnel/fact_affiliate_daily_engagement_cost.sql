select
	cast(date_format(substring(res.date_operation, 1, 10), '%Y%m%d') as SIGNED) as sk_date,
	cast(res.user_id as SIGNED) as sk_user,
	cast(res.region_id as SIGNED) as sk_region,
	res.dadosafiliado_id as sk_user_affiliate,
	u_aud.dadosagente_id as sk_user_agent,
	da_aud.ativo as is_affiliate_active,
	case when da_aud.affiliateType = 'Doorman' and u_aud.dadosagente_id is not null then 'Doorman & Agent'
	     when u_aud.dadosagente_id is not null then 'Agent'
		 else da_aud.affiliateType end as affiliate_type,
	res.commission_type,
	sum(res.value_brl) as value_brl
from (
        select
            occ.tipo as commission_type,
            occ.dataOperacao as date_operation,
            u.id as user_id,
            i.regiao_id as region_id,
            u.dadosAfiliado_id as dadosafiliado_id,
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
            sum(occ.valor) as value_brl
        from OperacaoContaCorrente occ
        left join Usuario u on u.ContaCorrente_id = occ.ContaCorrente_id
        join Imovel i on i.id = occ.imovel_id
        where occ.tipo in ('valorFixoPorIndicacaoDeImovel', 'porcentagemPorIndicacaoDeImovel')
        group by 1,2,3,4,5,6,7
    ) res
    join DadosAfiliado_AUD da_aud on da_aud.id = res.dadosAfiliado_id and da_aud.REV = res.da_max_rev
    join Usuario_AUD u_aud on u_aud.id = res.user_id and u_aud.REV = res.u_max_rev
    group by 1, 2, 3, 4, 5, 6, 7, 8
union all
select
	cast(date_format(substring(res.date_operation, 1, 10), '%Y%m%d') as SIGNED) as sk_date,
	cast(res.user_id as SIGNED) as sk_user,
	cast(res.region_id as SIGNED) as sk_region,
	res.dadosafiliado_id as sk_user_affiliate,
	u_aud.dadosagente_id,
	da_aud.ativo as is_affiliate_active,
	case when da_aud.affiliateType = 'Doorman' and u_aud.dadosagente_id is not null then 'Doorman & Agent'
	     when u_aud.dadosagente_id is not null then 'Agent'
		 else da_aud.affiliateType end as affiliate_type,
	'comissaoSobreAfiliadoIndicado' as commission_type,
	sum(res.value_brl * 0.1) as value_brl
from (
	select
		resf.date_operation,
		uqi.id as "user_id",
		resf.region_id,
		uqi.dadosAfiliado_id as dadosafiliado_id,
		(select max(da_aud_int.REV)
		 from DadosAfiliado_AUD da_aud_int
		 join UsuarioRevisionEntity da_ure_int
		   on da_aud_int.REV = da_ure_int.id
	     where da_aud_int.id = uqi.dadosAfiliado_id
		   and from_unixtime(da_ure_int.timestamp/1000) <= resf.date_operation) as da_max_rev,
	    (select max(ua_aud_int.REV)
	     from Usuario_AUD ua_aud_int
	     join UsuarioRevisionEntity ua_ure_int
	       on ua_aud_int.REV = ua_ure_int.id
		 where ua_aud_int.id = uqi.id
		   and from_unixtime(ua_ure_int.timestamp/1000) <= resf.date_operation) as u_max_rev,
		 sum(resf.value_brl) as value_brl
	from (
            select
                occ.dataOperacao as date_operation,
                u.id as user_id,
                i.regiao_id as region_id,
                u.dadosAfiliado_id as dadosafiliado_id,
                u.dadosagente_id as dadosagente_id,
                (select max(da_aud_int.REV)
                 from DadosAfiliado_AUD da_aud_int
                 join UsuarioRevisionEntity da_ure_int
                   on da_aud_int.REV = da_ure_int.id
                 where da_aud_int.id = u.dadosAfiliado_id
                   and from_unixtime(da_ure_int.timestamp/1000) <= occ.dataOperacao) as da_max_rev,
                sum(occ.valor) as value_brl
            from OperacaoContaCorrente occ
            left join Usuario u on u.ContaCorrente_id = occ.ContaCorrente_id
            join Imovel i on i.id = occ.imovel_id
            where occ.tipo in ('valorFixoPorIndicacaoDeImovel', 'porcentagemPorIndicacaoDeImovel')
            group by 1,2,3,4,5,6
        ) resf
        join DadosAfiliado_AUD da_aud on da_aud.id = resf.dadosAfiliado_id and da_aud.REV = resf.da_max_rev
        join Usuario uqi on uqi.id = da_aud.indicadoPor_id
        group by 1,2,3,4,5,6
    ) res
    join Usuario_AUD u_aud on u_aud.id = res.user_id and u_aud.REV = res.u_max_rev
    join DadosAfiliado_AUD da_aud on da_aud.id = res.dadosafiliado_id and da_aud.REV = res.da_max_rev
    group by 1, 2, 3, 4, 5, 6, 7, 8