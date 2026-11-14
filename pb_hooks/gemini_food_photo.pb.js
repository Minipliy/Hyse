/// <reference path="../pb_data/types.d.ts" />

// Older app versions may still call this endpoint. Never forward photos.
routerAdd("POST", "/api/hyse/ai/food-photo", () => {
    throw new ApiError(503, "Remote food analysis is unavailable.")
})
