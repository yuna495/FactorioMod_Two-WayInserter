# Two-Way Inserter Specification

## 1. Project

**Mod name:** Two-Way Inserter
**Project folder:** `Two-WayInserter`

Two-Way Inserter extends existing Factorio inserter entities with an optional **two-way / return-trip mode**.

The mod does not primarily add a new inserter prototype. Instead, inserter entities that already use the Factorio `inserter` prototype type can be given a two-way mode.

The purpose is to let one physical inserter use both halves of its arm movement for item transport:

- Forward trip: A -> B
- Return trip: B -> A

A normal inserter normally carries items only in its placed direction and returns empty. In two-way mode, the return movement may also carry an item when the reverse side has something valid to move.

---

## 2. Core concept

When an inserter is placed in the normal Factorio direction:

```text
A -> B
```

the original pickup side, **A**, is the primary side.

The original placement direction is always the **forward / primary direction**:

```text
Forward: A -> B
Reverse: B -> A
```

Two-way mode must not redefine the original placement direction based on the inserter's current arm position or temporary reverse state.

The mod must preserve the concept of a permanent primary direction even while the physical inserter is temporarily operating in reverse.

---

## 3. Two-way mode

Two-way behavior is an optional mode added to existing inserters.

### 3.1 Disabled

When two-way mode is disabled, the inserter behaves as a normal Factorio inserter.

```text
A -> B
B -> A return movement is empty
```

The mod should interfere as little as possible with normal inserter behavior while the mode is disabled.

### 3.2 Enabled

When two-way mode is enabled:

```text
A -> B
```

remains the primary direction.

The inserter attempts to use the return trip for transport whenever appropriate.

Conceptually:

```text
A --item--> B
A <--item-- B
```

A single physical arm round trip may therefore perform two item transfers.

---

## 4. Forward priority

The original placed direction has priority.

For an inserter placed as:

```text
A -> B
```

the preferred pickup side is always A.

The mod must not treat forward and reverse as equal-priority directions.

The reverse direction exists as a return-trip opportunity and as a fallback check while forward transport is idle.

---

## 5. Normal forward-to-reverse cycle

After a successful forward transfer:

```text
A -> B
```

the inserter has reached the B side.

At that point, instead of necessarily returning empty, the mod should attempt a reverse pickup:

```text
B -> A ?
```

### 5.1 Reverse item available

If the inserter can validly pick up an item from B and deliver it to A:

```text
A -> B completed
B -> A available
B -> A completed
```

After the reverse transfer completes, the inserter returns to the forward / primary profile.

### 5.2 Reverse item unavailable

If nothing valid can be transferred from B to A:

```text
A -> B completed
B -> A probe
no valid transfer
```

the inserter must return to the normal forward state:

```text
A -> B
```

The reverse state must not become the new default direction.

---

## 6. Forward-idle reverse probing

A two-way inserter must also periodically check the reverse direction when the forward direction cannot currently perform work.

Example:

- A contains material.
- B is an assembling machine.
- B currently does not accept more input.
- The inserter is therefore idle in the forward direction.
- B may meanwhile contain an output item that could be moved back to A.

In this situation, the mod should periodically probe:

```text
B -> A
```

If the reverse transfer succeeds, perform it and then restore the forward profile.

If it does not succeed, restore the forward profile and try again later.

### 6.1 Probe interval

The exact reverse-probe interval is **not yet fixed**.

A value around 10 ticks has been discussed as an initial prototype value, but it is not yet a final requirement.

Implementation should keep this interval configurable internally so it can be tuned after gameplay and UPS testing.

---

## 7. Transfer decision philosophy

The mod should prefer using Factorio's own inserter behavior to determine whether a transfer is valid.

The mod should not unnecessarily reimplement machine recipe logic, input/output inventory logic, or item compatibility logic.

When possible, the mod should:

1. Apply the appropriate direction profile to the real inserter.
2. Let Factorio determine whether the inserter can pick up and drop an item.
3. Observe whether the transfer proceeds.
4. Restore or switch profiles according to the two-way state machine.

This is intended to keep the feature generic across:

- Chests
- Logistic chests
- Belts
- Assembling machines
- Furnaces
- Cargo wagons
- Other compatible entities
- Modded machines where normal Factorio inserters already work

The mod must not assume that the forward item is an ingredient or that the reverse item is a finished product.

---

## 8. Example: assembling machine

Example layout:

```text
Buffer chest A
    |
    | iron plates
    v
  Inserter
    ^
    | iron gears
    |
Assembler B
```

Primary direction:

```text
A -> B
```

The inserter supplies iron plates to the assembling machine.

After reaching B, or while forward transfer is idle, it may probe:

```text
B -> A
```

and carry iron gears back to the same buffer chest.

The mod does not need to understand that iron plates are ingredients or that iron gears are products. Factorio's normal inserter rules should decide what can be moved.

---

## 9. Example: chest-to-chest behavior

If both A and B are chests and A initially contains one iron plate:

```text
A: iron plate x1
B: empty
```

with a two-way inserter placed:

```text
A -> B
```

the following is technically valid:

```text
A -> B : iron plate
B -> A : iron plate
```

Thus one physical round trip can perform two transfers.

Whether this results in useful behavior depends on the forward and reverse filter profiles.

Direction-specific filters are therefore an important part of the mod.

---

## 10. Direction profiles

A two-way inserter conceptually has two independent configuration profiles:

```text
Forward profile: A -> B
Reverse profile: B -> A
```

The physical entity is still one inserter.

The mod stores the two logical profiles and applies the currently active profile to the real inserter when direction changes.

The forward profile is the primary profile.

---

## 11. Forward profile

The forward profile corresponds to the inserter's normal placed direction and should remain as close as possible to normal Factorio behavior.

Where practical, the existing vanilla inserter GUI should represent the forward profile.

The forward profile may include normal inserter settings such as:

- Pickup/drop positions
- Filter enabled state
- Filter mode
- Filter contents
- Stack size override
- Spoilage priority where supported
- Circuit-related settings where supported

Not every setting is guaranteed to be direction-specific in the first implementation. See unresolved items below.

---

## 12. Reverse profile

The reverse profile is stored by Two-Way Inserter and applied while the inserter operates or while the player explicitly edits the reverse profile:

```text
B -> A
```

The goal is for the reverse direction to support its own independent normal-inserter settings where practical.

At minimum, the design should support independent reverse settings for:

- Filter enabled state
- Filter mode
- Filter contents
- Stack size override

Example:

```text
Forward A -> B
Filter mode: Whitelist
Filter: iron-plate

Reverse B -> A
Filter mode: Blacklist
Filter: iron-plate
```

This allows the inserter to send iron plates from A to B without immediately carrying the same plates back from B to A.

Where supported and useful, additional normal inserter properties may also become direction-specific.

---

## 13. Filter behavior

Forward and reverse filters are independent.

The user must be able to configure, for example:

```text
Forward A -> B
Whitelist: iron-plate
```

and:

```text
Reverse B -> A
Blacklist: iron-plate
```

The reverse profile must not automatically inherit the forward filter configuration unless explicitly chosen by future design.

The same applies to stack size overrides: forward and reverse may use different values.

In the editor GUI model, these direction-specific settings are edited through
Factorio's normal inserter GUI after the player switches the Two-Way Inserter
edit target to the desired direction. Two-Way Inserter stores the resulting
physical inserter settings as the selected logical profile.

---

## 14. Position handling

### 14.1 Base behavior

Two-Way Inserter requires runtime-adjustable inserter pickup/drop positions.

For compatible inserter prototypes, the mod may need to ensure:

```lua
allow_custom_vectors = true
```

so that pickup and drop positions can be changed at runtime.

### 14.2 Shared-position model

The default runtime compatibility model is that forward and reverse are two stored profiles for the same physical inserter.

If the configured endpoints are:

```text
A position
B position
```

then:

```text
Forward:
pickup = A
drop   = B

Reverse:
pickup = B
drop   = A
entity direction = reverse-facing runtime direction
```

This keeps position configuration simple and works naturally with normal inserters.

The persistent primary endpoint pair must not be overwritten while applying or
editing the temporary reverse profile. However, the physical inserter must
still receive the active profile's runtime direction, pickup/drop positions,
filters, and other supported settings, because Factorio's inserter logic uses
the physical entity state.

The stored primary direction remains the permanent source of truth for Forward.
Temporarily applying the reverse-facing physical direction must not redefine
the stored primary direction.

When Smart Inserters or another arm-position mod configures pickup/drop
coordinates before the reverse profile has been customized, the reverse
runtime positions must use the same coordinate configuration mirrored through
the inserter center and the reverse runtime direction:

```text
Forward:
pickup = configured pickup coordinate on A side
drop   = configured drop coordinate on B side

Reverse:
pickup = mirrored configured pickup coordinate on B side
drop   = mirrored configured drop coordinate on A side
```

For example, if Forward is configured as:

```text
A belt far lane -> B belt near lane
```

then Reverse should be:

```text
B belt far lane -> A belt near lane
```

The mod must not blindly swap the full absolute pickup/drop positions when
doing so would turn the Forward drop setting into the Reverse pickup setting.

---

## 15. Smart Inserters compatibility

Smart Inserters is treated as an optional compatibility target, not as a required dependency.

Two-Way Inserter must not require modifications to Smart Inserters.

The current intended compatibility scope is limited.

### 15.1 Supported compatibility goal

Smart Inserters may be used to configure whichever logical profile is currently
selected in the Two-Way Inserter GUI.

Before the reverse profile has been explicitly edited, Two-Way Inserter derives
its reverse pickup/drop positions from the forward profile by mirroring the
forward pickup and drop coordinates around the inserter center:

```text
Forward:
A -> B

Initial Reverse:
B -> A using mirrored forward pickup/drop coordinates
```

After the player switches the edit target to Reverse and edits Smart Inserters
or vanilla inserter settings, the resulting physical inserter settings are
stored as the reverse profile. Subsequent forward edits must not silently
overwrite that customized reverse profile.

### 15.2 Direction-specific Smart Inserters positions

Independent Smart Inserters positioning for forward and reverse is supported by
editing one logical profile at a time through the existing physical inserter.
Two-Way Inserter does not duplicate Smart Inserters' GUI. Instead, its own
relative GUI selects whether the real inserter is currently presenting the
Forward or Reverse profile to vanilla and Smart Inserters GUIs.

Example of a supported direction-specific configuration:

```text
Forward:
A outer belt lane -> B inner belt lane

Reverse:
B outer belt lane -> A inner belt lane
```

This is implemented by saving the real inserter's current pickup/drop positions
into the active profile when the player switches edit target or closes the GUI.
Because Smart Inserters edits the active physical inserter through its own GUI,
this lets Two-Way Inserter reuse Smart Inserters' normal controls without
copying or modifying Smart Inserters internals.

Therefore the initial compatibility rule is:

> Smart Inserters position editing is reused by switching which logical profile
> is applied to the physical inserter. Two-Way Inserter stores the Forward and
> Reverse pickup/drop positions separately, while still keeping the original
> Forward direction as the permanent primary direction.

### 15.3 Optional event integration

If Smart Inserters exposes a stable public event notifying other mods that arm positions changed, Two-Way Inserter may listen to that event and update the stored profile that is currently being edited.

Two-Way Inserter may also raise that public event after it applies a stored
profile to the physical inserter, so Smart Inserters can refresh its own GUI
from the actual inserter state.

Compatibility must use public interfaces/events only.

Do not copy, modify, or depend on Smart Inserters internal implementation details.

---

## 16. Circuit network concept

A direction-specific circuit convention is desired.

Proposed convention:

```text
Red wire   = Forward profile / A -> B
Green wire = Reverse profile / B -> A
```

This gives the two logical directions a clear circuit identity despite sharing one physical inserter.

Example:

```text
Red network:
enable A -> B when iron plates < threshold

Green network:
enable B -> A when gears > threshold
```

### 16.1 Implementation requirement

The exact implementation method is not yet fixed.

Preferred implementation, if Factorio's inserter control behavior permits it cleanly:

- Forward state reads only the red circuit network.
- Reverse state reads only the green circuit network.

If the vanilla inserter control behavior cannot cleanly isolate red and green networks per active direction, Two-Way Inserter may need to read signals itself and reproduce only the required direction-specific circuit behavior.

This must be verified during implementation.

### 16.2 Scope caution

Direction-specific circuit behavior is a desired feature, but it is more complex than filters and stack size.

The implementation should not compromise basic two-way transport stability merely to support full circuit parity in the first version.

---

## 17. GUI design

The vanilla inserter GUI cannot be assumed to support direct modification, tab injection, or replacement.

The current GUI design therefore treats:

```text
Vanilla inserter GUI = current Two-Way edit target
```

and adds a minimal Two-Way Inserter relative GUI for selecting that edit target.

### 17.1 Forward settings

When the Two-Way edit target is Forward, the normal Factorio inserter GUI represents the primary:

```text
A -> B
```

configuration wherever practical.

This keeps ordinary inserter setup familiar.

### 17.2 Reverse settings

When the Two-Way edit target is Reverse, the same normal Factorio inserter GUI
and any compatible inserter-position GUI, such as Smart Inserters, edit the
reverse profile currently applied to the physical inserter.

Two-Way Inserter should add a relative GUI associated with the opened inserter.

The Two-Way GUI should contain only the settings that cannot be represented by
the currently applied physical inserter profile:

```text
Two-Way mode enable/disable
Edit target: Forward / Reverse
```

Filters, stack size override, pickup/drop positions, and Smart Inserters arm
positions are edited through the vanilla inserter GUI or the other mod's
existing GUI for whichever profile is currently selected.

### 17.3 Preferred visual concept

A possible layout is:

```text
+----------------------+  +----------------------+
| Vanilla Inserter GUI |  | Two-Way Inserter     |
|                      |  | Two-Way: ON/OFF      |
| Selected profile     |  | Edit: Forward/Reverse|
|                      |  |                      |
| Filters              |  |                      |
| Stack size           |  |                      |
| Arm positions        |  |                      |
+----------------------+  +----------------------+
```

The exact visual layout is not fixed.

A tabbed solution would be elegant if Factorio's GUI API ever makes it practical, but the project must not depend on being able to tabify the vanilla GUI.

### 17.4 Smart Inserters GUI coexistence

Smart Inserters also uses relative GUI near the inserter GUI.

Two-Way Inserter must avoid assuming exclusive ownership of the right side of the vanilla inserter GUI.

If necessary, Two-Way Inserter may place its relative GUI:

- On another side, or
- In another stable relative position

when Smart Inserters is installed.

Exact coexistence layout is an implementation detail.

---

## 18. GUI-open behavior

Because the physical inserter's active runtime settings may change when switching between forward and reverse profiles, allowing profile switching while the player is editing the vanilla GUI could make the visible vanilla settings change unexpectedly.

Preferred behavior:

1. When a player opens a two-way inserter GUI, normalize the inserter to the forward profile when safe.
2. If two-way mode is enabled, temporarily deactivate the physical inserter with the Factorio script-disable flag while it is being edited.
3. Treat the vanilla GUI and compatible position GUIs as editors for the selected edit target.
4. When the edit target is Forward, apply the stored forward-facing profile to the physical inserter.
5. When the edit target is Reverse, apply the stored reverse-facing profile to the physical inserter so the visible direction matches the profile being edited.
6. Suspend reverse probing / reverse switching while the relevant inserter GUI is open.
7. Save the currently selected profile when the edit target changes or the GUI closes.
8. Restore the forward profile and the pre-edit script-disabled state when editing ends.
9. Resume normal two-way operation after the GUI is closed.

This keeps the rule:

```text
Vanilla GUI = selected edit target
```

stable and understandable.

---

## 19. Runtime state model

Each enabled two-way inserter should maintain enough persistent state to distinguish at least:

- Primary / forward endpoints
- Forward profile
- Reverse profile
- Current logical direction
- Whether a reverse probe is in progress
- Whether the inserter is waiting for a forward-idle probe
- Last relevant probe tick or equivalent scheduling state

Possible conceptual states:

```text
FORWARD
REVERSE_PROBE
REVERSE_TRANSFER
```

An implementation may use a different state representation as long as behavior remains equivalent.

---

## 20. Direction switching safety

Do not change direction in a way that corrupts an in-progress transfer.

The mod must account for the inserter currently holding an item.

Direction/profile switching should occur only at safe points.

At minimum:

- Do not arbitrarily swap pickup/drop positions while an item is being carried in a way that could lose, duplicate, or incorrectly redirect the held item.
- A transfer already in progress should normally be allowed to complete under the profile that initiated it.
- Profile changes should occur at well-defined arm/transfer boundaries.

Exact event/state detection should be determined during implementation and testing.

### 20.1 GUI editing exception

While a two-way inserter is open for GUI editing and has been temporarily
disabled by script, the player must be able to switch the visible edit target
between Forward and Reverse even if the inserter is currently holding an item.

In this editor-only state, Two-Way Inserter may apply and capture profile
settings while an item is held, because the inserter is not allowed to continue
transporting until the GUI edit session ends. This exception exists to keep
Forward and Reverse settings accessible in the same way a normal inserter can
still be rotated while holding an item.

Automatic runtime profile switching outside GUI editing should remain
conservative and avoid changing profiles while an item is held unless the
specific transition is known to be safe.

---

## 21. Performance / UPS requirements

The mod should remain suitable for large Factorio factories.

Avoid designs that perform expensive entity searches for every enabled inserter every tick.

### 21.1 Preferred approach

Track only inserters that have two-way mode enabled.

Use lightweight state checks and scheduled reverse probes.

When periodic checks are needed:

- Distribute work across ticks.
- Avoid synchronizing all two-way inserters on the same tick.
- Avoid repeated `find_entities_filtered` or similar world searches when stored entity references/state are sufficient.

### 21.2 Probe frequency

The reverse probe interval must be tunable during development.

Responsiveness should be balanced against UPS cost.

---

## 22. Existing inserter prototypes

The feature should work with existing entities whose prototype type is `inserter`, including compatible inserters added by other mods where practical.

The preferred design is not to create separate "two-way" copies of every inserter prototype.

Two-way behavior is a mode/state attached to the existing placed inserter.

Compatibility exceptions may be added for inserters whose custom behavior is incompatible with runtime pickup/drop changes.

---

## 23. Data-stage compatibility

Where required, compatible inserter prototypes may be patched so runtime pickup/drop vectors can be changed.

Any such data-stage patch should be as narrow as practical.

Do not assume that every modded inserter is automatically safe to modify.

If a compatibility exclusion system becomes necessary, add one rather than forcing behavior onto known-incompatible inserters.

---

## 24. Blueprint, copy/paste, upgrade, clone, and migration behavior

These behaviors are important but are **not yet fully specified**.

Future implementation must determine how to preserve:

- Two-way enabled/disabled state
- Reverse filters
- Reverse stack size
- Reverse circuit configuration
- Any additional reverse profile properties

across:

- Blueprints
- Entity settings copy/paste
- Entity cloning
- Fast replace / upgrade planner
- Save migration
- Mod updates

Until these rules are explicitly specified, implementation should not invent user-visible behavior that risks silently losing reverse-profile configuration.

---

## 25. Configuration persistence

Two-Way Inserter must store logical two-way configuration independently from the physical inserter's currently applied runtime state.

The stored configuration is the source of truth for:

- Which direction is primary
- Forward profile
- Reverse profile
- Direction-specific pickup/drop positions
- Current mode/state as needed

A temporary reverse state must never overwrite the definition of the primary direction.

---

## 26. Non-goals for the initial design

The following are not required for the initial implementation:

- Adding a completely new family of dedicated inserter prototypes
- Reimplementing assembling machine recipes or inventory rules
- Detecting "ingredient" versus "product" semantically
- Modifying Smart Inserters source code
- Depending on Smart Inserters internal/private implementation
- Replacing the vanilla inserter GUI
- Injecting custom tabs directly into the vanilla inserter GUI
- Guaranteeing complete direction-specific parity for every circuit-control feature in the first version

---

## 27. Desired advanced capability

The selected-profile editor model is intended to make fully independent arm
positions practical without duplicating another mod's GUI:

```text
Forward:
A outer lane -> B inner lane

Reverse:
B outer lane -> A inner lane
```

This allows one inserter to cross-transfer between selected lanes in both
directions by editing the Forward and Reverse profiles separately.

---

## 28. Initial implementation priorities

Recommended implementation order:

1. Add two-way mode to existing inserter entities.
2. Preserve the placed direction as the permanent primary direction.
3. Implement safe forward/reverse pickup/drop switching.
4. Implement reverse probing after successful forward transfer.
5. Implement periodic reverse probing while forward is idle.
6. Add persistent forward/reverse logical profiles.
7. Add independent forward/reverse filter settings through selected-profile editing.
8. Add independent forward/reverse stack size override through selected-profile editing.
9. Add the minimal Two-Way GUI for mode enable/disable and selected-profile editing.
10. Make GUI-open behavior normalize/suspend correctly.
11. Add Smart Inserters selected-profile compatibility through public interfaces only.
12. Evaluate red-wire-forward / green-wire-reverse circuit behavior.
13. Add blueprint/copy/upgrade persistence.
14. Tune probe timing and UPS behavior.

---

## 29. Open questions

The following items are intentionally unresolved and require implementation testing or further design discussion:

1. What is the ideal reverse-probe interval?
   - 10 ticks is an initial discussion value only.

2. What exact Factorio inserter state/event should be used to identify the safest direction-switch boundary?

3. Which normal inserter properties beyond filters and stack size should be direction-specific in the first release?
   - Spoilage priority is a candidate.
   - Full circuit-control parity is not yet confirmed.

4. Can the vanilla inserter control behavior cleanly use:
   - red network only in forward mode, and
   - green network only in reverse mode?
   If not, which circuit behaviors should Two-Way Inserter reproduce itself?

5. What is the best relative-GUI placement when Smart Inserters or other inserter GUI mods are installed?

6. How should reverse profile data be encoded into blueprints and entity settings copy/paste?

7. Which modded inserters, if any, require explicit compatibility exclusions?

---

## 30. Core design rule

The central design rule of Two-Way Inserter is:

> The inserter's placed direction remains primary.
> The return trip is an opportunity to perform useful transport instead of returning empty.

Everything else should preserve that behavior and keep the feature understandable as an extension of normal Factorio inserters rather than as a separate logistics system.
