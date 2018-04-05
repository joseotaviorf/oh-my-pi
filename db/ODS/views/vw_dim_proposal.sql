drop view if exists vw_dim_proposal;
create or replace view vw_dim_proposal as
select
  p.id as sk_proposal,
  p.id as id_proposal,
  p."dataProposta" as dt_proposal,
  p.garantia as guarantee,
  p."propostaAluguel" as renting_proposal_value ,
  p.status,
  p."dataAprovacao" as dt_proposal_approved,
  p."inquilinoEnviouDocumentos" as tenant_document_sent,
  p."dataDocumentosEnviados" as dt_tenant_document_sent,
  p."proprietarioEnviouDocumentos" as owner_document_sent,
  p."dataDocumentosProprietarioEnviados" as dt_owner_document_sent,
  p."inquilinoAceitouContrato" as tenant_contract_accepted,
  p."proprietarioAceitouContrato" as owner_contract_accepted,
  p."statusDocumentacaoInq" as status_doc_tenant,
  p."statusDocumentacaoProp" as status_doc_owner,
  p."qtdeEnviosDocumentacaoInq" as tenant_document_sent_count,
  p."criadoEm" as dt_created,
  p."atualizadoEm" as dt_updated,
  now()::timestamp as dt_timestamp,
  p."primeiroEnvioDocInq" as dt_tenant_first_document_sent,
  shp.created_at as dt_credit_analysis_init,
  shp.process_date as dt_credit_analysis_end
from proposal p
left join sortinghat.proposal shp
  on shp.id = p.id
;

