from bietlejuice.shared.agents.cli import parse_args


def test_parse_args_uses_spec_defaults(monkeypatch):
    monkeypatch.setattr("sys.argv", ["job.py"])
    args = parse_args(
        "demo_job",
        (
            ("env", str, "forno", "env"),
            ("table_name", str, "tier_metric_events", "table"),
        ),
    )
    assert args.env == "forno"
    assert args.table_name == "tier_metric_events"
    assert args.target_database_name is None
    assert args.target_table_name is None


def test_parse_args_reads_positionals_and_validation_flags(monkeypatch):
    monkeypatch.setattr(
        "sys.argv",
        [
            "job.py",
            "prod",
            "other_table",
            "--target-database-name",
            "validation_db",
            "--target-table-name",
            "validation_table",
        ],
    )
    args = parse_args(
        "demo_job",
        (
            ("env", str, "forno", "env"),
            ("table_name", str, "tier_metric_events", "table"),
        ),
    )
    assert args.env == "prod"
    assert args.table_name == "other_table"
    assert args.target_database_name == "validation_db"
    assert args.target_table_name == "validation_table"
