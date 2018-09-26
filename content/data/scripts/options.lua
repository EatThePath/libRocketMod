local utils = require("utils")
local tblUtil = utils.table

local rkt_util = require("rocket_util")

local dialogs = require("dialogs")

local class = require("class")

local function getFormatterName(key)
    return key:gsub("%.", "_")
end

local DataSourceWrapper = class()

function DataSourceWrapper:init(option)
    self.option = option

    local source = DataSource.new(getFormatterName(option.Key))

    self.values = option:getValidValues()
    source.GetNumRows = function()
        return #self.values
    end
    source.GetRow = function(_, i, columns)
        local val = self.values[i]
        local out = {}
        for _, v in ipairs(columns) do
            if v == "serialized" then
                table.insert(out, val.Serialized)
            elseif v == "display" then
                table.insert(out, val.Display)
            else
                table.insert(out, "")
            end
        end
        return out
    end

    self.source = source
end

function DataSourceWrapper:updateValues()
    ba.print("Updating values...")
    self.values = self.option:getValidValues()
    self.source:NotifyRowChange("Default")
end

local function createOptionSource(option)
    return DataSourceWrapper(option)
end

local OptionsController = class()

function OptionsController:init()
    self.sources = {}
    self.options = {}
    self.category_options = {
        basic = {},
        detail = {},
        other = {},
        multi = {}
    }
end

function OptionsController:init_selection_element(element, option, change_func)
    local select_el = Element.As.ElementFormControlDataSelect(element)
    select_el:SetDataSource(getFormatterName(option.Key) .. ".Default")

    local vals = option:getValidValues()
    local value = option.Value

    element:AddEventListener("change", function(event, _, _)
        for _, v in ipairs(vals) do
            if v.Serialized == event.parameters.value and option.Value ~= v then
                option.Value = v
                if change_func then
                    change_func(v)
                end
            end
        end
    end)

    select_el.selection = tblUtil.ifind(vals, value)
end

function OptionsController:init_range_element(element, value_el, option, change_func)
    local range_el = Element.As.ElementFormControlInput(element)

    element:AddEventListener("change", function(event, _, _)
        local value = option:getValueFromRange(event.parameters.value)
        value_el.inner_rml = value.Display

        if option.Value ~= value then
            option.Value = value
            if change_func then
                change_func(value)
            end
        end
    end)

    range_el.value = option:getInterpolantFromValue(option.Value)
end

function OptionsController:createOptionElement(option, parent_id, onchange_func)
    local parent_el = self.document:GetElementById(parent_id)
    if option.Type == OPTION_TYPE_SELECTION then
        local actual_el, text_el, dataselect_el = rkt_util.instantiate_template(self.document, "dropdown_template", {
            "dropdown_text_el",
            "dropdown_dataselect_el"
        })
        parent_el:AppendChild(actual_el)

        text_el.inner_rml = option.Title

        self:init_selection_element(dataselect_el, option, onchange_func)
    elseif option.Type == OPTION_TYPE_RANGE then
        local actual_el, title_el, value_el, range_el = rkt_util.instantiate_template(self.document, "slider_template", {
            "slider_title_el",
            "slider_value_el",
            "slider_range_el"
        })
        parent_el:AppendChild(actual_el)

        title_el.inner_rml = option.Title

        self:init_range_element(range_el, value_el, option, onchange_func)
    end
end

function OptionsController:initialize_detail_options()
    local current_column = 2
    for _, v in ipairs(self.category_options.detail) do
        if v.Key == "Graphics.Resolution" then
            self:createOptionElement(v, "detail_column_1")
        elseif v.Key == "Graphics.Display" then
            self:createOptionElement(v, "detail_column_1", function(_)
                self.sources["Graphics.Resolution"]:updateValues()
            end)
        else
            self:createOptionElement(v, string.format("detail_column_%d", current_column))
            current_column = current_column + 1
            if current_column > 4 then
                current_column = 2
            end
        end
    end
end

function OptionsController:initialize(document)
    self.document = document

    -- Persist current changes since we might discard them in this screen
    opt.persistChanges()

    self.options = opt.Options
    for _, v in ipairs(self.options) do
        if v.Type == OPTION_TYPE_SELECTION then
            self.sources[v.Key] = createOptionSource(v)
        end

        if v.Category == "Graphics" then
            -- TODO: The category might be a translated string at some point so this needs to be fixed then
            table.insert(self.category_options.detail, v)
        end
    end

    self:initialize_detail_options()
end

function OptionsController:accept_clicked(element)
    local unchanged = opt.persistChanges()

    if #unchanged <= 0 then
        -- All options were applied
        ba.postGameEvent(ba.GameEvents["GS_EVENT_PREVIOUS_STATE"])
        return
    end

    local titles = {}
    for _, v in ipairs(unchanged) do
        table.insert(titles, string.format("<li>%s</li>", v.Title))
    end

    local changed_text = table.concat(titles, "\n")

    local dialog_text = string.format(ba.XSTR("The following changes require a restart to apply their changes:<ul>%s</ul>", -1), changed_text)

    local builder = dialogs.new()
    builder:title(ba.XSTR("Restart required", -1))
    builder:text(dialog_text)
    builder:button(dialogs.BUTTON_TYPE_POSITIVE, ba.XSTR("Ok", -1))
    builder:show(self.document.context, function(_)
        ba.postGameEvent(ba.GameEvents["GS_EVENT_PREVIOUS_STATE"])
    end)
end

function OptionsController:global_keydown(element, event)
end

return OptionsController