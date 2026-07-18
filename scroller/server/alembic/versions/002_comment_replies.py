"""Comment replies

Revision ID: 002
Revises: 001
Create Date: 2026-07-13
"""

from typing import Sequence, Union

import sqlalchemy as sa
from alembic import op

revision: str = "002"
down_revision: Union[str, None] = "001"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.add_column("comments", sa.Column("parent_id", sa.Integer(), nullable=True))
    op.create_foreign_key(
        "fk_comments_parent_id",
        "comments",
        "comments",
        ["parent_id"],
        ["id"],
        ondelete="CASCADE",
    )
    op.create_index(
        "ix_comments_reel_parent_created",
        "comments",
        ["reel_id", "parent_id", "created_at"],
    )


def downgrade() -> None:
    op.drop_index("ix_comments_reel_parent_created", table_name="comments")
    op.drop_constraint("fk_comments_parent_id", "comments", type_="foreignkey")
    op.drop_column("comments", "parent_id")
