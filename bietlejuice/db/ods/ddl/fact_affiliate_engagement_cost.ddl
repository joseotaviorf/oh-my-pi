drop table if exists public.fact_affiliate_engagement_cost;

create table public.fact_affiliate_engagement_cost (
      data_operacao date,
      usuario_id integer,
      dadosafiliado_id integer,
      dadosagente_id integer,
      region_id integer,
      afiliado_ativo smallint,
      affiliate_type varchar(32),
      tipo_comissao varchar(64),
      comissao_lead decimal(10,2),
      comissao_por_locacao decimal(10,2),
      comissao_indicacao_afiliado decimal(10,2),
      comissao_total decimal(10,2)
);
