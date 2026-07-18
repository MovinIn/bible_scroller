import json

from src.progress import clear_stop_point, read_stop_point, write_stop_point


def test_write_stop_point_writes_reference_error_and_resume_hint(tmp_path):
    path = tmp_path / "groups" / "stop_point.json"

    write_stop_point(
        path,
        reference="John 3:16",
        error="503 UNAVAILABLE",
        group_id=42,
        resume_hint="python generate_batch.py --from-id 42",
    )

    payload = json.loads(path.read_text(encoding="utf-8"))
    assert payload["reference"] == "John 3:16"
    assert payload["error"] == "503 UNAVAILABLE"
    assert payload["group_id"] == 42
    assert payload["resume_hint"] == "python generate_batch.py --from-id 42"
    assert "stopped_at" in payload


def test_write_stop_point_omits_group_id_when_not_provided(tmp_path):
    path = tmp_path / "stop_point.json"

    write_stop_point(path, reference="John 3:16-20", error="boom")

    payload = json.loads(path.read_text(encoding="utf-8"))
    assert payload["reference"] == "John 3:16-20"
    assert "group_id" not in payload


def test_read_stop_point_returns_payload_when_file_exists(tmp_path):
    path = tmp_path / "stop_point.json"
    path.write_text(
        json.dumps({"group_id": 42, "reference": "John 3:16", "error": "503"}),
        encoding="utf-8",
    )

    payload = read_stop_point(path)

    assert payload == {"group_id": 42, "reference": "John 3:16", "error": "503"}


def test_read_stop_point_returns_none_when_file_is_missing(tmp_path):
    assert read_stop_point(tmp_path / "missing.json") is None


def test_clear_stop_point_deletes_file(tmp_path):
    path = tmp_path / "stop_point.json"
    path.write_text("{}", encoding="utf-8")

    clear_stop_point(path)

    assert not path.exists()


def test_clear_stop_point_tolerates_missing_file(tmp_path):
    clear_stop_point(tmp_path / "missing.json")
