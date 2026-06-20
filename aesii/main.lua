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

local ARC_BITMAP_SIZE = 135
local ARC_BITMAP_CENTER_X = 89
local ARC_BITMAP_CENTER_Y = 89
local RPM_BITMAP_W = 205
local RPM_BITMAP_H = 70
local FUEL_BITMAP_W = 210
local FUEL_BITMAP_H = 70
local FUEL_REMAINING_LINE_X = 9
local FUEL_REMAINING_LINE_W = 170
local arcTempBitmap = nil
local arcBattBitmap = nil
local arcTempBitmaps = {}
local arcBattBitmaps = {}
local fuelRemainingBitmap = nil
local fuelFlowBitmap = nil
local rpmBaseBitmap = nil
local labelBitmaps = {}
local arcBitmapLoadAttempted = false
local bitmapDrawMethod = nil

------------------------------------------------------------
-- UPDATE TIMER
------------------------------------------------------------
local lastTime = 0
local INTERVAL = 100
local QUANTIZE_CHT = 1
local QUANTIZE_BATTERY = 0.05
local QUANTIZE_RPM = 25
local QUANTIZE_FUEL_FLOW = 1
local QUANTIZE_FUEL_REMAINING = 5
local ARC_NEEDLE_STEP_DEG = 5
local REFRESH_CHT_MS = 400
local REFRESH_BATTERY_MS = 400
local REFRESH_FUEL_REMAINING_MS = 500
local REFRESH_FAST_MS = 100

------------------------------------------------------------
-- HELPERS
------------------------------------------------------------
local function round(v)
    v = tonumber(v)

    if v == nil then
        return 0
    end

    if v >= 0 then
        return math.floor(v + 0.5)
    end

    return math.ceil(v - 0.5)
end

local function clamp(v, lo, hi)
    v = tonumber(v)
    lo = tonumber(lo)
    hi = tonumber(hi)

    if v == nil then
        return lo or 0
    end

    if lo == nil then lo = v end
    if hi == nil then hi = v end

    if v < lo then return lo end
    if v > hi then return hi end
    return v
end

local function valuePercent(value, minValue, maxValue)
    value = tonumber(value)
    minValue = tonumber(minValue)
    maxValue = tonumber(maxValue)

    if value == nil then return 0 end
    if minValue == nil or maxValue == nil then return 0 end
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

local function quantizeAngleDegrees(angleDeg, stepDeg)
    if angleDeg == nil then
        return nil
    end

    if stepDeg == nil or stepDeg <= 0 then
        return angleDeg
    end

    return round(angleDeg / stepDeg) * stepDeg
end

local function arcDisplayAngle(value, minValue, maxValue)
    if value == nil then
        return nil
    end

    local position = valuePercent(value, minValue, maxValue)

    return quantizeAngleDegrees(
        180 + (300 - 180) * position,
        ARC_NEEDLE_STEP_DEG
    )
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
        "/scripts/aesii/images/arc_temp.png"
    }

    local battPaths = {
        "images/arc_batt.png",
        "scripts/aesii/images/arc_batt.png",
        "/scripts/aesii/images/arc_batt.png"
    }

    local fuelRemainingPaths = {
        "images/fuel_remaining.png",
        "scripts/aesii/images/fuel_remaining.png",
        "/scripts/aesii/images/fuel_remaining.png"
    }

    local fuelFlowPaths = {
        "images/fuel_flow.png",
        "scripts/aesii/images/fuel_flow.png",
        "/scripts/aesii/images/fuel_flow.png"
    }

    local rpmBasePaths = {
        "images/rpm_base.png",
        "scripts/aesii/images/rpm_base.png",
        "/scripts/aesii/images/rpm_base.png"
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

    for _, path in ipairs(fuelRemainingPaths) do
        fuelRemainingBitmap = tryLoadBitmap(path)

        if fuelRemainingBitmap ~= nil then
            break
        end
    end

    for _, path in ipairs(fuelFlowPaths) do
        fuelFlowBitmap = tryLoadBitmap(path)

        if fuelFlowBitmap ~= nil then
            break
        end
    end

    for _, path in ipairs(rpmBasePaths) do
        rpmBaseBitmap = tryLoadBitmap(path)

        if rpmBaseBitmap ~= nil then
            break
        end
    end
end

local function loadSteppedArcBitmap(cache, prefix, angleDeg)
    if angleDeg == nil then
        return nil
    end

    if cache[angleDeg] ~= nil then
        if cache[angleDeg] == false then
            return nil
        end

        return cache[angleDeg]
    end

    local filename = string.format("%s_%03d.png", prefix, angleDeg)
    local paths = {
        "images/" .. filename,
        "scripts/aesii/images/" .. filename,
        "/scripts/aesii/images/" .. filename
    }

    for _, path in ipairs(paths) do
        local loaded = tryLoadBitmap(path)

        if loaded ~= nil then
            cache[angleDeg] = loaded
            return loaded
        end
    end

    cache[angleDeg] = false
    return nil
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

local function quantizeValue(value, step)
    if value == nil then
        return nil
    end

    if step == nil or step <= 0 then
        return value
    end

    return round(value / step) * step
end

local function readTelemetrySnapshot(widget, nowMs)
    local previous = widget._telemetrySnapshot or {}
    local updateTimes = widget._telemetryUpdateMs or {}

    local function sampledValue(field, rawValue, step, minIntervalMs)
        local value = quantizeValue(rawValue, step)
        local lastUpdate = updateTimes[field]

        if previous[field] == nil or
            nowMs == nil or
            lastUpdate == nil or
            nowMs - lastUpdate >= (minIntervalMs or REFRESH_FAST_MS) then
            updateTimes[field] = nowMs
            return value
        end

        return previous[field]
    end

    local snapshot = {
        cht1 = sampledValue(
            "cht1",
            getVal(widget.temp1),
            QUANTIZE_CHT,
            REFRESH_CHT_MS
        ),
        cht2 = sampledValue(
            "cht2",
            getVal(widget.temp2),
            QUANTIZE_CHT,
            REFRESH_CHT_MS
        ),
        bat1 = sampledValue(
            "bat1",
            getVal(widget.volt1),
            QUANTIZE_BATTERY,
            REFRESH_BATTERY_MS
        ),
        bat2 = sampledValue(
            "bat2",
            getVal(widget.volt2),
            QUANTIZE_BATTERY,
            REFRESH_BATTERY_MS
        ),
        rpm = sampledValue(
            "rpm",
            getVal(widget.rpm),
            QUANTIZE_RPM,
            REFRESH_FAST_MS
        ),
        fuelFlow = sampledValue(
            "fuelFlow",
            getVal(widget.fuel_flow),
            QUANTIZE_FUEL_FLOW,
            REFRESH_FAST_MS
        ),
        fuelRemaining = sampledValue(
            "fuelRemaining",
            getVal(widget.fuel_remaining),
            QUANTIZE_FUEL_REMAINING,
            REFRESH_FUEL_REMAINING_MS
        ),
        ignitionEnabled = sampledValue(
            "ignitionEnabled",
            getVal(widget.ignition),
            nil,
            REFRESH_FAST_MS
        ),
        modeState = sampledValue(
            "modeState",
            getVal(widget.mode_state),
            nil,
            REFRESH_FAST_MS
        )
    }

    widget._telemetryUpdateMs = updateTimes
    return snapshot
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

    local numericValue = tonumber(value)

    if numericValue == nil then
        return "---"
    end

    local formatString = "%." .. tostring(decimals or 0) .. "f"
    local text = string.format(formatString, numericValue)

    if unit ~= nil then
        text = text .. unit
    end

    return text
end

local function formattedTelemetryKey(widget, telemetry)
    local cht1Min = widget.t1_min or 10
    local cht1Max = widget.t1_max or 150
    local cht2Min = widget.t2_min or 10
    local cht2Max = widget.t2_max or 150
    local bat1Min = widget.v1_min or 6.0
    local bat1Max = widget.v1_max or 8.4
    local bat2Min = widget.v2_min or 6.0
    local bat2Max = widget.v2_max or 8.4
    local rpmMax = widget.rpm_max or 8500
    local rpmIdle = widget.rpm_idle or 800
    local rpmRedline = widget.rpm_redline or 8000
    local flowMin = widget.ff_min or 0
    local flowMax = widget.ff_max or 100
    local fuelCapacity = widget.fuel_cap or 1000

    if cht1Min == 0 then
        cht1Min = 10
    end

    if cht2Min == 0 then
        cht2Min = 10
    end

    local snapshot = telemetry or readTelemetrySnapshot(widget)
    local cht1 = snapshot.cht1
    local cht2 = snapshot.cht2
    local bat1 = snapshot.bat1
    local bat2 = snapshot.bat2
    local rpm = snapshot.rpm
    local fuelFlow = snapshot.fuelFlow
    local fuelRemaining = snapshot.fuelRemaining
    local ignitionEnabled = snapshot.ignitionEnabled
    local modeState = snapshot.modeState
    local cht1Angle = arcDisplayAngle(cht1, cht1Min, cht1Max)
    local cht2Angle = arcDisplayAngle(cht2, cht2Min, cht2Max)
    local bat1Angle = arcDisplayAngle(bat1, bat1Min, bat1Max)
    local bat2Angle = arcDisplayAngle(bat2, bat2Min, bat2Max)

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
        cht1Angle == nil and "angnil" or string.format("a%d", cht1Angle),
        cht2Angle == nil and "angnil" or string.format("a%d", cht2Angle),
        bat1Angle == nil and "angnil" or string.format("a%d", bat1Angle),
        bat2Angle == nil and "angnil" or string.format("a%d", bat2Angle),
        rpm == nil and "---" or string.format("%d", round(rpm)),
        formatValue(fuelFlow, 1, nil),
        fuelRemaining == nil and "---" or formatValue(fuelRemaining / 10, 0, "%"),
        formatValue(cht1Min, 0, nil),
        formatValue(cht1Max, 0, nil),
        formatValue(cht2Min, 0, nil),
        formatValue(cht2Max, 0, nil),
        formatValue(bat1Min, 2, nil),
        formatValue(bat1Max, 2, nil),
        formatValue(bat2Min, 2, nil),
        formatValue(bat2Max, 2, nil),
        formatValue(rpmMax, 0, nil),
        formatValue(rpmRedline, 0, nil),
        formatValue(flowMax, 1, nil),
        formatValue(fuelCapacity, 0, nil),
        formatValue(rpmIdle, 0, nil),
        ignitionEnabled ~= nil and ignitionEnabled > 0 and "IGN1" or "IGN0",
        modeState == nil and "MODnil" or string.format("MOD%d", round(modeState))
    }, "|")
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

local drawNativeText

local function drawTinyText(x, y, text, color, flags)
    drawNativeText(
        x,
        y,
        text,
        color or COL_LABEL,
        FONT_SMALL,
        flags
    )
end

drawNativeText = function(x, y, text, color, font, align)
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

local function drawSmallValue(x, y, text, color, align)
    drawNativeText(x, y, text, color, FONT_SMALL, align)
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
    arcBitmap,
    steppedBitmaps,
    steppedPrefix
)
    local position = valuePercent(value, minValue, maxValue)

    local startAngle = 180
    local endAngle = 300
    local sweep = endAngle - startAngle

    local thickness = math.floor(
        clamp(radius * 0.131, 8, 12)
    )

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
        round(centerX + math.cos(maxLabelAngle) * maxLabelRadius + 38),
        round(centerY + math.sin(maxLabelAngle) * maxLabelRadius + 8),
        formatValue(maxValue, decimals, nil),
        COL_LABEL,
        RIGHT
    )

    --------------------------------------------------------
    -- Pointer
    --------------------------------------------------------
    local pointerAngleDeg = startAngle + sweep * position
    local displayAngleDeg = quantizeAngleDegrees(
        pointerAngleDeg,
        ARC_NEEDLE_STEP_DEG
    )

    displayAngleDeg = clamp(displayAngleDeg, startAngle, endAngle)

    local activeArcBitmap = arcBitmap

    if value ~= nil and steppedBitmaps ~= nil and steppedPrefix ~= nil then
        activeArcBitmap = loadSteppedArcBitmap(
            steppedBitmaps,
            steppedPrefix,
            displayAngleDeg
        ) or activeArcBitmap
    end

    drawArcBitmap(activeArcBitmap, centerX, centerY)

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
    local valueX = centerX + radius * 0.12
    local labelX = valueX

    if string.sub(label or "", 1, 3) == "CHT" then
        labelX = labelX + 2
    end
    local valueDrawY = valueY or centerY + 12

    drawNativeValue(
        valueX,
        valueDrawY + 1,
        valueText,
        valueColor,
        "center"
    )

    drawNativeText(
        labelX,
        labelY or centerY + 31,
        label,
        COL_LABEL,
        0,
        "center"
    )
end

------------------------------------------------------------
-- LARGE BOXED RPM DISPLAY
------------------------------------------------------------
local function rpmBox(x, y, w, h, rpm, maxRpm, idleRpm, redlineRpm)
    local position = valuePercent(rpm, 0, maxRpm)

    local valueColor = COL_RED

    if rpm == nil then
        valueColor = COL_RED
    elseif position >= 0.90 then
        valueColor = COL_RED
    elseif position >= 0.80 then
        valueColor = COL_RED
    end

    local rpmText = "---"

    if rpm ~= nil then
        rpmText = string.format("%d", rpm)
    end

    drawBitmapAt(
        rpmBaseBitmap,
        round(x),
        round(y)
    )

    --------------------------------------------------------
    -- RPM load bar
    --------------------------------------------------------
    local barX = x + 20
    local barY = y + 37
    local barW = 170
    local barRightX = barX + barW - 1
    local idlePosition = valuePercent(idleRpm or 800, 0, maxRpm)
    local redlinePosition = valuePercent(redlineRpm or 8000, 0, maxRpm)
    local idleX = barX + barW * idlePosition
    local redlineX = barX + barW * redlinePosition
    local markerX = barX + barW * position

    local rpmValueColor = COL_GREEN

    if position >= redlinePosition then
        rpmValueColor = COL_RED
    elseif position < idlePosition then
        rpmValueColor = COL_YELLOW
    end

    lcd.color(COL_GREEN)
    lcd.drawFilledRectangle(
        round(idleX - 1),
        round(barY - 4),
        2,
        8
    )

    local redlineStart = round(redlineX)
    local redlineWidth = round(barRightX) - redlineStart

    if redlineWidth > 0 then
        lcd.color(COL_RED)
        lcd.drawFilledRectangle(
            redlineStart,
            round(barY - 4),
            redlineWidth,
            8
        )
    end

    drawSmallValue(
        x + w - 2,
        barY - 9,
        rpmText,
        rpmValueColor,
        "left"
    )

    local scaleLabelY = barY + 13
    local minText = "0"
    local maxText = tostring(round(maxRpm))
    local minX = barX + 5
    local maxX = barX + barW + 6

    drawNativeText(minX, scaleLabelY, minText, COL_LABEL, FONT_SMALL, "right")
    drawNativeText(maxX, scaleLabelY, maxText, COL_LABEL, FONT_SMALL, "right")

    if rpm ~= nil then
        lcd.color(valueColor)
        lcd.drawFilledRectangle(
            round(markerX - 2),
            round(barY - 10),
            4,
            20
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
    zones,
    baseBitmap,
    faceStyle
)
    local effectiveMin = minValue or 0
    local effectiveMax = maxValue or effectiveMin

    local position = valuePercent(
        value,
        effectiveMin,
        effectiveMax
    )

    local valueColor

    if value == nil then
        valueColor = COL_RED
    else
        valueColor = zoneColor(position, zones)
    end

    drawBitmapAt(
        baseBitmap,
        round(x),
        round(y)
    )

    if faceStyle ~= "remaining" and faceStyle ~= "flow" then
        drawNativeText(x - 41, y + 4, label, COL_LABEL, 0)
    end

    local stripValueText = formatValue(value, decimals, unit)

    if faceStyle == "remaining" then
        local numericValue = tonumber(value)

        if numericValue == nil then
            stripValueText = "---"
        else
            stripValueText = formatValue(numericValue / 10, 0, "%")
        end
    end

    if faceStyle ~= "remaining" and faceStyle ~= "flow" then
        drawSmallValue(
            x + w - 2,
            y + 0,
            stripValueText,
            valueColor,
            "left"
        )
    end

    local lineY = y + 43
    local lineX = x + 10
    local lineW = 130

    if faceStyle == "remaining" or faceStyle == "flow" then
        lineY = y + 38
        lineX = x + FUEL_REMAINING_LINE_X
        lineW = FUEL_REMAINING_LINE_W
    end

    if faceStyle == "remaining" or faceStyle == "flow" then
        local lineRightX = lineX + lineW - 1
        local lastX = lineX

        if zones ~= nil then
            for _, zone in ipairs(zones) do
                local zoneStart = clamp(zone[1], 0, 1)
                local zoneEnd = clamp(zone[2], 0, 1)
                local segX1 = lineX + lineW * zoneStart
                local segX2 = math.min(lineRightX, lineX + lineW * zoneEnd)

                if segX2 > segX1 then
                    lcd.color(zone[3])
                    lcd.drawLine(
                        round(segX1),
                        round(lineY),
                        round(segX2),
                        round(lineY)
                    )
                    lcd.drawLine(
                        round(segX1),
                        round(lineY + 1),
                        round(segX2),
                        round(lineY + 1)
                    )
                    lastX = segX2
                end
            end
        end

        if lastX < lineRightX then
            lcd.color(COL_GREEN)
            lcd.drawLine(
                round(lastX),
                round(lineY),
                round(lineRightX),
                round(lineY)
            )
            lcd.drawLine(
                round(lastX),
                round(lineY + 1),
                round(lineRightX),
                round(lineY + 1)
            )
        end

        drawSmallValue(
            x + w - 20,
            lineY - 10,
            stripValueText,
            valueColor,
            "left"
        )
    end

    if faceStyle == "flow" then
        local labelY = lineY + 21
        local minText = formatValue(round(effectiveMin), 0, unit)
        local maxText = formatValue(round(effectiveMax), 0, unit)
        local minX = lineX + 5
        local maxX = lineX + lineW + 6

        drawNativeText(minX, labelY - 8, minText, COL_LABEL, 0, "right")
        drawNativeText(maxX, labelY - 10, maxText, COL_LABEL, 0, "right")
    end

    local markerPosition = clamp(position, 0, 1)
    local markerX = lineX + lineW * markerPosition

    lcd.color(valueColor)
    lcd.drawFilledRectangle(
        round(markerX - 2),
        round(lineY - 10),
        4,
        20
    )

    if faceStyle == "remaining" or faceStyle == "flow" then
        return
    end

    drawNativeText(
        x + w - 8,
        y + 35,
        formatValue(maxValue, decimals, unit),
        COL_WHITE,
        0,
        "right"
    )

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

    if labelBitmapName ~= nil then
        drawLabelBitmap(labelBitmapName, x + 38, y + 3)
    else
        drawNativeText(x + 38, y + 5, label, labelColor, 0)
    end

    if stateText ~= nil then
        drawNativeText(x + w - 10, y + 5, stateText, labelColor, 0, "right")
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
    local mode = nil

    if modeValue ~= nil then
        mode = round(modeValue)
    end

    local active = mode ~= nil and mode >= 0
    local stateText = "OFF"
    local activeColor = COL_LABEL

    if mode ~= nil and mode >= 100 then
        stateText = "STAB"
        activeColor = COL_GREEN
    elseif mode ~= nil and mode >= 0 then
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
    local telemetry = widget._telemetrySnapshot

    if telemetry == nil then
        telemetry = readTelemetrySnapshot(widget, os.clock() * 1000)
        widget._telemetrySnapshot = telemetry
    end

    local cht1 = telemetry.cht1
    local cht2 = telemetry.cht2

    local bat1 = telemetry.bat1
    local bat2 = telemetry.bat2

    local rpm = telemetry.rpm

    local fuelFlow = telemetry.fuelFlow
    local fuelRemaining = telemetry.fuelRemaining
    local ignitionEnabled = telemetry.ignitionEnabled
    local modeState = telemetry.modeState

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
    local bottomY = h - 58

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
        arcTempBitmap,
        arcTempBitmaps,
        "arc_temp"
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
        arcTempBitmap,
        arcTempBitmaps,
        "arc_temp"
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
        arcBattBitmap,
        arcBattBitmaps,
        "arc_batt"
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
        arcBattBitmap,
        arcBattBitmaps,
        "arc_batt"
    )

    local stackX = w / 2 - FUEL_BITMAP_W / 2
    local rpmY = topY - 32
    local flowY = rpmY + 80
    local fuelY = flowY + 80
    local annunciatorY = fuelY + 78

    --------------------------------------------------------
    -- RPM
    --------------------------------------------------------
    rpmBox(
        w / 2 - RPM_BITMAP_W / 2 - 13,
        rpmY,
        RPM_BITMAP_W,
        RPM_BITMAP_H,
        rpm,
        rpmMax,
        rpmIdle,
        rpmRedline
    )

    --------------------------------------------------------
    -- Fuel section
    --------------------------------------------------------
    fuelStrip(
        stackX,
        flowY,
        FUEL_BITMAP_W,
        "FF ML/MIN",
        fuelFlow,
        flowMin,
        flowMax,
        nil,
        1,
        {
            {0.00, 0.80, COL_GREEN},
            {0.80, 1.00, COL_YELLOW}
        },
        fuelFlowBitmap,
        "flow"
    )

    fuelStrip(
        stackX,
        fuelY,
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
        },
        fuelRemainingBitmap,
        "remaining"
    )

    local annunciatorW = 102
    local annunciatorGap = 10
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
        arcTempBitmap,
        arcTempBitmaps,
        "arc_temp"
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
        arcBattBitmap,
        arcBattBitmaps,
        "arc_batt"
    )
end

local function paintRpm(widget)
    local w, h = preparePanel()
    local x = math.floor((w - RPM_BITMAP_W) / 2) - 13
    local y = math.floor((h - RPM_BITMAP_H) / 2)

    rpmBox(
        x,
        y,
        RPM_BITMAP_W,
        RPM_BITMAP_H,
        getVal(widget.rpm),
        widget.rpm_max or 8500,
        widget.rpm_idle or 800,
        widget.rpm_redline or 8000
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
        widget.ff_min or 0,
        widget.ff_max or 100,
        nil,
        1,
        {
            {0.00, 0.80, COL_GREEN},
            {0.80, 1.00, COL_YELLOW}
        },
        fuelFlowBitmap,
        "flow"
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
        },
        fuelRemainingBitmap,
        "remaining"
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

    local telemetry = readTelemetrySnapshot(widget, now)
    local renderKey = formattedTelemetryKey(widget, telemetry)

    if widget._lastRenderKey ~= renderKey then
        widget._telemetrySnapshot = telemetry
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

    bindNumber(
        "RPM Idle",
        "rpm_idle",
        800,
        0,
        30000,
        0
    )

    bindNumber(
        "RPM Redline",
        "rpm_redline",
        8000,
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
        "Flow Minimum",
        "ff_min",
        0,
        0,
        1000,
        0
    )

    bindNumber(
        "Flow Maximum",
        "ff_max",
        100,
        0,
        1000,
        0
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
    "rpm_idle",
    "rpm_redline",

    "fuel_flow",
    "ff_min",
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
    widget._telemetrySnapshot = nil
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
