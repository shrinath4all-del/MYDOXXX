# MYDOXXX local test-room browser checks

Updated 3 November 2026. These checks use synthetic accounts in `mydoxxx-testing`, project `mydoxxx-dev-261102`. They do not establish production or clinical readiness.

## Observed browser behavior

| Check | Observed result | Scope |
|---|---|---|
| Patient 2 → Nurse 1 request | A fresh targeted nursing request reached Nurse 1 | Real shared synthetic Firestore, not a seeded completion |
| Nurse 1 decline → Nurse 2 accept | Broadcast fallback allowed Nurse 2 to accept; booking became Confirmed | Sequential fallback; no simultaneous race, payment, OTP or completed visit claim |
| Cardiologist 1 independent zoom | Root browser QA reduced this pane to 80% while peers kept running | Local viewer control; app identity and backend data unchanged |
| Expand and Restore | Worked in the actual Flutter view while other panels stayed running | No full emergency workflow acceptance implied |
| Restore status feedback | Browser QA found a stale “Expanded” message; corrected to “Restored …” with regression assertion | Code/unit verified; no additional browser-text result claimed |
| Optional iPhone presentation frame | Root browser review confirmed bezel, island/status area and home indicator before the height increase | Presentation toggle on; app viewport stays separate from frame decoration |
| Taller presentation phones | Live DOM measurements changed the Patient phone height from **600.488px to 752.5px**, approximately **25.3%**; Patient width stayed **337.676px** | All four phone heights measured 752.5px; account selection retained, picker closed, 6px panel gaps |

The read-only nursing audit recorded appointment `cNEO3F8ljP09prRKNzv0` with Patient 2, assigned Nurse 2, `Confirmed`, Nurse 1 in `declinedBy`, and payment still pending. The private receipt is `test-room-booking-audit-2026-11-03.json`; the audit wrote no Firestore records. Earlier Patient/Doctor booking and two-way seeded-chat observations remain documented separately in STATUS.md.

## Meaningful local regression checks

**16 Node console tests passed** after the phone-shell and restore-message changes. They exercise actual console JavaScript using a small DOM harness, without live credentials or network access:

- Exact 36-account catalogue, permitted project, unique origins/UIDs and no credential fields.
- Only four initial iframes; independent add/remove; saved account selections and safe separate tabs.
- Independent 60–140% zoom, reset and resized logical viewport; peers retain dimensions and sessions.
- Expand/resize/Restore/Escape/backdrop paths keep the same iframe object, parent and source assignment; removal releases background interaction.
- Restore announcement and absence of a spurious restore message during removal.
- iPhone frame default/toggle preference; frame status/home areas remain siblings outside the app viewport; narrow frames fit logical app width.

The earlier **23 Python host/security tests passed, one Windows symlink test skipped**. No host authentication or credential-boundary code changed for the presentation controls. These DOM/unit checks do not replace visual browser verification of layout and clinical workflows.

## Requested presentation refinements

The normal iPhone presentation shell has a 6px gap between panels and 4px side gutters. Its full height is now **25% larger than the prior computed baseline**, including the 30px status strip, 18px home strip and bezel. The iframe flexes into the added space without being replaced or reloaded. Width, zoom percentage, selection and backend behavior are unchanged. Plain view is unchanged; expanded phones still fit within the available viewport. These are local viewer CSS refinements. Root verified the taller layout through actual DOM measurements; the small difference from exactly 25% reflects the prior rendered baseline/rounding. Screenshot capture failed during this final check, so no new visual screenshot of the taller layout is claimed.

## Flutter responsive-dialog follow-up

The separate app fix is committed as **`b403f99f065b4fecc86800c52dd9a2bd496d911d`**. **21 focused tests passed**: 14 new dialog layout/action tests and seven existing SOS tests. Changed-file analysis reported no issues, and the release Web build passed. The existing full 413-test result was not rerun for this layout-only follow-up. Routing, acceptance transactions, timers and cancellation behavior were not changed by this fix.

Release `main.dart.js` SHA-256: `7b541bbc7999ce37244446f973ec81cd564f96ef149bcd8f26ca566e62451045`.

## Dummy service OTP follow-up

App commit **`57379575165107f3fe93228ce7a53287df445627`** centralizes 12 service-code generators. It returns **7777 only in the compile-time test lab**, while ordinary builds use random codes. Existing validators and Firebase Auth remain unchanged. **61 focused tests passed in normal mode and the same 61 in lab mode**, including six new OTP checks. Analysis reported zero errors/warnings and one pre-existing nurse style information notice. Release build passed; `main.dart.js` SHA-256: `d4e2073df9652fda999ff952c48be348882963ba7419f5c4409bf24ee1353d3a`. The full 413-test suite was not rerun for this follow-up.

The separate backend migration verified nine OTP fields on four synthetic appointments against a full 352-document snapshot. All non-OTP fields, Auth/passwords, default rules and protected backends remained unchanged. Existing expiry/issuance, payment, status, assignment and retry checks still apply. Offline migration safety checks passed without cloud calls.

Root browser QA confirmed all four role selectors are **18px, bold red and visible without header collisions**, and the **Test booking / duty OTP: 7777** notice is visible. The new release was reloaded with Patient 1, Cardiologist 1, Hospital 1 and Ambulance 1 retained. [Header and test-code screenshot](../mydoxxx-test-room-2026-11-03/evidence/red-role-headings-7777.png). This is evidence of stored-code migration and generator tests, **not evidence that a live OTP entry or duty/consultation completion succeeded**.

## Remaining browser checks

1. Capture the latest taller layout when screenshot capture becomes available, and verify narrow/plain-view variants with real request controls.
2. Recheck the corrected Restore message, zoom reset and independent zoom limits visually.
3. Exercise a fresh doctor emergency notification after the responsive-dialog app rebuild; verify Decline/Accept and relevant status actions remain reachable without changing routing/timers.
4. Enter 7777 in a fresh eligible synthetic booking/duty and observe the actual result; do not infer success from the stored-code migration or notice alone.
5. Test simultaneous acceptance separately if a race guarantee is required; the sequential nurse result is not evidence of that guarantee.
6. Test later OTP/completion/chat stages and other role workflows explicitly. Real SMS, FCM, payouts and live dispatch remain excluded.

The presentation frame, zoom and expand features belong to the local test viewer only. They do not alter Firebase records, roles, UIDs or the installed Flutter app design.
