# Reverse export governance (blank template)

**Purpose:** Copy this file (or the section below) when documenting a new People `reverse_reports` Google Sheet export. **Filled** governance lives under **`dags/people/reverse_reports/docs/`** (for example [`codex_pin_gsheet_exports.md`](../../../../dags/people/reverse_reports/docs/codex_pin_gsheet_exports.md)), not in `metadata/reverse/*.yml`, because repository CI rejects reverse-layer governance YAML.

**Reader-friendly index:** Keep [`codex_pin_gsheet_exports.md`](../../../../dags/people/reverse_reports/docs/codex_pin_gsheet_exports.md) short—links and per-export sections only. Put “how to add an export”, template copy-paste, and CI rationale in this file (and in the skill `SKILL.md`).

**Where to paste the filled copy**

- **CODEX → PIN–style exports** (same programme as organization / org unit classification): append a new `## \`your_table_name\`` section to [`codex_pin_gsheet_exports.md`](../../../../dags/people/reverse_reports/docs/codex_pin_gsheet_exports.md).
- **Other People reverse tabs:** add a new Markdown file under [`dags/people/reverse_reports/docs/`](../../../../dags/people/reverse_reports/docs/) (for example `other_topic_gsheet_exports.md`) and link it from a short comment on the `tables_customization` entry in `reverse_reports_declaration.yml` if helpful.

Keep prose in **English**. Align the **column inventory** row order with the outer `SELECT` list in `queries/reverse/<table_name>.sql` (see `sql_conventions.mdc`).

---

## `your_table_name` (replace heading and body)

| Field | Your answer |
| --- | --- |
| **Metastore table** | `reverse_reports.<table_name>` (must match `queries/reverse/<table_name>.sql`) |
| **Business owner** | Squad or role accountable for what the tab represents upstream (for example FP&A for CODEX, Compensation for salary tables). Name a contact email when the team expects one. |
| **Technical owner** | Email of the engineer or squad that owns SQL, DAG wiring, `load_to_gsheet`, and sheet ACLs (often Data People). |
| **Domain** | People |
| **One-line summary** | What each sheet row represents for the downstream consumer. |
| **Business purpose** | Why this export exists (bridge, review workflow, etc.). |
| **Business consumer** | Team or system that applies or ingests the tab. |
| **Operational source of truth** | Where business truth lives when it is not only DW (for example FP&A-owned spreadsheet). |
| **Delivery channel** | Google Sheets tab name, workbook, service account access notes. |
| **Contract notes** | Loader quirks, `column_mapping_mode`, fixed headers, PIN/Oracle/HDL wording as applicable. |

### Column inventory

| Column (sheet / Delta name) | Description | Lake source (`schema.table.column`) |
| --- | --- | --- |
| | | |
