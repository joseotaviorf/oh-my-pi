WITH
  -- One PERSONAL_DATA document per seller: latest ts_updated, then ts_created, then id
  docx_personal_data_ranked AS (
    SELECT
      sd.id_sales_flow,
      sd.id_seller,
      GET_JSON_OBJECT(d.attributes, '$.maritalStatus') AS maritalStatus,
      GET_JSON_OBJECT(d.attributes, '$.regimeOfAssets') AS regimeOfAssets,
      GET_JSON_OBJECT(d.attributes, '$.spouseName') AS spouseName,
      CAST(GET_JSON_OBJECT(d.attributes, '$.stableUnionRegistered') AS BOOLEAN) AS stable_union,
      GET_JSON_OBJECT(d.attributes, '$.cpf') AS sellerCPF,
      CAST(GET_JSON_OBJECT(d.attributes, '$.isRepresentedByAttorney') AS BOOLEAN) AS is_represented_by_attorney,
      CAST(GET_JSON_OBJECT(d.attributes, '$.isHouseHolder') AS BOOLEAN) AS seller_is_property_owner,
      ROW_NUMBER() OVER (
        PARTITION BY
          sd.id_sales_flow,
          sd.id_seller
        ORDER BY
          d.ts_updated DESC,
          d.ts_created DESC,
          d.id DESC
      ) AS rn
    FROM
      datalake_sales_flow_clean.seller_data AS sd
    INNER JOIN
      datalake_docx_clean.folder AS f
        ON sd.id_docx_folder = f.id
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
        AND dc.name = 'SELLER'
  ),
  docx_personal_data AS (
    SELECT
      id_sales_flow,
      id_seller,
      maritalStatus,
      regimeOfAssets,
      spouseName,
      stable_union,
      sellerCPF,
      is_represented_by_attorney,
      seller_is_property_owner
    FROM
      docx_personal_data_ranked
    WHERE
      rn = 1
  ),
  docx_bank_data AS (
    SELECT
      sd.id_sales_flow,
      sd.id_seller,
      MAX(TRY_CAST(GET_JSON_OBJECT(d.attributes, '$.willReceiveSaleValue') AS BOOLEAN)) AS seller_will_receive_sale_value
    FROM
      datalake_sales_flow_clean.seller_data AS sd
    INNER JOIN
      datalake_docx_clean.folder AS f
        ON sd.id_docx_folder = f.id
    INNER JOIN
      datalake_docx_clean.document AS d
        ON f.id = d.id_folder
    INNER JOIN
      datalake_docx_clean.document_type AS dt
        ON d.id_document_type = dt.id
        AND dt.name = 'BANK_DATA'
    INNER JOIN
      datalake_docx_clean.document_context AS dc
        ON d.id_document_context = dc.id
        AND dc.name = 'SELLER'
    GROUP BY
      sd.id_sales_flow,
      sd.id_seller
  ),
  sellers AS (
    SELECT
      sd.id_sales_flow,
      sd.id_seller,
      sd.name AS seller__name,
      sd.email AS seller__email,
      sd.share_percentage AS sellerdata__share_percentage,
      sd.holding_value AS sellerdata__holding_value,
      sd.is_ccv_signer AS sellerdata__is_ccv_signer
    FROM
      datalake_sales_flow_clean.seller_data AS sd
  )
SELECT
  screening.id_sales_flow,
  sellers.id_seller,
  sellers.seller__name,
  sellers.seller__email,
  docx_personal_data.sellerCPF,
  screening.Conditions__is_seller_pj AS is_seller_pj,
  docx_personal_data.is_represented_by_attorney,
  docx_personal_data.maritalStatus,
  docx_personal_data.regimeOfAssets,
  docx_personal_data.spouseName,
  docx_personal_data.stable_union,
  sellers.sellerdata__holding_value,
  sellers.sellerdata__is_ccv_signer,
  docx_personal_data.seller_is_property_owner,
  sellers.sellerdata__share_percentage,
  docx_bank_data.seller_will_receive_sale_value
FROM
  datalake_legalops.backtest_sources_sales_flows_screenings AS screening
LEFT JOIN
  sellers
    ON screening.id_sales_flow = sellers.id_sales_flow
LEFT JOIN
  docx_personal_data
    ON sellers.id_seller = docx_personal_data.id_seller
    AND sellers.id_sales_flow = docx_personal_data.id_sales_flow
LEFT JOIN
  docx_bank_data
    ON sellers.id_seller = docx_bank_data.id_seller
    AND sellers.id_sales_flow = docx_bank_data.id_sales_flow
