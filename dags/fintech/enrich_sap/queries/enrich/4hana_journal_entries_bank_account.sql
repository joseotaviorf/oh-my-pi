SELECT
    id_transaction,
    id_company,
    id_finance_entity,
    id_finance_entity_entry,
    id_business_entity,
    id_external_payment,
    id_line,
    source_client,
    fiscal_year,
    accrual_year_month,
    document_amount,
    account_shortname,
    CASE
        WHEN substr(account_number, 1, 5)=11003 THEN 11003X
        WHEN substr(account_number, 1, 5)=11004 THEN 11004X
        WHEN substr(account_number, 1, 5)=11005 THEN 11005X
        WHEN substr(account_number, 1, 5)=11010 THEN 11010X
        WHEN substr(account_number, 1, 5)=11015 THEN 11015X
        WHEN substr(account_number, 1, 5)=11016 THEN 11016X
        WHEN substr(account_number, 1, 5)=11017 THEN 11017X
        WHEN substr(account_number, 1, 5)=11021 THEN 11021X
        WHEN substr(account_number, 1, 5)=11035 THEN 11035X
        WHEN substr(account_number, 1, 5)=11036 THEN 11036X
        WHEN substr(account_number, 1, 5)=11039 THEN 11039X
        WHEN substr(account_number, 1, 5)=11051 THEN 11051X
        WHEN substr(account_number, 1, 5)=11053 THEN 11053X
        WHEN substr(account_number, 1, 5)=11054 THEN 11054X
        WHEN substr(account_number, 1, 5)=11055 THEN 11055X
        WHEN substr(account_number, 1, 5)=11057 THEN 11057X
        WHEN substr(account_number, 1, 5)=11059 THEN 11059X
        WHEN substr(account_number, 1, 5)=11060 THEN 11060X
        WHEN substr(account_number, 1, 5)=11061 THEN 11061X
        WHEN substr(account_number, 1, 5)=11073 THEN 11073X
        WHEN substr(account_number, 1, 5)=11078 THEN 11078X
        WHEN substr(account_number, 1, 5)=11085 THEN 11085X
        WHEN substr(account_number, 1, 5)=11086 THEN 11086X
        WHEN substr(account_number, 1, 5)=11087 THEN 11087X
        WHEN substr(account_number, 1, 5)=11088 THEN 11088X
        WHEN substr(account_number, 1, 5)=11089 THEN 11089X
        WHEN substr(account_number, 1, 5)=11117 THEN 11117X
        WHEN substr(account_number, 1, 5)=11118 THEN 11118X
        WHEN substr(account_number, 1, 5)=11119 THEN 11119X
        WHEN substr(account_number, 1, 5)=11121 THEN 11121X
        WHEN substr(account_number, 1, 5)=11122 THEN 11122X
        WHEN substr(account_number, 1, 5)=11124 THEN 11124X
        WHEN substr(account_number, 1, 5)=11125 THEN 11125X
        WHEN substr(account_number, 1, 5)=11126 THEN 11126X
        WHEN substr(account_number, 1, 5)=11127 THEN 11127X
        WHEN substr(account_number, 1, 5)=11129 THEN 11129X
        WHEN substr(account_number, 1, 5)=11130 THEN 11130X
        WHEN substr(account_number, 1, 5)=11131 THEN 11131X
        WHEN substr(account_number, 1, 5)=11132 THEN 11132X
        WHEN substr(account_number, 1, 5)=11133 THEN 11133X
        WHEN substr(account_number, 1, 5)=11134 THEN 11134X
        WHEN substr(account_number, 1, 5)=11135 THEN 11135X
        WHEN substr(account_number, 1, 5)=11136 THEN 11136X
        WHEN substr(account_number, 1, 5)=11137 THEN 11137X
        WHEN substr(account_number, 1, 5)=11138 THEN 11138X
        WHEN substr(account_number, 1, 5)=11139 THEN 11139X
        WHEN substr(account_number, 1, 5)=11143 THEN 11143X
        WHEN substr(account_number, 1, 5)=11154 THEN 11154X
        WHEN substr(account_number, 1, 5)=11177 THEN 11177X
        WHEN substr(account_number, 1, 5)=11182 THEN 11182X
        ELSE account_number
    AS account_number,
    user_type,
    accounting_rule,
    indicator,
    memo_line,
    cost_center_code,
    location_profit_code,
    managerial_code,
    posting_key,
    posting_period,
    accounting_type,
    memo,
    material,
    created_by,
    xblnr,
    currency_code,
    comments,
    hash,
    dt_tax,
    dt_accrual,
    dt_created,
    dt_updated,
    year,
    month,
    day
FROM
    datalake_sap.4hana_journal_entries
WHERE
    (
        dt_reference >= DATE('2024-11-01')
        AND account_number IN (110031, 110032, 110035, 110036, 110041, 110042, 110045, 110046, 110051, 110052, 110055, 110056, 110101, 110102, 110105, 110106, 110151, 110152, 110155, 110156, 110161, 110162, 110165, 110166, 110171, 110172, 110175, 110176, 110211, 110212, 110215, 110216, 110351, 110352, 110355, 110356, 110361, 110362, 110365, 110366, 110391, 110392, 110395, 110396, 110511, 110512, 110515, 110516, 110531, 110532, 110535, 110536, 110541, 110542, 110545, 110546, 110551, 110552, 110555, 110556, 110571, 110572, 110575, 110576, 110591, 110592, 110595, 110596, 110601, 110602, 110605, 110606, 110611, 110612, 110615, 110616, 110731, 110732, 110735, 110736, 110781, 110782, 110785, 110786, 110851, 110852, 110855, 110856, 110861, 110862, 110865, 110866, 110871, 110872, 110875, 110876, 110881, 110882, 110885, 110886, 110891, 110892, 110895, 110896, 111171, 111172, 111175, 111176, 111181, 111182, 111185, 111186, 111191, 111192, 111195, 111196, 111211, 111212, 111215, 111216, 111221, 111222, 111225, 111226, 111241, 111242, 111245, 111246, 111251, 111252, 111255, 111256, 111261, 111262, 111265, 111266, 111271, 111272, 111275, 111276, 111291, 111292, 111295, 111296, 111301, 111302, 111305, 111306, 111311, 111312, 111315, 111316, 111321, 111322, 111325, 111326, 111331, 111332, 111335, 111336, 111341, 111342, 111345, 111346, 111351, 111352, 111355, 111356, 111361, 111362, 111365, 111366, 111371, 111372, 111375, 111376, 111381, 111382, 111385, 111386, 111391, 111392, 111395, 111396, 111431, 111432, 111435, 111436, 111541, 111542, 111545, 111546, 111771, 111772, 111775, 111776, 111821, 111822, 111825, 111826)
        AND accounting_type NOT IN ('ZR', 'FR', 'SP')
    )
    OR
    (
        dt_reference < DATE('2024-11-01')
        AND account_number IN (110034, 110030, 110044, 110040, 110054, 110050, 110104, 110100, 110154, 110150, 110164, 110160, 110174, 110170, 110214, 110210, 110354, 110350, 110364, 110360, 110394, 110390, 110514, 110510, 110534, 110530, 110544, 110540, 110554, 110550, 110574, 110570, 110594, 110590, 110604, 110600, 110614, 110610, 110734, 110730, 110784, 110780, 110854, 110850, 110864, 110860, 110874, 110870, 110884, 110880, 110894, 110890, 111174, 111170, 111184, 111180, 111194, 111190, 111214, 111210, 111224, 111220, 111244, 111240, 111254, 111250, 111264, 111260, 111274, 111270, 111294, 111290, 111304, 111300, 111314, 111310, 111324, 111320, 111334, 111330, 111344, 111340, 111354, 111350, 111364, 111360, 111374, 111370, 111384, 111380, 111394, 111390, 111434, 111430, 111544, 111540, 111774, 111770, 111824, 111820)
        AND accounting_type NOT IN ('ZR', 'FR', 'SP')
    )
