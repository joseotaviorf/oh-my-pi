with cleaned_contracts as
(
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
        AND coalesce("dataRescisao", "dataFimContratoPrevisto") > coalesce("dataEntrada", "dataInicio")
)
select
	pl.id as imovel_id,
	((pl.id || '00') || COALESCE(pl."version", 1))::bigint as sk_property,
	pl.publication_date,
	pl.last_publication_date,
	pl.last_status_version as last_status,
	c.contract_id,
	c.created_date,
	c.contract_init_date,
	c.termination_date,
	c.status
from vw_property_listing pl
left join
cleaned_contracts c
on c.imovel_id = pl.id
and (c.contract_init_date::date >= pl.min_version_time::date or pl.min_version_time is null)
and (c.contract_init_date::date <= pl.max_version_time::date or pl.max_version_time is null)
--------------------------------------------------------------------
-- This rule should be implemented after the property listing fix --
--------------------------------------------------------------------
--and (c.contract_init_date::date >= pl.last_publication_date::date)
--------------------------------------------------------------------
order by id,version