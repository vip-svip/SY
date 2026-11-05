#!/usr/bin/env python3
"""Host integration tests for the FX loopback-only DNS health probe."""
import os
import socket
import struct
import subprocess
import tempfile
import threading

SOURCE = os.path.join(os.path.dirname(__file__), "..", "localdns-probe.c")


def run_case(binary, flags=0x8180, expect=0, mutate=None, truncate=None):
    srv = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    srv.bind(("127.0.0.1", 0))
    port = srv.getsockname()[1]

    def serve():
        try:
            packet, peer = srv.recvfrom(2048)
            packet = bytearray(packet)
            packet[2:4] = struct.pack("!H", flags)
            packet[6:12] = b"\0" * 6
            if mutate:
                mutate(packet)
            if truncate is not None:
                packet = packet[:truncate]
            srv.sendto(packet, peer)
        finally:
            srv.close()

    thread = threading.Thread(target=serve, daemon=True)
    thread.start()
    result = subprocess.run(
        [binary, "127.0.0.1", str(port), "2"],
        capture_output=True,
        text=True,
        timeout=4,
    )
    thread.join(timeout=3)
    assert not thread.is_alive(), "DNS fixture server did not terminate"
    assert result.returncode == expect, (
        result.returncode, result.stdout, result.stderr, expect
    )
    return result


def flip_transaction_id(packet):
    packet[0] ^= 0x01


def alter_question(packet):
    # The generated health label starts at byte 12. Mutate its first byte.
    packet[13] ^= 0x01


def main():
    with tempfile.TemporaryDirectory(prefix="fx-dns-probe-") as tmp:
        binary = os.path.join(tmp, "probe")
        subprocess.run(
            ["cc", "-std=c11", "-O2", "-Wall", "-Wextra", "-Werror",
             SOURCE, "-o", binary],
            check=True,
        )

        # A recursive positive response and NXDOMAIN are both healthy answers.
        assert "PASS" in run_case(binary).stdout
        assert "PASS" in run_case(binary, 0x8183).stdout

        # The response must match the outstanding query and be a DNS response.
        assert run_case(binary, 0x8080, 73).returncode == 73  # QR missing
        assert run_case(binary, 0x8980, 73).returncode == 73  # non-zero opcode
        assert run_case(binary, 0x8380, 73).returncode == 73  # truncated UDP reply
        assert run_case(binary, mutate=flip_transaction_id, expect=73).returncode == 73
        assert run_case(binary, mutate=alter_question, expect=73).returncode == 73
        assert run_case(binary, truncate=10, expect=72).returncode == 72

        # A syntactically valid response without recursion availability is not
        # sufficient for the local recursive resolver health contract.
        assert run_case(binary, 0x8100, 74).returncode == 74
        assert run_case(binary, 0x8181, 75).returncode == 75  # SERVFAIL

        remote = subprocess.run(
            [binary, "192.0.2.1", "5353", "1"],
            capture_output=True, text=True, timeout=2
        )
        assert remote.returncode == 64 and "loopback" in remote.stderr

        for args in (
            ["127.0.0.1", "5353junk"],
            ["127.0.0.1", "65536"],
            ["127.0.0.1", "5353", "0"],
            ["127.0.0.1", "5353", "1", "extra"],
        ):
            p = subprocess.run(
                [binary] + args, capture_output=True, text=True, timeout=2
            )
            assert p.returncode == 64, (args, p.returncode, p.stderr)

    print(
        "PASS: loopback restriction, strict CLI parsing, valid/NXDOMAIN, "
        "transaction/question matching, malformed/truncated replies, "
        "recursion availability and upstream error RCODE checks"
    )


if __name__ == "__main__":
    main()
