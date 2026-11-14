/// <reference path="../pb_data/types.d.ts" />

// The API rules already restrict every operation to the authenticated owner.
// These hooks additionally make the server authoritative for the relation, so
// a manipulated client payload can never assign a record to another account.
onRecordBeforeCreateRequest((e) => {
    const account = e.httpContext.get("authRecord")
    if (!account) throw new UnauthorizedError("Authentication required.")
    e.record.set("user", account.id)
}, "user_foods")

onRecordBeforeUpdateRequest((e) => {
    const account = e.httpContext.get("authRecord")
    if (!account) throw new UnauthorizedError("Authentication required.")
    if (String(e.record.get("user") || "") !== account.id) {
        throw new ForbiddenError("You can only update your own records.")
    }
    e.record.set("user", account.id)
}, "user_foods")
