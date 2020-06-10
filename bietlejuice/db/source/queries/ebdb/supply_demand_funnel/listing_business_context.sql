SELECT
  lbc.id,
  lbc.imovelId as id_house,
  lbc.businessContext as business_context,
  lbc.status as status,
  lbc.statusReason as status_reason,
  lbc.criadoEm as ts_created,
  lbc.atualizadoEm as ts_updated,
  lbc.firstPublicationDate as ts_first_listing,
  lbc.lastPublicationDate as  ts_last_listing,
  opt_out.ts_opt_out_rent,
  opt_out.ts_opt_out_sale,
  registrant.user_listing_registrant_rent,
  registrant.user_listing_registrant_sale
FROM
  ListingBusinessContext lbc
LEFT JOIN
  (SELECT 
      imovelid AS id_house,
      MAX(ts_opt_out_rent) AS ts_opt_out_rent,
      MAX(ts_opt_out_sale) AS ts_opt_out_sale
  FROM
  (SELECT 
      lbcaud.
      imovelid, 
      lbcaud.businessContext, 
      lbcaud.status, 
      CASE WHEN businessContext = 'RENT' THEN COALESCE(from_unixtime(ure.timestamp/1000), NULL) ELSE NULL END AS ts_opt_out_rent,
      CASE WHEN businessContext = 'SALE' THEN COALESCE(from_unixtime(ure.timestamp/1000), NULL) ELSE NULL END AS ts_opt_out_sale
  FROM 
      ListingBusinessContext_AUD lbcaud
  JOIN UsuarioRevisionEntity ure 
      ON ure.id = lbcaud.rev
  WHERE 
      status = 'OPTED_OUT' 
      AND status_MOD = '1')
  GROUP BY imovelid) AS opt_out ON lbc.imovelid = opt_out.id_house
LEFT JOIN
  (SELECT
      lbc.imovelid,
      ure_rent.usuario_id AS user_listing_registrant_rent,
      ure_sale.usuario_id AS user_listing_registrant_sale
  FROM
  ListingBusinessContext lbc   
  LEFT JOIN (SELECT 
      lbc_aud.imovelid,
      MIN(CASE WHEN businessContext = 'RENT' THEN lbc_aud.rev ELSE NULL END) AS first_rev_rent,
      MIN(CASE WHEN businessContext = 'SALE' THEN lbc_aud.rev ELSE NULL END) AS first_rev_sale
  FROM 
  ListingBusinessContext_AUD AS lbc_aud
  GROUP BY lbc_aud.imovelid) AS rev 
      ON rev.imovelid = lbc.imovelid
  LEFT JOIN UsuarioRevisionEntity AS ure_rent
      ON ure_rent.id = rev.first_rev_rent
  LEFT JOIN UsuarioRevisionEntity AS ure_sale
      ON ure_sale.id = rev.first_rev_sale     
  GROUP BY lbc.imovelid) AS registrant ON lbc.imovelid = registrant.imovelid
