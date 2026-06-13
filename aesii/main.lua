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
    return "AES"
end

------------------------------------------------------------
-- COLORS
------------------------------------------------------------
local COL_BG       = lcd.RGB(8, 10, 14)
local COL_PANEL    = lcd.RGB(17, 21, 28)
local COL_BOX      = lcd.RGB(23, 28, 36)
local COL_BORDER   = lcd.RGB(66, 78, 92)
local COL_DIM      = lcd.RGB(42, 49, 58)

local COL_TEXT     = lcd.RGB(245, 247, 250)
local COL_LABEL    = lcd.RGB(155, 172, 186)
local COL_WHITE    = lcd.RGB(255, 255, 255)

local COL_CYAN     = lcd.RGB(0, 190, 225)
local COL_GREEN    = lcd.RGB(20, 220, 115)
local COL_YELLOW   = lcd.RGB(255, 210, 0)
local COL_RED      = lcd.RGB(250, 55, 55)

local FONT_SMALL = SMLSIZE or 0

local ARC_BITMAP_SIZE = 192
local ARC_BITMAP_CENTER_X = 96
local ARC_BITMAP_CENTER_Y = 113
local RPM_BITMAP_W = 175
local RPM_BITMAP_H = 90
local arcTempBitmap = nil
local arcBattBitmap = nil
local rpmBaseBitmap = nil
local rpmDigitBitmaps = {}
local arcBitmapLoadAttempted = false

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
        "arc_temp.png",
        "scripts/aesii/arc_temp.png",
        "/scripts/aesii/arc_temp.png"
    }

    local battPaths = {
        "arc_batt.png",
        "scripts/aesii/arc_batt.png",
        "/scripts/aesii/arc_batt.png"
    }

    local rpmPaths = {
        "rpm_base.png",
        "scripts/aesii/rpm_base.png",
        "/scripts/aesii/rpm_base.png"
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

    for _, path in ipairs(rpmPaths) do
        rpmBaseBitmap = tryLoadBitmap(path)

        if rpmBaseBitmap ~= nil then
            break
        end
    end

    for _, char in ipairs({
        "0", "1", "2", "3", "4", "5", "6", "7", "8", "9", "-"
    }) do
        local suffix = char

        if char == "-" then
            suffix = "dash"
        end

        local paths = {
            "rpm_" .. suffix .. ".png",
            "scripts/aesii/rpm_" .. suffix .. ".png",
            "/scripts/aesii/rpm_" .. suffix .. ".png"
        }

        for _, path in ipairs(paths) do
            rpmDigitBitmaps[char] = tryLoadBitmap(path)

            if rpmDigitBitmaps[char] ~= nil then
                break
            end
        end
    end
end

local function drawBitmapAt(bitmapValue, x, y)
    if bitmapValue == nil then
        return false
    end

    if type(lcd.drawBitmap) == "function" then
        local ok = pcall(lcd.drawBitmap, bitmapValue, x, y)

        if ok then return true end

        ok = pcall(lcd.drawBitmap, x, y, bitmapValue)

        if ok then return true end
    end

    if type(lcd.drawImage) == "function" then
        local ok = pcall(lcd.drawImage, x, y, bitmapValue)

        if ok then return true end
    end

    if type(bitmapValue) == "table" and
        type(bitmapValue.draw) == "function" then
        local ok = pcall(function()
            bitmapValue:draw(x, y)
        end)

        if ok then return true end
    end

    return false
end

local function drawArcBitmap(bitmapValue, centerX, centerY)
    return drawBitmapAt(
        bitmapValue,
        round(centerX - ARC_BITMAP_CENTER_X),
        round(centerY - ARC_BITMAP_CENTER_Y)
    )
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

local function centeredText(x, y, text, color)
    lcd.color(color or COL_TEXT)
    lcd.drawText(round(x), round(y), text, CENTER)
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
    local scale = 3
    local drawX = round(x)

    if flags == RIGHT then
        drawX = drawX - tinyTextWidth(text, scale)
    elseif flags == CENTER then
        drawX = drawX - math.floor(tinyTextWidth(text, scale) / 2)
    end

    lcd.color(color or COL_LABEL)

    for i = 1, #text do
        local char = string.sub(text, i, i)
        local pattern = TINY_DIGITS[char]

        if pattern ~= nil then
            for row = 1, 5 do
                local bits = pattern[row]

                for col = 1, 3 do
                    if string.sub(bits, col, col) == "1" then
                        lcd.drawFilledRectangle(
                            drawX + (col - 1) * scale,
                            round(y) + (row - 1) * scale,
                            scale,
                            scale
                        )
                    end
                end
            end

            drawX = drawX + 4 * scale
        end
    end
end

local RPM_SEGMENTS = {
    ["0"] = {true, true, true, true, true, true, false},
    ["1"] = {false, true, true, false, false, false, false},
    ["2"] = {true, true, false, true, true, false, true},
    ["3"] = {true, true, true, true, false, false, true},
    ["4"] = {false, true, true, false, false, true, true},
    ["5"] = {true, false, true, true, false, true, true},
    ["6"] = {true, false, true, true, true, true, true},
    ["7"] = {true, true, true, false, false, false, false},
    ["8"] = {true, true, true, true, true, true, true},
    ["9"] = {true, true, true, true, false, true, true},
    ["-"] = {false, false, false, false, false, false, true}
}

local function drawSegmentDigit(x, y, char, color)
    local seg = RPM_SEGMENTS[char]

    if seg == nil then
        return
    end

    local w = 15
    local h = 28
    local t = 4
    local midY = y + 13

    lcd.color(color)

    if seg[1] then lcd.drawFilledRectangle(x + t, y, w - 2 * t, t) end
    if seg[2] then lcd.drawFilledRectangle(x + w - t, y + t, t, 10) end
    if seg[3] then lcd.drawFilledRectangle(x + w - t, midY + t, t, 10) end
    if seg[4] then lcd.drawFilledRectangle(x + t, y + h - t, w - 2 * t, t) end
    if seg[5] then lcd.drawFilledRectangle(x, midY + t, t, 10) end
    if seg[6] then lcd.drawFilledRectangle(x, y + t, t, 10) end
    if seg[7] then lcd.drawFilledRectangle(x + t, midY, w - 2 * t, t) end
end

local function drawRpmValue(x, y, text, color)
    local digitW = 24
    local digitH = 42
    local fallbackDigitW = 15
    local fallbackDigitH = 28
    local gap = 5
    local width = #text * digitW + (#text - 1) * gap
    local drawX = round(x - width / 2)

    for i = 1, #text do
        local char = string.sub(text, i, i)
        local bitmapValue = rpmDigitBitmaps[char]
        local drawn = false

        if bitmapValue ~= nil then
            drawn = drawBitmapAt(
                bitmapValue,
                drawX,
                round(y)
            )
        end

        if not drawn then
            drawSegmentDigit(
                drawX + math.floor((digitW - fallbackDigitW) / 2),
                round(y + (digitH - fallbackDigitH) / 2),
                char,
                color
            )
        end

        drawX = drawX + digitW + gap
    end
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

    local startAngle = 205
    local endAngle = 325
    local sweep = endAngle - startAngle

    local thickness = math.floor(
        clamp(radius * 0.19, 10, 13)
    )

    local segmentStep = 2

    --------------------------------------------------------
    -- Range arc
    --------------------------------------------------------
    if not drawArcBitmap(arcBitmap, centerX, centerY) then
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
        round(centerY + math.sin(minLabelAngle) * minLabelRadius + 14),
        formatValue(minValue, decimals, nil),
        COL_LABEL
    )

    local maxLabelAngle = math.rad(endAngle)
    local maxLabelRadius = radius - thickness - 2

    drawTinyText(
        round(centerX + math.cos(maxLabelAngle) * maxLabelRadius + 18),
        round(centerY + math.sin(maxLabelAngle) * maxLabelRadius + 13),
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

    lcd.color(valueColor)
    lcd.drawText(
        round(centerX + radius * 0.17),
        round(valueY or centerY + 12),
        formatValue(value, decimals, unit),
        CENTER
    )

    lcd.color(COL_LABEL)
    lcd.drawText(
        round(centerX + radius * 0.17),
        round(labelY or centerY + 31),
        label,
        CENTER
    )
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

    local baseDrawn = drawBitmapAt(
        rpmBaseBitmap,
        round(x),
        round(y)
    )

    if not baseDrawn then
        lcd.color(COL_BOX)
        lcd.drawFilledRectangle(
            round(x),
            round(y),
            round(w),
            round(h)
        )

        lcd.color(COL_CYAN)
        lcd.drawRectangle(
            round(x),
            round(y),
            round(w),
            round(h)
        )

        lcd.color(COL_BG)
        lcd.drawFilledRectangle(
            round(x + 12),
            round(y + 26),
            round(w - 24),
            38
        )
    end

    centeredText(
        x + w / 2,
        y + 7,
        "RPM",
        COL_LABEL
    )

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
    local barX = x + 14
    local barY = y + h - 18
    local barW = w - 28

    lcd.color(COL_DIM)
    lcd.drawFilledRectangle(
        round(barX),
        round(barY),
        round(barW),
        5
    )

    lcd.color(valueColor)
    lcd.drawFilledRectangle(
        round(barX),
        round(barY),
        round(barW * position),
        5
    )
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

    lcd.color(COL_BORDER)
    local stripH = 31

    lcd.drawRectangle(
        round(x),
        round(y),
        round(w),
        stripH
    )

    lcd.color(COL_LABEL)
    lcd.drawText(
        round(x + 4),
        round(y + 2),
        label
    )

    lcd.color(valueColor)
    lcd.drawText(
        round(x + w - 4),
        round(y + 2),
        formatValue(value, decimals, unit),
        RIGHT
    )

    local lineY = y + 23
    local lineX = x + 8
    local lineW = w - 16

    lcd.color(COL_WHITE)
    lcd.drawLine(
        round(lineX),
        round(lineY),
        round(lineX + lineW),
        round(lineY)
    )

    lcd.drawLine(
        round(lineX),
        round(lineY - 6),
        round(lineX),
        round(lineY + 6)
    )

    lcd.drawLine(
        round(lineX + lineW),
        round(lineY - 6),
        round(lineX + lineW),
        round(lineY + 6)
    )

    local markerX = lineX + lineW * position

    lcd.color(valueColor)
    lcd.drawFilledRectangle(
        round(markerX - 2),
        round(lineY - 7),
        5,
        14
    )

    lcd.color(COL_WHITE)
    lcd.drawLine(
        round(markerX - 4),
        round(lineY - 8),
        round(markerX + 4),
        round(lineY - 8)
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

    local rpmMax = widget.rpm_max or 12000
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
        clamp(w * 0.15, 90, 112)
    )

    local leftX = sideX
    local rightX = w - sideX
    local chtLeftX = leftX - 8
    local chtRightX = rightX + 8

    local topY = mainPanelY + 64
    local chtY = topY + 18
    local bottomY = h - 62

    local radius = math.floor(
        clamp((bottomY - topY) / 2 + 12, 50, 77)
    )

    local topLabelY = topY - 4
    local topValueY = topY + 18
    local chtValueY = chtY - 6
    local chtLabelY = chtValueY + 19
    local bottomValueY = bottomY + 8
    local bottomLabelY = bottomValueY + 18

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
        topY - 45,
        RPM_BITMAP_W,
        RPM_BITMAP_H,
        rpm,
        rpmMax
    )

    --------------------------------------------------------
    -- Fuel section
    --------------------------------------------------------
    fuelStrip(
        w / 2 - 84,
        topY + 50,
        168,
        "FF mL/min",
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
        w / 2 - 84,
        topY + 100,
        168,
        "FUEL mL",
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
end

------------------------------------------------------------
-- WAKEUP
------------------------------------------------------------
local function wakeup(widget)
    local now = os.clock() * 1000

    if now - lastTime >= INTERVAL then
        lastTime = now
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
        12000,
        0,
        30000,
        0
    )

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
        configure = configure
    })
end

return {
    init = init
}
