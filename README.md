# Darktable Lens Corrector

A Lua script for [Darktable](https://www.darktable.org/) that provides lens metadata correction, automatic lens name substitution for lensfun compatibility, and crop factor fixes.

## Features

- **Manual lens selection** — Dropdown with predefined lens models (vintage lenses, manual lenses)
- **Automatic lens name substitution** — Maps EXIF lens names to lensfun-compatible names on import
- **Crop factor correction** — Fixes incorrect crop factor for specific lens+camera combinations
- **Capture time override** — Option to set current date/time as capture date
- **Film camera tagging** — Add tags for film cameras (Zenit, Nikon FE, Praktika)
- **Film stock tagging** — Add tags for film stocks (Ilford, Kodak, Shanghai, etc.)

## Installation

1. Copy `set_lens_model.lua` to your Darktable Lua scripts directory:
   - Linux: `~/.config/darktable/lua/`
   - macOS: `~/.config/darktable/lua/`
   - Windows: `%LOCALAPPDATA%\darktable\lua\`

2. Enable the script in Darktable:
   - Go to **Settings → Lua scripts**
   - Or add to your `luarc` file: `require "set_lens_model"`

3. Restart Darktable

## Usage

### Manual Mode

1. Select images in lighttable
2. Find "correct lens" panel in the right sidebar
3. Select lens model from dropdown
4. Optionally check "overwrite capture date/time"
5. Optionally select camera and/or film stock for tagging
6. Click "update"

### Automatic Mode

The script automatically processes images on import:
- Substitutes lens names for lensfun compatibility
- Corrects crop factor for configured lens+camera combinations
- Updates Darktable database directly (no RAW file modification)

## Configuration

### Adding Lens Name Substitutions

Edit the `lens_names` table:

```lua
local lens_names = {
    ["EXIF Lens Name"] = "Lensfun Compatible Name",
    -- Example:
    ["EF35mm f/2 IS USM"] = "Canon EF 35mm f/2 IS USM",
}
```

### Adding Crop Factor Fixes

Edit the `crop_factor_fix` table:

```lua
local crop_factor_fix = {
    ["Lens Name|Camera Model"] = true,
    -- Example:
    ["Tamron SP 24-70mm f/2.8 Di VC USD G2|Canon EOS 6D Mark II"] = true,
}
```

### Adding Manual Lenses

Edit the `lens` table:

```lua
{
    model = "Lens Name for EXIF",
    fl = "50",            -- focal length
    ap = "1.4",           -- aperture
    -- substitution = true,  -- only for auto-detect lenses
},
```

## Requirements

- Darktable 4.0+ with Lua support
- `exiftool` for EXIF modifications (manual mode only)
- `lib/dtutils` Lua library (included with darktable-lua-scripts)

## License

MIT License

## Author

Vladimir Tyrtov (@vtyrtov)
