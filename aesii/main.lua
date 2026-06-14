-- AES-II GI275 STYLE ENGINE WIDGET
-- Full-screen 480x320 Ethos widget
-- Widget key must remain: aesii
--
-- Display:
--   CHT1       boxed RPM       CHT2
--   BAT1                       BAT2
--   Fuel flow and fuel remaining
--
-- Arc segments are rendered as overlapping rotated rectangles.
-- The rectangles are filled in software, avoiding gaps and heavy
-- pixelation from individual radial lines.

local function name()
    return "AES-II"
end

------------------------------------------------------------
-- COLORS
------------------------------------------------------------
local COL_BG       = lcd.RGB(8, 10, 14)
local COL_PANEL    = lcd.RGB(17, 21, 28)
local COL_BOX      = lcd.RGB(23, 28, 36)
local COL_BORDER   = lcd.RGB(54, 66, 78)
local COL_DIM      = lcd.RGB(42, 49, 58)

local COL_TEXT     = lcd.RGB(245, 247, 250)
local COL_LABEL    = lcd.RGB(155, 172, 186)
local COL_WHITE    = lcd.RGB(255, 255, 255)

local COL_CYAN     = lcd.RGB(0, 190, 225)
local COL_GREEN    = lcd.RGB(20, 220, 115)
local COL_YELLOW   = lcd.RGB(255, 210, 0)
local COL_RED      = lcd.RGB(250, 55, 55)

local FONT_SMALL = SMLSIZE or 0
local FONT_RPM = DBLSIZE or MIDSIZE or 0

local ARC_BITMAP_SIZE = 216
local ARC_BITMAP_CENTER_X = 108
local ARC_BITMAP_CENTER_Y = 127
local RPM_BITMAP_W = 205
local RPM_BITMAP_H = 90
local FUEL_BITMAP_W = 210
local FUEL_BITMAP_H = 70
local arcTempBitmap = nil
local arcBattBitmap = nil
local fuelBaseBitmap = nil
local labelBitmaps = {}
local spriteFontBitmaps = {}
local arcBitmapLoadAttempted = false
local bitmapDrawMethod = nil

------------------------------------------------------------
-- UPDATE TIMER
------------------------------------------------------------
local lastTime = 0
local INTERVAL = 100

------------------------------------------------------------
-- HELPERS
------------------------------------------------------------
local function round(v)
    if v >= 0 then
        return math.floor(v + 0.5)
    end

    return math.ceil(v - 0.5)
end

local function clamp(v, lo, hi)
    if v < lo then return lo end
    if v > hi then return hi end
    return v
end

local function valuePercent(value, minValue, maxValue)
    if value == nil then return 0 end
    if maxValue == minValue then return 0 end

    return clamp(
        (value - minValue) / (maxValue - minValue),
        0,
        1
    )
end

local function thresholdPercent(threshold, minValue, maxValue)
    return valuePercent(threshold, minValue, maxValue)
end

local function tryLoadBitmap(path)
    if type(lcd.loadBitmap) == "function" then
        local ok, loaded = pcall(lcd.loadBitmap, path)

        if ok and loaded ~= nil then
            return loaded
        end
    end

    if type(Bitmap) == "table" and
        type(Bitmap.open) == "function" then
        local ok, loaded = pcall(Bitmap.open, path)

        if ok and loaded ~= nil then
            return loaded
        end
    end

    if _G ~= nil and type(_G.bitmap) == "table" and
        type(_G.bitmap.open) == "function" then
        local ok, loaded = pcall(_G.bitmap.open, path)

        if ok and loaded ~= nil then
            return loaded
        end
    end

    return nil
end

local function loadArcBitmaps()
    if arcBitmapLoadAttempted then
        return
    end

    arcBitmapLoadAttempted = true

    local tempPaths = {
        "images/arc_temp.png",
        "scripts/aesii/images/arc_temp.png",
        "/scripts/aesii/images/arc_temp.png",
        "arc_temp.png",
        "scripts/aesii/arc_temp.png",
        "/scripts/aesii/arc_temp.png",
        "scripts/aestemp/arc_temp.png",
        "/scripts/aestemp/arc_temp.png",
        "scripts/aescht2/arc_temp.png",
        "/scripts/aescht2/arc_temp.png"
    }

    local battPaths = {
        "images/arc_batt.png",
        "scripts/aesii/images/arc_batt.png",
        "/scripts/aesii/images/arc_batt.png",
        "arc_batt.png",
        "scripts/aesii/arc_batt.png",
        "/scripts/aesii/arc_batt.png",
        "scripts/aesbatt/arc_batt.png",
        "/scripts/aesbatt/arc_batt.png",
        "scripts/aesbat2/arc_batt.png",
        "/scripts/aesbat2/arc_batt.png"
    }

    local fuelPaths = {
        "images/fuel_base.png",
        "scripts/aesii/images/fuel_base.png",
        "/scripts/aesii/images/fuel_base.png",
        "fuel_base.png",
        "scripts/aesii/fuel_base.png",
        "/scripts/aesii/fuel_base.png",
        "scripts/aesfuel/fuel_base.png",
        "/scripts/aesfuel/fuel_base.png"
    }

    for _, path in ipairs(tempPaths) do
        arcTempBitmap = tryLoadBitmap(path)

        if arcTempBitmap ~= nil then
            break
        end
    end

    for _, path in ipairs(battPaths) do
        arcBattBitmap = tryLoadBitmap(path)

        if arcBattBitmap ~= nil then
            break
        end
    end

    for _, path in ipairs(fuelPaths) do
        fuelBaseBitmap = tryLoadBitmap(path)

        if fuelBaseBitmap ~= nil then
            break
        end
    end
end

local function drawBitmapAt(bitmapValue, x, y)
    if bitmapValue == nil then
        return false
    end

    if bitmapDrawMethod == 1 then
        lcd.drawBitmap(bitmapValue, x, y)
        return true
    elseif bitmapDrawMethod == 2 then
        lcd.drawBitmap(x, y, bitmapValue)
        return true
    elseif bitmapDrawMethod == 3 then
        lcd.drawImage(x, y, bitmapValue)
        return true
    elseif bitmapDrawMethod == 4 then
        bitmapValue:draw(x, y)
        return true
    end

    if type(lcd.drawBitmap) == "function" then
        local ok = pcall(lcd.drawBitmap, bitmapValue, x, y)

        if ok then
            bitmapDrawMethod = 1
            return true
        end

        ok = pcall(lcd.drawBitmap, x, y, bitmapValue)

        if ok then
            bitmapDrawMethod = 2
            return true
        end
    end

    if type(lcd.drawImage) == "function" then
        local ok = pcall(lcd.drawImage, x, y, bitmapValue)

        if ok then
            bitmapDrawMethod = 3
            return true
        end
    end

    if type(bitmapValue) == "table" and
        type(bitmapValue.draw) == "function" then
        local ok = pcall(function()
            bitmapValue:draw(x, y)
        end)

        if ok then
            bitmapDrawMethod = 4
            return true
        end
    end

    return false
end

local function loadLabelBitmap(name)
    if labelBitmaps[name] ~= nil then
        if labelBitmaps[name] == false then
            return nil
        end

        return labelBitmaps[name]
    end

    local filename = "label_" .. name .. ".png"
    local paths = {
        "images/" .. filename,
        "scripts/aesii/images/" .. filename,
        "/scripts/aesii/images/" .. filename,
        filename,
        "scripts/aesii/" .. filename,
        "/scripts/aesii/" .. filename
    }

    for _, path in ipairs(paths) do
        local loaded = tryLoadBitmap(path)

        if loaded ~= nil then
            labelBitmaps[name] = loaded
            return loaded
        end
    end

    labelBitmaps[name] = false
    return nil
end

local LABEL_SIZES = {
    rpm = {w = 35, h = 20},
    ff_ml_min = {w = 107, h = 20},
    fuel_ml = {w = 83, h = 20},
    ign_label = {w = 35, h = 20},
    ign_green = {w = 35, h = 20},
    off_label = {w = 35, h = 20},
    gyro_yellow = {w = 47, h = 20},
    stab_green = {w = 47, h = 20}
}

local function drawLabelBitmap(name, x, y, align)
    local bitmapValue = loadLabelBitmap(name)

    if bitmapValue == nil then
        return false
    end

    local spec = LABEL_SIZES[name]
    local drawX = round(x)

    if spec ~= nil then
        if align == "right" or (RIGHT ~= nil and align == RIGHT) then
            drawX = drawX - spec.w
        elseif align == "center" or (CENTER ~= nil and align == CENTER) then
            drawX = drawX - math.floor(spec.w / 2)
        end
    end

    return drawBitmapAt(bitmapValue, drawX, round(y))
end

local function drawArcBitmap(bitmapValue, centerX, centerY)
    return drawBitmapAt(
        bitmapValue,
        round(centerX - ARC_BITMAP_CENTER_X),
        round(centerY - ARC_BITMAP_CENTER_Y)
    )
end

local FONT_SPRITES = {
    small = {w = 11, h = 20},
    value = {w = 17, h = 28},
    rpm = {w = 20, h = 35}
}

local function colorStyle(color)
    if color == COL_GREEN then return "green" end
    if color == COL_YELLOW then return "yellow" end
    if color == COL_RED then return "red" end
    if color == COL_WHITE then return "white" end

    return "label"
end

local function glyphName(sizeName, styleName, char)
    return string.format(
        "font_%s_%s_%04x.png",
        sizeName,
        styleName,
        string.byte(char)
    )
end

local function loadGlyph(sizeName, styleName, char)
    if char == " " then
        return true
    end

    local name = glyphName(sizeName, styleName, char)
    local cacheKey = sizeName .. "|" .. styleName .. "|" .. char

    if spriteFontBitmaps[cacheKey] ~= nil then
        if spriteFontBitmaps[cacheKey] == false then
            return nil
        end

        return spriteFontBitmaps[cacheKey]
    end

    local paths = {
        "images/" .. name,
        "scripts/aesii/images/" .. name,
        "/scripts/aesii/images/" .. name,
        name,
        "scripts/aesii/" .. name,
        "/scripts/aesii/" .. name
    }

    for _, path in ipairs(paths) do
        local loaded = tryLoadBitmap(path)

        if loaded ~= nil then
            spriteFontBitmaps[cacheKey] = loaded
            return loaded
        end
    end

    spriteFontBitmaps[cacheKey] = false
    return nil
end

local function spriteTextWidth(sizeName, text)
    local spec = FONT_SPRITES[sizeName]

    if spec == nil then
        return 0
    end

    return #text * spec.w
end

local function drawSpriteText(sizeName, x, y, text, color, align)
    local spec = FONT_SPRITES[sizeName]

    if spec == nil or text == nil then
        return false
    end

    local styleName = colorStyle(color or COL_LABEL)

    for i = 1, #text do
        local char = string.sub(text, i, i)

        if loadGlyph(sizeName, styleName, char) == nil then
            return false
        end
    end

    local drawX = round(x)
    local width = spriteTextWidth(sizeName, text)

    if align == "right" or (RIGHT ~= nil and align == RIGHT) then
        drawX = drawX - width
    elseif align == "center" or (CENTER ~= nil and align == CENTER) then
        drawX = drawX - math.floor(width / 2)
    end

    for i = 1, #text do
        local char = string.sub(text, i, i)
        local glyph = loadGlyph(sizeName, styleName, char)

        if glyph ~= true then
            drawBitmapAt(glyph, drawX, round(y))
        end

        drawX = drawX + spec.w
    end

    return true
end

local function getVal(source)
    if source == nil then return nil end

    local ok, value = pcall(function()
        return source:value()
    end)

    if ok and value ~= nil then
        return value
    end

    return nil
end

local function zoneColor(position, zones)
    if zones ~= nil then
        for _, zone in ipairs(zones) do
            if position >= zone[1] and position <= zone[2] then
                return zone[3]
            end
        end
    end

    return COL_GREEN
end

local function formatValue(value, decimals, unit)
    if value == nil then
        return "---"
    end

    local formatString = "%." .. tostring(decimals or 0) .. "f"
    local text = string.format(formatString, value)

    if unit ~= nil then
        text = text .. unit
    end

    return text
end

local function formattedTelemetryKey(widget)
    local cht1Min = widget.t1_min or 10
    local cht1Max = widget.t1_max or 150
    local cht2Min = widget.t2_min or 10
    local cht2Max = widget.t2_max or 150
    local bat1Min = widget.v1_min or 6.0
    local bat1Max = widget.v1_max or 8.4
    local bat2Min = widget.v2_min or 6.0
    local bat2Max = widget.v2_max or 8.4
    local rpmMax = widget.rpm_max or 8500
    local flowMax = widget.ff_max or 100
    local fuelCapacity = widget.fuel_cap or 1000

    if cht1Min == 0 then
        cht1Min = 10
    end

    if cht2Min == 0 then
        cht2Min = 10
    end

    local cht1 = getVal(widget.temp1)
    local cht2 = getVal(widget.temp2)
    local bat1 = getVal(widget.volt1)
    local bat2 = getVal(widget.volt2)
    local rpm = getVal(widget.rpm)
    local fuelFlow = getVal(widget.fuel_flow)
    local fuelRemaining = getVal(widget.fuel_remaining)
    local ignitionEnabled = getVal(widget.ignition)
    local modeState = getVal(widget.mode_state)

    return table.concat({
        widget.kind or "dashboard",
        widget.cht1_label or "CHT1",
        widget.cht2_label or "CHT2",
        widget.bat1_label or "BAT1",
        widget.bat2_label or "BAT2",
        formatValue(cht1, 0, "C"),
        formatValue(cht2, 0, "C"),
        formatValue(bat1, 2, "V"),
        formatValue(bat2, 2, "V"),
        rpm == nil and "---" or string.format("%d", round(rpm)),
        formatValue(fuelFlow, 1, nil),
        formatValue(fuelRemaining, 0, nil),
        formatValue(cht1Min, 0, nil),
        formatValue(cht1Max, 0, nil),
        formatValue(cht2Min, 0, nil),
        formatValue(cht2Max, 0, nil),
        formatValue(bat1Min, 2, nil),
        formatValue(bat1Max, 2, nil),
        formatValue(bat2Min, 2, nil),
        formatValue(bat2Max, 2, nil),
        formatValue(rpmMax, 0, nil),
        formatValue(flowMax, 1, nil),
        formatValue(fuelCapacity, 0, nil),
        ignitionEnabled ~= nil and ignitionEnabled > 0 and "IGN1" or "IGN0",
        modeState == nil and "MODnil" or string.format("MOD%d", round(modeState))
    }, "|")
end

local function centeredText(x, y, text, color)
    if drawSpriteText("small", x, y, text, color or COL_TEXT, "center") then
        return
    end

    lcd.color(color or COL_TEXT)
    if CENTER ~= nil then
        lcd.drawText(round(x), round(y), text, CENTER)
    else
        lcd.drawText(round(x - (#text * 3)), round(y), text)
    end
end

local function fuelLabelBitmapName(label)
    if label == "FF ML/MIN" then
        return "ff_ml_min"
    elseif label == "FUEL ML" then
        return "fuel_ml"
    end

    return nil
end

local function annunciatorLabelBitmapName(label, activeColor, active)
    if label == "IGN" then
        if active and activeColor == COL_GREEN then
            return "ign_green"
        end

        return "ign_label"
    elseif label == "OFF" then
        return "off_label"
    elseif label == "GYRO" and active and activeColor == COL_YELLOW then
        return "gyro_yellow"
    elseif label == "STAB" and active and activeColor == COL_GREEN then
        return "stab_green"
    end

    return nil
end

local TINY_DIGITS = {
    ["0"] = {"111", "101", "101", "101", "111"},
    ["1"] = {"010", "110", "010", "010", "111"},
    ["2"] = {"111", "001", "111", "100", "111"},
    ["3"] = {"111", "001", "111", "001", "111"},
    ["4"] = {"101", "101", "111", "001", "001"},
    ["5"] = {"111", "100", "111", "001", "111"},
    ["6"] = {"111", "100", "111", "101", "111"},
    ["7"] = {"111", "001", "010", "010", "010"},
    ["8"] = {"111", "101", "111", "101", "111"},
    ["9"] = {"111", "101", "111", "001", "111"},
    ["."] = {"000", "000", "000", "000", "010"},
    ["-"] = {"000", "000", "111", "000", "000"}
}

local function tinyTextWidth(text, scale)
    local width = 0

    for i = 1, #text do
        local char = string.sub(text, i, i)

        if TINY_DIGITS[char] ~= nil then
            width = width + 4 * scale
        end
    end

    if width > 0 then
        width = width - scale
    end

    return width
end

local function drawTinyText(x, y, text, color, flags)
    local align = nil

    if RIGHT ~= nil and flags == RIGHT then
        align = "right"
    elseif CENTER ~= nil and flags == CENTER then
        align = "center"
    end

    if drawSpriteText("small", x, y, text, color or COL_LABEL, align) then
        return
    end

    local drawX = round(x)
    local charWidth = 6

    if FONT_SMALL == 0 then
        charWidth = 7
    end

    local width = #text * charWidth

    if RIGHT ~= nil and flags == RIGHT then
        drawX = drawX - width
    elseif CENTER ~= nil and flags == CENTER then
        drawX = drawX - math.floor(width / 2)
    end

    lcd.color(color or COL_LABEL)

    if FONT_SMALL ~= 0 then
        lcd.drawText(drawX, round(y), text, FONT_SMALL)
    else
        lcd.drawText(drawX, round(y), text)
    end
end

local function drawNativeText(x, y, text, color, font, align)
    local drawX = round(x)

    lcd.color(color or COL_TEXT)

    if align == "right" or (RIGHT ~= nil and align == RIGHT) then
        if RIGHT ~= nil then
            lcd.drawText(drawX, round(y), text, (font or 0) + RIGHT)
        else
            lcd.drawText(drawX - (#text * 8), round(y), text, font or 0)
        end
    elseif align == "center" or (CENTER ~= nil and align == CENTER) then
        if CENTER ~= nil then
            lcd.drawText(drawX, round(y), text, (font or 0) + CENTER)
        else
            lcd.drawText(drawX - math.floor(#text * 4), round(y), text, font or 0)
        end
    else
        lcd.drawText(drawX, round(y), text, font or 0)
    end
end

local function drawNativeValue(x, y, text, color, align)
    drawNativeText(x, y, text, color, MIDSIZE or FONT_SMALL, align)
end

local function drawRpmValue(x, y, text, color)
    drawNativeText(x, y, text, color or COL_TEXT, FONT_RPM, "center")
end

------------------------------------------------------------
-- PANEL BOX
------------------------------------------------------------
local function drawBox(x, y, w, h)
    lcd.color(COL_BOX)
    lcd.drawFilledRectangle(
        round(x),
        round(y),
        round(w),
        round(h)
    )

    lcd.color(COL_BORDER)
    lcd.drawRectangle(
        round(x),
        round(y),
        round(w),
        round(h)
    )
end

------------------------------------------------------------
-- SOFTWARE-FILLED TRIANGLE
--
-- This avoids depending on lcd.drawFilledTriangle().
------------------------------------------------------------
local function fillTriangle(x1, y1, x2, y2, x3, y3, color)
    x1 = round(x1)
    y1 = round(y1)
    x2 = round(x2)
    y2 = round(y2)
    x3 = round(x3)
    y3 = round(y3)

    -- Sort vertices by Y.
    if y1 > y2 then
        x1, x2 = x2, x1
        y1, y2 = y2, y1
    end

    if y2 > y3 then
        x2, x3 = x3, x2
        y2, y3 = y3, y2
    end

    if y1 > y2 then
        x1, x2 = x2, x1
        y1, y2 = y2, y1
    end

    if y1 == y3 then
        return
    end

    lcd.color(color)

    for y = y1, y3 do
        local xa
        local xb

        local fullHeight = y3 - y1
        local fullRatio = 0

        if fullHeight ~= 0 then
            fullRatio = (y - y1) / fullHeight
        end

        xa = x1 + (x3 - x1) * fullRatio

        if y < y2 then
            local upperHeight = y2 - y1
            local upperRatio = 0

            if upperHeight ~= 0 then
                upperRatio = (y - y1) / upperHeight
            end

            xb = x1 + (x2 - x1) * upperRatio
        else
            local lowerHeight = y3 - y2
            local lowerRatio = 0

            if lowerHeight ~= 0 then
                lowerRatio = (y - y2) / lowerHeight
            end

            xb = x2 + (x3 - x2) * lowerRatio
        end

        if xa > xb then
            xa, xb = xb, xa
        end

        lcd.drawLine(
            round(xa),
            y,
            round(xb),
            y
        )
    end
end

------------------------------------------------------------
-- FILLED ROTATED RECTANGLE
------------------------------------------------------------
local function drawRotatedRectangle(
    centerX,
    centerY,
    length,
    thickness,
    angleRadians,
    color
)
    local cosA = math.cos(angleRadians)
    local sinA = math.sin(angleRadians)

    local halfLength = length / 2
    local halfThickness = thickness / 2

    -- Rectangle length follows the tangent.
    local tx = cosA * halfLength
    local ty = sinA * halfLength

    -- Rectangle thickness follows the radial normal.
    local nx = -sinA * halfThickness
    local ny = cosA * halfThickness

    local x1 = centerX - tx - nx
    local y1 = centerY - ty - ny

    local x2 = centerX + tx - nx
    local y2 = centerY + ty - ny

    local x3 = centerX + tx + nx
    local y3 = centerY + ty + ny

    local x4 = centerX - tx + nx
    local y4 = centerY - ty + ny

    fillTriangle(x1, y1, x2, y2, x3, y3, color)
    fillTriangle(x1, y1, x3, y3, x4, y4, color)
end

------------------------------------------------------------
-- ARC SEGMENT
--
-- A short rotated rectangle tangent to the arc.
------------------------------------------------------------
local function drawArcSegment(
    centerX,
    centerY,
    radius,
    angleDegrees,
    segmentAngle,
    thickness,
    color
)
    lcd.color(color)

    local startRadians = math.rad(angleDegrees)
    local endRadians = math.rad(angleDegrees + segmentAngle + 4)
    local innerRadius = radius - thickness

    for segmentRadius = innerRadius, radius, 2 do
        lcd.drawLine(
            round(centerX + math.cos(startRadians) * segmentRadius),
            round(centerY + math.sin(startRadians) * segmentRadius),
            round(centerX + math.cos(endRadians) * segmentRadius),
            round(centerY + math.sin(endRadians) * segmentRadius)
        )
    end
end

-- GARMIN-STYLE ARC GAUGE
------------------------------------------------------------
local function semiGauge(
    centerX,
    centerY,
    radius,
    value,
    minValue,
    maxValue,
    label,
    unit,
    decimals,
    zones,
    labelY,
    valueY,
    arcBitmap
)
    local position = valuePercent(value, minValue, maxValue)

    local startAngle = 180
    local endAngle = 300
    local sweep = endAngle - startAngle

    local thickness = math.floor(
        clamp(radius * 0.19, 10, 13)
    )

    local segmentStep = 2

    --------------------------------------------------------
    -- Range arc
    --------------------------------------------------------
    if radius < 72 or not drawArcBitmap(arcBitmap, centerX, centerY) then
        for angle = startAngle, endAngle, segmentStep do
            local segmentPosition =
                (angle - startAngle) / sweep

            drawArcSegment(
                centerX,
                centerY,
                radius,
                angle,
                segmentStep,
                thickness,
                zoneColor(segmentPosition, zones)
            )
        end
    end

    --------------------------------------------------------
    -- End markers and small numeric limits
    --------------------------------------------------------
    for _, tickPosition in ipairs({0, 1}) do
        local tickAngle = math.rad(
            startAngle + sweep * tickPosition
        )

        local outerRadius = radius + 4
        local innerRadius = radius - thickness - 7

        lcd.color(COL_WHITE)
        lcd.drawLine(
            round(centerX + math.cos(tickAngle) * outerRadius),
            round(centerY + math.sin(tickAngle) * outerRadius),
            round(centerX + math.cos(tickAngle) * innerRadius),
            round(centerY + math.sin(tickAngle) * innerRadius)
        )
    end

    local minLabelAngle = math.rad(startAngle)
    local minLabelRadius = radius - thickness - 1

    drawTinyText(
        round(centerX + math.cos(minLabelAngle) * minLabelRadius - 3),
        round(centerY + math.sin(minLabelAngle) * minLabelRadius + 9),
        formatValue(minValue, decimals, nil),
        COL_LABEL
    )

    local maxLabelAngle = math.rad(endAngle)
    local maxLabelRadius = radius - thickness - 2

    drawTinyText(
        round(centerX + math.cos(maxLabelAngle) * maxLabelRadius + 18),
        round(centerY + math.sin(maxLabelAngle) * maxLabelRadius + 8),
        formatValue(maxValue, decimals, nil),
        COL_LABEL,
        RIGHT
    )

    --------------------------------------------------------
    -- Pointer
    --------------------------------------------------------
    local pointerAngle = math.rad(
        startAngle + sweep * position
    )

    local tipRadius = radius - math.floor(thickness / 2)
    local baseRadius = tipRadius - math.floor(radius * 0.23)
    local needleHalfWidth = math.floor(
        clamp(radius * 0.11, 8, 12)
    )

    local tipX =
        centerX + math.cos(pointerAngle) * tipRadius

    local tipY =
        centerY + math.sin(pointerAngle) * tipRadius

    local baseCenterX =
        centerX + math.cos(pointerAngle) * baseRadius

    local baseCenterY =
        centerY + math.sin(pointerAngle) * baseRadius

    local normalX = -math.sin(pointerAngle)
    local normalY = math.cos(pointerAngle)

    local baseAX =
        baseCenterX + normalX * needleHalfWidth

    local baseAY =
        baseCenterY + normalY * needleHalfWidth

    local baseBX =
        baseCenterX - normalX * needleHalfWidth

    local baseBY =
        baseCenterY - normalY * needleHalfWidth

    if value ~= nil then
        fillTriangle(
            tipX,
            tipY,
            baseAX,
            baseAY,
            baseBX,
            baseBY,
            COL_WHITE
        )
    end

    --------------------------------------------------------
    -- Value readout
    --------------------------------------------------------
    local valueColor

    if value == nil then
        valueColor = COL_RED
    else
        valueColor = zoneColor(position, zones)
    end

    local valueText = formatValue(value, decimals, unit)
    local valueX = centerX + radius * 0.06
    local labelX = centerX + radius * 0.11
    local valueDrawY = valueY or centerY + 12

    drawNativeValue(
        valueX,
        valueDrawY + 1,
        valueText,
        valueColor,
        "center"
    )

    if not drawSpriteText(
        "small",
        labelX,
        labelY or centerY + 31,
        label,
        COL_LABEL,
        "center"
    ) then
        lcd.color(COL_LABEL)
        if CENTER ~= nil then
            lcd.drawText(
                round(labelX),
                round(labelY or centerY + 31),
                label,
                CENTER
            )
        else
            lcd.drawText(
                round(labelX - (#label * 3)),
                round(labelY or centerY + 31),
                label
            )
        end
    end
end

------------------------------------------------------------
-- LARGE BOXED RPM DISPLAY
------------------------------------------------------------
local function rpmBox(x, y, w, h, rpm, maxRpm)
    local position = valuePercent(rpm, 0, maxRpm)

    local valueColor = COL_RED

    if rpm == nil then
        valueColor = COL_RED
    elseif position >= 0.90 then
        valueColor = COL_RED
    elseif position >= 0.80 then
        valueColor = COL_RED
    end

    lcd.color(COL_BG)
    lcd.drawFilledRectangle(
        round(x + 15),
        round(y + 25),
        round(w - 30),
        39
    )

    lcd.color(COL_DIM)
    lcd.drawRectangle(
        round(x + 15),
        round(y + 25),
        round(w - 30),
        39
    )

    if not drawLabelBitmap("rpm", x + w / 2, y + 7, "center") then
        centeredText(
            x + w / 2,
            y + 7,
            "RPM",
            COL_LABEL
        )
    end

    local rpmText = "---"

    if rpm ~= nil then
        rpmText = string.format("%d", rpm)
    end

    drawRpmValue(
        x + w / 2,
        y + 28,
        rpmText,
        valueColor
    )

    --------------------------------------------------------
    -- RPM load bar
    --------------------------------------------------------
    local barX = x + 16
    local barY = y + h - 16
    local barW = w - 32
    local idlePosition = valuePercent(1200, 0, maxRpm)
    local idleX = barX + barW * idlePosition
    local markerX = barX + barW * position

    lcd.color(COL_WHITE)
    lcd.drawLine(
        round(barX),
        round(barY),
        round(barX + barW),
        round(barY)
    )

    lcd.color(COL_GREEN)
    lcd.drawFilledRectangle(
        round(idleX - 1),
        round(barY - 7),
        3,
        14
    )

    if rpm ~= nil then
        lcd.color(valueColor)
        lcd.drawFilledRectangle(
            round(markerX - 2),
            round(barY - 9),
            4,
            18
        )

        lcd.color(COL_WHITE)
        lcd.drawLine(
            round(markerX - 6),
            round(barY - 11),
            round(markerX + 6),
            round(barY - 11)
        )
    end
end

------------------------------------------------------------
-- SEGMENTED HORIZONTAL BAR
------------------------------------------------------------
local function barGauge(
    x,
    y,
    w,
    label,
    value,
    minValue,
    maxValue,
    unit,
    decimals,
    zones
)
    local labelWidth = 52
    local valueWidth = 88

    local barX = x + labelWidth
    local barWidth = w - labelWidth - valueWidth - 8
    local barHeight = 12

    local position = valuePercent(
        value,
        minValue,
        maxValue
    )

    local valueColor

    if value == nil then
        valueColor = COL_RED
    else
        valueColor = zoneColor(position, zones)
    end

    lcd.color(COL_LABEL)
    lcd.drawText(
        round(x),
        round(y - 1),
        label
    )

    lcd.color(COL_DIM)
    lcd.drawFilledRectangle(
        round(barX),
        round(y),
        round(barWidth),
        barHeight
    )

    local segmentCount = 18
    local gap = 2

    local segmentWidth = math.floor(
        (
            barWidth -
            ((segmentCount - 1) * gap)
        ) / segmentCount
    )

    local activeSegments = math.floor(
        segmentCount * position + 0.5
    )

    for i = 0, segmentCount - 1 do
        local segmentX =
            barX + i * (segmentWidth + gap)

        if value ~= nil and i < activeSegments then
            local segmentPosition =
                (i + 0.5) / segmentCount

            lcd.color(
                zoneColor(segmentPosition, zones)
            )
        else
            lcd.color(COL_DIM)
        end

        lcd.drawFilledRectangle(
            round(segmentX),
            round(y),
            segmentWidth,
            barHeight
        )
    end

    lcd.color(COL_BORDER)
    lcd.drawRectangle(
        round(barX),
        round(y),
        round(barWidth),
        barHeight
    )

    lcd.color(valueColor)
    lcd.drawText(
        round(x + w),
        round(y - 1),
        formatValue(value, decimals, unit),
        RIGHT
    )
end

------------------------------------------------------------
-- COMPACT AVIONICS-STYLE FUEL STRIP
------------------------------------------------------------
local function fuelStrip(
    x,
    y,
    w,
    label,
    value,
    minValue,
    maxValue,
    unit,
    decimals,
    zones
)
    local position = valuePercent(
        value,
        minValue,
        maxValue
    )

    local valueColor

    if value == nil then
        valueColor = COL_RED
    else
        valueColor = zoneColor(position, zones)
    end

    local baseDrawn = drawBitmapAt(
        fuelBaseBitmap,
        round(x),
        round(y)
    )

    if not baseDrawn then
        lcd.color(COL_WHITE)
        lcd.drawLine(
            round(x + 10),
            round(y + 43),
            round(x + 140),
            round(y + 43)
        )
    end

    local labelBitmapName = fuelLabelBitmapName(label)

    if not (
        labelBitmapName ~= nil and
        drawLabelBitmap(labelBitmapName, x + 4, y + 4)
    ) and not drawSpriteText(
            "small",
            x + 4,
            y + 4,
            label,
            COL_LABEL
        ) then
        lcd.color(COL_LABEL)
        lcd.drawText(
            round(x + 4),
            round(y + 4),
            label
        )
    end

    local stripValueText = formatValue(value, decimals, unit)

    drawNativeValue(
        x + w - 6,
        y + 5,
        stripValueText,
        valueColor,
        "right"
    )

    local lineY = y + 43
    local lineX = x + 10
    local lineW = 130
    local markerX = lineX + lineW * position

    lcd.color(valueColor)
    lcd.drawFilledRectangle(
        round(markerX - 2),
        round(lineY - 10),
        4,
        20
    )

    lcd.color(COL_WHITE)
    lcd.drawLine(
        round(markerX - 7),
        round(lineY - 12),
        round(markerX + 7),
        round(lineY - 12)
    )

    if not drawSpriteText(
        "small",
        x + w - 8,
        y + 35,
        formatValue(maxValue, decimals, unit),
        COL_WHITE,
        "right"
    ) then
        local maxText = formatValue(maxValue, decimals, unit)

        if RIGHT ~= nil then
            lcd.drawText(
                round(x + w - 8),
                round(y + 35),
                maxText,
                RIGHT
            )
        else
            lcd.drawText(
                round(x + w - 8 - (#maxText * 6)),
                round(y + 35),
                maxText
            )
        end
    end

end

local function annunciatorLamp(x, y, w, label, activeColor, active, stateText)
    local bodyColor = lcd.RGB(14, 18, 24)
    local borderColor = lcd.RGB(36, 42, 50)
    local lampBezel = lcd.RGB(26, 31, 38)
    local lampColor = active and activeColor or lcd.RGB(52, 58, 64)
    local lampGlow = active and lcd.RGB(10, 42, 24) or lcd.RGB(18, 20, 24)
    local labelColor = active and activeColor or COL_LABEL

    lcd.color(bodyColor)
    lcd.drawFilledRectangle(
        round(x),
        round(y),
        round(w),
        26
    )

    lcd.color(borderColor)
    lcd.drawRectangle(round(x), round(y), round(w), 26)

    lcd.color(lampGlow)
    lcd.drawFilledRectangle(
        round(x + 8),
        round(y + 5),
        16,
        16
    )

    lcd.color(lampBezel)
    lcd.drawFilledRectangle(
        round(x + 10),
        round(y + 7),
        12,
        12
    )

    lcd.color(lampColor)
    lcd.drawFilledRectangle(
        round(x + 12),
        round(y + 9),
        8,
        8
    )

    local labelBitmapName =
        annunciatorLabelBitmapName(label, activeColor, active)

    if not (
        labelBitmapName ~= nil and
        drawLabelBitmap(labelBitmapName, x + 38, y + 3)
    ) and not drawSpriteText(
            "small",
            x + 38,
            y + 3,
            label,
            labelColor
        ) then
        lcd.color(labelColor)
        lcd.drawText(round(x + 38), round(y + 5), label)
    end

    if stateText ~= nil then
        if not drawSpriteText(
            "small",
            x + w - 10,
            y + 3,
            stateText,
            labelColor,
            "right"
        ) then
            lcd.color(labelColor)
            if RIGHT ~= nil then
                lcd.drawText(round(x + w - 10), round(y + 5), stateText, RIGHT)
            else
                lcd.drawText(round(x + w - 10 - (#stateText * 6)), round(y + 5), stateText)
            end
        end
    end
end

local function ignitionAnnunciator(x, y, w, enabled)
    annunciatorLamp(
        x,
        y,
        w,
        "IGN",
        COL_GREEN,
        enabled ~= nil and enabled > 0,
        nil
    )
end

local function modeAnnunciator(x, y, w, modeValue)
    local mode = 0

    if modeValue ~= nil then
        mode = round(modeValue)
    end

    local active = mode >= 0
    local stateText = "OFF"
    local activeColor = COL_LABEL

    if mode >= 100 then
        stateText = "STAB"
        activeColor = COL_GREEN
    elseif mode >= 0 then
        stateText = "GYRO"
        activeColor = COL_YELLOW
    end

    annunciatorLamp(
        x,
        y,
        w,
        stateText,
        activeColor,
        active,
        nil
    )
end

------------------------------------------------------------
-- PAINT
------------------------------------------------------------
local function paint(widget)
    local w, h = lcd.getWindowSize()

    loadArcBitmaps()

    --------------------------------------------------------
    -- Telemetry
    --------------------------------------------------------
    local cht1 = getVal(widget.temp1)
    local cht2 = getVal(widget.temp2)

    local bat1 = getVal(widget.volt1)
    local bat2 = getVal(widget.volt2)

    local rpm = getVal(widget.rpm)

    local fuelFlow = getVal(widget.fuel_flow)
    local fuelRemaining = getVal(widget.fuel_remaining)
    local ignitionEnabled = getVal(widget.ignition)
    local modeState = getVal(widget.mode_state)

    --------------------------------------------------------
    -- Configuration
    --------------------------------------------------------
    local cht1Min = widget.t1_min or 10
    local cht1Max = widget.t1_max or 150

    local cht2Min = widget.t2_min or 10
    local cht2Max = widget.t2_max or 150

    if cht1Min == 0 then
        cht1Min = 10
    end

    if cht2Min == 0 then
        cht2Min = 10
    end

    local bat1Min = widget.v1_min or 6.0
    local bat1Max = widget.v1_max or 8.4

    local bat2Min = widget.v2_min or 6.0
    local bat2Max = widget.v2_max or 8.4

    local rpmMax = widget.rpm_max or 8500
    local flowMax = widget.ff_max or 100
    local fuelCapacity = widget.fuel_cap or 1000

    local cht1Label = widget.cht1_label or "CHT1"
    local cht2Label = widget.cht2_label or "CHT2"

    local bat1Label = widget.bat1_label or "BAT1"
    local bat2Label = widget.bat2_label or "BAT2"

    local cht1Yellow = thresholdPercent(90, cht1Min, cht1Max)
    local cht1Red = thresholdPercent(100, cht1Min, cht1Max)
    local cht2Yellow = thresholdPercent(90, cht2Min, cht2Max)
    local cht2Red = thresholdPercent(100, cht2Min, cht2Max)

    local bat1Red = thresholdPercent(7.2, bat1Min, bat1Max)
    local bat1Yellow = thresholdPercent(7.6, bat1Min, bat1Max)
    local bat2Red = thresholdPercent(7.2, bat2Min, bat2Max)
    local bat2Yellow = thresholdPercent(7.6, bat2Min, bat2Max)

    --------------------------------------------------------
    -- Background
    --------------------------------------------------------
    lcd.color(COL_BG)
    lcd.drawFilledRectangle(0, 0, w, h)

    lcd.color(COL_PANEL)
    lcd.drawFilledRectangle(2, 2, w - 4, h - 4)

    lcd.color(COL_BORDER)
    lcd.drawRectangle(2, 2, w - 4, h - 4)

    --------------------------------------------------------
    -- Main areas
    --------------------------------------------------------
    local mainPanelY = 6
    local mainPanelH = h - mainPanelY - 8

    drawBox(8, mainPanelY, w - 16, mainPanelH)

    --------------------------------------------------------
    -- Gauge geometry
    --------------------------------------------------------
    local sideX = math.floor(
        clamp(w * 0.15, 96, 128)
    )

    local leftX = sideX
    local rightX = w - sideX
    local chtLeftX = leftX - 4
    local chtRightX = rightX + 4

    local topY = mainPanelY + 58
    local chtY = topY + 36
    local bottomY = h - 50

    local radius = math.floor(
        clamp((bottomY - topY) / 2 + 22, 60, 88)
    )

    local topLabelY = topY - 4
    local topValueY = topY + 18
    local chtValueY = chtY + 1
    local chtLabelY = chtValueY + 23
    local bottomValueY = bottomY + 3
    local bottomLabelY = bottomValueY + 23

    --------------------------------------------------------
    -- Temperature gauges
    --------------------------------------------------------
    semiGauge(
        chtLeftX,
        chtY,
        radius,
        cht1,
        cht1Min,
        cht1Max,
        cht1Label,
        "C",
        0,
        {
            {0.00, cht1Yellow, COL_GREEN},
            {cht1Yellow, cht1Red, COL_YELLOW},
            {cht1Red, 1.00, COL_RED}
        },
        chtLabelY,
        chtValueY,
        arcTempBitmap
    )

    semiGauge(
        chtRightX,
        chtY,
        radius,
        cht2,
        cht2Min,
        cht2Max,
        cht2Label,
        "C",
        0,
        {
            {0.00, cht2Yellow, COL_GREEN},
            {cht2Yellow, cht2Red, COL_YELLOW},
            {cht2Red, 1.00, COL_RED}
        },
        chtLabelY,
        chtValueY,
        arcTempBitmap
    )

    --------------------------------------------------------
    -- Battery gauges
    --------------------------------------------------------
    semiGauge(
        leftX,
        bottomY,
        radius,
        bat1,
        bat1Min,
        bat1Max,
        bat1Label,
        "V",
        2,
        {
            {0.00, bat1Red, COL_RED},
            {bat1Red, bat1Yellow, COL_YELLOW},
            {bat1Yellow, 1.00, COL_GREEN}
        },
        bottomLabelY,
        bottomValueY,
        arcBattBitmap
    )

    semiGauge(
        rightX,
        bottomY,
        radius,
        bat2,
        bat2Min,
        bat2Max,
        bat2Label,
        "V",
        2,
        {
            {0.00, bat2Red, COL_RED},
            {bat2Red, bat2Yellow, COL_YELLOW},
            {bat2Yellow, 1.00, COL_GREEN}
        },
        bottomLabelY,
        bottomValueY,
        arcBattBitmap
    )

    --------------------------------------------------------
    -- RPM
    --------------------------------------------------------
    rpmBox(
        w / 2 - RPM_BITMAP_W / 2,
        topY - 48,
        RPM_BITMAP_W,
        RPM_BITMAP_H,
        rpm,
        rpmMax
    )

    --------------------------------------------------------
    -- Fuel section
    --------------------------------------------------------
    fuelStrip(
        w / 2 - FUEL_BITMAP_W / 2,
        topY + 54,
        FUEL_BITMAP_W,
        "FF ML/MIN",
        fuelFlow,
        0,
        flowMax,
        nil,
        1,
        {
            {0.00, 0.80, COL_GREEN},
            {0.80, 1.00, COL_YELLOW}
        }
    )

    fuelStrip(
        w / 2 - FUEL_BITMAP_W / 2,
        topY + 132,
        FUEL_BITMAP_W,
        "FUEL ML",
        fuelRemaining,
        0,
        fuelCapacity,
        nil,
        0,
        {
            {0.00, 0.15, COL_RED},
            {0.15, 0.30, COL_YELLOW},
            {0.30, 1.00, COL_GREEN}
        }
    )

    local annunciatorW = 102
    local annunciatorGap = 10
    local annunciatorY = topY + 210
    local annunciatorX =
        w / 2 - annunciatorW - annunciatorGap / 2

    ignitionAnnunciator(
        annunciatorX,
        annunciatorY,
        annunciatorW,
        ignitionEnabled
    )

    modeAnnunciator(
        annunciatorX + annunciatorW + annunciatorGap,
        annunciatorY,
        annunciatorW,
        modeState
    )
end

------------------------------------------------------------
-- DASHBOARD WIDGET PAINTERS
------------------------------------------------------------
local function preparePanel()
    local w, h = lcd.getWindowSize()

    loadArcBitmaps()

    lcd.color(COL_BG)
    lcd.drawFilledRectangle(0, 0, w, h)

    lcd.color(COL_PANEL)
    lcd.drawFilledRectangle(2, 2, w - 4, h - 4)

    lcd.color(COL_BORDER)
    lcd.drawRectangle(2, 2, w - 4, h - 4)

    return w, h
end

local function dashboardGaugeLayout(w, h)
    local radius = math.floor(
        clamp(math.min(w * 0.35, h * 0.72), 42, 77)
    )

    local cy = math.floor(h * 0.42)
    local valueY = math.floor(h * 0.58)
    local labelY = valueY + 17

    return radius, cy, valueY, labelY
end

local function paintTemperatureGauge(widget, gaugeIndex)
    local w, h = preparePanel()
    local radius, cy, valueY, labelY = dashboardGaugeLayout(w, h)

    local minValue = widget.t1_min or 10
    local maxValue = widget.t1_max or 150
    local source = widget.temp1
    local label = widget.cht1_label or "CHT1"

    if gaugeIndex == 2 then
        minValue = widget.t2_min or 10
        maxValue = widget.t2_max or 150
        source = widget.temp2
        label = widget.cht2_label or "CHT2"
    end

    if minValue == 0 then minValue = 10 end

    local yellow = thresholdPercent(90, minValue, maxValue)
    local red = thresholdPercent(100, minValue, maxValue)

    semiGauge(
        w * 0.50,
        cy,
        radius,
        getVal(source),
        minValue,
        maxValue,
        label,
        "C",
        0,
        {
            {0.00, yellow, COL_GREEN},
            {yellow, red, COL_YELLOW},
            {red, 1.00, COL_RED}
        },
        labelY,
        valueY,
        arcTempBitmap
    )
end

local function paintBatteryGauge(widget, gaugeIndex)
    local w, h = preparePanel()
    local radius, cy, valueY, labelY = dashboardGaugeLayout(w, h)

    local minValue = widget.v1_min or 6.0
    local maxValue = widget.v1_max or 8.4
    local source = widget.volt1
    local label = widget.bat1_label or "BAT1"

    if gaugeIndex == 2 then
        minValue = widget.v2_min or 6.0
        maxValue = widget.v2_max or 8.4
        source = widget.volt2
        label = widget.bat2_label or "BAT2"
    end

    local red = thresholdPercent(7.2, minValue, maxValue)
    local yellow = thresholdPercent(7.6, minValue, maxValue)

    semiGauge(
        w * 0.50,
        cy,
        radius,
        getVal(source),
        minValue,
        maxValue,
        label,
        "V",
        2,
        {
            {0.00, red, COL_RED},
            {red, yellow, COL_YELLOW},
            {yellow, 1.00, COL_GREEN}
        },
        labelY,
        valueY,
        arcBattBitmap
    )
end

local function paintRpm(widget)
    local w, h = preparePanel()
    local x = math.floor((w - RPM_BITMAP_W) / 2)
    local y = math.floor((h - RPM_BITMAP_H) / 2)

    rpmBox(
        x,
        y,
        RPM_BITMAP_W,
        RPM_BITMAP_H,
        getVal(widget.rpm),
        widget.rpm_max or 8500
    )
end

local function paintFuel(widget)
    local w, h = preparePanel()
    local x = math.floor((w - FUEL_BITMAP_W) / 2)
    local gap = 8
    local totalH = FUEL_BITMAP_H * 2 + gap
    local y = math.floor((h - totalH) / 2)

    fuelStrip(
        x,
        y,
        FUEL_BITMAP_W,
        "FF ML/MIN",
        getVal(widget.fuel_flow),
        0,
        widget.ff_max or 100,
        nil,
        1,
        {
            {0.00, 0.80, COL_GREEN},
            {0.80, 1.00, COL_YELLOW}
        }
    )

    fuelStrip(
        x,
        y + FUEL_BITMAP_H + gap,
        FUEL_BITMAP_W,
        "FUEL ML",
        getVal(widget.fuel_remaining),
        0,
        widget.fuel_cap or 1000,
        nil,
        0,
        {
            {0.00, 0.15, COL_RED},
            {0.15, 0.30, COL_YELLOW},
            {0.30, 1.00, COL_GREEN}
        }
    )
end

local function paintDashboard(widget)
    if widget.kind == "temp1" then
        paintTemperatureGauge(widget, 1)
    elseif widget.kind == "temp2" then
        paintTemperatureGauge(widget, 2)
    elseif widget.kind == "bat1" then
        paintBatteryGauge(widget, 1)
    elseif widget.kind == "bat2" then
        paintBatteryGauge(widget, 2)
    elseif widget.kind == "rpm" then
        paintRpm(widget)
    elseif widget.kind == "fuel" then
        paintFuel(widget)
    else
        paint(widget)
    end
end

------------------------------------------------------------
-- WAKEUP
------------------------------------------------------------
local function wakeup(widget)
    local now = os.clock() * 1000

    if now - lastTime < INTERVAL then
        return
    end

    lastTime = now

    local renderKey = formattedTelemetryKey(widget)

    if widget._lastRenderKey ~= renderKey then
        widget._lastRenderKey = renderKey
        lcd.invalidate()
    end
end

------------------------------------------------------------
-- CONFIGURATION
------------------------------------------------------------
local function configure(widget)
    local function bindSource(label, field)
        local line = form.addLine(label)

        form.addSourceField(
            line,
            nil,
            function()
                return widget[field]
            end,
            function(value)
                widget[field] = value
            end
        )
    end

    local function bindNumber(
        label,
        field,
        default,
        minimum,
        maximum,
        decimals
    )
        local line = form.addLine(label)

        form.addNumberField(
            line,
            nil,
            minimum,
            maximum,
            function()
                return widget[field] or default
            end,
            function(value)
                widget[field] = value
            end
        ):decimals(decimals or 0)
    end

    local function bindText(label, field, default)
        local line = form.addLine(label)

        form.addTextField(
            line,
            nil,
            function()
                return widget[field] or default
            end,
            function(value)
                widget[field] = value
            end
        )
    end

    local kind = widget.kind
    local showAll = kind == nil

    if showAll or kind == "temp1" then
    --------------------------------------------------------
    -- CHT 1
    --------------------------------------------------------
    form.addLine("-- CHT 1 --")

    bindText(
        "Label",
        "cht1_label",
        "CHT1"
    )

    bindSource(
        "Source",
        "temp1"
    )

    bindNumber(
        "Minimum",
        "t1_min",
        10,
        -50,
        500,
        0
    )

    bindNumber(
        "Maximum",
        "t1_max",
        150,
        -50,
        1000,
        0
    )
    end

    if showAll or kind == "temp2" then
    --------------------------------------------------------
    -- CHT 2
    --------------------------------------------------------
    form.addLine("-- CHT 2 --")

    bindText(
        "Label",
        "cht2_label",
        "CHT2"
    )

    bindSource(
        "Source",
        "temp2"
    )

    bindNumber(
        "Minimum",
        "t2_min",
        10,
        -50,
        500,
        0
    )

    bindNumber(
        "Maximum",
        "t2_max",
        150,
        -50,
        1000,
        0
    )
    end

    if showAll or kind == "bat1" then
    --------------------------------------------------------
    -- Battery 1
    --------------------------------------------------------
    form.addLine("-- Battery 1 --")

    bindText(
        "Label",
        "bat1_label",
        "BAT1"
    )

    bindSource(
        "Source",
        "volt1"
    )

    bindNumber(
        "Minimum",
        "v1_min",
        6.0,
        0,
        60,
        2
    )

    bindNumber(
        "Maximum",
        "v1_max",
        8.4,
        0,
        60,
        2
    )
    end

    if showAll or kind == "bat2" then
    --------------------------------------------------------
    -- Battery 2
    --------------------------------------------------------
    form.addLine("-- Battery 2 --")

    bindText(
        "Label",
        "bat2_label",
        "BAT2"
    )

    bindSource(
        "Source",
        "volt2"
    )

    bindNumber(
        "Minimum",
        "v2_min",
        6.0,
        0,
        60,
        2
    )

    bindNumber(
        "Maximum",
        "v2_max",
        8.4,
        0,
        60,
        2
    )
    end

    if showAll or kind == "rpm" then
    --------------------------------------------------------
    -- RPM
    --------------------------------------------------------
    form.addLine("-- RPM --")

    bindSource(
        "RPM Source",
        "rpm"
    )

    bindNumber(
        "RPM Maximum",
        "rpm_max",
        8500,
        0,
        30000,
        0
    )
    end

    if showAll or kind == "fuel" then
    --------------------------------------------------------
    -- Fuel
    --------------------------------------------------------
    form.addLine("-- Fuel --")

    bindSource(
        "Fuel Flow Source",
        "fuel_flow"
    )

    bindNumber(
        "Flow Maximum",
        "ff_max",
        100,
        0,
        500,
        1
    )

    bindSource(
        "Fuel Remaining Source",
        "fuel_remaining"
    )

    bindNumber(
        "Tank Capacity",
        "fuel_cap",
        1000,
        0,
        20000,
        0
    )
    end

    if showAll or kind == "annunciators" then
    --------------------------------------------------------
    -- Annunciators
    --------------------------------------------------------
    form.addLine("-- Annunciators --")

    bindSource(
        "Ignition Source",
        "ignition"
    )

    bindSource(
        "Mode Source",
        "mode_state"
    )
    end
end

------------------------------------------------------------
-- PERSISTENCE
------------------------------------------------------------
local PERSISTENT_FIELDS = {
    "kind",

    "cht1_label",
    "temp1",
    "t1_min",
    "t1_max",

    "cht2_label",
    "temp2",
    "t2_min",
    "t2_max",

    "bat1_label",
    "volt1",
    "v1_min",
    "v1_max",

    "bat2_label",
    "volt2",
    "v2_min",
    "v2_max",

    "rpm",
    "rpm_max",

    "fuel_flow",
    "ff_max",
    "fuel_remaining",
    "fuel_cap",

    "ignition",
    "mode_state"
}

local function read(widget)
    for _, field in ipairs(PERSISTENT_FIELDS) do
        widget[field] = storage.read(field)
    end

    widget._lastRenderKey = nil
end

local function write(widget)
    for _, field in ipairs(PERSISTENT_FIELDS) do
        storage.write(field, widget[field])
    end
end

------------------------------------------------------------
-- INITIALIZATION
------------------------------------------------------------
local function init()
    system.registerWidget({
        key = "aesii",
        name = name,

        create = function()
            return {}
        end,

        paint = paint,
        wakeup = wakeup,
        configure = configure,
        read = read,
        write = write
    })
end

return {
    init = init
}
