WITH
  -- One PERSONAL_DATA document per buyer: latest ts_updated, then ts_created, then id
  docx_data_ranked AS (
    SELECT
      bd.id_sales_flow,
      bd.id_buyer,
      GET_JSON_OBJECT(d.attributes, '$.maritalStatus') AS maritalStatus,
      GET_JSON_OBJECT(d.attributes, '$.regimeOfAssets') AS regimeOfAssets,
      GET_JSON_OBJECT(d.attributes, '$.spouseName') AS spouseName,
      CAST(GET_JSON_OBJECT(d.attributes, '$.stableUnionRegistered') AS BOOLEAN) AS stable_union,
      GET_JSON_OBJECT(d.attributes, '$.cpf') AS buyerCPF,
      ROW_NUMBER() OVER (
        PARTITION BY
          bd.id_sales_flow,
          bd.id_buyer
        ORDER BY
          d.ts_updated DESC,
          d.ts_created DESC,
          d.id DESC
      ) AS rn
    FROM
      datalake_sales_flow_clean.buyer_data AS bd
    INNER JOIN
      datalake_docx_clean.folder AS f
        ON bd.id_docx_folder = f.id
    INNER JOIN
      datalake_docx_clean.document AS d
        ON f.id = d.id_folder
    INNER JOIN
      datalake_docx_clean.document_type AS dt
        ON d.id_document_type = dt.id
        AND dt.name = 'PERSONAL_DATA'
    INNER JOIN
      datalake_docx_clean.document_context AS dc
        ON d.id_document_context = dc.id
        AND dc.name = 'BUYER'
  ),
  docx_data AS (
    SELECT
      id_sales_flow,
      id_buyer,
      maritalStatus,
      regimeOfAssets,
      spouseName,
      stable_union,
      buyerCPF
    FROM
      docx_data_ranked
    WHERE
      rn = 1
  ),
  buyers AS (
    SELECT
      bd.id_sales_flow,
      bd.id_buyer,
      bd.name AS buyer__name,
      bd.email AS buyer__email,
      bd.holding_value AS buyerdata__holding_value,
      bd.signer_status AS buyerdata__signer_status,
      sb.proposal_validation_status AS buyer_screening__proposal_validation_status,
      sb.legal_pendency_note AS buyer_screening__legal_pendency_note
    FROM
      datalake_sales_flow_clean.buyer_data AS bd
    LEFT JOIN
      datalake_sales_flow_clean.screening_buyer AS sb
        ON bd.id_buyer = sb.id_buyer_data
  ),
  enriched_buyers AS (
    SELECT
      screening.id_sales_flow,
      screening.Conditions__is_buyer_pj,
      buyers.id_buyer,
      buyers.buyer__name,
      buyers.buyer__email,
      buyers.buyerdata__holding_value,
      buyers.buyerdata__signer_status,
      buyers.buyer_screening__proposal_validation_status,
      buyers.buyer_screening__legal_pendency_note,
      docx_data.maritalStatus,
      docx_data.regimeOfAssets,
      docx_data.spouseName,
      docx_data.stable_union,
      docx_data.buyerCPF
    FROM
      datalake_legalops.backtest_sources_sales_flows_screenings AS screening
    LEFT JOIN
      buyers
        ON screening.id_sales_flow = buyers.id_sales_flow
    LEFT JOIN
      docx_data
        ON docx_data.id_sales_flow = buyers.id_sales_flow
        AND docx_data.id_buyer = buyers.id_buyer
  )
SELECT
  t.id_sales_flow,
  t.id_buyer,
  t.Conditions__is_buyer_pj,
  t.buyer__name,
  t.buyer__email,
  t.buyerCPF,
  t.maritalStatus,
  t.regimeOfAssets,
  t.spouseName,
  t.stable_union,
  t.buyerdata__holding_value,
  t.buyerdata__signer_status,
  t.buyer_screening__proposal_validation_status,
  t.buyer_screening__legal_pendency_note,
  CASE
    WHEN EXISTS (
      SELECT
        1
      FROM
        enriched_buyers AS t2
      WHERE
        t2.id_sales_flow = t.id_sales_flow
        AND t2.buyer__name = t.spouseName
        AND t2.spouseName = t.buyer__name
    )
    THEN TRUE
    ELSE FALSE
  END AS is_spouse_buyer
FROM
  enriched_buyers AS t
