DROP VIEW IF EXISTS vw_net_revenue_mgmt_fee CASCADE;
CREATE VIEW vw_net_revenue_mgmt_fee AS
  SELECT
    e.id                                            AS expense_id,
    c.id                                            AS charging_id,
    c.contrato_id                                   AS contract_id,
    ct.imovel_id,
    ct."valorAluguel"                               AS rent_value,
    e."dataDespesa"                                 AS expense_date,
    e.pagante                                       AS paying,
    e.responsavel                                   AS responsible,
    e.tipo                                          AS expense_type,
    e.valor                                         AS expense_value,
    c."valorTotalInquilino"                         AS tenant_value,
    c."valorTotalProprietario"                      AS owner_value,
    c."valorRecebido"                               AS received_value,
    sum(e.valor)
    OVER (
      PARTITION BY c.contrato_id, e."dataDespesa" ) AS mgmt_fee
  FROM expense e
    JOIN charging c ON e.cobranca_id = c.id
    JOIN contract ct ON ct.id = c.contrato_id
  WHERE e.tipo :: TEXT = 'TaxaAdministracao'
        AND ct.tipo <> 'DealOnly'
        AND ct.status <> 'Cancelado'
        AND coalesce(ct."dataRescisao", ct."dataFimContratoPrevisto") > coalesce(ct."dataEntrada", ct."dataInicio");

