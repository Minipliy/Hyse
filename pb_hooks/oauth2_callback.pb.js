/// <reference path="../pb_data/types.d.ts" />

// PocketBase 0.22 executes registered route callbacks in isolated JavaScript
// contexts. Keep both callbacks self-contained; a shared module-level helper
// makes the route fail at runtime even though the hook loads successfully.
routerAdd("GET", "/api/hyse/oauth2-callback", (c) => {
    const values = {
        code: c.queryParam("code"),
        state: c.queryParam("state"),
        error: c.queryParam("error"),
        error_description: c.queryParam("error_description")
    }
    const allowedParameters = ["code", "state", "error", "error_description"]
    const targetParameters = []
    for (const name of allowedParameters) {
        const value = String(values[name] || "")
        if (value) targetParameters.push(encodeURIComponent(name) + "=" + encodeURIComponent(value))
    }
    return c.redirect(302, "hyseapp://oauth-callback" +
        (targetParameters.length > 0 ? "?" + targetParameters.join("&") : ""))
})

// Sign in with Apple requires response_mode=form_post whenever name or email
// is requested. PocketBase normalizes URL-encoded form fields into data here.
routerAdd("POST", "/api/hyse/oauth2-callback", (c) => {
    const data = $apis.requestInfo(c).data || {}
    // requestInfo handles Apple's application/x-www-form-urlencoded response.
    // Keep a direct form-value fallback for PocketBase/Echo versions that don't
    // expose those fields through info.data.
    const formValue = (name) => {
        if (data[name]) return data[name]
        try { return c.request().formValue(name) } catch (_) { return "" }
    }
    const values = {
        code: formValue("code"),
        state: formValue("state"),
        error: formValue("error"),
        error_description: formValue("error_description")
    }
    const allowedParameters = ["code", "state", "error", "error_description"]
    const targetParameters = []
    for (const name of allowedParameters) {
        const value = String(values[name] || "")
        if (value) targetParameters.push(encodeURIComponent(name) + "=" + encodeURIComponent(value))
    }
    return c.redirect(302, "hyseapp://oauth-callback" +
        (targetParameters.length > 0 ? "?" + targetParameters.join("&") : ""))
})
