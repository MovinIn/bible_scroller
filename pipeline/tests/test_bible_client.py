import pytest

from src.bible_client import extract_chapter_text, extract_verse_text, strip_html


SAMPLE_CHAPTER = {
    "chapter": {
        "content": [
            {"type": "verse", "number": 16, "content": ["For God so loved the world,"]},
            {"type": "verse", "number": 17, "content": ["For God did not send his Son into the world to condemn the world,"]},
            {"type": "verse", "number": 18, "content": ["Whoever believes in him is not condemned,"]},
            {"type": "verse", "number": 19, "content": ["And this is the verdict:"]},
            {"type": "verse", "number": 20, "content": ["Everyone who does evil hates the light,"]},
        ]
    }
}


def test_extracts_verse_range_text_when_chapter_payload_is_valid():
    text = extract_verse_text(SAMPLE_CHAPTER, start_verse=16, end_verse=18)
    assert text == (
        "16 For God so loved the world,\n"
        "17 For God did not send his Son into the world to condemn the world,\n"
        "18 Whoever believes in him is not condemned,"
    )


def test_extracts_single_verse_when_start_and_end_match():
    text = extract_verse_text(SAMPLE_CHAPTER, start_verse=16, end_verse=16)
    assert text == "16 For God so loved the world,"


def test_raises_value_error_when_verse_missing_from_chapter():
    with pytest.raises(ValueError, match="No verses found in range 99-99"):
        extract_verse_text(SAMPLE_CHAPTER, start_verse=99, end_verse=99)


def test_extract_verse_text_skips_gaps_when_verse_numbers_are_non_contiguous():
    payload_with_gap = {
        "chapter": {
            "content": [
                {"type": "verse", "number": 10, "content": ["Tenth verse."]},
                {"type": "verse", "number": 12, "content": ["Twelfth verse."]},
                {"type": "verse", "number": 13, "content": ["Thirteenth verse."]},
                {"type": "verse", "number": 14, "content": ["Fourteenth verse."]},
            ]
        }
    }

    text = extract_verse_text(payload_with_gap, start_verse=10, end_verse=14)

    assert text == (
        "10 Tenth verse.\n"
        "12 Twelfth verse.\n"
        "13 Thirteenth verse.\n"
        "14 Fourteenth verse."
    )


def test_strips_html_tags_when_content_contains_markup():
    html = '<p class="p"><span class="v">1</span>In the beginning</p>'
    assert strip_html(html) == "In the beginning"


def test_extract_chapter_text_returns_all_verses_when_chapter_is_contiguous():
    text = extract_chapter_text(SAMPLE_CHAPTER)

    assert text.startswith("16 For God so loved the world,")
    assert text.endswith("20 Everyone who does evil hates the light,")


def test_extract_chapter_text_skips_gaps_when_verse_numbers_are_non_contiguous():
    payload_with_gap = {
        "chapter": {
            "content": [
                {"type": "verse", "number": 1, "content": ["First verse."]},
                {"type": "verse", "number": 2, "content": ["Second verse."]},
                {"type": "verse", "number": 4, "content": ["Fourth verse."]},
            ]
        }
    }

    text = extract_chapter_text(payload_with_gap)

    assert text == "1 First verse.\n2 Second verse.\n4 Fourth verse."


def test_extract_chapter_text_returns_empty_string_when_chapter_has_no_verses():
    assert extract_chapter_text({"chapter": {"content": []}}) == ""
