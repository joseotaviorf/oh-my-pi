DROP VIEW IF EXISTS vw_net_revenue_brokerage_fee CASCADE;
CREATE VIEW vw_net_revenue_brokerage_fee AS
  WITH c_dates AS (
      SELECT
        contract.id                                             AS contract_id,
        contract.imovel_id,
        contract."criadoEm"                                     AS created_date,
        contract."dataAssinado"                                 AS signature_date,
        coalesce(contract."dataEntrada", contract."dataInicio") AS contract_init_date,
        contract.status,
        CASE
        WHEN contract.status IN ('Ativo', 'PreAssinaturas')
          THEN COALESCE((contract."dataRescisao") :: TIMESTAMP WITHOUT TIME ZONE,
                        (contract."dataFimContratoPrevisto") :: TIMESTAMP WITHOUT TIME ZONE, contract."atualizadoEm")
        WHEN contract.status IN ('Cancelado', 'Finalizado')
          THEN COALESCE((contract."dataRescisao") :: TIMESTAMP WITHOUT TIME ZONE, contract."atualizadoEm")
        ELSE contract."atualizadoEm"
        END                                                     AS contract_date
      FROM contract
  ), all_dates AS (
      SELECT DISTINCT
        cd.contract_id,
        cd.imovel_id,
        cd.created_date,
        cd.signature_date,
        cd.contract_date,
        date_trunc('month', (dd.date) :: TIMESTAMP WITH TIME ZONE) AS date_range
      FROM dim_date dd
        JOIN c_dates cd
          ON ((dd.date >= (date_trunc('month' :: TEXT, (cd.contract_init_date) :: TIMESTAMP WITH TIME ZONE)) :: DATE)
              AND
              (dd.date <=
               CASE
               WHEN (((cd.status) :: TEXT = ANY
                      (ARRAY [('Cancelado' :: CHARACTER VARYING) :: TEXT, ('Finalizado' :: CHARACTER VARYING) :: TEXT]))
                     OR (cd.contract_init_date IS NULL))
                 THEN ((date_trunc('month', cd.contract_date)) :: DATE) :: TIMESTAMP WITHOUT TIME ZONE
               ELSE ((date_trunc('month', (cd.contract_init_date) :: TIMESTAMP WITH TIME ZONE)) :: DATE +
                     (30 * '1 mon' :: INTERVAL))
               END))
  ), ct AS (
      SELECT
        co.id                                          AS contract_id,
        co.imovel_id,
        co."valorAluguel"                              AS rent_value,
        (ad.date_range) :: TIMESTAMP WITHOUT TIME ZONE AS date_range,
        co."criadoEm"                                  AS created_date,
        co."atualizadoEm"                              AS updated_date,
        co."dataAssinado"                              AS signature_date,
        co."dataRescisao"                              AS termination_date,
        co."dataFimContratoPrevisto"                   AS contract_end_date,
        ad.contract_date,
        date_part('days', ((date_trunc('month', co."criadoEm") + '1 mon' :: INTERVAL) -
                           co."criadoEm"))             AS init_days,
        date_part('days', ((ad.contract_date - date_trunc('month', ad.contract_date)) -
                           '1 mon' :: INTERVAL))       AS end_days,
        (ad.contract_date) :: DATE -
        (co."criadoEm") :: DATE                        AS full_contract_days
      FROM contract co
        JOIN all_dates ad ON (((ad.contract_id = co.id) AND (ad.imovel_id = co.imovel_id)))
  ), brokerage_expense AS (
      SELECT
        ch.contrato_id,
        date_trunc('month', e."dataDespesa")                                AS "dataDespesa",
        e.pagante,
        e.responsavel,
        sum(valor)
        OVER (
          PARTITION BY ch.contrato_id, date_trunc('month', "dataDespesa") ) AS valor
      FROM expense e
        JOIN charging ch ON e.cobranca_id = ch.id
      WHERE e.tipo = 'TaxaCorretagem'
  ), expenses_values AS (
      SELECT
        ct.contract_id,
        ct.rent_value,
        ct.imovel_id,
        ct.date_range,
        be."dataDespesa"     AS expense_date,
        be.pagante           AS paying,
        be.responsavel       AS responsible,
        be.valor             AS brokerage_fee,
        be.valor IS NOT NULL AS flg_incurred
      FROM brokerage_expense be
        RIGHT JOIN ct ON (
          ct.contract_id = be.contrato_id
          AND date_trunc('month', be."dataDespesa") = ct.date_range
          )
  ), projected_values AS (
      SELECT
        contract_id,
        rent_value,
        imovel_id,
        dense_rank()
        OVER (
          PARTITION BY contract_id, imovel_id
          ORDER BY date_range ) AS rn,
        date_range,
        expense_date,
        paying,
        responsible,
        brokerage_fee,
        CASE
        WHEN (sum(brokerage_fee)
        OVER w) < rent_value
          THEN rent_value - (sum(brokerage_fee)
          OVER w)
        ELSE
          NULL
        END                     AS sum_projected,
        flg_incurred
      FROM expenses_values
      WINDOW w AS (
        PARTITION BY contract_id, imovel_id )
  ), max_rn_contracts AS (
      SELECT
        contract_id,
        max(rn) AS max_rn
      FROM projected_values
      WHERE brokerage_fee IS NOT NULL
      GROUP BY contract_id
  )
  SELECT
    pv.contract_id,
    pv.rent_value,
    pv.imovel_id,
    pv.rn,
    pv.date_range,
    pv.expense_date,
    pv.paying,
    pv.responsible,
    CASE
    WHEN pv.rn = mrc.max_rn + 1
      THEN pv.sum_projected
    ELSE pv.brokerage_fee
    END                                                     AS brokerage_fee,
    pv.flg_incurred,
    pv.rn = mrc.max_rn + 1 AND pv.sum_projected IS NOT NULL AS flg_projected
  FROM projected_values pv
    JOIN max_rn_contracts mrc
      ON mrc.contract_id = pv.contract_id
  WINDOW w AS (
    PARTITION BY pv.contract_id, pv.imovel_id )