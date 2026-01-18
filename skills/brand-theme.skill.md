---
name: brand-theme
description: Use when configuring app branding, theming, or visual styling. Guides through Q&A to capture logo, colors, and animation preferences, then generates theme_config.json.
---

# Brand Theme Configuration Skill

Guide deployment teams through a conversational Q&A to capture brand identity and generate a theme configuration file.

## When to Use

- User wants to customize the app's visual appearance
- User asks to "set up branding", "configure theme", or "reskin the app"
- User invokes `/brand-theme` directly

## Process Overview

Walk through three focused areas in order:
1. **Logo** - File paths for light/dark mode logos
2. **Colors** - Primary brand colors (accepts multiple input formats)
3. **Animation Style** - Visual effects preset from flutterfx_widgets

## Step 1: Logo Configuration

Ask the user:

```
Let's set up your brand. First, the logo.

Do you have separate logos for light and dark modes?
1. Yes, I have separate logos
2. No, I have a single logo for both modes
```

**If separate logos:**
- Ask: "What's the path to your light mode logo? (used on light backgrounds)"
- Then: "What's the path to your dark mode logo? (used on dark backgrounds)"

**If single logo:**
- Ask: "What's the path to your logo file?"
- Use the same path for both light and dark in the config

**Validation:**
- Check that provided paths exist in the project
- Warn if paths don't exist but allow proceeding (user may add files later)

## Step 2: Color Configuration

Ask the user:

```
Now for your brand colors.

What's your primary brand color? You can provide:
- A hex code (e.g., #ff5f46)
- A color name (e.g., electric blue)
- A brand reference (e.g., like Stripe's purple)
- A description (e.g., warm sunset orange)
```

### Color Normalization

Convert user input to hex values:

**Hex codes:** Use directly (validate format)

**Common color names:**
| Name | Hex |
|------|-----|
| electric blue | #00D4FF |
| coral | #FF6B6B |
| midnight | #0A0A14 |
| forest green | #228B22 |
| sunset orange | #FF5F46 |
| royal purple | #6366F1 |
| hot pink | #FF00FF |
| gold | #FFD700 |
| teal | #008B8B |
| crimson | #DC143C |

**Brand references:**
| Brand | Primary Hex |
|-------|-------------|
| Databricks | #FF5F46 |
| Stripe | #635BFF |
| Slack | #4A154B |
| Spotify | #1DB954 |
| Discord | #5865F2 |
| GitHub | #24292E |
| Linear | #5E6AD2 |
| Vercel | #000000 |
| Figma | #F24E1E |
| Notion | #000000 |

**Descriptive input:** Interpret the description and map to appropriate hex:
- "warm" → orange/red spectrum
- "cool" → blue/green spectrum
- "vibrant/electric" → high saturation
- "muted/soft" → lower saturation
- "dark/deep" → lower lightness
- "light/bright" → higher lightness

### Secondary and Accent Colors

After primary color, ask:

```
Would you like to specify secondary and accent colors, or have them auto-generated?
1. Auto-generate from primary (recommended)
2. I'll specify them manually
```

**If auto-generate:**
Use color theory to derive:
- Secondary: Complementary or analogous to primary
- Accent: Triadic or split-complementary

**If manual:**
- Ask for secondary color (same input formats)
- Ask for accent color (same input formats)

### Derived Colors

Always auto-generate these based on primary/secondary:
- `primaryForeground`: Contrasting text color (white or dark based on primary lightness)
- `muted`: Desaturated version of primary at low lightness
- `mutedForeground`: Medium gray with slight color tint

## Step 3: Animation Style

Ask the user:

```
Finally, what visual style fits your brand?

1. cosmic - Starfield background, rising particles, smooth fades
2. neon - Glowing borders, electric highlights, particle bursts
3. minimal - Clean transitions, subtle motion only
4. professional - Refined cards, understated loading indicators
5. playful - Bouncy effects, colorful particles
```

### Style Preset Mappings

Effects sourced from: https://github.com/flutterfx/flutterfx_widgets

| Style | background | loading | transitions | interactive |
|-------|------------|---------|-------------|-------------|
| cosmic | cosmic_background | rising_particles | blur_fade | — |
| neon | border_beams | wave_ripple | blur_fade | cool_mode_particles |
| minimal | — | progress_loader | blur_fade_subtle | — |
| professional | fancy_card | progress_loader | blur_fade | — |
| playful | flickering_grid | rising_particles | motion_blur | cool_mode_particles |

## Step 4: Theme Mode Preference

Ask the user:

```
Which theme mode should be the default?
1. Dark mode (recommended for most modern apps)
2. Light mode
3. Follow system preference
```

## Output Generation

After completing all questions, generate the config file.

### File Location

Write to: `assets/config/theme_config.json`

### JSON Template

```json
{
  "brand": {
    "name": "[BRAND_NAME or 'BrickChat']",
    "logo": {
      "light": "[LIGHT_LOGO_PATH]",
      "dark": "[DARK_LOGO_PATH]"
    }
  },
  "colors": {
    "primary": "[PRIMARY_HEX]",
    "secondary": "[SECONDARY_HEX]",
    "accent": "[ACCENT_HEX]",
    "derived": {
      "primaryForeground": "[CALCULATED]",
      "muted": "[CALCULATED]",
      "mutedForeground": "[CALCULATED]"
    }
  },
  "animation": {
    "style": "[STYLE_NAME]",
    "source": "https://github.com/flutterfx/flutterfx_widgets",
    "effects": {
      "background": "[EFFECT_OR_NULL]",
      "loading": "[EFFECT_OR_NULL]",
      "transitions": "[EFFECT_OR_NULL]",
      "interactive": "[EFFECT_OR_NULL]"
    }
  },
  "modes": {
    "default": "[dark|light|system]",
    "available": ["light", "dark"]
  },
  "meta": {
    "generated": "[ISO_TIMESTAMP]",
    "version": "1.0"
  }
}
```

## Post-Generation

After writing the config file:

1. Display a summary of what was configured
2. Show the generated JSON
3. Inform user about next steps:

```
Theme configuration saved to assets/config/theme_config.json

Summary:
- Logo: [paths]
- Primary color: [hex] ([original input])
- Animation style: [style]
- Default mode: [mode]

Next steps:
- Run /apply-theme to generate Dart code from this configuration
- Or manually update lib/core/theme/app_colors.dart using these values
```

## Validation Checklist

Before writing the config file, verify:
- [ ] At least one logo path is provided
- [ ] Primary color is a valid hex code
- [ ] Animation style is one of: cosmic, neon, minimal, professional, playful
- [ ] Default mode is one of: dark, light, system

## Error Handling

**Invalid color format:**
```
I couldn't interpret "[input]" as a color. Could you try:
- A hex code like #ff5f46
- A color name like "coral" or "electric blue"
- Or describe it differently?
```

**Missing logo path:**
```
I need at least one logo path to continue. Where is your logo file located?
(e.g., assets/images/logo.png)
```

**Unknown brand reference:**
```
I don't have "[brand]" in my reference list. Could you provide:
- The hex code directly
- Or describe the color you're looking for?
```
