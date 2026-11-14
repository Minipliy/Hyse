/// <reference path="../pb_data/types.d.ts" />

onRecordBeforeCreateRequest((e) => {
    const account = e.httpContext.get("authRecord")
    if (!account) throw new UnauthorizedError("Authentication required.")
    e.record.set("owner", account.id)
}, "recipe_shares")

onRecordBeforeUpdateRequest((e) => {
    const account = e.httpContext.get("authRecord")
    if (!account || String(e.record.get("owner") || "") !== account.id) throw new ForbiddenError("Not your recipe link.")
    e.record.set("owner", account.id)
}, "recipe_shares")
