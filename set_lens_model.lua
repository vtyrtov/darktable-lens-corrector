--[[
    Darktable Lua Script: Lens Model Corrector

    Adds a dropdown menu with lens models to the "Actions on selection" module
    and allows setting the selected lens model in image metadata via exiftool.

    Features:
    - Manual lens selection with automatic EXIF update
    - Lens name substitution for lensfun compatibility
    - Crop factor correction for specific lens+camera combinations
    - Film camera tagging (Zenit, Nikon, Praktika)
    - Film stock tagging
    - Automatic lens correction on import

    Author: Vladimir Tyrtov
    License: MIT
]]

local darktable = require "darktable"
local du = require "lib/dtutils"
local gettext = darktable.gettext.gettext

local function _(msgid)
    return gettext(msgid)
end

-- Lens name substitution table (for lensfun compatibility)
-- Maps EXIF lens names to lensfun-compatible names
local lens_names = {
    ["EF70-200mm f/4L IS USM"] = "Canon EF 70-200mm f/4L IS USM",
    ["EF35mm f/2 IS USM"] = "Canon EF 35mm f/2 IS USM",
    ["EF16-35mm f/4L IS USM"] = "Canon EF 16-35mm f/4L IS USM",
    ["28 - 70mm F2.8 DG DN | Contemporary 021"] = "28-70mm F2.8 DG DN | Contemporary 021",
    ["Sigma 50mm f/1.4 DG HSM | A"] = "Sigma 50mm f/1.4 DG HSM | A",
    ["COMMLITE+Canon EF 35mm f/2 IS USM"] = "Canon EF 35mm f/2 IS USM",
    ["COMMLITE+Canon EF 135mm f/2 L USM"] = "Canon EF 135mm f/2 L USM",
    ["35mm F2 DG DN | Contemporary 020"] = "Sigma 35mm F2 DG DN | Contemporary 020",
    ["TAMRON SP 24-70mm F/2.8 Di VC USD G2 A032"] = "Tamron SP 24-70mm f/2.8 Di VC USD G2",
    ["Tamron SP 24-70mm f/2.8 Di VC USD G2"] = "Tamron SP 24-70mm f/2.8 Di VC USD G2",
}

-- Crop factor correction table
-- For lens+camera combinations that report incorrect FocalLengthIn35mmFormat
-- Key: "<lens_name>|<camera_model>", Value: true if correction needed
local crop_factor_fix = {
    ["Tamron SP 24-70mm f/2.8 Di VC USD G2|Canon EOS 6D Mark II"] = true,
}

-- Available lens models for manual selection
local lens = {
    {
        model = "*Sigma|Canon|Tamron on S5|6Dm2",
        substitution = true,
        fl = "",
        ap = "",
    },
    {
        model = "Jupiter-37AM MC 3.5/135",
        fl = "85",
        ap = "2.0",
    },
    {
        model = "Jupiter-9 2/85",
        fl = "85",
        ap = "2.0",
    },
    {
        model = "Jupiter-21A 4/200",
        fl = "200",
        ap = "4.0",
    },
    {
        model = "Carl Zeiss Planar T* 1,4/50 ZF",
        fl = "50",
        ap = "1.4",
    },
    {
        model = "Carl Zeiss Jena Pancolar 50mm f/1.8",
        fl = "50",
        ap = "1.8",
    },
    {
        model = "Carl Zeiss Jena Sonnar 135mm f/3.5",
        fl = "135",
        ap = "3.5",
    },
    {
        model = "Carl Zeiss Jena Flektogon 35mm f/2.8",
        fl = "35",
        ap = "2.8",
    },
    {
        model = "Helios-44 58mm 1:2",
        fl = "58",
        ap = "2.0",
    },
    {
        model = "Helios-44M 58mm f/2",
        fl = "58",
        ap = "2.0",
    },
    {
        model = "Mir-1 37mm f/2.8",
        fl = "37",
        ap = "2.8",
    },
    {
        model = "Mir-24M MC 35mm f/2",
        fl = "35",
        ap = "2.0",
    },
    {
        model = "Zenitar-M 1.7/50",
        fl = "50",
        ap = "1.7",
    },
    {
        model = "7Artisans 28mm f/1.4",
        fl = "28",
        ap = "1.4",
    },
    {
        model = "Konica Hexanon AR 50/1.7",
        fl = "50",
        ap = "1.7",
    },
    {
        model = "Volna-9 2.8/50 MC",
        fl = "50",
        ap = "2.8",
    },
    {
        model = "Samyang 85mm f/1.4 IF UMC Aspherical",
        fl = "85",
        ap = "1.4",
    },
}

local lens_list = {}
for _, v in ipairs(lens) do
    table.insert(lens_list, v.model)
end

table.sort(lens_list)

-- Extract lens parameters from the lens table
local function extract_lens(model, exif_lens)
    for _, v in ipairs(lens) do
        if v.model == model then
            if v.substitution then
                if lens_names[exif_lens] then
                    return {
                        model = lens_names[exif_lens],
                        fl = v.fl,
                        ap = v.ap,
                        substitution = true,
                    }
                else
                    return nil
                end
            else
                return v
            end
        end
    end
    return nil
end

-- Create lens model dropdown widget
local lens_model_choice = darktable.new_widget("combobox") {
    label = _("lens model"),
    tooltip = _("Select lens model to set in metadata"),
    table.unpack(lens_list)
}

-- Checkbox: overwrite capture time with current date
local overwrite_time_checkbox = darktable.new_widget("check_button") {
    label = "overwrite capture date/time",
    value = false,
    tooltip = "If checked, current date/time will be written to EXIF (DateTimeOriginal/CreateDate/ModifyDate)"
}

-- Dropdown for camera selection (adds tags)
local camera_choice = darktable.new_widget("combobox") {
    label = "mark camera",
    tooltip = "Select camera to add corresponding tags",
    "---",
    "Nikon FE",
    "Praktika L2",
    "Zenit TTL",
    "Zenit 12cd",
    value = 1 -- default "---"
}

-- Dropdown for film stock selection (adds tag)
local film_choice = darktable.new_widget("combobox") {
    label = "mark film",
    tooltip = "Select film stock to add corresponding tag",
    "---",
    "Ilford Pan 400",
    "Kodak ColorPlus 200",
    "Kodak UltraMax 400 Color",
    "Lucky 400",
    "Shanghai GP3 400",
    "Shanghai GP3 100",
    value = 1 -- default "---"
}

-- Checkbox: mark as Zenit TTL (legacy, kept for reference) — добавляет теги "Пленка" и "Zenit TTL"
local mark_zenit_checkbox = darktable.new_widget("check_button") {
    label = "mark as Zenit TTL",
    value = false,
    tooltip = "If checked, tags 'Film' and 'Zenit TTL' will be added to the image"
}

-- Checkbox: mark as Nikon FE (legacy, kept for reference)
local mark_nikon_checkbox = darktable.new_widget("check_button") {
    label = "mark as Nikon FE",
    value = false,
    tooltip = "If checked, tags 'Film' and 'Nikon FE' will be added to the image"
}

-- Set lens parameters in Darktable database
local function set_darktable_lens_model(image, lens_model)
    -- Set lens model
    image.exif_lens = lens_model.model

    -- Set focal length if specified
    if lens_model.fl and lens_model.fl ~= "" then
        image.exif_focal_length = tonumber(lens_model.fl)
    end

    -- Set aperture if specified
    if lens_model.ap and lens_model.ap ~= "" then
        image.exif_aperture = tonumber(lens_model.ap)
    end
end


-- Ensure tag exists and return tag object
local function ensure_tag(tag_name)
    local tag = darktable.tags.find(tag_name)
    if not tag then
        tag = darktable.tags.create(tag_name)
    end
    return tag
end

-- Set lens model via exiftool (main processing function)
local function set_lens_model(images, model)
    for _, image in ipairs(images) do
        local path = image.path .. "/" .. image.filename
        local exif_lens = image.exif_lens
        local lens_model = extract_lens(model, exif_lens)
        local lens_missing = lens_model == nil
        -- Safe structure to avoid nil access
        local lm = lens_model or { model = "", fl = "", ap = "" }
        if lens_missing then
            darktable.print(string.format("[%s] No substitution found for lens '%s' - applying selected options only",
                image.filename, tostring(exif_lens)))
        end

        -- Build exiftool command with all parameters
        local exiftool_commands = {}

        -- Add lens model to EXIF if found
        if not lens_missing then
            table.insert(exiftool_commands, string.format('-LensModel="%s" -LensType="%s"', lm.model, lm.model))
        end

        -- Add focal length and aperture commands if specified
        if not lens_missing and lm.fl and lm.fl ~= "" then
            table.insert(exiftool_commands, string.format('-FocalLength="%s"', lm.fl))
        end
        if not lens_missing and lm.ap and lm.ap ~= "" then
            table.insert(exiftool_commands,
                string.format('-ApertureValue="%s" -MaxApertureValue="%s" -FNumber="%s"', lm.ap, lm.ap, lm.ap))
        end

        -- Check if crop factor correction needed for this lens+camera combination
        if not lens_missing and lm.substitution then
            local camera_model = image.exif_model or ""
            local override_key = lm.model .. "|" .. camera_model
            if crop_factor_fix[override_key] then
                -- For full frame: FocalLengthIn35mmFormat = FocalLength (crop = 1.0)
                local fl = image.exif_focal_length
                if fl and fl > 0 then
                    table.insert(exiftool_commands, string.format('-FocalLengthIn35mmFormat="%d"', math.floor(fl + 0.5)))
                    -- Also update crop factor in Darktable database
                    image.exif_crop = 1.0
                    darktable.print(string.format("[%s] Crop factor fix: FocalLengthIn35mmFormat=%d, exif_crop=1.0",
                        image.filename, math.floor(fl + 0.5)))
                end
            end
        end

        -- If checked, overwrite capture time with current date
        if overwrite_time_checkbox.value then
            local ts = os.date("%Y:%m:%d %H:%M:%S")
            table.insert(
                exiftool_commands,
                string.format('-DateTimeOriginal="%s" -CreateDate="%s" -ModifyDate="%s"', ts, ts, ts)
            )
        end

        -- Get selected camera from dropdown
        local selected_camera = camera_choice.value

        -- Get selected film from dropdown
        local selected_film = film_choice.value

        -- Combine all commands into single string
        local command = nil
        if #exiftool_commands > 0 then
            command = string.format('exiftool -overwrite_original %s "%s"', table.concat(exiftool_commands, " "), path)
        end

        -- Update parameters in Darktable database
        if not lens_missing then
            set_darktable_lens_model(image, lm)
        end

        -- Add tags based on selected camera
        if selected_camera ~= "---" then
            local tag_film = ensure_tag("Film")
            local tag_camera = ensure_tag(selected_camera)
            pcall(function() darktable.tags.attach(tag_film, image) end)
            pcall(function() darktable.tags.attach(tag_camera, image) end)
        end

        -- Add film stock tag if selected
        if selected_film ~= "---" then
            local tag_film_type = ensure_tag(selected_film)
            pcall(function() darktable.tags.attach(tag_film_type, image) end)
        end

        -- darktable.print_log(command)

        -- Execute command
        if command then
            local handle = io.popen(command)
            if handle then
                handle:close()
                if not lens_missing then
                    darktable.print(string.format("[%s] %s", image.filename, lm.model))
                else
                    darktable.print(string.format("[%s] EXIF changes applied (no lens)", image.filename))
                end
            else
                darktable.print_error(string.format("Error executing command for %s", path))
            end
        end
    end

    darktable.print("Processed " .. #images .. " images")
end

-- Create apply button widget
local apply_button = darktable.new_widget("button") {
    label = _("update"),
    clicked_callback = function()
        local selected_images = darktable.gui.selection()
        if #selected_images == 0 then
            darktable.print_error("No images selected")
            return
        end

        set_lens_model(selected_images, lens_model_choice.value)
    end
}

-- Register widgets in lighttable right panel
darktable.register_lib(
    "lens_model_selector",
    "correct lens",
    true,
    false,
    {
        [darktable.gui.views.lighttable] = { "DT_UI_CONTAINER_PANEL_RIGHT_CENTER", 100 },
    },
    darktable.new_widget("box") {
        orientation = "vertical",
        lens_model_choice,
        overwrite_time_checkbox,
        camera_choice,
        film_choice,
        apply_button
    }
)

--[[
    Automatic processing after image import (post-import-image event)
    Updates metadata directly in Darktable database (without modifying RAW file)
]]

local function auto_fix_on_import(event, image)
    local exif_lens = image.exif_lens or ""
    local camera_model = image.exif_model or ""

    darktable.print("[post-import] " .. image.filename .. " lens: " .. exif_lens)

    -- Check if lens substitution exists
    local new_lens_name = lens_names[exif_lens]
    if not new_lens_name then
        return
    end

    -- Update lens name in Darktable database
    image.exif_lens = new_lens_name

    -- Check if crop factor correction needed
    local override_key = new_lens_name .. "|" .. camera_model
    local need_crop_fix = false
    if crop_factor_fix[override_key] then
        -- Set crop factor = 1.0 (full frame)
        image.exif_crop = 1.0
        need_crop_fix = true
    end

    local msg = string.format("[auto-import] %s: %s", image.filename, new_lens_name)
    if need_crop_fix then
        msg = msg .. " (crop=1.0)"
    end
    darktable.print(msg)
end

-- Register post-import-image event handler
darktable.register_event("lens_auto_fix", "post-import-image", auto_fix_on_import)
darktable.print("[set_lens_model] post-import-image event registered")
