/*
Aquisition Channel
*/

SELECT 
  DATE_FORMAT(ia.firstPublication,'%Y-%m') AS yearMonth,
  CASE 
    WHEN ia.imovelAttribution='Self-Service' THEN 'Self-Service'
  	WHEN ia.lead_tipo='Afiliado' AND ia.lead_origem='App' THEN 'Affiliate App'
  	WHEN ia.lead_tipo='Afiliado' AND ia.lead_origem='Form' THEN 'Affiliate Form'
  	WHEN ia.lead_tipo='Afiliado' AND ia.lead_origem='Planilha' THEN 'Affiliate Spreadsheet'
  	WHEN ia.conversao_tipo='Lead' AND ia.lead_tipo='Marketing' AND ia.lead_origem='Landing' THEN 'Landing Page Leads'
  	WHEN ia.conversao_tipo='Lead' AND ia.lead_tipo='Marketing' AND ia.lead_origem<>'Landing' THEN 'Marketing Leads'
   	WHEN ia.conversao_tipo='InsideSales' THEN 'Organic/Duplicate/Referred Leads'
  	WHEN ia.lead_tipo='Afiliado' AND ia.lead_origem='Desconhecida' THEN 'Affiliate Unknown'
  	WHEN ia.conversao_tipo='Lead' THEN 'Other Lead Source'
  	WHEN ia.imovelAttribution NOT IN ('Self-Service','Undetermined') THEN 'Organic/Duplicate/Referred Leads'
  	ELSE 'Unknown' 
  END AS 'type',
	CASE 
    WHEN ia.imovelAttribution='Self-Service' THEN 'Self-Service'
  	WHEN ia.lead_tipo='Afiliado' THEN 'Affiliate Lead'
  	WHEN ia.conversao_tipo='Lead' AND ia.lead_tipo='Marketing' AND ia.lead_origem='Landing' THEN 'Landing Page Lead'
  	WHEN ia.conversao_tipo='Lead' AND ia.lead_tipo='Marketing' AND ia.lead_origem<>'Landing' THEN 'Marketing Lead'
 	  WHEN ia.conversao_tipo='InsideSales' THEN 'Organic/Duplicate/Referred Lead'
	  WHEN ia.conversao_tipo='Lead' THEN 'Other Lead Source'
	  WHEN ia.imovelAttribution NOT IN ('Self-Service','Undetermined') THEN 'Organic/Duplicate/Referred Lead'
	  ELSE 'Unknown' 
  END AS 'category',
	COUNT(DISTINCT ia.id) AS listingCount
FROM 
	Imovel i
INNER JOIN 
	v_ImovelAttribution_v2 ia ON i.id=ia.id
WHERE
	ia.firstPublication >= DATE_SUB(DATE_FORMAT(CURRENT_DATE(),'%Y-%m-01'), INTERVAL 12 MONTH)
GROUP BY 
	yearMonth, type
ORDER BY 
	yearMonth, type


/*
Aq Method
Self-Service =>  aqchannekl = 'Self-Service'
Outbound =>  lead_tipo = 'Afiliado'
Inbound => todo o restante
*/