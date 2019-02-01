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
	da.id
FROM
	DoormanAffiliateData dad
LEFT JOIN
	DadosAfiliado da
	ON da.doormanAffiliateData_id = dad.id