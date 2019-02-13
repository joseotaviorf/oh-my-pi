SELECT
	dad.id,
	dad.workAddress,
	dad.workHouseNumber,
	dad.workNeighbourhood,
	dad.workCity,
	dad.code,
	dad.atualizadoEm,
	dad.criadoEm,
	dad.joinedProgramAt,
	da.id,
	(da.doormanAffiliateData_id is not null
        and coalesce(da.affiliateType,'') = 'Doorman'
        and dad.joinedProgramAt is not null) as is_active
FROM
	DoormanAffiliateData dad
LEFT JOIN
	DadosAfiliado da
	ON da.doormanAffiliateData_id = dad.id
LEFT JOIN
    Usuario u
    ON u.dadosAfiliado_id = da.id