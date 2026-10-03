---
uid: PJ7K2M
description: >-
  Represents this repository's project-state integration boundary where
  independently owned working, coordination, assurance, provenance, and
  retained record structures may coexist without becoming current product
  authority.
---
# Project State

This controlled sideband is the repository-local project-state integration
boundary defined by Repo Manager. It determines what may coexist here and how
the location participates in repository control; it does not acquire the
semantics of independently owned descendants.

The local structure is:

```text
.project/
├── README.md
├── Work/
│   ├── README.md
│   ├── drafts/README.md
│   ├── active/README.md
│   ├── blocked/README.md
│   └── review/README.md
└── Records/
    ├── README.md
    ├── Work/README.md
    ├── Research/README.md
    ├── Decisions/README.md
    ├── Fault/README.md
    ├── Audits/
    │   ├── README.md
    │   ├── document-audits/README.md
    │   └── workflow-audits/README.md
    └── User/README.md
```

Every directory beneath `.project/` is a meaningful project-state boundary
and therefore has a literal `README.md` describing its admission, placement,
transition, and routing semantics.

## Work

Work Management owns `Work/` and closed Work retained beneath
`Records/Work/`. Open lifecycle state is represented by directory placement:
`drafts`, `active`, `blocked`, or `review`.

Open Work filenames use `PP YYMMDD.## Concise title.md`; priority `50` is
the neutral default.

## Records

`Records/` is the default project-local integration boundary for retained
evidence, provenance, observations, findings, decisions, research, fault
history, assurance results, and user-originated provenance. Its children retain
their own semantic owners.

Current technical and operator authority remains outside this sideband.

## Publication and build behavior

This sideband is source-only project state. Docker excludes `.project/` from
the build context through the repository `.dockerignore`, and the image-build
workflow does not trigger for `.project/`-only changes.
