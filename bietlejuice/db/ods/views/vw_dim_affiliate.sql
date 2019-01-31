DROP VIEW if exists public.vw_dim_affiliate;

CREATE VIEW public.vw_dim_affiliate as
 select
 	id as sk_affiliate,
 	id as id_affiliate,
	inicioAtuacao as ts_joined_program,
	tipoAfiliado as category,
	cidadeAtuacao  as work_city,
	ativo as is_active,
	atualizadoEm as ts_updated,
	criadoEm as ts_created,
	numeroCreci as creci_number,
	origin as origin,
	affiliateType as "type",
	now() as ts_load
 from affiliate
;

  