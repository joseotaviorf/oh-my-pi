# Imovelweb Demand — Imovelweb CDC

CDC ingestion slice for **prospect contact actions (leads) generated on Imovelweb listings** from Imovelweb's Navent MySQL database ([RD-3333](https://quintoandar.atlassian.net/browse/RD-3333), parent [RD-3332](https://quintoandar.atlassian.net/browse/RD-3332)).

Schemas: `datalake_imovelweb_raw` (raw) and `datalake_imovelweb_clean` (clean). Column mapping is shared across Navent portals (Zonaprop/Imovelweb/RealEstate); validate against Imovelweb live schema before the first Forno run.

## Tables

| Clean table | Raw table | Grain / PK | Z-ORDER |
|---|---|---|---|
| `contact_actions` | `contactosacciones` | one row per contact action (PK `id_contact_action`) | id_contact |

## Notes

- Depends on [RD-3294](https://quintoandar.atlassian.net/browse/RD-3294) (Debezium + S3 sink) for Forno/prod runs.
- `company_users.password` is excluded from clean; other PII columns remain without `table_privileges` in this POC.
- `empresas.falta` → `dt_missing` and `usuariosempresas.falta` → `ts_missing`: Spanish column semantics not yet confirmed with domain owner.
- `listing_rankings`: declaration PK is `id_listing`; logical grain may be composite — validate against source before tightening DQ.
