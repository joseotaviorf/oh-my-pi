# `organization_codex_pin_sync` — reverse export governance

People `reverse_reports` Google Sheet export: organization flexfields formatted for Oracle PIN (HCM), sourced from CODEX drift output. Part of the CODEX → PIN programme; see also the [programme index](codex_pin_gsheet_exports.md).

| Field | Value |
| --- | --- |
| **Metastore table** | `reverse_reports.organization_codex_pin_sync` |
| **Query** | `queries/reverse/organization_codex_pin_sync.sql` |
| **Business owner** | **FP&A** — operational source of truth for CODEX org attributes in the FP&A-managed spreadsheet. **People Systems** — accountable for PIN / Oracle HCM ingestion behaviour using this tab. |
| **Technical owner** | gabriel.berger@quintoandar.com.br |
| **Domain** | People |
| **One-line summary** | Reverse extract formatted for Oracle PIN (HCM): organization flexfield data sourced from CODEX for People Systems to ingest into PIN. |
| **Business purpose** | Bridge CODEX org attributes into PIN until a direct integration exists between PIN and the CODEX spreadsheet (that spreadsheet is owned and maintained by FP&A). |
| **Business consumer** | People Systems performs the PIN ingestion; content ultimately reflects CODEX as the operational source for those attributes. |
| **Operational source of truth** | CODEX attributes and drift alignment surfaced through `datalake_people.codex_pin_sync_drift`; business ownership of the CODEX spreadsheet is FP&A. |
| **Delivery channel** | Google Sheets tab **Organization** — People Systems uses this tab for PIN ingestion; there is not yet a direct integration between PIN and the FP&A-managed CODEX spreadsheet. |
| **Contract notes** | `column_mapping_mode: name` on this table in `reverse_reports_declaration.yml` so PIN flexfield headers (including `=` between segment and context) map correctly in Delta / `load_to_gsheet`. |

## Column inventory

Row order follows the outer `SELECT` in `queries/reverse/organization_codex_pin_sync.sql`.

| Column | Description | Lake source |
| --- | --- | --- |
| METADATA | HDL verb sent to the integration layer; constant MERGE for this export path when drift exists. | — |
| Organization | Constant Oracle business object label for organization uploads used by the PIN loader contract. | — |
| EffectiveStartDate | Effective start date of the row formatted as yyyy/MM/dd for Oracle effective dating semantics in the sheet payload. | — |
| EffectiveEndDate | Constant far-future effective end date placeholder expected by Oracle effective dating for open-ended rows. | — |
| Name | PIN organization display name taken from drift detection output for departments that require Codex alignment. | `datalake_people.codex_pin_sync_drift.pin_organization_name` |
| ClassificationCode | Constant department classification code required by the Oracle loader template for organization uploads. | — |
| ClassificationName | Constant department classification name paired with ClassificationCode for the loader template. | — |
| FLEX:PER_ORGANIZATION_UNIT_DFF | Oracle flexfield context marker column required in the sheet header row for department descriptive flexfields. | — |
| codigo(PER_ORGANIZATION_UNIT_DFF=Global Data Elements) | Trimmed cost center code mapped to the Oracle flexfield segment name expected by the PIN integration template. | `datalake_people.codex_pin_sync_drift.cost_center_code` |
| business(PER_ORGANIZATION_UNIT_DFF=Global Data Elements) | CODEX business attribute exported to the Oracle flexfield segment named business under Global Data Elements context. | `datalake_people.codex_pin_sync_drift.codex_business` |
| product(PER_ORGANIZATION_UNIT_DFF=Global Data Elements) | CODEX product attribute exported to the Oracle flexfield segment named product under Global Data Elements context. | `datalake_people.codex_pin_sync_drift.codex_product` |
| vertical(PER_ORGANIZATION_UNIT_DFF=Global Data Elements) | CODEX vertical attribute exported to the Oracle flexfield segment named vertical under Global Data Elements context. | `datalake_people.codex_pin_sync_drift.codex_vertical` |
| brand(PER_ORGANIZATION_UNIT_DFF=Global Data Elements) | CODEX brand attribute exported to the Oracle flexfield segment named brand under Global Data Elements context. | `datalake_people.codex_pin_sync_drift.codex_brand` |
| structure(PER_ORGANIZATION_UNIT_DFF=Global Data Elements) | CODEX structure attribute exported to the Oracle flexfield segment named structure under Global Data Elements context. | `datalake_people.codex_pin_sync_drift.codex_structure` |
| team(PER_ORGANIZATION_UNIT_DFF=Global Data Elements) | CODEX team attribute exported to the Oracle flexfield segment named team under Global Data Elements context. | `datalake_people.codex_pin_sync_drift.codex_team` |
| chapter(PER_ORGANIZATION_UNIT_DFF=Global Data Elements) | CODEX chapter attribute with display default "-" when missing, mapped to the Oracle flexfield segment named chapter. | `datalake_people.codex_pin_sync_drift.codex_chapter` |
| line(PER_ORGANIZATION_UNIT_DFF=Global Data Elements) | CODEX line attribute with display default "-" when missing, mapped to the Oracle flexfield segment named line. | `datalake_people.codex_pin_sync_drift.codex_line` |
| l1Cc(PER_ORGANIZATION_UNIT_DFF=Global Data Elements) | CODEX owner L1 cost center label with display default "-" when missing, mapped to the Oracle flexfield segment l1Cc. | `datalake_people.codex_pin_sync_drift.codex_owner_l1_name` |
| l2Cc(PER_ORGANIZATION_UNIT_DFF=Global Data Elements) | CODEX owner L2 cost center label with display default "-" when missing, mapped to the Oracle flexfield segment l2Cc. | `datalake_people.codex_pin_sync_drift.codex_owner_l2_name` |
| l3Cc(PER_ORGANIZATION_UNIT_DFF=Global Data Elements) | CODEX owner L3 cost center label with display default "-" when missing, mapped to the Oracle flexfield segment l3Cc. | `datalake_people.codex_pin_sync_drift.codex_owner_l3_name` |
| headcountType(PER_ORGANIZATION_UNIT_DFF=Global Data Elements) | CODEX headcount type attribute with display default "-" when missing, mapped to the Oracle flexfield segment headcountType. | `datalake_people.codex_pin_sync_drift.codex_headcount_type` |
| year | Partition year for the reverse extract, aligned with the DAG load date (current date in the SQL template). | — |
| month | Partition month for the reverse extract, aligned with the DAG load date (current date in the SQL template). | — |
| day | Partition day for the reverse extract, aligned with the DAG load date (current date in the SQL template). | — |
