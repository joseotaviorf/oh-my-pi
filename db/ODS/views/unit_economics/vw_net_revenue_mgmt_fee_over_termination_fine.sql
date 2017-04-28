DROP VIEW vw_net_revenue_mgmt_fee_over_termination_fine CASCADE;
CREATE VIEW vw_net_revenue_mgmt_fee_over_termination_fine AS
  SELECT DISTINCT
    c.id                                                                     AS contract_id,
    c.imovel_id,
    date_trunc('month' :: TEXT, (tf."Month") :: TIMESTAMP WITHOUT TIME ZONE) AS date_range,
    tf."Receita"                                                             AS cost
  FROM (files.termination_fine tf
    JOIN contract c ON ((tf."ID imovel" = c.imovel_id)));

