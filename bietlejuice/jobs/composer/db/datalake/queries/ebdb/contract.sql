WITH
    max_cancellations AS (
        SELECT
            id,
            max(rev) AS max_rev
        FROM
            datalake_ebdb_raw.contrato_aud
        WHERE
            status = 'Cancelado'
            AND status_mod = '1'
        GROUP BY
            id
    ),
    contract_reasons AS (
        SELECT
            max_cancellations.id,
            CASE
                WHEN usuariorevisionentity.motivo rlike 'Desacordo entre AS partes com rela..o a data de vig.ncia'
                    THEN 'VALIDITY_DATES'
                WHEN usuariorevisionentity.motivo rlike 'N.o foi poss.vel contactar uma das partes'
                    THEN 'UNREACHABLE'
                WHEN usuariorevisionentity.motivo rlike 'Prazo de assinatura expirado'
                    THEN 'SIG_DEADLINE_EXPIRED'
                WHEN usuariorevisionentity.motivo rlike 'Inquilino alugou im.vel por fora do 5A'
                    THEN 'TENANT_RENTING_WITH_OTHER_COMPANY'
                WHEN usuariorevisionentity.motivo rlike 'Propriet.rio alugou im.vel por fora do 5A'
                    THEN 'OWNER_RENTING_WITH_OTHER_COMPANY'
                WHEN usuariorevisionentity.motivo rlike 'Inquilino prefere outro im.vel 5A'
                    THEN 'TENANT_PREFERS_OTHER'
                WHEN usuariorevisionentity.motivo rlike 'Propriet.rio prefere outro inquilino 5A'
                    THEN 'OWNER_PREFERS_OTHER'
                WHEN usuariorevisionentity.motivo rlike 'Caracter.sticas/informa..es incorretas no an.ncio'
                    THEN 'INCORRECT_INFO'
                WHEN usuariorevisionentity.motivo rlike 'Desacordo entre AS partes durante negocia..o'
                    THEN 'DISAGREEMENT'
                WHEN usuariorevisionentity.motivo rlike 'Inquilino n.o concorda com modelo 5A'
                    THEN 'TENANT_DOESNT_AGREE'
                WHEN usuariorevisionentity.motivo rlike 'Propriet.rio n.o concorda com modelo 5A'
                    THEN 'OWNER_DOESNT_AGREE'
                WHEN usuariorevisionentity.motivo rlike 'Demora/confus.o durante processo 5A por parte do inquilino'
                    THEN 'TENANT_DELAY'
                WHEN usuariorevisionentity.motivo rlike 'Demora/confus.o durante o processo 5A por parte do propriet.rio'
                    THEN 'OWNER_DELAY'
                WHEN usuariorevisionentity.motivo rlike 'Houve uma altera..o no valor do im.vel'
                    THEN 'PRICE_MODIFICATION'
                WHEN usuariorevisionentity.motivo rlike 'Inquilino comprou um im.vel e desistiu da loca..o'
                    THEN 'TENANT_BUYING_HOUSE'
                WHEN usuariorevisionentity.motivo rlike 'Propriet.rio vendeu o im.vel e desistiu da loca..o'
                    THEN 'OWNER_SELLING_HOUSE'
                WHEN usuariorevisionentity.motivo rlike 'Inquilino desistiu da loca..o devido a mudan.a ou problema familiar'
                    THEN 'TENANT_GAVE_UP_RENTING'
                WHEN usuariorevisionentity.motivo rlike 'Propriet.rio desistiu da loca..o devido a mudan.a ou problema familiar'
                    THEN 'OWNER_GAVE_UP_RENTING'
                WHEN usuariorevisionentity.motivo rlike 'Inquilino n.o conseguiu entregar/sair do im.vel atual'
                    THEN 'TENANT_UNABLE_TO_LEAVE'
                WHEN usuariorevisionentity.motivo rlike 'Propriet.rio n.o conseguiu entregar/sair do im.vel'
                    THEN 'OWNER_UNABLE_TO_LEAVE'
                ELSE 'OTHERS'
            END AS cancellation_reason,
            from_unixtime(usuariorevisionentity.`timestamp` / 1000) AS ts_canceled
        FROM
            max_cancellations
            JOIN datalake_ebdb_raw.usuariorevisionentity AS usuariorevisionentity
                ON max_cancellations.max_rev = usuariorevisionentity.id
    )
SELECT
    contrato.id AS id_contract,
    contrato.valorAluguel AS rent,
    contrato.diaMesCobranca AS day_month_due,
    contrato.garantia AS guarantee,
    contrato.tipo AS type,
    contrato.status AS status,
    contrato.dataInicio AS dt_start,
    contrato.dataAssinado AS ts_signature,
    contrato.dataMinutaAprovada AS ts_draft_approved,
    contrato.dataEntrada AS dt_entrance,
    contrato.dataFimContratoPrevisto AS dt_intended_end,
    contrato.dataRescisao AS dt_annulment,
    contrato.paganteCondominio AS condo_payer,
    contrato.responsavelCondominio AS condo_responsible,
    contrato.paganteIptu AS iptu_payer,
    contrato.responsavelIptu AS iptu_responsible,
    contrato.seguroFianca_parcelas AS rental_insurance_installments,
    contrato.seguroFianca_valor AS rental_insurance_value,
    contrato.seguroResidencial_parcelas AS home_insurance_installments,
    contrato.seguroResidencial_valor AS home_insurance_value,
    contrato.taxacomissaoprimeiroaluguel AS first_rental_commission,
    contratofull.taxaAdministracaoMensal AS monthly_administration_fee,
    contrato.valorCondominio AS condo,
    contrato.iptu_valor AS iptu,
    contrato.tipoAssinatura AS signature_type,
    contrato.statusClosing AS closing_status,
    contrato.criadoEm AS ts_created,
    contrato.atualizadoEm AS ts_updated,
    contract_reasons.ts_canceled,
    contract_reasons.cancellation_reason,
    contrato.proposta_id AS id_proposal,
    contrato.imovel_id AS id_house
FROM
    datalake_ebdb_raw.contrato AS contrato
    LEFT JOIN contract_reasons
        ON contract_reasons.id = contrato.id
    LEFT JOIN datalake_ebdb_raw.contratofull AS contratofull
        ON contratofull.id = contrato.id
