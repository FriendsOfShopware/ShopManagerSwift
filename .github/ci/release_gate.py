"""Require full and minimum verification of the exact checked-out release SHA."""

import os
import subprocess


def verify_release(head, full_sha, full_mode, minimum_sha, minimum_mode):
    if not head or full_sha != head or minimum_sha != head:
        raise ValueError("Release verification belongs to another commit or is missing")
    if full_mode != "full" or minimum_mode != "compatibility":
        raise ValueError("Only full regression and minimum compatibility can authorize release signing")


if __name__ == "__main__":
    head = subprocess.check_output(["git", "rev-parse", "HEAD"], text=True).strip()
    verify_release(head, os.environ.get("VERIFIED_SHA"), os.environ.get("VERIFIED_MODE"),
                   os.environ.get("MINIMUM_SHA"), os.environ.get("MINIMUM_MODE"))
    print(f"Full and minimum checks verified release {head}")
