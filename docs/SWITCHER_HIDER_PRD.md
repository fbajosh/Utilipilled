# PRD | Utilipilled — Switcher Hider

## 1. Overview

Switcher Hider is a new Utilipilled pill that allows users to selectively exclude applications from the macOS application switcher (⌘ Tab) without affecting the applications themselves.

The pill recreates the native macOS application switcher in its entirety, with application exclusion as its only intentional functional deviation. It should be visually and behaviorally indistinguishable from the native switcher under normal use, with equivalent or better performance.

Unlike utilities that modify application activation policies, Switcher Hider operates independently of the applications it excludes, supporting both third-party and native Apple applications.

## 2. Product objectives

- Selectively exclude applications from the application switcher
- Achieve visual, behavioral, and performance parity with the native macOS application switcher
- Support native Apple applications, including Messages
- Preserve normal application functionality, appearance, and accessibility
- Minimize incremental resource consumption by Utilipilled
- Ensure the native application switcher is restored whenever the pill is unavailable

### 2.1. Design philosophy

Switcher Hider is not intended to improve, modernize, or redesign the macOS application switcher. It is intended to reproduce it.

A user unfamiliar with Utilipilled should not be able to distinguish between the native and replacement switchers without knowing which applications have been excluded.

### 2.2. Non-objectives

- Window-level switching
- Window previews or thumbnails
- Alternative keyboard shortcuts
- Application search
- Customizable themes, dimensions, or animations
- Application bundle modification or code injection
- Dock management
- Window management

## 3. User interface

### 3.1. Utilipilled menu

Switcher Hider appears as an independent section in the existing Utilipilled menu, consistent with the other pills.

```
Switcher Hider
    Disable
    Apps                         ›
──────────────────────────────────
```

The section contains two menu items:

| Item | Function |
|---|---|
| Enable / Disable | Toggles the pill |
| Apps | Opens the application exclusion submenu |

Switcher Hider is disabled by default.

### 3.2. Application submenu

The Apps submenu is divided into two sections, separated by a horizontal line.

```
    Calendar
    Finder
    Google Chrome
    Mail
  ✓ Messages
    Notes
    Safari
  ✓ Spotify
    Visual Studio Code
──────────────────────────────────
  ✓ Discord
  ✓ Slack
```

The first section contains all running, user-facing applications, including those currently excluded from the switcher.

The second section contains all previously excluded applications that are not currently running.

- Each section is independently sorted alphabetically
- A checkmark indicates that an application is excluded from the switcher
- Selecting an application toggles its exclusion
- Applications move between sections automatically as they launch or terminate
- Unchecking a non-running application removes it from the submenu
- The separator is omitted if the second section is empty
- Application icons should be displayed if consistent with Utilipilled's existing menu conventions

Background processes, system daemons, and application helper processes are not listed.

### 3.3. Pill state

Disabling Switcher Hider restores the native macOS application switcher but retains the application exclusion list.

Re-enabling Switcher Hider immediately reapplies all saved exclusions.

Exclusion preferences may be modified while the pill is disabled. Checkmarks represent saved exclusion preferences rather than the current operational state of the pill.

## 4. Functional requirements

### 4.1. Application exclusion

| ID | Requirement |
|---|---|
| SH-01 | Excluded applications shall not appear in the replacement switcher |
| SH-02 | Exclusions shall take effect without restarting the selected application |
| SH-03 | Exclusions shall persist across application launches, Utilipilled launches, and system restarts |
| SH-04 | Exclusions shall be associated with application bundle identifiers rather than process identifiers |
| SH-05 | Exclusions shall support both Apple and third-party applications |
| SH-06 | Excluded applications shall remain accessible through the Dock, Finder, Spotlight, and other normal application entry points |
| SH-07 | Excluded applications shall retain their normal menu bars, windows, notifications, and activation behavior |
| SH-08 | No application files, signatures, entitlements, or configuration shall be modified |

### 4.2. Application ordering

The switcher shall replicate the native most-recently-used (MRU) application ordering.

Application activation history shall be maintained independently of switcher invocations and reflect applications activated through any mechanism, including the Dock, Spotlight, mouse interactions, and other keyboard shortcuts.

Excluded applications shall remain part of the underlying activation history but be filtered from the displayed application list.

Removing an exclusion shall return the application to its appropriate position in the MRU sequence.

If an excluded application is in the foreground when the switcher is invoked, the initial selection shall be the most recently used non-excluded application.

### 4.3. Keyboard and mouse interactions

All native application switcher interactions shall be reproduced.

| Input | Behavior |
|---|---|
| ⌘ Tab | Invoke switcher and cycle forward |
| ⌘ Shift Tab | Cycle backward |
| ⌘ \` | Cycle backward while the switcher is active |
| Left / Right arrow | Navigate applications |
| Up / Down arrow | Invoke application window overview where supported by native behavior |
| Release ⌘ | Activate selected application |
| Escape | Dismiss without switching |
| Return | Activate selected application |
| Q | Quit selected application |
| H | Hide selected application |
| Option + release ⌘ | Replicate native minimized-window restoration behavior |
| Mouse movement | Replicate native hover and selection behavior |
| Mouse click | Activate selected application |

The implementation shall also reproduce native behavior for key repetition, modifier combinations, selection wrapping, drag-and-drop interactions, and application termination while the switcher is visible.

Rapid press-and-release of ⌘ Tab shall switch applications without introducing additional delay or requiring completion of the switcher's presentation animation.

### 4.4. Application activation

Application activation shall reproduce native behavior across:

- Applications with multiple windows
- Applications with no open windows
- Hidden applications
- Minimized windows
- Full-screen applications
- Multiple displays
- Multiple Spaces
- Stage Manager
- Applications that are launching, terminating, or unresponsive

The switcher shall respect relevant macOS system preferences, including whether switching applications changes the active Space.

The pill shall not introduce independent window management behavior.

### 4.5. Edge cases

- If only one eligible application is running, replicate the equivalent native behavior
- If no eligible applications are running, dismiss the switcher without activating another application
- Applications that terminate during a switching session shall be removed safely
- Applications that fail to activate shall not leave the switcher visible or prevent subsequent switching
- Multiple instances of an application shall be handled consistently with the native switcher

## 5. Visual requirements

The native macOS application switcher shall serve as the visual reference implementation.

### 5.1. Visual properties

The following shall match the native switcher:

| Component | Properties |
|---|---|
| Container | Position, dimensions, padding, corner radius, border, shadow |
| Background | Transparency, translucency, blur, material, tint |
| Application icons | Size, resolution, spacing, alignment |
| Selection indicator | Dimensions, radius, color, opacity |
| Application labels | Typeface, size, weight, alignment, positioning |
| Animations | Duration, easing, sequencing, opacity |
| Layout | Scaling and adaptation to application count and available screen width |
| Presentation | Window level, display selection, behavior across Spaces |

Native application icons shall be used directly. Icons shall not be independently recreated or stylized.

### 5.2. System appearance

The switcher shall adapt to system settings and environmental changes, including:

- Light and dark appearance
- Retina and non-Retina display scaling
- Reduce Motion
- Reduce Transparency
- Increased Contrast
- Display resolution and arrangement
- OS-specific visual materials and design conventions

There shall be no independent appearance settings.

### 5.3. Visual validation

Capture reference screenshots and recordings of the native switcher under controlled conditions and compare them against the implementation.

Validation shall include multiple application counts, desktop backgrounds, appearance modes, display configurations, and animation states.

Static layout geometry should match the reference within one logical point wherever technically achievable.

Any remaining visual differences shall be documented before release.

## 6. Performance requirements

The native switcher shall be treated as the performance baseline rather than relying exclusively on arbitrary latency thresholds.

### 6.1. Performance targets

| Metric | Target |
|---|---|
| Input-to-first-frame latency | Within one display refresh interval of native at p95 |
| Selection update latency | Within one display refresh interval at p95 |
| Application activation latency | Within one display refresh interval of native at p95 |
| Rendering frame rate | Match active display refresh rate |
| Idle CPU utilization | <0.1% average incremental CPU |
| Idle memory footprint | ≤25 MB incremental resident memory |
| Network activity | None |
| Dropped keyboard events | Zero during validation |

At 60 Hz, one refresh interval is approximately 16.67 ms. At 120 Hz, it is approximately 8.33 ms.

These are initial engineering targets and shall be validated against actual measurements.

### 6.2. Performance architecture

The implementation shall avoid performing expensive operations in response to switcher invocation.

- Maintain an in-memory registry of running applications
- Maintain MRU ordering continuously
- Cache application icons and display names
- Preinitialize the switcher presentation layer
- Use event-driven application lifecycle monitoring rather than continuous polling
- Keep keyboard event callbacks lightweight and nonblocking
- Perform expensive operations outside the latency-critical input path
- Avoid window screenshots and unnecessary Accessibility queries

### 6.3. Benchmarking

Benchmark the native and replacement switchers on the same hardware under equivalent conditions.

Capture p50, p95, and p99 latency for:

- Initial invocation
- Selection changes
- Rapid application switching
- Application activation
- Switcher dismissal

Test both warm invocation and first invocation following launch, system wake, and extended inactivity.

Resource utilization shall be measured incrementally against Utilipilled with Switcher Hider disabled.

## 7. Technical architecture

### 7.1. Implementation

The pill shall be written in native Swift and AppKit, consistent with Utilipilled's existing architecture.

Suggested directory structure:

```
Pills/
└── SwitcherHider/
    ├── SwitcherHider.swift
    ├── ApplicationRegistry.swift
    ├── ApplicationHistory.swift
    ├── ExclusionStore.swift
    ├── KeyboardInterceptor.swift
    ├── SwitcherController.swift
    ├── SwitcherPanel.swift
    └── ApplicationActivator.swift
```

| Component | Responsibility |
|---|---|
| SwitcherHider | Pill lifecycle and coordination |
| ApplicationRegistry | Running application discovery and lifecycle monitoring |
| ApplicationHistory | MRU ordering |
| ExclusionStore | Persistent application exclusions |
| KeyboardInterceptor | Global keyboard event interception |
| SwitcherController | Switching session and selection state |
| SwitcherPanel | Native-style rendering and presentation |
| ApplicationActivator | Application activation and native switching behavior |

Use AppKit, Core Graphics, Core Animation, and native macOS APIs wherever possible.

### 7.2. Input interception

Evaluate Core Graphics event taps as the primary mechanism for intercepting ⌘ Tab and associated input events.

Preference shall be given to interception mechanisms that do not persistently disable the native shortcut.

Where private APIs are necessary to suppress the native switcher or reproduce its behavior, their use shall be isolated behind dedicated interfaces with runtime availability checks.

The replacement and native switchers shall never be presented simultaneously during normal operation.

Unrelated keyboard events shall pass through without modification.

### 7.3. Persistence

Store pill preferences using Utilipilled's existing UserDefaults approach.

Proposed preference keys:

```
switcherHider.enabled
switcherHider.excludedApps
```

Each excluded application record should contain:

- Bundle identifier
- Display name
- Last known application URL

Application history should remain in memory. Persistent records of application usage are not required.

### 7.4. Compatibility

Initial visual and performance validation shall prioritize macOS 26 on Apple silicon.

Utilipilled's existing minimum supported macOS version shall not be raised solely to accommodate Switcher Hider.

Earlier macOS versions may receive version-specific implementations once validated. Unsupported configurations shall retain the native switcher.

## 8. Permissions, security, and privacy

The pill may require Accessibility and/or Input Monitoring permissions depending on the chosen interception mechanism.

Permissions shall only be requested when necessary to enable Switcher Hider.

The pill shall not require:

- Disabling System Integrity Protection
- Disabling the Signed System Volume
- Full Disk Access
- Screen Recording
- Administrator privileges
- Modification of protected system files
- Application re-signing
- Code injection into other applications

Keyboard events unrelated to switcher functionality shall not be stored, logged, or transmitted.

All application exclusion preferences shall remain local to the device.

## 9. Reliability and fail-safe behavior

The native macOS application switcher is the mandatory fallback.

| Event | Expected behavior |
|---|---|
| Pill disabled | Native switcher restored |
| Utilipilled quits normally | Native switcher restored |
| Utilipilled crashes | Native switcher restored automatically |
| Utilipilled is force-quit | Native switcher restored automatically |
| Required permissions revoked | Native switcher restored |
| Keyboard interceptor fails | Native switcher restored |
| System API unavailable | Native switcher retained |
| Utilipilled uninstalled | Native switcher unaffected |
| System update introduces incompatibility | Pill fails safely to native switcher |

If interception requires changing native shortcut state, an independent recovery mechanism shall restore the original state following unexpected termination.

The user shall never lose access to application switching because of a Utilipilled failure.

## 10. Development and release plan

### Phase 0 — Technical feasibility

- Validate global ⌘ Tab interception
- Confirm reliable native switcher suppression and restoration
- Test activation of native Apple applications
- Test full-screen applications and Spaces
- Establish native switcher performance benchmarks

### Phase 1 — Functional reproduction

- Implement application discovery and MRU ordering
- Implement exclusion management
- Implement keyboard navigation and activation
- Integrate Switcher Hider into the Utilipilled menu
- Implement persistent preferences

### Phase 2 — Visual reproduction

- Capture native switcher reference imagery
- Reproduce layout, materials, typography, and iconography
- Reproduce presentation and dismissal animations
- Validate system appearance and display configurations

### Phase 3 — Performance and reliability

- Optimize invocation and activation latency
- Measure incremental CPU and memory utilization
- Validate native keyboard interactions
- Exercise crash recovery and permission revocation
- Resolve behavioral and visual discrepancies

### Phase 4 — Release

- Update README and development documentation
- Document permission requirements
- Include applicable third-party license notices
- Release through Utilipilled's existing distribution process

## 11. Acceptance criteria

Switcher Hider is ready for release when:

- Spotify and Apple Messages can be excluded without restarting or modifying either application
- Excluded applications retain their normal functionality
- The replacement is visually indistinguishable from the native switcher during normal use on validated configurations
- Native application switching interactions are reproduced
- Defined performance targets are satisfied
- The exclusion list persists across system restarts
- The pill can be enabled and disabled without restarting Utilipilled
- The native switcher is restored reliably across all tested failure scenarios
- Existing Utilipilled pills are unaffected

Application exclusion shall remain the sole intentional deviation from native switcher behavior.
