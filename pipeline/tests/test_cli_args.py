from pathlib import Path

from src.cli_args import join_cli_words, parse_generate_one_argv


def test_joins_reference_parts_when_shell_splits_on_spaces():
    assert join_cli_words(["John", "3:16-20"]) == "John 3:16-20"


def test_joins_numbered_book_parts_when_shell_splits_on_spaces():
    assert join_cli_words(["1", "John", "3:16-20"]) == "1 John 3:16-20"


def test_joins_extra_parts_when_shell_splits_on_spaces():
    assert (
        join_cli_words(["dawn", "light,", "hopeful", "mood"])
        == "dawn light, hopeful mood"
    )


def test_parses_unquoted_reference_and_extra_when_argv_is_split():
    args = parse_generate_one_argv(
        ["John", "3:16-20", "--extra", "dawn", "light,", "hopeful", "mood"]
    )

    assert args.reference == "John 3:16-20"
    assert args.extra == "dawn light, hopeful mood"


def test_parses_quoted_reference_and_extra_when_argv_is_single_tokens():
    args = parse_generate_one_argv(
        ["John 3:16-20", "--extra", "dawn light, hopeful mood"]
    )

    assert args.reference == "John 3:16-20"
    assert args.extra == "dawn light, hopeful mood"


def test_defaults_extra_to_empty_string_when_flag_is_omitted():
    args = parse_generate_one_argv(["John", "3:16-20"])

    assert args.reference == "John 3:16-20"
    assert args.extra == ""


def test_parses_optional_flags_when_reference_and_extra_are_split():
    args = parse_generate_one_argv(
        [
            "John",
            "3:16-20",
            "--extra",
            "dawn",
            "light",
            "--no-cache",
            "--output-dir",
            "custom/out",
        ]
    )

    assert args.reference == "John 3:16-20"
    assert args.extra == "dawn light"
    assert args.no_cache is True
    assert args.output_dir == Path("custom/out")
