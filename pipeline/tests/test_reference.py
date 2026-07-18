import pytest

from src.reference import VerseReference, parse_reference


def test_parses_verse_range_when_reference_has_dash():
    ref = parse_reference("John 3:16-20")
    assert ref == VerseReference(book="John", chapter=3, start_verse=16, end_verse=20)


def test_parses_single_verse_when_reference_has_no_range():
    ref = parse_reference("John 3:16")
    assert ref == VerseReference(book="John", chapter=3, start_verse=16, end_verse=16)


def test_parses_multi_word_book_when_reference_includes_number_prefix():
    ref = parse_reference("1 John 4:7-10")
    assert ref == VerseReference(book="1 John", chapter=4, start_verse=7, end_verse=10)


def test_raises_value_error_when_reference_is_malformed():
    with pytest.raises(ValueError, match="Invalid verse reference"):
        parse_reference("not a reference")


def test_slugifies_reference_for_filenames():
    ref = parse_reference("John 3:16-20")
    assert ref.slug() == "John_3_16-20"
