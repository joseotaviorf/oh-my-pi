SELECT
    ID AS id,
    IDProduto AS id_product,
    NrDecisao AS decision_number,
    Descricao AS proposal_status,
    PrxStatus AS id_proposal_status,
    Situacao AS id_proposal_situation
FROM
    datalake_atta_test_raw.produto_esteira
