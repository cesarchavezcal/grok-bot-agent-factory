import json
import shutil
import tempfile
import unittest
from pathlib import Path

from scripts.evaluate_run import evaluate_merged_pr


class TestEvaluateRun(unittest.TestCase):
    def setUp(self):
        self.test_dir = tempfile.mkdtemp(prefix="test_eval_run_")
        self.repo_root = Path(self.test_dir)
        self.mem_dir = self.repo_root / ".factory" / "memory"
        self.mem_dir.mkdir(parents=True, exist_ok=True)

        # Create dummy work-item
        items_dir = self.repo_root / ".factory" / "work-items"
        items_dir.mkdir(parents=True, exist_ok=True)
        work_item = {
            "id": "gh-99",
            "source": "https://github.com/cesarchavezcal/grok-bot-agent-factory/issues/99",
            "label": "agent",
            "stage": "complete",
            "status": "complete",
            "builder": "poteto-mode",
            "playbook": "autopilot-full",
            "primarySkill": "implement-ticket",
            "planPath": "plans/gh-99.md",
            "ticketIds": [],
            "verifySkill": "verify-app",
            "evidenceDir": "artifacts/gh-99",
            "pendingQuestions": [],
            "blockers": [],
            "decisions": [],
            "retryCount": 1,
            "waitingOn": "none",
        }
        with open(items_dir / "gh-99.json", "w", encoding="utf-8") as f:
            json.dump(work_item, f)

    def tearDown(self):
        shutil.rmtree(self.test_dir, ignore_errors=True)

    def test_evaluate_merged_pr_records_lesson(self):
        res = evaluate_merged_pr(
            pr_number=99,
            pr_url="https://github.com/cesarchavezcal/grok-bot-agent-factory/pull/99",
            mem_dir=self.mem_dir,
            repo_root=self.repo_root,
        )
        self.assertEqual(res["prNumber"], 99)
        self.assertEqual(res["lessonsRecorded"], 1)
        self.assertEqual(res["lessons"][0]["workItemId"], "gh-99")
        self.assertEqual(res["lessons"][0]["failureClass"], "audit_interrogation_failure")


if __name__ == "__main__":
    unittest.main()
