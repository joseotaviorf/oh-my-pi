DROP VIEW vw_rental_mgmt_contract CASCADE;
CREATE VIEW vw_rental_mgmt_contract AS
  SELECT
    id                                                                   AS contract_id,
    imovel_id,
    "criadoEm" :: TIMESTAMP WITHOUT TIME ZONE                            AS created_date,
    "dataAssinado" :: TIMESTAMP WITHOUT TIME ZONE                        AS signature_date,
    coalesce("dataEntrada", "dataInicio") :: TIMESTAMP WITHOUT TIME ZONE AS contract_init_date,
    "dataRescisao" :: TIMESTAMP WITHOUT TIME ZONE                        AS termination_date,
    status,
    CASE
    WHEN status IN ('Ativo', 'PreAssinaturas')
      THEN COALESCE("dataRescisao" :: TIMESTAMP WITHOUT TIME ZONE,
                    "dataFimContratoPrevisto" :: TIMESTAMP WITHOUT TIME ZONE)
    WHEN status = 'Finalizado'
      THEN "dataRescisao" :: TIMESTAMP WITHOUT TIME ZONE
    ELSE "atualizadoEm"
    END                                                                  AS contract_date
  FROM contract
  WHERE tipo <> 'DealOnly'
        AND status <> 'Cancelado'
        AND coalesce("dataRescisao", "dataFimContratoPrevisto") > coalesce("dataEntrada", "dataInicio");