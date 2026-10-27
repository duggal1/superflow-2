# DESIGN_RULES.md

Read before writing any UI. Every rule is checkable. If you can't point to a token, a number, or a reason for a visual decision, don't make it.

## 0. Process (mandatory)

1. Before writing UI, list the tokens you'll use: spacing, radii, type sizes, colors, control heights. Use only those.
2. Build.
3. Screenshot it. Run the checklist at the bottom. Fix before reporting done.
4. Delete anything that doesn't carry information or affordance.

## 1. Anti-slop

Banned unless the user explicitly asks:

- Gradient text, purple/indigo-to-blue gradients, glows, neon shadows
- Glassmorphism / blur cards as decoration
- Emoji as icons, "✨ New" pill badges, centered-badge-above-hero patterns
- Every feature as an icon-in-a-colored-rounded-square card in a 3-column grid
- `rounded-2xl` + `shadow-xl` on everything
- Unmodified shadcn defaults, untouched Tailwind palette, Inter at default settings with no tracking or weight decisions
- Gradient or glowing fill progress bars, shimmer skeletons everywhere, bouncy springs
- Lorem ipsum, fake testimonials, fake stats, "Acme Inc"

Test: swap the logo. If the screen could belong to any other SaaS, redesign it.

Reference for the standard. Progress is a quiet indicator, not a loud bar:

```tsx
import { cn } from "@/lib/utils";

export function ProgressDots({ value }: { value: number }) {
  const complete = value >= 100;
  const current = value >= 88 ? 2 : value >= 62 ? 1 : 0;
  return (
    <div
      role="progressbar"
      aria-valuemin={0}
      aria-valuemax={100}
      aria-valuenow={value}
      className="flex items-center justify-center gap-1.5"
    >
      {Array.from({ length: 3 }).map((_, index) => (
        <span
          key={index}
          aria-hidden="true"
          className={cn(
            "h-1 rounded-full transition-[width,background-color] duration-300 ease-[cubic-bezier(0.22,1,0.36,1)] motion-reduce:transition-none",
            complete
              ? "w-4 bg-neutral-300"
              : index === current
                ? "w-6 bg-neutral-300"
                : index < current
                  ? "w-1.5 bg-neutral-800"
                  : "w-1.5 bg-neutral-900",
          )}
        />
      ))}
    </div>
  );
}
```

## 2. Spacing

- 4px base grid. Allowed values: 4, 8, 12, 16, 24, 32, 48, 64. No arbitrary values (`p-[13px]` is a bug).
- Proximity rule: space inside a group is always smaller than space between groups. Hierarchy comes from spacing before it comes from size or color.
- Card padding 16 or 24, never mixed within one view.
- "Breathing room" means clear grouping, not big gaps everywhere. This is B2B: dense where users scan, spacious only around the one primary thing.

## 3. Surfaces, not borders

- Separate layers with background luminance steps, not borders.
- Dark mode: page bg ~L4-6%, surface +3-4%, raised +3-4% more. Light mode: the inverse, with surfaces slightly darker or lighter than the page, never pure white on pure white.
- Cards: no border, no shadow, just a bg step. Shadows only for floating layers (menus, popovers, modals).
- Borders allowed only for: inputs, focus rings, table row dividers, and hairlines at 6-8% alpha.
- Never stack border + shadow + bg on the same element.

## 4. Color

- Neutral base, tinted ~2-4% toward the accent hue so greys feel designed, not default.
- One accent. It marks the primary action and the active state, nothing else. One accent-filled element per view.
- Semantic colors (green/amber/red) are for status only.
- Text hierarchy = 3 defined tokens (primary, secondary, tertiary). Don't fake hierarchy with random opacity.
- Contrast: body and secondary text >= 4.5:1, tertiary >= 3:1 and only for non-essential text.

## 5. Type

- One family. Max two if one is mono.
- 5 sizes max (e.g. 12 / 13 / 14 / 16 / 24). Dense UI body is 13-14px. Never below 12px.
- 2 weights (400, 500). 600 only for rare emphasis.
- Line height: 1.5 body, 1.2 headings. Tracking on large headings: -0.01em to -0.02em.
- `tabular-nums` on every number that can change or align in a column.
- Sentence case. Uppercase only for tiny labels, with +0.04em tracking.

## 6. Pixel precision

- No fractional layout values. Borders and dividers are 1px.
- One radius scale: 4 / 6 / 8 / 12. Nested radius = outer radius - padding.
- Control heights: 28 / 32 / 36 only. Same row, same height.
- Icons: 16 or 20px boxes, one stroke width (1.5) across the app. Optically center icons against the text's cap height, not the line box.
- Equal visual padding on all sides of a container. Check by eye at 2x, not just in code.
- Anything misaligned by 1px is a bug. Fix it.

## 7. Motion

- 150-250ms. Easing `cubic-bezier(0.22, 1, 0.36, 1)`.
- Animate transform, opacity, and size only, and only to explain a state change.
- Always honor `prefers-reduced-motion`.
- No decorative or looping animation.

## 8. B2B product rules

- Information first. Show real states, real data, real units.
- Every view has designed empty, loading, and error states.
- Keyboard-first: visible shortcuts, command palette where there's more than ~10 actions.
- Copy is short, specific, verb-led. No marketing voice inside the product.
- Show system status (what's running, what finished, what failed) without being asked.

## 9. Interaction states

Every interactive element has: default, hover, `focus-visible`, active, disabled. Focus ring is always visible and never removed. Hit target >= 32px on desktop.

## Pre-ship checklist

- [ ] Only tokens from step 0 are used
- [ ] Nothing from the banned list
- [ ] Layers separated by bg, not borders
- [ ] One accent-filled element per view
- [ ] Grouping is obvious from spacing alone
- [ ] All numbers tabular, all icons aligned, all radii on scale
- [ ] All five interaction states + empty/loading/error exist
- [ ] Reduced-motion honored
- [ ] Screenshot reviewed at 2x