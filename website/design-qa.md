# Estrobo website — design QA

Date: 2026-08-07

## Scope

- Routes: `/`, `/guia/`, `/404/`
- Desktop reference viewport: 1672 × 941 px
- Mobile validation viewport: 390 × 844 px
- Browser: Codex in-app browser
- Source captures: the eight ImageGen references in `design-references/`
- Implementation captures: the final browser screenshots in `qa/`

## Combined visual comparisons

The source and implementation were placed together at the same 1672 × 941 px viewport before judging differences.

- Hero: `qa/comparison-hero.png`
  - Source: `design-references/01-hero.png`
  - Implementation: `qa/home-desktop-1672x941.png`
  - Result: the implementation preserves the deep-ink studio setting, large left-aligned wordmark, amber CTA, restrained navigation, and dominant product view. It replaces the synthetic laptop framing with an exact public-beta interface capture so the website does not imply UI that the downloadable build lacks.
- Product views: `qa/comparison-product.png`
  - Source: `design-references/04-product.png`
  - Implementation: `qa/home-product-inspector-1672x941.png`
  - Result: the implementation preserves the ivory editorial composition, oversized heading, amber detail, and dark app surface. The static three-window composition became an accessible three-tab switcher so Canales, Inspector, and Matriz are all usable rather than decorative.

## Responsive and interaction evidence

- Desktop home: `qa/home-desktop-1672x941.png`
- Desktop guide: `qa/guide-desktop-1672x941.png`
- Mobile home: `qa/home-mobile-390x844.png`
- Mobile menu: `qa/home-mobile-menu-390x844.png`
- Mobile guide: `qa/guide-mobile-390x844.png`
- Main navigation reaches the guide route.
- The Canales, Inspector, and Matriz tabs respond to clicks and orientation-aware keyboard arrow navigation, update `aria-selected`, and reveal the correct real screenshot.
- The mobile menu updates `aria-expanded`, locks background scrolling, exposes all navigation links, moves focus inside on open, traps focus, closes on Escape, restores focus to its trigger, and has no horizontal overflow.
- The guide copy control changes to its confirmed state, and the troubleshooting disclosures open correctly.
- All tested routes completed without browser console errors or warnings.
- The final 390 px home and guide layouts report equal document and viewport widths: no horizontal overflow.

## Findings and fixes

1. P1 — Global images kept their intrinsic pixel height while their width shrank, making the hero more than 2300 px tall and placing its copy below the first viewport. Fixed with proportional global image sizing (`height: auto`) and re-captured.
2. P2 — Oversized guide imagery caused horizontal overflow at 390 px. Fixed with contained mobile media widths and re-captured; document width now equals viewport width.
3. P2 — Astro's development toolbar polluted the local preview and accessibility tree. Disabled in project configuration and verified absent.
4. Build blocker — The icon-font import used an internal package path that Vite could not resolve. Replaced with the public package export and added the side-effect module declaration; build now passes cleanly.
5. P2 — The default header state made the 404 page's section links resolve against `/404/`. Changed the default to a neutral page state so those links return to the matching home-page sections.
6. P2 — The collapsed mobile navigation remained reachable to keyboard users. Added an early `.js` document state, `inert`, hidden visibility, disabled pointer events, an initial-focus target, a two-way focus trap, Escape handling, and trigger-focus restoration while retaining a no-JavaScript fallback.
7. P2 — The initial focus and muted/amber text colors did not provide sufficiently robust contrast across dark and light surfaces. Added a two-layer white/cobalt focus treatment and deepened the muted and amber text tokens; measured contrast now clears WCAG AA for the tested surfaces.
8. Product-truth risk — The compatibility copy could be read as broader physical validation than the recorded evidence supports. The front-page compatibility section was removed, and the guide now limits its evidence to the tested Godox X3Pro for Sony + AD400Pro II combination.
9. Product-truth risk — The first generated local-control illustration showed a cable between the Mac and trigger, conflicting with the Bluetooth workflow. Replaced it with an ImageGen edit that clearly separates the devices and re-verified the final asset visually.
10. P2 — The tab list announced a fixed horizontal orientation while the mobile layout stacks vertically. Orientation is now resolved from the live layout, with Left/Right keys on desktop and Up/Down keys on mobile, plus Home/End support.
11. P2 — The custom 404 page was indexable and carried the site's home canonical URL. The page now emits `noindex, nofollow` and omits its canonical URL.
12. P2 — The checksum copy control confirmed success visually but did not expose that state to assistive technology. Its feedback is now an `aria-live` status and the control's accessible label updates after copying.
13. Security-flow risk — The guide previously described an unsigned ZIP flow. It now uses the signed and notarized DMG, documents the standard drag-to-Applications installation, and retains checksum verification as an optional detail.
14. Security guidance — Added a reminder not to reuse a personal PIN for the optional locally stored radio code.
15. Performance — Raw multi-megabyte generated and app captures were publicly served. The site now uses optimized WebP/JPEG derivatives, keeps archival PNG sources outside `public/`, and suppresses the decorative hero background on narrow screens.
16. Usability — The product-view controls scrolled away while evaluating tall real-app captures. The selector now stays visible in the desktop inspection layout.
17. Final browser pass — Rechecked home, guide, and 404 at 1672 × 941 px and 390 × 844 px. Verified clean console output, exact screenshot dimensions, no horizontal overflow, safe guide CTA, cable-free local-control art, keyboard behavior, and 404 metadata.
18. P0 — The guide body inherited the page's deep-ink background while its reading text also used deep ink, producing 1:1 contrast below the hero. Split the guide and 404 page surfaces so the guide reads on paper while its hero remains dark; verified the installation step in desktop and mobile production previews.
19. P1 — Small dark-amber eyebrow text reached only 2.72:1 on the amber closing sections. Those two contexts now use the primary ink token at 8.67:1 while light reading surfaces retain the original amber-deep accent.
20. P2 — Link-initiated mobile navigation restored focus to the now-hidden menu trigger. Same-page navigation now closes without that jump and moves focus to the destination heading; Escape and explicit menu closure still restore focus to the trigger.
21. P2 — Secondary text links were shorter than the recommended 44 px touch target. Shared text links now have a 44 px minimum block size without changing their visual hierarchy.
22. P2 — Several two-column layouts crossed their intrinsic minimum just above the former 62rem collapse point. Content grids now collapse at 68rem while the navigation retains its independent 62rem breakpoint; 1024 × 768 px was checked without clipping.
23. P2 — Product captures decoded at their original 2774 px width on narrow screens and the interactive switcher intentionally clipped them to 135%. Added uncropped 960 px and 1600 px WebP sources plus `srcset`/`sizes`, and restored the complete screenshot at 390 px. The browser selected the 960 px Inspector asset on mobile.
24. P2 — The long guide had no persistent location on mobile. Added a compact sticky progress link, synchronized `aria-current="location"` in the index, and verified direct hash entry and scroll state for “02 de 07 · Instalar Estrobo”.
25. P2 — Release identity was repeated across five source files. Version, DMG asset name, and download URLs now come from one typed release module; the live prerelease inventory contains the DMG, manifest, and `SHA256SUMS` named by the site.
26. P2 — The screenshot tabs and copy button lacked a deliberate no-JavaScript state. The static page now exposes every product panel while hiding inactive controls without JS; normal JS initializes the tab state without layout flash, and the copy control remains an enhancement.
27. Performance — App screenshots now use responsive candidates, the below-fold switcher is lazy-loaded, hero captures receive high fetch priority, and the detector's real `layout-transition` warning was removed. Its remaining Instrument Sans warning is a reviewed false positive against the site's established wordmark-adjacent typography.
28. Final production round — Built with the supported Node 24 runtime, produced all three static routes with zero diagnostics, then verified desktop, tablet, 390 px mobile, and 320 px minimum-width states against the production preview. Home, guide, tabs, copy feedback, mobile menu/focus, guide progress, 404 metadata, responsive image selection, overflow, and console output all passed.
29. Independent closeout — The final read-only audit scored the presentation 18/20 (Excellent). Its remaining notes were closed by normalizing the brand, footer, and copy-control touch targets to 44 px and explicitly declaring the site's light color scheme.

## Final assessment

No open implementation P0 or WCAG P1 issues remain in the validated scope. Two product-copy decisions were intentionally not changed during refinement: whether the first CTA should download immediately or route through the safety preflight, and how prominently the hero should qualify the physically tested hardware combination. Both require product-owner wording approval rather than a silent design rewrite.

final result: passed
