/// <reference path="../pb_data/types.d.ts" />

// Compatibility endpoint for obsolete clients. It deliberately performs no
// write so normal app users can never create a global catalogue row directly.
routerAdd("POST", "/api/hyse/global-foods/resolve", (_c) => {
    throw new BadRequestError("Direct global food creation is disabled. Update Hyse and submit the personal food for moderation.")
}, $apis.requireRecordAuth("users"))
