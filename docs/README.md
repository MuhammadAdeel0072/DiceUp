# DiceUp docs

## Source documents (not committed here)

The SRS and SDD are `.docx` binaries and the GitHub connector used for
this branch can only push UTF-8 text files, so they are not in this
folder. Their source copies live in the project workspace:

- **SRS v0.1** (16 Nov 2026, draft) — supplied by the team.
- **SDD v1.0** (21 Nov 2026) — derived from the SRS; 76 pages, 17
  sections, 11 UML diagrams, traceability FR-01…FR-82 verified 82/82.

To add the binaries to the repository, run from a machine with git
access (e.g. the owner's Windows machine, in the repo root):

```powershell
git checkout implementation/foundation-phase-2-3
Copy-Item <path-to>\DiceUp_SRS_v0.1.docx docs\
Copy-Item <path-to>\DiceUp_Software_Design_Document_v1.0.docx docs\
git add docs/*.docx
git commit -m "docs: add SRS v0.1 and SDD v1.0 source documents"
git push
```

## Living implementation docs (committed)

- `IMPLEMENTATION-PLAN.md` — Phase 1 audit, roadmap, risks, verification
  evidence. The plan of record for the implementation.
- `TRACEABILITY.md` — SRS ID → SDD section → module → implementation
  location → test case → status.
