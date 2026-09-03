# RealEstate Company — MySQL CDC (Navent)

CDC slice of the RealEstate Navent MySQL database for the **company** domain. Parent initiative: [RD-3335](https://quintoandar.atlassian.net/browse/RD-3335) (Navent → QuintoAndar migration POC, parent [RD-3332](https://quintoandar.atlassian.net/browse/RD-3332)).

**Schedule:** `0 8,12,21 * * *` (3× daily at minute 0 UTC).
**Schemas:** `datalake_realestate_raw` / `datalake_realestate_clean` (shared across all RealEstate CDC DAGs).
**Secret:** `REALESTATE_DB`

## Tables

| Raw table | Clean table | Grain / PK | Z-order |
|---|---|---|---|
| `empresas` | `companies` | id_company | id_company |
| `interfaceconfigurationparameters` | `interface_configuration_parameters` | id_parameter | id_interface |
| `interfaceconfigurations` | `interface_configurations` | id_interface | id_interface |
| `interfaceempresas` | `interface_companies` | id_interface_company | id_company |
| `tiposdeinmobiliaria` | `agency_types` | id_agency_type | id_agency_type |
| `usuariosempresas` | `company_users` | id_company_user | id_company |

## Notes

- No date partitions on any table; rely on Z-order keys documented in metadata.
- Depends on [RD-3294](https://quintoandar.atlassian.net/browse/RD-3294) (Debezium + S3 sink) for raw data availability.
- Column mapping shared with Zonaprop/Imovelweb Navent portals; validated against Zonaprop mapping spreadsheet.
