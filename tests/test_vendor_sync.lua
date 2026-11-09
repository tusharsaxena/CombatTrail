-- tests/test_vendor_sync.lua — the vendored-payload gate (testing-§11): libs/LibKa0s/ and tests/_kit/
-- are exactly what LibKa0s published at the tag root CLAUDE.md names, icons pruned to its declaration.
-- DELEGATES to the kit's own gate; never a reimplementation of the comparison.

local T = _G.CT_TEST
local VendorSync = dofile((T.root or ".") .. "/tests/_kit/vendor_sync.lua")
VendorSync.register(T, { root = T.root })
