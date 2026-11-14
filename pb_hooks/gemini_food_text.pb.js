/// <reference path="../pb_data/types.d.ts" />

// Suspended until the API provider terms, age access and EEA paid-service
// requirements have been resolved. Keep this server-side fail-closed even
// when an older app version calls the endpoint.
routerAdd("POST", "/api/hyse/ai/food-text", () => {
    throw new ApiError(503, "Remote food analysis is unavailable.")
})
