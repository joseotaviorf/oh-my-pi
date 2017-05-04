DROP VIEW IF EXISTS vw_net_revenue_fine_for_delay_in_payment CASCADE;
CREATE VIEW vw_net_revenue_fine_for_delay_in_payment AS WITH leads AS (
    SELECT
      id,
      imovel_id,
      date_trunc('month', ("dataEntrada") :: TIMESTAMP WITH TIME ZONE)  AS entrance_date,
      date_trunc('month', ("dataRescisao") :: TIMESTAMP WITH TIME ZONE) AS termination_date,
      date_trunc('month', (lead("dataEntrada")
      OVER (
        PARTITION BY imovel_id
        ORDER BY id )) :: TIMESTAMP WITH TIME ZONE)                     AS lead_date
    FROM contract
    WHERE tipo <> 'DealOnly'
          AND status <> 'Cancelado'
          AND coalesce("dataRescisao", "dataFimContratoPrevisto") > coalesce("dataEntrada", "dataInicio")
)
SELECT
  c.id                                                                           AS contract_id,
  c.imovel_id,
  date_trunc('month' :: TEXT, (df."Competência") :: TIMESTAMP WITHOUT TIME ZONE) AS date_range,
  df."Valor Bruto"                                                               AS cost
FROM (files.delay_fine df
  JOIN leads c ON ((((df."Fornecedor") :: TEXT = ((c.imovel_id) :: CHARACTER VARYING) :: TEXT) AND
                    (((df."Competência") :: TIMESTAMP WITHOUT TIME ZONE >= c.entrance_date) AND
                     ((df."Competência") :: TIMESTAMP WITHOUT TIME ZONE <=
                      COALESCE(c.termination_date, c.lead_date, date_trunc('month' :: TEXT, now())))))));

