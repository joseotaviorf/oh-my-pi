drop view if exists vw_fact_affiliate_engagement_cost;
create view vw_fact_affiliate_engagement_cost as
    SELECT
        data_operacao,
        usuario_id,
        dadosafiliado_id,
        dadosagente_id,
        region_id,
        afiliado_ativo,
        affiliate_type,
        tipo_comissao,
        comissao_lead,
        comissao_por_locacao,
        comissao_indicacao_afiliado,
        comissao_total,
        now()::timestamp as ts_load
    FROM
      public.fact_affiliate_engagement_cost
;