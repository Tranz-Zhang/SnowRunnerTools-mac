# Manifest-Backed Conflict Resolution Design

## Overview

`ConflictDetailsView` currently lists duplicated mapped targets and the enabled
mods that contribute them. The next version will turn that screen into a
resolver that lets the user choose which mod version should win for each
conflicted target.

Resolution choices will be stored in the workspace manifest. Mod files stay in
their original `mods/<mod>/...` paths. No losing files are moved, renamed, or
deleted. The workspace verify/build path will read the manifest choices and
apply them before handing mapped entries to the merger.

## Goals

- Let users resolve mod-to-mod conflicts from the macOS app.
- Preserve every mod file in place.
- Store conflict choices explicitly in workspace metadata.
- Keep the UI focused on current conflicts only.
- Use gentler language for byte-identical candidates.
- Allow users to clear a saved choice and make the conflict unresolved again.

## Non-Goals

- Do not move conflict files into a disabled folder.
- Do not disable whole mods as a conflict-resolution mechanism.
- Do not show cleanup-only stale manifest data in the UI.
- Do not redesign the low-level archive writer.

## Conflict Resolution Model

Add a manifest section named `conflictResolutions`, containing one choice per
mapped output target. Each choice is keyed by:

- `targetArchive`
- `internalName`

Each choice stores the selected mod folder. The selected mod and mapped target
are the build inputs. Candidate source paths and content hashes belong in quick
verify conflict details, not in the first manifest schema.

Example shape:

```json
{
  "conflictResolutions": [
    {
      "targetArchive": "initial.pak",
      "internalName": "[media]\\classes\\trucks\\foo.xml",
      "selectedMod": "modA"
    }
  ]
}
```

## Conflict Resolution Updates

`conflictResolutions` changes only through explicit resolution actions or safe
workspace cleanup:

- `Use This Version` adds or replaces the saved choice for the target with the
  selected mod.
- `Keep One Copy` adds or replaces the saved choice for a byte-identical target
  with the selected mod.
- `Clear Resolution` removes the saved choice for that target.
- Workspace open, quick verify, and build prune saved choices that no
  longer correspond to a current multi-candidate conflict.

Conflict discovery is otherwise read-only. Finding a new conflict must not
write a resolution automatically. The manifest changes only when the user
chooses or clears a resolution, or when old irrelevant choices are safely
removed.

## Conflict States

The user-facing model has only two states:

- **Unresolved**: multiple current enabled candidates map to the same target,
  and no valid saved choice points to one of those current candidates.
- **Resolved**: multiple current enabled candidates map to the same target, and
  the saved choice points to one of those current candidates.

Invalid or obsolete saved choices are implementation details. If a saved choice
points to a removed mod, disabled mod, removed entry, renamed entry, or a target
that no longer has multiple candidates, the workspace manager prunes the choice
or treats it as absent before classifying current conflicts. The UI must not
show stale-resolution-only information because the task is to resolve current
conflicts.

## Workspace Verification

`PakWorkspaceManager.quickVerify` will produce richer conflict details than the
current `targetPath + mods` list. Each conflict detail includes:

- target archive
- internal target path
- display target path
- candidate mod folder names
- candidate original source paths
- candidate byte sizes and hashes
- whether the candidates are byte-identical
- selected mod when the conflict is resolved

Quick verify classifies current duplicate targets as resolved or
unresolved by validating each manifest choice against the current enabled mapped
entries. A valid choice must point to a current candidate for the same mapped
target.

Before classification, the workspace manager prunes saved choices that do not
correspond to a current multi-candidate target with the selected mod present. A
pruned choice is treated as absent. Cleanup-only events do not appear in
`ConflictDetailsView`.

## Workspace Build

Build becomes resolution-aware in the workspace layer:

```text
workspace mods -> mapped entries -> apply manifest choices -> ModMerger.mergeWorkspaceInitial(...)
```

For each duplicate mapped target:

- If a valid manifest choice exists, keep only the selected candidate for that
  target and filter out the losing candidates before merge.
- If no valid choice exists and candidate bytes differ, leave the duplicate
  entries unresolved so build fails as it does today.
- If no valid choice exists and candidates are byte-identical, leave the
  duplicate entries for the merger's existing identical-duplicate handling.
  Quick verify still reports the target as unresolved until the user chooses
  `Keep One Copy`.
- If candidates are byte-identical and a valid choice exists, keep the selected
  candidate.

The lower-level merger does not own manifest resolution. The workspace manager
owns resolution-aware filtering because it has access to the workspace manifest
and enabled mod metadata.

## User Interface

`ConflictDetailsView` becomes a two-pane resolver:

- left pane: target list with target path, status, and involved mods
- right pane: details for the selected target

Each candidate row shows:

- mod folder name
- original source path inside the mod
- selected winner marker when resolved
- content hint such as byte size and hash prefix
- action button

Action language:

- Different candidate bytes: `Use This Version`
- Byte-identical candidates: `Keep One Copy`
- Resolved conflicts: show selected winner and `Clear Resolution`

Choosing an action writes or replaces the manifest resolution, refreshes quick
verify, and keeps the user on the conflict details screen. Clearing a resolution
removes the manifest choice, refreshes quick verify, and makes the conflict
unresolved again if multiple current candidates still exist.

The workspace Quick Verify card distinguishes unresolved conflicts from
resolved conflicts. Unresolved conflicts keep the warning state. If every
current conflict is resolved, the card shows an “All conflicts resolved”
state while still offering `Show Conflict Details`.

## View Model And Service Flow

Add workspace service APIs for:

- loading resolution-aware conflict details through quick verify
- resolving a conflict target to a selected mod
- clearing a conflict resolution

`WorkspaceViewModel` gets async methods such as:

- `resolveConflict(targetArchive:internalName:selectedMod:)`
- `clearConflictResolution(targetArchive:internalName:)`

Both methods call the service, update manifest-backed workspace state, refresh
summary/quick verify data, and remain on `.conflictDetails`.

## Error Handling

Conflict resolution is conservative:

- If the selected mod/file no longer exists by the time the user clicks an
  action, refresh conflict details and leave the conflict unresolved.
- If manifest writing fails, show the existing app error message and keep the
  previous resolution state.
- If build sees unresolved conflicting candidates, it continues to fail.
- If build sees resolved conflicting candidates, it filters losing
  candidates before merge.
- Stale choices that no longer affect a current conflict are pruned or treated
  as absent before conflict classification.

## Tests

Core tests cover:

- quick verify reports an unresolved conflict when no manifest choice exists
- resolving a conflict writes the selected mod to the manifest
- quick verify reports a resolved conflict when the selected mod is still a
  current candidate
- build succeeds for a previously conflicting target when a valid resolution
  exists
- build output uses the selected candidate
- clearing a resolution makes the conflict unresolved again
- byte-identical candidates are identified so the UI can use `Keep One Copy`
- stale choices are ignored or cleaned when no current conflict remains
- stale choices are treated as unresolved when the target still has multiple
  current candidates and the selected mod is no longer valid

App tests cover:

- conflict details screen can show unresolved and resolved rows
- resolving a conflict calls the view model/service and refreshes quick verify
- clearing a conflict calls the view model/service and refreshes quick verify
- quick verify card can represent unresolved, resolved, and no-conflict states
