# shared_verify_tools

Two small scripts for checking that Fortran code survived a move or refactor,
whether the move was done by hand or by an LLM. Python 3.7+ and git; no other
dependencies, no model build.

| Tool | Question it answers |
|---|---|
| `bin/fbody` | Is the body of this subroutine/function the same code in its new place, statement for statement? If not, which statements changed? |
| `bin/fsig` | Did any procedure signature change between two revisions? Do the call sites match the signature positionally? |

## Why

When a subroutine is "copied" from one file to another, especially by an LLM,
it is usually read and re-emitted rather than moved byte for byte. Regression
tests catch answer changes eventually, hours later on a cluster. These tools
answer a narrower question in under a second: once comments, indentation,
alignment, continuation-line wrapping and letter case are ignored, is the code
in the new place the same code? Where it is not, the diff shows only the real
changes, so every one of them can be accounted for (a constant threaded as an
argument, an abort turned into an error return) or caught.

The output is deterministic and pastes into a PR as provenance. Nothing here
needs an AI to run.

## Install

```
git clone <this repo> shared_verify_tools
export PATH="$PWD/shared_verify_tools/bin:$PATH"   # or call bin/fbody directly
```

Both scripts print `--help`. Exit status is 0 when nothing differs, 1 when
there is something to look at, 2 on a usage error or a file / revision that
cannot be read (one-line message on stderr).

## fbody: procedure bodies

```
fbody SPEC                                list program units (lines, kind, name)
fbody SPEC UNIT                           print the normalized body of UNIT
fbody --diff SPEC UNIT SPEC2 [UNIT2]      diff UNIT against its copy in SPEC2;
                                          give UNIT2 when it was renamed
fbody --walk SPEC SPEC2 [SPEC3 ...]       every unit of SPEC looked up by name in
                                          SPEC2...: one verdict line per unit
  --map OLD=NEW      treat identifiers OLD and NEW as the same on both sides
                     (repeatable); --map r8=kind_phys also covers 1.0_r8
  --rename OLD=NEW   with --walk: look OLD up under the name NEW (repeatable)
  --show             with --walk: print the diff under each non-identical unit
```

A `SPEC` is one of

| Form | Reads |
|---|---|
| `path/to/file.F90` | the working-tree file |
| `REV:path/from/repo/root.F90` | that revision from the repo you are standing in |
| `DIR:REV:path/from/repo/root.F90` | that revision from the repo at `DIR`, so two repos can be compared at fixed commits |

Verdicts from `--walk`:

| Verdict | Meaning |
|---|---|
| `IDENTICAL` | same statements after normalization |
| `DIFF n` | `n` statements added or removed; `--show` prints them |
| `NOT FOUND` | no unit of that name in any target; a rename, or a real omission |

Normalization: comments are stripped, continuation lines are joined,
everything outside string literals is lowercased and runs of blanks collapse
to one. Blanks inside a statement are not removed, so `a(i,k)` and `a(i, k)`
still differ; this keeps the diffs readable and keeps style drift visible.
When a unit is compared under a new name, the new name is folded back to the
old one so the diff shows only body changes. Internal procedures are found
individually; interface bodies are skipped.

### Example

`examples/fbody/a.F90` is an original module: an interface block, a
subroutine `outer` with an internal function `helper`, and a subroutine
`second`. `examples/fbody/b.F90` is what a typical "copy" looks like:
`outer` renamed to `outer_run`, re-indented, comments dropped, one
continuation line joined and another introduced, `INTEGER` uppercased, the
kind swept from `r8` to `kind_phys`, and one real change slipped into
`second`.

```
$ fbody examples/fbody/a.F90
   10-25    subroutine outer
   21-24    function     helper
   27-31    subroutine second
```

Walking the original against the copy, telling fbody about the kind sweep and
the rename:

```
$ fbody --walk examples/fbody/a.F90 examples/fbody/b.F90 --map r8=kind_phys --rename outer=outer_run --show
IDENTICAL  outer                            subroutine    16 -> 16    examples/fbody/b.F90:outer_run
IDENTICAL  helper                           function       4 -> 5     examples/fbody/b.F90
DIFF 2     second                           subroutine     5 -> 4     examples/fbody/b.F90
    --- examples/fbody/a.F90:second (subroutine, lines 27-31)
    +++ examples/fbody/b.F90:second (subroutine, lines 22-25)
    @@ -1,4 +1,4 @@
     subroutine second(msg)
     character(len=*), intent(in) :: msg
    -write(*,*) 'subroutine fake was called! '//msg
    +write(*,*) 'subroutine fake was called! '//trim(msg)
     end subroutine second
```

The restyling is invisible; the one real change is the only thing reported.
Without `--map` and `--rename` the same walk shows what those options are for:

```
$ fbody --walk examples/fbody/a.F90 examples/fbody/b.F90
NOT FOUND  outer                            subroutine    16
DIFF 4     helper                           function       4 -> 5     examples/fbody/b.F90
DIFF 2     second                           subroutine     5 -> 4     examples/fbody/b.F90
```

### Typical use: a CAM scheme moved to a portable CCPP module

Standing in the CAM checkout, compare the original file at the pre-refactor
tag against the new portable file and the CAM wrapper that kept the host glue.
List the portable file first: when the wrapper keeps a same-named marshal
routine, the first target wins and `(also in ...)` is appended.

```
cd /path/to/CAM     # cam_development; the original file exists only at the old tag
fbody --walk cam6_4_189:src/chemistry/aerosol/aero_convproc.F90 \
      src/chemistry/aerosol/aero_convproc_cam.F90 \
      /path/to/atmospheric_physics:main:schemes/aerosol/core/aero_convproc.F90 \
      --map r8=kind_phys --rename aero_convproc_tend=aero_convproc_run
#   IDENTICAL  aero_convproc_readnl   subroutine   43 -> 43    src/chemistry/aerosol/aero_convproc_cam.F90
#   DIFF 14    aero_convproc_init     subroutine  142 -> 143   src/chemistry/aerosol/aero_convproc_cam.F90
#   ...
#   DIFF 585   aero_convproc_tend     subroutine  926 -> 919   /path/to/atmospheric_physics:main:...:aero_convproc_run
```

The wrapper routines that stayed in CAM come back IDENTICAL or with a few lines
of host glue; the portable routines show the aerosol-object refactor that the
port made on purpose. Add `--show` to read those diffs. The `DIR:REV:PATH` form
pins both repositories to fixed commits, which is what a PR description wants.

Read every `DIFF` with `--show` and confirm each changed statement is host
decoupling and not science: dimensions and constants threaded as arguments,
assumed-shape dummies, `endrun` turned into `errmsg`/`errflg`, logging
removed. Paste the walk output into the PR.

### Limitations

- Free-form Fortran only.
- Procedure bodies only. Module-level `use` lines and declarations are not
  compared; use plain `diff` for whole files.
- `--map` is a token replacement applied to both sides before diffing, so
  identifiers such as `dtype_r8` display as `dtype_kind_phys` in the diff.
- Signatures with a `bind(c)` suffix are not recognized as units.

## fsig: signatures and call sites

```
fsig SPEC ...                    one line per subroutine/function: name(args)
fsig --calls NAME SPEC           normalized call statements of NAME
fsig --diff SPEC SPEC2           unified diff of the signatures of two specs
                                 (no output, exit 0, when they match)
```

`SPEC` takes the same three forms as for `fbody`. Continuation lines are joined, comments stripped, all whitespace removed and
names lowercased, so signatures from two revisions diff cleanly. Use
`--calls` next to the signature to check a positional call after an argument
was added.

```
$ fsig --diff examples/fbody/a.F90 examples/fbody/b.F90
--- examples/fbody/a.F90
+++ examples/fbody/b.F90
@@ -1,2 +1 @@
-subroutine ext_sub(x)
-subroutine outer(n,x,y)
+subroutine outer_run(n,x,y)

$ fsig --calls ext_sub examples/fbody/a.F90
call ext_sub(y(1))
```

`fsig` lists interface-block declarations too (`ext_sub` above); `fbody`
skips them because they have no body.

## Provenance

Both scripts were written with Claude Code. `fbody` is the generic core of a
project-specific verifier used during the CCPP-ization of the CAM modal
aerosol code; on that project's transfer of 19 files to
`atmospheric_physics` it reports every moved procedure `IDENTICAL` modulo the
`r8` to `kind_phys` sweep. Issues and pull requests welcome.
