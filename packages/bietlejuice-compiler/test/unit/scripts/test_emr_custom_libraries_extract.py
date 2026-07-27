"""Unit tests for emr_custom_libraries YAML extractors used by EMR bootstrap."""

import email.message
import sys
import zipfile
from pathlib import Path

import pytest
import yaml

_SCRIPTS_DIR = Path(__file__).resolve().parents[3] / "scripts"
if str(_SCRIPTS_DIR) not in sys.path:
    sys.path.insert(0, str(_SCRIPTS_DIR))

from emr_custom_libraries import (  # noqa: E402
    extract_maven_coords,
    extract_pypi_packages,
    extract_uris,
    extract_wheel_requires_dist,
    filter_requires_dist_for_emr_constraints,
    gav_to_maven_path,
    main,
    maven_relative_path,
)


@pytest.fixture
def cluster_yaml(tmp_path: Path):
    def _write(payload: dict) -> Path:
        path = tmp_path / "demo_cluster.yml"
        path.write_text(yaml.dump(payload), encoding="utf-8")
        return path

    return _write


class TestExtractJars:
    def test_prod_only_jar(self, cluster_yaml):
        # arrange
        path = cluster_yaml(
            {
                "cluster": {
                    "custom_libraries": [
                        {"jar": "{artifacts_bucket}/jars/ojdbc8.jar"},
                        {"whl": "{artifacts_bucket}/pkg/client.whl"},
                    ]
                }
            }
        )
        data = yaml.safe_load(path.read_text(encoding="utf-8"))

        # act
        jars = extract_uris(data, key="jar", is_validation=False)

        # assert
        assert jars == ["{artifacts_bucket}/jars/ojdbc8.jar"]

    def test_validation_union_and_dedupe(self, cluster_yaml):
        # arrange
        path = cluster_yaml(
            {
                "cluster": {
                    "custom_libraries": [
                        {"jar": "{artifacts_bucket}/jars/ojdbc8.jar"},
                    ]
                },
                "validation": {
                    "cluster": {
                        "custom_libraries": [
                            {"jar": "{artifacts_bucket}/jars/ojdbc8.jar"},
                            {
                                "jar": (
                                    "{artifacts_bucket}/jars/mssql-jdbc-12.8.1.jre8.jar"
                                )
                            },
                        ]
                    }
                },
            }
        )
        data = yaml.safe_load(path.read_text(encoding="utf-8"))

        # act
        jars = extract_uris(data, key="jar", is_validation=True)

        # assert
        assert jars == [
            "{artifacts_bucket}/jars/ojdbc8.jar",
            "{artifacts_bucket}/jars/mssql-jdbc-12.8.1.jre8.jar",
        ]

    def test_empty_and_missing_custom_libraries(self, cluster_yaml):
        # arrange / act / assert
        assert extract_uris({}, key="jar", is_validation=False) == []
        assert (
            extract_uris(
                {"cluster": {"custom_libraries": []}},
                key="jar",
                is_validation=False,
            )
            == []
        )
        assert (
            extract_uris(
                {"cluster": {}},
                key="jar",
                is_validation=True,
            )
            == []
        )


class TestExtractWhlAndPypi:
    def test_whl_ignores_non_whl_entries(self, cluster_yaml):
        # arrange
        path = cluster_yaml(
            {
                "cluster": {
                    "custom_libraries": [
                        {"jar": "{artifacts_bucket}/jars/ojdbc8.jar"},
                        {"whl": "{artifacts_bucket}/airtable/client.whl"},
                        {"pypi": {"package": "paramiko==4.0.0"}},
                    ]
                }
            }
        )
        data = yaml.safe_load(path.read_text(encoding="utf-8"))

        # act / assert
        assert extract_uris(data, key="whl", is_validation=False) == [
            "{artifacts_bucket}/airtable/client.whl"
        ]

    def test_pypi_emr_flags_and_dedupe(self, cluster_yaml):
        # arrange
        path = cluster_yaml(
            {
                "cluster": {
                    "custom_libraries": [
                        {
                            "pypi": {
                                "package": "presidio-analyzer==2.2.357",
                                "no_deps": True,
                            }
                        },
                        {
                            "pypi": {
                                "package": "numpy==1.26.4",
                                "only_binary": "true",
                            }
                        },
                        {"pypi": {"package": "presidio-analyzer==2.2.357"}},
                    ]
                }
            }
        )
        data = yaml.safe_load(path.read_text(encoding="utf-8"))

        # act
        packages = extract_pypi_packages(data, is_validation=False)

        # assert
        assert packages == [
            ("presidio-analyzer==2.2.357", 1, 0),
            ("numpy==1.26.4", 0, 1),
        ]


class TestMainCli:
    def test_jar_mode_prints_uris(self, cluster_yaml, capsys):
        # arrange
        path = cluster_yaml(
            {
                "cluster": {
                    "custom_libraries": [
                        {"jar": "{artifacts_bucket}/jars/ojdbc8.jar"},
                    ]
                }
            }
        )

        # act
        rc = main(["jar", str(path), "0"])

        # assert
        assert rc == 0
        assert capsys.readouterr().out.strip() == ("{artifacts_bucket}/jars/ojdbc8.jar")

    def test_pypi_mode_prints_tsv(self, cluster_yaml, capsys):
        # arrange
        path = cluster_yaml(
            {
                "cluster": {
                    "custom_libraries": [
                        {
                            "pypi": {
                                "package": "google-auth==2.23.0",
                                "no_deps": False,
                                "only_binary": True,
                            }
                        }
                    ]
                }
            }
        )

        # act
        rc = main(["pypi", str(path)])

        # assert
        assert rc == 0
        assert capsys.readouterr().out.strip() == "google-auth==2.23.0\t0\t1"

    def test_maven_mode_prints_tsv(self, cluster_yaml, capsys):
        # arrange
        path = cluster_yaml(
            {
                "cluster": {
                    "custom_libraries": [
                        {
                            "maven": {
                                "coordinates": (
                                    "graphframes:graphframes:0.8.1-spark3.0-s_2.12"
                                )
                            }
                        }
                    ]
                }
            }
        )

        # act
        rc = main(["maven", str(path), "0"])

        # assert
        assert rc == 0
        assert capsys.readouterr().out.strip() == (
            "graphframes:graphframes:0.8.1-spark3.0-s_2.12\t-\t"
            "graphframes/graphframes/0.8.1-spark3.0-s_2.12/"
            "graphframes-0.8.1-spark3.0-s_2.12.jar\t"
            "graphframes-0.8.1-spark3.0-s_2.12.jar"
        )

    def test_maven_mode_preserves_custom_repo(self, cluster_yaml, capsys):
        # arrange
        path = cluster_yaml(
            {
                "cluster": {
                    "custom_libraries": [
                        {
                            "maven": {
                                "coordinates": (
                                    "org.apache.sedona:"
                                    "sedona-python-adapter-3.0_2.12:1.2.1-incubating"
                                ),
                                "repo": "https://repo.example.com/maven2",
                            }
                        }
                    ]
                }
            }
        )

        # act
        rc = main(["maven", str(path), "0"])

        # assert
        assert rc == 0
        line = capsys.readouterr().out.strip()
        cols = line.split("\t")
        assert len(cols) == 4
        assert cols[0].startswith("org.apache.sedona:")
        assert cols[1] == "https://repo.example.com/maven2"
        assert cols[2].startswith("org/apache/sedona/")
        assert cols[3].endswith(".jar")
        # No empty column that would break bash read
        assert all(c != "" for c in cols)

    def test_maven_mode_rejects_malformed_gav(self, cluster_yaml, capsys):
        # arrange
        path = cluster_yaml(
            {
                "cluster": {
                    "custom_libraries": [
                        {"maven": {"coordinates": "not-a-gav"}},
                    ]
                }
            }
        )

        # act
        rc = main(["maven", str(path)])

        # assert
        assert rc == 1
        assert "group:artifact:version" in capsys.readouterr().err


class TestGavToMavenPath:
    def test_graphframes_layout(self):
        # act
        group_path, artifact, version, jar_name = gav_to_maven_path(
            "graphframes:graphframes:0.8.1-spark3.0-s_2.12"
        )

        # assert
        assert group_path == "graphframes"
        assert artifact == "graphframes"
        assert version == "0.8.1-spark3.0-s_2.12"
        assert jar_name == "graphframes-0.8.1-spark3.0-s_2.12.jar"
        assert maven_relative_path("graphframes:graphframes:0.8.1-spark3.0-s_2.12") == (
            "graphframes/graphframes/0.8.1-spark3.0-s_2.12/"
            "graphframes-0.8.1-spark3.0-s_2.12.jar"
        )

    def test_dotted_group_and_sedona(self):
        # act
        group_path, artifact, version, jar_name = gav_to_maven_path(
            "org.apache.sedona:sedona-python-adapter-3.0_2.12:1.2.1-incubating"
        )

        # assert
        assert group_path == "org/apache/sedona"
        assert artifact == "sedona-python-adapter-3.0_2.12"
        assert version == "1.2.1-incubating"
        assert jar_name == ("sedona-python-adapter-3.0_2.12-1.2.1-incubating.jar")

    @pytest.mark.parametrize(
        "bad",
        ["", "a:b", "a:b:c:d", ":artifact:1.0", "group::1.0"],
    )
    def test_malformed_raises(self, bad):
        with pytest.raises(ValueError, match="group:artifact:version"):
            gav_to_maven_path(bad)


class TestExtractMaven:
    def test_prod_graphframes_and_sedona(self, cluster_yaml):
        # arrange
        path = cluster_yaml(
            {
                "cluster": {
                    "custom_libraries": [
                        {
                            "maven": {
                                "coordinates": (
                                    "graphframes:graphframes:0.8.1-spark3.0-s_2.12"
                                )
                            }
                        },
                        {
                            "maven": {
                                "coordinates": (
                                    "org.apache.sedona:"
                                    "sedona-python-adapter-3.0_2.12:1.2.1-incubating"
                                )
                            }
                        },
                        {"jar": "{artifacts_bucket}/jars/ojdbc8.jar"},
                    ]
                }
            }
        )
        data = yaml.safe_load(path.read_text(encoding="utf-8"))

        # act
        rows = extract_maven_coords(data, is_validation=False)

        # assert
        assert rows == [
            ("graphframes:graphframes:0.8.1-spark3.0-s_2.12", ""),
            (
                "org.apache.sedona:sedona-python-adapter-3.0_2.12:1.2.1-incubating",
                "",
            ),
        ]

    def test_validation_union_dedupe_and_repo(self, cluster_yaml):
        # arrange
        path = cluster_yaml(
            {
                "cluster": {
                    "custom_libraries": [
                        {
                            "maven": {
                                "coordinates": (
                                    "graphframes:graphframes:0.8.1-spark3.0-s_2.12"
                                )
                            }
                        },
                    ]
                },
                "validation": {
                    "cluster": {
                        "custom_libraries": [
                            {
                                "maven": {
                                    "coordinates": (
                                        "graphframes:graphframes:0.8.1-spark3.0-s_2.12"
                                    )
                                }
                            },
                            {
                                "maven": {
                                    "coordinates": (
                                        "org.datasyslab:geotools-wrapper:1.1.0-25.2"
                                    ),
                                    "repo": "https://repo.example.com/maven2",
                                }
                            },
                        ]
                    }
                },
            }
        )
        data = yaml.safe_load(path.read_text(encoding="utf-8"))

        # act
        rows = extract_maven_coords(data, is_validation=True)

        # assert
        assert rows == [
            ("graphframes:graphframes:0.8.1-spark3.0-s_2.12", ""),
            (
                "org.datasyslab:geotools-wrapper:1.1.0-25.2",
                "https://repo.example.com/maven2",
            ),
        ]

    def test_empty_and_malformed(self):
        # arrange / act / assert
        assert extract_maven_coords({}, is_validation=False) == []
        with pytest.raises(ValueError, match="group:artifact:version"):
            extract_maven_coords(
                {
                    "cluster": {
                        "custom_libraries": [
                            {"maven": {"coordinates": "bad"}},
                        ]
                    }
                },
                is_validation=False,
            )


def test_module_lives_next_to_emr_init_script():
    assert (_SCRIPTS_DIR / "emr_custom_libraries.py").is_file()
    assert (_SCRIPTS_DIR / "emr_init_script.sh").is_file()


def test_emr_constraints_include_urllib3_cap_for_awscli():
    """Requires-Dist and custom_libraries pypi install under EMR_CONSTRAINTS only."""
    script = (_SCRIPTS_DIR / "emr_init_script.sh").read_text(encoding="utf-8")
    marker = "cat >\"${EMR_CONSTRAINTS}\" <<'EOF'"
    start = script.index(marker) + len(marker)
    end = script.index("\nEOF\n", start)
    block = script[start:end]
    assert "urllib3>=1.25.4,<1.27" in block
    assert "Restoring python-dateutil and urllib3 for awscli compatibility" in script


def _write_fake_wheel(path: Path, *, requires_dist: list) -> Path:
    """Build a minimal wheel zip with dist-info METADATA for Requires-Dist tests."""
    msg = email.message.EmailMessage()
    msg["Metadata-Version"] = "2.1"
    msg["Name"] = "demo-client"
    msg["Version"] = "0.1.0"
    for req in requires_dist:
        msg.add_header("Requires-Dist", req)
    metadata = msg.as_string()
    with zipfile.ZipFile(path, "w") as zf:
        zf.writestr("demo_client-0.1.0.dist-info/METADATA", metadata)
        zf.writestr("demo_client/__init__.py", "")
    return path


class TestExtractWheelRequiresDist:
    def test_parses_and_dedupes_requires_dist(self, tmp_path: Path):
        # arrange
        whl = _write_fake_wheel(
            tmp_path / "demo_client-0.1.0-py3-none-any.whl",
            requires_dist=[
                "requests>=2.28",
                "urllib3<2",
                "requests>=2.28",
            ],
        )

        # act
        reqs = extract_wheel_requires_dist(str(whl))

        # assert
        assert reqs == ["requests>=2.28", "urllib3<2"]

    def test_skips_extra_markers_keeps_base_req(self, tmp_path: Path):
        # arrange
        whl = _write_fake_wheel(
            tmp_path / "demo_client-0.1.0-py3-none-any.whl",
            requires_dist=[
                "gspread==5.5.0",
                'pytest>=7; extra == "dev"',
                'tomli>=2; python_version < "3.11"',
            ],
        )

        # act
        reqs = extract_wheel_requires_dist(str(whl))

        # assert
        assert reqs == ["gspread==5.5.0", "tomli>=2"]

    def test_keeps_extra_not_equal_markers_as_default_runtime(self, tmp_path: Path):
        # arrange — PEP 508: extra != "x" is required when no extra is requested
        whl = _write_fake_wheel(
            tmp_path / "demo_client-0.1.0-py3-none-any.whl",
            requires_dist=[
                "requests>=2.28",
                'httpx>=0.27; extra != "async"',
                'pytest>=7; extra == "dev"',
            ],
        )

        # act
        reqs = extract_wheel_requires_dist(str(whl))

        # assert
        assert reqs == ["requests>=2.28", "httpx>=0.27"]

    def test_missing_metadata_returns_empty(self, tmp_path: Path):
        # arrange
        whl = tmp_path / "empty-0.0.1-py3-none-any.whl"
        with zipfile.ZipFile(whl, "w") as zf:
            zf.writestr("empty/__init__.py", "")

        # act / assert
        assert extract_wheel_requires_dist(str(whl)) == []

    def test_cli_requires_dist_mode(self, tmp_path: Path, capsys):
        # arrange
        whl = _write_fake_wheel(
            tmp_path / "demo_client-0.1.0-py3-none-any.whl",
            requires_dist=["oauth2client==4.1.3"],
        )

        # act
        rc = main(["requires-dist", str(whl)])

        # assert
        assert rc == 0
        assert capsys.readouterr().out.strip() == "oauth2client==4.1.3"

    def test_cli_requires_dist_missing_file(self, tmp_path: Path, capsys):
        # act
        rc = main(["requires-dist", str(tmp_path / "missing.whl")])

        # assert
        assert rc == 1
        assert "wheel not found" in capsys.readouterr().err


class TestFilterRequiresDistForEmrConstraints:
    def test_skips_conflicting_pin_when_distribution_already_installed(
        self, tmp_path: Path, monkeypatch
    ):
        # arrange
        constraints = tmp_path / "constraints.txt"
        constraints.write_text(
            "requests>=2.32.3\nurllib3>=1.25.4,<1.27\n",
            encoding="utf-8",
        )

        class _FakeDist:
            def __init__(self, name: str):
                self.metadata = {"Name": name}

        monkeypatch.setattr(
            "emr_custom_libraries.importlib.metadata.distributions",
            lambda: [_FakeDist("requests")],
        )

        # act
        kept, skipped = filter_requires_dist_for_emr_constraints(
            ["requests ==2.32.2", "httpx>=0.27"],
            str(constraints),
        )

        # assert
        assert kept == ["httpx>=0.27"]
        assert skipped == ["requests ==2.32.2"]

    def test_cli_requires_dist_skips_conflicting_requests_pin(
        self, tmp_path: Path, capsys, monkeypatch
    ):
        # arrange
        whl = _write_fake_wheel(
            tmp_path / "demo_client-0.1.0-py3-none-any.whl",
            requires_dist=["requests ==2.32.2", "httpx>=0.27"],
        )
        constraints = tmp_path / "constraints.txt"
        constraints.write_text("requests>=2.32.3\n", encoding="utf-8")

        class _FakeDist:
            def __init__(self, name: str):
                self.metadata = {"Name": name}

        monkeypatch.setattr(
            "emr_custom_libraries.importlib.metadata.distributions",
            lambda: [_FakeDist("requests")],
        )

        # act
        rc = main(["requires-dist", str(whl), str(constraints)])

        # assert
        captured = capsys.readouterr()
        assert rc == 0
        assert captured.out.strip() == "httpx>=0.27"
        assert "Skipping Requires-Dist requests ==2.32.2" in captured.err
