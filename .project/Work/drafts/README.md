---
uid: DR6T1Q
description: >-
  Represents open Work that has been durably captured and prioritized but has
  not yet been explicitly admitted to execution.
---
# Draft Work

Place Work here when its outcome is durably captured but execution has not yet
begun. Assign priority `00` through `99`, using `50` as the neutral default,
and keep the immutable `YYMMDD.##` creation locator in its filename.

Move Work to `../active/` when execution is admitted. Use `../blocked/` only
for previously admitted Work that cannot progress, and `../review/` for
materially complete Work awaiting review or validation.

Closed Work moves to `../../Records/Work/`.
