# /// script
# requires-python = ">=3.9"
# description = "Compute the server_key for device provisioning from the server's SECRET_KEY."
# ///
"""
Compute server_key for IoT device provisioning.

The puzzle authentication protocol requires the device to know
server_key = SHA256(SECRET_KEY + "|puzzle_v1"). This script reads
the SECRET_KEY from the server's .secrets file and computes the
server_key_hex value to put in the device's config.json.

Usage:
    uv run compute_server_key.py <path_to_secrets_file>
    uv run compute_server_key.py --key <SECRET_KEY_VALUE>

The .secrets file is created by install.sh and stored at
~/.iot-platform/.secrets on the server host. Look for the
SECRET_KEY= line.
"""

import hashlib
import sys
from pathlib import Path


def compute_server_key(secret_key: str) -> str:
    """Derive server_key hex from the server's SECRET_KEY."""
    raw = (secret_key + "|puzzle_v1").encode("utf-8")
    digest = hashlib.sha256(raw).digest()
    return digest.hex()


def extract_secret_from_file(filepath: Path) -> str:
    """Extract SECRET_KEY from a .secrets file (KEY=value format)."""
    for line in filepath.read_text().splitlines():
        line = line.strip()
        if line.startswith("SECRET_KEY="):
            return line.split("=", 1)[1].strip().strip('"').strip("'")
    raise ValueError("SECRET_KEY not found in {}".format(filepath))


def main() -> None:
    if len(sys.argv) < 2:
        print("Usage:")
        print("  uv run compute_server_key.py <path_to_secrets_file>")
        print("  uv run compute_server_key.py --key <SECRET_KEY_VALUE>")
        print()
        print("Example:")
        print("  uv run compute_server_key.py ~/.iot-platform/.secrets")
        sys.exit(1)

    if sys.argv[1] == "--key":
        if len(sys.argv) < 3:
            print("Error: --key requires a value")
            sys.exit(1)
        secret_key = sys.argv[2]
    else:
        secrets_path = Path(sys.argv[1])
        if not secrets_path.exists():
            print("Error: file not found: {}".format(secrets_path))
            sys.exit(1)
        secret_key = extract_secret_from_file(secrets_path)

    server_key_hex = compute_server_key(secret_key)

    print()
    print("SECRET_KEY: {}...{}".format(secret_key[:8], secret_key[-4:]))
    print()
    print("server_key_hex (64 chars, paste into config.json):")
    print(server_key_hex)
    print()
    print("Verification: {} bytes".format(len(bytes.fromhex(server_key_hex))))


if __name__ == "__main__":
    main()
