# Switcher Hider development preview

The source PRD is in [SWITCHER_HIDER_PRD.md](SWITCHER_HIDER_PRD.md). SwitcherMogged ships as an **opt-in preview**; full native behavioral, display-matrix and performance parity remain unverified. The user accepted the visual comparison for this release. Default: disabled. Preview platform: macOS 26, Apple silicon. Other macOS versions and Intel keep the native switcher; the package minimum stays macOS 13. Unknown future major OS versions fail closed to the native switcher.

## Implemented

- Enable/Disable and Hide apps submenu in the existing menu. No appearance preferences.
- Regular user-facing applications only. Running applications and saved non-running exclusions are independently alphabetized. Duplicate running instances share one preference; sessions retain process identities.
- Bundle-identifier exclusions containing display name and last known URL, saved through UserDefaults. Editing exclusions while disabled works; disabling keeps them.
- Workspace lifecycle/activation notifications and activation-policy observation. Startup order is seeded from LaunchServices through a runtime-resolved interface; subsequent activation notifications maintain in-memory MRU, retaining excluded apps. Native icons are cached; no polling of the running application list.
- Session snapshots, forward/backward wrapping, grave/arrow navigation, Escape/Period cancellation, Return, Command release, normal quit/hide requests, hover selection and clicking. Up/Down activates the selected app and requests native App Exposé after confirming the target is frontmost. Option-release sends a native reopen event through LaunchServices.
- Delayed panel presentation with immediate activation on quick Command-Tab release. Panel layout/material is an approximation awaiting native comparison. Space/display handling uses a nonactivating AppKit panel; application activation uses NSRunningApplication.
- Unrelated key events pass through. Consumed key-up events are paired with their key-down, including after dismissal. Control-modified system commands and Option-Command-Escape cancel the session and pass through unchanged. Unrelated input is never stored or logged.
- Native AppKit URL/file dragging destinations and system-managed spring loading. Drop operations use NSWorkspace to open the URLs in the selected running app; spring loading activates the app while preserving the source drag. Arbitrary non-URL pasteboard payloads are not supported yet.
- Accessible app tiles provide names, selection and press actions. Character commands use the current keyboard layout; navigation uses physical keycodes.
- Active session removal of terminated/excluded apps. Empty results consume the invocation without displaying excluded apps. Activation failure leaves the panel dismissed.
- Tap teardown on disable, quit, sleep/session inactivity and reported tap failure. Wake/session resume checks availability without permission prompts. Tap failures disable the saved enabled preference and require explicit retry. The menu also checks tap availability.
- Accessibility permission is requested only on an explicit Enable action when needed. Launch and wake do not request permissions. No persistent hotkey/Dock/system changes, injected code, network calls, application modifications, or helper recovery process.

## Release blockers and known differences

| Area | Current status / required validation |
| --- | --- |
| Native suppression | **Live feasibility confirmed on the target Mac:** the user physically invoked Command-Tab and reported only the replacement appeared. The lab recorded 8 invocations, 6 presentations and 8 commits. Stress/OS-matrix validation remains. Desktop-control-generated shortcuts do not reach the global tap and cannot replace physical input for this test. |
| Pre-launch MRU | Implemented using runtime-resolved `_LSCopyApplicationArrayInFrontToBackOrder`, ASN type/extraction and legacy PID conversion. A read-only live probe returned the current user apps in system order; integration checks passed. Hidden-app and multi-instance order must still be compared to native. The operational pill requires a successful seed; unavailable interfaces retain native switching. |
| Window overview | Implemented through runtime-resolved CoreDock notification, after observing activation of the selected process. Pending requests cancel on a newer session/disable and time out after 750 ms. Actual overview behavior across Spaces and macOS settings needs live verification. |
| Option-release | Implemented with the selected application’s normal `kAEReopenApplication` event via NSWorkspace. Restoration is delegated to the app. Compare this against native minimized-window selection semantics before release; no arbitrary Accessibility window manipulation is used. |
| Drag and drop | File/URL drops and NSSpringLoadingDestination are implemented; spring-loading timing follows system preferences. Live drag validation is pending. Non-URL payloads and file promises remain unsupported and must be resolved before full parity. |
| Native activation | Messages/Spotify exclusion and activation, no-window apps, hidden/minimized/full-screen apps, Spaces preferences, multiple displays, Stage Manager and unresponsive apps require live verification. No independent window-management logic is used. |
| Appearance | Initial AppKit approximation only. Icon geometry, labels, selection, material, display choice, scaling and animation timing require native references and point-by-point comparison. The supplied eight-app Retina screenshot now provides a measured geometry baseline; material comparison and animation recordings remain pending. |
| Accessibility | Reduce Transparency/Increased Contrast are consulted; no motion animation is introduced. The panel exposes accessible app buttons and selected children; integration checks verify their presence. Q/H/grave use the active keyboard layout. System appearance and accessibility display-option changes request a redraw; Increased Contrast also outlines the selected tile. Full VoiceOver navigation, display scaling and appearance/layout changes need live validation. |
| Rapid sessions | Input routing tests include consumed key pairing, repeats after Command release, cancellation of queued activation and excluded-foreground selection in both directions. Physical repeats, modifier combinations and rapid consecutive-session stress tests remain. |
| Recovery | Disable and a live SIGKILL test both removed the owned interceptor; relaunch resumed the saved enabled state with permission intact. No persistent shortcut change is made. Hung main thread, live permission revocation, secure input, sleep/wake and fast-user switching still need validation. Permission loss is detected on invocation, menu access or a tap-disabled notification, not by an idle polling loop. |
| Performance | A small physical-input trace and one five-minute enabled/disabled lab resource pair have been collected (results below). Native latency, refresh-rate/frame cadence and the production incremental resource comparison remain unverified. Presentation delay is provisional (120 ms), not a measured native value. Release performance acceptance remains pending. |

## Automated checks

`./test.sh` includes `Support/check_switcher_hider.swift`, exercising MRU retention, filtered foreground selection, wrapping, termination/empty sessions, persistent exclusions, corrupt/duplicate preferences, input pass-through, consumed key pairing, repeats, quick commit/cancellation, Option state and tap failure handling. These checks do **not** install an event tap, prompt for permissions, generate user input, or activate other applications. They cannot establish native switcher suppression or crash recovery.

`Support/check_switcher_integration.sh` uses the real desktop registry and disposable preferences to check native startup order, user-app eligibility, menu sorting/sections/toggling, disabled persistence, accessibility children and cancellation of queued activation. It also injects permission denial/revocation, missing native interfaces, tap-creation failure, timeout/failure callbacks, suspension and saved-enabled relaunch. These checks use a fake interceptor and never enable a global tap, prompt, show windows or switch apps. It needs access to LaunchServices and the window server.

`python3 Support/test_switcher_measurements.py` validates timestamp pairing across overlapping sessions, percentile calculation, malformed input rejection and CPU-time parsing.

`swift build` compiles all integration components. A successful build is not visual or behavioral acceptance.

## Local verification record

On 2026-11-17, the pill compiled on arm64 macOS 26.6.2 with Swift 6.4.2. The complete local check runner passed: 29 Camera Quiet checks plus Keep Awake, Percentage Hider, Claude target and Switcher Hider checks. The release app bundle was built and its code signature verified by `build.sh`. Restricted execution initially prevented the existing boot-session check and release debug-symbol generation; both succeeded with the necessary local access.

An offscreen AppKit render with four running application icons was inspected for icon/label layout at 544 × 176 logical points. This was a layout check, not a native-reference comparison or a live translucency/frame-timing test. That first layout check did not install a keyboard interceptor. A later isolated lab run did install the live tap with the user’s Accessibility grant: the user confirmed only the replacement appeared and reported no noticeable activation issues. The first lab’s NSRunningApplication return-value counter reported 5 refusals out of 8 commits, so the updated diagnostics separately observe actual frontmost activation; this discrepancy is not classified as 5 proven switching failures. The lab was explicitly disabled afterward, returning switching to macOS. A read-only CGGetEventTapList probe of the later disabled lab process returned zero owned taps, confirming teardown at the system level. The read-only integration checks and updated input/geometry checks also passed. Further live checks on the rebuilt lab were interrupted by the locked desktop and the need to renew its ad-hoc-signature permission.

## Live validation procedure

Use an isolated preview bundle/preference domain so installed production settings are preserved. Do not run competing camera/audio-controlling instances. Record machine model, OS build, display resolution/scaling/refresh rate, appearance/accessibility preferences and Space/Stage Manager configuration with every result.

1. With the pill disabled, capture native switcher screenshots/recordings for 1, 2, 5, 10 and overflow application counts. Include light/dark backgrounds, Retina and available non-Retina displays, Reduce Transparency, Increased Contrast and Reduce Motion.
2. Enable the pill; grant Accessibility in System Settings if required and explicitly choose Enable again. If the tap cannot be created, confirm the native shortcut still works.
3. Launch Messages and Spotify. Toggle exclusions while they run; verify Dock, Spotlight, notifications, menu bars and application windows still work. Disable, restart Utilipilled and restart macOS; verify exclusion persistence. Edit stopped-app exclusions while disabled.
4. Compare every input and activation case in PRD sections 4.3–4.5 against native. Include both Command keys, repeats, rapid release, app exits, unresponsive apps, zero eligible apps and duplicate instances.
5. Record enabled/disabled native behavior after normal quit, force-quit, crash, main-thread stall, permission revocation, sleep/wake, secure-input sessions and unsupported OS configurations. Do not declare fallback validated based solely on the tap architecture.
6. Record at least 200 samples per latency scenario (warm, cold, after wake, after idle) for native and preview under the same conditions. Use high-speed recordings or instrumented event/frame/activation timestamps, and retain raw samples. Report p50/p95/p99. Compare p95 differences to one refresh interval, not to absolute thresholds. Measure incremental idle CPU/RSS over at least five minutes with the pill disabled/enabled; target <0.1% CPU and ≤25 MB RSS. Check dropped input and display frame cadence separately.
7. List remaining geometry/material/behavior differences with references and measurements. Release only when all PRD acceptance criteria are met or explicitly revised.

## API references

- [CGEvent.tapCreate](https://developer.apple.com/documentation/coregraphics/cgevent/tapcreate(tap:place:options:eventsofinterest:callback:userinfo:)) and the installed CoreGraphics `CGEvent.h` describe active event filtering, permission constraints and run-loop callbacks.
- [CGEvent.tapEnable](https://developer.apple.com/documentation/coregraphics/cgevent/tapenable(tap:enable:)) documents tap-disabled notifications. The preview tears down on failure rather than automatically re-enabling a failed tap.
- [NSRunningApplication](https://developer.apple.com/documentation/appkit/nsrunningapplication) provides normal application activation, hide and termination requests. These requests do not prove parity with Dock's native switching behavior.


## Isolated lab and measurements

Build with `Support/build_switcher_lab.sh`, then open `.build/SwitcherHiderLab.app`. This uses only the switcher pill and the separate `local.Utilipilled.SwitcherLab` preference domain. It never starts Camera Quiet, Keep Awake or Percentage Hider. With ad-hoc signing, rebuilding changes the code signature and macOS may require removing/re-adding the lab in Accessibility. Production distribution needs a stable signing identity to avoid repeated permission grants.

Use **Excluded Apps** to edit preferences. **Save measurements** writes `.build/switcher-measurements.json` beside the lab app. Only semantic switcher event types, session IDs and monotonic timestamps are recorded—no application identifiers or unrelated keyboard input. Saving is an explicit lab action. The regular Utilipilled app has no diagnostics observer, recorder or automatic export.

```
python3 Support/analyze_switcher_measurements.py .build/switcher-measurements.json
python3 Support/measure_switcher_idle.py --pid LAB_PID --label disabled --duration 300 --output .build/switcher-idle-disabled.json
python3 Support/measure_switcher_idle.py --pid LAB_PID --label enabled --duration 300 --output .build/switcher-idle-enabled.json
python3 Support/compare_switcher_resources.py --disabled .build/switcher-idle-disabled.json --enabled .build/switcher-idle-enabled.json
```

Use the same lab build and idle desktop conditions for both resource samples. Subtract disabled from enabled CPU/RSS; these are lab measurements, not a replacement for the production-app comparison required by the PRD. CPU time comes from `ps` at 0.01-second resolution; RSS is resident memory, not physical footprint. Keep system lock state and other test activity equivalent. A process exiting mid-run fails the sample rather than inventing missing data.

To inspect ownership and callback timing without observing key contents:

```
swiftc Support/probe_switcher_taps.swift -framework CoreGraphics -o .build/SwitcherTapProbe
.build/SwitcherTapProbe LAB_PID
```

The probe reports only taps owned by the specified PID. Use it before/after disable, normal quit and forced termination to verify removal. Callback microseconds from CGEventTapInformation are not input-to-screen or native-switcher latency.

Native interfaces are independently wrapped and runtime-checked in `NativeSwitcherServices.swift`. The ordering interface’s ABI was researched using [MTMR declarations](https://github.com/Toxblh/MTMR/blob/be6ae30411f6f62baf4708fd548b824322a556a4/MTMR/CBridge/DeprecatedCarbonAPI.h), [OpenBoard’s dynamic binding](https://github.com/OpenBoard-org/OpenBoard/blob/888c3287a66ef0a2423ba13ec730ac041f858620/src/frameworks/MacUtils.h), and current SDK exports. The Dock notification name was cross-checked against [Instantools’ native interface](https://github.com/infeace/Instantools/blob/0eb69b63df8af7b2cd9b3d650191b9e7e1a1ad3e/Sources/SkyLightShim/Dock.swift). No implementation code or assets from those projects are included.


### Live activation follow-up

After removing the stale Accessibility entry, re-adding the exact current `.build/SwitcherHiderLab.app` bundle and enabling it, the user performed physical Command-Tab switching again. The lab recorded **13 invocations, 13 commits, 13 confirmed frontmost activations, zero API refusals and zero unconfirmed activations**. There were 11 presentations (two quick switches committed before showing the panel), 22 selection events and 22 draw events. The user reported normal-feeling switching and a visibly different replacement appearance.

The explicit lab export is retained locally in `.build/switcher-measurements.json`. Nearest-rank statistics from this small sample were: selection-to-AppKit-draw p95 **2.4 ms** and commit-to-workspace-confirmed-focus p95 **23.3 ms**. These are internal processing/notification measurements, not physical input-to-display latency, and are not compared to a native baseline. They do not establish the PRD performance targets or visual parity.

A CoreGraphics metadata probe also confirmed one enabled session tap owned by the lab process. Its reported callback-latency fields were all approximately 30.95 ms at the sampled instant; this API snapshot is not a p95 distribution and must not be treated as a passed callback-latency benchmark. Native-reference and high-speed end-to-end measurements remain required.


Apple also documents Period as a native cancellation input; it is now handled alongside Escape and covered by the routing checks. See [Apple’s window-switching instructions](https://support.apple.com/guide/mac-help/mchlp2469/mac). Registry discovery relies on activation policy rather than explicitly omitting its host process, so a regular development host can participate just as it does in the native switcher; Utilipilled itself remains an accessory app and is naturally absent.


### Five-minute idle pair and recovery checks

The same lab process/build was measured for 300 seconds enabled and 300 seconds disabled. Results are retained locally as `.build/switcher-idle-enabled.json` and `.build/switcher-idle-disabled.json`; `.build/switcher-live-manifest.json` records the executable SHA-256 so these results cannot be mistaken for a later binary.

| Metric | Enabled | Disabled | Signed difference |
| --- | ---: | ---: | ---: |
| Average CPU | 0.00333% | 0.00667% | -0.00333 percentage points |
| Mean resident memory | 81.21 MB | 74.05 MB | +7.16 MB (6.83 MiB) |

This single sequential pair showed no measurable CPU increase at the 0.01-second CPU-time resolution, and its observed memory difference was below the initial 25 MB target. Cache warming/paging and order effects are not controlled. These are preliminary isolated-lab results, not production acceptance or native latency measurements. Use `Support/compare_switcher_resources.py` for the matched-pair calculation; its tests reject different processes, swapped labels and short sample durations.

A live force-stop test recorded one enabled tap immediately before SIGKILL of the verified lab process and zero taps owned by that PID afterward. Both metadata snapshots are saved in `.build/switcher-taps-before-crash.json` and `.build/switcher-taps-after-crash.json`. Relaunching the unchanged lab resumed its saved enabled state and saw its Accessibility grant. The lab was then explicitly disabled and normally closed, leaving native switching available.

The desktop tooling did not expose usable Dock switcher or system screenshot-tool controls. No native reference screenshot was obtained through those attempts. The user subsequently supplied the matched grid screenshots described below. First-frame/animation latency still needs a native recording baseline.


### Matched grid reference and visual calibration

The user supplied an original 1410 × 600 grid and two 2880 × 1864 Retina screenshots with and without the native switcher. Unmodified copies and original-pixel diagnostic crops remain in ignored `.build/switcher-reference`; desktop screenshots are not committed. The grid is pixel-identical outside the panel in the sampled upper/lower bands, allowing an aligned comparison without resampling.

The eight-app reference gives a candidate logical panel of **1112 × 176 pt**, centered on a 1440 × 932 pt display. Measured candidates are 134 pt icon pitch, 128 pt icon image frames, a 120 pt selection frame and a 13 pt bold label. The initial 64 pt outer-radius estimate was superseded by the Figma comparison below. Native icon image transparency affects visible bounds. These values now drive the layout, including proportional shrinking on smaller screens; they are not yet a claim of one-point parity across application counts.

`Support/analyze_switcher_reference.py` fits Gaussian blur plus an affine RGB transform to narrow interior strips between icons, withholding two strips from fitting. The encoded-RGB fit estimates sigma **10.16 screenshot pixels (5.08 pt)** with held-out RMSE **3.15/255**. This is a diagnostic approximation: the repeating pattern cannot uniquely identify the native kernel, and the fit excludes edge refraction, icons, selection and text. It must not be treated as a recovered native shader. The synthetic recovery test in `Support/test_switcher_reference.py` independently checks the fitter against a known blur and color transform.

The rendering now uses guarded macOS 26 glass recipes for the Dock container and focus-border selection. Both getter/setter integer signatures are checked before use, and configuration is read back. Runtime availability and recipe assignment pass the read-only integration checks; rendered parity remains unverified. Recipe mappings were researched from [UIFoundation's NSGlassEffectView investigation](https://github.com/Mx-Iris/UIFoundation/blob/86fd6ed35d7f2b7bdd031a1aaaea4617e4c62f73/Researchs/AppKit-NSGlassEffectView-PrivateConfiguration.md); no implementation or assets were copied. Private recipe numbers can drift even within a supported OS family.

`Support/build_switcher_visual_reference.sh` builds a separate static comparison app with no keyboard interception or Accessibility request. Compare menu shortcuts: Command-1 native screenshot, Command-2 public clear glass, Command-3 public regular glass, Command-4 background, Command-5 Dock recipe. Its background occupies a separate window to exercise behind-window sampling. Window-only tooling captures omit that background, so they cannot establish live material parity. The current Dock variant reads back as 3, adaptive appearance 1, and the panel frame is {{164, 378}, {1112, 176}}. The user confirmed that the colored grid is visible through the replacement on screen. This establishes live backdrop sampling, but does not establish matching diffusion, tint or edge refraction; a full-screen replacement capture under the same conditions is still needed for quantitative comparison. The fixture's ChatGPT/Codex icon differs from the user's dynamic Dock icon because the standard application-icon API returns the bundle icon; dynamic icon parity remains unresolved.

Analysis uses an isolated local environment containing NumPy, SciPy and Pillow:

```sh
.build/switcher-analysis/bin/python Support/analyze_switcher_reference.py --background .build/switcher-reference/background.png --native .build/switcher-reference/native.png --without .build/switcher-reference/without.png --output .build/switcher-reference/measurements.json
.build/switcher-analysis/bin/python Support/test_switcher_reference.py
```


The user confirmed that the background grid is visible through the live preview, then supplied a full-screen replacement screenshot. In the aligned gap x1436–1449/y850–1010, native mean RGB was (105.2,112.0,83.5), replacement (104.7,112.1,82.7); spatial standard deviations were also close. This is one sampled region, not a whole-panel acceptance result. In the ring's top strip x720–825/y815–827, native mean RGB was (192.0,189.8,199.8), replacement (60.3,54.9,61.2). Native spatial standard deviations were (33.3,24.2,43.5), replacement (4.3,2.3,3.8), confirming substantially darker output and lost background modulation.

The static fixture now provides light-appearance clear/regular/Dock selection candidates via Command-6/7/8; Command-5 restores the original focus-border recipe. Only the fixture changes ring recipes for this experiment. The pill's material recipe remains unchanged until a matched candidate is established; subsequent experimental layering changes are described below. The updated comparison app compiles/signs successfully and Command-8 was opened for local inspection.


### Independent selection backdrop experiment

The user identified likely stacked glass: the selection should see the original background rather than the already-treated bar. A diagnostic fit of two thin native ring strips against the unobscured screenshot estimated Gaussian sigma 7.32 screenshot pixels (3.66 pt), smaller than the bar's approximate 10.16 pixels. This is consistent with independent sampling, but does not prove the native hierarchy or shader. Ring and bar colors also use different transforms.

The pill now places the icon/selection strip beside the container material in a common transparent root rather than inside its glass contentView. An even-odd layer mask cuts the selected rounded rectangle out of the container, preventing drawn overlap. The integration check verifies sibling placement and that the selected center is excluded while an unselected background point remains included. The selection's material recipe and radius are not declared matched; the user also noted a small corner-radius difference.

The fixture now uses an opaque image window plus an attached transparent glass child, recreating the material views for each mode. This prevents independent background-window ordering and avoids repeatedly changing a live glass recipe. It ran 25 mode changes with one visible child and a non-nil image before the latest ring-layer changes. Its builder now stages and signs a complete app before replacing the previous bundle, preserving the old executable inode. No crash report establishing the cause of the reported black view was found. Long-run visual stability and the revised material remain under review. Command-9 additionally previews the app-icon glass recipe. Desktop captures of child-window compositing differ from the original independent-window capture; user screenshots remain the quantitative reference.


The user reported that the independent ring remained too opaque/dark and that a narrow gap was visible between ring and bar. The cutout is now inset by one physical pixel, leaving bar coverage under the shared antialiased edge. The static fixture holds the light Dock recipe/color constant and varies only ring alpha: Command-6 = 25%, Command-7 = 65%, Command-8 = 45%, Command-9 = 100% (previous). These shortcuts supersede the earlier recipe comparisons. Command-1 remains native. Alpha below 1 may expose more high-frequency grid detail than native; a matched screenshot is needed before adopting an opacity value in the pill. The pill's default alpha/recipe are unchanged. The preview was reopened at 45% and its recipe/alpha are recorded in render-state.json; visual acceptance and seam confirmation remain pending.


The user reported that the bar's blur/transparency regressed after the ring experiments. The custom container layer mask and explicit layer-backing request have been removed, and integration checks now guard against reintroducing a mask on the native glass. Removing the mask alone did not restore the captured appearance. The fixture also restores independent image/glass windows because the attached-window configuration changed the backdrop context; the transparent glass window is held one window level above the image and ordered out when the app deactivates. This restores the earlier window-sampling topology while keeping keyboard focus in the image window. The native bar recipe remains 3, adaptive appearance 1 and no tint. This is a baseline restoration, not a verified final match; the ring's direct-sampling/cutout experiment is unresolved. Earlier cutout and attached-window notes describe superseded experiments.


A further user report indicated the background still did not reflect the restoration. The current process path was verified as `.build/SwitcherVisualReference.app`, and SHA-256 checks confirmed that the copied grid and unobscured screenshot were identical to the user's original files; stale input copies were ruled out. The previous rollback had left the container inside a new sibling-view root. The original panel hierarchy is now fully restored: NSGlassEffectView is the window content view and the icon/selection strip is its contentView. The integration check guards this hierarchy and absence of a custom glass mask. Thus the independent-selection hierarchy experiment is rolled back, rather than considered solved. The comparison was rebuilt, reopened and its 45% ring mode selected through the actual Compare menu. Live full-screen material confirmation is pending.


The user clarified that the grid was not showing through the bar, rather than a changed source file failing to reload. The fixture's glass window is now a key-capable ReferenceWindow, explicitly made key on presentation and reactivation. The grid window is explicitly ordered front before each replacement presentation. Exported state now verifies background_window_visible=true, glass_window_can_be_key=true, glass_window_key=true and panel_visible=true, at the 45% ring mode. This establishes window wiring/state only, not visual material acceptance: the window-only desktop capture continues to omit the underlying grid. The corrected fixture was rebuilt, signed and reopened. Production nonactivating-panel appearance remains independently unverified.


### Confirmed background baseline and measured radius correction

The user confirmed that the bar background was restored correctly after correcting window activation/visibility and restoring the original glass content hierarchy. They reported that the nested selection darkened again. They also explicitly measured native/replacement outer radii as 56.5/64.5 in Figma. The configured outer radius is reduced from 64 to 56 logical points (an 8-point correction; the shared half-point visible-edge offset is retained). The analyzer's candidate-radius metadata follows the corrected configuration. A new rendered Figma comparison remains required.

The original pill hierarchy remains the default and Command-5 baseline. The fixture's light-ring modes use a separate opt-in hierarchy (`SwitcherPanel(independentSelection: true)`): the bar retains an explicit, empty glass contentView while the ring/icon strip is its sibling. No custom layer mask, tint, or blur is added to the bar. This avoids the earlier experiment's missing contentView while removing selection nesting. Read-only checks cover both hierarchies. The current 45% preview records selection_nested_in_container=false, container_content_present=true, container_corner_radius=56, visible grid and key glass window. These are structural checks, not proof of a matched backdrop or ring. Command-1/5/8 provide native, confirmed-hierarchy baseline and independent-ring candidate respectively. Opacity acceptance, ring radius and material parity remain pending.


The user reported the independent candidate was very close in texture, opacity and obfuscation, but explicitly reiterated that its color was still too dark. The fixture now changes the ring's actual NSGlassEffectView.tintColor to white at 0.65 tint alpha, holding view alpha at 0.45, independent hierarchy, backdrop recipe and 56-point container radius fixed. The default preview and Command-8 use this lightened tint. Command-6 is the same configuration with the prior untinted color; Command-7 uses stronger white tint (0.85). These supersede the earlier opacity controls. Ring tint alpha is exported so a color change can be distinguished from another opacity-only change. Rendered acceptance of the tint remains pending.


The user judged the initial 0.65 white tint roughly halfway toward the reference brightness. The current default/Command-8 applies full white tint (tint alpha 1.0), while preserving 0.45 view alpha, the same recipe, independent hierarchy, and 56-point outer radius. Command-6 retains the previous 0.65 tint and Command-7 the intermediate 0.85 tint. This is a color correction, not an increase to the ring view's opacity. Final rendered color acceptance is still pending.


The user found the ring still excessively diffused, describing a second blur applied to the already-diffused bar. The default/Command-8 static fixture now uses a plain white, continuous-corner highlight view over the bar rather than a second NSGlassEffectView. The bar supplies the only backdrop diffusion. White color and 0.45 view alpha are retained, with outer radius 56. Command-6 retains the previous double-glass renderer for comparison. The pill's default renderer is unchanged pending visual acceptance; the opt-in initializer supports this single-blur fixture. Integration checks reject NSGlassEffectView/NSVisualEffectView and layer/background filters on the highlight. Render state now exports selection_adds_blur=false. This addresses additive blur structurally; the final native edge/refraction match remains unverified.


### Accepted appearance and Show after feature

The user accepted the static visual result as close enough and asked to move on. The controller now uses that single-blur implementation: independent selection strip, white highlight at 0.45 alpha, native container recipe and 56-point outer radius. This supersedes earlier notes that the approved renderer was fixture-only; the broader display/appearance and production behavior matrix remains unverified.

Hide apps now has labeled Running, Not running, and Show after sections. Show after stores 1 cycle, 2 cycles or Never in `switcherHider.showAfter`; missing/invalid values use Never to preserve existing behavior. Exclusions and the reveal choice can be edited while disabled. Settings are read at session start. Hidden running apps are frozen in MRU order alongside the visible session, then appended when enough full visible cycles have completed. The next selection enters the revealed group in the current direction. Reveal lasts only until commit/cancel; no exclusion preference is removed. Partial reverse movement backtracks; completed laps in either direction are retained. Pointer selection or visible-app removal resets the partial lap. Dead hidden candidates are pruned. If no visible apps remain, configured reveal immediately exposes the hidden group; Never keeps exclusions hidden.

Automated checks cover exact one-/two-cycle boundaries in both directions, mixed-direction complete laps, key repeats, committing a revealed app, reset on physical-Command callback release, cancellation/session restart, Never, persisted/corrupt preferences, excluded foreground, pointer selection, app exit, zero/one visible app, duplicate hidden IDs, menu labels/checkmarks/action persistence and real registry/controller reveal retention. Keyboard checks route synthetic events directly through the callback; they do not post input or install a tap. Live physical switching with the new option has not yet been retested.


Verification for the Show after change: the complete local test runner passed, including the real keyboard-callback release/reset test; the read-only registry/controller/menu integration checks passed; the production app and isolated lab built and signed successfully. In the live native lab menu, Running, Not running and Show after headers and all three choices were present. Choosing 1 cycle persisted integer 1 in the isolated lab domain. Never was restored, and the disabled lab was normally closed (inventory confirmed exit). The rebuilt lab reported Accessibility not granted; no live interceptor was enabled and no physical Command-Tab test of this new behavior was claimed. Build output: `dist/Utilipilled.app`. The pre-existing CameraQuiet weak-capture compiler warning remains unrelated.


### Reveal timing clarification and pill/menu naming

The current heading is **Show hidden apps**, with **At end of first cycle**, **After start of second cycle**, **At end of second cycle**, and **Never**. Existing persisted values 1/2/0 retain their previous boundary behavior; the additional middle choice is value 3. For N visible apps with a visible foreground, these reveal at advancements N, N+1, and 2N respectively. The N+1 option leaves the ordinary wrap selection intact at N and enters the hidden group on the following advancement. Pending reveal is reset on dismissal, pointer selection, or a changed visible list; losing all deferred hidden candidates also clears it. Tests cover both directions, N=1/2/3/5, exact wrap selection, release at the boundary, hidden-app exit and keyboard callback routing.

App-level terminology is now pill/pills, including the `Sources/Utilipilled/Pills` directory and CameraQuietPill, KeepAwakePill, PercentageHiderPill and SwitcherHiderPill types. Build/test helper paths follow the rename; Swift compiler module-cache flags and persisted settings/recovery namespaces are intentionally unchanged.

The main Hide apps row uses alphabetized, distinct running hidden-app names if the full title fits within the existing menu text width; otherwise it uses the count. Saved non-running exclusions are omitted. Menu checks cover zero, exact-fit and overflow titles plus real running-app filtering. Status and duration values now start lowercase after their colon; Claude target uses sentence case. Credits say Visit the GitHub while retaining the link target. Reopening the menu is scheduled by the run loop rather than a main-dispatch block, avoiding the nested menu/termination wait captured during the previous Desktop update.


Current app-section names are NotificationRot, CaffeinePilled, PowerYeeted, SwitcherMogged and ClaudeMaxxing, as requested. Main headings, status-item descriptions and relevant alerts use these names. ClaudeMaxxing's percentage/deadline calculation is unchanged. Persisted keys and recovery/implementation namespaces retain their existing identifiers; the rename is presentation-only. Current README and development documentation use the new names.


Final verification for the terminology/menu/timing pass: the complete local test runner and read-only integration checks passed after the Pill/Pills move, wrap-plus-one timing and names/count summary changes. ClaudeMaxxing's title/date checks passed after the final display-name correction, and the final release build signed/verified successfully. The previous Desktop process quit normally. The Desktop app was atomically replaced with a byte-verified build, its prior bundle was retained under `.build/desktop-backups`, and the new Desktop executable/watchdog were confirmed running. Desktop and dist executable SHA-256 both equal `02fae4b897ec2073a9b1db267d0946be427d59fee9765f967b337bdbca5486cd`. The menu-only app is not exposed by the desktop UI tooling; running-path/hash checks establish build identity, not a new physical-keyboard acceptance result.


### Always visible, deprioritized apps

Show hidden apps now starts with Always, followed by the existing reveal timings and Never. Always uses persisted value 4; existing values and the Never default are unchanged. Sessions immediately combine the primary group's MRU list with the checked group's MRU list. Checked apps remain visible for the whole session and cannot enter the primary group simply by becoming recently active. Invoking from a checked foreground enters the primary group at its first app for forward navigation or its last app for backward navigation; if there is no primary group, switching uses the checked apps' normal MRU cycle. Runtime refresh retains the checked apps until dismissal, and the next session rebuilds both groups from current MRU. Other reveal policies continue to reset and hide as before.

Checks cover option order/checkmarks/persistence, immediate controller visibility and refresh retention, ordering across repeated foreground changes, quick primary-app swaps, entry from a deprioritized foreground in both directions, full-group cycling, duplicate IDs, app termination, empty groups, all-checked apps, and changing back to Never. The Always tooltip explains that these apps stay visible after the other apps.


Always-mode verification: the full local check runner and read-only menu/controller integration checks passed, and the signed app build succeeded. The existing installed process quit normally; the updated test app was published to the Desktop with the previous Desktop bundle retained under `.build/desktop-backups`. The new Desktop executable and watchdog were confirmed running, and its executable hash matched `dist/Utilipilled.app`. Physical Command-Tab behavior for Always remains a manual test; no tap was enabled by the verification process.
