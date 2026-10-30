#!/usr/bin/env python3
"""Post-merge evaluation runner for Grok Bot Agent Factory.

Inspects merged pull requests, extracts diff and work-item evidence,
records lessons into the Memory Store, and checks for threshold readiness.
"""

from __future__ import annotations

import argparse
import json
import os
import subprocess
import sys
from pathlib import Path
from typing import Any, Dict, List, Optional

from scripts.evaluator import evaluate_work_item
from scripts.memory_store import get_ready_patterns, resolve_memory_dir


def evaluate_merged_pr(
    *,
    pr_number: int,
    pr_url: Optional[str] = None,
    mem_dir: Optional[Path] = None,
    repo_root: Optional[Path] = None,
) -> Dict[str, Any]:
    """Evaluates a merged PR against factory rubrics and updates memory store."""
    root = repo_root or Path.cwd()
    memory_path = mem_dir or resolve_memory_dir(root)

    # 1. Obtain merge diff if git is available
    diff_text = ""
    try:
        diff_text = subprocess.check_output(
            ["git", "diff", "HEAD~1", "HEAD"],
            cwd=root,
            text=True,
            stderr=subprocess.DEVNULL,
        )
    except Exception:
        pass

    # 2. Locate associated work-item JSON if present
    work_item_id = f"gh-{pr_number}"
    work_item_file = root / ".factory" / "work-items" / f"{work_item_id}.json"
    if work_item_file.exists():
        with open(work_item_file, "r", encoding="utf-8") as f:
            work_item = json.load(f)
    else:
        work_item = {
            "id": work_item_id,
            "prUrl": pr_url,
            "primarySkill": "implement-ticket",
            "retryCount": 0,
            "blockers": [],
        }

    # 3. Read audit log if present
    audit_file = root / "artifacts" / work_item_id / "audit.log"
    audit_log = None
    if audit_file.exists():
        with open(audit_file, "r", encoding="utf-8") as af:
            audit_log = af.read()

    # 4. Evaluate
    lessons = evaluate_work_item(
        work_item,
        audit_log=audit_log,
        diff_text=diff_text,
        mem_dir=memory_path,
    )

    ready_patterns = get_ready_patterns(memory_path)

    return {
        "prNumber": pr_number,
        "lessonsRecorded": len(lessons),
        "lessons": [l["lesson"] for l in lessons],
        "readyPatterns": ready_patterns,
    }


def main() -> None:
    parser = argparse.ArgumentParser(description="Evaluate merged PR and update factory memory.")
    parser.add_argument("--pr-number", type=int, required=True, help="Merged PR number")
    parser.add_argument("--pr-url", type=str, default=None, help="PR HTML URL")
    args = parser.parse_args()

    result = evaluate_merged_pr(pr_number=args.pr_number, pr_url=args.pr_url)
    print(json.dumps(result, indent=2))


if __name__ == "__main__":
    main()
