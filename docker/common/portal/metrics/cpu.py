from __future__ import annotations

from pathlib import Path
from typing import Any

from .cgroups import detect_version, first_existing, parse_key_value_file, read_int, read_text


def _quota_cores(quota: int | None, period: int | None) -> float | None:
    if quota is None or period is None or quota < 0 or period <= 0:
        return None
    return quota / period


def read_cpu_metrics(root: Path) -> dict[str, Any]:
    version = detect_version(root)
    if version == "v2":
        stat = parse_key_value_file(root / "cpu.stat")
        max_text = read_text(root / "cpu.max") or "max 100000"
        parts = max_text.split()
        quota = None if not parts or parts[0] == "max" else int(parts[0])
        period = int(parts[1]) if len(parts) > 1 else 100000
        return {
            "version": "v2",
            "usageUsec": stat.get("usage_usec", 0),
            "quotaUsec": quota,
            "periodUsec": period,
            "quotaCores": _quota_cores(quota, period),
            "throttledUsec": stat.get("throttled_usec", 0),
        }

    usage_path = first_existing(root, ["cpuacct.usage", "cpu/cpuacct.usage", "cpu,cpuacct/cpuacct.usage"])
    quota_path = first_existing(root, ["cpu.cfs_quota_us", "cpu/cpu.cfs_quota_us", "cpu,cpuacct/cpu.cfs_quota_us"])
    period_path = first_existing(root, ["cpu.cfs_period_us", "cpu/cpu.cfs_period_us", "cpu,cpuacct/cpu.cfs_period_us"])
    usage_nsec = read_int(usage_path) if usage_path else None
    quota = read_int(quota_path) if quota_path else None
    period = read_int(period_path) if period_path else None
    return {
        "version": "v1",
        "usageUsec": int((usage_nsec or 0) / 1000),
        "quotaUsec": quota if quota is not None and quota >= 0 else None,
        "periodUsec": period,
        "quotaCores": _quota_cores(quota, period),
        "throttledUsec": 0,
    }
