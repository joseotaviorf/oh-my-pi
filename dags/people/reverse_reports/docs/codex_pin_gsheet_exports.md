# CODEX → PIN Google Sheet exports (`reverse_reports`)

People lake → Google Sheets exports shaped for Oracle PIN (HCM). Use the table below to open each export’s notes and column list.

---

## Exports in this programme

| Table | Governance doc |
| --- | --- |
| organization_codex_pin_sync | [organization_codex_pin_sync.md](organization_codex_pin_sync.md) |
| org_unit_classification_codex_pin_sync | [Section below](#org_unit_classification_codex_pin_sync) (inline in this index) |

---

## `org_unit_classification_codex_pin_sync`

| Field | Value |
| --- | --- |
| **Metastore table** | `reverse_reports.org_unit_classification_codex_pin_sync` |
| **Business owner** | **FP&A** — CODEX spreadsheet as operational source. **People Systems** — PIN ingestion using this tab. |
| **Technical owner** | gabriel.berger@quintoandar.com.br |
| **Domain** | People |
| **One-line summary** | Reverse extract formatted for Oracle PIN (HCM): org unit classification data sourced from CODEX for People Systems to ingest into PIN. |
| **Business purpose** | Bridge CODEX classification fields into PIN until a direct integration exists between PIN and the CODEX spreadsheet (that spreadsheet is owned and maintained by FP&A). |
| **Business consumer** | People Systems performs the PIN ingestion; content ultimately reflects CODEX as the operational source for those attributes. |
| **Delivery channel** | Google Sheets tab **OrgUnitClassification** — People Systems uses this tab for PIN ingestion; there is not yet a direct integration between PIN and the FP&A-managed CODEX spreadsheet. |

### Column inventory

| Column | Description | Lake source |
| --- | --- | --- |
| METADATA | HDL verb sent to the integration layer; constant MERGE for this export path when drift exists. | — |
| OrgUnitClassification | Constant Oracle business object label for org unit classification uploads used by the PIN loader contract. | — |
| EffectiveStartDate | Effective start date of the row formatted as yyyy/MM/dd for Oracle effective dating semantics in the sheet payload. | — |
| EffectiveEndDate | Constant far-future effective end date placeholder expected by Oracle effective dating for open-ended rows. | — |
| OrganizationName | PIN organization display name taken from drift detection output for departments that require Codex alignment. | `datalake_people.codex_pin_sync_drift.pin_organization_name` |
| ClassificationName | Constant department classification name required by the Oracle loader template for org unit classification uploads. | — |
| ClassificationCode | Constant department classification code paired with ClassificationName for the loader template. | — |
| Status | PIN organization lifecycle status from drift output, included so operators can validate active versus inactive departments before upload. | `datalake_people.codex_pin_sync_drift.pin_organization_status` |
| SetCode | Constant Oracle set code marker required by the PIN integration template for flexfield payloads. | — |
| year | Partition year for the reverse extract, aligned with the DAG load date (current date in the SQL template). | — |
| month | Partition month for the reverse extract, aligned with the DAG load date (current date in the SQL template). | — |
| day | Partition day for the reverse extract, aligned with the DAG load date (current date in the SQL template). | — |
