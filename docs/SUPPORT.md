# 0.1.0 support matrix

The manifest is version `0.1.0` and the candidate is unreleased.

| Area | Candidate support |
| --- | --- |
| Toolchain | Required GitHub Actions uses `ghcr.io/zaplang-io/zap:latest`. |
| CI platform | Linux x86-64 on GitHub-hosted runners. |
| Installation | An external Zap project adds a reviewed checkout as a path dependency, materializes it into `zenv`, and imports `msgpack` from the installed package. CI also validates package metadata with a dry run. |
| Wire format | MessagePack base types, all fixed and variable application extension headers, and all three Timestamp formats. Modern and legacy packing modes have exact-byte fixtures. |
| Maps | Ordered key/value pairs preserve every duplicate. Strict decoding accepts string and binary keys. Explicit conversion lets applications select their duplicate policy. |
| Streaming | `Packer.pack` returns bytes per call. `Unpacker.feed`, `unpack`, and iteration retain partial frames. The default unread-byte budget is 100 MiB. |
| Decode limits | Per-type caps are configurable. The default nesting cap is 1,024 levels, and complete headers are checked before allocating the decoded body. |
| Extensions and datetime | Application codes 0 through 127, typed top-level hooks, and exact Timestamp nanoseconds. Aware `DateTime` inputs convert to Unix seconds, and the decoded datetime helper returns aware UTC in years 1 through 9999. |
| Python option mapping | The [option table](../README.md#msgpack-python-options) lists the default behavior and the corresponding explicit conversions. |

[Release checklist and install instructions](RELEASING.md)
