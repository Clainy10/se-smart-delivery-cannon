data:extend({
    {
        type = "int-setting", name = "se-sc-check-interval", setting_type = "startup",
        default_value = 10, minimum_value = 1, maximum_value = 60, order = "a",
    },
    {
        type = "int-setting", name = "se-sc-default-limit", setting_type = "runtime-global",
        default_value = 8, minimum_value = 1, maximum_value = 48, order = "b",
    },
    {
        type = "string-setting", name = "se-sc-default-mode", setting_type = "runtime-global",
        default_value = "manual", allowed_values = {"manual", "auto"}, order = "c",
    },
    {
        type = "bool-setting", name = "se-sc-stop-without-chest", setting_type = "runtime-global",
        default_value = true, order = "d",
    },
    {
        type = "bool-setting", name = "se-sc-show-messages", setting_type = "runtime-per-user",
        default_value = true, order = "e",
    },
})