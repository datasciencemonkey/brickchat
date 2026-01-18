# Brand Theme Skill Design

## Overview

A Claude Code skill that guides deployment teams through a conversational Q&A to capture brand identity, then generates a `theme_config.json` file for app theming.

**Skill name:** `brand-theme` (invoked as `/brand-theme`)

**Target users:** Deployment teams configuring BrickChat for different brands without code changes

**Output:** `assets/config/theme_config.json`

**Companion skill (future):** `/apply-theme` - reads the JSON and generates Dart code updates

## Q&A Flow

The skill walks through three focused areas:

### Step 1: Logo

```
"Let's set up your brand. First, the logo.

Do you have separate logos for light and dark modes, or a single logo?"
```

- If separate: ask for light logo path, then dark logo path
- If single: ask for the path, note it will be used for both modes

### Step 2: Colors

```
"Now for your brand colors.

What's your primary brand color? You can provide:
- A hex code (#ff5f46)
- A color name (electric blue)
- A reference (like Stripe's purple)
- Or describe it (warm sunset orange)"
```

- Follow up for secondary/accent if user wants, or derive algorithmically
- If user provides an image path, extract dominant colors

**Color input formats accepted:**
- Hex codes: use as-is
- Color names: map common names to hex (built-in list)
- Brand references: lookup table of known brands (Databricks, Stripe, etc.)
- Natural language: interpret descriptively (e.g., "warm sunset" → orange-red spectrum)
- Image: instruct to use color extraction tools

### Step 3: Animation Style

```
"Finally, what visual style fits your brand?"

1. cosmic - Starfield background, rising particles, smooth fades
2. neon - Glowing borders, electric highlights, particle bursts
3. minimal - Clean transitions, subtle motion only
4. professional - Refined cards, understated loading indicators
5. playful - Bouncy effects, colorful particles
```

## JSON Config Schema

```json
{
  "brand": {
    "name": "Acme Corp",
    "logo": {
      "light": "assets/images/acme-logo-dark.png",
      "dark": "assets/images/acme-logo-light.png"
    }
  },
  "colors": {
    "primary": "#00D4FF",
    "secondary": "#FF00FF",
    "accent": "#FFE500",
    "derived": {
      "primaryForeground": "#0A0A14",
      "muted": "#1E1E32",
      "mutedForeground": "#9090B0"
    }
  },
  "animation": {
    "style": "neon",
    "source": "https://github.com/flutterfx/flutterfx_widgets",
    "effects": {
      "background": "border_beams",
      "loading": "wave_ripple",
      "transitions": "blur_fade",
      "interactive": "cool_mode_particles"
    }
  },
  "modes": {
    "default": "dark",
    "available": ["light", "dark"]
  },
  "meta": {
    "generated": "2026-01-18T10:30:00Z",
    "version": "1.0"
  }
}
```

**Notes:**
- `derived` colors are auto-calculated from primary/secondary using color theory
- `effects` maps to specific flutterfx_widgets components
- `meta` tracks when config was generated for debugging

## Animation Style Presets

Effects sourced from: [flutterfx/flutterfx_widgets](https://github.com/flutterfx/flutterfx_widgets)

| Style | Background | Loading | Transitions | Interactive |
|-------|------------|---------|-------------|-------------|
| **cosmic** | CosmicBackground | RisingParticles | BlurFade | — |
| **neon** | BorderBeamsBackground | AnimatedWaveRipple | BlurFade | CoolMode particles |
| **minimal** | — | ProgressLoader | BlurFade (subtle) | — |
| **professional** | FancyCard backgrounds | ProgressLoader | BlurFade | — |
| **playful** | FlickeringGrid | RisingParticles | MotionBlur | CoolMode particles |

Each preset includes:
- Intensity multiplier (affects animation duration/amplitude)
- Color integration (effects use brand colors from config)
- Reference to specific widget implementations in the flutterfx repo

## Skill File Structure

Location: `skills/brand-theme.skill.md`

Key sections:
1. **Frontmatter** - name, description, trigger conditions
2. **Context gathering** - Read existing theme files to understand current state
3. **Q&A protocol** - Step-by-step questions with multiple choice where possible
4. **Color processing** - Rules for normalizing various color inputs to hex
5. **Style presets** - Mapping of style names to flutterfx effect combinations
6. **Output generation** - JSON template and file write instructions
7. **Validation** - Verify paths exist, colors are valid hex

## Implementation Notes

- Skill should be project-level (not global) since it's specific to BrickChat
- Q&A uses multiple choice where possible for easier answering
- Color normalization handles fuzzy inputs gracefully
- Generated JSON includes metadata for debugging/versioning
- Future `/apply-theme` skill will read this JSON and update Dart code
