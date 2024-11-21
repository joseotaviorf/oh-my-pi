SELECT
  Id AS id_storage_document,
  DocumentId AS id_document,
  EntidadeId AS id_entity,
  UsuarioId AS id_user,
  TipoDocumento AS document_type,
  ContentType AS content_type,
  `key` AS storage_key,
  bucket,
  Topico AS topic,
  status,
  cpf,
  Extensao AS extension,
  Tamanho AS file_size,
  NomeArquivo AS file_name,
  `_OCR` AS extracted_data,
  EnviadoEm AS ts_sent,
  CASE 
      WHEN AtualizadoEm = "0001-01-01T00:00:00.000+00:00" THEN TIMESTAMP("1970-01-01T00:00:00.000+00:00")
      ELSE AtualizadoEm
  END ts_updated
FROM
  datalake_atta_test_raw.storagedocumentos
