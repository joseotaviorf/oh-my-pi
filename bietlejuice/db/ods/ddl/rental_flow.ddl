drop table if exists rental_flow;
create table if not exists rental_flow (
  id bigint,
  atualizadoEm timestamp,
  criadoEm timestamp,
  cliente_id bigint,
  gerente_id bigint,
  imovel_id bigint,
  ignorarAntesDe timestamp,
  status varchar(100),
  etapaRejeitada smallint,
  withoutIptu bit(1),
  currentOffer_id bigint,
  currentContrato_id bigint,
  currentProposta_id bigint,
  originalRentFlowId bigint
);