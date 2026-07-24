from scripts.dependency_handling import automate_dependencies as mod


class TestGenerateDependencies:
    def test_filters_ignored_dag_keys_from_output(self, monkeypatch):
        def fake_generate_dependencies(self, manual_modifications):
            return {
                "bietlejuice.migration_emr_foo": [
                    "bietlejuice.up:load-clean:first-run-of-day"
                ],
                "bietlejuice.enrich_velo": ["bietlejuice.dw:load-dw:first-run-of-day"],
            }

        monkeypatch.setattr(
            mod.FileDependencyGenerator,
            "generate_dependencies",
            fake_generate_dependencies,
        )
        monkeypatch.setattr(mod, "get_unstandard_dags_file_content", lambda _path: {})
        monkeypatch.setattr(
            mod, "get_manual_modifications_file_content", lambda _path: {}
        )
        monkeypatch.setattr(
            "bietlejuice.base.dependencies.ignored_dag_ids.ignored_dag_ids",
            lambda dags_root=None: frozenset({"bietlejuice.migration_emr_foo"}),
        )

        assert mod.generate_dependencies() == {
            "bietlejuice.enrich_velo": ["bietlejuice.dw:load-dw:first-run-of-day"],
        }
