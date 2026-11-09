local addonName, NS = ...
-- core/MediaSetup.lua — NS.Icon / NS.MediaFont from LibKa0s-Media-1.0 and the one RegisterLSM call.

local Media = LibStub and LibStub("LibKa0s-Media-1.0", true)

--- The texture path for one shipped icon, or nil. Nil is a real answer: the library may be absent
--- or the name not one this addon declares (root CLAUDE.md's `LibKa0s icons:` line), and both mean
--- the same thing to a caller -- draw something else.
function NS.Icon(name)
    if not Media then return nil end
    return Media.Icon(addonName, name)
end

--- The path of one shipped face, or nil when the library is absent.
function NS.MediaFont(name)
    if not Media then return nil end
    return Media.Font(addonName, name)
end

-- At FILE LOAD, not PLAYER_LOGIN: LibSharedMedia is vendored under libs/ and has already run.
-- Every call passes the FOLDER name: the library is vendored and cannot know where it was copied.
if Media then Media.RegisterLSM(addonName) end
