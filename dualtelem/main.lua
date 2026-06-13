-- Generic Dual Telemetry Gauge (ETHOS 26.1)
-- Clean UI + grouped config + full customization

local translations = {
    en = "Dual Telemetry",
    fr = "Double Télémétrie"
}

local function name(widget)
    local locale = system.getLocale()
    return translations[locale] or translations.en
end

------------------------------------------------------------
-- CREATE
------------------------------------------------------------
local function create()
    return {
        source1 = nil,
        source2 = nil,

        value1 = 0,
        value2 = 0,

        -- labels / units
        label1 = "",
        label2 = "",
        unit1 = "",
        unit2 = "",

        -- CH1 range
        min1 = 0,
        max1 = 100,
        warn1_low = 30,
        warn1_high = 70,

        -- CH2 range
        min2 = 0,
        max2 = 100,
        warn2_low = 30,
        warn2_high = 70,

        color_red = lcd.RGB(220, 60, 60),
        color_yellow = lcd.RGB(240, 200, 0),
        color_green = lcd.RGB(60, 200, 120)
    }
end

------------------------------------------------------------
-- UTILS
------------------------------------------------------------
local function norm(v, min, max)
    local r = max - min
    if r == 0 then r = 1 end
    local p = (v - min) / r
    if p < 0 then p = 0 elseif p > 1 then p = 1 end
    return p
end

local function getColor(widget, value, low, high)
    if value < low then
        return widget.color_red
    elseif value < high then
        return widget.color_yellow
    else
        return widget.color_green
    end
end

local function drawBar(x, y, w, h, pct, color)

    lcd.color(lcd.RGB(210, 210, 210))
    lcd.drawFilledRectangle(x, y, w, h)

    local fill = math.floor(w * pct)
    if fill < 2 then fill = 2 end

    lcd.color(color)
    lcd.drawFilledRectangle(x, y, fill, h)

    lcd.color(lcd.RGB(150, 150, 150))
    lcd.drawRectangle(x, y, w, h)
end

local function label(source, overrideLabel, overrideUnit)

    local n = source:name()
    local u = source:unit()

    if overrideLabel and overrideLabel ~= "" then
        n = overrideLabel
    end

    if overrideUnit and overrideUnit ~= "" then
        u = overrideUnit
    end

    if u and u ~= "" then
        return n .. " (" .. u .. ")"
    end

    return n
end

------------------------------------------------------------
-- PAINT
------------------------------------------------------------
local function paint(widget)

    local w, h = lcd.getWindowSize()

    -- light background (important for readability)
    lcd.color(lcd.RGB(250, 250, 250))
    lcd.drawFilledRectangle(0, 0, w, h)

    if h < 50 then
        lcd.font(FONT_XS)
    elseif h < 80 then
        lcd.font(FONT_S)
    elseif h > 170 then
        lcd.font(FONT_XL)
    else
        lcd.font(FONT_M)
    end

    local left = 6
    local width = w - 12
    local mid = math.floor(h / 2)

    --------------------------------------------------------
    -- update values
    --------------------------------------------------------
    widget.value1 = widget.source1 and widget.source1:value() or 0
    widget.value2 = widget.source2 and widget.source2:value() or 0

    local p1 = norm(widget.value1, widget.min1, widget.max1)
    local p2 = norm(widget.value2, widget.min2, widget.max2)

    --------------------------------------------------------
    -- background panels
    --------------------------------------------------------
    lcd.color(lcd.RGB(238, 238, 238))
    lcd.drawFilledRectangle(2, 2, w - 4, mid - 3)

    lcd.color(lcd.RGB(230, 230, 230))
    lcd.drawFilledRectangle(2, mid + 1, w - 4, h - mid - 3)

    --------------------------------------------------------
    -- CHANNEL 1
    --------------------------------------------------------
    if widget.source1 then

        lcd.color(BLACK)
        lcd.drawText(
            left,
            2,
            label(widget.source1, widget.label1, widget.unit1)
        )

        lcd.drawText(left + width, 2, widget.source1:stringValue(), RIGHT)

        local col1 = getColor(widget, widget.value1, widget.warn1_low, widget.warn1_high)

        drawBar(left, mid - 18, width, 10, p1, col1)
    end

    --------------------------------------------------------
    -- CHANNEL 2
    --------------------------------------------------------
    if widget.source2 then

        lcd.color(BLACK)
        lcd.drawText(
            left,
            mid + 4,
            label(widget.source2, widget.label2, widget.unit2)
        )

        lcd.drawText(left + width, mid + 4, widget.source2:stringValue(), RIGHT)

        local col2 = getColor(widget, widget.value2, widget.warn2_low, widget.warn2_high)

        drawBar(left, h - 18, width, 10, p2, col2)
    end

    --------------------------------------------------------
    -- frame
    --------------------------------------------------------
    lcd.color(lcd.RGB(180, 180, 180))
    lcd.drawRectangle(1, 1, w - 2, h - 2)
end

------------------------------------------------------------
-- WAKEUP
------------------------------------------------------------
local function wakeup(widget)

    local changed = false

    if widget.source1 then
        local v = widget.source1:value()
        if v ~= nil and v ~= widget.value1 then
            widget.value1 = v
            changed = true
        end
    end

    if widget.source2 then
        local v = widget.source2:value()
        if v ~= nil and v ~= widget.value2 then
            widget.value2 = v
            changed = true
        end
    end

    if changed then
        lcd.invalidate()
    end
end

------------------------------------------------------------
-- CONFIG (GROUPED UI)
------------------------------------------------------------
local function configure(widget)

    local line

    --------------------------------------------------------
    -- CHANNEL 1
    --------------------------------------------------------
    line = form.addLine("━━ Channel 1 ━━")

    line = form.addLine("Source")
    form.addSourceField(line, nil,
        function() return widget.source1 end,
        function(v) widget.source1 = v end
    )

    line = form.addLine("Label")
    form.addTextField(line, nil,
        function() return widget.label1 end,
        function(v) widget.label1 = v end
    )

    line = form.addLine("Unit")
    form.addTextField(line, nil,
        function() return widget.unit1 end,
        function(v) widget.unit1 = v end
    )

    line = form.addLine("Min")
    form.addNumberField(line, nil, -100000, 100000,
        function() return widget.min1 end,
        function(v) widget.min1 = v end
    )

    line = form.addLine("Max")
    form.addNumberField(line, nil, -100000, 100000,
        function() return widget.max1 end,
        function(v) widget.max1 = v end
    )

    --------------------------------------------------------
    -- SPACER
    --------------------------------------------------------
    line = form.addLine(" ")

    --------------------------------------------------------
    -- CHANNEL 2
    --------------------------------------------------------
    line = form.addLine("━━ Channel 2 ━━")

    line = form.addLine("Source")
    form.addSourceField(line, nil,
        function() return widget.source2 end,
        function(v) widget.source2 = v end
    )

    line = form.addLine("Label")
    form.addTextField(line, nil,
        function() return widget.label2 end,
        function(v) widget.label2 = v end
    )

    line = form.addLine("Unit")
    form.addTextField(line, nil,
        function() return widget.unit2 end,
        function(v) widget.unit2 = v end
    )

    line = form.addLine("Min")
    form.addNumberField(line, nil, -100000, 100000,
        function() return widget.min2 end,
        function(v) widget.min2 = v end
    )

    line = form.addLine("Max")
    form.addNumberField(line, nil, -100000, 100000,
        function() return widget.max2 end,
        function(v) widget.max2 = v end
    )

    --------------------------------------------------------
    -- EXIT
    --------------------------------------------------------
    line = form.addLine(" ")
    form.addButton(line, nil, {
        text = "Exit",
        press = function() system.exit() end
    })
end

------------------------------------------------------------
-- STORAGE
------------------------------------------------------------
local function read(widget)
    widget.source1 = storage.read("source1")
    widget.source2 = storage.read("source2")

    widget.min1 = storage.read("min1") or 0
    widget.max1 = storage.read("max1") or 100

    widget.min2 = storage.read("min2") or 0
    widget.max2 = storage.read("max2") or 100

    widget.label1 = storage.read("label1") or ""
    widget.label2 = storage.read("label2") or ""

    widget.unit1 = storage.read("unit1") or ""
    widget.unit2 = storage.read("unit2") or ""
end

local function write(widget)
    storage.write("source1", widget.source1)
    storage.write("source2", widget.source2)

    storage.write("min1", widget.min1)
    storage.write("max1", widget.max1)

    storage.write("min2", widget.min2)
    storage.write("max2", widget.max2)

    storage.write("label1", widget.label1)
    storage.write("label2", widget.label2)

    storage.write("unit1", widget.unit1)
    storage.write("unit2", widget.unit2)
end

------------------------------------------------------------
-- REGISTER
------------------------------------------------------------
local function init()
    system.registerWidget({
        key = "dualg",
        name = name,
        create = create,
        paint = paint,
        wakeup = wakeup,
        configure = configure,
        read = read,
        write = write
    })
end

return { init = init }
