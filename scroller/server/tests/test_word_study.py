from __future__ import annotations

import json
from pathlib import Path

import pytest

from src.services.word_study import (
    WordStudyService,
    load_strongs_lexicon,
)


@pytest.fixture
def word_study_root(tmp_path: Path) -> Path:
    display = tmp_path / "display" / "GEN"
    display.mkdir(parents=True)
    (display / "GEN1.json").write_text(
        json.dumps(
            {
                "eng": {
                    "1": [
                        ["In the beginning", "H7225"],
                        [" ", None],
                        ["God", "H430"],
                        ["", "H853", {"elided": True}],
                        [" ", None],
                        ["created", "H1254"],
                        [" ", None],
                        ["the heavens", "H8064"],
                        [" ", None],
                        ["and", "H853"],
                        [" ", None],
                        ["the earth", "H776"],
                        [".", None],
                    ],
                    "2": [
                        ["Now the earth", "H776"],
                        [" ", None],
                        ["was", "H1961"],
                        [" ", None],
                        ["formless", "H8414"],
                        [".", None],
                    ],
                },
                "heb": {
                    "1": [
                        ["רֵאשִׁית", "H7225"],
                        ["בָּרָא", "H1254"],
                        ["אֱלֹהִים", "H430"],
                        ["אֵת", "H853"],
                        ["הַשָּׁמַיִם", "H8064"],
                        ["וְאֵת", "H853"],
                        ["הָאָרֶץ", "H776"],
                    ],
                    "2": [
                        ["הָאָרֶץ", "H776"],
                        ["הָיְתָה", "H1961"],
                        ["תֹהוּ", "H8414"],
                    ],
                },
            },
            ensure_ascii=False,
        ),
        encoding="utf-8",
    )
    jhn = tmp_path / "display" / "JHN"
    jhn.mkdir(parents=True)
    (jhn / "JHN3.json").write_text(
        json.dumps(
            {
                "eng": {
                    "16": [
                        ["For", "G1063"],
                        [" ", None],
                        ["God", "G2316"],
                        [" ", None],
                        ["so", "G3779"],
                        [" ", None],
                        ["loved", "G25"],
                        [" ", None],
                        ["the world", "G2889"],
                        [".", None],
                    ],
                },
                "grk": {
                    "16": [
                        ["γάρ", "G1063"],
                        ["θεός", "G2316"],
                        ["οὕτως", "G3779"],
                        ["ἀγαπάω", "G25"],
                        ["κόσμος", "G2889"],
                    ],
                },
            },
            ensure_ascii=False,
        ),
        encoding="utf-8",
    )
    lexicon_dir = tmp_path / "lexicon"
    lexicon_dir.mkdir()
    (lexicon_dir / "strongs.json").write_text(
        json.dumps(
            {
                "H7225": {
                    "lemma": "רֵאשִׁית",
                    "definition": "the first, in place, time, order or rank",
                },
                "H430": {
                    "lemma": "אֱלֹהִים",
                    "definition": "gods in the ordinary sense; but specifically used of the supreme God",
                },
                "H1254": {
                    "lemma": "בָּרָא",
                    "definition": "to create",
                },
                "H8064": {
                    "lemma": "שָׁמַיִם",
                    "definition": "the sky",
                },
                "H853": {
                    "lemma": "אֵת",
                    "definition": "properly, self",
                },
                "H776": {
                    "lemma": "אֶרֶץ",
                    "definition": "the earth",
                },
                "H1961": {
                    "lemma": "הָיָה",
                    "definition": "to exist",
                },
                "H8414": {
                    "lemma": "תֹּהוּ",
                    "definition": "a desolation",
                },
                "G1063": {
                    "lemma": "γάρ",
                    "definition": "properly, assigning a reason",
                },
                "G2316": {
                    "lemma": "θεός",
                    "definition": "a deity, especially the supreme Divinity",
                },
                "G3779": {
                    "lemma": "οὕτω",
                    "definition": "in this way",
                },
                "G25": {
                    "lemma": "ἀγαπάω",
                    "definition": "to love",
                },
                "G2889": {
                    "lemma": "κόσμος",
                    "definition": "orderly arrangement, i.e. decoration; by implication, the world",
                },
            },
            ensure_ascii=False,
        ),
        encoding="utf-8",
    )
    return tmp_path


def test_returns_bsb_phrase_groups_for_genesis_1_1(word_study_root: Path) -> None:
    service = WordStudyService(root=word_study_root)
    result = service.get_word_study(
        book="Genesis",
        chapter=1,
        start_verse=1,
        end_verse=1,
    )

    assert result["reference"] == "Genesis 1:1"
    assert result["version_id"] == "bsb"
    assert len(result["verses"]) == 1
    assert result["verses"][0]["verse"] == 1
    phrases = [g["phrase"] for g in result["verses"][0]["groups"]]
    assert phrases == [
        "In the beginning",
        "God",
        "created",
        "the heavens",
        "and",
        "the earth",
    ]
    assert [g["strongs"] for g in result["verses"][0]["groups"]] == [
        "H7225",
        "H430",
        "H1254",
        "H8064",
        "H853",
        "H776",
    ]


def test_enriches_groups_with_lemma_and_definition(word_study_root: Path) -> None:
    service = WordStudyService(root=word_study_root)
    result = service.get_word_study(
        book="Genesis",
        chapter=1,
        start_verse=1,
        end_verse=1,
    )
    first = result["verses"][0]["groups"][0]
    assert first["strongs"] == "H7225"
    assert first["lemma"] == "רֵאשִׁית"
    assert first["definition"] == "the first, in place, time, order or rank"


def test_covers_multi_verse_range(word_study_root: Path) -> None:
    service = WordStudyService(root=word_study_root)
    result = service.get_word_study(
        book="Genesis",
        chapter=1,
        start_verse=1,
        end_verse=2,
    )

    assert result["reference"] == "Genesis 1:1-2"
    assert [v["verse"] for v in result["verses"]] == [1, 2]
    assert result["verses"][1]["groups"][0]["phrase"] == "Now the earth"
    assert result["verses"][1]["groups"][0]["strongs"] == "H776"


def test_uses_greek_strongs_for_new_testament(word_study_root: Path) -> None:
    service = WordStudyService(root=word_study_root)
    result = service.get_word_study(
        book="John",
        chapter=3,
        start_verse=16,
        end_verse=16,
    )

    strongs = [g["strongs"] for g in result["verses"][0]["groups"]]
    assert strongs == ["G1063", "G2316", "G3779", "G25", "G2889"]
    assert all(s.startswith("G") for s in strongs)
    god = next(g for g in result["verses"][0]["groups"] if g["strongs"] == "G2316")
    assert god["lemma"] == "θεός"
    assert god["definition"] == "a deity, especially the supreme Divinity"


def test_load_strongs_lexicon_reads_compact_json(tmp_path: Path) -> None:
    path = tmp_path / "strongs.json"
    path.write_text(
        json.dumps({"H1": {"lemma": "אָב", "definition": "father"}}),
        encoding="utf-8",
    )
    lexicon = load_strongs_lexicon(path)
    assert lexicon["H1"]["lemma"] == "אָב"
    assert lexicon["H1"]["definition"] == "father"


def test_word_study_endpoint_returns_bsb_groups(client, word_study_root: Path, monkeypatch) -> None:
    monkeypatch.setattr(
        "src.routes.reels.get_word_study_service",
        lambda: WordStudyService(root=word_study_root),
    )

    response = client.get(
        "/bible/word-study",
        params={
            "book": "Genesis",
            "chapter": 1,
            "start_verse": 1,
            "end_verse": 1,
        },
    )
    assert response.status_code == 200
    payload = response.json()
    assert payload["version_id"] == "bsb"
    assert payload["verses"][0]["groups"][0]["phrase"] == "In the beginning"
    assert payload["verses"][0]["groups"][0]["strongs"] == "H7225"
    assert payload["verses"][0]["groups"][0]["lemma"] == "רֵאשִׁית"
    assert "first" in payload["verses"][0]["groups"][0]["definition"]
