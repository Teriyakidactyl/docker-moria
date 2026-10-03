---
uid: AC9V3H
description: >-
  Represents open Work that has been admitted to execution and currently
  carries execution attention.
---
# Active Work

Work belongs here after an explicit decision to begin execution.

Each file keeps an explicit priority and immutable `YYMMDD.##` creation
locator, plus enough Current state and Next action information to resume without
conversation history.

Move Work to `../blocked/` when a named condition prevents progress, to
`../review/` when primary execution is materially complete but review remains,
or to `../../Records/Work/` when attention closes.
