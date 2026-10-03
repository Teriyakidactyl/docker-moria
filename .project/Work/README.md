---
uid: WK4R8N
description: >-
  Represents the Work Management storage boundary for open repository-local
  Work whose lifecycle is maintained through ordinary file operations.
---
# Work

This directory collects open Work files. A Work file is durable repository-local
state carrying one executable or coordinating outcome independently of
conversation history.

Open lifecycle state is represented by the containing directory. Every open Work
file has priority `00` through `99`; use `50` when no stronger ordering is
justified. Open filenames use:

```text
PP YYMMDD.## Concise title.md
```

Closed Work moves to `../Records/Work/`.

## Local routing

- `drafts/` — captured but not yet admitted to execution.
- `active/` — admitted Work holding execution attention.
- `blocked/` — admitted Work prevented from progressing by a named condition.
- `review/` — materially complete Work awaiting a declared review or
  validation condition.

Repo Manager Work Management guidance owns lifecycle semantics; this README
specializes storage for this repository.
