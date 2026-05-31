#!/usr/bin/env python3
import json
import os
import stat
from pathlib import Path


def main() -> None:
    home = Path.home()
    settings_path = home / ".claude" / "settings.json"
    script_path = home / ".claude" / "aifuelgauge-statusline.py"
    output_path = home / "Library" / "Application Support" / "AI Fuel Gauge" / "claude-statusline.json"

    settings_path.parent.mkdir(parents=True, exist_ok=True)
    output_path.parent.mkdir(parents=True, exist_ok=True)

    try:
        raw_settings = settings_path.read_text(encoding="utf-8") if settings_path.exists() else ""
        settings = json.loads(raw_settings) if raw_settings.strip() else {}
    except Exception:
        settings = {}

    status_line = settings.get("statusLine") if isinstance(settings.get("statusLine"), dict) else {}
    existing = status_line.get("command") if isinstance(status_line.get("command"), str) else None
    previous = None if existing == str(script_path) else existing

    script = "\n".join(
        [
            "#!/usr/bin/env python3",
            "import json",
            "import os",
            "import subprocess",
            "import sys",
            "import time",
            "",
            f"OUTPUT_PATH = {str(output_path)!r}",
            f"PREVIOUS_COMMAND = {previous!r}",
            "",
            "raw = sys.stdin.read()",
            "try:",
            "    payload = json.loads(raw) if raw.strip() else {}",
            "except Exception:",
            "    payload = {}",
            "",
            'rate_limits = payload.get("rate_limits") or {}',
            "capture = {",
            '    "updated_at": time.time(),',
            '    "session_id": payload.get("session_id"),',
            '    "model": payload.get("model"),',
            '    "rate_limits": {',
            '        "five_hour": rate_limits.get("five_hour"),',
            '        "seven_day": rate_limits.get("seven_day"),',
            "    },",
            "}",
            "",
            "try:",
            "    os.makedirs(os.path.dirname(OUTPUT_PATH), exist_ok=True)",
            '    tmp_path = f"{OUTPUT_PATH}.tmp.{os.getpid()}"',
            '    with open(tmp_path, "w", encoding="utf-8") as handle:',
            '        json.dump(capture, handle, separators=(",", ":"))',
            "    os.replace(tmp_path, OUTPUT_PATH)",
            "except Exception:",
            "    pass",
            "",
            "if PREVIOUS_COMMAND:",
            "    try:",
            "        result = subprocess.run(PREVIOUS_COMMAND, input=raw, text=True, shell=True, capture_output=True, timeout=2)",
            '        output = (result.stdout or "").rstrip("\\n")',
            "        if output:",
            "            print(output)",
            "            sys.exit(0)",
            "    except Exception:",
            "        pass",
            "",
            'five = (rate_limits.get("five_hour") or {}).get("used_percentage")',
            'seven = (rate_limits.get("seven_day") or {}).get("used_percentage")',
            "parts = []",
            "if isinstance(five, (int, float)):",
            '    parts.append(f"5h {five:.0f}%")',
            "if isinstance(seven, (int, float)):",
            '    parts.append(f"7d {seven:.0f}%")',
            'print("Claude " + " · ".join(parts) if parts else "Claude")',
            "",
        ]
    )
    script_path.write_text(script, encoding="utf-8")
    script_path.chmod(script_path.stat().st_mode | stat.S_IXUSR | stat.S_IXGRP | stat.S_IXOTH)

    settings["statusLine"] = {
        "type": "command",
        "command": str(script_path),
        "refreshInterval": 30,
    }
    settings_path.write_text(json.dumps(settings, indent=2, sort_keys=True) + "\n", encoding="utf-8")

    print(f"installed={script_path}")
    print(f"settings={settings_path}")
    print("chained_previous=" + ("yes" if previous else "no"))


if __name__ == "__main__":
    main()
