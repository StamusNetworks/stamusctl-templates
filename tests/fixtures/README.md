# Test Fixtures

## Included PCAP Files

These PCAPs are sourced from the [testmynids.org](https://github.com/3CORESec/testmynids.org) project
(Shadow Brokers collection). They contain well-known exploit traffic that Suricata's ET Open rules detect reliably.

### `eternalblue.pcap` (348 KB, 576 packets)

**EternalBlue (MS17-010)** — successful exploitation of an unpatched Windows 7 host.

| Field | Value |
|-------|-------|
| Attacker | 192.168.198.204 |
| Victim | 192.168.198.203 |
| Protocol | SMB (port 445) |
| Attack | MS17-010 EternalBlue buffer overflow |
| Result | Remote code execution |

**Expected Suricata alerts:**
- `ET EXPLOIT Possible ETERNALBLUE MS17-010`
- `ET EXPLOIT Possible DOUBLEPULSAR`
- SMB-related signatures

### `eternalromance-meterpreter.pcap` (1.6 MB, 740 packets)

**Full exploit chain:** EternalRomance exploit + DoublePulsar backdoor install + Meterpreter reverse shell session.

| Field | Value |
|-------|-------|
| Attacker | 10.99.99.8 |
| Victims | 10.99.99.182, 10.99.99.189 |
| Protocols | SMB (445), Meterpreter (4444) |
| Attack stages | Exploit → Backdoor → C2 |
| Kill chain | Exploitation → Installation → Command & Control |

**Expected Suricata alerts:**
- `ET EXPLOIT Possible ETERNALROMANCE`
- `ET EXPLOIT Possible DOUBLEPULSAR`
- `ET TROJAN Meterpreter` or reverse shell signatures
- Multiple SMB anomaly signatures

This PCAP exercises the full kill chain and is ideal for validating multi-stage detection.

## Custom PCAP Files

You can override the default fixture by setting `PCAP_FILE`:

```bash
PCAP_FILE=/path/to/custom.pcap just test
```

Tests will skip (not fail) if no PCAP file is found and no fixture exists.
