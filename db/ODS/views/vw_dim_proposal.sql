drop view if exists vw_dim_proposal;
create view vw_dim_proposal
as
SELECT
  id as sk_proposal,
  id as id_proposal,
  "dataProposta" as dt_proposal,
  garantia as guarantee,
  "propostaAluguel" as renting_proposal_value ,
  status,
  "ticketID" as id_ticket,
  "dataAprovacao" as dt_proposal_approved,
  "inquilinoEnviouDocumentos" as tenant_document_sent,
  "dataDocumentosEnviados" as dt_tenant_document_sent,
  "proprietarioEnviouDocumentos" as owner_document_sent,
  "dataDocumentosProprietarioEnviados" as dt_owner_document_sent,
  "inquilinoAceitouContrato" as tenant_contract_accepted,
  "proprietarioAceitouContrato" as owner_contract_accepted,
  "statusDocumentacaoInq" as status_doc_tenant,
  "statusDocumentacaoProp" as status_doc_owner,
  "preProposta_id" as id_pre_proposal,
  "qtdeEnviosDocumentacaoInq" as tenant_document_sent_count,
  "criadoEm" as dt_created,
  "atualizadoEm" as dt_updated,
  now()::timestamp as dt_timestamp
FROM
  public.proposal ;

