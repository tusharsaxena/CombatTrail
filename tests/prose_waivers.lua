-- tests/prose_waivers.lua — what the kit's US-English gate MUST NOT correct here.
--
-- Read by `tests/_kit/test_prose.lua` (localization-§5). Per FILE and per WORD, never per file
-- alone: a whole-file waiver hides every OTHER British spelling in a file this repository edits.
-- Every file below is waived for one word and for nothing else, so a `colour` that lands in any of
-- them still reddens.

return {
    waived = {
        -- A LIBRARY'S FIELD NAME. AceTimer (libs/AceTimer-3.0) and the kit's timer mock
        -- (tests/_kit/mock_ace.lua, tests/_kit/mock_record.lua) mark a canceled handle with
        -- AceTimer's own field, `cancelled`. The race clock suite's HUD beat finder skips a handle by
        -- that field, so it must spell it the way the mock writes it, or a canceled beat would still
        -- read as armed.
        ["tests/test_race_clock.lua"] = { cancelled = true },
    },
}
