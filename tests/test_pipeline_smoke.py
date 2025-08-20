import shutil
from pathlib import Path

def test_layout_exists():
    """Test that the layout of the project exists."""
    assert Path("src/eopf_geozarr_pipeline/cli.py").exists()

def test_docs_exist():
    """Test that the documentation exists."""
    assert Path("docs/index.md").exists()

def teardown_module():
    """Teardown any state after tests."""
    for p in ("out-zarr", "target-stac"):
        shutil.rmtree(p, ignore_errors=True)